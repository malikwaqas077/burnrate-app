import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _firestore = FirestoreService();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _type = 'expense';
  String _category = 'other';
  String _source = 'cash';
  DateTime _date = DateTime.now();
  bool _loading = false;

  Future<void> _submit() async {
    if (_descriptionController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final amount = double.tryParse(_amountController.text) ?? 0;
    final signedAmount = _type == 'income' ? amount.abs() : -amount.abs();

    final tx = TransactionModel(
      id: '',
      description: _descriptionController.text.trim(),
      amount: signedAmount,
      category: _category,
      date: _date,
      source: _source,
      createdAt: DateTime.now(),
    );

    try {
      await _firestore.addTransaction(uid, tx);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _type == 'income' ? 'Income added!' : 'Expense added!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        _descriptionController.clear();
        _amountController.clear();
        setState(() {
          _type = 'expense';
          _category = 'other';
          _source = 'cash';
          _date = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_type == 'income' ? 'Add Income' : 'Add Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: _typeButton('Expense', 'expense', AppColors.danger),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _typeButton('Income', 'income', AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Amount (big)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text(
                  'Amount',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '£',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: TextStyle(color: AppColors.surfaceLighter),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              prefixIcon: Icon(
                Icons.description_outlined,
                color: AppColors.textMuted,
              ),
            ),
            style: const TextStyle(color: AppColors.text),
          ),
          const SizedBox(height: 16),

          // Date picker
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppColors.primary,
                        surface: AppColors.surface,
                        onSurface: AppColors.text,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('EEEE, d MMMM yyyy').format(_date),
                    style: const TextStyle(color: AppColors.text),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Source
          const Text(
            'Source',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _sourceButton('Cash', 'cash', Icons.money, AppColors.cash),
              const SizedBox(width: 8),
              _sourceButton(
                'Monzo',
                'monzo',
                Icons.account_balance,
                AppColors.monzo,
              ),
              const SizedBox(width: 8),
              _sourceButton(
                'Lloyds',
                'truelayer_lloyds',
                Icons.account_balance,
                AppColors.lloyds,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category
          const Text(
            'Category',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: defaultCategories
                .where(
                  (cat) => _type == 'income'
                      ? cat.id == 'income' ||
                            cat.id == 'transfer' ||
                            cat.id == 'other'
                      : cat.id != 'income',
                )
                .map((cat) {
                  final selected = _category == cat.id;
                  return GestureDetector(
                    onTap: () => setState(() => _category = cat.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? cat.color.withValues(alpha: 0.2)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? cat.color : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat.icon,
                            size: 16,
                            color: selected ? cat.color : AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? cat.color : AppColors.textMuted,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: 32),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _type == 'income' ? 'Add Income' : 'Add Expense',
                      style: const TextStyle(fontSize: 17),
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sourceButton(String label, String value, IconData icon, Color color) {
    final selected = _source == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _source = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.15)
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : AppColors.border),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? color : AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? color : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeButton(String label, String value, Color color) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() {
        _type = value;
        _category = value == 'income' ? 'income' : 'other';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
