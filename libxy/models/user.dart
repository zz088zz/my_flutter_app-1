class User {
  final String? id;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? password;
  final String? createdAt;

  User({
    this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.password,
    this.createdAt,
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
          createdAtString =
              DateTime.fromMillisecondsSinceEpoch(
                timestamp.millisecondsSinceEpoch,
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
    };
  }

  // For Firestore operations - excludes id field for new documents
  Map<String, dynamic> toFirestoreMap() {
    return {
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'password': password,
      'created_at': createdAt,
    };
  }

  String get fullName => '$firstName $lastName';
}
