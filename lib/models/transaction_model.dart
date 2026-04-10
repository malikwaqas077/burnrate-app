import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final String description;
  final double amount;
  final String category;
  final DateTime date;
  final String source; // 'cash', 'monzo', 'truelayer_lloyds'
  final String? externalId;
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.date,
    required this.source,
    this.externalId,
    required this.createdAt,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      description: data['description'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      category: data['category'] ?? 'other',
      date: (data['date'] as Timestamp).toDate(),
      source: data['source'] ?? 'cash',
      externalId: data['externalId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'description': description,
      'amount': amount,
      'category': category,
      'date': Timestamp.fromDate(date),
      'source': source,
      if (externalId != null) 'externalId': externalId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  bool get isExpense => amount < 0;
  bool get isIncome => amount > 0;
  double get absAmount => amount.abs();
}
