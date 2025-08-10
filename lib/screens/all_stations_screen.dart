import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/charging_station.dart';
import '../services/station_service.dart';
import 'reservation_details_screen.dart';

class AllStationsScreen extends StatefulWidget {
  const AllStationsScreen({Key? key}) : super(key: key);

  @override
  State<AllStationsScreen> createState() => _AllStationsScreenState();
}

class _AllStationsScreenState extends State<AllStationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final stationService = Provider.of<StationService>(context);
    
    // Get all stations
    final allStations = stationService.stations;
    
    // Filter stations based on search query
    final filteredStations = _searchQuery.isEmpty
        ? allStations
        : allStations.where((station) => 
            station.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Charging Stations'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
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
          ),
          
          // Station list
          Expanded(
            child: filteredStations.isEmpty
              ? Center(
                  child: Text(
                    'No stations found for "$_searchQuery"',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredStations.length,
                  itemBuilder: (context, index) {
                    return _buildChargingStationCard(filteredStations[index]);
                  },
                ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChargingStationCard(ChargingStation station) {
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
            
            // Reserve button
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
    );
  }
} 