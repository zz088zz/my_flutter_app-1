import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/station_service.dart';
import '../services/auth_service.dart';
import '../services/vehicle_service.dart';
import '../services/refund_service.dart';
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

class _ReservationScreenState extends State<ReservationScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isLoading = true;
  List<Reservation> _upcomingReservations = [];
  List<Reservation> _previousReservations = [];
  DateTime? _lastRefreshTime;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadData(forceRefresh: true);
    
    // Add timeout protection
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isLoading) {
        print('WARNING: Reservation loading timeout - forcing completion');
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading timeout. Please try again.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    // Only reload data if sufficient time has passed (at least 2 seconds) or never loaded
    final now = DateTime.now();
    if (_lastRefreshTime == null || now.difference(_lastRefreshTime!).inSeconds > 2) {
      _loadData();
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) {
      print('Skipping load - already loading and not forced refresh');
      return;
    }
    
    print('Starting to load reservation data...');
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      print('No authenticated user found');
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
      print('Loading reservations for user: $userId');

      // Fetch reservations from Firestore with timeout
      final query = await FirebaseFirestore.instance
          .collection('reservations')
          .where('user_id', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 15));

      print('Fetched ${query.docs.length} reservations from Firestore');

      final allReservations = query.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Reservation.fromMap(data);
      }).toList();

      print('Parsed ${allReservations.length} reservations');

      // Split into upcoming and previous
      _upcomingReservations = allReservations.where((r) {
        final isActive = r.status == 'confirmed' || r.status == 'pending';
        return isActive && r.startTime.isAfter(now.subtract(const Duration(minutes: 30)));
      }).toList();

      // Sort upcoming reservations by creation time (newest first), fallback to start time
      _upcomingReservations.sort((a, b) {
        // Try to parse createdAt strings to DateTime for comparison
        DateTime? aCreated;
        DateTime? bCreated;
        
        try {
          if (a.createdAt != null) aCreated = DateTime.parse(a.createdAt!);
        } catch (e) {
          // If parsing fails, aCreated remains null
        }
        
        try {
          if (b.createdAt != null) bCreated = DateTime.parse(b.createdAt!);
        } catch (e) {
          // If parsing fails, bCreated remains null
        }
        
        // If both have creation times, sort by creation time (newest first)
        if (aCreated != null && bCreated != null) {
          return bCreated.compareTo(aCreated);
        }
        
        // If only one has creation time, prioritize the one with creation time
        if (aCreated != null && bCreated == null) return -1;
        if (aCreated == null && bCreated != null) return 1;
        
        // If neither has creation time, fallback to start time (newest first)
        return b.startTime.compareTo(a.startTime);
      });

      print('Found ${_upcomingReservations.length} upcoming reservations (sorted by newest first):');
      for (var r in _upcomingReservations) {
        final createdTime = r.createdAt != null ? 'Created: ${r.createdAt}' : 'Created: N/A';
        print('\u001b[34m${r.id} - ${r.status} - ${r.startTime} - $createdTime\u001b[0m');
      }

      _previousReservations = allReservations.where((r) {
        final isCompletedOrCancelled = r.status == 'completed' || r.status == 'cancelled';
        final isPast = r.startTime.isBefore(now.subtract(const Duration(minutes: 30)));
        return isCompletedOrCancelled || isPast;
      }).toList();

      // Sort by creation time descending (newest created first), fallback to start time if no creation time
      _previousReservations.sort((a, b) {
        // Try to parse createdAt strings to DateTime for comparison
        DateTime? aCreated;
        DateTime? bCreated;
        
        try {
          if (a.createdAt != null) aCreated = DateTime.parse(a.createdAt!);
        } catch (e) {
          // If parsing fails, aCreated remains null
        }
        
        try {
          if (b.createdAt != null) bCreated = DateTime.parse(b.createdAt!);
        } catch (e) {
          // If parsing fails, bCreated remains null
        }
        
        // If both have creation times, sort by creation time (newest first)
        if (aCreated != null && bCreated != null) {
          return bCreated.compareTo(aCreated);
        }
        
        // If only one has creation time, prioritize the one with creation time
        if (aCreated != null && bCreated == null) return -1;
        if (aCreated == null && bCreated != null) return 1;
        
        // If neither has creation time, fallback to start time (newest first)
        return b.startTime.compareTo(a.startTime);
      });

      // Debug print: show all previous reservations loaded
      print('Loaded previous reservations (sorted by newest first):');
      for (var r in _previousReservations) {
        final createdTime = r.createdAt != null ? 'Created: ${r.createdAt}' : 'Created: N/A';
        print('Reservation ID: ${r.id} - Status: ${r.status} - $createdTime');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _lastRefreshTime = DateTime.now();
        print('Reservation data loaded successfully');
      }
    } catch (e) {
      print('Error loading reservations: $e');
      print('Error stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _lastRefreshTime = DateTime.now();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading reservations: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservations'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Previous'),
          ],
        ),
      ),
      body: _isLoading
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
    final availableStations = stations.where((station) => station.availableSpots > 0).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
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
                  child: availableStations.isEmpty
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
    final highestACPower = hasACCharger ? station.chargers.where((c) => c.type == 'AC').map((c) => c.power).reduce((a, b) => a > b ? a : b) : 0;
    final highestDCPower = hasDCCharger ? station.chargers.where((c) => c.type == 'DC').map((c) => c.power).reduce((a, b) => a > b ? a : b) : 0;

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
                builder: (context) => ReservationDetailsScreen(station: station),
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
                              color: station.availableSpots > 0 ? Colors.green : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (hasACCharger || hasDCCharger)
                            Text(
                              [
                                if (hasACCharger) 'AC ${highestACPower.toStringAsFixed(0)}kW',
                                if (hasDCCharger) 'DC ${highestDCPower.toStringAsFixed(0)}kW',
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
      builder: (context) => AlertDialog(
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
  void _proceedWithUnlocking(Reservation reservation, ChargingStation station) async {
    try {
      print('Unlocking charger for reservation ${reservation.id}, chargerId: ${reservation.chargerId}');
      
      if (reservation.chargerId == null) {
        throw Exception('No charger ID associated with this reservation');
      }
      
      // First refresh the station data to ensure we have the latest chargers
      final stationService = Provider.of<StationService>(context, listen: false);
      await stationService.refreshChargerAvailabilityData();
      
      // Get the updated station with fresh charger data
      final updatedStationData = await stationService.getStationById(reservation.stationId);
      final updatedStation = updatedStationData ?? station;
      
      print('Station has ${updatedStation.chargers.length} chargers');
      for (var c in updatedStation.chargers) {
        print('Available charger: ID=${c.id}, Name=${c.name}, Type=${c.type}');
      }
      
      // Get the charger directly from database
      Charger? chargerNullable;
      Charger? charger;
      try {
        chargerNullable = await stationService.getChargerByIdAsync(reservation.chargerId!);
        if (chargerNullable == null) {
          throw Exception('Charger not found');
        }
        charger = chargerNullable;
        print('Using charger: ID=${charger.id}, Name=${charger.name}, Type=${charger.type}, Power=${charger.power}kW');
      } catch (e) {
        print('Failed to get charger from database: $e');
        // Show error dialog with retry option
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Charger Not Found'),
            content: Text('Could not find charger information in the database. Error: ${e.toString()}'),
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
      final vehicleService = Provider.of<VehicleService>(context, listen: false);
      final vehicle = await vehicleService.getVehicleById(reservation.vehicleId);
      
      if (vehicle == null) {
        throw Exception('Vehicle not found');
      }

      // Navigate to charging screen
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => ChargingScreen(
            reservation: reservation,
            station: updatedStation,
            vehicle: vehicle,
            chargerType: charger!.type == 'DC' && charger.power >= 49 && charger.power < 51 
                ? 'DC 50kW' 
                : '${charger.type} ${charger.power.toStringAsFixed(1)}kW',
            charger: charger,
          ),
        ),
        (route) => false,  // Remove all previous routes
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
      builder: (context) => AlertDialog(
        title: const Text('Cancel Reservation'),
        content: const Text('Are you sure you want to cancel this reservation? 80% of your deposit will be refunded to your wallet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NO'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              // Store all services and context before async operations
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final stationService = Provider.of<StationService>(context, listen: false);
              final authService = Provider.of<AuthService>(context, listen: false);
              final refundService = Provider.of<RefundService>(context, listen: false);
              
              try {
                print('Starting reservation cancellation for ID: ${reservation.id}');
                print('Reservation details: ${reservation.toMap()}');
                
                // Update reservation status in Firestore
                print('Updating reservation status to cancelled...');
                await FirebaseFirestore.instance
                    .collection('reservations')
                    .doc(reservation.id)
                    .update({'status': 'cancelled'});
                print('Reservation status updated successfully');

                // Debug print: fetch the reservation again to confirm status
                final updated = await FirebaseFirestore.instance
                    .collection('reservations')
                    .doc(reservation.id)
                    .get();
                print('Reservation after cancel: ${updated.data()}');

                // Update charger availability if needed
                if (reservation.chargerId != null) {
                  print('Updating charger availability for charger: ${reservation.chargerId}');
                  await stationService.updateChargerAvailability(
                    reservation.stationId,
                    reservation.chargerId!,
                    true, // Set to available
                  );
                  print('Charger availability updated successfully');
                }

                // Process 80% refund
                if (reservation.deposit > 0) {
                  print('Processing refund for deposit: RM ${reservation.deposit}');
                  final userId = authService.currentUser?.id ?? reservation.userId;
                  print('User ID for refund: $userId');
                  
                  // Check if already refunded to prevent double refunds
                  final alreadyRefunded = await refundService.isReservationRefunded(reservation.id ?? '');
                  print('Already refunded: $alreadyRefunded');
                  
                  if (alreadyRefunded) {
                    print('WARNING: Reservation already refunded, skipping refund process');
                  } else {
                    final refundSuccess = await refundService.processCancellationRefund(reservation, userId);
                    print('Refund success: $refundSuccess');
                    
                    if (refundSuccess) {
                      print('Successfully processed 80% refund for cancelled reservation');
                    } else {
                      print('Failed to process refund for cancelled reservation');
                      // Continue with cancellation even if refund fails
                    }
                  }
                } else {
                  print('No deposit to refund');
                }

                // Refresh the reservations list
                print('Refreshing reservations list...');
                await _loadData(forceRefresh: true);
                print('Reservations list refreshed successfully');

                // Use stored context for success message
                try {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Reservation cancelled successfully.'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                } catch (e) {
                  print('Could not show success message: $e');
                }
              } catch (e) {
                print('Error cancelling reservation: $e');
                print('Error stack trace: ${StackTrace.current}');
                
                // Use stored context for error message
                try {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Error cancelling reservation: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                } catch (snackbarError) {
                  print('Could not show error message: $snackbarError');
                }
                
                // Ensure loading state is reset on error
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text(
              'YES',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
          Icon(
            Icons.warning,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
        final stationData = await stationService.getStationById(reservation.stationId);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                        color: charger.type == 'DC' ? Colors.orange : Colors.blue,
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
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeRange(reservation.startTime, reservation.duration),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                      ),
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
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
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
                        side: BorderSide(
                          color: Colors.grey[300]!,
                        ),
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
        final stationData = await stationService.getStationById(reservation.stationId);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                        color: charger.type == 'DC' ? Colors.orange : Colors.blue,
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
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeRange(reservation.startTime, reservation.duration),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                      ),
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
                          color: reservation.status == 'completed'
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
                            color: reservation.status == 'completed'
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