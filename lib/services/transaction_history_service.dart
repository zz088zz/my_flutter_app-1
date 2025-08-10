import 'package:flutter/material.dart';
import '../models/transaction.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;


class TransactionHistoryService with ChangeNotifier {
  List<Transaction> _allTransactions = [];
  bool _isLoading = false;
  
  TransactionHistoryService();
  
  List<Transaction> get allTransactions => _allTransactions;
  bool get isLoading => _isLoading;
  
  Future<void> loadAllUserTransactions(String userId) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      print('Loading ALL transactions for user ID: $userId');
      
      // Load wallet transactions
      final walletTransactions = await _loadWalletTransactions(userId);
      
      // Load payment transactions (credit cards, Apple Pay, etc.)
      final paymentTransactions = await _loadPaymentTransactions(userId);
      
      // Combine all transactions (excluding charging session transactions)
      _allTransactions = [
        ...walletTransactions,
        ...paymentTransactions,
        // Charging session transactions are excluded as per requirement
      ];
      
      // Sort by created_at in descending order (newest first)
      _allTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      // Remove duplicates based on transaction ID and other criteria
      _allTransactions = _allTransactions.toSet().toList();
      
      // Additional duplicate detection based on amount, description, and timestamp
      final uniqueTransactions = <String, Transaction>{};
      for (final transaction in _allTransactions) {
        final key = '${transaction.amount}_${transaction.description}_${transaction.createdAt.millisecondsSinceEpoch}';
        if (!uniqueTransactions.containsKey(key)) {
          uniqueTransactions[key] = transaction;
        } else {
          print('WARNING: Duplicate transaction detected and removed: ${transaction.description}');
        }
      }
      _allTransactions = uniqueTransactions.values.toList();
      
      // Filter out any charging session transactions that might have been loaded from other sources
      _allTransactions = _allTransactions.where((transaction) => 
        transaction.transactionSource != 'charging_session'
      ).toList();
      
      print('Total transactions loaded: ${_allTransactions.length}');
      print('Wallet transactions: ${walletTransactions.length}');
      print('Payment transactions: ${paymentTransactions.length}');
      print('Charging transactions excluded as per requirement');
      
    } catch (e) {
      print('Error loading all transactions: $e');
      print('Stack trace: ${StackTrace.current}');
      _allTransactions = [];
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  Future<List<Transaction>> _loadWalletTransactions(String userId) async {
    try {
      final query = await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .where('user_id', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 10));
      
      return query.docs.map((doc) {
        final map = doc.data();
        map['id'] = doc.id;
        // Only mark as wallet if no transaction_source is set
        if (map['transaction_source'] == null) {
          map['transaction_source'] = 'wallet';
        }
        return Transaction.fromMap(map);
      }).where((transaction) => 
        // Filter out "Wallet created" transactions
        !transaction.description.toLowerCase().contains('wallet created')
      ).toList();
    } catch (e) {
      print('Error loading wallet transactions: $e');
      return [];
    }
  }
  
  Future<List<Transaction>> _loadPaymentTransactions(String userId) async {
    try {
      // Payment transactions are now stored in the transactions collection
      // with transaction_source = 'payment_method', so we don't need to create
      // them from payment_methods collection anymore
      // This prevents duplicate transactions
      
      print('Payment transactions are loaded from transactions collection');
      return [];
    } catch (e) {
      print('Error loading payment transactions: $e');
      return [];
    }
  }
  
  Future<List<Transaction>> _loadChargingTransactions(String userId) async {
    try {
      // Load charging sessions and convert them to transactions
      final chargingSessionsQuery = await firestore.FirebaseFirestore.instance
          .collection('charging_sessions')
          .where('user_id', isEqualTo: userId)
          .where('status', isEqualTo: 'completed')
          .get()
          .timeout(const Duration(seconds: 10));
      
      return chargingSessionsQuery.docs.map((doc) {
        final session = doc.data();
        final amount = session['amount'] ?? 0.0;
        final energyConsumed = session['energy_consumed'] ?? 0.0;
        final stationId = session['station_id'] ?? '';
        
        return Transaction(
          userId: userId,
          amount: amount,
          description: 'Charging session - ${energyConsumed.toStringAsFixed(2)} kWh at Station $stationId',
          transactionType: amount > 0 ? 'debit' : 'credit',
          createdAt: (session['created_at'] as firestore.Timestamp).toDate(),
          transactionSource: 'charging_session',
          sessionId: doc.id,
        );
      }).toList();
    } catch (e) {
      print('Error loading charging transactions: $e');
      return [];
    }
  }
  
  // Method to create a payment transaction record
  Future<bool> createPaymentTransaction({
    required String userId,
    required double amount,
    required String paymentMethodId,
    required String cardType,
    required String lastFourDigits,
    required String description,
    double? fineAmount,
    int? overtimeMinutes,
    int? gracePeriodMinutes,
    String? sessionId,
  }) async {
    try {
      final transaction = Transaction(
        userId: userId,
        amount: amount,
        description: description,
        transactionType: 'debit',
        createdAt: DateTime.now(),
        transactionSource: 'payment_method',
        paymentMethodId: paymentMethodId,
        fineAmount: fineAmount,
        overtimeMinutes: overtimeMinutes,
        gracePeriodMinutes: gracePeriodMinutes,
        sessionId: sessionId,
      );
      
      // Save to transactions collection
      await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .add(transaction.toMap());
      
      // Update payment method with last used info
      await firestore.FirebaseFirestore.instance
          .collection('payment_methods')
          .doc(paymentMethodId)
          .update({
        'last_used': firestore.FieldValue.serverTimestamp(),
        'last_amount': amount,
      });
      
      // Add to local list
      _allTransactions.insert(0, transaction);
      notifyListeners();
      
      print('Created payment transaction: ${transaction.toMap()}');
      return true;
    } catch (e) {
      print('Error creating payment transaction: $e');
      return false;
    }
  }
  
  // Method to create an Apple Pay transaction record
  Future<bool> createApplePayTransaction({
    required String userId,
    required double amount,
    required String description,
    double? fineAmount,
    int? overtimeMinutes,
    int? gracePeriodMinutes,
    String? sessionId,
  }) async {
    try {
      final transaction = Transaction(
        userId: userId,
        amount: amount,
        description: description,
        transactionType: 'debit',
        createdAt: DateTime.now(),
        transactionSource: 'apple_pay',
        paymentMethodId: 'apple_pay', // Special ID for Apple Pay
        fineAmount: fineAmount,
        overtimeMinutes: overtimeMinutes,
        gracePeriodMinutes: gracePeriodMinutes,
        sessionId: sessionId,
      );
      
      // Save to transactions collection
      await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .add(transaction.toMap());
      
      // Add to local list
      _allTransactions.insert(0, transaction);
      notifyListeners();
      
      print('Created Apple Pay transaction: ${transaction.toMap()}');
      return true;
    } catch (e) {
      print('Error creating Apple Pay transaction: $e');
      return false;
    }
  }
  
  // Method to force stop loading (for timeout scenarios)
  void forceStopLoading() {
    _isLoading = false;
    notifyListeners();
  }
}