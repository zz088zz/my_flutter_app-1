import 'package:flutter/material.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import 'payment_methods_screen.dart';
import 'refund_wallet_screen.dart';

class PaymentSummaryScreen extends StatelessWidget {
  final Reservation reservation;
  final ChargingStation station;
  final Vehicle vehicle;
  final double energyConsumed;
  final int chargingDuration; // in minutes
  final String chargerType; // Add charger type property
  final Charger charger; // Add charger property
  final double fineAmount; // Fine amount for overtime
  final int overtimeMinutes; // Overtime duration in minutes
  final int gracePeriodMinutes; // Grace period in minutes

  const PaymentSummaryScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.vehicle,
    required this.energyConsumed,
    required this.chargingDuration,
    required this.chargerType, // Add charger type parameter
    required this.charger, // Add charger parameter
    this.fineAmount = 0.0, // Fine amount for overtime
    this.overtimeMinutes = 0, // Overtime duration in minutes
    this.gracePeriodMinutes =
        3, // Grace period in minutes (for 50kW fast chargers)
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Define a base price per kWh based on charger type
    final double pricePerKWh =
        chargerType.contains('DC') ? 1.30 : 0.80; // Set price based on type

    // Calculate charging fee based on energy consumed and price per kWh
    final chargingFee = double.parse(
      (energyConsumed * pricePerKWh).toStringAsFixed(2),
    );

    // Format duration as hh:mm:ss exactly as used time
    final hours = chargingDuration ~/ 60;
    final minutes = chargingDuration % 60;
    final seconds = 0; // Since we track only in minutes
    final durationText =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Use full deposit amount instead of 80%
    final depositAmount = reservation.deposit;

    // Calculate total fee (charging fee + fine - full deposit)
    // Round to 2 decimal places for consistency with other screens
    final totalFee = double.parse(
      (chargingFee + fineAmount - depositAmount).toStringAsFixed(2),
    );

    // LOGGING: For debugging payment calculations
    print('PAYMENT SUMMARY CALCULATION:');
    print('Energy consumed: $energyConsumed kWh');
    print('Price per kWh: $pricePerKWh');
    print('Charging fee: $chargingFee');
    print('Fine amount: $fineAmount');
    print('Deposit amount: $depositAmount');
    print('Total fee: $totalFee');

    // Check if this is a refund situation (negative total fee or negative kWh)
    final isRefund = totalFee < 0 || energyConsumed < 0;

    // If it's a refund, the amount should be positive for display
    final displayAmount = isRefund ? totalFee.abs() : totalFee;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isRefund ? 'Refund' : 'Pay'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context, true);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (context) => Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        width: 280,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'INFORMATION',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Charging Calculation:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Energy Consumed (kWh) × RM${pricePerKWh.toStringAsFixed(2)} per kWh',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                minimumSize: const Size(120, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text(
                                'Confirm',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Plug type and vehicle details
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          chargerType,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Vehicle image
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[200],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              'https://images.unsplash.com/photo-1549399542-7e8f2e928464?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, error, stackTrace) => const Center(
                                    child: Icon(
                                      Icons.directions_car,
                                      size: 80,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Charging details
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTimeEnergyBox(
                              context,
                              Icons.access_time,
                              durationText,
                              Colors.orange,
                            ),
                            const SizedBox(width: 16),
                            _buildTimeEnergyBox(
                              context,
                              Icons.bolt,
                              '${energyConsumed.toStringAsFixed(1)} kWh',
                              energyConsumed < 0 ? Colors.red : Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFEEEEEE),
                  ),

                  // Payment details
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Charging fee
                        _buildPaymentRow(
                          'Charging Fee',
                          isRefund && chargingFee < 0
                              ? '- RM ${chargingFee.abs().toStringAsFixed(2)}'
                              : 'RM ${chargingFee.toStringAsFixed(2)}',
                          isRefund && chargingFee < 0
                              ? Colors.red
                              : Color(0xFF4285F4),
                          isBold: false,
                        ),
                        const SizedBox(height: 10),

                        // Unit price
                        _buildPaymentRow(
                          'Unit Price',
                          'RM ${pricePerKWh.toStringAsFixed(2)}/kWh',
                          Colors.grey[800]!,
                          isBold: false,
                        ),
                        const SizedBox(height: 10),

                        // Transaction fee
                        _buildPaymentRow(
                          'Transaction Fee',
                          'RM 0.00',
                          Colors.grey,
                          isBold: false,
                        ),
                        const SizedBox(height: 10),

                        // Fine amount (if applicable)
                        if (fineAmount > 0) ...[
                          _buildPaymentRow(
                            'Overtime Fine',
                            'RM ${fineAmount.toStringAsFixed(2)}',
                            Colors.red,
                            isBold: false,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              'Overtime: $overtimeMinutes min (Grace: $gracePeriodMinutes min)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // Reservation deposit refund
                        _buildPaymentRow(
                          'Reservation Deposit',
                          '- RM ${depositAmount.toStringAsFixed(2)}',
                          Colors.green,
                          isBold: false,
                        ),
                        const SizedBox(height: 10),

                        // Points earned (only show if charging fee > 0)
                        if (chargingFee > 0) ...[
                          _buildPaymentRow(
                            'Points Earned',
                            '${chargingFee.toStringAsFixed(2)} pts',
                            Colors.orange,
                            isBold: false,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              '1 point per RM 1 spent',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        const Divider(thickness: 1, color: Color(0xFFEEEEEE)),
                        const SizedBox(height: 16),

                        // Total fee or refund
                        _buildPaymentRow(
                          isRefund ? 'Total Refund' : 'Total Fee',
                          'RM ${displayAmount.toStringAsFixed(2)}',
                          isRefund ? Colors.green : Color(0xFF4285F4),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action button (Pay or Refund)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x29000000),
                  offset: Offset(0, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                if (isRefund) {
                  // For refund process
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => RefundWalletScreen(
                            reservation: reservation,
                            station: station,
                            refundAmount: displayAmount,
                            energyConsumed: energyConsumed.abs(),
                            chargingDuration: chargingDuration,
                            chargerType: chargerType,
                          ),
                    ),
                  );
                } else {
                  // For normal payment process - ensure we pass all necessary data and the exact total amount
                  print('Navigating to payment with total fee: $totalFee');

                  // Calculate energy consumed to pass to the next screen
                  final energyConsumed = this.energyConsumed;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => PaymentMethodsScreen(
                            reservation: reservation.copyWith(
                              // Ensure we pass the actual energy consumed & duration to calculate accurately
                              duration: chargingDuration,
                            ),
                            station: station,
                            charger: charger.copyWith(
                              // Override charger properties to ensure consistency
                              pricePerKWh: pricePerKWh,
                              power:
                                  energyConsumed /
                                  (chargingDuration /
                                      60.0), // Ensure power will give us same energy
                            ),
                            isDepositPayment:
                                false, // This is not a deposit payment
                            depositAmount:
                                depositAmount, // Pass the original deposit amount for calculation
                            fineAmount: fineAmount, // Pass the fine amount
                          ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isRefund ? Colors.indigo : Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isRefund ? 'Refund To EV Wallet' : 'Continue To Pay',
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
    );
  }

  Widget _buildTimeEnergyBox(
    BuildContext context,
    IconData icon,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(
    String label,
    String amount,
    Color color, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: Colors.black87,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
