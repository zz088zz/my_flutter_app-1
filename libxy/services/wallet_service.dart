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

  Future<void> loadWalletForUser(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Get wallet directly by ID
      final walletDoc =
          await firestore.FirebaseFirestore.instance
              .collection('wallets')
              .doc(userId)
              .get();

      if (walletDoc.exists) {
        final walletData = walletDoc.data()!;
        walletData['id'] = walletDoc.id;
        _wallet = Wallet.fromMap(walletData);
        await loadTransactionsForUser(userId);
      } else {
        print('No wallet found for user ID: $userId');
        _wallet = null;
        _transactions = [];
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

  Future<void> loadTransactionsForUser(String userId) async {
    try {
      print('Loading transactions for user ID: $userId');

      final query =
          await firestore.FirebaseFirestore.instance
              .collection('transactions')
              .where('user_id', isEqualTo: userId)
              .get();

      print(
        'Query returned ${query.docs.length} transactions for user $userId',
      );

      if (query.docs.isEmpty) {
        print('No transactions found for user ID: $userId');
        _transactions = [];
      } else {
        _transactions =
            query.docs
                .map((doc) {
                  final map = doc.data();
                  map['id'] = doc.id;
                  try {
                    return Transaction.fromMap(map);
                  } catch (e) {
                    print('Error parsing transaction data: $e');
                    print('Problematic transaction data: $map');
                    return null;
                  }
                })
                .whereType<Transaction>()
                .toList();

        // Filter out wallet creation transactions
        _transactions =
            _transactions
                .where(
                  (transaction) =>
                      !transaction.description.toLowerCase().contains(
                        'wallet created',
                      ),
                )
                .toList();

        // Sort by created_at in descending order (newest first) and limit to 50
        _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (_transactions.length > 50) {
          _transactions = _transactions.take(50).toList();
        }

        print('Successfully loaded ${_transactions.length} transactions');

        // Debug: Print first few transactions
        for (int i = 0; i < Math.min(3, _transactions.length); i++) {
          final tx = _transactions[i];
          print(
            'Transaction ${i + 1}: ${tx.description} - ${tx.amount} - ${tx.transactionType}',
          );
        }
      }
    } catch (e) {
      print('Error loading transactions: $e');
      print('Stack trace: ${StackTrace.current}');
      _transactions = [];
    }
    notifyListeners();
  }

  Future<bool> topUpWallet(
    String userId,
    double amount,
    String description,
  ) async {
    try {
      if (amount <= 0) {
        print(
          'ERROR: Invalid top-up amount: $amount. Amount must be positive.',
        );
        return false;
      }

      print(
        'PAYMENT: Beginning wallet top-up of RM ${amount.toStringAsFixed(2)} with description: $description',
      );
      _isLoading = true;
      notifyListeners();

      // Get wallet directly by ID
      final walletDoc =
          await firestore.FirebaseFirestore.instance
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
      );

      // Use a batch to ensure both operations succeed or fail together
      final batch = firestore.FirebaseFirestore.instance.batch();

      // Add transaction
      final transactionRef =
          firestore.FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(transactionRef, transaction.toMap());

      // Update wallet balance
      batch.update(walletDoc.reference, {'balance': newBalance});

      // Commit the batch
      await batch.commit();

      // Update local state
      _wallet = Wallet(id: walletDoc.id, userId: userId, balance: newBalance);
      _transactions.insert(0, transaction);

      print(
        'PAYMENT: Successfully topped up wallet with RM ${amount.toStringAsFixed(2)}',
      );
      print(
        'PAYMENT: New wallet balance: RM ${_wallet?.balance.toStringAsFixed(2)}',
      );

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

  Future<bool> deductFromWallet(
    String userId,
    double amount,
    String description,
  ) async {
    try {
      if (_wallet == null) {
        print('ERROR: Cannot deduct from wallet - wallet is null');
        return false;
      }
      if (amount <= 0) {
        print(
          'ERROR: Invalid deduction amount: $amount. Amount must be positive.',
        );
        return false;
      }

      print(
        'PAYMENT: Beginning wallet deduction of RM ${amount.toStringAsFixed(2)} with description: $description',
      );
      print(
        'PAYMENT: Current wallet balance before deduction: RM ${_wallet?.balance.toStringAsFixed(2)}',
      );

      _isLoading = true;
      notifyListeners();

      // Get wallet directly by ID
      final walletDoc =
          await firestore.FirebaseFirestore.instance
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
        print(
          'ERROR: Insufficient balance. Current: $currentBalance, Requested: $amount',
        );
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
      );

      // Use a batch to ensure both operations succeed or fail together
      final batch = firestore.FirebaseFirestore.instance.batch();

      // Add transaction
      final transactionRef =
          firestore.FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(transactionRef, transaction.toMap());

      // Update wallet balance
      batch.update(walletDoc.reference, {'balance': newBalance});

      // Commit the batch
      await batch.commit();

      // Update local state
      _wallet = Wallet(id: walletDoc.id, userId: userId, balance: newBalance);
      _transactions.insert(0, transaction);

      print(
        'PAYMENT: Successfully deducted RM ${amount.toStringAsFixed(2)} from wallet',
      );
      print(
        'PAYMENT: New wallet balance: RM ${_wallet?.balance.toStringAsFixed(2)}',
      );

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
}
