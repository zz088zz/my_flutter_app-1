import 'package:flutter/material.dart';
import '../models/vehicle.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleService with ChangeNotifier {
  List<Vehicle> _vehicles = [];
  bool _isLoading = false;
  
  VehicleService();
  
  List<Vehicle> get vehicles => _vehicles;
  bool get isLoading => _isLoading;
  
  Future<void> loadUserVehicles(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final query = await FirebaseFirestore.instance.collection('vehicles').where('user_id', isEqualTo: userId).get();
      _vehicles = query.docs.map((doc) {
        final map = doc.data();
        map['id'] = doc.id;
        return Vehicle.fromMap(map);
      }).toList();
      _vehicles.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return 0;
      });
    } catch (e) {
      _vehicles = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Vehicle?> addVehicle(Vehicle vehicle) async {
    try {
      if (vehicle.isDefault) {
        final query = await FirebaseFirestore.instance.collection('vehicles').where('user_id', isEqualTo: vehicle.userId).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in query.docs) {
          batch.update(doc.reference, {'is_default': false});
        }
        await batch.commit();
      }
      final docRef = await FirebaseFirestore.instance.collection('vehicles').add(vehicle.toMap());
      final newVehicle = vehicle.copyWith(id: docRef.id);
      await loadUserVehicles(vehicle.userId);
      return newVehicle;
    } catch (e) {
      print('Error adding vehicle: $e');
      return null;
    }
  }

  Future<bool> updateVehicle(Vehicle vehicle) async {
    try {
      final vehicleId = vehicle.id;
      if (vehicleId == null) return false;
      if (vehicle.isDefault) {
        final query = await FirebaseFirestore.instance.collection('vehicles').where('user_id', isEqualTo: vehicle.userId).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in query.docs) {
          if (doc.id != vehicleId) {
            batch.update(doc.reference, {'is_default': false});
          }
        }
        await batch.commit();
      }
      await FirebaseFirestore.instance.collection('vehicles').doc(vehicleId).update(vehicle.toMap());
      await loadUserVehicles(vehicle.userId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteVehicle(String vehicleId, String userId) async {
    try {
      await FirebaseFirestore.instance.collection('vehicles').doc(vehicleId).delete();
      await loadUserVehicles(userId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setDefaultVehicle(String vehicleId, String userId) async {
    try {
      final query = await FirebaseFirestore.instance.collection('vehicles').where('user_id', isEqualTo: userId).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'is_default': doc.id == vehicleId});
      }
      await batch.commit();
      await loadUserVehicles(userId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Vehicle? getDefaultVehicle() {
    return _vehicles.isNotEmpty
        ? _vehicles.firstWhere((v) => v.isDefault, orElse: () => _vehicles.first)
        : null;
  }

  Vehicle? getVehicleById(String vehicleId) {
    try {
      return _vehicles.firstWhere((v) => v.id == vehicleId);
    } catch (e) {
      return null;
    }
  }
} 