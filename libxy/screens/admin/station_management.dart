import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/charging_station.dart';
import '../../models/charger.dart';
import '../../services/admin_service.dart';
import 'station_form.dart';
import 'charger_form.dart';

class StationManagement extends StatefulWidget {
  const StationManagement({Key? key}) : super(key: key);

  @override
  State<StationManagement> createState() => _StationManagementState();
}

class _StationManagementState extends State<StationManagement> {
  @override
  void initState() {
    super.initState();
    // Load stations when the screen is initialized
    Future.microtask(() => 
      Provider.of<AdminService>(context, listen: false).loadAllStations()
    );
  }

  void _showAddStationDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StationForm(
          onSave: (station, chargers) {
            final adminService = Provider.of<AdminService>(context, listen: false);
            return adminService.addStation(station, chargers);
          },
        ),
      ),
    );
  }

  void _showEditStationDialog(ChargingStation station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StationForm(
          station: station,
          onSave: (updatedStation, chargers) {
            final adminService = Provider.of<AdminService>(context, listen: false);
            return adminService.updateStation(updatedStation, chargers);
          },
        ),
      ),
    );
  }

  void _showAddChargerDialog(ChargingStation station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChargerForm(
          stationId: station.id!,
          onSave: (charger) {
            final adminService = Provider.of<AdminService>(context, listen: false);
            return adminService.addChargerToStation(station.id!, charger);
          },
        ),
      ),
    );
  }

  void _showEditChargerDialog(Charger charger) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChargerForm(
          charger: charger,
          stationId: charger.stationId,
          onSave: (updatedCharger) {
            final adminService = Provider.of<AdminService>(context, listen: false);
            return adminService.updateCharger(updatedCharger);
          },
        ),
      ),
    );
  }

  void _confirmDeleteStation(ChargingStation station) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Charging Station'),
        content: Text('Are you sure you want to delete ${station.name}? This will also delete all associated chargers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteStation(station.id!);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCharger(Charger charger, String stationName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Charger'),
        content: Text('Are you sure you want to delete charger ${charger.name} from $stationName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteCharger(charger.id!);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStation(String stationId) async {
    final adminService = Provider.of<AdminService>(context, listen: false);
    final result = await adminService.deleteStation(stationId);
    
    if (!mounted) return;
    
    if (result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station deleted successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete station')),
      );
    }
  }

  Future<void> _deleteCharger(String chargerId) async {
    final adminService = Provider.of<AdminService>(context, listen: false);
    final result = await adminService.deleteCharger(chargerId);
    
    if (!mounted) return;
    
    if (result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Charger deleted successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete charger')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AdminService>(
        builder: (context, adminService, child) {
          if (adminService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final stations = adminService.stations;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Consistent header
              AppBar(
                title: const Text(
                  'Station Management',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.indigo[800],
                elevation: 0,
              ),
              
              // Main content
              Expanded(
                child: stations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'No charging stations available',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _showAddStationDialog,
                              child: const Text('Add New Station'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: stations.length,
                        itemBuilder: (context, index) {
                          final station = stations[index];
                          return _buildStationCard(station);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStationDialog,
        backgroundColor: Colors.indigo[700],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStationCard(ChargingStation station) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        title: Text(
          station.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(station.location),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Address:', station.address.isEmpty ? 'Not provided' : station.address),
                _buildInfoRow('City:', station.city.isEmpty ? 'Not provided' : station.city),
                _buildInfoRow('Total Chargers:', station.totalSpots.toString()),
                _buildInfoRow('Available Chargers:', station.availableSpots.toString()),
                _buildInfoRow('Highest Power:', station.powerOutput),

                const SizedBox(height: 16),
                const Text(
                  'Chargers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                
                // List of chargers
                if (station.chargers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No chargers added yet'),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: station.chargers.length,
                    itemBuilder: (context, index) {
                      final charger = station.chargers[index];
                      return _buildChargerItem(charger, station.name);
                    },
                  ),
                
                // Action buttons in a responsive layout
                const SizedBox(height: 16),
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton.icon(
                            onPressed: () => _showEditStationDialog(station),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Edit Station'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddChargerDialog(station),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Charger'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton.icon(
                            onPressed: () => _confirmDeleteStation(station),
                            icon: const Icon(Icons.delete, size: 18),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChargerItem(Charger charger, String stationName) {
    final color = charger.type == 'AC' ? Colors.blue : Colors.orange;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text(
            charger.type,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          charger.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${charger.power} kW',
          style: TextStyle(color: Colors.black87),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditChargerDialog(charger),
              tooltip: 'Edit Charger',
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteCharger(charger, stationName),
              tooltip: 'Delete Charger',
            ),
          ],
        ),
      ),
    );
  }
} 