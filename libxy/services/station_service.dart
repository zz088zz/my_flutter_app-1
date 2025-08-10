import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/charging_station.dart';
import '../models/reservation.dart';
import '../models/charging_session.dart';
import '../models/charger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle.dart';
import 'package:geolocator/geolocator.dart';

class StationService with ChangeNotifier {
  List<ChargingStation> _stations = [];
  bool _isLoading = false;
  Map<String, double> _cachedEnergyValues = {};

  StationService();

  List<ChargingStation> get stations => _stations;
  bool get isLoading => _isLoading;

  // Method to calculate and update distances for all stations
  Future<void> updateStationDistances() async {
    try {
      print('Starting distance calculation for ${_stations.length} stations');

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled. Using default distances.');
        _setDefaultDistances();
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied. Using default distances.');
          _setDefaultDistances();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print(
          'Location permissions are permanently denied. Using default distances.',
        );
        _setDefaultDistances();
        return;
      }

      print('Location permissions granted. Getting current position...');

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Location timeout. Using default distances.');
          _setDefaultDistances();
          throw Exception('Location timeout');
        },
      );

      print('Current location: ${position.latitude}, ${position.longitude}');

      // Update distances for all stations
      bool hasValidCoordinates = false;
      for (int i = 0; i < _stations.length; i++) {
        final station = _stations[i];

        // Check if station has valid coordinates
        if (station.latitude == 0.0 && station.longitude == 0.0) {
          print('Station ${station.name} has invalid coordinates (0,0)');
          continue;
        }

        hasValidCoordinates = true;

        // Calculate distance in meters
        double distanceInMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          station.latitude,
          station.longitude,
        );

        // Convert to kilometers and format
        double distanceInKm = distanceInMeters / 1000;
        String formattedDistance;

        if (distanceInKm < 1) {
          formattedDistance = '${(distanceInMeters).round()} m';
        } else {
          formattedDistance = '${distanceInKm.toStringAsFixed(1)} km';
        }

        print(
          'Station ${station.name}: ${formattedDistance} (${station.latitude}, ${station.longitude})',
        );

        // Update the station's distance property
        _stations[i] = station.copyWith(distance: formattedDistance);
      }

      if (!hasValidCoordinates) {
        print('No stations have valid coordinates. Using default distances.');
        _setDefaultDistances();
        return;
      }

      // Sort stations by distance (closest first)
      _stations.sort((a, b) {
        double distanceA = _parseDistance(a.distance);
        double distanceB = _parseDistance(b.distance);
        return distanceA.compareTo(distanceB);
      });

      print('Successfully updated distances for ${_stations.length} stations');
      notifyListeners();
    } catch (e) {
      print('Error updating station distances: $e');
      _setDefaultDistances();
    }
  }

  // Fallback method to set default distances when location is not available
  void _setDefaultDistances() {
    print('Setting default distances for stations');
    for (int i = 0; i < _stations.length; i++) {
      final station = _stations[i];

      // Set default distances based on station names or use incremental distances
      String defaultDistance;
      if (station.name.toLowerCase().contains('parking a')) {
        defaultDistance = '0.1 km';
      } else if (station.name.toLowerCase().contains('parking b')) {
        defaultDistance = '0.3 km';
      } else if (station.name.toLowerCase().contains('parking c')) {
        defaultDistance = '0.5 km';
      } else if (station.name.toLowerCase().contains('parking d')) {
        defaultDistance = '0.7 km';
      } else {
        defaultDistance = '${(i + 1) * 0.2} km';
      }

      _stations[i] = station.copyWith(distance: defaultDistance);
    }
    notifyListeners();
  }

  // Helper method to parse distance string back to double for sorting
  double _parseDistance(String distance) {
    if (distance.contains('km')) {
      return double.tryParse(distance.replaceAll(' km', '')) ?? 999.0;
    } else if (distance.contains('m')) {
      double meters =
          double.tryParse(distance.replaceAll(' m', '')) ?? 999000.0;
      return meters / 1000; // Convert to km for comparison
    }
    return 999.0; // Default high value for unknown distances
  }

  // Add a method to get charger by ID
  Charger? getChargerById(String chargerId) {
    print('Looking for charger with ID: $chargerId');
    for (var station in _stations) {
      for (var charger in station.chargers) {
        if (charger.id == chargerId) {
          print(
            'Found charger in memory: ${charger.name} (${charger.type} ${charger.power}kW)',
          );
          return charger;
        }
      }
    }
    print('Charger with ID $chargerId not found in memory');
    return null;
  }

  // Async version that also checks the database
  Future<Charger?> getChargerByIdAsync(String chargerId) async {
    print('Looking for charger with ID: $chargerId (async)');
    try {
      print('Querying Firestore for charger ID: $chargerId');
      final doc =
          await FirebaseFirestore.instance
              .collection('chargers')
              .doc(chargerId)
              .get();
      if (doc.exists) {
        print('Found charger in Firestore: ${doc.data()}');
        return Charger.fromMap(doc.data()!..['id'] = doc.id);
      }
      print(
        'Charger with ID $chargerId not found in Firestore, checking memory cache',
      );
      return getChargerById(chargerId);
    } catch (e) {
      print('Error getting charger from Firestore: $e');
      return null;
    }
  }

  Future<void> loadStations() async {
    _isLoading = true;
    notifyListeners();
    try {
      final stationQuery =
          await FirebaseFirestore.instance
              .collection('charging_stations')
              .get();
      final List<ChargingStation> newStations = [];
      print('Loading ${stationQuery.docs.length} stations from Firestore');

      for (var stationDoc in stationQuery.docs) {
        final stationId = stationDoc.id;
        final chargerQuery =
            await FirebaseFirestore.instance
                .collection('chargers')
                .where('station_id', isEqualTo: stationId)
                .get();
        print('Station $stationId: Found ${chargerQuery.docs.length} chargers');

        final chargers =
            chargerQuery.docs.map((doc) {
              final chargerData = doc.data();
              chargerData['id'] = doc.id;
              print('Raw charger data: $chargerData');
              final charger = Charger.fromMap(chargerData);
              print(
                '  Charger ${charger.id}: ${charger.name} (${charger.type}) - Available: ${charger.isAvailable} (raw is_available: ${chargerData['is_available']})',
              );
              return charger;
            }).toList();

        final station = ChargingStation.fromMap(
          stationDoc.data()!..['id'] = stationId,
        );
        station.chargers = chargers;

        // Calculate and log availability
        final availableCount = chargers.where((c) => c.isAvailable).length;
        print(
          'Station ${station.name}: ${availableCount}/${chargers.length} chargers available',
        );

        newStations.add(station);
      }
      _stations = newStations;
      print('Loaded ${_stations.length} stations from Firestore');

      // Always update distances after loading stations
      await updateStationDistances();
    } catch (e) {
      print('Error loading stations from Firestore: $e');
      print('Stack trace: ${StackTrace.current}');
      _stations = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> resetAndLoadStations() async {
    _isLoading = true;
    notifyListeners();
    try {
      await loadStations();
    } catch (e) {
      print('Error resetting and loading stations: $e');
      _stations = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  List<ChargingStation> getAvailableStations() {
    final availableStations =
        _stations.where((station) {
          final availableSpots = station.availableSpots;
          print(
            'Station ${station.name}: availableSpots = $availableSpots (${station.chargers.where((c) => c.isAvailable).length}/${station.chargers.length} chargers available)',
          );
          return availableSpots > 0;
        }).toList();

    print(
      'getAvailableStations: Found ${availableStations.length}/${_stations.length} available stations',
    );
    return availableStations;
  }

  Future<ChargingStation?> getStationById(String id) async {
    final stationData =
        await FirebaseFirestore.instance
            .collection('charging_stations')
            .doc(id)
            .get();
    if (!stationData.exists) return null;
    return ChargingStation.fromMap(
      stationData.data()!..['id'] = stationData.id,
    );
  }

  Future<bool> updateStationAvailability(String id, int availableSpots) async {
    try {
      final stationRef = FirebaseFirestore.instance
          .collection('charging_stations')
          .doc(id);
      await stationRef.update({'available_spots': availableSpots});

      // Update the local list
      final index = _stations.indexWhere((station) => station.id == id);
      if (index >= 0) {
        // Get existing chargers
        List<Charger> existingChargers = _stations[index].chargers;

        // Update the availability of chargers
        // We'll mark the first 'availableSpots' chargers as available,
        // and the rest as unavailable
        List<Charger> updatedChargers = [];
        for (int i = 0; i < existingChargers.length; i++) {
          Charger charger = existingChargers[i];

          // Create a copy of the charger with updated availability
          updatedChargers.add(
            Charger(
              id: charger.id,
              stationId: charger.stationId,
              name: charger.name,
              type: charger.type,
              power: charger.power,
              pricePerKWh: charger.pricePerKWh,
              isAvailable:
                  i < availableSpots, // First 'availableSpots' are available
            ),
          );

          // Update charger in database
          await FirebaseFirestore.instance
              .collection('chargers')
              .doc(charger.id)
              .update({'is_available': i < availableSpots ? 1 : 0});
        }

        // Create a copy of the station with updated chargers
        final updated = ChargingStation(
          id: _stations[index].id,
          name: _stations[index].name,
          location: _stations[index].location,
          address: _stations[index].address,
          city: _stations[index].city,
          latitude: _stations[index].latitude,
          longitude: _stations[index].longitude,
          isActive: _stations[index].isActive,
          chargers: updatedChargers,
          distance: _stations[index].distance,
          waitingTime: _stations[index].waitingTime,
        );

        _stations[index] = updated;
        notifyListeners();
      }

      return true;
    } catch (e) {
      print('Error updating station availability: $e');
      return false;
    }
  }

  Future<Reservation?> createReservation(Reservation reservation) async {
    try {
      print(
        'Creating reservation for user ${reservation.userId} at station ${reservation.stationId}',
      );
      print('Reservation details: ${reservation.toMap()}');

      final reservationMap = {
        ...reservation.toMap(),
        'created_at': DateTime.now().toIso8601String(),
        // Explicitly set the status to ensure it's properly set
        'status': 'confirmed',
      };

      // Debug the actual data being saved to database
      print('Saving to database: $reservationMap');

      // Try direct database insertion first (more reliable)
      String id;
      try {
        final docRef = await FirebaseFirestore.instance
            .collection('reservations')
            .add(reservationMap);
        id = docRef.id;
        print('Direct DB insert: Reservation created with ID: $id');
      } catch (e) {
        print('Direct DB insert failed: $e, falling back to helper method');
        // The original code had a DatabaseHelper.insertReservation, which is removed.
        // This part of the logic needs to be re-evaluated or removed if DatabaseHelper is gone.
        // For now, we'll just print an error and return null.
        print(
          'ERROR: DatabaseHelper.insertReservation is no longer available. Cannot create reservation.',
        );
        return null;
      }

      print('Reservation created with ID: $id');

      if (id.isEmpty) {
        print('ERROR: Failed to create reservation - invalid ID returned: $id');
        return null;
      }

      // Double check reservation was actually created
      final savedReservation =
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(id)
              .get();
      if (!savedReservation.exists) {
        print(
          'ERROR: Failed to retrieve newly created reservation with ID $id',
        );
        // Try inserting again if the first attempt didn't work
        print('Attempting to retry reservation creation...');
        final retryId = await FirebaseFirestore.instance
            .collection('reservations')
            .add(reservationMap);
        print('Retry result: ID=${retryId.id}');

        // Check if retry worked
        final retryCheck =
            await FirebaseFirestore.instance
                .collection('reservations')
                .doc(retryId.id)
                .get();
        if (!retryCheck.exists) {
          print('CRITICAL ERROR: Retry also failed to create reservation');

          // FALLBACK: Last attempt with hardcoded values
          final emergencyId = '9999';
          try {
            // Create a reservation with fixed ID as last resort
            await FirebaseFirestore.instance
                .collection('reservations')
                .doc(emergencyId)
                .set({
                  'id': emergencyId,
                  'user_id': reservation.userId,
                  'station_id': reservation.stationId,
                  'vehicle_id': reservation.vehicleId,
                  'payment_method_id': reservation.paymentMethodId,
                  'start_time': reservation.startTime.toIso8601String(),
                  'duration': reservation.duration,
                  'status': 'confirmed',
                  'deposit': reservation.deposit,
                  'created_at': DateTime.now().toIso8601String(),
                  'charger_id': reservation.chargerId,
                });

            print(
              'EMERGENCY: Created fallback reservation with ID $emergencyId',
            );
            id = emergencyId;
          } catch (e) {
            print('CRITICAL: Even emergency reservation creation failed: $e');
            return null;
          }
        } else {
          print('Retry successful, reservation created on second attempt');
          id = retryId.id;
        }
      } else {
        print('Successfully verified reservation ID $id exists in database');
        print('Saved data: ${savedReservation.data()}');
      }

      // Update the availability of the specific charger that was selected
      if (reservation.chargerId != null) {
        print('Setting charger ${reservation.chargerId} to unavailable');
        await updateChargerAvailability(
          reservation.stationId,
          reservation.chargerId!,
          false,
        );
      } else {
        // If no specific charger was selected (legacy code path), update general availability
        final stationIndex = _stations.indexWhere(
          (s) => s.id == reservation.stationId,
        );
        if (stationIndex >= 0) {
          final station = _stations[stationIndex];
          print(
            'Updating station ${station.id} availability from ${station.availableSpots} to ${station.availableSpots - 1}',
          );
          await updateStationAvailability(
            station.id!,
            station.availableSpots - 1,
          );
        } else {
          print(
            'Warning: Station ${reservation.stationId} not found in local stations list',
          );
        }
      }

      // Force refresh our stations list to reflect the new reservation
      await refreshChargerAvailabilityData();
      await loadStations();

      // Return the created reservation with its ID
      return Reservation(
        id: id,
        userId: reservation.userId,
        stationId: reservation.stationId,
        vehicleId: reservation.vehicleId,
        paymentMethodId: reservation.paymentMethodId,
        startTime: reservation.startTime,
        duration: reservation.duration,
        deposit: reservation.deposit,
        status: 'confirmed', // Explicitly set status to confirmed
        chargerId: reservation.chargerId,
      );
    } catch (e) {
      print('Error creating reservation: $e');
      return null;
    }
  }

  Future<bool> cancelReservation(String reservationId) async {
    try {
      print('Cancelling reservation with ID: $reservationId');

      // First, get the reservation details to obtain the charger ID
      final reservationData =
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(reservationId)
              .get();

      if (!reservationData.exists) {
        print('Reservation with ID $reservationId not found');
        return false;
      }

      // Update the reservation status to cancelled
      await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .update({'status': 'cancelled'});

      // Verify the update was successful
      final updatedReservation =
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(reservationId)
              .get();
      if (updatedReservation.data()?['status'] != 'cancelled') {
        print('Failed to update reservation status to cancelled');

        // Try direct database update as a fallback
        await FirebaseFirestore.instance
            .collection('reservations')
            .doc(reservationId)
            .update({'status': 'cancelled'});
      }

      // If this reservation had a specific charger, mark it as available again
      final chargerId = reservationData.data()?['charger_id'];
      if (chargerId != null) {
        final stationId = reservationData.data()?['station_id'];
        print(
          'Setting charger $chargerId at station $stationId to available after cancellation',
        );
        await updateChargerAvailability(stationId, chargerId, true);
      }

      // Reload stations to refresh availability
      await loadStations();

      return true;
    } catch (e) {
      print('Error cancelling reservation: $e');
      return false;
    }
  }

  Future<bool> completeReservation(String reservationId) async {
    try {
      print('Completing reservation with ID: $reservationId');
      final reservationData =
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(reservationId)
              .get();

      if (!reservationData.exists) {
        print('Reservation with ID $reservationId not found');
        return false;
      }

      // Update the reservation status to completed
      await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .update({'status': 'completed'});

      // Verify the update was successful
      final updatedReservation =
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(reservationId)
              .get();
      if (updatedReservation.data()?['status'] != 'completed') {
        print('Failed to update reservation status to completed');

        // Try direct database update as a fallback
        await FirebaseFirestore.instance
            .collection('reservations')
            .doc(reservationId)
            .update({'status': 'completed'});
      }

      // If this reservation had a specific charger, mark it as available again
      final chargerId = reservationData.data()?['charger_id'];
      if (chargerId != null) {
        final stationId = reservationData.data()?['station_id'];
        await updateChargerAvailability(stationId, chargerId, true);
      }

      // Reload stations to refresh availability
      await loadStations();

      return true;
    } catch (e) {
      print('Error completing reservation: $e');
      return false;
    }
  }

  Future<ChargingSession?> startChargingSession(ChargingSession session) async {
    try {
      final idRef = await FirebaseFirestore.instance
          .collection('charging_sessions')
          .add(session.toMap());
      final id = idRef.id;

      // Update station availability if not from reservation
      if (session.reservationId == null) {
        final stationIndex = _stations.indexWhere(
          (s) => s.id == session.stationId,
        );
        if (stationIndex >= 0) {
          final station = _stations[stationIndex];
          await updateStationAvailability(
            station.id!,
            station.availableSpots - 1,
          );
        }
      }

      return ChargingSession(
        id: id,
        userId: session.userId,
        stationId: session.stationId,
        vehicleId: session.vehicleId,
        reservationId: session.reservationId,
        startTime: session.startTime,
        status: 'in_progress',
      );
    } catch (e) {
      return null;
    }
  }

  Future<bool> completeChargingSession(
    int sessionId,
    double energyConsumed,
    double amount,
  ) async {
    try {
      print('Completing charging session with ID: $sessionId');
      final now = DateTime.now();

      // First, get the charging session details to find associated reservation
      final sessionRef = FirebaseFirestore.instance
          .collection('charging_sessions')
          .doc(sessionId.toString());
      final sessionData = await sessionRef.get();

      if (!sessionData.exists) {
        print('Charging session with ID $sessionId not found');
        return false;
      }

      final String? reservationId =
          sessionData.data()?['reservation_id'] as String?;
      final String stationId = sessionData.data()?['station_id'] as String;

      // Complete the charging session
      await sessionRef.update({
        'end_time': now.toIso8601String(),
        'energy_consumed': energyConsumed,
        'amount': amount,
      });

      // If this session was associated with a reservation, complete it and update charger
      if (reservationId != null) {
        print('Completing associated reservation ID: $reservationId');
        await completeReservation(reservationId);
      } else {
        // If no reservation was involved, we need to find and update the charger directly
        print('No reservation associated, trying to find used charger');

        // Try to determine which charger was used by checking active chargers at the time
        // This is a best-effort approach as we don't directly track which charger in a charging session
        final station = _stations.firstWhere(
          (s) => s.id == stationId,
          orElse:
              () => ChargingStation(
                id: '0',
                name: '',
                chargers: [],
                latitude: 0.0,
                longitude: 0.0,
              ),
        );

        if (station.id != '0') {
          // Find any chargers marked as unavailable and update them
          for (var charger in station.chargers) {
            if (!charger.isAvailable && charger.id != null) {
              print(
                'Making charger ${charger.id} available after charging completion',
              );
              await updateChargerAvailability(stationId, charger.id!, true);
            }
          }
        }
      }

      // Reload stations to refresh availability
      await loadStations();

      return true;
    } catch (e) {
      print('Error completing charging session: $e');
      return false;
    }
  }

  // Method to update a specific charger's availability
  Future<bool> updateChargerAvailability(
    String stationId,
    String chargerId,
    bool isAvailable,
  ) async {
    try {
      // Find the station in our local list
      final stationIndex = _stations.indexWhere(
        (station) => station.id == stationId,
      );
      if (stationIndex < 0) {
        print('Station with ID $stationId not found');
        return false;
      }

      // Get the station and its chargers
      final station = _stations[stationIndex];
      final chargerIndex = station.chargers.indexWhere(
        (charger) => charger.id == chargerId,
      );

      if (chargerIndex < 0) {
        print('Charger with ID $chargerId not found in station $stationId');
        return false;
      }

      // Create a new list of chargers with the updated availability
      List<Charger> updatedChargers = List<Charger>.from(station.chargers);
      Charger oldCharger = updatedChargers[chargerIndex];

      // Replace the charger with an updated version
      updatedChargers[chargerIndex] = Charger(
        id: oldCharger.id,
        stationId: oldCharger.stationId,
        name: oldCharger.name,
        type: oldCharger.type,
        power: oldCharger.power,
        pricePerKWh: oldCharger.pricePerKWh,
        isAvailable: isAvailable,
      );

      // Update the charger in the database
      await FirebaseFirestore.instance
          .collection('chargers')
          .doc(chargerId.toString())
          .update({'is_available': isAvailable ? 1 : 0});

      // Update the station in our local list with the new chargers
      final updatedStation = ChargingStation(
        id: station.id,
        name: station.name,
        location: station.location,
        address: station.address,
        city: station.city,
        latitude: station.latitude,
        longitude: station.longitude,
        isActive: station.isActive,
        chargers: updatedChargers,
        distance: station.distance,
        waitingTime: station.waitingTime,
      );

      _stations[stationIndex] = updatedStation;

      // Also update the overall availability count of the station
      int availableChargers =
          updatedChargers.where((c) => c.isAvailable).length;
      await FirebaseFirestore.instance
          .collection('charging_stations')
          .doc(stationId.toString())
          .update({'available_spots': availableChargers});

      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating charger availability: $e');
      return false;
    }
  }

  // Method to check if a charger is available for the specified time period
  Future<bool> isChargerAvailableForTimeSlot(
    String chargerId,
    DateTime startTime,
    int durationMinutes,
  ) async {
    try {
      print('\n----- CHECKING AVAILABILITY FOR CHARGER $chargerId -----');
      print(
        'Requested time: ${startTime.toIso8601String()} for $durationMinutes minutes',
      );

      // First, check if the charger exists in the database
      final chargerDoc =
          await FirebaseFirestore.instance
              .collection('chargers')
              .doc(chargerId)
              .get();

      if (!chargerDoc.exists) {
        print('Charger $chargerId does not exist in database');
        print('----- END CHECK (NOT AVAILABLE) -----\n');
        return false;
      }

      final chargerData = chargerDoc.data()!;
      final isChargerAvailable =
          chargerData['is_available'] == 1 ||
          chargerData['is_available'] == true;

      // Only check the is_available status if the requested time is in the near future (within 1 hour)
      // This allows booking future time slots even if the charger is currently occupied
      final now = DateTime.now();
      final isNearFuture = startTime.difference(now).inHours < 1;

      if (!isChargerAvailable && isNearFuture) {
        print(
          'Charger $chargerId is marked as unavailable in database and requested time is near future (is_available: ${chargerData['is_available']})',
        );
        print('----- END CHECK (NOT AVAILABLE) -----\n');
        return false;
      }

      print(
        'Charger $chargerId exists in database, checking for reservation conflicts...',
      );

      // Get all reservations for this charger regardless of status
      final reservations =
          await FirebaseFirestore.instance
              .collection('reservations')
              .where('charger_id', isEqualTo: chargerId)
              .get();
      print(
        'Found ${reservations.docs.length} total reservations for this charger',
      );

      // Calculate the end time for our requested slot
      final endTime = startTime.add(Duration(minutes: durationMinutes));

      // Count active reservations that might conflict
      int activeReservations = 0;

      // Check each reservation for overlap
      for (var reservationDoc in reservations.docs) {
        final String status =
            reservationDoc.data()?['status'] as String? ?? 'unknown';

        // Skip completed or cancelled reservations
        if (status == 'completed' || status == 'cancelled') {
          print('Skipping ${status} reservation ID: ${reservationDoc.id}');
          continue;
        }

        // Only 'confirmed' reservations are considered active and can conflict
        if (status != 'confirmed') {
          print(
            'Skipping reservation with status "$status" (ID: ${reservationDoc.id})',
          );
          continue;
        }

        activeReservations++;

        // Parse the reservation start time
        final reservationStart = DateTime.parse(
          reservationDoc.data()?['start_time'] as String,
        );

        // Calculate reservation end time
        final reservationEnd = reservationStart.add(
          Duration(minutes: reservationDoc.data()?['duration'] as int),
        );

        print(
          'Checking against confirmed reservation ID: ${reservationDoc.id}',
        );
        print(
          'Reservation time: ${reservationStart.toIso8601String()} to ${reservationEnd.toIso8601String()}',
        );

        // Check for overlap - considering complete date and time
        // Two time periods overlap if the start of one is before the end of the other,
        // and the end of one is after the start of the other
        if (startTime.isBefore(reservationEnd) &&
            endTime.isAfter(reservationStart)) {
          print('CONFLICT DETECTED: Charger $chargerId is NOT available');
          print('Conflict with reservation ID: ${reservationDoc.id}');
          print(
            'Requested: ${startTime.toIso8601String()} to ${endTime.toIso8601String()}',
          );
          print(
            'Existing: ${reservationStart.toIso8601String()} to ${reservationEnd.toIso8601String()}',
          );
          print('----- END CHECK (NOT AVAILABLE) -----\n');
          return false; // Overlap detected
        }
      }

      print('No conflicts found with $activeReservations active reservations');
      print('Charger $chargerId IS available for the requested time slot');
      print('----- END CHECK (AVAILABLE) -----\n');

      return true; // No overlap, charger is available
    } catch (e) {
      print('Error checking charger availability: $e');
      return false; // Assume not available on error
    }
  }

  // Method to refresh charger availability data
  Future<void> refreshChargerAvailabilityData() async {
    try {
      print('Refreshing charger availability data...');

      // Keep a backup of the current stations list in case of errors
      final List<ChargingStation> backupStations = List.from(_stations);

      // Explicitly reload each station's chargers to ensure we have the latest data
      final stationsQuery =
          await FirebaseFirestore.instance
              .collection('charging_stations')
              .get();

      if (stationsQuery.docs.isEmpty) {
        print(
          'WARNING: No stations returned from database. Using backup stations list.',
        );
        // If no stations were returned, this might be an error - keep the existing list
        return;
      }

      // Clear the current stations list to rebuild it completely
      _stations.clear();

      // Track if we had any errors during loading
      bool hadErrors = false;

      for (final stationDoc in stationsQuery.docs) {
        try {
          // Get all chargers for this station
          final chargersQuery =
              await FirebaseFirestore.instance
                  .collection('chargers')
                  .where('station_id', isEqualTo: stationDoc.id)
                  .get();
          print(
            'Retrieved ${chargersQuery.docs.length} chargers for station ${stationDoc.id} (${stationDoc.data()?['name']})',
          );

          // Convert to Charger objects
          List<Charger> chargers =
              chargersQuery.docs
                  .map((doc) => Charger.fromMap(doc.data()!..['id'] = doc.id))
                  .toList();

          // Add the station with its chargers
          final stationWithChargers = ChargingStation(
            id: stationDoc.id,
            name: stationDoc.data()?['name'] as String,
            location: stationDoc.data()?['location'] as String? ?? '',
            address: stationDoc.data()?['address'] as String? ?? '',
            city: stationDoc.data()?['city'] as String? ?? '',
            latitude: stationDoc.data()?['latitude'] as double? ?? 0.0,
            longitude: stationDoc.data()?['longitude'] as double? ?? 0.0,
            isActive: stationDoc.data()?['is_active'] == 1,
            chargers: chargers,
            distance: stationDoc.data()?['distance'] as String? ?? '0 km',
            waitingTime: stationDoc.data()?['waiting_time']?.toString() ?? '0',
          );
          _stations.add(stationWithChargers);
        } catch (e) {
          print(
            'Error loading chargers for station ${stationDoc.id} (${stationDoc.data()?['name']}): $e',
          );
          hadErrors = true;

          // Add station without chargers as fallback
          _stations.add(
            ChargingStation.fromMap(stationDoc.data()!..['id'] = stationDoc.id),
          );
        }
      }

      // If we had errors and ended up with fewer stations than before, restore from backup
      if (hadErrors && _stations.length < backupStations.length) {
        print(
          'WARNING: Errors occurred and stations were lost. Restoring from backup.',
        );
        _stations = backupStations;
      }

      // Verify that all stations were loaded
      if (_stations.isEmpty && backupStations.isNotEmpty) {
        print(
          'CRITICAL: No stations loaded but we had stations before. Restoring from backup.',
        );
        _stations = backupStations;
      }

      // Log the number of available chargers for debugging
      int totalChargers = 0;
      int availableChargers = 0;
      for (var station in _stations) {
        totalChargers += station.chargers.length;
        availableChargers +=
            station.chargers.where((c) => c.isAvailable).length;
        print('Station: ${station.name} - ${station.chargers.length} chargers');
      }

      print(
        'After refresh: $availableChargers out of $totalChargers chargers available',
      );
      print('Total stations: ${_stations.length}');

      notifyListeners();
    } catch (e) {
      print('Error refreshing charger availability data: $e');
      // Don't clear the stations list on error
    }
  }

  // Method to ensure charging_sessions table exists
  Future<bool> ensureChargingSessionsTableExists() async {
    try {
      print('Checking if charging_sessions table exists...');
      final db = FirebaseFirestore.instance;

      // Check if the table exists
      final stations = await db.collection('charging_stations').get();

      if (stations.docs.isEmpty) {
        print(
          'CRITICAL: charging_stations table does not exist! Creating it now...',
        );
        await db.collection('charging_stations').add({
          'name': 'Test Station',
          'location': 'Test Location',
          'address': 'Test Address',
          'city': 'Test City',
          'latitude': 0.0,
          'longitude': 0.0,
          'is_active': 1,
          'available_spots': 10,
          'distance': '0 km',
          'waiting_time': 0,
        });
        print('Successfully created charging_stations table');
        return true;
      } else {
        print('charging_stations table already exists');
        return true;
      }
    } catch (e) {
      print('Error ensuring charging_sessions table exists: $e');
      return false;
    }
  }

  // Get total energy consumed by user in kWh
  Future<double> getTotalEnergyConsumed(String userId) async {
    try {
      print('Querying database for energy consumption for user $userId');
      final db = FirebaseFirestore.instance;

      // First check if charging_sessions table exists and create if needed
      final tableExists = await ensureChargingSessionsTableExists();
      if (!tableExists) {
        print(
          'ERROR: Could not create charging_sessions table - returning cached value',
        );
        return _cachedEnergyValues[userId] ?? 0.0;
      }

      // Get all sessions for debugging
      final allSessions = await db.collection('charging_sessions').get();
      print('All charging sessions in database: ${allSessions.docs.length}');

      // Print all sessions for debugging
      double manualTotal = 0.0;
      for (var sessionDoc in allSessions.docs) {
        print(
          'SESSION: ${sessionDoc.id} - User: ${sessionDoc.data()?['user_id']}, Energy: ${sessionDoc.data()?['energy_consumed']}, Status: ${sessionDoc.data()?['status']}',
        );

        // Calculate total manually to ensure we're getting all sessions
        if (sessionDoc.data()?['user_id'] == userId &&
            sessionDoc.data()?['status'] == 'completed') {
          final energyValue = sessionDoc.data()?['energy_consumed'];
          if (energyValue != null) {
            if (energyValue is double) {
              manualTotal += energyValue;
            } else if (energyValue is int) {
              manualTotal += energyValue.toDouble();
            } else if (energyValue is String) {
              manualTotal += double.tryParse(energyValue) ?? 0.0;
            }
          }
        }
      }

      print('Manual calculation from all sessions: $manualTotal kWh');

      // Direct energy query with better error handling
      try {
        final result =
            await db
                .collection('charging_sessions')
                .where('user_id', isEqualTo: userId)
                .where('status', isEqualTo: 'completed')
                .get();

        print('Direct energy query result: ${result.docs.length}');

        double totalEnergy = 0.0;

        if (result.docs.isNotEmpty &&
            result.docs.first.data()?['total'] != null) {
          final rawTotal = result.docs.first.data()?['total'];

          if (rawTotal is double) {
            totalEnergy = rawTotal;
          } else if (rawTotal is int) {
            totalEnergy = rawTotal.toDouble();
          } else if (rawTotal is String) {
            totalEnergy = double.tryParse(rawTotal) ?? 0.0;
          }

          print('Energy calculation complete: $totalEnergy kWh');

          // If SQL query result is less than our manual calculation, use the manual result
          if (totalEnergy < manualTotal) {
            print(
              'SQL result ($totalEnergy) is less than manual calculation ($manualTotal), using manual result',
            );
            totalEnergy = manualTotal;
          }

          // Update cached value only if we got a non-zero result
          if (totalEnergy > 0) {
            _cachedEnergyValues[userId] = totalEnergy;
            notifyListeners();
          } else {
            // If we got zero but have a cached value, keep using the cached value
            final cachedValue = _cachedEnergyValues[userId] ?? 0.0;
            if (cachedValue > 0) {
              print(
                'Database returned 0 kWh but we have cached value of $cachedValue kWh',
              );
              totalEnergy = cachedValue;
            }
          }

          return totalEnergy;
        }
      } catch (e) {
        print('Error in direct energy query: $e');
      }

      print('WARNING: No energy data found for user $userId');

      // If we get here, use the manual calculation if it's non-zero
      if (manualTotal > 0) {
        print('Using manual calculation result: $manualTotal kWh');
        _cachedEnergyValues[userId] = manualTotal;
        notifyListeners();
        return manualTotal;
      }

      // If we get here, we couldn't get energy data - check for cached value
      final cachedValue = _cachedEnergyValues[userId] ?? 0.0;
      print('No sessions found, using cached value: $cachedValue kWh');

      // Force update the UI
      notifyListeners();

      return cachedValue;
    } catch (e) {
      print('Error getting total energy consumed: $e');
      return _cachedEnergyValues[userId] ?? 0.0;
    }
  }

  // Get charging sessions for a user
  Future<List<Map<String, dynamic>>> getChargingSessionsForUser(
    String userId,
  ) async {
    try {
      final sessions =
          await FirebaseFirestore.instance
              .collection('charging_sessions')
              .where('user_id', isEqualTo: userId)
              .get();
      return sessions.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error getting charging sessions: $e');
      return [];
    }
  }

  // Create a test charging session for debugging
  Future<bool> createTestChargingSession({
    required String userId,
    required String stationId,
    required String vehicleId,
    required double energyConsumed,
    required double amount,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final id = await FirebaseFirestore.instance
          .collection('charging_sessions')
          .add({
            'user_id': userId,
            'station_id': stationId,
            'vehicle_id': vehicleId,
            'start_time': startTime.toIso8601String(),
            'end_time': endTime.toIso8601String(),
            'energy_consumed': energyConsumed,
            'amount': amount,
            'status': 'completed',
            'created_at': DateTime.now().toIso8601String(),
          });

      print('Created test charging session with ID: ${id.id}');
      return true;
    } catch (e) {
      print('Error creating test charging session: $e');
      return false;
    }
  }

  // Calculate CO2 saved based on energy consumed (kWh * 0.9)
  double calculateCO2Saved(double energyConsumed) {
    // The CO2 saved value should be calculated correctly
    // The app currently shows 9.5 kg for 10.5 kWh - 0.9 per kWh is correct
    // But we need to make sure the result is updated when energy changes
    final co2Saved = energyConsumed * 0.9;
    print('Calculated CO2 saved: $co2Saved kg from $energyConsumed kWh');
    return co2Saved;
  }

  Future<List<Map<String, dynamic>>> _seedChargers(String stationId) async {
    // Create a list of chargers for the station
    final chargers = [
      Charger.ac(
        stationId: stationId,
        name: 'Charger1AC',
        power: 11.0,
        pricePerKWh: 0.80,
      ).toMap(),
      Charger.ac(
        stationId: stationId,
        name: 'Charger2AC',
        power: 11.0,
        pricePerKWh: 0.80,
      ).toMap(),
      Charger.dc(
        stationId: stationId,
        name: 'Charger3DC',
        power: 50.0,
        pricePerKWh: 1.30,
      ).toMap(),
      Charger.dc(
        stationId: stationId,
        name: 'Charger4DC',
        power: 50.0,
        pricePerKWh: 1.30,
      ).toMap(),
    ];

    // Insert the chargers into the database
    final results = <Map<String, dynamic>>[];
    for (var charger in chargers) {
      final id = await FirebaseFirestore.instance
          .collection('chargers')
          .add(charger);
      results.add({...charger, 'id': id.id});
    }

    return results;
  }

  // Method to update cached energy value without expensive operations
  Future<void> updateCachedEnergyValue(
    String userId,
    double energyValue,
  ) async {
    try {
      print(
        'Updating cached energy value for user $userId to $energyValue kWh',
      );

      // Ensure energy value is valid
      if (energyValue < 0) {
        print(
          'WARNING: Negative energy value $energyValue is invalid, setting to 0',
        );
        energyValue = 0.0;
      }

      // Check if the new value is significantly different from the old one
      final oldValue = _cachedEnergyValues[userId] ?? 0.0;
      final isSignificantChange = (energyValue - oldValue).abs() > 0.01;

      if (isSignificantChange) {
        print(
          'Significant change in energy value: $oldValue kWh -> $energyValue kWh',
        );
      }

      // Always update the cached value, even if it's the same as before
      // This ensures we don't miss any energy updates
      _cachedEnergyValues[userId] = energyValue;

      // Also update the value in the database for persistence
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'total_energy_consumed': energyValue,
      });

      // Calculate CO2 saved based on new energy value
      final co2Saved = calculateCO2Saved(energyValue);
      print('Updated CO2 saved value: $co2Saved kg');

      // Always notify listeners to update any UI that depends on this data
      // This is critical for ensuring the UI reflects the latest values
      notifyListeners();

      // Force any changes to immediately propagate to the UI with a slight delay
      // This helps ensure that the UI updates even if the initial notification gets missed
      Future.delayed(const Duration(milliseconds: 100), () {
        notifyListeners();
      });

      // Schedule one more notification to ensure UI consistency
      Future.delayed(const Duration(milliseconds: 500), () {
        notifyListeners();
      });

      return;
    } catch (e) {
      print('Error updating cached energy value: $e');
    }
  }

  // Add a getter for the cached energy value
  double getCachedEnergyValue(String userId) {
    // First check in-memory cache
    final cachedValue = _cachedEnergyValues[userId];

    // If we have a value in memory, return it
    if (cachedValue != null) {
      return cachedValue;
    }

    // For new users, always start with 0.0
    // Don't load from database automatically to avoid showing stale data
    return 0.0;
  }

  // Method to clear cached values for a user (useful for new users or logout)
  void clearCachedEnergyValue(String userId) {
    _cachedEnergyValues.remove(userId);
    notifyListeners();
  }

  // Method to clear all cached values (useful for logout or app restart)
  void clearAllCachedValues() {
    _cachedEnergyValues.clear();
    notifyListeners();
  }

  // Method to load cached energy value from database
  Future<void> _loadCachedEnergyValueFromDb(String userId) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
      final cachedEnergy = userDoc.data()?['total_energy_consumed'] as double?;
      if (cachedEnergy != null && cachedEnergy > 0) {
        // Update the in-memory cache
        _cachedEnergyValues[userId] = cachedEnergy;
        // Notify listeners to update UI
        notifyListeners();
      }
    } catch (e) {
      print('Error loading cached energy value from database: $e');
    }
  }

  // Initialize the service with cached values from database
  Future<void> initCachedValues(String userId) async {
    await _loadCachedEnergyValueFromDb(userId);
  }

  // Add a special method to force set energy value without throttling
  Future<void> forceSetEnergyValue(String userId, double energyValue) async {
    try {
      print('FORCE SETTING energy value for user $userId to $energyValue kWh');

      // Directly set the cached value without any throttling
      _cachedEnergyValues[userId] = energyValue;

      // Also update the database value
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'total_energy_consumed': energyValue,
      });

      // Make sure we notify all listeners multiple times to ensure UI updates
      notifyListeners();

      // Force multiple notifications with delays
      Future.delayed(const Duration(milliseconds: 100), () {
        notifyListeners();
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        notifyListeners();
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        notifyListeners();
      });

      // Create a special charging session to ensure the energy is counted
      try {
        final db = FirebaseFirestore.instance;
        final uniqueTimestamp =
            DateTime.now().microsecondsSinceEpoch.toString();

        // Insert a special "force_update" charging session to ensure the energy is counted
        await db.collection('charging_sessions').add({
          'user_id': userId,
          'station_id': '1', // Default station ID
          'vehicle_id': '1', // Default vehicle ID
          'start_time':
              DateTime.now()
                  .subtract(const Duration(minutes: 30))
                  .toIso8601String(),
          'end_time': DateTime.now().toIso8601String(),
          'energy_consumed': energyValue, // Use the total energy value
          'amount': 0.0, // No amount needed for this special session
          'status': 'energy_update',
          'created_at': DateTime.now().toIso8601String(),
        });

        print('Created special forced energy update session');
      } catch (e) {
        print('Error creating special session: $e');
      }

      return;
    } catch (e) {
      print('Error force setting energy value: $e');
    }
  }

  // Add getVehicles method for compatibility with home_screen.dart
  Future<List<Vehicle>> getVehicles(String userId) async {
    // You may want to use VehicleService here, but for now, fetch directly from Firestore
    final query =
        await FirebaseFirestore.instance
            .collection('vehicles')
            .where('user_id', isEqualTo: userId)
            .get();
    return query.docs.map((doc) {
      final map = doc.data();
      map['id'] = doc.id;
      return Vehicle.fromMap(map);
    }).toList();
  }
}
