import 'package:flutter/material.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import 'payment_methods_screen.dart';

class PaymentScreen extends StatelessWidget {
  final Reservation reservation;
  final ChargingStation station;
  final Vehicle vehicle;
  final Charger charger;
  final bool isDepositPayment;
  final double depositAmount;

  const PaymentScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.vehicle,
    required this.charger,
    this.isDepositPayment = false,
    this.depositAmount = 30.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final totalFee = isDepositPayment 
        ? depositAmount 
        : charger.pricePerKWh * (charger.power * reservation.duration / 60.0) - reservation.deposit;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isDepositPayment ? 'Pay Deposit' : 'Pay'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Deposit Information'),
                  content: const Text(
                    'A refundable deposit of RM30.00 is required to secure your reservation. '
                    'If you cancel your reservation, 80% of the deposit will be refunded to your wallet.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Station and Vehicle Info
            Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    station.address,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.directions_car, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${vehicle.brand} ${vehicle.model}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (!isDepositPayment) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildInfoCard(
                      icon: Icons.timer,
                      value: '${reservation.duration ~/ 60}:${(reservation.duration % 60).toString().padLeft(2, '0')}',
                      label: 'Duration',
                    ),
                    _buildInfoCard(
                      icon: Icons.bolt,
                      value: '${((charger.power * reservation.duration) / 60.0).toStringAsFixed(1)} kWh',
                      label: 'Energy',
                    ),
                  ],
                ),
              ),
            ],
            
            // Payment Details
            Container(
              margin: const EdgeInsets.all(24),
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
                children: [
                  if (isDepositPayment) ...[
                    _buildPaymentRow(
                      'Deposit Amount',
                      'RM ${depositAmount.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 8),
                    Container(
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
                              '80% of deposit will be refunded if reservation is cancelled',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _buildPaymentRow(
                      'Charging Fee',
                      'RM ${((charger.power * reservation.duration / 60.0) * charger.pricePerKWh).toStringAsFixed(2)}',
                    ),
                    _buildPaymentRow(
                      'Unit Price',
                      'RM ${charger.pricePerKWh.toStringAsFixed(2)}/kWh',
                    ),
                    _buildPaymentRow(
                      'Reservation Deposit',
                      '- RM ${reservation.deposit.toStringAsFixed(2)}',
                      isDeduction: true,
                    ),
                  ],
                  const Divider(height: 32),
                  _buildPaymentRow(
                    isDepositPayment ? 'Total Deposit' : 'Total Fee',
                    'RM ${totalFee.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),
            
            // Continue Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PaymentMethodsScreen(
                        reservation: reservation,
                        station: station,
                        charger: charger,
                        isDepositPayment: isDepositPayment,
                        depositAmount: depositAmount,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isDepositPayment ? 'Pay Deposit' : 'Continue To Pay',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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

  Widget _buildInfoCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String label, String value, {bool isDeduction = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDeduction ? Colors.red : Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDeduction ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
} 