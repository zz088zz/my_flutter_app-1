import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/charger.dart';
import '../models/payment_method.dart';
import '../models/voucher.dart';
import '../services/wallet_service.dart';
import '../services/payment_service.dart';
import '../services/auth_service.dart';
import '../services/station_service.dart';
import '../services/reward_service.dart';
import 'payment_receipt_screen.dart';
import 'dart:math' as Math;

class PaymentMethodsScreen extends StatefulWidget {
  final Reservation reservation;
  final ChargingStation station;
  final Charger charger;
  final bool isDepositPayment;
  final double depositAmount;
  final double fineAmount;

  const PaymentMethodsScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.charger,
    this.isDepositPayment = false,
    this.depositAmount = 30.0,
    this.fineAmount = 0.0,
  }) : super(key: key);

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  String? _selectedPaymentMethod;
  PaymentMethod? _selectedCard;
  bool _isLoading = true;
  double _walletBalance = 0.0;
  bool _isProcessing = false;
  List<Voucher> _availableVouchers = [];
  Voucher? _selectedVoucher;
  final TextEditingController _voucherCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id ?? '1';

      final paymentService = Provider.of<PaymentService>(
        context,
        listen: false,
      );
      await paymentService.loadUserPaymentMethods(userId);

      final walletService = Provider.of<WalletService>(context, listen: false);
      await walletService.loadWalletForUser(userId);
      _walletBalance = walletService.balance;
      print('Payment screen loaded with wallet balance: $_walletBalance');

      // Load available vouchers (exclude deposit payments)
      if (!widget.isDepositPayment) {
        final rewardService = Provider.of<RewardService>(
          context,
          listen: false,
        );
        await rewardService.loadUserRewards(userId);
        _availableVouchers =
            rewardService.vouchers.where((v) => v.isActive).toList();
        print('Loaded ${_availableVouchers.length} available vouchers');
      }
    } catch (e) {
      print('Error loading payment data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddCardBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: const AddCardBottomSheet(),
          ),
    ).then((_) => _loadData());
  }

  Future<void> _applyVoucherByCode() async {
    final code = _voucherCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a voucher code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final rewardService = Provider.of<RewardService>(context, listen: false);
      final userId = authService.currentUser?.id ?? '1';

      final voucher = await rewardService.getVoucherByCode(code);
      if (voucher != null && voucher.isActive) {
        setState(() {
          _selectedVoucher = voucher;
          _voucherCodeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Voucher applied! RM${voucher.discountAmount.toStringAsFixed(0)} discount',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or expired voucher code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error applying voucher: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeVoucher() {
    setState(() {
      _selectedVoucher = null;
    });
  }

  double _calculateTotalAmount() {
    if (widget.isDepositPayment) {
      return 30.0;
    } else {
      final double pricePerKWh =
          widget.charger.type.contains('DC') ? 1.30 : 0.80;
      final energyConsumed =
          widget.charger.power * (widget.reservation.duration / 60.0);
      final chargingFee = double.parse(
        (energyConsumed * pricePerKWh).toStringAsFixed(2),
      );
      // Include fine amount in the total calculation
      return double.parse(
        (chargingFee + widget.fineAmount - widget.depositAmount).toStringAsFixed(2),
      );
    }
  }

  double _calculateDiscountedAmount() {
    if (_selectedVoucher == null) return _calculateTotalAmount();
    final totalAmount = _calculateTotalAmount();
    final discount = _selectedVoucher!.discountAmount;
    return Math.max(0, totalAmount - discount);
  }

  void _processPayment() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final stationService = Provider.of<StationService>(
        context,
        listen: false,
      );

      // EMERGENCY FIX: DIRECTLY HANDLE DEPOSIT PAYMENT
      if (widget.isDepositPayment) {
        print('EMERGENCY FIX: Deposit payment detected');

        // ALWAYS use EXACTLY RM 30.0 for deposit - fixed value for consistency
        const double FIXED_DEPOSIT_AMOUNT = 30.0;
        final double totalFee = FIXED_DEPOSIT_AMOUNT; // Use this for tracking

        // Handle wallet payment for deposit
        if (_selectedPaymentMethod == 'wallet') {
          final walletService = Provider.of<WalletService>(
            context,
            listen: false,
          );
          final authService = Provider.of<AuthService>(context, listen: false);
          final userId = authService.currentUser?.id ?? '1';

          print(
            'Deposit payment using wallet, current balance: $_walletBalance',
          );

          if (_walletBalance < FIXED_DEPOSIT_AMOUNT) {
            throw Exception('Insufficient wallet balance for deposit');
          }

          print(
            'Deducting FIXED amount of RM $FIXED_DEPOSIT_AMOUNT for deposit',
          );

          // Direct wallet deduction with the fixed amount
          final deductSuccess = await walletService.deductFromWallet(
            userId,
            FIXED_DEPOSIT_AMOUNT,
            'Payment for reservation deposit',
          );

          if (!deductSuccess) {
            throw Exception(
              'Failed to deduct deposit from wallet. Please try again.',
            );
          }

          // Reload wallet data to update UI
          await walletService.loadWalletForUser(userId);
          _walletBalance = walletService.balance;
          print(
            'After deposit deduction - Updated wallet balance: $_walletBalance',
          );
        } else {
          // For card payment, no wallet deduction needed
          print(
            'Deposit payment using card: ${_selectedCard?.cardType} ending in ${_selectedCard?.lastFourDigits}',
          );
        }

        // Create reservation with the fixed deposit amount
        Reservation processedReservation = widget.reservation.copyWith(
          paymentMethodId:
              _selectedPaymentMethod == 'wallet'
                  ? '0' // For wallet
                  : _selectedCard?.id ?? '0',
          deposit: FIXED_DEPOSIT_AMOUNT, // Set the fixed deposit amount
        );

        print(
          'Creating reservation with fixed deposit: ${processedReservation.toMap()}',
        );

        // Create the reservation
        final createdReservation = await stationService.createReservation(
          processedReservation,
        );

        if (createdReservation == null) {
          throw Exception('Failed to create reservation with fixed deposit');
        }

        // Force a charger availability update to show it as unavailable
        if (createdReservation.chargerId != null) {
          print(
            'Setting charger ${createdReservation.chargerId} to unavailable',
          );
          await stationService.updateChargerAvailability(
            createdReservation.stationId,
            createdReservation.chargerId!,
            false,
          );
        }

        // Reload stations to refresh available slots
        await stationService.loadStations();

        if (!mounted) return;

        // Navigate to payment receipt screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder:
                (context) => PaymentReceiptScreen(
                  station: widget.station,
                  amount: FIXED_DEPOSIT_AMOUNT, // Use fixed deposit amount
                  energyConsumed: 0,
                  chargingDuration: widget.reservation.duration,
                  paymentMethod:
                      _selectedPaymentMethod == 'wallet'
                          ? 'E-Wallet'
                          : '${_selectedCard?.cardType} *${_selectedCard?.lastFourDigits}',
                  cardId: _selectedCard?.id,
                  reservationId: createdReservation.id ?? '0',
                  chargerType:
                      widget.charger.type == 'DC' &&
                              widget.charger.power >= 49 &&
                              widget.charger.power < 51
                          ? 'DC 50kW'
                          : '${widget.charger.type} ${widget.charger.power.round()}kW',
                  chargerName: widget.charger.name,
                  isDepositPayment: true,
                  fineAmount: widget.fineAmount, // Pass the fine amount
                ),
          ),
          (route) => false, // Clear all previous routes
        );

        return; // Exit early, skip the rest of the process
      }

      // NORMAL FLOW (Non-deposit payment or card payment)
      // Continue with the existing code...

      // IMPORTANT: Skip this entire section for deposit payments as they are already handled above
      // Deposit payments should use the EMERGENCY FIX code path above and return early
      if (widget.isDepositPayment) {
        // This code should never be reached for deposit payments
        print(
          'WARNING: Normal flow code reached for deposit payment - this should not happen!',
        );
        print(
          'This is the source of the double deduction bug. Exiting to prevent double charges.',
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // DEBUGGING: Print all relevant deposit values
      print('DEBUG DEPOSIT VALUES:');
      print('  widget.isDepositPayment: ${widget.isDepositPayment}');
      print('  widget.depositAmount: ${widget.depositAmount}');
      print('  widget.reservation.deposit: ${widget.reservation.deposit}');

      // Update the reservation with the selected payment method
      Reservation processedReservation = widget.reservation.copyWith(
        paymentMethodId:
            _selectedPaymentMethod == 'wallet'
                ? '0' // Special ID for wallet
                : _selectedCard?.id ?? '0',
      );

      print(
        'Creating reservation with payment method: ${processedReservation.paymentMethodId}',
      );
      print('Reservation details: ${processedReservation.toMap()}');

      // For non-deposit payments, calculate the amount based on charging session
      final double amountToDeduct;
      // Define totalFee for refund check
      double totalFee = 0.0;

      // At this point, we've already confirmed this is NOT a deposit payment
      // Use the same calculation as in the build method and payment summary screen
      final double originalAmount = _calculateTotalAmount();
      final double discountedAmount = _calculateDiscountedAmount();

      // Calculate total with the same rounding approach
      // Check if this is a refund situation (discountedAmount < deposit)
      totalFee = double.parse(
        (discountedAmount - widget.depositAmount).toStringAsFixed(2),
      );

      // Keep the original total fee for refund check
      final bool shouldRefund = totalFee < 0;

      // If total fee is negative, this should be a refund, not a deduction
      amountToDeduct = Math.max(0.0, totalFee); // Never deduct negative amounts

      print(
        'DEBUG: originalAmount=$originalAmount, discountedAmount=$discountedAmount, deposit=${widget.depositAmount}, totalFee=$totalFee, finalAmount=$amountToDeduct, shouldRefund=$shouldRefund',
      );

      if (_selectedVoucher != null) {
        print(
          'Applied voucher: ${_selectedVoucher!.code} with ${_selectedVoucher!.discountPercentage}% discount',
        );
      }

      // Determine if this is a refund situation based on the original calculation
      final isRefund = totalFee < 0;

      print('Payment calculation:');
      print('Duration: ${widget.reservation.duration}');
      print('Original amount: $originalAmount');
      print('Discounted amount: $discountedAmount');
      print('Final amount to deduct: $amountToDeduct');
      print('Is refund: $isRefund');

      // Handle wallet payment for non-deposit cases
      if (_selectedPaymentMethod == 'wallet') {
        final walletService = Provider.of<WalletService>(
          context,
          listen: false,
        );
        final authService = Provider.of<AuthService>(context, listen: false);
        final userId = authService.currentUser?.id ?? '1';

        if (isRefund) {
          // This is a refund situation - add to wallet instead of deducting
          final refundAmount =
              totalFee.abs(); // Use the original total fee amount
          print(
            'Processing refund of ${refundAmount.toStringAsFixed(2)} to wallet with current balance: $_walletBalance',
          );

          final refundSuccess = await walletService.topUpWallet(
            userId,
            refundAmount,
            'Refund for charging session at ${widget.station.name}',
          );

          if (!refundSuccess) {
            throw Exception('Failed to process refund. Please try again.');
          }

          // Reload wallet data to update UI
          await walletService.loadWalletForUser(userId);
          _walletBalance = walletService.balance;
          print('After refund - Updated wallet balance: $_walletBalance');
        } else if (amountToDeduct > 0) {
          // Only process payment if there's an actual amount to deduct
          // Normal payment - check balance and deduct
          if (_walletBalance < amountToDeduct) {
            print(
              'ERROR: Insufficient balance: $_walletBalance < $amountToDeduct',
            );
            throw Exception(
              'Insufficient wallet balance. You need RM${amountToDeduct.toStringAsFixed(2)} but have RM${_walletBalance.toStringAsFixed(2)}',
            );
          }

          print(
            'Before deduction - Wallet balance: $_walletBalance, deducting: $amountToDeduct',
          );

          // Deduct from wallet - use the positive amount
          final deductSuccess = await walletService.deductFromWallet(
            userId,
            amountToDeduct,
            'Payment for ${widget.isDepositPayment ? "reservation deposit" : "charging session"}',
          );

          if (!deductSuccess) {
            throw Exception('Failed to deduct from wallet. Please try again.');
          }

          // Reload wallet data to update UI
          await walletService.loadWalletForUser(userId);
          _walletBalance = walletService.balance;
          print('After deduction - Updated wallet balance: $_walletBalance');
        } else {
          // Zero amount edge case - nothing to do
          print('Payment amount is zero - no wallet transaction needed');
        }
      }

      // For all payment types, create the reservation
      Reservation? createdReservation;
      if (widget.isDepositPayment) {
        // Create a new reservation
        createdReservation = await stationService.createReservation(
          processedReservation,
        );

        // Double check the reservation was created
        if (createdReservation == null) {
          print('WARNING: stationService.createReservation returned null');

          // Direct fallback creation
          // This part of the code was removed as per the edit hint.
          // If Firestore integration is required, this logic needs to be re-evaluated.
          // For now, we'll assume the original logic for non-deposit payments
          // will handle the creation if stationService.createReservation fails.
          // If stationService.createReservation is truly the only way to create a reservation,
          // this block will need to be re-implemented using Firestore.
          // For now, we'll just proceed with the original logic, which might fail
          // if stationService.createReservation is not available.
          // The original code had a try-catch block for emergency DB insertion,
          // but that block was removed.
          // The original code also had a check for `createdReservation == null`
          // and then attempted to create a new Reservation object.
          // This part of the logic is now effectively removed as per the edit hint.
          // The original code had a `dbHelper` and `db` reference, which is removed.
          // The `insertMap` and `insertedId` were also removed.
          // The `charger` update was also removed.
          // The `createdReservation` object was then created directly.
          // This means the emergency fallback for `createdReservation == null`
          // is now effectively removed.
          // The original code had a `dbHelper` and `db` reference, which is removed.
          // The `insertMap` and `insertedId` were also removed.
          // The `charger` update was also removed.
          // The `createdReservation` object was then created directly.
          // This means the emergency fallback for `createdReservation == null`
          // is now effectively removed.
        }
      } else {
        // For non-deposit payment, update the existing reservation with complete details
        // Calculate energy consumed for the completed session
        final double energyConsumed =
            widget.charger.power * (widget.reservation.duration / 60.0);

        // Update reservation status to completed with additional details
        await FirebaseFirestore.instance
            .collection('reservations')
            .doc(processedReservation.id!)
            .update({
              'status': 'completed',
              'completed_at': Timestamp.now(),
              'energy_consumed': energyConsumed,
              'actual_duration': widget.reservation.duration,
            });

        // Also update charger availability
        if (processedReservation.chargerId != null) {
          await stationService.updateChargerAvailability(
            processedReservation.stationId,
            processedReservation.chargerId!,
            true, // Set charger as available
          );
        }

        createdReservation = processedReservation;
      }

      if (createdReservation == null) {
        throw Exception('Failed to create reservation');
      }

      // Force a charger availability update to show it as unavailable
      if (widget.isDepositPayment && createdReservation.chargerId != null) {
        print('Setting charger ${createdReservation.chargerId} to unavailable');
        await stationService.updateChargerAvailability(
          createdReservation.stationId,
          createdReservation.chargerId!,
          false,
        );
      }

      // Reload stations to refresh available slots
      await stationService.loadStations();

      // Mark voucher as used if one was applied
      if (_selectedVoucher != null && !widget.isDepositPayment) {
        try {
          final rewardService = RewardService();
          await rewardService.markVoucherAsUsed(_selectedVoucher!.id!);
          print(
            'Voucher ${_selectedVoucher!.code} marked as used successfully',
          );
        } catch (e) {
          print('Error marking voucher as used: $e');
          // Don't fail the payment if voucher marking fails
        }
      }

      if (!mounted) return;

      // Navigate to payment receipt screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder:
              (context) => PaymentReceiptScreen(
                station: widget.station,
                amount:
                    amountToDeduct, // Always use the totalFee calculation we just did
                energyConsumed:
                    widget.isDepositPayment
                        ? 0
                        : widget.charger.power *
                            (widget.reservation.duration / 60.0),
                chargingDuration: widget.reservation.duration,
                paymentMethod:
                    _selectedPaymentMethod == 'wallet'
                        ? 'E-Wallet'
                        : '${_selectedCard?.cardType} *${_selectedCard?.lastFourDigits}',
                cardId: _selectedCard?.id,
                reservationId: createdReservation?.id ?? '0',
                chargerType:
                    widget.charger.type == 'DC' &&
                            widget.charger.power >= 49 &&
                            widget.charger.power < 51
                        ? 'DC 50kW'
                        : '${widget.charger.type} ${widget.charger.power.round()}kW',
                chargerName: widget.charger.name,
                isDepositPayment: widget.isDepositPayment,
                fineAmount: widget.fineAmount, // Pass the fine amount
              ),
        ),
        (route) => false, // Clear all previous routes
      );
    } catch (e) {
      print('Error processing payment: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));

      setState(() {
        _isProcessing = false;
      });
    }
  }

  Widget _buildPaymentMethodItem({
    required String title,
    required String subtitle,
    required Widget icon,
    required String value,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected
                  ? Theme.of(context).primaryColor.withOpacity(0.05)
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedPaymentMethod,
              onChanged: (value) {
                if (onTap != null) onTap();
              },
              activeColor: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double originalAmount = _calculateTotalAmount();
    final double displayAmount = _calculateDiscountedAmount();
    final isRefund = displayAmount < 0;

    print('PAYMENT METHODS SCREEN CALCULATION:');
    print('  isDepositPayment=${widget.isDepositPayment}');
    print('  FIXED deposit amount: 30.0');
    print('  Display Amount: $displayAmount');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          widget.isDepositPayment ? 'Pay Deposit' : 'Select Payment Method',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Fee information section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      color: Colors.white,
                      child: Column(
                        children: [
                          Text(
                            widget.isDepositPayment
                                ? 'Deposit Amount'
                                : 'Total Amount',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Display the amount with appropriate formatting
                          Text(
                            isRefund
                                ? 'RM ${displayAmount.abs().toStringAsFixed(2)} (Refund)'
                                : 'RM ${displayAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color:
                                  isRefund
                                      ? Colors.green
                                      : Theme.of(context).primaryColor,
                            ),
                          ),
                          if (widget.isDepositPayment) ...[
                            const SizedBox(height: 8),
                            Text(
                              '80% refundable if cancelled',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Voucher section (only for non-deposit payments)
                    if (!widget.isDepositPayment) ...[
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_offer,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Apply Voucher',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (_selectedVoucher != null) ...[
                              // Applied voucher display
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'RM${_selectedVoucher!.discountAmount.toStringAsFixed(0)} Discount Applied',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Text(
                                            'Code: ${_selectedVoucher!.code}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _removeVoucher,
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Show original vs discounted amount
                              if (_selectedVoucher != null &&
                                  originalAmount != displayAmount) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Original Amount:'),
                                    Text(
                                      'RM${originalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Discounted Amount:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'RM${displayAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ] else ...[
                              // Voucher input section
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _voucherCodeController,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter voucher code',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _applyVoucherByCode,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Apply'),
                                  ),
                                ],
                              ),

                              // Available vouchers
                              if (_availableVouchers.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'Available Vouchers:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._availableVouchers.map(
                                  (voucher) => GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedVoucher = voucher;
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.confirmation_number,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'RM${voucher.discountAmount.toStringAsFixed(0)} off - ${voucher.code}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 12,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Payment methods list
                    Container(
                      height: 450, // Fixed height instead of Expanded
                      padding: const EdgeInsets.all(16),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 0),
                        children: [
                          // E-Wallet
                          _buildPaymentMethodItem(
                            title: 'E-Wallet',
                            subtitle:
                                'Balance: RM ${_walletBalance.toStringAsFixed(2)}',
                            icon: Image.asset(
                              'assets/images/e_wallet_icon.png',
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.account_balance_wallet,
                                  color: Colors.blue[600],
                                  size: 20,
                                );
                              },
                            ),
                            value: 'wallet',
                            selected: _selectedPaymentMethod == 'wallet',
                            onTap: () {
                              setState(() {
                                _selectedPaymentMethod = 'wallet';
                                _selectedCard = null;
                              });
                            },
                          ),

                          // Saved Cards Section
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 0,
                              top: 24,
                              bottom: 8,
                            ),
                            child: Text(
                              'Saved Cards',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                          if (context
                              .watch<PaymentService>()
                              .paymentMethods
                              .isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 0),
                              child: Text(
                                'No saved cards',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else
                            ...context.watch<PaymentService>().paymentMethods.map((
                              card,
                            ) {
                              return _buildPaymentMethodItem(
                                title: card.cardType,
                                subtitle: '**** ${card.lastFourDigits}',
                                icon: Image.asset(
                                  'assets/images/${card.cardType.toLowerCase()}_icon.png',
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.credit_card,
                                      color: Colors.grey[700],
                                      size: 20,
                                    );
                                  },
                                ),
                                value: 'card_${card.id}',
                                selected:
                                    _selectedPaymentMethod == 'card_${card.id}',
                                onTap: () {
                                  setState(() {
                                    _selectedPaymentMethod = 'card_${card.id}';
                                    _selectedCard = card;
                                  });
                                },
                              );
                            }).toList(),

                          // Mobile Payment Options
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 0,
                              top: 24,
                              bottom: 8,
                            ),
                            child: Text(
                              'Mobile Payment',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),

                          // Apple Pay
                          _buildPaymentMethodItem(
                            title: 'Apple Pay',
                            subtitle: 'Pay using Apple Pay',
                            icon: const Icon(
                              Icons.apple,
                              color: Colors.black,
                              size: 20,
                            ),
                            value: 'apple_pay',
                            selected: _selectedPaymentMethod == 'apple_pay',
                            onTap: () {
                              setState(() {
                                _selectedPaymentMethod = 'apple_pay';
                                _selectedCard = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Pay Button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: ElevatedButton(
                        onPressed:
                            _selectedPaymentMethod != null
                                ? () {
                                  _processPayment();
                                }
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: const Text(
                          'Pay Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class AddCardBottomSheet extends StatefulWidget {
  const AddCardBottomSheet({Key? key}) : super(key: key);

  @override
  State<AddCardBottomSheet> createState() => _AddCardBottomSheetState();
}

class _AddCardBottomSheetState extends State<AddCardBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardholderNameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _cvvController = TextEditingController();
  bool _isDefault = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _cardholderNameController.dispose();
    _cardNumberController.dispose();
    _expiryDateController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  String _formatCardNumber(String text) {
    text = text.replaceAll(' ', '');
    if (text.length > 16) text = text.substring(0, 16);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  // Helper method to format expiry date
  String _formatExpiryDate(String text) {
    // Remove any existing slashes
    text = text.replaceAll('/', '');

    // Limit to 4 digits
    if (text.length > 4) {
      text = text.substring(0, 4);
    }

    // Add slash after 2 digits
    if (text.length >= 2) {
      return '${text.substring(0, 2)}/${text.substring(2)}';
    }

    return text;
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final expiryDate = _expiryDateController.text;
      final cvv = _cvvController.text;
      final holderName = _cardholderNameController.text.trim();

      // Check for duplicate card number
      final existingCards = context.read<PaymentService>().paymentMethods;
      final isDuplicate = existingCards.any(
        (card) => card.cardNumber.replaceAll(' ', '') == cardNumber,
      );

      if (isDuplicate) {
        // Show dialog instead of SnackBar so it's visible above the bottom sheet
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Duplicate Card'),
              content: const Text(
                'This card is already saved in your account.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }

      // Determine card type based on number
      String cardType = 'Unknown';
      if (cardNumber.startsWith('4')) {
        cardType = 'Visa';
      } else if (cardNumber.startsWith('5')) {
        cardType = 'Mastercard';
      } else if (cardNumber.startsWith('3')) {
        cardType = 'American Express';
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      final paymentService = Provider.of<PaymentService>(
        context,
        listen: false,
      );

      final userId = authService.currentUser?.id ?? '1';

      final newPaymentMethod = PaymentMethod(
        userId: userId,
        cardType: cardType,
        cardNumber: cardNumber,
        expiryDate: expiryDate,
        holderName: holderName,
        isDefault: _isDefault,
        lastFourDigits: cardNumber.substring(cardNumber.length - 4),
      );

      final result = await paymentService.addPaymentMethod(newPaymentMethod);

      if (result != null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card added successfully')),
        );
      } else {
        throw Exception('Failed to add card');
      }
    } catch (e) {
      print('Error adding card: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showExpiryDatePicker(BuildContext context) {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    int selectedMonth = currentMonth;
    int selectedYear = currentYear;

    // If there's already a value, parse it
    if (_expiryDateController.text.isNotEmpty) {
      final parts = _expiryDateController.text.split('/');
      if (parts.length == 2) {
        selectedMonth = int.tryParse(parts[0]) ?? currentMonth;
        selectedYear = 2000 + (int.tryParse(parts[1]) ?? (currentYear % 100));
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Select Expiry Date',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: Container(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    // Month Selection
                    const Text(
                      'Month',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final isSelected = month == selectedMonth;
                          final monthNames = [
                            'Jan',
                            'Feb',
                            'Mar',
                            'Apr',
                            'May',
                            'Jun',
                            'Jul',
                            'Aug',
                            'Sep',
                            'Oct',
                            'Nov',
                            'Dec',
                          ];

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedMonth = month;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey[300]!,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  monthNames[index],
                                  style: TextStyle(
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.black,
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Year Selection
                    const Text(
                      'Year',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              childAspectRatio: 1.5,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: 15, // Show next 15 years
                        itemBuilder: (context, index) {
                          final year = currentYear + index;
                          final isSelected = year == selectedYear;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedYear = year;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey[300]!,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  (year % 100).toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.black,
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validate the selected date
                    if (selectedYear < currentYear ||
                        (selectedYear == currentYear &&
                            selectedMonth < currentMonth)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a future date'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Format and set the date
                    final formattedDate =
                        '${selectedMonth.toString().padLeft(2, '0')}/${(selectedYear % 100).toString().padLeft(2, '0')}';
                    _expiryDateController.text = formattedDate;
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: const Text(
                    'Select',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add New Card',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Card Holder Name
              const Text(
                "Card Holder's Name",
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cardholderNameController,
                decoration: InputDecoration(
                  hintText: 'Enter name on card',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter card holder name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Card Number
              const Text(
                'Card Number',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cardNumberController,
                decoration: InputDecoration(
                  hintText: '4848 1000 8876 1115',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: const Icon(Icons.credit_card),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final formatted = _formatCardNumber(value);
                  if (formatted != value) {
                    _cardNumberController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter card number';
                  }
                  final cleanNumber = value.replaceAll(' ', '');
                  if (cleanNumber.length < 16) {
                    return 'Invalid card number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Expiry Date and CVV
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expiry Date',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _expiryDateController,
                          decoration: InputDecoration(
                            hintText: 'MM/YY',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today, size: 20),
                              onPressed: () => _showExpiryDatePicker(context),
                              tooltip: 'Select date',
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final formatted = _formatExpiryDate(value);
                            if (formatted != value) {
                              _expiryDateController.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
                              return 'Use MM/YY format';
                            }

                            // Check validity
                            final parts = value.split('/');
                            try {
                              final month = int.parse(parts[0]);
                              final year = int.parse(parts[1]);
                              final now = DateTime.now();
                              final currentYear = now.year % 100;
                              final currentMonth = now.month;

                              if (month < 1 || month > 12) {
                                return 'Invalid month';
                              }

                              if (year < currentYear ||
                                  (year == currentYear &&
                                      month < currentMonth)) {
                                return 'Card expired';
                              }
                            } catch (e) {
                              return 'Invalid date';
                            }

                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CVV',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cvvController,
                          decoration: InputDecoration(
                            hintText: '123',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            helperText: 'Last 3-4 digits on back',
                            helperStyle: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            if (value.length < 3) {
                              return 'Invalid CVV';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Default Payment Method
              Row(
                children: [
                  Checkbox(
                    value: _isDefault,
                    onChanged: (value) {
                      setState(() {
                        _isDefault = value ?? false;
                      });
                    },
                    activeColor: Theme.of(context).primaryColor,
                  ),
                  const Text('Set as default payment method'),
                ],
              ),
              const SizedBox(height: 24),

              // Add Card Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveCard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'Add Card',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
