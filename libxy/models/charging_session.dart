class ChargingSession {
  final String? id;
  final String userId;
  final String stationId;
  final String vehicleId;
  final String? reservationId;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime? chargerRemovedTime;
  final double? energyConsumed;
  final double? amount;
  final double? fineAmount;
  final String status; // 'in_progress', 'completed', 'charger_removed'
  final int gracePeriodMinutes; // Grace period before fine starts

  ChargingSession({
    this.id,
    required this.userId,
    required this.stationId,
    required this.vehicleId,
    this.reservationId,
    required this.startTime,
    this.endTime,
    this.chargerRemovedTime,
    this.energyConsumed,
    this.amount,
    this.fineAmount,
    this.status = 'in_progress',
    this.gracePeriodMinutes =
        3, // Default 3 minutes grace period (for 50kW fast chargers)
  });

  factory ChargingSession.fromMap(Map<String, dynamic> map) {
    return ChargingSession(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      vehicleId: map['vehicle_id']?.toString() ?? '',
      reservationId: map['reservation_id']?.toString(),
      startTime: DateTime.parse(map['start_time']),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
      chargerRemovedTime:
          map['charger_removed_time'] != null
              ? DateTime.parse(map['charger_removed_time'])
              : null,
      energyConsumed:
          map['energy_consumed'] is String
              ? double.parse(map['energy_consumed'])
              : map['energy_consumed'],
      amount:
          map['amount'] is String ? double.parse(map['amount']) : map['amount'],
      fineAmount:
          map['fine_amount'] is String
              ? double.parse(map['fine_amount'])
              : map['fine_amount'],
      status: map['status'],
      gracePeriodMinutes: map['grace_period_minutes'] ?? 3,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'station_id': stationId,
      'vehicle_id': vehicleId,
      'reservation_id': reservationId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'charger_removed_time': chargerRemovedTime?.toIso8601String(),
      'energy_consumed': energyConsumed,
      'amount': amount,
      'fine_amount': fineAmount,
      'status': status,
      'grace_period_minutes': gracePeriodMinutes,
    };
  }

  // Method for Firestore operations (excludes id)
  Map<String, dynamic> toFirestoreMap() {
    return toMap(); // Same as toMap since id is already excluded
  }

  Duration get duration {
    if (endTime != null) {
      return endTime!.difference(startTime);
    } else {
      return DateTime.now().difference(startTime);
    }
  }

  int get durationInMinutes => duration.inMinutes;

  // Calculate overtime duration after charging completion
  Duration? get overtimeDuration {
    if (endTime != null && chargerRemovedTime != null) {
      return chargerRemovedTime!.difference(endTime!);
    } else if (endTime != null &&
        chargerRemovedTime == null &&
        status == 'completed') {
      // If charging is completed but charger not removed yet
      return DateTime.now().difference(endTime!);
    }
    return null;
  }

  // Check if fine should be applied
  bool get shouldApplyFine {
    final overtime = overtimeDuration;
    if (overtime == null) return false;
    return overtime.inMinutes > gracePeriodMinutes;
  }

  // Calculate fine amount based on overtime duration
  double calculateFine({double fineRatePerMinute = 1.00}) {
    if (!shouldApplyFine) return 0.0;

    final overtime = overtimeDuration!;
    final overtimeMinutes = overtime.inMinutes - gracePeriodMinutes;

    // Fine starts after grace period
    if (overtimeMinutes <= 0) return 0.0;

    return overtimeMinutes * fineRatePerMinute;
  }

  // Get overtime minutes beyond grace period
  int get overtimeMinutesBeyondGrace {
    final overtime = overtimeDuration;
    if (overtime == null) return 0;

    final totalOvertimeMinutes = overtime.inMinutes;
    return totalOvertimeMinutes > gracePeriodMinutes
        ? totalOvertimeMinutes - gracePeriodMinutes
        : 0;
  }

  // Create a copy with updated fields
  ChargingSession copyWith({
    String? id,
    String? userId,
    String? stationId,
    String? vehicleId,
    String? reservationId,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? chargerRemovedTime,
    double? energyConsumed,
    double? amount,
    double? fineAmount,
    String? status,
    int? gracePeriodMinutes,
  }) {
    return ChargingSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      stationId: stationId ?? this.stationId,
      vehicleId: vehicleId ?? this.vehicleId,
      reservationId: reservationId ?? this.reservationId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      chargerRemovedTime: chargerRemovedTime ?? this.chargerRemovedTime,
      energyConsumed: energyConsumed ?? this.energyConsumed,
      amount: amount ?? this.amount,
      fineAmount: fineAmount ?? this.fineAmount,
      status: status ?? this.status,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
    );
  }
}
