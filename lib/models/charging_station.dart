import 'charger.dart';

class ChargingStation {
  final String? id;
  final String name;
  final String location;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final bool isActive;
  List<Charger> chargers;
  
  // These are computed properties
  int get totalSpots => chargers.length;
  int get availableSpots => chargers.where((c) => c.isAvailable).length;
  String get powerOutput => _getHighestPowerOutput();
  double get pricePerKWh => _getAveragePricePerKWh();
  
  // For backward compatibility, we'll keep these fields
  final String distance;
  final String? waitingTime;

  ChargingStation({
    this.id,
    required this.name,
    this.location = '',
    this.address = '',
    this.city = '',
    required this.latitude,
    required this.longitude,
    this.isActive = true,
    this.chargers = const [],
    this.distance = '0 km',
    this.waitingTime,
  });

  factory ChargingStation.fromMap(Map<String, dynamic> map) {
    return ChargingStation(
      id: map['id']?.toString(),
      name: map['name'],
      location: map['location'],
      address: map['address'] ?? '',
      city: map['city'] ?? '',
      latitude: map['latitude'] is String ? double.parse(map['latitude']) : map['latitude'] ?? 0.0,
      longitude: map['longitude'] is String ? double.parse(map['longitude']) : map['longitude'] ?? 0.0,
      isActive: map['is_active'] == 1 || map['is_active'] == true,
      distance: map['distance'] ?? '0 km',
      waitingTime: map['waiting_time'],
      // Chargers are loaded separately
      chargers: [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'location': location,
      'address': address,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive ? 1 : 0,
      'distance': distance,
      'waiting_time': waitingTime,
      // Chargers are saved separately
    };
  }

  // Helper method to get highest power output among chargers
  String _getHighestPowerOutput() {
    if (chargers.isEmpty) return 'N/A';
    double highestPower = 0;
    for (var charger in chargers) {
      if (charger.power > highestPower) {
        highestPower = charger.power;
      }
    }
    return 'Up to ${highestPower.toStringAsFixed(0)} kW';
  }
  
  // Helper method to get average price per kWh
  double _getAveragePricePerKWh() {
    if (chargers.isEmpty) return 1.20; // Default to 1.20 RM per kWh
    double totalPrice = 0;
    for (var charger in chargers) {
      totalPrice += charger.pricePerKWh;
    }
    return totalPrice / chargers.length;
  }

  bool get isAvailable => availableSpots > 0;
  
  // Get estimated cost based on energy consumption
  double getEstimatedCostByEnergy(double energyKWh, String chargerType) {
    // Find a charger with the requested type
    final charger = chargers.firstWhere(
      (c) => c.type == chargerType && c.isAvailable,
      orElse: () => chargers.first,
    );
    return energyKWh * charger.pricePerKWh;
  }
  
  // Create a copy with updated chargers
  ChargingStation copyWithChargers(List<Charger> updatedChargers) {
    return ChargingStation(
      id: id,
      name: name,
      location: location,
      address: address,
      city: city,
      latitude: latitude,
      longitude: longitude,
      isActive: isActive,
      chargers: updatedChargers,
      distance: distance,
      waitingTime: waitingTime,
    );
  }

  // Add a general copyWith method
  ChargingStation copyWith({
    String? id,
    String? name,
    String? location,
    String? address,
    String? city,
    double? latitude,
    double? longitude,
    bool? isActive,
    List<Charger>? chargers,
    String? distance,
    String? waitingTime,
  }) {
    return ChargingStation(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      address: address ?? this.address,
      city: city ?? this.city,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isActive: isActive ?? this.isActive,
      chargers: chargers ?? this.chargers,
      distance: distance ?? this.distance,
      waitingTime: waitingTime ?? this.waitingTime,
    );
  }
} 