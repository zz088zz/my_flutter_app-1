import 'package:cloud_firestore/cloud_firestore.dart';

class Transaction {
  final String? id;
  final String userId;
  final double amount;
  final String description;
  final String transactionType; // 'credit' or 'debit'
  final DateTime createdAt;
  final String? transactionSource; // 'wallet', 'payment_method', 'charging_session'
  final String? paymentMethodId; // For payment method transactions
  final String? sessionId; // For charging session transactions
  final double? fineAmount; // Fine amount for overtime
  final int? overtimeMinutes; // Minutes over the scheduled time
  final int? gracePeriodMinutes; // Grace period minutes allowed

  Transaction({
    this.id,
    required this.userId,
    required this.amount,
    required this.description,
    required this.transactionType,
    required this.createdAt,
    this.transactionSource,
    this.paymentMethodId,
    this.sessionId,
    this.fineAmount,
    this.overtimeMinutes,
    this.gracePeriodMinutes,
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
      transactionSource: map['transaction_source'],
      paymentMethodId: map['payment_method_id'],
      sessionId: map['session_id'],
      fineAmount: map['fine_amount'] is num ? (map['fine_amount'] as num).toDouble() : null,
      overtimeMinutes: map['overtime_minutes'] is num ? (map['overtime_minutes'] as num).toInt() : null,
      gracePeriodMinutes: map['grace_period_minutes'] is num ? (map['grace_period_minutes'] as num).toInt() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'amount': amount,
      'description': description,
      'transaction_type': transactionType,
      'created_at': Timestamp.fromDate(createdAt),
      if (transactionSource != null) 'transaction_source': transactionSource,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (sessionId != null) 'session_id': sessionId,
      if (fineAmount != null) 'fine_amount': fineAmount,
      if (overtimeMinutes != null) 'overtime_minutes': overtimeMinutes,
      if (gracePeriodMinutes != null) 'grace_period_minutes': gracePeriodMinutes,
    };
  }

  bool get isCredit => transactionType == 'credit';
  bool get isDebit => transactionType == 'debit';
}