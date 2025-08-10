import 'dart:async';
import 'package:flutter/material.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import '../models/charging_session.dart';
import '../services/fine_service.dart';
import 'payment_summary_screen.dart';

class ChargingScreen extends StatefulWidget {
  final Reservation reservation;
  final ChargingStation station;
  final Vehicle vehicle;
  final String chargerType;
  final Charger charger;

  const ChargingScreen({
    Key? key,
    required this.reservation,
    required this.station,
    required this.vehicle,
    required this.chargerType,
    required this.charger,
  }) : super(key: key);

  @override
  State<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends State<ChargingScreen> {
  // Charging states
  static const String pleasePlugIn = 'pleasePlugIn';
  static const String charging = 'charging';
  static const String paused = 'paused';
  static const String completed = 'completed';
  static const String chargerRemoved = 'chargerRemoved';

  // Current state
  String _currentState = pleasePlugIn;

  // Charging progress from 0.0 to 1.0
  double _chargingProgress = 0.0;

  // Battery percentage
  int _batteryPercentage = 0;

  // Energy consumed in kWh
  double _energyConsumed = 0.0;

  // Timer for simulation
  Timer? _chargingTimer;

  // Booking time in minutes
  int _totalBookingTime = 0;

  // Remaining time in minutes
  int _remainingTime = 0;

  // Actual time spent charging in minutes (incremented only when actively charging)
  double _actualChargingTimeMinutes = 0.0;

  // Charger power in kW (extracted from chargerType)
  late double _chargerPower;

  // Charging completion time
  DateTime? _chargingCompletedTime;

  // Timer for overtime tracking
  Timer? _overtimeTimer;

  // Overtime duration in minutes
  int _overtimeMinutes = 0;

  // Fine amount
  double _fineAmount = 0.0;

  // Grace period in minutes (reduced for 50kW fast chargers due to high demand)
  static const int _gracePeriodMinutes = 3;

  // Fine rate per minute (increased for 50kW fast chargers - RM 1.00 per minute)
  static const double _fineRatePerMinute = 1.00;

  // Fine service instance
  final FineService _fineService = FineService();

  // Current charging session ID (would be set when session starts)
  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    // Extract power from chargerType
    _extractPowerFromChargerType();
    // Initialize the booking time and remaining time from reservation
    _initializeBookingTime();
    // Start in pleasePlugIn state instead of auto-starting
    _currentState = pleasePlugIn;
  }

  void _extractPowerFromChargerType() {
    try {
      // Parse the charger power from the string format (e.g., "AC 11kW" -> 11.0)
      final powerString = widget.chargerType.split(' ')[1];
      _chargerPower = double.parse(powerString.replaceAll('kW', ''));
      print('Extracted charger power: $_chargerPower kW');
    } catch (e) {
      // Default to 50 kW if extraction fails
      _chargerPower = 50.0;
      print(
        'Failed to extract power from ${widget.chargerType}, using default: $_chargerPower kW',
      );
    }
  }

  void _initializeBookingTime() {
    setState(() {
      // Set booking time and remaining time from reservation duration
      _remainingTime = widget.reservation.duration;
      _totalBookingTime =
          widget
              .reservation
              .duration; // Use reservation duration as total booking time

      print('Initialized booking time: $_totalBookingTime minutes');
      print(
        'Expected total energy: ${(_chargerPower * _totalBookingTime / 60.0).toStringAsFixed(2)} kWh',
      );
    });
  }

  // When a charging completes, make sure it shows correct values
  void _handleCompletedState() {
    setState(() {
      _currentState = completed;
      _batteryPercentage = 100;
      _chargingProgress = 1.0;
      _chargingCompletedTime = DateTime.now();

      // Calculate the final energy consumption based on actual charging time
      // For 50kW charger: 1 second = 0.0139 kWh, 1 minute = 0.833 kWh
      _energyConsumed = (_chargerPower * _actualChargingTimeMinutes) / 60.0;

      print('Charging completed. Total energy: $_energyConsumed kWh');
    });

    // Start overtime tracking
    _startOvertimeTracking();
  }

  void _startOvertimeTracking() {
    _overtimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Allow overtime tracking for both paused and completed states
      if (_currentState != completed && _currentState != paused) {
        timer.cancel();
        return;
      }

      setState(() {
        final now = DateTime.now();
        final overtimeDuration = now.difference(_chargingCompletedTime!);
        _overtimeMinutes = overtimeDuration.inMinutes;

        // Calculate fine if overtime exceeds grace period
        if (_overtimeMinutes > _gracePeriodMinutes) {
          final fineableMinutes = _overtimeMinutes - _gracePeriodMinutes;
          _fineAmount = fineableMinutes * _fineRatePerMinute;
        } else {
          _fineAmount = 0.0;
        }
      });
    });
  }

  void _handleChargerRemoved() async {
    _overtimeTimer?.cancel();
    setState(() {
      _currentState = chargerRemoved;
    });

    // Update the charging session in the database if we have a session ID
    if (_currentSessionId != null) {
      try {
        await _fineService.updateSessionWithChargerRemoval(
          sessionId: _currentSessionId!,
          userId: widget.reservation.userId,
          chargerRemovedTime: DateTime.now(),
          fineAmount: _fineAmount,
        );
      } catch (e) {
        print('Error updating session with charger removal: $e');
        // Continue with payment even if database update fails
      }
    }

    // Proceed to payment with fine included
    _proceedToPaymentWithFine();
  }

  void _proceedToPaymentWithFine() async {
    // Navigate to payment summary screen with fine included
    final shouldContinueCharging = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (context) => PaymentSummaryScreen(
              reservation: widget.reservation,
              station: widget.station,
              vehicle: widget.vehicle,
              energyConsumed: _energyConsumed,
              chargingDuration: _totalBookingTime - _remainingTime,
              chargerType: widget.chargerType,
              charger: widget.charger,
              fineAmount: _fineAmount,
              overtimeMinutes: _overtimeMinutes,
              gracePeriodMinutes: _gracePeriodMinutes,
            ),
      ),
    );

    // If user pressed back, they can't continue charging after removal
    if (shouldContinueCharging == true) {
      // Show message that charger has been removed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Charger has been removed. Cannot continue charging.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  void dispose() {
    _chargingTimer?.cancel();
    _overtimeTimer?.cancel();
    super.dispose();
  }

  void _startCharging() {
    // Cancel any existing timer
    _chargingTimer?.cancel();

    // Start a new charging session
    setState(() {
      _currentState = charging;

      // Initialize charging values starting at 0%
      _chargingProgress = 0.0;
      _energyConsumed = 0.0;
      _batteryPercentage = 0;

      // Reset actual charging time if starting fresh
      _actualChargingTimeMinutes = 0.0;

      // For testing: Calculate expected energy for full 30 minutes at 11kW
      double expectedEnergyFor30Min =
          (_chargerPower * widget.reservation.duration) / 60.0;
      print(
        'Expected energy for ${widget.reservation.duration} min at $_chargerPower kW: $expectedEnergyFor30Min kWh',
      );
    });

    // Simulate charging progress
    _chargingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentState != charging) {
        return; // Do nothing if not in charging state
      }

      setState(() {
        // Decrease remaining time
        if (_remainingTime > 0) {
          _remainingTime -= 1;

          // Calculate actual minutes elapsed (1 second = 1/60 of a minute)
          _actualChargingTimeMinutes += 1.0 / 60.0;
        }

        // Calculate the percentage to progress evenly from 0% to 100% over the total time
        _batteryPercentage =
            ((_totalBookingTime - _remainingTime) * 100) ~/ _totalBookingTime;

        // Update charging progress based on percentage
        _chargingProgress = _batteryPercentage / 100;

        // Update energy consumed based on actual charging time only
        // Energy (kWh) = (Power (kW) × Actual Charging Minutes) ÷ 60
        // For 50kW charger: 1 second = 0.0139 kWh, 1 minute = 0.833 kWh
        _energyConsumed = _chargerPower * _actualChargingTimeMinutes / 60.0;

        // Debug output
        if (_remainingTime % 5 == 0) {
          print(
            'Progress: $_chargingProgress, Actual charging minutes: $_actualChargingTimeMinutes, Energy: $_energyConsumed kWh',
          );
        }

        // Ensure energy consumed never goes negative
        if (_energyConsumed < 0) {
          _energyConsumed = 0.0;
        }

        // Check if charging completed
        if (_remainingTime <= 0 || _batteryPercentage >= 100) {
          timer.cancel();
          _handleCompletedState();
        }
      });
    });
  }

  void _pauseCharging() {
    // Pause the charging process
    setState(() {
      _currentState = paused;
      _chargingCompletedTime =
          DateTime.now(); // Start tracking pause time for fine calculation
    });

    // Cancel the timer
    _chargingTimer?.cancel();

    // Start overtime tracking for paused state
    _startOvertimeTracking();
  }

  void _resumeCharging() {
    // Resume the charging process without resetting values
    setState(() {
      _currentState = charging;
      _chargingCompletedTime = null; // Clear pause time
    });

    // Cancel overtime tracking when resuming
    _overtimeTimer?.cancel();
    _overtimeMinutes = 0;
    _fineAmount = 0.0;

    // Restart the timer without reinitializing charging values
    _chargingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentState != charging) {
        return; // Do nothing if not in charging state
      }

      setState(() {
        // Decrease remaining time
        if (_remainingTime > 0) {
          _remainingTime -= 1;

          // Calculate actual minutes elapsed (1 second = 1/60 of a minute)
          _actualChargingTimeMinutes += 1.0 / 60.0;
        }

        // Calculate the percentage to progress evenly over time
        _batteryPercentage =
            ((_totalBookingTime - _remainingTime) * 100) ~/ _totalBookingTime;

        // Update charging progress based on percentage
        _chargingProgress = _batteryPercentage / 100;

        // Update energy consumed based on actual charging time only
        // Energy (kWh) = (Power (kW) × Actual Charging Minutes) ÷ 60
        // For 50kW charger: 1 second = 0.0139 kWh, 1 minute = 0.833 kWh
        _energyConsumed = _chargerPower * _actualChargingTimeMinutes / 60.0;

        // Ensure energy consumed never goes negative
        if (_energyConsumed < 0) {
          _energyConsumed = 0.0;
        }

        // Check if charging completed
        if (_remainingTime <= 0 || _batteryPercentage >= 100) {
          timer.cancel();
          _handleCompletedState();
        }
      });
    });
  }

  void _proceedToPayment() async {
    // Navigate to payment summary screen and get return value
    final shouldContinueCharging = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (context) => PaymentSummaryScreen(
              reservation: widget.reservation,
              station: widget.station,
              vehicle: widget.vehicle,
              energyConsumed: _energyConsumed,
              chargingDuration: _totalBookingTime - _remainingTime,
              chargerType: widget.chargerType,
              charger: widget.charger,
            ),
      ),
    );

    // If user pressed back, return to charging mode
    if (shouldContinueCharging == true) {
      _resumeCharging();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  // Status indicator
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor().withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getStatusIcon(),
                          color: _getStatusColor(),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            color: _getStatusColor(),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Charging progress indicator
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      children: [
                        // Background circle
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                          ),
                        ),

                        // Progress circle
                        if (_currentState == charging ||
                            _currentState == paused ||
                            _currentState == completed)
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: CircularProgressIndicator(
                              value: _chargingProgress,
                              strokeWidth: 10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _getProgressColor(),
                              ),
                              backgroundColor: Colors.grey[200],
                            ),
                          ),

                        // Center content
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_batteryPercentage%',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getProgressText(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Charging details
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Connector Type', widget.chargerType),
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          'Energy Consumed',
                          '${_energyConsumed.toStringAsFixed(2)} kWh',
                        ),
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          'Time Remaining',
                          '${_remainingTime ~/ 60}h ${_remainingTime % 60}m',
                        ),
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          'Charging Power',
                          '${_chargerPower.toStringAsFixed(1)} kW',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Vehicle details
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.directions_car, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailRow(
                                'Vehicle Model',
                                widget.vehicle.model,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.pin, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailRow(
                                'Vehicle Number',
                                widget.vehicle.plateNumber,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Station details
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.ev_station, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailRow(
                                'Station Name',
                                widget.station.name,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailRow(
                                'Booking Duration',
                                '${widget.reservation.duration ~/ 60}h ${widget.reservation.duration % 60}m',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildBottomActionButtons(),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_currentState) {
      case pleasePlugIn:
        return Colors.blue;
      case charging:
        return Colors.green;
      case paused:
        return Colors.orange;
      case completed:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentState) {
      case pleasePlugIn:
        return Icons.power_outlined;
      case charging:
        return Icons.bolt;
      case paused:
        return Icons.pause_circle_outline;
      case completed:
        return Icons.check_circle_outline;
      case chargerRemoved:
        return Icons.power_off;
      default:
        return Icons.error_outline;
    }
  }

  String _getStatusText() {
    switch (_currentState) {
      case pleasePlugIn:
        return 'Ready to Start';
      case charging:
        return 'Charging in Progress';
      case paused:
        return 'Charging Paused';
      case completed:
        if (_overtimeMinutes > 0) {
          if (_overtimeMinutes <= _gracePeriodMinutes) {
            return 'Charging Complete - Grace Period';
          } else {
            return 'Charging Complete - Overtime Fine Applied';
          }
        }
        return 'Charging Complete';
      case chargerRemoved:
        return 'Charger Removed';
      default:
        return 'Unknown State';
    }
  }

  Color _getProgressColor() {
    switch (_currentState) {
      case charging:
        return Theme.of(context).primaryColor;
      case paused:
        return Colors.orange;
      case completed:
        if (_overtimeMinutes > _gracePeriodMinutes) {
          return Colors.red; // Red when fine is applied
        }
        return Colors.green;
      case chargerRemoved:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getProgressText() {
    switch (_currentState) {
      case pleasePlugIn:
        return 'Not Started';
      case charging:
        return 'Charging';
      case paused:
        return 'Paused';
      case completed:
        return 'Complete';
      default:
        return '';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBottomActionButtons() {
    // Different bottom actions based on current state
    switch (_currentState) {
      case pleasePlugIn:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please plug in your vehicle to begin charging',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startCharging,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Start Charging',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );

      case charging:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _pauseCharging,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Pause Charging',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );

      case paused:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show overtime information if applicable
              if (_overtimeMinutes > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:
                        _overtimeMinutes > _gracePeriodMinutes
                            ? Colors.red[50]
                            : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          _overtimeMinutes > _gracePeriodMinutes
                              ? Colors.red[300]!
                              : Colors.orange[300]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _overtimeMinutes > _gracePeriodMinutes
                                ? Icons.warning
                                : Icons.info_outline,
                            color:
                                _overtimeMinutes > _gracePeriodMinutes
                                    ? Colors.red[700]
                                    : Colors.orange[700],
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _overtimeMinutes > _gracePeriodMinutes
                                      ? 'Overtime Fine Applied'
                                      : 'Grace Period Active',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        _overtimeMinutes > _gracePeriodMinutes
                                            ? Colors.red[700]
                                            : Colors.orange[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _overtimeMinutes > _gracePeriodMinutes
                                      ? 'Fine is being applied for paused time'
                                      : 'Resume charging within ${_gracePeriodMinutes - _overtimeMinutes} minutes to avoid fine',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Paused Duration:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '$_overtimeMinutes minutes',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_fineAmount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Fine Amount:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              'RM ${_fineAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Continue Charging button (primary action)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _resumeCharging,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Continue Charging',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Remove Charger & Proceed to Payment button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleChargerRemoved,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Remove Charger & Proceed to Payment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );

      case completed:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Overtime information if applicable
              if (_overtimeMinutes > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:
                        _overtimeMinutes > _gracePeriodMinutes
                            ? Colors.red[50]
                            : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          _overtimeMinutes > _gracePeriodMinutes
                              ? Colors.red[300]!
                              : Colors.orange[300]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _overtimeMinutes > _gracePeriodMinutes
                                ? Icons.warning
                                : Icons.info_outline,
                            color:
                                _overtimeMinutes > _gracePeriodMinutes
                                    ? Colors.red[700]
                                    : Colors.orange[700],
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _overtimeMinutes > _gracePeriodMinutes
                                      ? 'Overtime Fine Applied'
                                      : 'Grace Period Active',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        _overtimeMinutes > _gracePeriodMinutes
                                            ? Colors.red[700]
                                            : Colors.orange[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _overtimeMinutes > _gracePeriodMinutes
                                      ? 'Please remove charger to avoid additional charges'
                                      : 'Remove charger within ${_gracePeriodMinutes - _overtimeMinutes} minutes to avoid fine',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Overtime Duration:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '$_overtimeMinutes minutes',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_fineAmount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Fine Amount:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              'RM ${_fineAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Remove Charger & Proceed to Payment button (only option for completed state)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleChargerRemoved,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Remove Charger & Proceed to Payment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );

      case chargerRemoved:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Charger Removed Successfully',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Proceeding to payment...',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
