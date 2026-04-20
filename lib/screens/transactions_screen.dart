import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _firestore = FirestoreService();
  String _filter = 'all';
  String _sourceFilter = 'all';
  String _typeFilter = 'all';
  late Stream<List<TransactionModel>> _transactionsStream;
  List<TransactionModel> _lastTransactions = const [];

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _transactionsStream = _firestore.getTransactionsStream(uid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final currencyFormat = NumberFormat.currency(locale: 'en_GB', symbol: '£');

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildChip('All', 'all', _sourceFilter, (v) => setState(() => _sourceFilter = v)),
                _buildChip('Cash', 'cash', _sourceFilter, (v) => setState(() => _sourceFilter = v)),
                _buildChip('Monzo', 'monzo', _sourceFilter, (v) => setState(() => _sourceFilter = v)),
                _buildChip('Lloyds', 'truelayer_lloyds', _sourceFilter, (v) => setState(() => _sourceFilter = v)),
              ],
            ),
          ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildChip('All Types', 'all', _typeFilter, (v) => setState(() => _typeFilter = v)),
                _buildChip('Income', 'income', _typeFilter, (v) => setState(() => _typeFilter = v)),
                _buildChip('Expenses', 'expense', _typeFilter, (v) => setState(() => _typeFilter = v)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Category filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildChip('All Categories', 'all', _filter, (v) => setState(() => _filter = v)),
                ...defaultCategories.map((c) =>
                  _buildChip(c.name, c.id, _filter, (v) => setState(() => _filter = v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Transaction list
          Expanded(
            child: StreamBuilder<List<TransactionModel>>(
              stream: _transactionsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError && _lastTransactions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 46, color: AppColors.danger),
                          const SizedBox(height: 12),
                          const Text(
                            'Could not load transactions',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData &&
                    _lastTransactions.isEmpty) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }

                var transactions = snapshot.data ?? _lastTransactions;
                if (snapshot.hasData) {
                  _lastTransactions = snapshot.data!;
                }

                if (_sourceFilter != 'all') {
                  transactions = transactions.where((t) => t.source == _sourceFilter).toList();
                }
                if (_typeFilter == 'income') {
                  transactions = transactions.where((t) => t.isIncome).toList();
                } else if (_typeFilter == 'expense') {
                  transactions = transactions.where((t) => t.isExpense).toList();
                }
                if (_filter != 'all') {
                  transactions = transactions.where((t) => t.category == _filter).toList();
                }

                if (transactions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No transactions found', style: TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 6),
                        const Text(
                          'Try clearing filters or check your connection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                final grouped = _groupByDate(transactions);
                final widgets = <Widget>[];
                for (final entry in grouped.entries) {
                  widgets.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  );
                  widgets.addAll(entry.value.map((tx) => _buildTxItem(tx, uid, currencyFormat)));
                }
                final filtered = transactions;
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: widgets,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${filtered.length} transaction${filtered.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                          Text(
                            currencyFormat.format(filtered.fold<double>(0, (s, t) => s + t.amount)),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: filtered.fold<double>(0, (s, t) => s + t.amount) >= 0
                                  ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<TransactionModel>> _groupByDate(List<TransactionModel> txs) {
    final map = <String, List<TransactionModel>>{};
    for (final t in txs) {
      final key = DateFormat('d MMMM yyyy').format(t.date);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Widget _buildTxItem(TransactionModel tx, String uid, NumberFormat currencyFormat) {
    final cat = getCategoryById(tx.category);
    return Dismissible(
      key: Key(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            SizedBox(width: 8),
            Icon(Icons.delete, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Delete Transaction'),
            content: Text('Delete "${tx.description}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _firestore.deleteTransaction(uid, tx.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cat.icon, color: cat.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.description, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        DateFormat('d MMM yyyy').format(tx.date),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      _sourceTag(tx.source),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${tx.amount < 0 ? '-' : '+'}${currencyFormat.format(tx.absAmount)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: tx.amount < 0 ? AppColors.danger : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, String value, String current, ValueChanged<String> onSelected) {
    final selected = current == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textMuted)),
        selected: selected,
        onSelected: (_) => onSelected(value),
        backgroundColor: AppColors.surfaceLight,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _sourceTag(String source) {
    final config = {
      'monzo': ('Monzo', AppColors.monzo),
      'truelayer_lloyds': ('Lloyds', AppColors.lloyds),
      'cash': ('Cash', AppColors.cash),
    };
    final (label, color) = config[source] ?? ('Other', AppColors.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
