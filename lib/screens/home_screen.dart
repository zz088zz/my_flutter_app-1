import 'package:flutter/material.dart';
import '../models/charging_station.dart';
import '../models/charger.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/station_service.dart';
import '../models/user.dart';
import '../screens/reservation_details_screen.dart';
import '../screens/all_stations_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
  
  // Access to the state for other screens
  static _HomeScreenState? of(BuildContext context) {
    return context.findAncestorStateOfType<_HomeScreenState>();
  }
  
  // Static method to refresh the home screen from anywhere
  static void refreshHomeScreen() {
    if (_HomeScreenState.homeScreenKey.currentState != null) {
      print('Refreshing home screen via static method');
      _HomeScreenState.homeScreenKey.currentState!._refreshEnergyData();
    } else {
      print('Cannot refresh home screen - key not available');
    }
  }
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // Make this key static so it can be accessed from outside
  static final GlobalKey<_HomeScreenState> homeScreenKey = GlobalKey<_HomeScreenState>();
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  double _totalEnergyConsumed = 0.0;
  double _co2Saved = 0.0;
  bool _isRefreshing = false;
  
  // Add throttling mechanism to prevent excessive refreshes
  DateTime _lastRefreshTime = DateTime.now().subtract(const Duration(minutes: 5));
  final _minRefreshInterval = const Duration(seconds: 3);
  bool _didInitialLoad = false;
  
  // Static method to force refresh from anywhere
  static void refreshHomeScreen() {
    if (homeScreenKey.currentState != null) {
      print('Forcing home screen refresh via static method');
      homeScreenKey.currentState!._forceRefresh();
    } else {
      print('Cannot force refresh - home screen key not available');
    }
  }
  
  // Method to force refresh regardless of throttling
  void _forceRefresh() {
    print('Force refreshing home screen data');
    _lastRefreshTime = DateTime.now().subtract(const Duration(minutes: 5));
    if (mounted) {
      _loadUserData(forceRefresh: true);
    }
  }
  
  // Method specifically to refresh energy data
  Future<void> _refreshEnergyData() async {
    if (!mounted) return;
    
    // Throttling mechanism to prevent excessive refreshes
    final now = DateTime.now();
    final timeSinceLastRefresh = now.difference(_lastRefreshTime);
    if (timeSinceLastRefresh < _minRefreshInterval) {
      print('Throttling energy refresh: Last refresh was ${timeSinceLastRefresh.inMilliseconds}ms ago');
      return;
    }
    
    // Update the last refresh timestamp
    _lastRefreshTime = now;
    
    try {
      if (_isRefreshing) {
        print('Already refreshing energy data, skipping');
        return;
      }
      
      setState(() {
        _isRefreshing = true;
      });
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final stationService = Provider.of<StationService>(context, listen: false);
      
      if (authService.currentUser == null) {
        print('No user logged in, cannot refresh energy data');
        setState(() {
          _isRefreshing = false;
        });
        return;
      }
      
      final userId = authService.currentUser!.id!;
      print('Refreshing energy data for user $userId');
      
      try {
        // Firestore: Fetch all completed charging sessions for this user
        final query = await FirebaseFirestore.instance
          .collection('charging_sessions')
          .where('user_id', isEqualTo: userId)
          .where('status', whereIn: ['completed', 'charger_removed'])
          .get();
        double totalEnergy = 0.0;
        for (var doc in query.docs) {
          final data = doc.data();
          final energy = data['energy_consumed'];
          if (energy != null) {
            if (energy is double) {
              totalEnergy += energy;
            } else if (energy is int) {
              totalEnergy += energy.toDouble();
            } else if (energy is String) {
              totalEnergy += double.tryParse(energy) ?? 0.0;
            }
          }
        }
        final co2Saved = totalEnergy * 0.91;
        print('Updated energy data: $totalEnergy kWh, CO2: $co2Saved kg');
        
        // Update both the in-memory and persistent cached values
        await stationService.updateCachedEnergyValue(userId, totalEnergy);
        
        // Update the UI
        if (mounted) {
          setState(() {
            _totalEnergyConsumed = totalEnergy;
            _co2Saved = co2Saved;
            _isRefreshing = false;
          });
        }
        
        // For new users with no charging history, energy should remain 0
        print('Energy calculation complete: $totalEnergy kWh, CO2: $co2Saved kg');
        
        // Force UI update
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print('Error refreshing energy data: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
  
  @override
  bool get wantKeepAlive => true; // Keep alive when navigating
  
  @override
  void initState() {
    super.initState();
    // Register to detect when app is resumed
    WidgetsBinding.instance.addObserver(this);
    // Load stations data
    final stationService = Provider.of<StationService>(context, listen: false);
    stationService.loadStations(); // This will now also calculate distances
    
    // Clear any cached energy values to ensure fresh start for new users
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser != null) {
      final userId = authService.currentUser!.id!;
      stationService.clearCachedEnergyValue(userId);
      print('Cleared cached energy values for user $userId');
    }
    
    // Use cached values if available first, then update in background
    _loadInitialUserData();
    
    // Then do a full data refresh in the background, but only once
    if (!_didInitialLoad) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshEnergyData(); // Explicitly refresh energy data just once on start
        _didInitialLoad = true;
      });
    }
    
    // Listen for changes to the station service
    stationService.addListener(() {
      if (mounted) {
        final authService = Provider.of<AuthService>(context, listen: false);
        if (authService.currentUser != null) {
          final userId = authService.currentUser!.id!;
          final cachedEnergy = stationService.getCachedEnergyValue(userId);
          setState(() {
            _totalEnergyConsumed = cachedEnergy;
            _co2Saved = cachedEnergy * 0.91;
          });
        }
      }
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only refresh when the app is resumed from background
    if (state == AppLifecycleState.resumed) {
      print('App resumed, forcing energy data refresh');
      // Use a delay to ensure app is fully visible
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshEnergyData();
        // Also refresh station distances in case user location changed
        final stationService = Provider.of<StationService>(context, listen: false);
        stationService.updateStationDistances();
      });
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Do NOT refresh here - this is called too frequently
  }
  
  // Special override to ensure we refresh when the screen becomes visible again
  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This is called when parent rebuilds - avoid refreshing here
    // But we might need to update with latest cached data
    _loadInitialUserData();
  }
  
  Future<void> _loadUserData({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final stationService = Provider.of<StationService>(context, listen: false);
    
    if (authService.currentUser != null) {
      try {
        final userId = authService.currentUser!.id!;
        
        print('\n========== DEBUGGING ENERGY DATA (${DateTime.now().toIso8601String()}) ==========');
        print('Current user ID: $userId');
        
        // Skip refresh if too recent unless forced
        final now = DateTime.now();
        final timeSinceLastRefresh = now.difference(_lastRefreshTime);
        if (!forceRefresh && timeSinceLastRefresh < _minRefreshInterval) {
          print('Throttling refresh: Last refresh was ${timeSinceLastRefresh.inMilliseconds}ms ago');
          
          if (mounted) {
            setState(() {
              _isRefreshing = false;
            });
          }
          return;
        }
        
        // Update last refresh time
        _lastRefreshTime = now;
        
        // Firestore: Fetch all completed charging sessions for this user
        final query = await FirebaseFirestore.instance
          .collection('charging_sessions')
          .where('user_id', isEqualTo: userId)
          .where('status', whereIn: ['completed', 'charger_removed'])
          .get();
        double totalEnergy = 0.0;
        for (var doc in query.docs) {
          final data = doc.data();
          final energy = data['energy_consumed'];
          if (energy != null) {
            if (energy is double) {
              totalEnergy += energy;
            } else if (energy is int) {
              totalEnergy += energy.toDouble();
            } else if (energy is String) {
              totalEnergy += double.tryParse(energy) ?? 0.0;
            }
          }
        }
        final co2Saved = totalEnergy * 0.91;
        print('Calculated CO2 saved: $co2Saved kg from $totalEnergy kWh');
        
        if (mounted) {
          setState(() {
            _totalEnergyConsumed = totalEnergy;
            _co2Saved = co2Saved;
            _isRefreshing = false;
          });
        }
        
        print('========== END DEBUGGING ==========');
      } catch (e) {
        print('Error loading user data: $e');
        if (mounted) {
          setState(() {
            _isRefreshing = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
  
  // Fast loading method that uses cached values
  void _loadInitialUserData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final stationService = Provider.of<StationService>(context, listen: false);
    
    if (authService.currentUser != null) {
      final userId = authService.currentUser!.id!;
      
      // Use cached value if available
      final cachedEnergy = stationService.getCachedEnergyValue(userId);
      
      setState(() {
        _totalEnergyConsumed = cachedEnergy;
        _co2Saved = stationService.calculateCO2Saved(cachedEnergy);
      });
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Get current user from auth service
    final authService = Provider.of<AuthService>(context);
    final stationService = Provider.of<StationService>(context);
    
    final User? currentUser = authService.currentUser;
    final String userName = currentUser != null 
        ? '${currentUser.firstName} ${currentUser.lastName}'
        : 'Guest User';
    final String userInfo = currentUser != null
        ? 'Welcome to EV Charging!'
        : 'Welcome';
    
    // Get available stations from StationService
    final availableStations = stationService.getAvailableStations();
    final allStations = stationService.stations;
    
    // Filter stations based on search query
    final filteredStations = _searchQuery.isEmpty
        ? allStations
        : allStations.where((station) => 
            station.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, $userName',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              userInfo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                      // Energy Stats Card - REDESIGNED FOR PROMINENCE
                      Container(
                        margin: const EdgeInsets.only(bottom: 24.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue[800]!,
                              Colors.blue[600]!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.eco_outlined,
                                    color: Colors.white.withOpacity(0.9),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Your Impact',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isRefreshing)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildImpactStat(
                                    icon: Icons.bolt,
                                    value: '${_totalEnergyConsumed.toStringAsFixed(1)}',
                                    unit: 'kWh',
                                    label: 'Energy Used',
                                  ),
                                  Container(
                                    height: 50,
                                    width: 1,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  _buildImpactStat(
                                    icon: Icons.eco,
                                    value: '${_co2Saved.toStringAsFixed(1)}',
                                    unit: 'kg',
                                    label: 'CO₂ Saved',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Debug button removed as it was only needed during development
                            ],
                          ),
                        ),
                      ),
                      
                    // Daily Tip Section
                    Container(
                      margin: const EdgeInsets.only(bottom: 20.0),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.8),
                            Theme.of(context).primaryColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tips_and_updates,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Eco Tip of the Day',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Charging during off-peak hours can save up to 30% on energy costs!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Search Bar
                    Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        decoration: InputDecoration(
                          hintText: 'Search for charging stations',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 15,
                          ),
                          prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // All Charging Stations Section
                    _buildSectionHeader('All Charging Stations'),
                    if (filteredStations.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'No stations found for "$_searchQuery"',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    if (filteredStations.isNotEmpty)
                      ...filteredStations.map((station) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildChargingStationCard(station: station),
                      )),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildImpactStat({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
  }) {
    return Column(
        children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
            style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
                  TextSpan(
                    text: ' $unit',
              style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
              ),
                  ),
                ],
            ),
          ),
        ],
      ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
              fontSize: 18,
                      fontWeight: FontWeight.bold,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AllStationsScreen(),
                ),
              ).then((_) {
                // Refresh data when returning from all stations screen
                _loadUserData();
              });
            },
            child: const Text(
              'See All',
                    style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
      ),
    );
  }

  Widget _buildChargingStationCard({required ChargingStation station}) {
    final isAvailable = station.availableSpots > 0;
    final availabilityText = '${station.availableSpots}/${station.totalSpots} Available';
    
    // Extract charger types from station.chargers
    final Set<String> connectorTypes = station.chargers.map((c) => c.type).toSet();
    final String chargerTypesText = connectorTypes.join(', ');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Station header row with name and distance
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                // Station name
                  Expanded(
                  child: Text(
                                station.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                    ),
                  ),
                  
                  // Distance info
                Row(
                      children: [
                    Icon(Icons.location_on_outlined, color: Colors.grey[600], size: 14),
                        const SizedBox(width: 4),
                        Text(
                          station.distance,
                          style: TextStyle(
                        color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                  ),
                ],
              ),
            
            // Availability indicator
            const SizedBox(height: 8),
            Text(
              availabilityText,
              style: TextStyle(
                color: isAvailable ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
              
              const SizedBox(height: 12),
              Divider(color: Colors.grey[200]),
            const SizedBox(height: 8),
            
            // Charger details (types and power)
                        Row(
                          children: [
                            Icon(Icons.electric_car, size: 16, color: Colors.grey[700]),
                            const SizedBox(width: 6),
                            Text(
                  chargerTypesText,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
            
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.bolt, size: 16, color: Colors.grey[700]),
                            const SizedBox(width: 6),
                            Text(
                              station.powerOutput,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
            ),
            
            const SizedBox(height: 12),
            
            // Reserve button only
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => _reserveStation(station),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      ),
                child: const Text('Reserve'),
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  void _reserveStation(ChargingStation station) {
    // Navigate to reservation details screen with the selected station
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReservationDetailsScreen(station: station),
      ),
    ).then((_) {
      // Refresh data when returning from reservation screen
      _loadUserData();
    });
  }

  // Add the missing reservation diagnostics method
  Future<void> _runReservationDiagnostics(String userId) async {
    print('Running reservation diagnostics for user $userId');
    try {
      // This part needs to be replaced with Firestore logic
      // For now, it's a placeholder
      print('Reservation diagnostics not implemented for Firestore');
    } catch (e) {
      print('Error running reservation diagnostics: $e');
    }
  }

  // Public method to refresh energy data that can be called from outside
  Future<void> refreshEnergyData() async {
    return _refreshEnergyData();
  }
} 