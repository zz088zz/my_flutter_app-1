class Charger {
  String? id;
  String stationId;
  String name;
  String type; // AC or DC
  double power; // in kW
  double pricePerKWh;
  bool isAvailable;

  Charger({
    this.id,
    required this.stationId,
    required this.name,
    required this.type,
    required this.power,
    required this.pricePerKWh,
    this.isAvailable = true,
  });

  // Convenience constructor for AC chargers
  factory Charger.ac({
    String? id,
    required String stationId,
    required String name,
    double power = 11.0,
    double pricePerKWh = 0.80, // Default price per kWh for AC
    bool isAvailable = true,
  }) {
    return Charger(
      id: id,
      stationId: stationId,
      name: name,
      type: 'AC',
      power: power,
      pricePerKWh: pricePerKWh,
      isAvailable: isAvailable,
    );
  }

  // Convenience constructor for DC chargers
  factory Charger.dc({
    String? id,
    required String stationId,
    required String name,
    double power = 50.0,
    double pricePerKWh = 1.30, // Default price per kWh for DC
    bool isAvailable = true,
  }) {
    return Charger(
      id: id,
      stationId: stationId,
      name: name,
      type: 'DC',
      power: power,
      pricePerKWh: pricePerKWh,
      isAvailable: isAvailable,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'station_id': stationId,
      'name': name,
      'type': type,
      'power': power,
      'price_per_kwh': pricePerKWh,
      'is_available': isAvailable ? 1 : 0,
    };
  }

  // Method for Firestore operations (excludes id)
  Map<String, dynamic> toFirestoreMap() {
    return toMap(); // Same as toMap since id is already excluded
  }

  factory Charger.fromMap(Map<String, dynamic> map) {
    return Charger(
      id: map['id']?.toString(),
      stationId: map['station_id']?.toString() ?? '',
      name: map['name'],
      type: map['type'],
      power: map['power'] is String ? double.parse(map['power']) : map['power'],
      pricePerKWh:
          map['price_per_kwh'] is String
              ? double.parse(map['price_per_kwh'])
              : (map['price_per_kwh'] ?? (map['type'] == 'AC' ? 0.80 : 1.30)),
      isAvailable: map['is_available'] == 1 || map['is_available'] == true,
    );
  }

  Charger copyWith({
    String? id,
    String? stationId,
    String? name,
    String? type,
    double? power,
    double? pricePerKWh,
    bool? isAvailable,
  }) {
    return Charger(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      name: name ?? this.name,
      type: type ?? this.type,
      power: power ?? this.power,
      pricePerKWh: pricePerKWh ?? this.pricePerKWh,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }
}
