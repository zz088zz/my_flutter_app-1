import 'package:flutter/material.dart';
import '../models/charging_station.dart';
import '../services/payment_service.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../main.dart' as app_main;
import '../services/station_service.dart';
import '../models/payment_method.dart';
import '../services/wallet_service.dart';
import '../services/reward_service.dart';
import '../services/fine_service.dart';
import '../screens/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction.dart' as AppTransaction;

class PaymentReceiptScreen extends StatefulWidget {
  final ChargingStation station;
  final double amount;
  final double energyConsumed;
  final int chargingDuration;
  final String paymentMethod;
  final String? cardId;
  final String? reservationId;
  final String? chargerType;
  final String? chargerName;
  final bool isDepositPayment;
  final double fineAmount;

  const PaymentReceiptScreen({
    Key? key,
    required this.station,
    required this.amount,
    required this.energyConsumed,
    required this.chargingDuration,
    required this.paymentMethod,
    this.cardId,
    this.reservationId,
    this.chargerType,
    this.chargerName,
    this.isDepositPayment = false,
    this.fineAmount = 0.0,
  }) : super(key: key);

  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
  final PaymentService _paymentService = PaymentService();
  final WalletService _walletService = WalletService();
  final RewardService _rewardService = RewardService();
  final FineService _fineService = FineService();
  bool _processedReservation = false;
  PaymentMethod? _paymentCard;
  Map<String, dynamic>? reservationData;
  bool _isLoading = true;
  // Add a flag to track if a charging session has been created
  bool _chargingSessionCreated = false;
  // Add a variable to store the final energy value
  double _finalEnergyValue = 0.0;

  @override
  void initState() {
    super.initState();
    _checkForExistingChargingSession();
    _markReservationCompleted();
    _loadCardDetails();
    _processPayment();

    // Delay verification to ensure DB operations complete
    Future.delayed(const Duration(seconds: 1), () {
      _verifyReservation();
    });
  }

  Future<void> _markReservationCompleted() async {
    if (widget.reservationId != null && !_processedReservation) {
      try {
        // Get the station service
        final stationService = Provider.of<StationService>(
          context,
          listen: false,
        );
        final authService = Provider.of<AuthService>(context, listen: false);

        // Update reservation status in database
        final newStatus = widget.isDepositPayment ? 'confirmed' : 'completed';
        print(
          'Updating reservation ${widget.reservationId} to status: $newStatus',
        );

        // Force direct update
        final db = await FirebaseFirestore.instance
            .collection('reservations')
            .doc(widget.reservationId)
            .update({'status': newStatus});

        // Double check and ensure the status is actually updated
        final checkResult =
            await FirebaseFirestore.instance
                .collection('reservations')
                .doc(widget.reservationId)
                .get();
        if (checkResult.data() == null) {
          print(
            'CRITICAL ERROR: Reservation ${widget.reservationId} not found after status update',
          );

          // Create a new reservation if it doesn't exist
          if (widget.isDepositPayment && authService.currentUser != null) {
            // We need to create a new reservation
            final db = await FirebaseFirestore.instance
                .collection('reservations')
                .doc(widget.reservationId);

            // Get charger ID from the station data
            String? chargerId;
            if (widget.chargerName != null && widget.station.id != null) {
              // Find charger in station by name
              for (final charger in widget.station.chargers) {
                if (charger.name == widget.chargerName) {
                  chargerId = charger.id;
                  break;
                }
              }
            }

            // If no charger found by name, just use the first charger
            if (chargerId == null && widget.station.chargers.isNotEmpty) {
              chargerId = widget.station.chargers.first.id;
            }

            if (chargerId != null) {
              // Get vehicle ID
              String vehicleId = '1'; // Default fallback
              final vehicles =
                  await FirebaseFirestore.instance
                      .collection('vehicles')
                      .where('user_id', isEqualTo: authService.currentUser!.id)
                      .get();
              if (vehicles.docs.isNotEmpty) {
                vehicleId = vehicles.docs.first.data()['id'] as String;
              }

              // Insert the reservation
              await db.set({
                'id': widget.reservationId,
                'user_id': authService.currentUser!.id!,
                'station_id': widget.station.id,
                'vehicle_id': vehicleId,
                'payment_method_id':
                    widget.cardId ?? '1', // Use provided card ID or default
                'charger_id': chargerId,
                'start_time':
                    DateTime.now()
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                'duration': 60, // 60 minutes
                'status': 'confirmed',
                'deposit': widget.amount,
                'created_at': DateTime.now().toIso8601String(),
              });

              print(
                'Created missing reservation with ID ${widget.reservationId}',
              );
            }
          }
        } else if (checkResult.data()!['status'] != newStatus) {
          print('WARNING: Reservation status update failed, forcing update...');
          // Force direct update in Firestore if needed
          await FirebaseFirestore.instance
              .collection('reservations')
              .doc(widget.reservationId)
              .update({'status': newStatus});
        } else {
          print(
            'Confirmed reservation ${widget.reservationId} status updated to $newStatus',
          );
        }

        // Get the reservation details to know which charger to update
        final reservationData =
            await FirebaseFirestore.instance
                .collection('reservations')
                .doc(widget.reservationId)
                .get();
        if (reservationData.data() != null &&
            reservationData.data()!['charger_id'] != null) {
          final chargerId = reservationData.data()!['charger_id'] as String;
          final stationId = reservationData.data()!['station_id'] as String;

          // If deposit payment, make sure the charger is marked as unavailable
          if (widget.isDepositPayment) {
            print(
              'Marking charger $chargerId at station $stationId as UNAVAILABLE',
            );
            await stationService.updateChargerAvailability(
              stationId,
              chargerId,
              false, // isAvailable = false for deposit payment
            );
          } else {
            // For final payment, mark as available
            print(
              'Marking charger $chargerId at station $stationId as AVAILABLE',
            );
            await stationService.updateChargerAvailability(
              stationId,
              chargerId,
              true, // isAvailable = true for final payment
            );
          }

          // Verify charger availability was updated
          await stationService.refreshChargerAvailabilityData();
          bool isUpdated = false;

          for (final station in stationService.stations) {
            if (station.id == stationId) {
              for (final charger in station.chargers) {
                if (charger.id == chargerId) {
                  final expectedAvailability = !widget.isDepositPayment;
                  isUpdated = charger.isAvailable == expectedAvailability;
                  print(
                    'Charger $chargerId availability status: ${charger.isAvailable} (expected: $expectedAvailability)',
                  );
                  break;
                }
              }
              break;
            }
          }

          if (!isUpdated) {
            print(
              'WARNING: Charger availability update may not have been applied',
            );
            // Try again with direct database access
            await FirebaseFirestore.instance
                .collection('chargers')
                .doc(chargerId)
                .update({'is_available': widget.isDepositPayment ? 0 : 1});
            print('Forced charger availability update directly in database');
          }
        } else if (widget.isDepositPayment && widget.chargerName != null) {
          // Try to find the charger by name and update its availability
          print(
            'No charger_id in reservation, trying to find by name: ${widget.chargerName}',
          );

          for (final station in stationService.stations) {
            if (station.id == widget.station.id) {
              for (final charger in station.chargers) {
                if (charger.name == widget.chargerName) {
                  print('Found charger by name, updating availability');
                  await stationService.updateChargerAvailability(
                    station.id!,
                    charger.id!,
                    false, // Set to unavailable for deposit payment
                  );

                  // Also update the reservation with this charger ID
                  await FirebaseFirestore.instance
                      .collection('reservations')
                      .doc(widget.reservationId)
                      .update({'charger_id': charger.id});

                  print('Updated reservation with charger ID ${charger.id}');
                  break;
                }
              }
              break;
            }
          }
        }

        // Force reload stations data to refresh reservation info
        await stationService.loadStations();

        // If this is a final payment (not deposit), create or update the charging session
        if (!widget.isDepositPayment &&
            widget.energyConsumed > 0 &&
            !_chargingSessionCreated) {
          print(
            'Creating/updating charging session with energy: ${widget.energyConsumed} kWh',
          );
          // Look for existing charging session for this reservation
          final userId = authService.currentUser?.id ?? '1';
          final chargingSessionsRef = FirebaseFirestore.instance.collection(
            'charging_sessions',
          );
          final query =
              await chargingSessionsRef
                  .where('reservation_id', isEqualTo: widget.reservationId)
                  .get();
          final sessions = query.docs;

          if (sessions.isEmpty) {
            // Create a new completed charging session in Firestore
            final sessionData = {
              'user_id': userId,
              'station_id': widget.station.id,
              'vehicle_id': reservationData?.data()?['vehicle_id'] ?? '1',
              'reservation_id': widget.reservationId,
              'start_time':
                  DateTime.now()
                      .subtract(Duration(minutes: widget.chargingDuration))
                      .toIso8601String(),
              'end_time': DateTime.now().toIso8601String(),
              'energy_consumed': widget.energyConsumed,
              'amount': widget.amount,
              'status': 'completed',
              'created_at': DateTime.now().toIso8601String(),
            };
            print('Attempting to insert charging session with data:');
            print(sessionData);
            try {
              final docRef = await chargingSessionsRef.add(sessionData);
              print(
                'Created new charging session with ID: ${docRef.id} and energy: ${widget.energyConsumed}',
              );
              // Set flag to prevent duplicate creation
              _chargingSessionCreated = true;
            } catch (e) {
              print('ERROR inserting charging session in Firestore: $e');
            }
          } else {
            // Update existing charging session in Firestore
            final sessionId = sessions.first.id;
            try {
              await chargingSessionsRef.doc(sessionId).update({
                'end_time': DateTime.now().toIso8601String(),
                'energy_consumed': widget.energyConsumed,
                'amount': widget.amount,
                'status': 'completed',
              });
              print(
                'Updated charging session with ID: $sessionId to include energy: ${widget.energyConsumed}',
              );
            } catch (e) {
              print('ERROR updating charging session in Firestore: $e');
            }
          }

          // Force refresh the home screen data
          print('Forcing refresh of energy consumption data');
          await stationService.refreshChargerAvailabilityData();
        }

        _processedReservation = true;
        print(
          'Reservation ${widget.reservationId} successfully marked as $newStatus',
        );
      } catch (e) {
        print('Error marking reservation as completed: $e');
      }
    }
  }

  Future<void> _loadCardDetails() async {
    // If we have a cardId, load the card details from the database
    if (widget.cardId != null) {
      try {
        final paymentService = Provider.of<PaymentService>(
          context,
          listen: false,
        );
        final card = await paymentService.getPaymentMethodById(widget.cardId!);
        if (mounted) {
          setState(() {
            _paymentCard = card;
          });
        }
      } catch (e) {
        print('Error loading card details: $e');
      }
    }

    // If paymentMethod is directly passed as a card type (like Apple Pay), we don't need to load from database
    print('Payment method received: ${widget.paymentMethod}');
  }

  Future<void> _processPayment() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final walletService = Provider.of<WalletService>(context, listen: false);
      final stationService = Provider.of<StationService>(
        context,
        listen: false,
      );

      if (authService.currentUser == null) {
        print('Error: No logged in user');
        return;
      }

      final userId = authService.currentUser!.id!;

      // Process the payment
      if (widget.paymentMethod == 'Wallet') {
        // Process wallet payment
        await walletService.deductFromWallet(
          userId,
          widget.amount,
          widget.isDepositPayment
              ? 'Deposit for reservation at ${widget.station.name}'
              : 'Payment for charging at ${widget.station.name}',
        );
      } else {
        // Process card payment - note: most card payments are already processed
        // before reaching this screen, so this is just for record keeping
        print(
          'Card payment already processed: ${widget.cardId ?? 0}, Amount: ${widget.amount}',
        );

        // Record the payment in logs
        if (widget.cardId != null) {
          final paymentService = PaymentService();
          final card = await paymentService.getPaymentMethodById(
            widget.cardId!,
          );
          print(
            'Payment made using card: ${card?.cardType} ending in ${card?.lastFourDigits}',
          );
        }
      }

      // If this is a completed charging session (not just a deposit), record it
      if (!widget.isDepositPayment &&
          widget.energyConsumed > 0 &&
          !_chargingSessionCreated) {
        // Ensure the charging_sessions table exists
        // This part of the logic is no longer needed as charging sessions are in Firestore
        // The _chargingSessionCreated flag is still relevant for the UI.

        // The energy consumption update logic is now handled by the home screen's
        // energy consumption tracking and the _finalEnergyValue.
        // We just need to ensure the session is marked as completed in Firestore.

        final userId = authService.currentUser?.id ?? '1';
        final chargingSessionsRef = FirebaseFirestore.instance.collection(
          'charging_sessions',
        );
        final query =
            await chargingSessionsRef
                .where('reservation_id', isEqualTo: widget.reservationId)
                .get();
        final sessions = query.docs;

        if (sessions.isEmpty) {
          // Create a new completed charging session in Firestore
          final sessionData = {
            'user_id': userId,
            'station_id': widget.station.id,
            'vehicle_id': reservationData?['vehicle_id'] ?? '1',
            'reservation_id': widget.reservationId,
            'start_time':
                DateTime.now()
                    .subtract(Duration(minutes: widget.chargingDuration))
                    .toIso8601String(),
            'end_time': DateTime.now().toIso8601String(),
            'energy_consumed': widget.energyConsumed,
            'amount': widget.amount,
            'status': 'completed',
            'created_at': DateTime.now().toIso8601String(),
          };
          print('Attempting to insert charging session with data:');
          print(sessionData);
          try {
            final docRef = await chargingSessionsRef.add(sessionData);
            print(
              'Created new charging session with ID: ${docRef.id} and energy: ${widget.energyConsumed}',
            );
            // Set flag to prevent duplicate creation
            _chargingSessionCreated = true;
          } catch (e) {
            print('ERROR inserting charging session in Firestore: $e');
          }
        } else {
          // Update existing charging session in Firestore
          final sessionId = sessions.first.id;
          try {
            await chargingSessionsRef.doc(sessionId).update({
              'end_time': DateTime.now().toIso8601String(),
              'energy_consumed': widget.energyConsumed,
              'amount': widget.amount,
              'status': 'completed',
            });
            print(
              'Updated charging session with ID: $sessionId to include energy: ${widget.energyConsumed}',
            );
          } catch (e) {
            print('ERROR updating charging session in Firestore: $e');
          }
        }

        // Force refresh energy consumption data
        // This is now handled by the home screen's energy consumption tracking.
        // We just need to ensure the session is marked as completed in Firestore.
      }

      // Award points for charging payments (exclude deposit payments)
      print('PAYMENT RECEIPT DEBUG: Checking point awarding conditions');
      print(
        'PAYMENT RECEIPT DEBUG: isDepositPayment: ${widget.isDepositPayment}',
      );
      print('PAYMENT RECEIPT DEBUG: amount: ${widget.amount}');
      print('PAYMENT RECEIPT DEBUG: userId: $userId');
      print(
        'PAYMENT RECEIPT DEBUG: authService.currentUser: ${authService.currentUser}',
      );

      if (!widget.isDepositPayment && widget.amount > 0) {
        print('PAYMENT RECEIPT DEBUG: Conditions met for point awarding');
        final rewardService = Provider.of<RewardService>(
          context,
          listen: false,
        );

        // Calculate charging fee for points calculation
        final isAC = (widget.chargerType?.contains('AC') ?? false);
        final double pricePerKWh = isAC ? 0.80 : 1.30;
        final chargingFee = double.parse(
          (widget.energyConsumed * pricePerKWh).toStringAsFixed(2),
        );

        print(
          'POINTS DEBUG: About to award points for charging fee: RM${chargingFee.toStringAsFixed(2)} (${chargingFee.floor()} points)',
        );

        final pointsAwarded = await rewardService.awardPoints(
          userId,
          chargingFee, // Use charging fee instead of total payment amount
          'Points earned from charging at ${widget.station.name}',
        );

        print(
          'POINTS DEBUG: Points awarding result: $pointsAwarded for RM${chargingFee.toStringAsFixed(2)} (${chargingFee.floor()} points)',
        );
      } else {
        print('PAYMENT RECEIPT DEBUG: Conditions NOT met for point awarding');
        if (widget.isDepositPayment) {
          print(
            'PAYMENT RECEIPT DEBUG: This is a deposit payment, no points awarded',
          );
        }
        if (widget.amount <= 0) {
          print('PAYMENT RECEIPT DEBUG: Amount is <= 0, no points awarded');
        }
      }

      // Create fine transaction if there's a fine amount
      print(
        'FINE DEBUG: Checking fine amount - widget.fineAmount = ${widget.fineAmount}',
      );
      print('FINE DEBUG: Fine amount type: ${widget.fineAmount.runtimeType}');
      print('FINE DEBUG: Fine amount > 0? ${widget.fineAmount > 0}');

      if (widget.fineAmount > 0) {
        print(
          'FINE DEBUG: Creating fine transaction for amount: RM${widget.fineAmount}',
        );
        print('FINE DEBUG: User ID: $userId');
        print('FINE DEBUG: Station name: ${widget.station.name}');
        print('FINE DEBUG: Payment method: ${widget.paymentMethod}');

        try {
          final transaction = AppTransaction.Transaction(
            userId: userId,
            amount: widget.fineAmount,
            description:
                'Overtime fine for charging session at ${widget.station.name}',
            transactionType: 'debit',
            createdAt: DateTime.now(),
          );

          print(
            'FINE DEBUG: Transaction object to be added: ${transaction.toMap()}',
          );

          final docRef = await FirebaseFirestore.instance
              .collection('transactions')
              .add(transaction.toMap());
          print(
            'FINE DEBUG: Fine transaction created successfully with ID: ${docRef.id}',
          );
        } catch (e) {
          print('FINE DEBUG: Error creating fine transaction: $e');
          print('FINE DEBUG: Error type: ${e.runtimeType}');
          print('FINE DEBUG: Stack trace: ${StackTrace.current}');
        }
      } else {
        print(
          'FINE DEBUG: No fine transaction created - fine amount is ${widget.fineAmount}',
        );
      }
    } catch (e) {
      print('Error processing payment: $e');
    }
  }

  Future<void> _verifyReservation() async {
    if (widget.reservationId != null) {
      try {
        // Get direct access to database
        final db =
            await FirebaseFirestore.instance
                .collection('reservations')
                .doc(widget.reservationId)
                .get();

        print('\n=========== PAYMENT VERIFICATION ============');
        print('Verifying reservation ID: ${widget.reservationId}');

        // Check if reservation exists in database
        if (db.data() == null) {
          print(
            'CRITICAL ERROR: Reservation ${widget.reservationId} NOT FOUND in database!',
          );
        } else {
          print('Reservation found with data:');
          print(db.data());

          final status = db.data()!['status'];
          print('Current status: $status');
          if (widget.isDepositPayment && status != 'confirmed') {
            print(
              'WARNING: Deposit payment made but status is not "confirmed"',
            );
          }

          final startTimeStr = db.data()!['start_time'] as String?;
          if (startTimeStr != null) {
            try {
              final startTime = DateTime.parse(startTimeStr);
              final now = DateTime.now();
              if (startTime.isBefore(now)) {
                print('WARNING: Reservation start time is in the past!');
              } else {
                print(
                  'Reservation start time is valid: ${startTime.toIso8601String()}',
                );
              }
            } catch (e) {
              print('ERROR parsing start time: $e');
            }
          }
        }

        // Check all reservations for this user
        final authService = Provider.of<AuthService>(context, listen: false);
        final userId = authService.currentUser?.id ?? '-1';

        if (userId != '-1') {
          final userReservations =
              await FirebaseFirestore.instance
                  .collection('reservations')
                  .where('user_id', isEqualTo: userId)
                  .get();

          print(
            'Found ${userReservations.docs.length} total reservations for user $userId',
          );
          for (var res in userReservations.docs) {
            print(
              'ID: ${res.id}, Status: ${res.data()['status']}, StartTime: ${res.data()['start_time']}',
            );
          }
        }

        print('============ END VERIFICATION ===========\n');
      } catch (e) {
        print('Error verifying reservation: $e');
      }
    }
  }

  // Helper method to ensure charging_sessions table exists
  Future<bool> _ensureChargingSessionsTable() async {
    try {
      final db =
          await FirebaseFirestore.instance
              .collection('charging_sessions')
              .doc('charging_sessions')
              .get();

      if (db.data() == null) {
        print(
          'CRITICAL: charging_sessions table does not exist, creating it now...',
        );
        await FirebaseFirestore.instance
            .collection('charging_sessions')
            .doc('charging_sessions')
            .set({
              'id': 'charging_sessions', // Use a unique ID for the collection
              'user_id': '1', // Default user_id
              'station_id': '1', // Default station_id
              'vehicle_id': '1', // Default vehicle_id
              'reservation_id': null, // Default reservation_id
              'start_time':
                  DateTime.now().toIso8601String(), // Default start_time
              'end_time': null, // Default end_time
              'energy_consumed': 0.0, // Default energy_consumed
              'amount': 0.0, // Default amount
              'status': 'completed', // Default status
              'created_at':
                  DateTime.now().toIso8601String(), // Default created_at
            });
        print('Successfully created charging_sessions table');
        return true;
      } else {
        print('charging_sessions table already exists');

        // Verify table structure
        final tableInfo =
            await FirebaseFirestore.instance
                .collection('charging_sessions')
                .doc('charging_sessions')
                .get();
        print('Table schema: ${tableInfo.data()}');

        // Check if energy_consumed column exists
        bool hasEnergyColumn = false;
        bool hasUserIdColumn = false;
        bool hasStatusColumn = false;

        if (tableInfo.data() != null) {
          final data = tableInfo.data()!;
          if (data['energy_consumed'] != null) {
            hasEnergyColumn = true;
          }
          if (data['user_id'] != null) {
            hasUserIdColumn = true;
          }
          if (data['status'] != null) {
            hasStatusColumn = true;
          }
        }

        if (!hasEnergyColumn) {
          print('Adding missing energy_consumed column');
          await FirebaseFirestore.instance
              .collection('charging_sessions')
              .doc('charging_sessions')
              .update({
                'energy_consumed': 0.0, // Default value
              });
        }

        if (!hasUserIdColumn) {
          print('Adding missing user_id column');
          await FirebaseFirestore.instance
              .collection('charging_sessions')
              .doc('charging_sessions')
              .update({
                'user_id': '1', // Default value
              });
        }

        if (!hasStatusColumn) {
          print('Adding missing status column');
          await FirebaseFirestore.instance
              .collection('charging_sessions')
              .doc('charging_sessions')
              .update({
                'status': 'completed', // Default value
              });
        }

        return true;
      }
    } catch (e) {
      print('Error ensuring charging_sessions table: $e');
      return false;
    }
  }

  // Check if a charging session already exists for this reservation
  Future<void> _checkForExistingChargingSession() async {
    if (!widget.isDepositPayment && widget.reservationId != null) {
      try {
        final sessions =
            await FirebaseFirestore.instance
                .collection('charging_sessions')
                .where('reservation_id', isEqualTo: widget.reservationId)
                .get();

        if (sessions.docs.isNotEmpty) {
          print(
            'Found existing charging session for reservation ${widget.reservationId}',
          );
          setState(() {
            _chargingSessionCreated = true;
          });
        }
      } catch (e) {
        print('Error checking for existing charging session: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define a base price per kWh based on charger type
    final isAC = (widget.chargerType?.contains('AC') ?? false);
    final double pricePerKWh = isAC ? 0.80 : 1.30; // Set price based on type

    // Calculate the charging fee
    final chargingFee = double.parse(
      (widget.energyConsumed * pricePerKWh).toStringAsFixed(2),
    );

    // For deposit payments, use the provided amount directly
    final depositAmount = widget.isDepositPayment ? widget.amount : 30.0;

    // For consistency across screens, use the same calculation logic
    // If final payment, use charging fee minus deposit
    // If deposit payment, use fixed deposit amount
    final rawAmount =
        widget.isDepositPayment
            ? depositAmount
            : double.parse((chargingFee - depositAmount).toStringAsFixed(2));

    // For display purposes - don't modify the actual amount for refund processing
    final isRefund = rawAmount < 0;
    final actualAmount = widget.isDepositPayment ? rawAmount : rawAmount;
    final displayAmount = isRefund ? actualAmount.abs() : actualAmount;

    // LOGGING: For debugging payment calculations
    print('PAYMENT RECEIPT CALCULATION:');
    print('Is deposit payment: ${widget.isDepositPayment}');
    print('Energy consumed: ${widget.energyConsumed} kWh');
    print('Price per kWh: $pricePerKWh');
    print('Charging fee: $chargingFee');
    print('Deposit amount: $depositAmount');
    print('Raw amount: $rawAmount');
    print('Actual amount: $actualAmount');
    print('Is refund: $isRefund');
    print('Display amount: $displayAmount');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: Text(
          widget.isDepositPayment ? 'Deposit Receipt' : 'Payment Receipt',
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Success icon and message
            Container(
              padding: const EdgeInsets.all(24),
              color: Colors.green[50],
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 64),
                  const SizedBox(height: 16),
                  Text(
                    widget.isDepositPayment
                        ? 'Deposit Payment Successful'
                        : 'Payment Successful',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isDepositPayment
                        ? 'Your reservation is confirmed'
                        : 'Thank you for using our service',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            ),

            // Payment details
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
                  Text(
                    widget.isDepositPayment
                        ? 'Deposit Details'
                        : 'Payment Details',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Amount Paid',
                    'RM ${displayAmount.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                  if (!widget.isDepositPayment) ...[
                    _buildDetailRow(
                      'Energy Consumed',
                      '${widget.energyConsumed.toStringAsFixed(1)} kWh',
                    ),
                    _buildDetailRow(
                      'Unit Price',
                      'RM ${pricePerKWh.toStringAsFixed(2)}/kWh',
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Charging Fee',
                      'RM ${chargingFee.toStringAsFixed(2)}',
                    ),

                    // Only show deposit refund for non-deposit payments
                    if (!widget.isDepositPayment)
                      _buildDetailRow(
                        'Deposit Refund',
                        '- RM ${depositAmount.toStringAsFixed(2)}',
                        isCredit: true,
                      ),
                  ],
                  const Divider(
                    height: 24,
                    thickness: 1,
                    color: Color(0xFFEEEEEE),
                  ),
                  _buildDetailRow(
                    widget.isDepositPayment
                        ? 'Deposit Amount'
                        : (isRefund ? 'Refund Amount' : 'Total Fee'),
                    'RM ${displayAmount.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                  _buildDetailRow(
                    'Payment Method',
                    widget.paymentMethod == 'E-Wallet'
                        ? 'EV Wallet'
                        : widget.paymentMethod == 'Apple Pay'
                        ? 'Apple Pay'
                        : _paymentCard != null
                        ? '${_paymentCard!.cardType} ****${_paymentCard!.lastFourDigits}'
                        : widget.paymentMethod.startsWith('Visa') ||
                            widget.paymentMethod.startsWith('Mastercard') ||
                            widget.paymentMethod.startsWith('American Express')
                        ? widget.paymentMethod
                        : 'Card',
                  ),
                  _buildDetailRow(
                    'Date & Time',
                    DateTime.now().toString().substring(0, 16),
                  ),
                  // Add Charger Information
                  if (widget.chargerType != null) ...[
                    const SizedBox(height: 8),
                    // Divider for charger section
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Charger Information',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Charging Station', widget.station.name),
                    _buildDetailRow(
                      'Charger Type',
                      _formatChargerType(widget.chargerType!),
                    ),
                    if (widget.chargerName != null)
                      _buildDetailRow('Charger Name', widget.chargerName!),
                  ],
                  if (widget.isDepositPayment)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '80% of deposit (RM ${(widget.amount * 0.8).toStringAsFixed(2)}) will be refunded if cancelled',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Done button
            _buildFooterButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isTotal = false,
    bool isCredit = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color:
                  isTotal
                      ? Theme.of(context).primaryColor
                      : isCredit
                      ? Colors.green
                      : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                // Update energy data before navigating
                print('Updating energy consumption data before navigation');
                final stationService = Provider.of<StationService>(
                  context,
                  listen: false,
                );
                final authService = Provider.of<AuthService>(
                  context,
                  listen: false,
                );

                // First make sure the charging session was inserted correctly
                if (!widget.isDepositPayment &&
                    widget.energyConsumed > 0 &&
                    authService.currentUser != null &&
                    !_chargingSessionCreated) {
                  try {
                    final userId = authService.currentUser!.id!;
                    final chargingSessionsRef = FirebaseFirestore.instance
                        .collection('charging_sessions');
                    final query =
                        await chargingSessionsRef
                            .where(
                              'reservation_id',
                              isEqualTo: widget.reservationId,
                            )
                            .get();
                    final sessions = query.docs;

                    if (sessions.isEmpty) {
                      // Create a new completed charging session in Firestore
                      final sessionData = {
                        'user_id': userId,
                        'station_id': widget.station.id,
                        'vehicle_id': reservationData?['vehicle_id'] ?? '1',
                        'reservation_id': widget.reservationId,
                        'start_time':
                            DateTime.now()
                                .subtract(
                                  Duration(minutes: widget.chargingDuration),
                                )
                                .toIso8601String(),
                        'end_time': DateTime.now().toIso8601String(),
                        'energy_consumed': widget.energyConsumed,
                        'amount': widget.amount,
                        'status': 'completed',
                        'created_at': DateTime.now().toIso8601String(),
                      };
                      print(
                        'Attempting to insert new charging session with data: $sessionData',
                      );
                      final docRef = await chargingSessionsRef.add(sessionData);

                      print('Created charging session with ID: ${docRef.id}');
                      _chargingSessionCreated = true;

                      // CRITICAL FIX: Directly update the cached energy value with the current session
                      // This ensures the home screen will show the updated value regardless of database issues
                      double currentEnergy = stationService
                          .getCachedEnergyValue(userId);
                      double newTotalEnergy =
                          currentEnergy + widget.energyConsumed;

                      print(
                        'Updating energy value: Current: $currentEnergy kWh + New: ${widget.energyConsumed} kWh = Total: $newTotalEnergy kWh',
                      );
                      await stationService.updateCachedEnergyValue(
                        userId,
                        newTotalEnergy,
                      );

                      // Also update the persistent cached value in the database
                      // This part is no longer needed as energy_records are in Firestore
                      // await _db.updateCachedEnergyValue(userId, newTotalEnergy);

                      // Force refresh the home screen's energy data
                      await stationService.refreshChargerAvailabilityData();

                      // Force the station service to notify listeners to update the UI
                      stationService.notifyListeners();

                      // Get the total energy consumed directly from the database to verify
                      final verifiedEnergy = await stationService
                          .getTotalEnergyConsumed(userId);
                      print(
                        'Verified total energy from database: $verifiedEnergy kWh',
                      );

                      // If database value is less than our calculated value, force update with our calculation
                      if (verifiedEnergy < newTotalEnergy) {
                        print(
                          'WARNING: Database energy value ($verifiedEnergy) is less than calculated value ($newTotalEnergy)',
                        );
                        print('Forcing update with calculated value');
                        await stationService.updateCachedEnergyValue(
                          userId,
                          newTotalEnergy,
                        );
                        // This part is no longer needed as energy_records are in Firestore
                        // await _db.updateCachedEnergyValue(userId, newTotalEnergy);

                        // Force UI update again
                        stationService.notifyListeners();
                      }

                      // Store the final energy value for navigation
                      _finalEnergyValue = newTotalEnergy;

                      // CRITICAL: Force set the exact value to ensure it shows up
                      await stationService.forceSetEnergyValue(
                        userId,
                        newTotalEnergy,
                      );

                      // Create a permanent record of this energy transaction to avoid losing it
                      try {
                        await FirebaseFirestore.instance
                            .collection('energy_records')
                            .add({
                              'user_id': userId,
                              'energy_consumed': widget.energyConsumed,
                              'timestamp': DateTime.now().toIso8601String(),
                              'description':
                                  'Charging at ${widget.station.name}',
                            });
                        print(
                          'Created permanent energy record of ${widget.energyConsumed} kWh in Firestore',
                        );
                      } catch (e) {
                        print(
                          'Failed to create permanent energy record in Firestore: $e',
                        );
                      }

                      // Send multiple notification events to ensure UI updates
                      stationService.notifyListeners();
                      Future.delayed(const Duration(milliseconds: 100), () {
                        stationService.notifyListeners();
                      });
                    } else {
                      // Update existing charging session in Firestore
                      final sessionId = sessions.first.id;
                      try {
                        await chargingSessionsRef.doc(sessionId).update({
                          'end_time': DateTime.now().toIso8601String(),
                          'energy_consumed': widget.energyConsumed,
                          'amount': widget.amount,
                          'status': 'completed',
                        });
                        print(
                          'Updated charging session with ID: $sessionId to include energy: ${widget.energyConsumed}',
                        );
                      } catch (e) {
                        print(
                          'ERROR updating charging session in Firestore: $e',
                        );
                      }
                    }
                  } catch (e) {
                    print('Error processing charging session: $e');
                  }
                }

                // Navigate to home screen directly with force refresh flag
                print('Navigating back to home screen with force refresh...');

                // Ensure we force refresh even if the _chargingSessionCreated flag is not set
                if (!widget.isDepositPayment && widget.energyConsumed > 0) {
                  final stationService = Provider.of<StationService>(
                    context,
                    listen: false,
                  );
                  final authService = Provider.of<AuthService>(
                    context,
                    listen: false,
                  );

                  // Make sure the energy value is updated regardless of session creation
                  if (authService.currentUser != null) {
                    final userId = authService.currentUser!.id!;
                    double currentEnergy = stationService.getCachedEnergyValue(
                      userId,
                    );
                    double newTotalEnergy =
                        currentEnergy + widget.energyConsumed;

                    print(
                      'FINAL CHECK: Ensuring energy value is updated before navigation',
                    );
                    print(
                      'Current: $currentEnergy kWh + Session: ${widget.energyConsumed} kWh = Total: $newTotalEnergy kWh',
                    );

                    // Store the final energy value for navigation
                    _finalEnergyValue = newTotalEnergy;

                    // CRITICAL: Force set the exact value to ensure it shows up
                    await stationService.forceSetEnergyValue(
                      userId,
                      newTotalEnergy,
                    );

                    // Create a permanent record of this energy transaction to avoid losing it
                    try {
                      await FirebaseFirestore.instance
                          .collection('energy_records')
                          .add({
                            'user_id': userId,
                            'energy_consumed': widget.energyConsumed,
                            'timestamp': DateTime.now().toIso8601String(),
                            'description': 'Charging at ${widget.station.name}',
                          });
                      print(
                        'Created permanent energy record of ${widget.energyConsumed} kWh in Firestore',
                      );
                    } catch (e) {
                      print(
                        'Failed to create permanent energy record in Firestore: $e',
                      );
                    }

                    // Send multiple notification events to ensure UI updates
                    stationService.notifyListeners();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      stationService.notifyListeners();
                    });
                  }
                }

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => app_main.MainScreen(),
                  ),
                  (route) => false, // Remove all previous routes
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format charger type string
  String _formatChargerType(String rawChargerType) {
    // Extract the type (AC/DC) and power value
    final parts = rawChargerType.split(' ');
    if (parts.length >= 2) {
      final type = parts[0]; // AC or DC

      // Extract the numeric part and format to a whole number
      String powerString = parts[1];
      if (powerString.endsWith('kW')) {
        powerString = powerString.substring(0, powerString.length - 2);
        try {
          final power = double.parse(powerString);

          // Special handling for DC chargers around 49-50kW - always show as 50kW
          if (type == 'DC' && power >= 49 && power < 51) {
            return 'DC 50kW';
          }

          // For other chargers, round to the nearest whole number
          return '$type ${power.round()}kW';
        } catch (e) {
          print('Error parsing charger power: $e');
        }
      }
    }

    // Fallback - return as is if we couldn't parse
    return rawChargerType;
  }
}
