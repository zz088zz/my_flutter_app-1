class Vehicle {
  final String? id;
  final String userId;
  final String brand;
  final String model;
  final String plateNumber;
  final bool isDefault;

  Vehicle({
    this.id,
    required this.userId,
    required this.brand,
    required this.model,
    required this.plateNumber,
    this.isDefault = false,
  });

  Vehicle copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? plateNumber,
    bool? isDefault,
  }) {
    return Vehicle(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      plateNumber: plateNumber ?? this.plateNumber,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'],
      userId: map['user_id'] ?? '',
      brand: map['brand'] ?? '',
      model: map['model'] ?? '',
      plateNumber: map['plate_number'] ?? '',
      isDefault: map['is_default'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'brand': brand,
      'model': model,
      'plate_number': plateNumber,
      'is_default': isDefault,
    };
  }

  // For Firestore operations - excludes id field for new documents
  Map<String, dynamic> toFirestoreMap() {
    return {
      'user_id': userId,
      'brand': brand,
      'model': model,
      'plate_number': plateNumber,
      'is_default': isDefault,
    };
  }
}
