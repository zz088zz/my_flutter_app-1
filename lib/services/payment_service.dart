import 'package:flutter/material.dart';
import '../models/payment_method.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService with ChangeNotifier {
  List<PaymentMethod> _paymentMethods = [];
  bool _isLoading = false;
  
  PaymentService();
  
  List<PaymentMethod> get paymentMethods => _paymentMethods;
  bool get isLoading => _isLoading;
  
  Future<void> loadUserPaymentMethods(dynamic userId) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      print('Loading payment methods for user ID: $userId');
      
      // Add timeout to prevent infinite loading
      final query = await FirebaseFirestore.instance
          .collection('payment_methods')
          .where('user_id', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 10));
          
      _paymentMethods = query.docs.map((doc) {
        final map = doc.data();
        map['id'] = doc.id;
        return PaymentMethod.fromMap(map);
      }).toList();
      
      print('Final payment methods count: ${_paymentMethods.length}');
      for (var method in _paymentMethods) {
        print('- ${method.cardType}: ${method.maskedCardNumber} (Default: ${method.isDefault})');
      }
    } catch (e) {
      print('Error loading payment methods: $e');
      print('Stack trace: ${StackTrace.current}');
      _paymentMethods = [];
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  Future<PaymentMethod?> addPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      print('Adding payment method: ${paymentMethod.toMap()}');
      
      // If this is set as default, update other cards first
      if (paymentMethod.isDefault) {
        final query = await FirebaseFirestore.instance.collection('payment_methods').where('user_id', isEqualTo: paymentMethod.userId).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in query.docs) {
          batch.update(doc.reference, {'is_default': false});
        }
        await batch.commit();
      }
      
      // Now insert the new payment method
      final docRef = await FirebaseFirestore.instance.collection('payment_methods').add(paymentMethod.toMap());
      final newMethod = paymentMethod.copyWith(id: docRef.id);
      
      // Reload payment methods to reflect changes
      print('Reloading payment methods after adding new card');
      await loadUserPaymentMethods(paymentMethod.userId);
      return newMethod;
    } catch (e) {
      print('Error adding payment method: $e');
      print('Stack trace: ${StackTrace.current}');
      
      // Try to reload payment methods to ensure we have the latest data
      try {
        await loadUserPaymentMethods(paymentMethod.userId);
      } catch (reloadError) {
        print('Error reloading payment methods: $reloadError');
      }
      
      return null;
    }
  }
  
  Future<bool> deletePaymentMethod(String methodId, dynamic userId) async {
    try {
      print('Deleting payment method with ID: $methodId for user $userId');
      
      // Verify the payment method exists before attempting to delete
      final methodIndex = _paymentMethods.indexWhere((m) => m.id == methodId);
      if (methodIndex == -1) {
        print('ERROR: Payment method with ID $methodId not found in memory');
        return false;
      }
      
      print('Payment method found at index $methodIndex: ${_paymentMethods[methodIndex].toMap()}');
      await FirebaseFirestore.instance.collection('payment_methods').doc(methodId).delete();
      
      print('Successfully deleted payment method');
      await loadUserPaymentMethods(userId);
      return true;
    } catch (e) {
      print('Error deleting payment method: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }
  
  Future<bool> setDefaultPaymentMethod(String methodId, dynamic userId) async {
    try {
      print('Setting payment method $methodId as default for user $userId');
      
      // Find the payment method
      final methodIndex = _paymentMethods.indexWhere((m) => m.id == methodId);
      if (methodIndex == -1) {
        print('ERROR: Payment method not found with ID: $methodId');
        // Dump all available payment methods for debugging
        print('Available methods: ${_paymentMethods.map((m) => 'ID: ${m.id}, Type: ${m.cardType}').join(', ')}');
        return false;
      }
      
      print('Payment method found at index $methodIndex: ${_paymentMethods[methodIndex].toMap()}');
      
      // First, set all payment methods to non-default
      final query = await FirebaseFirestore.instance.collection('payment_methods').where('user_id', isEqualTo: userId).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'is_default': doc.id == methodId});
      }
      await batch.commit();
      
      print('Successfully updated payment method default status');
      // Reload to reflect changes
      await loadUserPaymentMethods(userId);
      return true;
    } catch (e) {
      print('Error setting default payment method: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }
  
  Future<bool> updatePaymentMethod(PaymentMethod method) async {
    try {
      // If setting as default, ensure we set others to non-default
      if (method.isDefault) {
        // Get current method to check if default status changed
        final currentMethodIndex = _paymentMethods.indexWhere((m) => m.id == method.id);
        final wasDefault = currentMethodIndex != -1 ? 
            _paymentMethods[currentMethodIndex].isDefault : false;
        
        // If changing to default, reset others
        if (!wasDefault) {
          final query = await FirebaseFirestore.instance.collection('payment_methods').where('user_id', isEqualTo: method.userId).get();
          final batch = FirebaseFirestore.instance.batch();
          for (var doc in query.docs) {
            if (doc.id != method.id) {
              batch.update(doc.reference, {'is_default': false});
            }
          }
          await batch.commit();
        }
      }
      
      // Update the method in Firestore
      await FirebaseFirestore.instance.collection('payment_methods').doc(method.id).update(method.toMap());
      
      // Reload to reflect changes
      await loadUserPaymentMethods(method.userId);
      return true;
    } catch (e) {
      print('Error updating payment method: $e');
      return false;
    }
  }
  
  PaymentMethod? getDefaultPaymentMethod() {
    return _paymentMethods.isNotEmpty
        ? _paymentMethods.firstWhere((m) => m.isDefault, orElse: () => _paymentMethods.first)
        : null;
  }
  
  PaymentMethod? getPaymentMethodById(String methodId) {
    try {
      return _paymentMethods.firstWhere((m) => m.id == methodId);
    } catch (e) {
      return null;
    }
  }

  // Add a stub for clearAllPaymentMethods to resolve undefined method error
  Future<bool> clearAllPaymentMethods(String userId) async {
    // Implement actual logic if needed
    return true;
  }
}