import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import '../models/charging_session.dart';
import '../services/fine_service.dart';
import 'payment_methods_screen.dart';
import 'refund_wallet_screen.dart';

class PaymentSummaryScreen extends StatefulWidget {
  final Reservation reservation;
  final ChargingStation station;
  final Vehicle vehicle;
  final double energyConsumed;
  final int chargingDuration; // in minutes
  final String chargerType; // Add charger type property
  final Charger charger;  // Add charger property
  final double fineAmount; // Fine amount for overtime
  final int overtimeMinutes; // Minutes of overtime
  final int gracePeriodMinutes; // Grace period in minutes
  
  const PaymentSummaryScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.vehicle,
    required this.energyConsumed,
    required this.chargingDuration,
    required this.chargerType, // Add charger type parameter
    required this.charger,  // Add charger parameter
    this.fineAmount = 0.0, // Default to no fine
    this.overtimeMinutes = 0, // Default to no overtime
    this.gracePeriodMinutes = 3, // Default grace period
  }) : super(key: key);
  
  @override
  State<PaymentSummaryScreen> createState() => _PaymentSummaryScreenState();
}

class _PaymentSummaryScreenState extends State<PaymentSummaryScreen> {
  late double pricePerKWh;
  late double chargingFee;
  late double depositAmount;
  late double totalFee;
  late bool isRefund;
  late double displayAmount;
  late String durationText;
  
  // Fine amount (if any)
  double fineAmount = 0.0;
  
  @override
  void initState() {
    super.initState();
    
    // Define a base price per kWh based on charger type
    pricePerKWh = widget.chargerType.contains('DC') ? 1.30 : 0.80; // Set price based on type
    
    // Calculate charging fee based on energy consumed and price per kWh
    chargingFee = double.parse((widget.energyConsumed * pricePerKWh).toStringAsFixed(2));
    
    // Format duration as hh:mm:ss exactly as used time
    final hours = widget.chargingDuration ~/ 60;
    final minutes = widget.chargingDuration % 60;
    final seconds = 0; // Since we track only in minutes
    durationText = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    
    // Use full deposit amount instead of 80%
    depositAmount = widget.reservation.deposit;
    
    // Use fine amount from constructor parameter
    fineAmount = widget.fineAmount;
    
    // Calculate total fee (charging fee - deposit + fine)
    totalFee = double.parse((chargingFee - depositAmount + fineAmount).toStringAsFixed(2));
    
    // Check if this is a refund situation (negative total fee only)
    isRefund = totalFee < 0;
    
    // If it's a refund, the amount should be positive for display
    displayAmount = isRefund ? totalFee.abs() : totalFee;
    
    // LOGGING: For debugging payment calculations
    print('PAYMENT SUMMARY CALCULATION:');
    print('Energy consumed: ${widget.energyConsumed} kWh');
    print('Price per kWh: $pricePerKWh');
    print('Charging fee: $chargingFee');
    print('Deposit amount: $depositAmount');
    print('Fine amount: $fineAmount');
    print('Overtime minutes: ${widget.overtimeMinutes}');
    print('Grace period minutes: ${widget.gracePeriodMinutes}');
    print('Total fee: $totalFee');
  }
  
  // Check if there are any fines associated with this session
  // This method is no longer needed as we're using the fine amount passed from the constructor
  // Keeping it as a placeholder in case we need to fetch additional fine information in the future
  Future<void> _checkForFines() async {
    // Fine amount is now passed directly from the charging screen
    print('Using fine amount passed from constructor: $fineAmount');
  }
  
  @override
  Widget build(BuildContext context) {

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
                builder: (context) => Dialog(
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
                          style: const TextStyle(
                            fontSize: 14,
                          ),
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
                          widget.chargerType,
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
                              errorBuilder: (context, error, stackTrace) => const Center(
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
                              '${widget.energyConsumed.toStringAsFixed(1)} kWh',
                              widget.energyConsumed < 0 ? Colors.red : Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                  
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
                          isRefund && chargingFee < 0 ? Colors.red : Color(0xFF4285F4),
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
                        
                        // Reservation deposit refund
                        _buildPaymentRow(
                          'Reservation Deposit',
                          '- RM ${depositAmount.toStringAsFixed(2)}',
                          Colors.green,
                          isBold: false,
                        ),
                        
                        // Fine amount and overtime details (if any)
                        if (fineAmount > 0) ...[  
                          const SizedBox(height: 10),
                          _buildPaymentRow(
                            'Overtime Fine',
                            'RM ${fineAmount.toStringAsFixed(2)}',
                            Colors.red,
                            isBold: false,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Overtime: ${widget.overtimeMinutes} minutes',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Text(
                                'Grace period: ${widget.gracePeriodMinutes} minutes',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
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
                      builder: (context) => RefundWalletScreen(
                        reservation: widget.reservation,
                        station: widget.station,
                        refundAmount: displayAmount,
                        energyConsumed: widget.energyConsumed.abs(),
                        chargingDuration: widget.chargingDuration,
                        chargerType: widget.chargerType,
                        fineAmount: fineAmount,
                        overtimeMinutes: widget.overtimeMinutes,
                        gracePeriodMinutes: widget.gracePeriodMinutes,
                      ),
                    ),
                  );
                } else {
                  // For normal payment process - ensure we pass all necessary data and the exact total amount
                  print('Navigating to payment with total fee: $totalFee');
                  
                  // Calculate energy consumed to pass to the next screen
                  final energyConsumed = widget.energyConsumed;
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PaymentMethodsScreen(
                        reservation: widget.reservation.copyWith(
                          // Ensure we pass the actual energy consumed & duration to calculate accurately
                          duration: widget.chargingDuration,
                        ),
                        station: widget.station,
                        charger: widget.charger.copyWith(
                          // Override charger properties to ensure consistency
                          pricePerKWh: pricePerKWh,
                          power: energyConsumed / (widget.chargingDuration / 60.0), // Ensure power will give us same energy 
                        ),
                        isDepositPayment: false, // This is not a deposit payment
                        depositAmount: depositAmount, // Pass the original deposit amount for calculation
                        fineAmount: fineAmount, // Pass the fine amount for calculation
                        overtimeMinutes: widget.overtimeMinutes, // Pass overtime minutes
                        gracePeriodMinutes: widget.gracePeriodMinutes, // Pass grace period minutes
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isRefund ? Colors.indigo : Theme.of(context).primaryColor,
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
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