import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import '../services/vehicle_service.dart';
import '../services/auth_service.dart';
import '../models/reservation.dart';
import 'payment_screen.dart';
import '../services/station_service.dart';

class ReservationDetailsScreen extends StatefulWidget {
  final ChargingStation station;

  const ReservationDetailsScreen({Key? key, required this.station})
    : super(key: key);

  @override
  State<ReservationDetailsScreen> createState() =>
      _ReservationDetailsScreenState();
}

class _ReservationDetailsScreenState extends State<ReservationDetailsScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _durationHours = 1;
  int _durationMinutes = 30;
  Vehicle? _selectedVehicle;
  Charger? _selectedCharger;
  bool _isLoading = true;
  List<Charger> _availableChargersForTimeSlot = [];
  bool _checkingAvailability = false;
  bool _previousChargerBecameUnavailable = false;
  String? _previousChargerName;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _initTimeSlot();
  }

  void _initTimeSlot() {
    // Initialize with default values for time slot
    // Tomorrow with current time
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _selectedTime = TimeOfDay.now();

    // Initialize duration to 1 hour 30 minutes
    _durationHours = 1;
    _durationMinutes = 30;

    // Check availability for this initial time slot
    _checkAvailabilityForTimeSlot();
  }

  // Convert selected date and time to a DateTime object
  DateTime _getStartDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  // Check which chargers are available for the selected time slot
  Future<void> _checkAvailabilityForTimeSlot() async {
    if (!mounted) return;

    // Remember the currently selected charger to try to restore it later
    final Charger? previouslySelectedCharger = _selectedCharger;
    final String? previousChargerName = previouslySelectedCharger?.name;

    setState(() {
      _checkingAvailability = true;
      _previousChargerBecameUnavailable = false;
      // Don't immediately reset selected charger, we'll try to preserve it
    });

    try {
      final stationService = Provider.of<StationService>(
        context,
        listen: false,
      );
      final startDateTime = _getStartDateTime();
      final totalMinutes = _totalDurationMinutes;

      print(
        'Checking availability for ${startDateTime.toIso8601String()} with duration $totalMinutes minutes',
      );
      print('Total chargers in station: ${widget.station.chargers.length}');

      // Print all chargers in the station for debugging
      print('ALL CHARGERS IN STATION:');
      for (final charger in widget.station.chargers) {
        print(
          'Charger ${charger.id}: ${charger.name} (${charger.type}, ${charger.power}kW) - ${charger.isAvailable ? "Available" : "Unavailable"}',
        );
      }

      // Create a list to store available chargers
      List<Charger> availableChargers = [];

      // Check each charger's availability for the selected time slot
      int checkedCount = 0;
      int skippedCount = 0;
      int availableCount = 0;
      int notAvailableCount = 0;

      for (final charger in widget.station.chargers) {
        if (charger.id == null) {
          print('Skipping charger with null ID: ${charger.name}');
          skippedCount++;
          continue;
        }

        // We no longer skip chargers just because they're marked as unavailable in the database
        // The most important factor is whether they have conflicting reservations
        // for the specific date and time we're checking

        checkedCount++;
        final isAvailable = await stationService.isChargerAvailableForTimeSlot(
          charger.id!,
          startDateTime,
          totalMinutes,
        );

        if (isAvailable) {
          print('Adding available charger: ${charger.name}');
          availableChargers.add(charger);
          availableCount++;
        } else {
          print(
            'Charger ${charger.name} is not available for the selected time slot',
          );
          notAvailableCount++;
        }
      }

      print('AVAILABILITY CHECK SUMMARY:');
      print('Total chargers: ${widget.station.chargers.length}');
      print('Checked: $checkedCount');
      print('Skipped: $skippedCount');
      print('Available: $availableCount');
      print('Not available due to scheduling: $notAvailableCount');

      if (mounted) {
        setState(() {
          _availableChargersForTimeSlot = availableChargers;
          _checkingAvailability = false;

          // Check if previously selected charger is still available
          if (previouslySelectedCharger != null &&
              availableChargers.any(
                (c) => c.id == previouslySelectedCharger.id,
              )) {
            // Keep the same charger selected if it's still available
            _selectedCharger = availableChargers.firstWhere(
              (c) => c.id == previouslySelectedCharger.id,
            );
            print(
              'Restored previously selected charger: ${_selectedCharger?.name}',
            );
            _previousChargerBecameUnavailable = false;
          } else if (previouslySelectedCharger != null) {
            // Previously selected charger is no longer available
            _previousChargerBecameUnavailable = true;
            _previousChargerName = previousChargerName;

            // Select the first available charger if there is one
            if (availableChargers.isNotEmpty) {
              _selectedCharger = availableChargers.first;
              print(
                'Previously selected charger became unavailable, selected first available: ${_selectedCharger?.name}',
              );
            } else {
              _selectedCharger = null;
              print(
                'Previously selected charger became unavailable and no others are available',
              );
            }
          } else if (availableChargers.isNotEmpty) {
            // First time selecting or no previous selection
            _selectedCharger = availableChargers.first;
            print(
              'Selected first available charger: ${_selectedCharger?.name}',
            );
          } else {
            // No chargers available
            _selectedCharger = null;
            print('No chargers available for selected time slot');
          }
        });
      }
    } catch (e) {
      print('Error checking charger availability: $e');
      if (mounted) {
        setState(() {
          _checkingAvailability = false;
          _availableChargersForTimeSlot = [];
          _selectedCharger = null;
        });
      }
    }
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final vehicleService = Provider.of<VehicleService>(context, listen: false);

    // Ensure user is logged in
    if (authService.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to make reservations')),
        );
        Navigator.pop(context);
      }
      return;
    }

    // Load vehicles for the logged in user
    final String userId = authService.currentUser!.id!;
    await vehicleService.loadUserVehicles(userId);

    final vehicles = vehicleService.vehicles;
    if (vehicles.isNotEmpty) {
      setState(() {
        _selectedVehicle = vehicleService.getDefaultVehicle();
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  // Helper method to update time slot and check availability
  void _updateTimeSlotAndCheckAvailability({
    DateTime? date,
    TimeOfDay? time,
    int? hours,
    int? minutes,
  }) {
    setState(() {
      if (date != null) _selectedDate = date;
      if (time != null) _selectedTime = time;
      if (hours != null) _durationHours = hours;
      if (minutes != null) _durationMinutes = minutes;
    });

    // After updating the state, check availability for the new time slot
    _checkAvailabilityForTimeSlot();
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (pickedDate != null && pickedDate != _selectedDate) {
      // If user selects today, validate that the current time is not in the past
      final now = DateTime.now();
      if (pickedDate.year == now.year &&
          pickedDate.month == now.month &&
          pickedDate.day == now.day) {
        // If selecting today, check if current selected time is in the past
        final selectedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        );

        if (selectedDateTime.isBefore(now)) {
          // Update time to current time if it's in the past
          _selectedTime = TimeOfDay.now();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Time updated to current time since past time is not allowed',
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }

      _updateTimeSlotAndCheckAvailability(date: pickedDate);
    }
  }

  Future<void> _selectTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (pickedTime != null && pickedTime != _selectedTime) {
      // Check if the selected time is valid (current time or future)
      final selectedDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );

      final now = DateTime.now();

      // If selected date is today, ensure time is not in the past
      if (_selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day) {
        if (selectedDateTime.isBefore(now)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please select current time or future time for reservation',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      _updateTimeSlotAndCheckAvailability(time: pickedTime);
    }
  }

  void _incrementDuration() {
    // First, calculate the new duration
    int newMinutes = _durationMinutes + 30;
    int newHours = _durationHours;

    if (newMinutes >= 60) {
      newHours++;
      newMinutes = 0;
    }

    // Check if the new duration exceeds 3 hours (180 minutes)
    int totalNewMinutes = (newHours * 60) + newMinutes;
    if (totalNewMinutes > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum reservation duration is 3 hours'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _updateTimeSlotAndCheckAvailability(hours: newHours, minutes: newMinutes);
  }

  void _decrementDuration() {
    if (_durationHours == 0 && _durationMinutes <= 30) {
      return; // Minimum duration is 30 minutes
    }

    // Calculate the new duration
    int newMinutes = _durationMinutes - 30;
    int newHours = _durationHours;

    if (newMinutes < 0) {
      newHours--;
      newMinutes = 30;
    }

    _updateTimeSlotAndCheckAvailability(hours: newHours, minutes: newMinutes);
  }

  int get _totalDurationMinutes => (_durationHours * 60) + _durationMinutes;

  double get _chargingFee {
    if (_selectedCharger != null) {
      // Calculate estimated energy consumption: (power in kW × time in minutes) ÷ 60
      double estimatedEnergyKWh =
          (_selectedCharger!.power * _totalDurationMinutes) / 60.0;
      // Calculate cost based on price per kWh
      return estimatedEnergyKWh * _selectedCharger!.pricePerKWh;
    } else {
      // Fallback to station average if no charger selected
      // Calculate based on average power and price per kWh
      double averagePowerKW = 22.0; // Assume an average value
      double estimatedEnergyKWh =
          (averagePowerKW * _totalDurationMinutes) / 60.0;
      return estimatedEnergyKWh * widget.station.pricePerKWh;
    }
  }

  double get _depositAmount => 30.0; // Fixed deposit amount

  void _proceedToPayment() {
    if (_selectedVehicle == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a vehicle')));
      return;
    }

    if (_selectedCharger == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a charger')));
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);

    // Ensure user is logged in
    if (authService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to make reservations')),
      );
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    final String userId = authService.currentUser!.id!;

    // Combine date and time for the start time
    final startTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final Reservation reservation = Reservation(
      userId: userId,
      stationId: widget.station.id!,
      vehicleId: _selectedVehicle!.id!,
      paymentMethodId: '0', // Temporary ID, will be updated during payment
      startTime: startTime,
      duration: _totalDurationMinutes,
      deposit: _depositAmount,
      status: 'pending',
      chargerId: _selectedCharger!.id!,
    );

    // Navigate to payment screen for deposit payment
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PaymentScreen(
              reservation: reservation,
              station: widget.station,
              vehicle: _selectedVehicle!,
              charger: _selectedCharger!,
              isDepositPayment: true, // Add this flag
              depositAmount: _depositAmount, // Pass the deposit amount
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Charger Reservation'), elevation: 0),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Station image
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          'https://images.unsplash.com/photo-1593941707882-a5bba15151e7?q=80&w=1172&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => const Icon(
                                Icons.ev_station,
                                size: 80,
                                color: Colors.grey,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Reservation details card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fill in Your Reservation Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Vehicle selection
                          const Text(
                            'Vehicle Type:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Consumer<VehicleService>(
                            builder: (context, vehicleService, child) {
                              final vehicles = vehicleService.vehicles;

                              if (vehicles.isEmpty) {
                                return const Text(
                                  'No vehicles added. Please add a vehicle in your account.',
                                );
                              }

                              return DropdownButtonFormField<Vehicle>(
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                value: _selectedVehicle,
                                items:
                                    vehicles.map((vehicle) {
                                      return DropdownMenuItem<Vehicle>(
                                        value: vehicle,
                                        child: Text(
                                          '${vehicle.brand} ${vehicle.model}',
                                        ),
                                      );
                                    }).toList(),
                                onChanged: (vehicle) {
                                  setState(() {
                                    _selectedVehicle = vehicle;
                                  });
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Vehicle number
                          const Text(
                            'Vehicle Number:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedVehicle?.plateNumber ??
                                  'No vehicle selected',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Location
                          const Text(
                            'Location:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.station.name,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Icon(Icons.location_on_outlined),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Charger selection
                          const Text(
                            'Select Charger:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          _buildChargerSelector(),
                          const SizedBox(height: 16),

                          // Date selection
                          const Text(
                            'Start Time:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _selectDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _selectTime,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _selectedTime.format(context),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const Icon(Icons.access_time, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Duration selection
                          const Text(
                            'Duration:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_durationHours} hours ${_durationMinutes} minutes',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: _decrementDuration,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.remove,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: _incrementDuration,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.add,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Constraint information
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Reservations can only be made for current or future time. Maximum duration is 3 hours.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Charging fee
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Charging Fee:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _selectedCharger != null
                                      ? 'RM${_selectedCharger!.pricePerKWh.toStringAsFixed(2)} / kWh'
                                      : 'RM${widget.station.pricePerKWh.toStringAsFixed(2)} / kWh',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Total amount
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Amount:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'RM${_chargingFee.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Deposit
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Deposit:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'RM${_depositAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Proceed to payment button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _proceedToPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Proceed to Payment',
                          style: TextStyle(
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

  Widget _buildChargerSelector() {
    // Show a loading indicator while checking availability
    if (_checkingAvailability) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking availability...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    // Sort available chargers by name for consistent display
    final availableChargers =
        _availableChargersForTimeSlot.toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    if (availableChargers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No chargers available for selected time',
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              'Selected time: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} at ${_selectedTime.format(context)}',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            if (_previousChargerBecameUnavailable &&
                _previousChargerName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Your previous selection "$_previousChargerName" is not available at this time',
                      style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Try a different date or time',
                    style: TextStyle(fontSize: 14, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Charger>(
              isExpanded: true,
              value: _selectedCharger,
              items:
                  availableChargers.map((charger) {
                    String chargerType =
                        charger.type == 'AC' ? 'AC' : 'DC Fast';
                    String powerOutput =
                        '${charger.power.toStringAsFixed(1)} kW';
                    return DropdownMenuItem<Charger>(
                      value: charger,
                      child: Text(
                        '${charger.name} (${chargerType}, ${powerOutput})',
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  }).toList(),
              onChanged: (charger) {
                setState(() {
                  _selectedCharger = charger;
                });
              },
            ),
          ),
        ),

        if (_previousChargerBecameUnavailable &&
            _previousChargerName != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange[700],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Your previous selection "$_previousChargerName" is not available at this time',
                    style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                  ),
                ),
              ],
            ),
          ),
        ],

        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(
                'Available at selected time',
                style: TextStyle(fontSize: 14, color: Colors.green[700]),
              ),
            ],
          ),
        ),

        if (_selectedCharger != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                Icon(
                  _selectedCharger!.type == 'AC' ? Icons.bolt : Icons.flash_on,
                  color:
                      _selectedCharger!.type == 'AC'
                          ? Colors.blue
                          : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_selectedCharger!.type} · ${_selectedCharger!.power.toStringAsFixed(1)} kW',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
