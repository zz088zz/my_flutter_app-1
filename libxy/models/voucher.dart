class Voucher {
  final String? id;
  final String userId;
  final String code;
  final double discountAmount;
  final double discountPercentage;
  final String status; // 'active', 'used', 'expired'
  final DateTime createdAt;
  final DateTime? usedAt;
  final DateTime expiryDate;

  Voucher({
    this.id,
    required this.userId,
    required this.code,
    required this.discountAmount,
    this.discountPercentage = 0.0,
    required this.status,
    required this.createdAt,
    this.usedAt,
    required this.expiryDate,
  });

  factory Voucher.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    if (map['created_at'] is String) {
      createdAt = DateTime.parse(map['created_at']);
    } else {
      createdAt = DateTime.now();
    }

    DateTime expiryDate;
    if (map['expiry_date'] is String) {
      expiryDate = DateTime.parse(map['expiry_date']);
    } else {
      expiryDate = DateTime.now().add(const Duration(days: 30));
    }

    DateTime? usedAt;
    if (map['used_at'] is String) {
      usedAt = DateTime.parse(map['used_at']);
    }

    return Voucher(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      code: map['code'] ?? '',
      discountAmount: (map['discount_amount'] ?? 0.0).toDouble(),
      discountPercentage: (map['discount_percentage'] ?? 0.0).toDouble(),
      status: map['status'] ?? 'active',
      createdAt: createdAt,
      usedAt: usedAt,
      expiryDate: expiryDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'code': code,
      'discount_amount': discountAmount,
      'discount_percentage': discountPercentage,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'used_at': usedAt?.toIso8601String(),
      'expiry_date': expiryDate.toIso8601String(),
    };
  }

  Voucher copyWith({
    String? id,
    String? userId,
    String? code,
    double? discountAmount,
    double? discountPercentage,
    String? status,
    DateTime? createdAt,
    DateTime? usedAt,
    DateTime? expiryDate,
  }) {
    return Voucher(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      code: code ?? this.code,
      discountAmount: discountAmount ?? this.discountAmount,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      usedAt: usedAt ?? this.usedAt,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  bool get isActive =>
      status == 'active' && DateTime.now().isBefore(expiryDate);
  bool get isUsed => status == 'used';
  bool get isExpired =>
      status == 'expired' || DateTime.now().isAfter(expiryDate);
}
