import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _txCollection(String uid) {
    return _db.collection('users').doc(uid).collection('transactions');
  }

  Future<void> addTransaction(String uid, TransactionModel tx) {
    return _txCollection(uid).add(tx.toFirestore());
  }

  Future<void> updateTransaction(String uid, String txId, Map<String, dynamic> data) {
    return _txCollection(uid).doc(txId).update(data);
  }

  Future<void> deleteTransaction(String uid, String txId) {
    return _txCollection(uid).doc(txId).delete();
  }

  Stream<List<TransactionModel>> getTransactionsStream(
    String uid, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    Query query = _txCollection(uid).orderBy('date', descending: true);

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    return query.snapshots().map((snap) {
      return snap.docs.map((doc) => TransactionModel.fromFirestore(doc)).toList();
    });
  }

  Future<List<TransactionModel>> getTransactions(
    String uid, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query query = _txCollection(uid).orderBy('date', descending: true);

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    final snap = await query.get();
    return snap.docs.map((doc) => TransactionModel.fromFirestore(doc)).toList();
  }
}
