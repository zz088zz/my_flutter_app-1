import 'package:flutter/material.dart';
import '../models/reservation.dart';
import '../services/wallet_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RefundService with ChangeNotifier {
  final WalletService _walletService;
  
  RefundService(this._walletService);
  
  /// Process refund for cancelled reservation (80% of deposit)
  Future<bool> processCancellationRefund(Reservation reservation, String userId) async {
    try {
      if (reservation.deposit <= 0) {
        print('No deposit to refund for reservation ${reservation.id}');
        return true; // No refund needed
      }
      
      // Calculate 80% of deposit
      final refundAmount = reservation.deposit * 0.8;
      
      print('Processing 80% refund for cancelled reservation: RM ${refundAmount.toStringAsFixed(2)}');
      
      // Get station name for better description
      String stationName = 'Unknown Station';
      try {
        final stationDoc = await FirebaseFirestore.instance
            .collection('charging_stations')
            .doc(reservation.stationId)
            .get();
        if (stationDoc.exists && stationDoc.data() != null) {
          stationName = stationDoc.data()!['name'] ?? 'Unknown Station';
        }
      } catch (e) {
        print('Error getting station name: $e');
      }
      
      // Add refund to wallet
      final refundSuccess = await _walletService.topUpWallet(
        userId,
        refundAmount,
        '80% refund for cancelled reservation at $stationName',
      );
      
      if (refundSuccess) {
        print('Successfully refunded RM ${refundAmount.toStringAsFixed(2)} to wallet');
        
        // Update reservation status to cancelled
        if (reservation.id != null) {
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(reservation.id)
              .update({
                'status': 'cancelled',
                'refund_amount': refundAmount,
                'refunded_at': DateTime.now().toIso8601String(),
              });
        }
        
        return true;
      } else {
        print('Failed to process refund for cancelled reservation');
        return false;
      }
    } catch (e) {
      print('Error processing cancellation refund: $e');
      return false;
    }
  }
  
  /// Process refund for overpayment (when charging fee < deposit)
  Future<bool> processOverpaymentRefund(
    String userId, 
    double refundAmount, 
    String stationName,
    String reservationId,
    {double? fineAmount, int? overtimeMinutes, int? gracePeriodMinutes, String? sessionId}
  ) async {
    try {
      if (refundAmount <= 0) {
        print('No refund amount to process');
        return true; // No refund needed
      }
      
      print('Processing overpayment refund: RM ${refundAmount.toStringAsFixed(2)}');
      
      // Add refund to wallet
      final refundSuccess = await _walletService.topUpWallet(
        userId,
        refundAmount,
        'Refund for charging session at $stationName',
        fineAmount: fineAmount,
        overtimeMinutes: overtimeMinutes,
        gracePeriodMinutes: gracePeriodMinutes,
        sessionId: sessionId,
      );
      
      if (refundSuccess) {
        print('Successfully refunded RM ${refundAmount.toStringAsFixed(2)} to wallet');
        
        // Update reservation with refund information
        await FirebaseFirestore.instance
            .collection('reservations')
            .doc(reservationId)
            .update({
              'refund_amount': refundAmount,
              'refunded_at': DateTime.now().toIso8601String(),
            });
        
        return true;
      } else {
        print('Failed to process overpayment refund');
        return false;
      }
    } catch (e) {
      print('Error processing overpayment refund: $e');
      return false;
    }
  }
  
  /// Check if a reservation has already been refunded
  Future<bool> isReservationRefunded(String reservationId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return data['refunded_at'] != null;
      }
      
      return false;
    } catch (e) {
      print('Error checking refund status: $e');
      return false;
    }
  }
  
  /// Get refund amount for a reservation
  Future<double> getRefundAmount(String reservationId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return (data['refund_amount'] as num?)?.toDouble() ?? 0.0;
      }
      
      return 0.0;
    } catch (e) {
      print('Error getting refund amount: $e');
      return 0.0;
    }
  }
}