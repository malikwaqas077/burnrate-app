import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import '../widgets/spending_chart.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/summary_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();
  String _period = 'month';
  late Stream<List<TransactionModel>> _transactionsStream;
  List<TransactionModel> _lastTransactions = const [];

  DateTimeRange _getRange() {
    final now = DateTime.now();
    switch (_period) {
      case 'week':
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'year':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _transactionsStream = _buildTransactionsStream();
  }

  Stream<List<TransactionModel>> _buildTransactionsStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final range = _getRange();
    return _firestore.getTransactionsStream(
      uid,
      startDate: range.start,
      endDate: range.end,
    );
  }

  void _setPeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _transactionsStream = _buildTransactionsStream();
    });
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BurnRate', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _auth.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<TransactionModel>>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError && _lastTransactions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 42),
                    const SizedBox(height: 10),
                    const Text(
                      'Could not load dashboard data',
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
            return Column(
              children: [
                LinearProgressIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceLight,
                  minHeight: 2,
                ),
                const Spacer(),
              ],
            );
          }

          final transactions = snapshot.data ?? _lastTransactions;
          if (snapshot.hasData) {
            _lastTransactions = snapshot.data!;
          }
          final expenses = transactions.where((t) => t.amount < 0).toList();
          final income = transactions.where((t) => t.amount > 0).toList();
          final totalSpent = expenses.fold<double>(0, (sum, t) => sum + t.absAmount);
          final totalIncome = income.fold<double>(0, (sum, t) => sum + t.amount);
          final netFlow = totalIncome - totalSpent;
          final avgDaily = _period == 'week'
              ? totalSpent / 7
              : _period == 'month'
                  ? totalSpent / DateTime.now().day
                  : totalSpent / (DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays + 1);

          final categoryTotals = <String, double>{};
          for (final t in expenses) {
            categoryTotals[t.category] = (categoryTotals[t.category] ?? 0) + t.absAmount;
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEEE, d MMMM').format(DateTime.now()),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.local_fire_department, color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                ),
                // Period selector
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: ['week', 'month', 'year'].map((p) {
                      final selected = _period == p;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _setPeriod(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              p[0].toUpperCase() + p.substring(1),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selected ? Colors.white : AppColors.textMuted,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // Summary cards
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'Total Spent',
                        amount: totalSpent,
                        subtitle: 'This $_period',
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Income',
                        amount: totalIncome,
                        subtitle: 'This $_period',
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'Net Flow',
                        amount: netFlow,
                        subtitle: netFlow >= 0 ? 'Money in' : 'Money out',
                        color: netFlow >= 0 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Daily Avg',
                        amount: avgDaily,
                        subtitle: 'Spent per day',
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SummaryCard(
                  title: 'Transactions',
                  amount: transactions.length.toDouble(),
                  isCount: true,
                  subtitle: '${transactions.length} total this $_period',
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),

                // Spending chart
                if (expenses.isNotEmpty) ...[
                  const Text('Spending Over Time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: SpendingBarChart(transactions: expenses, period: _period),
                  ),
                  const SizedBox(height: 24),

                  // Category breakdown
                  const Text('By Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: CategoryPieChartWidget(categoryTotals: categoryTotals),
                  ),
                  const SizedBox(height: 12),
                  ...categoryTotals.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value)),
                ].whereType<MapEntry<String, double>>().map((entry) {
                  final cat = getCategoryById(entry.key);
                  final pct = totalSpent > 0 ? (entry.value / totalSpent * 100) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(cat.icon, color: cat.color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cat.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct / 100,
                                  backgroundColor: AppColors.surfaceLight,
                                  color: cat.color,
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          NumberFormat.currency(locale: 'en_GB', symbol: '£').format(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }),

                if (transactions.isEmpty)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border, width: 1.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 64, color: AppColors.textMuted),
                          const SizedBox(height: 16),
                          const Text(
                            'No transactions yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add your first transaction or connect\na bank to get started',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.add),
                            label: const Text('Add Transaction'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
