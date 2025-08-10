import 'package:flutter/material.dart';
import '../models/charging_station.dart';
import '../models/charger.dart';
import '../models/transaction.dart' as app_transaction;
import '../models/user.dart'; // Adjust the import to your actual User model
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class AdminService with ChangeNotifier {
  List<ChargingStation> _stations = [];
  List<User> _users = []; // Added users list
  bool _isLoading = false;
  bool _initialized = false;
  int _retryCount = 0;
  static const int maxRetries = 3;

  List<ChargingStation> get stations => _stations;
  List<User> get users => _users; // Added getter for users
  bool get isLoading => _isLoading;

  // Initialize the database schema for admin functionality
  Future<void> init() async {
    if (_initialized) return;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print(
          '\n=== Initializing Admin Service (Attempt $attempt/$maxRetries) ===',
        );

        // Check if user is authenticated
        final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          throw Exception('User not authenticated');
        }

        // Verify admin status
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();

        if (!userDoc.exists) {
          throw Exception('User document does not exist');
        }

        final userData = userDoc.data() as Map<String, dynamic>;
        final isAdmin =
            userData['is_admin'] == true || userData['role'] == 'admin';

        if (!isAdmin) {
          throw Exception('User is not an admin');
        }

        // Test access to required collections
        await FirebaseFirestore.instance
            .collection('charging_stations')
            .limit(1)
            .get();
        await FirebaseFirestore.instance.collection('chargers').limit(1).get();
        await FirebaseFirestore.instance.collection('users').limit(1).get();
        await FirebaseFirestore.instance
            .collection('transactions')
            .limit(1)
            .get();

        _initialized = true;
        _retryCount = 0; // Reset retry count on success
        await loadAllUsers();
        print('Admin Service initialized successfully');
        return;
      } catch (e) {
        print('Error initializing admin service (Attempt $attempt): $e');
        _retryCount = attempt;

        if (attempt == maxRetries) {
          print('Max retries reached. Initialization failed.');
          rethrow; // Re-throw to handle in UI
        } else {
          // Wait before retrying (exponential backoff)
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  // Helper method to verify that essential collections exist and are accessible
  Future<bool> _verifyCollectionsExist() async {
    try {
      // Check if user is authenticated
      final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('User not authenticated');
        return false;
      }

      // Try to read from collections
      await FirebaseFirestore.instance
          .collection('charging_stations')
          .limit(1)
          .get();
      await FirebaseFirestore.instance.collection('chargers').limit(1).get();
      await FirebaseFirestore.instance.collection('users').limit(1).get();
      await FirebaseFirestore.instance
          .collection('transactions')
          .limit(1)
          .get();
      return true;
    } catch (e) {
      print('Error verifying collections: $e');
      return false;
    }
  }

  // Load all stations with their chargers
  Future<void> loadAllStations() async {
    _isLoading = true;
    notifyListeners();
    try {
      await init();

      // Check if collections are accessible
      if (!await _verifyCollectionsExist()) {
        throw Exception(
          'Cannot access required collections. Please check your admin permissions.',
        );
      }

      final stationQuery =
          await FirebaseFirestore.instance
              .collection('charging_stations')
              .get();
      final List<ChargingStation> loadedStations = [];

      for (var stationDoc in stationQuery.docs) {
        try {
          final stationId = stationDoc.id;
          final stationData = stationDoc.data();
          stationData['id'] = stationId; // Add the document ID to the data

          final chargerQuery =
              await FirebaseFirestore.instance
                  .collection('chargers')
                  .where('station_id', isEqualTo: stationId)
                  .get();

          final chargers =
              chargerQuery.docs.map((doc) {
                final chargerData = doc.data();
                chargerData['id'] = doc.id; // Add the document ID to the data
                return Charger.fromMap(chargerData);
              }).toList();

          final station = ChargingStation.fromMap(stationData);
          loadedStations.add(station.copyWithChargers(chargers));
        } catch (e) {
          print('Error processing station ${stationDoc.id}: $e');
          // Continue with other stations even if one fails
        }
      }

      _stations = loadedStations;
      print('Successfully loaded ${_stations.length} stations');
    } catch (e) {
      print('Error loading stations: $e');
      rethrow; // Re-throw to handle in UI
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a new station with chargers
  Future<bool> addStation(
    ChargingStation station,
    List<Charger> chargers,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      print('\n=== ADDING NEW STATION ===');
      print('Station name: ${station.name}');
      print('Latitude: ${station.latitude}, Longitude: ${station.longitude}');
      await init();
      final stationMap = station.toMap();
      stationMap['total_spots'] = chargers.length;
      stationMap['available_spots'] =
          chargers.where((c) => c.isAvailable).length;
      stationMap['power_output'] = _getHighestPowerOutput(chargers);
      stationMap['price_per_kwh'] = _getAveragePricePerKWh(chargers);
      print('Full station map for Firestore: ${stationMap}');
      final stationRef = await FirebaseFirestore.instance
          .collection('charging_stations')
          .add(stationMap);
      for (var charger in chargers) {
        charger.stationId = stationRef.id;
        await FirebaseFirestore.instance
            .collection('chargers')
            .add(charger.toMap());
      }
      await loadAllStations();
      return true;
    } catch (e) {
      print('ERROR adding station: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper method to get highest power output among chargers
  String _getHighestPowerOutput(List<Charger> chargers) {
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
  double _getAveragePricePerKWh(List<Charger> chargers) {
    if (chargers.isEmpty) return 0.0;
    double totalPrice = 0;
    for (var charger in chargers) {
      totalPrice += charger.pricePerKWh;
    }
    return totalPrice / chargers.length;
  }

  // Update an existing station with chargers
  Future<bool> updateStation(
    ChargingStation station,
    List<Charger> chargers,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      await init();
      final stationId = station.id?.toString() ?? station.id;
      if (stationId == null) throw Exception('Station ID is required');
      final stationMap = station.toMap();
      stationMap['total_spots'] = chargers.length;
      stationMap['available_spots'] =
          chargers.where((c) => c.isAvailable).length;
      stationMap['power_output'] = _getHighestPowerOutput(chargers);
      stationMap['price_per_kwh'] = _getAveragePricePerKWh(chargers);
      await FirebaseFirestore.instance
          .collection('charging_stations')
          .doc(stationId)
          .update(stationMap);
      // Delete existing chargers for this station
      final chargerQuery =
          await FirebaseFirestore.instance
              .collection('chargers')
              .where('station_id', isEqualTo: stationId)
              .get();
      for (var doc in chargerQuery.docs) {
        await doc.reference.delete();
      }
      // Insert updated chargers
      for (var charger in chargers) {
        charger.stationId = stationId;
        await FirebaseFirestore.instance
            .collection('chargers')
            .add(charger.toMap());
      }
      await loadAllStations();
      return true;
    } catch (e) {
      print('ERROR updating station: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a station and its chargers
  Future<bool> deleteStation(String stationId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await init();
      // Delete chargers first
      final chargerQuery =
          await FirebaseFirestore.instance
              .collection('chargers')
              .where('station_id', isEqualTo: stationId)
              .get();
      for (var doc in chargerQuery.docs) {
        await doc.reference.delete();
      }
      // Delete the station
      await FirebaseFirestore.instance
          .collection('charging_stations')
          .doc(stationId)
          .delete();
      await loadAllStations();
      return true;
    } catch (e) {
      print('ERROR deleting station: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a charger to a station
  Future<bool> addChargerToStation(String stationId, Charger charger) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Ensure database schema is initialized
      await init();

      // Make sure the charger has the correct station ID
      charger = charger.copyWith(stationId: stationId);

      // Add to database
      final chargerId = await FirebaseFirestore.instance
          .collection('chargers')
          .add(charger.toMap());

      if (chargerId.id.isNotEmpty) {
        // Reload stations to refresh the list
        await loadAllStations();
        return true;
      }

      return false;
    } catch (e) {
      print('Error adding charger: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a charger
  Future<bool> updateCharger(Charger charger) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Ensure database schema is initialized
      await init();

      if (charger.id == null) {
        throw Exception('Cannot update a charger without an ID');
      }

      // Update in database
      await FirebaseFirestore.instance
          .collection('chargers')
          .doc(charger.id)
          .update(charger.toMap());

      // Reload stations to refresh the list
      await loadAllStations();
      return true;
    } catch (e) {
      print('Error updating charger: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a charger
  Future<bool> deleteCharger(String chargerId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Ensure database schema is initialized
      await init();

      // Delete from database
      await FirebaseFirestore.instance
          .collection('chargers')
          .doc(chargerId)
          .delete();

      // Reload stations to refresh the list
      await loadAllStations();
      return true;
    } catch (e) {
      print('Error deleting charger: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get all transactions from all users
  Future<List<app_transaction.Transaction>> getAllTransactions() async {
    try {
      await init();

      // Check if collections are accessible
      if (!await _verifyCollectionsExist()) {
        throw Exception(
          'Cannot access required collections. Please check your admin permissions.',
        );
      }

      final transactionsData =
          await FirebaseFirestore.instance.collection('transactions').get();

      // Convert the map data to Transaction objects
      final transactions =
          transactionsData.docs
              .map((doc) {
                try {
                  final data = doc.data();
                  data['id'] = doc.id;
                  return app_transaction.Transaction.fromMap(data);
                } catch (e) {
                  print('Error processing transaction ${doc.id}: $e');
                  // Return null for failed transactions, will be filtered out
                  return null;
                }
              })
              .where((transaction) => transaction != null)
              .cast<app_transaction.Transaction>()
              .toList();

      print('Successfully loaded ${transactions.length} transactions');
      return transactions;
    } catch (e) {
      print('Error getting all transactions: $e');
      rethrow; // Re-throw to handle in UI
    }
  }

  // Get username by user ID
  Future<String> getUsernameById(String userId) async {
    try {
      // Ensure database schema is initialized
      await init();

      // Get the database instance
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final firstName = data?['first_name'] as String? ?? '';
        final lastName = data?['last_name'] as String? ?? '';

        if (firstName.isNotEmpty || lastName.isNotEmpty) {
          return '$firstName $lastName'.trim();
        } else {
          // Fallback to email if name is empty
          return data?['email'] as String? ?? 'User #$userId';
        }
      }

      return 'User #$userId'; // Fallback if user not found
    } catch (e) {
      print('Error getting username: $e');
      return 'User #$userId'; // Fallback on error
    }
  }

  // Load all users
  Future<void> loadAllUsers() async {
    try {
      await init();
      // Check if collections are accessible
      if (!await _verifyCollectionsExist()) {
        throw Exception(
          'Cannot access required collections. Please check your admin permissions.',
        );
      }
      // Fetch all admin IDs
      final adminQuery =
          await FirebaseFirestore.instance.collection('admins').get();
      final Set<String> adminIds = adminQuery.docs.map((doc) => doc.id).toSet();
      // Fetch all users
      final userQuery =
          await FirebaseFirestore.instance.collection('users').get();
      _users =
          userQuery.docs
              .where((doc) => !adminIds.contains(doc.id)) // Exclude admin users
              .map((doc) {
                try {
                  final data = doc.data();
                  data['id'] = doc.id;
                  return User.fromMap(data);
                } catch (e) {
                  print('Error processing user ${doc.id}: $e');
                  // Return a default user object if parsing fails
                  final fallbackData = doc.data();
                  return User(
                    id: doc.id,
                    firstName: 'Unknown',
                    lastName: 'User',
                    email: fallbackData['email'] ?? 'unknown@example.com',
                    phoneNumber: fallbackData['phone_number'] ?? '',
                    createdAt: DateTime.now().toIso8601String(),
                    password: '',
                  );
                }
              })
              .toList();
      print('Successfully loaded ${_users.length} users (excluding admins)');
      notifyListeners();
    } catch (e) {
      print('Error loading users: $e');
      rethrow; // Re-throw to handle in UI
    }
  }

  // Update a user in the database
  Future<bool> updateUser(User user) async {
    try {
      // Make sure user has an ID
      if (user.id == null) {
        print('Cannot update user without an ID');
        return false;
      }

      // Update user in the database
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .update(user.toMap());

      // Reload users to refresh the list
      await loadAllUsers();
      return true;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  // Delete a user from the database
  Future<bool> deleteUser(String? userId) async {
    try {
      // Make sure user ID is not null
      if (userId == null) {
        print('Cannot delete user with null ID');
        return false;
      }

      // Delete user from the database
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();

      // Reload users to refresh the list
      await loadAllUsers();
      return true;
    } catch (e) {
      print('Error deleting user: $e');
      return false;
    }
  }

  // Admin authentication
  Future<bool> adminLogin(String email, String password) async {
    try {
      print('Attempting admin login for: $email');

      // Sign in with Firebase Auth
      final credential = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (credential.user == null) {
        print('No user returned from Firebase Auth');
        return false;
      }

      print('User authenticated: ${credential.user!.uid}');

      // Check if user is admin in users collection
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(credential.user!.uid)
              .get();

      if (!userDoc.exists) {
        print('User document does not exist');
        // Sign out the user since they don't exist
        await fb_auth.FirebaseAuth.instance.signOut();
        return false;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final isAdmin =
          userData['is_admin'] == true || userData['role'] == 'admin';

      if (!isAdmin) {
        print('User is not an admin');
        // Sign out the user since they're not an admin
        await fb_auth.FirebaseAuth.instance.signOut();
        return false;
      }

      print('Admin login successful');
      return true;
    } catch (e) {
      print('Admin login error: $e');
      return false;
    }
  }
}

// UserService functionality is now integrated into AdminService above
// The getAllUsers method is implemented as loadAllUsers() in AdminService
