import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../services/wallet_service.dart';
import '../services/station_service.dart';
import '../main.dart' as app_main;
import 'package:cloud_firestore/cloud_firestore.dart';

class RefundWalletScreen extends StatefulWidget {
  final Reservation reservation;
  final ChargingStation station;
  final double refundAmount;
  final double energyConsumed;
  final int chargingDuration;
  final String chargerType;
  final double fineAmount;
  final int? overtimeMinutes;
  final int? gracePeriodMinutes;

  const RefundWalletScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.refundAmount,
    required this.energyConsumed,
    required this.chargingDuration,
    required this.chargerType,
    this.fineAmount = 0.0,
    this.overtimeMinutes,
    this.gracePeriodMinutes,
  }) : super(key: key);

  @override
  State<RefundWalletScreen> createState() => _RefundWalletScreenState();
}

class _RefundWalletScreenState extends State<RefundWalletScreen> {
  bool _isProcessing = false;
  bool _isRefunded = false;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _processRefund();
  }
  
  Future<void> _processRefund() async {
    if (_isProcessing || _isRefunded) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final walletService = Provider.of<WalletService>(context, listen: false);
      
      // Add the refund amount to the user's wallet
      await walletService.topUpWallet(
        widget.reservation.userId, 
        widget.refundAmount,
        'Refund for charging at ${widget.station.name}'
      );
      
      // Mark the reservation as completed
      if (widget.reservation.id != null) {
        // Update reservation status in Firestore
        await FirebaseFirestore.instance
            .collection('reservations')
            .doc(widget.reservation.id)
            .update({'status': 'completed'});
        
        print('Updated reservation ${widget.reservation.id} status to completed');
      }
      
      // Update charger availability by making it available again
      if (widget.reservation.chargerId != null) {
        final stationService = Provider.of<StationService>(context, listen: false);
        
        // Set the charger as available
        await stationService.updateChargerAvailability(
          widget.reservation.stationId, 
          widget.reservation.chargerId!, 
          true // isAvailable = true
        );
      }
      
      // Show completed state
      setState(() {
        _isProcessing = false;
        _isRefunded = true;
      });
    } catch (e) {
      print('Error processing refund: $e');
      setState(() {
        _isProcessing = false;
        _error = 'Failed to process refund. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund to Wallet'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: _isProcessing
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _processRefund,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Success Icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green[700],
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Refund Successful!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Transaction Details Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            'Station',
                            widget.station.name,
                            showDivider: true,
                          ),
                          _buildDetailRow(
                            'Duration',
                            '${widget.chargingDuration} minutes',
                            showDivider: true,
                          ),
                          _buildDetailRow(
                            'Energy Used',
                            '${widget.energyConsumed.toStringAsFixed(2)} kWh',
                            showDivider: true,
                          ),
                          _buildDetailRow(
                            'Refund Method',
                            'E-Wallet',
                            showDivider: true,
                          ),
                          // Show fine amount and overtime details if applicable
                          if (widget.fineAmount > 0) ...[  
                            _buildDetailRow(
                              'Overtime Fine',
                              'RM ${widget.fineAmount.toStringAsFixed(2)}',
                              isAmount: false,
                              showDivider: true,
                            ),
                            // Add overtime minutes and grace period information
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            Divider(
                              height: 1,
                              color: Colors.grey[200],
                            ),
                          ],
                          _buildDetailRow(
                            'Refund Amount',
                            'RM ${widget.refundAmount.toStringAsFixed(2)}',
                            isAmount: true,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Done Button
                    ElevatedButton(
                      onPressed: () {
                        // Navigate directly to MainScreen
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => app_main.MainScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool showDivider = true, bool isAmount = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isAmount ? Colors.green[700] : Colors.black,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: Colors.grey[200],
          ),
      ],
    );
  }
}