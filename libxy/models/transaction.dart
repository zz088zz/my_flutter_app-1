import 'package:cloud_firestore/cloud_firestore.dart';

class Transaction {
  final String? id;
  final String userId;
  final double amount;
  final String description;
  final String transactionType; // 'credit' or 'debit'
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.userId,
    required this.amount,
    required this.description,
    required this.transactionType,
    required this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    if (map['created_at'] is Timestamp) {
      createdAt = (map['created_at'] as Timestamp).toDate();
    } else if (map['created_at'] is String) {
      createdAt = DateTime.parse(map['created_at']);
    } else {
      createdAt = DateTime.now();
      print('Warning: Invalid created_at format in transaction data');
    }

    // Ensure amount is always a double
    double amount;
    final rawAmount = map['amount'];
    if (rawAmount is int) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is double) {
      amount = rawAmount;
    } else if (rawAmount is String) {
      amount = double.tryParse(rawAmount) ?? 0.0;
    } else {
      amount = 0.0;
      print('Warning: Invalid amount format in transaction data');
    }

    return Transaction(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      amount: amount,
      description: map['description'] ?? '',
      transactionType: map['transaction_type'] ?? 'debit',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'amount': amount,
      'description': description,
      'transaction_type': transactionType,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }

  bool get isCredit => transactionType == 'credit';
  bool get isDebit => transactionType == 'debit';
}
