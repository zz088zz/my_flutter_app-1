import 'package:flutter/material.dart';
import '../models/charging_station.dart';
import '../services/payment_service.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../main.dart' as app_main;
import '../services/station_service.dart';
import '../models/payment_method.dart';
import '../services/wallet_service.dart';
// Removed reward service import
import '../screens/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final int? overtimeMinutes;
  final int? gracePeriodMinutes;
  
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
    this.overtimeMinutes,
    this.gracePeriodMinutes,
  }) : super(key: key);
  
  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
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
        final stationService = Provider.of<StationService>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);
        
        // Update reservation status in database
        final newStatus = widget.isDepositPayment ? 'confirmed' : 'completed';

        // Force direct update
        final db = await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).update({
          'status': newStatus,
        });
        
        // Double check and ensure the status is actually updated
        final checkResult = await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).get();
        if (checkResult.data() == null) {

          // Create a new reservation if it doesn't exist
          if (widget.isDepositPayment && authService.currentUser != null) {
            // We need to create a new reservation
            final db = await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId);
            
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
              final vehicles = await FirebaseFirestore.instance.collection('vehicles').where('user_id', isEqualTo: authService.currentUser!.id).get();
              if (vehicles.docs.isNotEmpty) {
                vehicleId = vehicles.docs.first.data()['id'] as String;
              }
              
              // Insert the reservation
              await db.set({
                'id': widget.reservationId,
                'user_id': authService.currentUser!.id!,
                'station_id': widget.station.id,
                'vehicle_id': vehicleId,
                'payment_method_id': widget.cardId ?? '1', // Use provided card ID or default
                'charger_id': chargerId,
                'start_time': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
                'duration': 60, // 60 minutes
                'status': 'confirmed',
                'deposit': widget.amount,
                'created_at': DateTime.now().toIso8601String(),
              });

            }
          }
        } else if (checkResult.data()!['status'] != newStatus) {

          // Force direct update in Firestore if needed
          await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).update({
            'status': newStatus,
          });
        } else {

        }
        
        // Get the reservation details to know which charger to update
        final reservationData = await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).get();
        if (reservationData.data() != null && reservationData.data()!['charger_id'] != null) {
          final chargerId = reservationData.data()!['charger_id'] as String;
          final stationId = reservationData.data()!['station_id'] as String;
          
          // If deposit payment, make sure the charger is marked as unavailable
          if (widget.isDepositPayment) {

            await stationService.updateChargerAvailability(
              stationId, 
              chargerId, 
              false // isAvailable = false for deposit payment
            );
          } else {
            // For final payment, mark as available

            await stationService.updateChargerAvailability(
              stationId, 
              chargerId, 
              true // isAvailable = true for final payment
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

                  break;
                }
              }
              break;
            }
          }
          
          if (!isUpdated) {

            // Try again with direct database access
            await FirebaseFirestore.instance.collection('chargers').doc(chargerId).update({
              'is_available': widget.isDepositPayment ? 0 : 1,
            });

          }
        } else if (widget.isDepositPayment && widget.chargerName != null) {
          // Try to find the charger by name and update its availability

          for (final station in stationService.stations) {
            if (station.id == widget.station.id) {
              for (final charger in station.chargers) {
                if (charger.name == widget.chargerName) {

                  await stationService.updateChargerAvailability(
                    station.id!, 
                    charger.id!, 
                    false // Set to unavailable for deposit payment
                  );
                  
                  // Also update the reservation with this charger ID
                  await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).update({
                    'charger_id': charger.id,
                  });

                  break;
                }
              }
              break;
            }
          }
        }
        
        // Force reload stations data to refresh reservation info
        await stationService.loadStations();
        
        // Create or update charging session for both deposit and final payments

        // For deposit payments: create paused session with deposit amount
        // For final payments: create/update completed session with final amount
        if (!_chargingSessionCreated) {

          // Look for existing charging session for this reservation
          final userId = authService.currentUser?.id ?? '1';
          final chargingSessionsRef = FirebaseFirestore.instance.collection('charging_sessions');
          final query = await chargingSessionsRef.where('reservation_id', isEqualTo: widget.reservationId).get();
          final sessions = query.docs;
          
          if (sessions.isEmpty) {
            // Create a new charging session in Firestore
            // Prepare session data with explicit null check
            Map<String, dynamic> sessionData = {
              'user_id': userId,
              'station_id': widget.station.id,
              'vehicle_id': reservationData?.data()?['vehicle_id'] ?? '1',
              'reservation_id': widget.reservationId,
              'start_time': DateTime.now().subtract(Duration(minutes: widget.chargingDuration)).toIso8601String(),
              'end_time': DateTime.now().toIso8601String(),
              'energy_consumed': widget.energyConsumed,
              'status': widget.isDepositPayment ? 'paused' : 'completed',
              'created_at': DateTime.now().toIso8601String()
            };

            // Always include amount field for both deposit and final payments
            sessionData['amount'] = widget.amount;

            try {
              final docRef = await chargingSessionsRef.add(sessionData);

              // Set flag to prevent duplicate creation
              _chargingSessionCreated = true;
            } catch (e) {

            }
          } else {
            // Update existing charging session in Firestore
            final sessionId = sessions.first.id;
            try {
              await chargingSessionsRef.doc(sessionId).update({
                'end_time': DateTime.now().toIso8601String(),
                'energy_consumed': widget.energyConsumed,
                'amount': widget.amount, // Store amount for both deposit and final payments
                'status': widget.isDepositPayment ? 'paused' : 'completed',
              });

            } catch (e) {

            }
          }
          
          // Force refresh the home screen data

          await stationService.refreshChargerAvailabilityData();
        }
        
        _processedReservation = true;

      } catch (e) {

      }
    }
  }

  Future<void> _loadCardDetails() async {
    // If we have a cardId, load the card details from the database
    if (widget.cardId != null) {
      try {
        final paymentService = Provider.of<PaymentService>(context, listen: false);
        final card = await paymentService.getPaymentMethodById(widget.cardId!);
        if (mounted) {
          setState(() {
            _paymentCard = card;
          });
        }
      } catch (e) {

      }
    }
    
    // If paymentMethod is directly passed as a card type (like Apple Pay), we don't need to load from database

  }

  Future<void> _processPayment() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final walletService = Provider.of<WalletService>(context, listen: false);
      final stationService = Provider.of<StationService>(context, listen: false);
      
      if (authService.currentUser == null) {

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

        // Record the payment in logs
        if (widget.cardId != null) {
          final paymentService = PaymentService();
          final card = await paymentService.getPaymentMethodById(widget.cardId!);

        }
      }
      
      // Record all charging sessions (both deposit and final payments)
      if (!_chargingSessionCreated) {
        // Ensure the charging_sessions table exists
        // This part of the logic is no longer needed as charging sessions are in Firestore
        // The _chargingSessionCreated flag is still relevant for the UI.
        
        // The energy consumption update logic is now handled by the home screen's
        // energy consumption tracking and the _finalEnergyValue.
        // We just need to ensure the session is marked as completed in Firestore.
        
        final userId = authService.currentUser?.id ?? '1';
        final chargingSessionsRef = FirebaseFirestore.instance.collection('charging_sessions');
        final query = await chargingSessionsRef.where('reservation_id', isEqualTo: widget.reservationId).get();
        final sessions = query.docs;
        
        if (sessions.isEmpty) {
          // Create a new completed charging session in Firestore
          final sessionData = {
            'user_id': userId,
            'station_id': widget.station.id,
            'vehicle_id': reservationData?['vehicle_id'] ?? '1',
            'reservation_id': widget.reservationId,
            'start_time': DateTime.now().subtract(Duration(minutes: widget.chargingDuration)).toIso8601String(),
            'end_time': DateTime.now().toIso8601String(),
            'energy_consumed': widget.energyConsumed,
            'amount': widget.amount, // Store amount for both deposit and final payments
            'status': widget.isDepositPayment ? 'paused' : 'completed',
            'created_at': DateTime.now().toIso8601String(),
          };

          try {
            final docRef = await chargingSessionsRef.add(sessionData);

            // Set flag to prevent duplicate creation
            _chargingSessionCreated = true;
          } catch (e) {

          }
        } else {
          // Update existing charging session in Firestore
          final sessionId = sessions.first.id;
          try {
                                    // Prepare update data
                        Map<String, dynamic> updateData = {
                          'end_time': DateTime.now().toIso8601String(),
                          'energy_consumed': widget.energyConsumed,
                          'amount': widget.amount,
                          'status': widget.isDepositPayment ? 'paused' : 'completed',
                        };



                        await chargingSessionsRef.doc(sessionId).update(updateData);

                        // Verify the update
                        final updatedDoc = await chargingSessionsRef.doc(sessionId).get();

          } catch (e) {

          }
        }
        
        // Force refresh energy consumption data
        // This is now handled by the home screen's energy consumption tracking.
        // We just need to ensure the session is marked as completed in Firestore.
      }
      
    } catch (e) {

    }
  }

  Future<void> _verifyReservation() async {
    if (widget.reservationId != null) {
      try {
        // Get direct access to database
        final db = await FirebaseFirestore.instance.collection('reservations').doc(widget.reservationId).get();

        // Check if reservation exists in database
        if (db.data() == null) {

        } else {

          final status = db.data()!['status'];

          if (widget.isDepositPayment && status != 'confirmed') {

          }
          
          final startTimeStr = db.data()!['start_time'] as String?;
          if (startTimeStr != null) {
            try {
              final startTime = DateTime.parse(startTimeStr);
              final now = DateTime.now();
              if (startTime.isBefore(now)) {

              } else {

              }
            } catch (e) {

            }
          }
        }
        
        // Check all reservations for this user
        final authService = Provider.of<AuthService>(context, listen: false);
        final userId = authService.currentUser?.id ?? '-1';
        
        if (userId != '-1') {
          final userReservations = await FirebaseFirestore.instance.collection('reservations').where('user_id', isEqualTo: userId).get();

          for (var res in userReservations.docs) {

          }
        }

      } catch (e) {

      }
    }
  }

  // Helper method to ensure charging_sessions table exists
  Future<bool> _ensureChargingSessionsTable() async {
    try {
      final db = await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').get();
      
      if (db.data() == null) {

        await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').set({
          'id': 'charging_sessions', // Use a unique ID for the collection
          'user_id': '1', // Default user_id
          'station_id': '1', // Default station_id
          'vehicle_id': '1', // Default vehicle_id
          'reservation_id': null, // Default reservation_id
          'start_time': DateTime.now().toIso8601String(), // Default start_time
          'end_time': null, // Default end_time
          'energy_consumed': 0.0, // Default energy_consumed
          'amount': 0.0, // Default amount
          'status': 'completed', // Default status
          'created_at': DateTime.now().toIso8601String(), // Default created_at
        });

        return true;
      } else {

        // Verify table structure
        final tableInfo = await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').get();

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

          await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').update({
            'energy_consumed': 0.0, // Default value
          });
        }
        
        if (!hasUserIdColumn) {

          await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').update({
            'user_id': '1', // Default value
          });
        }
        
        if (!hasStatusColumn) {

          await FirebaseFirestore.instance.collection('charging_sessions').doc('charging_sessions').update({
            'status': 'completed', // Default value
          });
        }
        
        return true;
      }
    } catch (e) {

      return false;
    }
  }

  // Check if a charging session already exists for this reservation
  Future<void> _checkForExistingChargingSession() async {
    if (widget.reservationId != null) { // Check for existing sessions for both deposit and final payments
      try {
        final sessions = await FirebaseFirestore.instance.collection('charging_sessions').where('reservation_id', isEqualTo: widget.reservationId).get();
        
        if (sessions.docs.isNotEmpty) {

          setState(() {
            _chargingSessionCreated = true;
          });
        }
      } catch (e) {

      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define a base price per kWh based on charger type
    final isAC = (widget.chargerType?.contains('AC') ?? false);
    final double pricePerKWh = isAC ? 0.80 : 1.30; // Set price based on type
    
    // Calculate the charging fee
    final chargingFee = double.parse((widget.energyConsumed * pricePerKWh).toStringAsFixed(2));
    
    // For deposit payments, use the provided amount directly
    final depositAmount = widget.isDepositPayment ? widget.amount : 30.0;
    
    // Get fine amount if any
    final fineAmount = widget.fineAmount;
    
    // For consistency across screens, use the same calculation logic
    // If final payment, use charging fee plus fine minus deposit
    // If deposit payment, use fixed deposit amount
    final rawAmount = widget.isDepositPayment 
        ? depositAmount 
        : double.parse((chargingFee + fineAmount - depositAmount).toStringAsFixed(2));
    
    // For display purposes - don't modify the actual amount for refund processing
    final isRefund = rawAmount < 0;
    final displayAmount = isRefund ? rawAmount.abs() : rawAmount;
    
    // LOGGING: For debugging payment calculations

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: Text(widget.isDepositPayment ? 'Deposit Receipt' : 'Payment Receipt'),
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
                  Icon(
                    Icons.check_circle,
                    color: Colors.green[700],
                    size: 64,
                  ),
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
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
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
                    widget.isDepositPayment ? 'Deposit Details' : 'Payment Details',
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
                    
                    // Show fine amount and overtime details if applicable
                    if (widget.fineAmount > 0) ...[  
                      _buildDetailRow(
                        'Overtime Fine',
                        'RM ${widget.fineAmount.toStringAsFixed(2)}',
                        isCredit: false,
                      ),
                      // Add overtime minutes and grace period information
                      Container(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Overtime: ${widget.overtimeMinutes ?? 0} minutes',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            Text(
                              'Grace period: ${widget.gracePeriodMinutes ?? 3} minutes',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Only show deposit refund for non-deposit payments
                    if (!widget.isDepositPayment)
                      _buildDetailRow(
                        'Deposit Refund',
                        '- RM ${depositAmount.toStringAsFixed(2)}',
                        isCredit: true,
                      ),
                  ],
                  const Divider(height: 24, thickness: 1, color: Color(0xFFEEEEEE)),
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
                        : widget.paymentMethod.contains('*')
                            ? widget.paymentMethod.replaceAll('*', '****')
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
                    _buildDetailRow(
                      'Charging Station',
                      widget.station.name,
                    ),
                    _buildDetailRow(
                      'Charger Type',
                      _formatChargerType(widget.chargerType!),
                    ),
                    if (widget.chargerName != null)
                      _buildDetailRow(
                        'Charger Name',
                        widget.chargerName!,
                      ),
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
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
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

  Widget _buildDetailRow(String label, String value, {bool isTotal = false, bool isCredit = false}) {
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
              color: isTotal ? Theme.of(context).primaryColor : isCredit ? Colors.green : Colors.black87,
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

                final stationService = Provider.of<StationService>(context, listen: false);
                final authService = Provider.of<AuthService>(context, listen: false);
                
                // First make sure the charging session was inserted correctly
                if (authService.currentUser != null && !_chargingSessionCreated) {
                  try {
                    final userId = authService.currentUser!.id!;
                    final chargingSessionsRef = FirebaseFirestore.instance.collection('charging_sessions');
                    final query = await chargingSessionsRef.where('reservation_id', isEqualTo: widget.reservationId).get();
                    final sessions = query.docs;
                    
                    if (sessions.isEmpty) {
                      // Create a new completed charging session in Firestore
                      // Prepare session data with explicit null check
                      Map<String, dynamic> sessionData = {
                        'user_id': userId,
                        'station_id': widget.station.id,
                        'vehicle_id': reservationData?['vehicle_id'] ?? '1',
                        'reservation_id': widget.reservationId,
                        'start_time': DateTime.now().subtract(Duration(minutes: widget.chargingDuration)).toIso8601String(),
                        'end_time': DateTime.now().toIso8601String(),
                        'energy_consumed': widget.energyConsumed,
                        'status': widget.isDepositPayment ? 'paused' : 'completed',
                        'created_at': DateTime.now().toIso8601String(),
                      };

                      // Always include amount field for both deposit and final payments
                      sessionData['amount'] = widget.amount;

                      final docRef = await chargingSessionsRef.add(sessionData);

                      _chargingSessionCreated = true;
                      
                                              // Reward points functionality has been removed
                      
                      // CRITICAL FIX: Directly update the cached energy value with the current session
                      // This ensures the home screen will show the updated value regardless of database issues
                      double currentEnergy = stationService.getCachedEnergyValue(userId);
                      double newTotalEnergy = currentEnergy + widget.energyConsumed;

                      await stationService.updateCachedEnergyValue(userId, newTotalEnergy);
                      
                      // Also update the persistent cached value in the database
                      // This part is no longer needed as energy_records are in Firestore
                      // await _db.updateCachedEnergyValue(userId, newTotalEnergy); 
                      
                      // Force refresh the home screen's energy data
                      await stationService.refreshChargerAvailabilityData();
                      
                      // Force the station service to notify listeners to update the UI
                      stationService.notifyListeners();
                      
                      // Get the total energy consumed directly from the database to verify
                      final verifiedEnergy = await stationService.getTotalEnergyConsumed(userId);

                      // If database value is less than our calculated value, force update with our calculation
                      if (verifiedEnergy < newTotalEnergy) {

                        await stationService.updateCachedEnergyValue(userId, newTotalEnergy);
                        // This part is no longer needed as energy_records are in Firestore
                        // await _db.updateCachedEnergyValue(userId, newTotalEnergy); 
                        
                        // Force UI update again
                        stationService.notifyListeners();
                      }
                      
                      // Store the final energy value for navigation
                      _finalEnergyValue = newTotalEnergy;
                      
                      // CRITICAL: Force set the exact value to ensure it shows up
                      await stationService.forceSetEnergyValue(userId, newTotalEnergy);
                      
                      // Create a permanent record of this energy transaction to avoid losing it
                      try {
                        await FirebaseFirestore.instance.collection('energy_records').add({
                          'user_id': userId,
                          'energy_consumed': widget.energyConsumed,
                          'timestamp': DateTime.now().toIso8601String(),
                          'description': 'Charging at ${widget.station.name}',
                        });

                      } catch (e) {

                      }
                      
                      // Send multiple notification events to ensure UI updates
                      stationService.notifyListeners();
                      Future.delayed(const Duration(milliseconds: 100), () {
                        stationService.notifyListeners();
                      });
                      
                      // CRITICAL: Force refresh the home screen to update energy display
                      HomeScreen.refreshHomeScreen();
                    } else {
                      // Update existing charging session in Firestore
                      final sessionId = sessions.first.id;
                      try {
                        // Prepare update data with explicit null check
                        Map<String, dynamic> updateData = {
                          'end_time': DateTime.now().toIso8601String(),
                          'energy_consumed': widget.energyConsumed,
                          'status': widget.isDepositPayment ? 'paused' : 'completed',
                          'amount': widget.amount // Always include amount for both deposit and final payments
                        };

                        // Print the full update data

                        updateData.forEach((key, value) {

                        });

                        final beforeDoc = await chargingSessionsRef.doc(sessionId).get();


                        
                        try {
                          await chargingSessionsRef.doc(sessionId).update(updateData);

                        } catch (e) {

                        }

                        // Verify the update
                        final updatedDoc = await chargingSessionsRef.doc(sessionId).get();

                        // Reward points functionality has been removed
                      } catch (e) {

                      }
                    }
                  } catch (e) {

                  }
                }
                
                // Navigate to home screen directly with force refresh flag

                // Ensure we force refresh even if the _chargingSessionCreated flag is not set
                if (!widget.isDepositPayment && widget.energyConsumed > 0) { // Only update energy for final payments
                  final stationService = Provider.of<StationService>(context, listen: false);
                  final authService = Provider.of<AuthService>(context, listen: false);
                  
                  // Make sure the energy value is updated regardless of session creation
                  if (authService.currentUser != null) {
                    final userId = authService.currentUser!.id!;
                    double currentEnergy = stationService.getCachedEnergyValue(userId);
                    double newTotalEnergy = currentEnergy + widget.energyConsumed;

                    // Store the final energy value for navigation
                    _finalEnergyValue = newTotalEnergy;
                    
                    // CRITICAL: Force set the exact value to ensure it shows up
                    await stationService.forceSetEnergyValue(userId, newTotalEnergy);
                    
                    // Create a permanent record of this energy transaction to avoid losing it
                    try {
                      await FirebaseFirestore.instance.collection('energy_records').add({
                        'user_id': userId,
                        'energy_consumed': widget.energyConsumed,
                        'timestamp': DateTime.now().toIso8601String(),
                        'description': 'Charging at ${widget.station.name}',
                      });

                    } catch (e) {

                    }
                    
                    // Send multiple notification events to ensure UI updates
                    stationService.notifyListeners();
                    Future.delayed(const Duration(milliseconds: 100), () {
                      stationService.notifyListeners();
                    });
                    
                    // CRITICAL: Force refresh the home screen before navigation
                    HomeScreen.refreshHomeScreen();
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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

        }
      }
    }
    
    // Fallback - return as is if we couldn't parse
    return rawChargerType;
  }
}
