class User {
  final String? id;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? password;
  final String? createdAt;
  final bool isActive; // Add active status
  final String? disabledAt; // Add disabled timestamp

  User({
    this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.password,
    this.createdAt,
    this.isActive = true, // Default to active
    this.disabledAt,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    // Handle created_at field - it could be a Timestamp or String
    String? createdAtString;
    if (map['created_at'] != null) {
      final createdAtValue = map['created_at'];
      if (createdAtValue is String) {
        createdAtString = createdAtValue;
      } else if (createdAtValue.toString().contains('Timestamp')) {
        // It's a Firestore Timestamp, convert to ISO string
        try {
          final timestamp = createdAtValue as dynamic;
          createdAtString = DateTime.fromMillisecondsSinceEpoch(
            timestamp.millisecondsSinceEpoch
          ).toIso8601String();
        } catch (e) {
          print('Error converting timestamp: $e');
          createdAtString = DateTime.now().toIso8601String();
        }
      }
    }
    
    return User(
      id: map['id']?.toString(),
      email: map['email'],
      firstName: map['first_name'],
      lastName: map['last_name'],
      phoneNumber: map['phone_number'],
      password: map['password'],
      createdAt: createdAtString,
      isActive: map['is_active'] ?? true, // Default to true if not set
      disabledAt: map['disabled_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'password': password,
      'created_at': createdAt,
      'is_active': isActive,
      'disabled_at': disabledAt,
    };
  }

  String get fullName => '$firstName $lastName';
  
  // Helper methods for soft delete
  bool get isDisabled => !isActive;
  bool get canLogin => isActive;
  
  User copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? password,
    String? createdAt,
    bool? isActive,
    String? disabledAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      disabledAt: disabledAt ?? this.disabledAt,
    );
  }
} 