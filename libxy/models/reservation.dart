class Reservation {
  final String? id;
  final String userId;
  final String stationId;
  final String vehicleId;
  final String paymentMethodId;
  final DateTime startTime;
  final int duration; // in minutes
  final String status; // 'pending', 'confirmed', 'completed', 'cancelled'
  final double deposit;
  final String? createdAt;
  final String? chargerId; // ID of the selected charger

  Reservation({
    this.id,
    required this.userId,
    required this.stationId,
    required this.vehicleId,
    required this.paymentMethodId,
    required this.startTime,
    required this.duration,
    required this.deposit,
    this.status = 'pending',
    this.createdAt,
    this.chargerId,
  });

  factory Reservation.fromMap(Map<String, dynamic> map) {
    try {
      final startTimeStr = map['start_time'] as String;
      final startTime = DateTime.parse(startTimeStr);

      return Reservation(
        id: map['id']?.toString(),
        userId: map['user_id']?.toString() ?? '',
        stationId: map['station_id']?.toString() ?? '',
        vehicleId: map['vehicle_id']?.toString() ?? '',
        paymentMethodId: map['payment_method_id']?.toString() ?? '',
        startTime: startTime,
        duration:
            map['duration'] is String
                ? int.parse(map['duration'])
                : map['duration'],
        status: map['status'] as String,
        deposit:
            (map['deposit'] is int)
                ? (map['deposit'] as int).toDouble()
                : map['deposit'] as double,
        chargerId: map['charger_id']?.toString(),
      );
    } catch (e) {
      print('Error parsing reservation data: $e');
      print('Map contents: $map');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'station_id': stationId,
      'vehicle_id': vehicleId,
      'payment_method_id': paymentMethodId,
      'start_time': startTime.toIso8601String(),
      'duration': duration,
      'status': status,
      'deposit': deposit,
      if (chargerId != null) 'charger_id': chargerId,
    };
  }

  // Method for Firestore operations (excludes id)
  Map<String, dynamic> toFirestoreMap() {
    return toMap(); // Same as toMap since id is already excluded
  }

  DateTime get endTime => startTime.add(Duration(minutes: duration));

  // Add a copyWith method to create a new instance with modified properties
  Reservation copyWith({
    String? id,
    String? userId,
    String? stationId,
    String? vehicleId,
    String? paymentMethodId,
    DateTime? startTime,
    int? duration,
    String? status,
    double? deposit,
    String? createdAt,
    String? chargerId,
  }) {
    return Reservation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      stationId: stationId ?? this.stationId,
      vehicleId: vehicleId ?? this.vehicleId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      status: status ?? this.status,
      deposit: deposit ?? this.deposit,
      createdAt: createdAt ?? this.createdAt,
      chargerId: chargerId ?? this.chargerId,
    );
  }
}
