import 'package:flutter/material.dart';
import '../../models/charging_station.dart';
import '../../models/charger.dart';

class StationForm extends StatefulWidget {
  final ChargingStation? station;
  final Future<bool> Function(ChargingStation station, List<Charger> chargers) onSave;

  const StationForm({
    Key? key,
    this.station,
    required this.onSave,
  }) : super(key: key);

  @override
  State<StationForm> createState() => _StationFormState();
}

class _StationFormState extends State<StationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  bool _isActive = true;
  bool _isLoading = false;
  final List<Charger> _chargers = [];

  @override
  void initState() {
    super.initState();
    if (widget.station != null) {
      _nameController.text = widget.station!.name;
      _locationController.text = widget.station!.location;
      _addressController.text = widget.station!.address;
      _cityController.text = widget.station!.city;
      _latitudeController.text = widget.station!.latitude.toString();
      _longitudeController.text = widget.station!.longitude.toString();
      _isActive = widget.station!.isActive;
      
      // Copy the chargers
      _chargers.addAll(widget.station!.chargers);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _saveStation() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Parse latitude and longitude values
        double? latitude = double.tryParse(_latitudeController.text);
        double? longitude = double.tryParse(_longitudeController.text);
        
        if (latitude == null || longitude == null) {
          throw Exception('Invalid latitude or longitude values');
        }
        
        print('\n=== SAVING STATION DATA ===');
        print('Name: ${_nameController.text}');
        print('Latitude: $latitude, Longitude: $longitude');
        print('Total chargers: ${_chargers.length}');

        // Create or update the station
        final station = ChargingStation(
          id: widget.station?.id,
          name: _nameController.text,
          location: _locationController.text,
          address: _addressController.text,
          city: _cityController.text,
          latitude: latitude,
          longitude: longitude,
          isActive: _isActive,
          distance: widget.station?.distance ?? '0 km',
          waitingTime: widget.station?.waitingTime,
          chargers: _chargers,
        );

        // Add total spots and available spots for compatibility
        final Map<String, dynamic> stationMap = station.toMap();
        stationMap['total_spots'] = _chargers.length;
        stationMap['available_spots'] = _chargers.where((c) => c.isAvailable).length;
        stationMap['power_output'] = _getHighestPowerOutput();
        stationMap['price_per_kwh'] = _getAveragePricePerKWh();
        
        print('Station data: $stationMap');
        print('Charger data: ${_chargers.map((c) => c.toMap()).toList()}');

        final result = await widget.onSave(station, _chargers);

        if (!mounted) return;

        if (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.station == null
                  ? 'Charging station added successfully'
                  : 'Charging station updated successfully'),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save charging station. Please check the console logs.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e, stackTrace) {
        print('\n=== ERROR SAVING STATION ===');
        print('Error: $e');
        print('Stack trace: $stackTrace');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
  
  // Helper methods to calculate values for old charging_stations table compatibility
  String _getHighestPowerOutput() {
    if (_chargers.isEmpty) return 'N/A';
    double highestPower = 0;
    for (var charger in _chargers) {
      if (charger.power > highestPower) {
        highestPower = charger.power;
      }
    }
    return 'Up to ${highestPower.toStringAsFixed(0)} kW';
  }
  
  double _getAveragePricePerKWh() {
    if (_chargers.isEmpty) return 0.0;
    double totalPrice = 0;
    for (var charger in _chargers) {
      totalPrice += charger.pricePerKWh;
    }
    return totalPrice / _chargers.length;
  }

  void _addDefaultChargers() {
    // Check if we've reached the maximum number of chargers (10)
    if (_chargers.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum limit of 10 chargers reached'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Default Chargers'),
          content: const Text('This will add one AC charger and one DC charger to your station. You can customize their names below.'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add Default Chargers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                
                // Show dialog to customize AC charger name
                _showChargerNameDialog('AC', '1', () {
                  // After AC is added, show dialog for DC charger
                  _showChargerNameDialog('DC', '2', null);
                });
              },
            ),
          ],
        );
      },
    );
  }
  
  // Helper method to show charger name dialog
  void _showChargerNameDialog(String type, String chargerNumber, Function? onComplete) {
    final stationId = widget.station?.id ?? '0';
    String defaultName = 'Charger $chargerNumber (${type})';
    
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController(text: defaultName);
        return AlertDialog(
          title: Text('Add ${type} Charger'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Charger Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                if (onComplete != null) onComplete();
              },
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                Navigator.of(context).pop();
                final chargerName = nameController.text.trim().isNotEmpty ? 
                    nameController.text.trim() : defaultName;
                
                if (type == 'AC') {
                  _chargers.add(
                    Charger.ac(
                      stationId: stationId,
                      name: chargerName,
                    ),
                  );
                } else {
                  _chargers.add(
                    Charger.dc(
                      stationId: stationId,
                      name: chargerName,
                    ),
                  );
                }
                
                setState(() {});
                if (onComplete != null) onComplete();
              },
            ),
          ],
        );
      },
    );
  }

  // Add a new charger of specified type
  void _addNewCharger(String type) {
    // Check if we've reached the maximum number of chargers (10)
    if (_chargers.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum limit of 10 chargers reached'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final chargerNumber = _chargers.length + 1;
    _showChargerNameDialog(type, chargerNumber.toString(), null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station == null ? 'Add Charging Station' : 'Edit Charging Station'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Station Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a station name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      // No validator - field is optional
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      // No validator - field is optional
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      // No validator - field is optional
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _longitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Active'),
                      value: _isActive,
                      onChanged: (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chargers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_chargers.length}/10 chargers',
                          style: TextStyle(
                            color: _chargers.length >= 10 ? Colors.red : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_chargers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              const Text('No chargers added yet'),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _addDefaultChargers,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Add Default Chargers'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          // Charger type buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Add AC Charger'),
                                  onPressed: _chargers.length >= 10 ? null : () => _addNewCharger('AC'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Add DC Charger'),
                                  onPressed: _chargers.length >= 10 ? null : () => _addNewCharger('DC'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Charger list
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _chargers.length,
                            itemBuilder: (context, index) {
                              final charger = _chargers[index];
                              return _buildChargerItem(charger, index);
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _saveStation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Station'),
                    ),
                    // Add padding at the bottom to ensure we have space for buttons
                    const SizedBox(height: 72),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildChargerItem(Charger charger, int index) {
    final color = charger.type == 'AC' ? Colors.blue : Colors.orange;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
        title: Text(charger.name),
        subtitle: Text(
          '${charger.power} kW',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {
            setState(() {
              _chargers.removeAt(index);
            });
          },
        ),
      ),
    );
  }
} 