class PaymentMethod {
  final String? id;
  final String userId;
  final String cardType;
  final String cardNumber;
  final String expiryDate;
  final String holderName;
  final bool isDefault;
  final String lastFourDigits;

  PaymentMethod({
    this.id,
    required this.userId,
    required this.cardType,
    required this.cardNumber,
    required this.expiryDate,
    required this.holderName,
    this.isDefault = false,
    required this.lastFourDigits,
  });

  PaymentMethod copyWith({
    String? id,
    String? userId,
    String? cardType,
    String? cardNumber,
    String? expiryDate,
    String? holderName,
    bool? isDefault,
    String? lastFourDigits,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      cardType: cardType ?? this.cardType,
      cardNumber: cardNumber ?? this.cardNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      holderName: holderName ?? this.holderName,
      isDefault: isDefault ?? this.isDefault,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
    );
  }

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'],
      userId: map['user_id'] ?? '',
      cardType: map['card_type'] ?? '',
      cardNumber: map['card_number'] ?? '',
      expiryDate: map['expiry_date'] ?? '',
      holderName: map['holder_name'] ?? '',
      isDefault: map['is_default'] == true,
      lastFourDigits: map['last_four_digits'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'card_type': cardType,
      'card_number': cardNumber,
      'expiry_date': expiryDate,
      'holder_name': holderName,
      'is_default': isDefault,
      'last_four_digits': lastFourDigits,
    };
  }

  // For Firestore operations - excludes id field for new documents
  Map<String, dynamic> toFirestoreMap() {
    return {
      'user_id': userId,
      'card_type': cardType,
      'card_number': cardNumber,
      'expiry_date': expiryDate,
      'holder_name': holderName,
      'is_default': isDefault,
      'last_four_digits': lastFourDigits,
    };
  }

  String get maskedCardNumber {
    if (cardNumber.length < 8) return cardNumber;
    final lastFour = cardNumber.substring(cardNumber.length - 4);
    return '•••• •••• •••• $lastFour';
  }
}
