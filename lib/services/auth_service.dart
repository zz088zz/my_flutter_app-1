import 'package:flutter/material.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

enum LoginResult {
  success,
  invalidCredentials,
  userNotFound,
  accountDisabled,
  error
}

class AuthService with ChangeNotifier {
  User? _currentUser;
  
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && (_currentUser?.canLogin ?? false);
  
  // Refresh current user status from database
  Future<void> refreshUserStatus() async {
    if (_currentUser?.id != null) {
      await _loadUserFromId(_currentUser!.id!);
    }
  }

  // Initialize auth state from shared preferences
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null) {
        try {
          await _loadUserFromId(userId);
        } catch (e) {
          print('Error loading user data: $e');
          // Clear invalid user credentials
          await prefs.remove('user_id');
        }
      }
      notifyListeners();
    } catch (e) {
      print('Error initializing AuthService: $e');
    }
  }
  
  Future<void> _loadUserFromId(String userId) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (userDoc.exists) {
      final userData = userDoc.data()!;
      userData['id'] = userId;  // Ensure ID is set
      final user = User.fromMap(userData);
      
      // Check if user account is still active
      if (!user.canLogin) {
        print('Session invalid: User account is disabled');
        // Clear the session for disabled user
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('user_id');
        _currentUser = null;
        notifyListeners();
        return;
      }
      
      _currentUser = user;
      notifyListeners();
    }
  }
  
  Future<LoginResult> login(String email, String password) async {
    try {
      print('Attempting login with email: $email');
      
      final credential = await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      final userId = credential.user!.uid;
      
      print('Firebase Auth successful, user ID: $userId');
      
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        print('User document not found for ID: $userId');
        return LoginResult.userNotFound;
      }
      
      print('User document found in Firestore');
      
      final userData = userDoc.data()!;
      userData['id'] = userId;  // Ensure ID is set
      final user = User.fromMap(userData);
      
      // Check if user account is active
      if (!user.canLogin) {
        print('Login denied: User account is disabled');
        // Sign out from Firebase since the user is disabled
        await fb_auth.FirebaseAuth.instance.signOut();
        return LoginResult.accountDisabled;
      }
      
      _currentUser = user;
      
      // Save user session
      await _saveUserSession(userId);
      
      notifyListeners();
      print('Login successful for user: ${_currentUser?.email}');
      return LoginResult.success;
    } on fb_auth.FirebaseAuthException catch (e) {
      print('Firebase Auth error: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-email':
        case 'invalid-credential':
          // Return the same error for all credential-related issues for security
          return LoginResult.invalidCredentials;
        case 'user-disabled':
          return LoginResult.accountDisabled;
        default:
          return LoginResult.error;
      }
    } catch (e) {
      print('Firebase login error: $e');
      print('Stack trace: ${StackTrace.current}');
      return LoginResult.error;
    }
  }
  
  // Register a new user
  Future<bool> register(String email, String password, String firstName, String lastName, String phoneNumber) async {
    try {
      final credential = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      final userId = credential.user!.uid;
      
      // Create timestamp string for User model
      final timestamp = DateTime.now().toIso8601String();
      
      // Create user document for Firestore (with FieldValue for server timestamp)
      final userDocMap = {
        'id': userId,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone_number': phoneNumber,
        'created_at': FieldValue.serverTimestamp(),
      };
      
      // Create user map for User model (with string timestamp)
      final userMap = {
        'id': userId,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone_number': phoneNumber,
        'created_at': timestamp,
      };
      
      // Create wallet document
      final walletMap = {
        'user_id': userId,
        'balance': 0.0,
        'created_at': FieldValue.serverTimestamp(),
      };
      
      // Create initial transaction
      final transactionMap = {
        'user_id': userId,
        'amount': 0.0,
        'description': 'Wallet created',
        'transaction_type': 'credit',
        'created_at': FieldValue.serverTimestamp(),
      };
      
      // Use a batch write to ensure all documents are created atomically
      final batch = FirebaseFirestore.instance.batch();
      
      // Add user document (using userDocMap with FieldValue)
      final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
      batch.set(userRef, userDocMap);
      
      // Add wallet document
      final walletRef = FirebaseFirestore.instance.collection('wallets').doc(userId);
      batch.set(walletRef, walletMap);
      
      // Add initial transaction
      final transactionRef = FirebaseFirestore.instance.collection('transactions').doc();
      batch.set(transactionRef, transactionMap);
      
      // Commit the batch
      await batch.commit();
      
      // Send email verification
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        print('Email verification sent to: $email');
      }
      
      // Set current user (using userMap with string timestamp)
      _currentUser = User.fromMap(userMap);
      notifyListeners();
      
      // Save user session
      await _saveUserSession(userId);
      
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      print('Firebase Auth error: ${e.code} - ${e.message}');
      rethrow; // Let the UI handle specific Firebase Auth errors
    } catch (e) {
      print('Firebase registration error: $e');
      print('Stack trace: ${StackTrace.current}');
      
      // If user was created in Auth but Firestore failed, clean up
      try {
        final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await currentUser.delete();
          print('Cleaned up orphaned Firebase Auth user');
        }
      } catch (cleanupError) {
        print('Failed to cleanup user: $cleanupError');
      }
      
      rethrow; // Let the UI handle the error
    }
  }
  
  Future<bool> signup(User user, String password) async {
    try {
      final credential = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(email: user.email, password: password);
      final userMap = user.toMap();
      userMap.remove('password');
      await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set(userMap);
      _currentUser = user;
      notifyListeners();
      return true;
    } catch (e) {
      print('Firebase signup error: $e');
      return false;
    }
  }
  
  Future<void> logout() async {
    _currentUser = null;
    await fb_auth.FirebaseAuth.instance.signOut();
    notifyListeners();
  }
  
  Future<void> _saveUserSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }
  
  // Update user profile
  Future<bool> updateUserProfile(User updatedUser) async {
    try {
      final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) return false;
      
      final userId = firebaseUser.uid;
      
      // Note: Email updates are disabled in the UI - email remains unchanged
      // Only update other profile fields in Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'first_name': updatedUser.firstName,
        'last_name': updatedUser.lastName,
        'phone_number': updatedUser.phoneNumber,
        // Email is intentionally omitted - it cannot be changed
      });
      
      _currentUser = updatedUser;
      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating user profile: $e');
      return false;
    }
  }
  
  // Verify if the given password matches the current user's password
  Future<bool> verifyPassword(String password) async {
    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return false;
      final cred = fb_auth.EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(cred);
      return true;
    } catch (e) {
      print('Error verifying password with Firebase: $e');
      return false;
    }
  }
  
  // Change the current user's password
  Future<bool> changePassword(String newPassword) async {
    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.updatePassword(newPassword);
      return true;
    } catch (e) {
      print('Error changing password with Firebase: $e');
      return false;
    }
  }
  
  // Request password reset
  Future<bool> requestPasswordReset(String email) async {
    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      print('Firebase Auth error sending password reset email: ${e.code} - ${e.message}');
      // Re-throw to let the UI handle specific error codes
      rethrow;
    } catch (e) {
      print('Error sending password reset email with Firebase: $e');
      return false;
    }
  }
  
  // Check if email exists in database
  Future<bool> emailExists(String email) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();
      return userDoc.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if email exists: $e');
      return false;
    }
  }
  
  // Reset password
  Future<bool> resetPassword(String email, String newPassword) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (userDoc.docs.isEmpty) {
        return false; // User not found
      }
      
      // Update user's password
      await FirebaseFirestore.instance.collection('users').doc(userDoc.docs.first.id).update({'password': newPassword});
      
      return true;
    } catch (e) {
      print('Password reset error: $e');
      return false;
    }
  }
}