class ChargingSession {
  final String? id;
  final String userId;
  final String stationId;
  final String vehicleId;
  final String? reservationId;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime? chargerRemovedTime; // Time when charger was removed
  final double? energyConsumed;
  final double? amount;
  final double? fineAmount; // Fine amount for overtime
  final String status; // 'in_progress', 'completed', 'charger_removed'

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
  });

  factory ChargingSession.fromMap(Map<String, dynamic> map) {
    return ChargingSession(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      vehicleId: map['vehicle_id']?.toString() ?? '',
      reservationId: map['reservation_id']?.toString(),
      startTime: map['start_time'] is String 
          ? DateTime.parse(map['start_time']) 
          : (map['start_time'] as dynamic)?.toDate(),
      endTime: map['end_time'] != null 
          ? (map['end_time'] is String 
              ? DateTime.parse(map['end_time']) 
              : (map['end_time'] as dynamic)?.toDate()) 
          : null,
      chargerRemovedTime: map['charger_removed_time'] != null 
          ? (map['charger_removed_time'] is String 
              ? DateTime.parse(map['charger_removed_time']) 
              : (map['charger_removed_time'] as dynamic)?.toDate()) 
          : null,
      energyConsumed: map['energy_consumed'] is String ? double.parse(map['energy_consumed']) : map['energy_consumed']?.toDouble(),
      amount: map['amount'] is String ? double.parse(map['amount']) : map['amount']?.toDouble(),
      fineAmount: map['fine_amount'] is String ? double.parse(map['fine_amount']) : map['fine_amount']?.toDouble(),
      status: map['status'] ?? 'in_progress',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }

  Duration get duration {
    if (endTime != null) {
      return endTime!.difference(startTime);
    } else {
      return DateTime.now().difference(startTime);
    }
  }

  int get durationInMinutes => duration.inMinutes;
}