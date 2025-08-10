import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../models/transaction.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'dart:math' as Math;

class WalletService with ChangeNotifier {
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  bool _isLoading = false;
  
  WalletService();
  
  Wallet? get wallet => _wallet;
  List<Transaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  double get balance => _wallet?.balance ?? 0.0;
  
  // Method to force stop loading (for timeout scenarios)
  void forceStopLoading() {
    _isLoading = false;
    notifyListeners();
  }
  
  // Test Firebase connectivity
  Future<bool> testFirebaseConnection() async {
    try {
      // Test with actual collections that should exist
      await firestore.FirebaseFirestore.instance
          .collection('wallets')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));
      print('Firebase connection test successful');
      return true;
    } catch (e) {
      print('Firebase connection test failed: $e');
      // Try alternative connectivity test
      try {
        await firestore.FirebaseFirestore.instance
            .collection('transactions')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
        print('Alternative Firebase connection test successful');
        return true;
      } catch (e2) {
        print('Alternative Firebase connection test also failed: $e2');
        return false;
      }
    }
  }
  
  Future<void> loadWalletForUser(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      print('Loading wallet for user ID: $userId');
      
      // Add timeout to prevent infinite loading
      final walletDoc = await firestore.FirebaseFirestore.instance
          .collection('wallets')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 10));
          
      if (walletDoc.exists) {
        final walletData = walletDoc.data()!;
        walletData['id'] = walletDoc.id;
        _wallet = Wallet.fromMap(walletData);
        print('Wallet loaded successfully: RM ${_wallet?.balance.toStringAsFixed(2)}');
        
        // Load transactions with timeout
        try {
          await loadTransactionsForUser(userId).timeout(const Duration(seconds: 15));
        } catch (e) {
          print('Warning: Transaction loading timed out or failed: $e');
          _transactions = []; // Set empty transactions list to prevent hanging
        }
      } else {
        print('No wallet found for user ID: $userId - creating new wallet');
        // Create a new wallet for the user
        await _createWalletForUser(userId);
      }
    } catch (e) {
      print('Error loading wallet: $e');
      print('Stack trace: ${StackTrace.current}');
      _wallet = null;
      _transactions = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _createWalletForUser(String userId) async {
    try {
      print('Creating new wallet for user ID: $userId');
      
      // Create a new wallet with 0 balance
      final newWallet = Wallet(
        id: userId,
        userId: userId,
        balance: 0.0,
      );
      
      // Save to Firestore
      await firestore.FirebaseFirestore.instance
          .collection('wallets')
          .doc(userId)
          .set(newWallet.toMap());
      
      // Create initial transaction
      final initialTransaction = Transaction(
        userId: userId,
        amount: 0.0,
        description: 'Wallet created',
        transactionType: 'credit',
        createdAt: DateTime.now(),
        transactionSource: 'wallet',
      );
      
      await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .add(initialTransaction.toMap());
      
      // Update local state
      _wallet = newWallet;
      _transactions = [initialTransaction];
      
      print('Wallet created successfully for user ID: $userId');
    } catch (e) {
      print('Error creating wallet: $e');
      print('Stack trace: ${StackTrace.current}');
      _wallet = null;
      _transactions = [];
    }
  }

  Future<void> loadTransactionsForUser(String userId) async {
    try {
      print('Loading transactions for user ID: $userId');
      
      // Use a simple query without orderBy to avoid index requirement
      final query = await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .where('user_id', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 10));
      
      print('Transactions found for user $userId: ${query.docs.length}');
      
      // If we found transactions, let's debug their structure
      if (query.docs.isNotEmpty) {
        print('Sample transaction data:');
        for (int i = 0; i < Math.min(3, query.docs.length); i++) {
          final doc = query.docs[i];
          print('Transaction ${i + 1}: ${doc.data()}');
        }
      }
      
      if (query.docs.isEmpty) {
        print('No transactions found for user ID: $userId');
        _transactions = [];
      } else {
        _transactions = query.docs.map((doc) {
          final map = doc.data();
          map['id'] = doc.id;
          try {
            return Transaction.fromMap(map);
          } catch (e) {
            print('Error parsing transaction data: $e');
            print('Problematic transaction data: $map');
            return null;
          }
        }).whereType<Transaction>().toList();
        
        // Filter out wallet creation transactions
        _transactions = _transactions
            .where((transaction) => !transaction.description.toLowerCase().contains('wallet created'))
            .toList();
        
        // Sort by created_at in descending order (newest first) - NO LIMIT
        _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        // Removed 50 transaction limit to show all transactions
        
        print('Successfully loaded ${_transactions.length} transactions');
        
        // Debug: Print first few transactions
        for (int i = 0; i < Math.min(3, _transactions.length); i++) {
          final tx = _transactions[i];
          print('Transaction ${i + 1}: ${tx.description} - ${tx.amount} - ${tx.transactionType}');
        }
      }
    } catch (e) {
      print('Error loading transactions: $e');
      print('Stack trace: ${StackTrace.current}');
      _transactions = [];
    }
    notifyListeners();
  }

  Future<bool> topUpWallet(String userId, double amount, String description, {
    double? fineAmount,
    int? overtimeMinutes,
    int? gracePeriodMinutes,
    String? sessionId,
  }) async {
    try {
      if (amount <= 0) {
        print('ERROR: Invalid top-up amount: $amount. Amount must be positive.');
        return false;
      }
      
      print('PAYMENT: Beginning wallet top-up of RM ${amount.toStringAsFixed(2)} with description: $description');
      _isLoading = true;
      notifyListeners();
      
      // Get wallet directly by ID
      final walletDoc = await firestore.FirebaseFirestore.instance
          .collection('wallets')
          .doc(userId)
          .get();
          
      if (!walletDoc.exists) {
        print('ERROR: Wallet not found for user ID: $userId');
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final currentBalance = (walletDoc.data()!['balance'] as num).toDouble();
      final newBalance = currentBalance + amount;
      
      // Create transaction
      final transaction = Transaction(
        userId: userId,
        amount: amount,
        description: description,
        transactionType: 'credit',
        createdAt: DateTime.now(),
        transactionSource: 'wallet',
        fineAmount: fineAmount,
        overtimeMinutes: overtimeMinutes,
        gracePeriodMinutes: gracePeriodMinutes,
        sessionId: sessionId,
      );
      
      // Use a batch to ensure both operations succeed or fail together
      final batch = firestore.FirebaseFirestore.instance.batch();
      
      // Add transaction
      final transactionRef = firestore.FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(transactionRef, transaction.toMap());
      
      // Update wallet balance
      batch.update(walletDoc.reference, {'balance': newBalance});
      
      // Commit the batch
      await batch.commit();
      
      // Update local state
      _wallet = Wallet(id: walletDoc.id, userId: userId, balance: newBalance);
      _transactions.insert(0, transaction);
      
      print('PAYMENT: Successfully topped up wallet with RM ${amount.toStringAsFixed(2)}');
      print('PAYMENT: New wallet balance: RM ${_wallet?.balance.toStringAsFixed(2)}');
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('ERROR in topUpWallet: $e');
      print('Stack trace: ${StackTrace.current}');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deductFromWallet(String userId, double amount, String description, {
    double? fineAmount,
    int? overtimeMinutes,
    int? gracePeriodMinutes,
    String? sessionId,
  }) async {
    try {
      if (_wallet == null) {
        print('ERROR: Cannot deduct from wallet - wallet is null');
        return false;
      }
      if (amount <= 0) {
        print('ERROR: Invalid deduction amount: $amount. Amount must be positive.');
        return false;
      }
      
      print('PAYMENT: Beginning wallet deduction of RM ${amount.toStringAsFixed(2)} with description: $description');
      print('PAYMENT: Current wallet balance before deduction: RM ${_wallet?.balance.toStringAsFixed(2)}');
      
      _isLoading = true;
      notifyListeners();
      
      // Get wallet directly by ID
      final walletDoc = await firestore.FirebaseFirestore.instance
          .collection('wallets')
          .doc(userId)
          .get();
          
      if (!walletDoc.exists) {
        print('ERROR: Wallet not found for user ID: $userId');
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final currentBalance = (walletDoc.data()!['balance'] as num).toDouble();
      if (currentBalance < amount) {
        print('ERROR: Insufficient balance. Current: $currentBalance, Requested: $amount');
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final newBalance = currentBalance - amount;
      
      // Create transaction
      final transaction = Transaction(
        userId: userId,
        amount: amount,
        description: description,
        transactionType: 'debit',
        createdAt: DateTime.now(),
        transactionSource: 'wallet',
        fineAmount: fineAmount ?? (description.toLowerCase().contains('fine') ? amount : null),
        overtimeMinutes: overtimeMinutes,
        gracePeriodMinutes: gracePeriodMinutes,
        sessionId: sessionId,
      );
      
      // Use a batch to ensure both operations succeed or fail together
      final batch = firestore.FirebaseFirestore.instance.batch();
      
      // Add transaction
      final transactionRef = firestore.FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(transactionRef, transaction.toMap());
      
      // Update wallet balance
      batch.update(walletDoc.reference, {'balance': newBalance});
      
      // Commit the batch
      await batch.commit();
      
      // Update local state
      _wallet = Wallet(id: walletDoc.id, userId: userId, balance: newBalance);
      _transactions.insert(0, transaction);
      
      print('PAYMENT: Successfully deducted RM ${amount.toStringAsFixed(2)} from wallet');
      print('PAYMENT: New wallet balance: RM ${_wallet?.balance.toStringAsFixed(2)}');
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('ERROR in deductFromWallet: $e');
      print('Stack trace: ${StackTrace.current}');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  List<Transaction> getRecentTransactions([int count = 5]) {
    // Transactions are already filtered in loadTransactionsForUser
    if (_transactions.length <= count) {
      return _transactions;
    }
    return _transactions.sublist(0, count);
  }
  
  Future<void> refreshTransactions() async {
    if (_wallet != null) {
      await loadTransactionsForUser(_wallet!.userId);
    }
  }
  
  // Method to load ALL transactions including wallet creation (for admin/debug purposes)
  Future<void> loadAllTransactionsForUser(String userId) async {
    try {
      print('Loading ALL transactions for user ID: $userId (including wallet creation)');
      
      final query = await firestore.FirebaseFirestore.instance
          .collection('transactions')
          .where('user_id', isEqualTo: userId)
          .get();
      
      if (query.docs.isEmpty) {
        print('No transactions found for user ID: $userId');
        _transactions = [];
      } else {
        _transactions = query.docs.map((doc) {
          final map = doc.data();
          map['id'] = doc.id;
          try {
            return Transaction.fromMap(map);
          } catch (e) {
            print('Error parsing transaction data: $e');
            print('Problematic transaction data: $map');
            return null;
          }
        }).whereType<Transaction>().toList();
        
        // Sort by created_at in descending order (newest first) - NO LIMIT
        _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        print('Successfully loaded ALL ${_transactions.length} transactions (including wallet creation)');
      }
    } catch (e) {
      print('Error loading all transactions: $e');
      print('Stack trace: ${StackTrace.current}');
      _transactions = [];
    }
    notifyListeners();
  }
}