import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/station_service.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';
import '../services/vehicle_service.dart';
import '../models/reservation.dart';
import '../models/charging_station.dart';
import '../models/vehicle.dart';
import '../models/charger.dart';
import 'reservation_details_screen.dart';
import 'charging_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Reservation> _upcomingReservations = [];
  List<Reservation> _previousReservations = [];
  DateTime? _lastRefreshTime;

  @override
  bool get wantKeepAlive => false; // Don't keep alive to allow fresh data loading

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadData(forceRefresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Force reload when app is resumed
      _loadData(forceRefresh: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Don't call _loadData here as it can cause setState during build
    // Data loading is handled in initState and didChangeAppLifecycleState
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to manage reservations')),
        );
        Navigator.of(context).pushReplacementNamed('/login');
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final String userId = authService.currentUser!.id!;
      final now = DateTime.now();

      // Fetch reservations from Firestore
      final query =
          await FirebaseFirestore.instance
              .collection('reservations')
              .where('user_id', isEqualTo: userId)
              .get();

      final allReservations =
          query.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Reservation.fromMap(data);
          }).toList();

      // Split into upcoming and previous with improved filtering
      _upcomingReservations =
          allReservations.where((r) {
            // Only show confirmed or pending reservations that haven't been completed
            final isActive =
                (r.status == 'confirmed' || r.status == 'pending') &&
                r.status != 'completed';
            final isNotTooOld = r.startTime.isAfter(
              now.subtract(const Duration(minutes: 30)),
            );
            return isActive && isNotTooOld;
          }).toList();

      print('Upcoming reservations (${_upcomingReservations.length}):');
      for (var r in _upcomingReservations) {
        print('\u001b[34m${r.id} - ${r.status} - ${r.startTime}\u001b[0m');
      }

      _previousReservations =
          allReservations.where((r) {
            // Show completed, cancelled reservations or old reservations
            final isCompletedOrCancelled =
                r.status == 'completed' || r.status == 'cancelled';
            final isPast = r.startTime.isBefore(
              now.subtract(const Duration(minutes: 30)),
            );
            return isCompletedOrCancelled || isPast;
          }).toList();

      // Debug print
      print('Previous reservations (${_previousReservations.length}):');
      for (var r in _previousReservations) {
        print('\u001b[33m${r.id} - ${r.status} - ${r.startTime}\u001b[0m');
      }

      // Sort reservations by date (newest first)
      _upcomingReservations.sort((a, b) => a.startTime.compareTo(b.startTime));
      _previousReservations.sort((a, b) => b.startTime.compareTo(a.startTime));

      setState(() {
        _isLoading = false;
      });
      _lastRefreshTime = DateTime.now();
    } catch (e) {
      print('Error loading reservations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _lastRefreshTime = DateTime.now();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading reservations: $e'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _loadData(forceRefresh: true),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservations'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
            tooltip: 'Refresh reservations',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Previous')],
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildUpcomingReservationsList(),
                  _buildPreviousReservations(),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showStationsBottomSheet(
            Provider.of<StationService>(context, listen: false).stations,
          );
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildUpcomingReservationsList() {
    if (_upcomingReservations.isEmpty) {
      return _buildEmptyState('No upcoming reservations');
    }

    return ListView.builder(
      itemCount: _upcomingReservations.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final reservation = _upcomingReservations[index];
        return FutureBuilder<Widget>(
          future: _buildReservationCard(reservation),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            } else if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading reservation: ${snapshot.error}'),
                ),
              );
            } else {
              return snapshot.data ?? _buildEmptyReservationCard();
            }
          },
        );
      },
    );
  }

  Widget _buildEmptyReservationCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Reservation data unavailable'),
      ),
    );
  }

  Widget _buildPreviousReservations() {
    if (_previousReservations.isEmpty) {
      return _buildEmptyState('No previous reservations');
    }

    return ListView.builder(
      itemCount: _previousReservations.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final reservation = _previousReservations[index];
        return FutureBuilder<Widget>(
          future: _buildPreviousReservationCard(reservation),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            } else if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading reservation: ${snapshot.error}'),
                ),
              );
            } else {
              return snapshot.data ?? _buildEmptyReservationCard();
            }
          },
        );
      },
    );
  }

  void _showStationsBottomSheet(List<ChargingStation> stations) {
    // Filter out stations with no available spots
    final availableStations =
        stations.where((station) => station.availableSpots > 0).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SELECT A STATION',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child:
                          availableStations.isEmpty
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.ev_station_outlined,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No stations available',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Please try again later',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : ListView.builder(
                                controller: scrollController,
                                itemCount: availableStations.length,
                                itemBuilder: (context, index) {
                                  final station = availableStations[index];
                                  return _buildStationTile(station);
                                },
                              ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildStationTile(ChargingStation station) {
    final hasACCharger = station.chargers.any((c) => c.type == 'AC');
    final hasDCCharger = station.chargers.any((c) => c.type == 'DC');
    final highestACPower =
        hasACCharger
            ? station.chargers
                .where((c) => c.type == 'AC')
                .map((c) => c.power)
                .reduce((a, b) => a > b ? a : b)
            : 0;
    final highestDCPower =
        hasDCCharger
            ? station.chargers
                .where((c) => c.type == 'DC')
                .map((c) => c.power)
                .reduce((a, b) => a > b ? a : b)
            : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => ReservationDetailsScreen(station: station),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${station.availableSpots}/${station.totalSpots} spots available',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color:
                                  station.availableSpots > 0
                                      ? Colors.green
                                      : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (hasACCharger || hasDCCharger)
                            Text(
                              [
                                if (hasACCharger)
                                  'AC ${highestACPower.toStringAsFixed(0)}kW',
                                if (hasDCCharger)
                                  'DC ${highestDCPower.toStringAsFixed(0)}kW',
                              ].join(' / '),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _unlockCharger(Reservation reservation, ChargingStation station) async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Start Charging'),
            content: const Text(
              'Are you sure you want to start charging? Once you unlock the charger, this reservation cannot be cancelled and you will be charged for the complete session.',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _proceedWithUnlocking(reservation, station);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('PROCEED'),
              ),
            ],
          ),
    );
  }

  // This method handles the actual unlocking process
  void _proceedWithUnlocking(
    Reservation reservation,
    ChargingStation station,
  ) async {
    try {
      print(
        'Unlocking charger for reservation ${reservation.id}, chargerId: ${reservation.chargerId}',
      );

      if (reservation.chargerId == null) {
        throw Exception('No charger ID associated with this reservation');
      }

      // First refresh the station data to ensure we have the latest chargers
      final stationService = Provider.of<StationService>(
        context,
        listen: false,
      );
      await stationService.refreshChargerAvailabilityData();

      // Get the updated station with fresh charger data
      final updatedStationData = await stationService.getStationById(
        reservation.stationId,
      );
      final updatedStation = updatedStationData ?? station;

      print('Station has ${updatedStation.chargers.length} chargers');
      for (var c in updatedStation.chargers) {
        print('Available charger: ID=${c.id}, Name=${c.name}, Type=${c.type}');
      }

      // Get the charger directly from database
      Charger? chargerNullable;
      Charger? charger;
      try {
        chargerNullable = await stationService.getChargerByIdAsync(
          reservation.chargerId!,
        );
        if (chargerNullable == null) {
          throw Exception('Charger not found');
        }
        charger = chargerNullable;
        print(
          'Using charger: ID=${charger.id}, Name=${charger.name}, Type=${charger.type}, Power=${charger.power}kW',
        );
      } catch (e) {
        print('Failed to get charger from database: $e');
        // Show error dialog with retry option
        if (!mounted) return;
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Charger Not Found'),
                content: Text(
                  'Could not find charger information in the database. Error: ${e.toString()}',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _proceedWithUnlocking(reservation, station);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('RETRY'),
                  ),
                ],
              ),
        );
        return;
      }

      // Get the vehicle for this reservation
      final vehicleService = Provider.of<VehicleService>(
        context,
        listen: false,
      );
      final vehicle = await vehicleService.getVehicleById(
        reservation.vehicleId,
      );

      if (vehicle == null) {
        throw Exception('Vehicle not found');
      }

      // Navigate to charging screen
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder:
              (context) => ChargingScreen(
                reservation: reservation,
                station: updatedStation,
                vehicle: vehicle,
                chargerType:
                    charger!.type == 'DC' &&
                            charger.power >= 49 &&
                            charger.power < 51
                        ? 'DC 50kW'
                        : '${charger.type} ${charger.power.toStringAsFixed(1)}kW',
                charger: charger,
              ),
        ),
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      print('Error unlocking charger: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'RETRY',
            onPressed: () => _proceedWithUnlocking(reservation, station),
          ),
        ),
      );
    }
  }

  void _cancelReservation(Reservation reservation) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Reservation'),
            content: const Text(
              'Are you sure you want to cancel this reservation? 80% of your deposit will be refunded to your wallet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('NO'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  
                  // Get service references BEFORE any async operations to avoid widget disposal issues
                  final stationService = Provider.of<StationService>(
                    context,
                    listen: false,
                  );
                  final walletService = Provider.of<WalletService>(
                    context,
                    listen: false,
                  );
                  
                  setState(() => _isLoading = true);
                  try {
                    // Check if reservation ID is valid
                    if (reservation.id == null || reservation.id!.isEmpty) {
                      throw Exception(
                        'Invalid reservation ID. Cannot cancel reservation.',
                      );
                    }

                    final success = await stationService.cancelReservation(
                      reservation.id!,
                    );

                    if (!success) {
                      throw Exception(
                        'Failed to cancel reservation. Please try again.',
                      );
                    }

                    // Process 80% refund to wallet
                    final refundAmount =
                        reservation.deposit * 0.8; // 80% refund

                    final refundSuccess = await walletService.topUpWallet(
                      reservation.userId,
                      refundAmount,
                      'Refund for cancelled reservation at ${reservation.stationId}',
                    );

                    if (!refundSuccess) {
                      print('Warning: Reservation cancelled but refund failed');
                      // Don't throw error here as reservation is already cancelled
                    }

                    // Refresh the reservations list
                    await _loadData(forceRefresh: true);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reservation cancelled successfully.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error cancelling reservation: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                },
                child: const Text('YES', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTimeRange(DateTime start, int durationMinutes) {
    final end = start.add(Duration(minutes: durationMinutes));
    final startHour = start.hour.toString().padLeft(2, '0');
    final startMinute = start.minute.toString().padLeft(2, '0');
    final endHour = end.hour.toString().padLeft(2, '0');
    final endMinute = end.minute.toString().padLeft(2, '0');
    return '$startHour:$startMinute - $endHour:$endMinute';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<Widget> _buildReservationCard(Reservation reservation) async {
    final stationService = Provider.of<StationService>(context, listen: false);

    // Get station details - use a safe approach with null checking
    ChargingStation station;
    try {
      if (reservation.stationId != null) {
        final stationData = await stationService.getStationById(
          reservation.stationId,
        );
        if (stationData != null) {
          station = stationData;
        } else {
          station = ChargingStation(
            id: '0',
            name: 'Unknown Station',
            chargers: [],
            latitude: 0.0,
            longitude: 0.0,
          );
        }
      } else {
        station = ChargingStation(
          id: '0',
          name: 'Unknown Station',
          chargers: [],
          latitude: 0.0,
          longitude: 0.0,
        );
      }
    } catch (e) {
      print('Error getting station: $e');
      station = ChargingStation(
        id: '0',
        name: 'Unknown Station',
        chargers: [],
        latitude: 0.0,
        longitude: 0.0,
      );
    }

    // Get charger details - use a safe approach with null checking
    Charger? charger;
    try {
      if (reservation.chargerId != null) {
        charger = stationService.getChargerById(reservation.chargerId!);
      }
    } catch (e) {
      print('Error getting charger: $e');
    }

    // Default charger if not found
    charger ??= Charger.dc(
      id: '0',
      stationId: '0',
      name: 'Unknown Charger',
      power: 0.0,
      pricePerKWh: 0.0,
      isAvailable: false,
    );

    // Get vehicle details
    final vehicleService = Provider.of<VehicleService>(context, listen: false);
    Vehicle? vehicle;
    try {
      if (reservation.vehicleId != null) {
        vehicle = await vehicleService.getVehicleById(reservation.vehicleId);
      }
    } catch (e) {
      print('Error getting vehicle: $e');
    }

    // Default vehicle if not found
    vehicle ??= Vehicle(
      id: '0',
      userId: '0',
      brand: 'Unknown',
      model: 'Vehicle',
      plateNumber: 'N/A',
      isDefault: false,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.ev_station,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (charger != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        charger.type == 'DC' ? Icons.flash_on : Icons.bolt,
                        color:
                            charger.type == 'DC' ? Colors.orange : Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${charger.name} - ${charger.type} ${charger.power}kW',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(reservation.startTime),
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeRange(
                        reservation.startTime,
                        reservation.duration,
                      ),
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton.icon(
                      onPressed: () => _unlockCharger(reservation, station),
                      icon: const Icon(
                        Icons.lock_open,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Unlock',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelReservation(reservation),
                      icon: Icon(
                        Icons.cancel_outlined,
                        color: Colors.grey[700],
                        size: 20,
                      ),
                      label: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Widget> _buildPreviousReservationCard(Reservation reservation) async {
    final stationService = Provider.of<StationService>(context, listen: false);

    // Get station details - use a safe approach with null checking
    ChargingStation station;
    try {
      if (reservation.stationId != null) {
        final stationData = await stationService.getStationById(
          reservation.stationId,
        );
        if (stationData != null) {
          station = stationData;
        } else {
          station = ChargingStation(
            id: '0',
            name: 'Unknown Station',
            chargers: [],
            latitude: 0.0,
            longitude: 0.0,
          );
        }
      } else {
        station = ChargingStation(
          id: '0',
          name: 'Unknown Station',
          chargers: [],
          latitude: 0.0,
          longitude: 0.0,
        );
      }
    } catch (e) {
      print('Error getting station: $e');
      station = ChargingStation(
        id: '0',
        name: 'Unknown Station',
        chargers: [],
        latitude: 0.0,
        longitude: 0.0,
      );
    }

    // Get charger details - use a safe approach with null checking
    Charger? charger;
    try {
      if (reservation.chargerId != null) {
        charger = stationService.getChargerById(reservation.chargerId!);
      }
    } catch (e) {
      print('Error getting charger: $e');
    }

    // Default charger if not found
    charger ??= Charger.dc(
      id: '0',
      stationId: '0',
      name: 'Unknown Charger',
      power: 0.0,
      pricePerKWh: 0.0,
      isAvailable: false,
    );

    // Get vehicle details
    final vehicleService = Provider.of<VehicleService>(context, listen: false);
    Vehicle? vehicle;
    try {
      if (reservation.vehicleId != null) {
        vehicle = await vehicleService.getVehicleById(reservation.vehicleId);
      }
    } catch (e) {
      print('Error getting vehicle: $e');
    }

    // Default vehicle if not found
    vehicle ??= Vehicle(
      id: '0',
      userId: '0',
      brand: 'Unknown',
      model: 'Vehicle',
      plateNumber: 'N/A',
      isDefault: false,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.ev_station,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (charger != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        charger.type == 'DC' ? Icons.flash_on : Icons.bolt,
                        color:
                            charger.type == 'DC' ? Colors.orange : Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${charger.name} - ${charger.type} ${charger.power}kW',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(reservation.startTime),
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeRange(
                        reservation.startTime,
                        reservation.duration,
                      ),
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          reservation.status == 'completed'
                              ? Icons.check_circle
                              : Icons.cancel,
                          color:
                              reservation.status == 'completed'
                                  ? Colors.green
                                  : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          reservation.status == 'completed'
                              ? 'Completed'
                              : 'Cancelled',
                          style: TextStyle(
                            color:
                                reservation.status == 'completed'
                                    ? Colors.green
                                    : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
