import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/charging_session.dart';
import 'transaction_history_service.dart';

class FineService with ChangeNotifier {
  static const double _defaultFineRatePerMinute =
      1.00; // RM 1.00 per minute (for 50kW fast chargers)
  static const int _defaultGracePeriodMinutes =
      3; // 3 minutes grace period (for 50kW fast chargers)

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TransactionHistoryService? _transactionHistoryService;

  FineService({TransactionHistoryService? transactionHistoryService})
      : _transactionHistoryService = transactionHistoryService;

  /// Calculate fine amount for a charging session
  double calculateFine(ChargingSession session, {double? customFineRate}) {
    final fineRate = customFineRate ?? _defaultFineRatePerMinute;
    
    // Check if session has overtimeDuration method, if not return 0
    if (session.endTime == null || session.chargerRemovedTime == null) {
      return 0.0;
    }
    
    // Calculate overtime minutes beyond grace period
    final overtimeMinutes = session.endTime!.difference(session.chargerRemovedTime!).inMinutes;
    if (overtimeMinutes <= _defaultGracePeriodMinutes) {
      return 0.0;
    }
    
    // Calculate fine based on overtime minutes beyond grace period
    final chargableMinutes = overtimeMinutes - _defaultGracePeriodMinutes;
    return chargableMinutes > 0 ? chargableMinutes * fineRate : 0.0;
  }

  /// Update charging session with charger removal time and fine
  Future<void> updateSessionWithChargerRemoval({
    required String sessionId,
    required String userId,
    required DateTime chargerRemovedTime,
    required double fineAmount,
  }) async {
    try {
      await _firestore.collection('charging_sessions').doc(sessionId).update({
        'charger_removed_time': Timestamp.fromDate(chargerRemovedTime),
        'fine_amount': fineAmount,
        'status': 'charger_removed',
        'updated_at': Timestamp.now(),
      });

      // If there's a fine, create a transaction record using TransactionHistoryService
      if (fineAmount > 0 && _transactionHistoryService != null) {
        await _createFineTransaction(
          userId: userId,
          sessionId: sessionId,
          fineAmount: fineAmount,
        );
      }
      
      notifyListeners();
    } catch (e) {
      print('Error updating charging session with charger removal: $e');
      rethrow;
    }
  }

  /// Create a transaction record for the fine
  Future<void> _createFineTransaction({
    required String userId,
    required String sessionId,
    required double fineAmount,
  }) async {
    try {
      if (_transactionHistoryService != null) {
        // Get the charging session to calculate overtime minutes
        final session = await getChargingSession(sessionId);
        int? overtimeMinutes;
        int gracePeriodMinutes = _defaultGracePeriodMinutes;
        
        if (session != null && session.endTime != null && session.chargerRemovedTime != null) {
          overtimeMinutes = session.endTime!.difference(session.chargerRemovedTime!).inMinutes;
        }
        
        // Use the existing transaction history service to create the transaction
        await _transactionHistoryService!.createPaymentTransaction(
          userId: userId,
          amount: fineAmount,
          paymentMethodId: 'fine_payment',
          cardType: 'Fine',
          lastFourDigits: '',
          description: 'Overtime fine for charging session $sessionId',
          fineAmount: fineAmount,
          overtimeMinutes: overtimeMinutes,
          gracePeriodMinutes: gracePeriodMinutes,
          sessionId: sessionId,
        );
      } else {
        // Fallback if transaction history service is not available
        print('Warning: TransactionHistoryService not available, fine transaction not recorded');
      }
    } catch (e) {
      print('Error creating fine transaction: $e');
      rethrow;
    }
  }

  /// Get charging session by ID
  Future<ChargingSession?> getChargingSession(String sessionId) async {
    try {
      final doc =
          await _firestore.collection('charging_sessions').doc(sessionId).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return ChargingSession.fromMap(data);
      }
      return null;
    } catch (e) {
      print('Error getting charging session: $e');
      return null;
    }
  }

  /// Update charging session status to completed
  Future<void> markSessionCompleted({
    required String sessionId,
    required DateTime endTime,
    required double energyConsumed,
    required double amount,
  }) async {
    try {
      await _firestore.collection('charging_sessions').doc(sessionId).update({
        'end_time': Timestamp.fromDate(endTime),
        'energy_consumed': energyConsumed,
        'amount': amount,
        'status': 'completed',
        'updated_at': Timestamp.now(),
      });
      
      notifyListeners();
    } catch (e) {
      print('Error marking session as completed: $e');
      rethrow;
    }
  }

  /// Get all charging sessions with fines for a user
  Future<List<ChargingSession>> getUserSessionsWithFines(String userId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('charging_sessions')
              .where('user_id', isEqualTo: userId)
              .where('fine_amount', isGreaterThan: 0)
              .orderBy('fine_amount')
              .orderBy('start_time', descending: true)
              .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ChargingSession.fromMap(data);
      }).toList();
    } catch (e) {
      print('Error getting user sessions with fines: $e');
      return [];
    }
  }

  /// Get total fine amount for a user
  Future<double> getUserTotalFines(String userId) async {
    try {
      final sessions = await getUserSessionsWithFines(userId);
      return sessions.fold<double>(
        0.0,
        (total, session) => total + (session.fineAmount ?? 0.0),
      );
    } catch (e) {
      print('Error calculating user total fines: $e');
      return 0.0;
    }
  }

  /// Check if a user has any unpaid fines
  Future<bool> hasUnpaidFines(String userId) async {
    try {
      final totalFines = await getUserTotalFines(userId);
      return totalFines > 0;
    } catch (e) {
      print('Error checking unpaid fines: $e');
      return false;
    }
  }

  /// Get fine amount for a specific reservation
  Future<double> getFineForReservation(String reservationId) async {
    try {
      final querySnapshot = await _firestore
          .collection('charging_sessions')
          .where('reservation_id', isEqualTo: reservationId)
          .where('fine_amount', isGreaterThan: 0)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        return (data['fine_amount'] as num?)?.toDouble() ?? 0.0;
      }
      
      return 0.0;
    } catch (e) {
      print('Error getting fine for reservation: $e');
      return 0.0;
    }
  }

  /// Get fine statistics for admin
  Future<Map<String, dynamic>> getFineStatistics() async {
    try {
      final querySnapshot =
          await _firestore
              .collection('charging_sessions')
              .where('fine_amount', isGreaterThan: 0)
              .get();

      double totalFines = 0.0;
      int totalSessions = querySnapshot.docs.length;
      Map<String, int> finesByUser = {};

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final fineAmount = data['fine_amount'] ?? 0.0;
        final userId = data['user_id'] ?? '';

        totalFines += fineAmount;
        finesByUser[userId] = (finesByUser[userId] ?? 0) + 1;
      }

      return {
        'total_fines': totalFines,
        'total_sessions_with_fines': totalSessions,
        'average_fine': totalSessions > 0 ? totalFines / totalSessions : 0.0,
        'fines_by_user': finesByUser,
      };
    } catch (e) {
      print('Error getting fine statistics: $e');
      return {
        'total_fines': 0.0,
        'total_sessions_with_fines': 0,
        'average_fine': 0.0,
        'fines_by_user': {},
      };
    }
  }
}