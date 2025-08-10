import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/station_service.dart';
import '../models/charging_station.dart';
import 'reservation_details_screen.dart';
import 'dart:math' as math;
import 'dart:async';

// Main screen for displaying charging stations on a map with a list view
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// State class for the MapScreen with AutomaticKeepAliveClientMixin to preserve state during navigation
class _MapScreenState extends State<MapScreen> with AutomaticKeepAliveClientMixin {
  // Selected filter for station display
  String _selectedFilter = 'All Stations';
  // Loading state for showing progress indicator
  bool _isLoading = true;
  // Controller for manipulating the map view
  final MapController _mapController = MapController();
  // User's current location coordinates
  double? _userLat, _userLng;
  // Cache of stations to avoid excessive rebuilds
  List<ChargingStation> _cachedStations = [];
  // Flag to track if map has been initialized to user's location
  bool _mapInitialized = false;
  // Timer for debouncing filter changes to improve performance
  Timer? _debounceTimer;
  
  // Default center location on TARUMT campus
  final LatLng _campusCenter = LatLng(3.2152659087070754, 101.72655709633432);
  
  // Marker list to display on the map
  List<Marker> _markers = [];

  // Keep the widget state alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Load station data from service
    _loadData();
    // Delay location initialization to avoid overloading app on startup
    Future.delayed(const Duration(milliseconds: 500), _initLocation);
  }

  @override
  void dispose() {
    // Cancel any pending timer to prevent memory leaks
    _debounceTimer?.cancel();
    super.dispose();
  }
  
  /// Initialize user location with permissions check and handle errors
  Future<void> _initLocation() async {
    if (!mounted) return;
    
    try {
      // Check if device location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services disabled'))
          );
        }
        return;
      }
      
      // Check and request location permissions if needed
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      if (perm == LocationPermission.deniedForever) return;

      // Get user position with a timeout to prevent hanging
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        // Fall back to last known position if current position fails
        pos = await Geolocator.getLastKnownPosition();
        if (pos == null) {
          print('Could not get location: $e');
          return;
        }
      }
      
      if (!mounted) return;
      
      // Update state with user location
      setState(() {
        _userLat = pos!.latitude;
        _userLng = pos.longitude;
        _updateMarkers(); // Refresh markers with new location
      });
      
      // Center map on user location only on initial load
      if (!_mapInitialized && mounted) {
        _mapInitialized = true;
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
      }
    } catch (e) {
      print('Location error: $e');
      // Continue without location if there's an error
    }
  }

  /// Load charging station data from the service
  Future<void> _loadData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      // Get station service from provider
      final stationService = Provider.of<StationService>(context, listen: false);
      await stationService.loadStations();

      if (mounted) {
        // Create a copy of the stations to avoid modifying the original data
        final stationsList = List<ChargingStation>.from(stationService.stations);
        
        setState(() {
          // Cache stations for better performance
          _cachedStations = stationsList;
          _isLoading = false; // Hide loading indicator
        });
        
        // Update markers asynchronously to avoid UI blocking
        Future.microtask(() {
          if (mounted) {
            _updateMarkers();
          }
        });
      }
    } catch (e) {
      print('Error loading stations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false; // Hide loading indicator even on error
        });
      }
    }
  }

  /// Handle filter selection with debouncing to prevent excessive rebuilds
  void _onFilterSelected(String filter) {
    // Cancel previous debounce timer
    _debounceTimer?.cancel();
    
    // Create new timer to delay execution for a smoother experience
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        // Update filter state
        setState(() {
          _selectedFilter = filter;
        });
        
        // Update markers asynchronously
        Future.microtask(() {
          if (mounted) {
            _updateMarkers();
          }
        });
      }
    });
  }

  /// Update map markers based on filtered stations and user location
  void _updateMarkers() {
    if (!mounted) return;
    
    try {
      // Get filtered stations
      final filteredStations = _getFilteredStations(_cachedStations);
      final List<Marker> newMarkers = [];
      
      // Add station markers with appropriate colors based on availability
      for (final station in filteredStations.take(5)) {
        newMarkers.add(
          Marker(
            point: LatLng(station.latitude, station.longitude),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showStationMarkerDialog(station),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.ev_station,
                  color: station.availableSpots > 0 ? Colors.green : Colors.red,
                  size: 28,
                ),
              ),
            ),
          ),
        );
      }
      
      // Add user location marker if available
      if (_userLat != null && _userLng != null) {
        newMarkers.add(
          Marker(
            point: LatLng(_userLat!, _userLng!),
            width: 30,
            height: 30,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        );
      }
      
      // Update state with new markers
      if (mounted) {
        setState(() {
          _markers = List<Marker>.from(newMarkers);
        });
      }
    } catch (e) {
      print('Error updating markers: $e');
    }
  }

  /// Show station information dialog when marker is tapped
  void _showStationMarkerDialog(ChargingStation station) {
    // Calculate charger statistics
    final acChargers = station.chargers.where((c) => c.type == 'AC').toList();
    final dcChargers = station.chargers.where((c) => c.type == 'DC').toList();
    final acAvailable = acChargers.where((c) => c.isAvailable).length;
    final dcAvailable = dcChargers.where((c) => c.isAvailable).length;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            padding: const EdgeInsets.all(20.0),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Station header with status
                Row(
                  children: [
                    Icon(
                      Icons.ev_station,
                      color: station.availableSpots > 0 ? Colors.green : Colors.red,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: station.availableSpots > 0 
                            ? Colors.green.withOpacity(0.1) 
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        station.availableSpots > 0 ? 'Available' : 'Busy',
                        style: TextStyle(
                          color: station.availableSpots > 0 ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Location and distance
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        station.address.isNotEmpty ? station.address : station.location,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Distance from user
                Row(
                  children: [
                    Icon(Icons.directions_walk, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _distanceLabel(station),
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Charger information
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Charger Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // AC chargers
                      if (acChargers.isNotEmpty) 
                        Row(
                          children: [
                            Icon(Icons.bolt, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 4),
                            Text(
                              'AC: $acAvailable/${acChargers.length} available',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      
                      if (acChargers.isNotEmpty && dcChargers.isNotEmpty)
                        const SizedBox(height: 4),
                      
                      // DC chargers
                      if (dcChargers.isNotEmpty) 
                        Row(
                          children: [
                            Icon(Icons.flash_on, size: 16, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Text(
                              'DC: $dcAvailable/${dcChargers.length} available',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reserve button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToStationDetails(station);
                        },
                        icon: const Icon(Icons.book_online, size: 18),
                        label: const Text('Reserve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Navigate button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showMapSelectionDialog(station);
                        },
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text('Navigate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Close button
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Apply filters to the station list and sort by distance if user location available
  List<ChargingStation> _getFilteredStations(List<ChargingStation> allStations) {
    // Limit total stations for performance
    const maxStationsToShow = 10;
    List<ChargingStation> result;
    
    // Apply filter based on selection
    switch (_selectedFilter) {
      case 'Available':
        result = allStations.where((station) => station.availableSpots > 0).toList();
        break;
      case 'Fast':
        // Check if station has any charger with power >= 22kW (considered fast charging)
        result = allStations.where((station) => 
          station.chargers.any((charger) => charger.power >= 22.0)
        ).toList();
        break;
      case 'Reservable':
        // Only show stations that are active AND have available spots
        result = allStations.where((station) => 
          station.isActive && station.availableSpots > 0
        ).toList();
        break;  
      case 'All':
      default:
        result = List.from(allStations);
    }
    
    // Sort by distance if user location is available
    if (_userLat != null && _userLng != null) {
      result.sort((a, b) {
        final distA = _calculateDistance(_userLat!, _userLng!, a.latitude, a.longitude);
        final distB = _calculateDistance(_userLat!, _userLng!, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });
    }
    
    // Limit results to improve performance
    return result.length > maxStationsToShow 
        ? result.sublist(0, maxStationsToShow) 
        : result;
  }

  /// Calculate approximate distance between two coordinates
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Simple distance approximation for sorting (not exact)
    return math.sqrt(math.pow(lat2 - lat1, 2) + math.pow(lon2 - lon1, 2));
  }

  /// Format distance as "x.x km" from user to station
  String _distanceLabel(ChargingStation s) {
    if (_userLat == null) return s.distance; // Use default distance from model
    
    try {
      // Calculate actual distance using Geolocator
      final meters = Geolocator.distanceBetween(_userLat!, _userLng!, s.latitude, s.longitude);
      return '${(meters / 1000).toStringAsFixed(1)} km';
    } catch (e) {
      return s.distance; // Fallback to stored distance
    }
  }

  /// Navigate to station details screen for reservations
  void _navigateToStationDetails(ChargingStation station) {
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (context) => ReservationDetailsScreen(station: station),
      ),
    );
  }

  /// Show dialog for selecting navigation app
  void _showMapSelectionDialog(ChargingStation station) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Navigate to',
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  station.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                // Navigation app options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Google Maps option
                    _buildNavigationOption(
                      context,
                      'Google Maps',
                      'assets/images/google_maps_icon.png',
                      Icons.map, // Fallback icon if image asset isn't available
                      Colors.blue,
                      () => _openGoogleMaps(station),
                    ),
                    // Waze option
                    _buildNavigationOption(
                      context,
                      'Waze',
                      'assets/images/waze_icon.png',
                      Icons.navigation, // Fallback icon if image asset isn't available
                      Colors.cyan,
                      () => _openWaze(station),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Cancel button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Helper widget for building navigation app options
  Widget _buildNavigationOption(
    BuildContext context,
    String label,
    String iconAssetPath,
    IconData fallbackIcon,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                fallbackIcon,
                color: iconColor,
                size: 30,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Launch Google Maps with directions to the station
  Future<void> _openGoogleMaps(ChargingStation station) async {
    try {
      // Prepare origin parameter if user location is available
      String originParam = '';
      if (_userLat != null && _userLng != null) {
        originParam = '&origin=${_userLat!},${_userLng!}';
      }
      
      // Try different URL schemes in order of preference
      
      // 1. Try with Google Maps app URI first
      final googleMapsUri = Uri.parse(
        'google.navigation:q=${station.latitude},${station.longitude}${originParam}&mode=d'
      );
      
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
        return;
      }
      
      // 2. Try with geo URI as a fallback
      final geoUri = Uri.parse(
        'geo:${station.latitude},${station.longitude}?q=${Uri.encodeComponent(station.name)}'
      );
      
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
      
      // 3. Fall back to web URL if app schemes fail
      final destinationParam = '${station.latitude},${station.longitude}';
      final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1${originParam}&destination=$destinationParam&travelmode=driving'
      );
    
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        return;
      }
      
      // Show error if all methods fail
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    } catch (e) {
      print("Error launching Google Maps: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error opening navigation app')),
        );
      }
    }
  }

  /// Launch Waze with directions to the station
  Future<void> _openWaze(ChargingStation station) async {
    try {
      // 1. Try the Waze app URI scheme
      final wazeAppUrl = Uri.parse(
        'waze://?ll=${station.latitude},${station.longitude}&navigate=yes&zoom=10'
      );
      
      if (await canLaunchUrl(wazeAppUrl)) {
        await launchUrl(wazeAppUrl, mode: LaunchMode.externalApplication);
        return;
      }
      
      // 2. Fall back to Waze web URL
      final wazeWebUrl = Uri.parse(
        'https://waze.com/ul?ll=${station.latitude},${station.longitude}&navigate=yes&zoom=10'
      );
      
      if (await canLaunchUrl(wazeWebUrl)) {
        await launchUrl(wazeWebUrl, mode: LaunchMode.externalApplication);
        return;
      }
      
      // 3. Try Google Maps as a last resort
      await _openGoogleMaps(station);
    } catch (e) {
      print("Error launching Waze: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error opening navigation app')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Map'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator()) // Loading indicator
        : Column(
            children: [
              // Map View section (35% of screen height)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.35,
                width: double.infinity,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _campusCenter,
                    initialZoom: 15.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Disable rotation
                    ),
                    onMapReady: () {
                      _updateMarkers();
                    },
                  ),
                  children: [
                    // OpenStreetMap tile layer
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.my_flutter_app',
                      maxZoom: 18,
                      minZoom: 12,
                    ),
                    // Markers layer for stations and user location
                    MarkerLayer(markers: _markers),
                  ],
                ),
              ),
              
              // Filter chips for filtering stations
              Container(
                padding: const EdgeInsets.only(top: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _buildSimpleFilterChip('All'),
                      _buildSimpleFilterChip('Available'),
                      _buildSimpleFilterChip('Fast'),
                      _buildSimpleFilterChip('Reservable'),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              
              // Stations List - scrollable list of charging stations
              Expanded(
                child: Builder(
                  builder: (context) {
                    final filteredStations = _getFilteredStations(_cachedStations);
                    
                    // Show empty state message if no stations match filter
                    return filteredStations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'No charging stations found for filter: $_selectedFilter',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      // List of station cards
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: filteredStations.length,
                          itemBuilder: (context, index) {
                            return _buildSimpleStationCard(filteredStations[index]);
                          },
                        );
                  },
                ),
              ),
            ],
          ),
    );
  }

  /// Build filter chip with selected state styling
  Widget _buildSimpleFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 14,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            _onFilterSelected(label);
          }
        },
        backgroundColor: Colors.grey[200],
        selectedColor: Theme.of(context).primaryColor,
      ),
    );
  }

  /// Build a card for an individual charging station
  Widget _buildSimpleStationCard(ChargingStation station) {
    // Calculate charger statistics
    final acChargers = station.chargers.where((c) => c.type == 'AC').toList();
    final dcChargers = station.chargers.where((c) => c.type == 'DC').toList();
    final acAvailable = acChargers.where((c) => c.isAvailable).length;
    final dcAvailable = dcChargers.where((c) => c.isAvailable).length;
    
    // Format power range text
    String formatPowerText(List<double> powers) {
      if (powers.isEmpty) return 'N/A';
      final uniquePowers = powers.toSet().toList()..sort();
      if (uniquePowers.length == 1) {
        return '${uniquePowers.first.toStringAsFixed(0)} kW';
      } else {
        return '${uniquePowers.first.toStringAsFixed(0)}-${uniquePowers.last.toStringAsFixed(0)} kW';
      }
    }

    // Get formatted power text for each charger type
    String acPowerText = formatPowerText(acChargers.map((c) => c.power).toList());
    String dcPowerText = formatPowerText(dcChargers.map((c) => c.power).toList());
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Station name with availability status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    station.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Status indicator (Available/Busy)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: station.availableSpots > 0 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    station.availableSpots > 0 ? 'Available' : 'Busy',
                    style: TextStyle(
                      color: station.availableSpots > 0 ? Colors.green : Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Location address and distance from user
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    station.address.isNotEmpty ? station.address : station.location,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _distanceLabel(station),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Charger availability details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AC chargers information
                  if (acChargers.isNotEmpty) Row(
                    children: [
                      Icon(Icons.bolt, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 4),
                      Text(
                        'AC',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[700],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$acAvailable/${acChargers.length} available · $acPowerText',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  
                  if (acChargers.isNotEmpty && dcChargers.isNotEmpty)
                    const SizedBox(height: 6),
                  
                  // DC chargers information
                  if (dcChargers.isNotEmpty) Row(
                    children: [
                      Icon(Icons.flash_on, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        'DC',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.orange[700],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$dcAvailable/${dcChargers.length} available · $dcPowerText',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action buttons (Reserve and Directions)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Reserve button
                ElevatedButton(
                  onPressed: () => _navigateToStationDetails(station),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Reserve',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Direction button
                ElevatedButton(
                  onPressed: () => _showMapSelectionDialog(station),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    foregroundColor: Theme.of(context).primaryColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Direction',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 