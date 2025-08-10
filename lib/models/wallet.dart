class Wallet {
  final String? id;
  final String userId;
  final double balance;

  Wallet({
    this.id,
    required this.userId,
    required this.balance,
  });

  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      balance: map['balance'] is int ? (map['balance'] as int).toDouble() : map['balance'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'balance': balance,
    };
  }
} 