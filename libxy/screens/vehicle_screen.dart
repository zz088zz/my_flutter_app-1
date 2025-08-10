import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

// Main screen that displays the user's vehicles and allows management
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  // Tracks loading state for showing loading indicator
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Load user's vehicles when screen initializes
    _loadVehicles();
  }

  // Fetches vehicles belonging to the current user
  Future<void> _loadVehicles() async {
    // Access services through Provider
    final authService = Provider.of<AuthService>(context, listen: false);
    final vehicleService = Provider.of<VehicleService>(context, listen: false);
    
    setState(() {
      _isLoading = true; // Show loading indicator
    });
    
    // Authentication check - redirect if not logged in
    if (authService.currentUser == null) {
      // Show message and navigate back if not logged in
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to manage your vehicles')),
        );
        Navigator.pop(context);
      }
      return;
    }
    
    // Load vehicles for authenticated user
    await vehicleService.loadUserVehicles(authService.currentUser!.id!);
    
    // Update UI only if widget is still mounted
    if (mounted) {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  // Navigation to add new vehicle screen
  void _navigateToAddVehicle() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditVehicleScreen(),
      ),
    ).then((_) => _loadVehicles()); // Refresh list when returning
  }

  // Navigation to edit existing vehicle
  void _navigateToEditVehicle(Vehicle vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditVehicleScreen(vehicle: vehicle),
      ),
    ).then((_) => _loadVehicles()); // Refresh list when returning
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vehicles'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // Show loading indicator
          : Consumer<VehicleService>(
              // Use Consumer to listen for changes in VehicleService
              builder: (context, vehicleService, _) {
                final vehicles = vehicleService.vehicles;
                
                // Display empty state message when no vehicles exist
                if (vehicles.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_car_outlined,
                          size: 72,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No vehicles added yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add your first vehicle to get started',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                // Display list of vehicles using ListView.builder for efficiency
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    return Dismissible(
                      key: Key(vehicle.id ?? '${vehicle.brand}_${vehicle.model}_${vehicle.plateNumber}_$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white, size: 32),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Vehicle'),
                            content: const Text('Are you sure you want to delete this vehicle?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        final vehicleService = Provider.of<VehicleService>(context, listen: false);
                        await vehicleService.deleteVehicle(vehicle.id!, vehicle.userId);
                        _loadVehicles();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Vehicle deleted')),
                        );
                      },
                      child: _buildVehicleCard(vehicle),
                    );
                  },
                );
              },
            ),
      // Floating action button to add new vehicle
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddVehicle,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // Helper method to create vehicle card UI
  Widget _buildVehicleCard(Vehicle vehicle) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToEditVehicle(vehicle), // Navigate to edit screen on tap
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Vehicle icon container
              Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.directions_car,
                    color: Theme.of(context).primaryColor,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Vehicle information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle.brand} ${vehicle.model}', // Display brand and model
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle.plateNumber, // Display license plate
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                      ),
                    ),
                    // Conditional badge for default vehicle
                    if (vehicle.isDefault)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.green[300]!,
                            ),
                          ),
                          child: Text(
                            'Default',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Right arrow indicator
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Screen for adding or editing vehicle information
class AddEditVehicleScreen extends StatefulWidget {
  final Vehicle? vehicle; // Null for adding, non-null for editing
  
  const AddEditVehicleScreen({
    super.key,
    this.vehicle,
  });

  @override
  State<AddEditVehicleScreen> createState() => _AddEditVehicleScreenState();
}

class _AddEditVehicleScreenState extends State<AddEditVehicleScreen> {
  final _formKey = GlobalKey<FormState>(); // For form validation
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _plateNumberController;
  bool _isDefault = false;
  bool _isLoading = false;
  
  // Predefined list of Electric Vehicle brands only
  final List<String> _carBrands = [
    'Audi', 'BMW', 'BYD', 'Cadillac', 'Chevrolet', 'Ford', 'Honda', 
    'Hyundai', 'Kia', 'Lexus', 'Mazda', 'Mercedes-Benz', 'Mini', 
    'Mitsubishi', 'Nissan', 'Porsche', 'Subaru', 'Tesla', 'Volkswagen', 
    'Volvo', 'Other'
  ];
  
  // Map of ONLY Electric Vehicle models by brand
  Map<String, List<String>> _carModels = {
    'Tesla': ['Model 3', 'Model S', 'Model X', 'Model Y', 'Cybertruck', 'Roadster'],
    'BYD': ['Tang', 'Song', 'Qin', 'Han', 'Seal', 'Atto 3', 'Dolphin'],
    'BMW': ['i3', 'i4', 'iX', 'iX3'],
    'Mercedes-Benz': ['EQC', 'EQS', 'EQE', 'EQA', 'EQB'],
    'Nissan': ['Leaf', 'Ariya'],
    'Honda': ['e'],
    'Hyundai': ['Ioniq', 'Ioniq 5', 'Ioniq 6', 'Kona Electric'],
    'Kia': ['EV6', 'Niro EV', 'Soul EV'],
    'Ford': ['Mustang Mach-E', 'F-150 Lightning'],
    'Volkswagen': ['ID.4', 'ID.3', 'e-Golf'],
    'Audi': ['e-tron', 'e-tron GT', 'Q4 e-tron'],
    'Mazda': ['MX-30'],
    'Subaru': ['Solterra'],
    'Lexus': ['UX 300e'],
    'Mitsubishi': ['Outlander PHEV'],
    'Chevrolet': ['Bolt EV', 'Bolt EUV'],
    'Porsche': ['Taycan'],
    'Volvo': ['XC40 Recharge', 'C40 Recharge'],
    'Mini': ['Cooper SE'],
    'Cadillac': ['Lyriq'],
  };
  
  // Track selected dropdown values
  String? _selectedBrand;
  String? _selectedModel;
  List<String> _filteredModels = []; // Models filtered by selected brand

  @override
  void initState() {
    super.initState();
    // Initialize controller instances
    _brandController = TextEditingController();
    _modelController = TextEditingController();
    _plateNumberController = TextEditingController();
    
    // Populate form data if editing an existing vehicle
    if (widget.vehicle != null) {
      _brandController.text = widget.vehicle!.brand;
      _modelController.text = widget.vehicle!.model;
      _plateNumberController.text = widget.vehicle!.plateNumber;
      _isDefault = widget.vehicle!.isDefault;
      
      _selectedBrand = widget.vehicle!.brand;
      _selectedModel = widget.vehicle!.model;
      
      // Update model dropdown if brand is in predefined list
      if (_carBrands.contains(_selectedBrand)) {
        _updateFilteredModels();
      }
    }
  }
  
  // Updates available models when brand changes
  void _updateFilteredModels() {
    if (_selectedBrand != null && _carModels.containsKey(_selectedBrand)) {
      setState(() {
        _filteredModels = _carModels[_selectedBrand]!;
      });
    } else {
      setState(() {
        _filteredModels = [];
      });
    }
  }

  // Helper method to get electric vehicle models (now all models are electric)
  Map<String, List<String>> getElectricVehicleModels() {
    return _carModels; // All models are now electric
  }

  // Helper method to check if a model is electric (always true now)
  bool isElectricVehicle(String brand, String model) {
    return _carModels[brand]?.contains(model) ?? false;
  }

  // Helper method to determine vehicle type (always Electric now)
  String _getVehicleType(Vehicle vehicle) {
    return 'Electric'; // All vehicles are now electric
  }

  @override
  void dispose() {
    // Clean up controllers when widget is removed
    _brandController.dispose();
    _modelController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  // Saves new vehicle or updates existing one
  Future<void> _saveVehicle() async {
    // Validate form before proceeding
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true; // Show loading indicator
    });
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final vehicleService = Provider.of<VehicleService>(context, listen: false);
      
      // Check authentication status
      if (authService.currentUser == null) {
        throw Exception('User must be logged in to save vehicle');
      }
      
      final userId = authService.currentUser!.id!;
      print('Attempting to add/update vehicle for user ID: $userId');
      
      if (widget.vehicle == null) {
        // Create new vehicle
        final newVehicle = Vehicle(
          userId: userId,
          brand: _selectedBrand ?? _brandController.text,
          model: _selectedModel ?? _modelController.text,
          plateNumber: _plateNumberController.text,
          isDefault: _isDefault,
        );
        
        print('Vehicle details: ${newVehicle.toMap()}');
        
        // Add to database through service
        final result = await vehicleService.addVehicle(newVehicle);
        
        if (result != null) {
          print('Vehicle added successfully with ID: ${result.id}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle added successfully')),
          );
          Navigator.pop(context);
        } else {
          print('Failed to add vehicle');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to add vehicle')),
          );
        }
      } else {
        // Update existing vehicle
        final updatedVehicle = Vehicle(
          id: widget.vehicle!.id,
          userId: userId,
          brand: _selectedBrand ?? _brandController.text,
          model: _selectedModel ?? _modelController.text,
          plateNumber: _plateNumberController.text,
          isDefault: _isDefault,
        );
        
        print('Updating vehicle details: ${updatedVehicle.toMap()}');
        
        // Update in database through service
        final success = await vehicleService.updateVehicle(updatedVehicle);
        
        if (success) {
          print('Vehicle updated successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle updated successfully')),
          );
          Navigator.pop(context);
        } else {
          print('Failed to update vehicle');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update vehicle')),
          );
        }
      }
    } catch (e) {
      // Handle and display errors
      print('Error when saving vehicle: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  // Handles deleting a vehicle with confirmation
  Future<void> _deleteVehicle() async {
    if (widget.vehicle == null) return;
    
    // Show confirmation dialog before deleting
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: const Text('Are you sure you want to delete this vehicle? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirmed) return;
    
    setState(() {
      _isLoading = true; // Show loading indicator
    });
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final vehicleService = Provider.of<VehicleService>(context, listen: false);
      
      // Check authentication status
      if (authService.currentUser == null) {
        throw Exception('User must be logged in to delete vehicle');
      }
      
      final userId = authService.currentUser!.id!;
      // Delete from database through service
      final success = await vehicleService.deleteVehicle(widget.vehicle!.id!, userId);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle deleted successfully')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete vehicle')),
        );
      }
    } catch (e) {
      // Handle and display errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.vehicle != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Electric Vehicle' : 'Add Electric Vehicle'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // Show loading indicator
          : Form(
              key: _formKey, // Connect to form key for validation
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Electric Vehicle Indicator
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.electric_car,
                            color: Colors.green.shade600,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Electric Vehicles Only',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'All available models are electric or hybrid vehicles',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.bolt,
                            color: Colors.green.shade600,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    
                    // Brand Dropdown
                    const Text(
                      'Brand',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedBrand,
                        decoration: const InputDecoration(
                          hintText: 'Select brand',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                        items: _carBrands.map((brand) {
                          return DropdownMenuItem<String>(
                            value: brand,
                            child: Text(brand),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedBrand = value;
                            _selectedModel = null; // Reset model when brand changes
                            _brandController.text = value ?? '';
                          });
                          _updateFilteredModels(); // Update available models
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a brand';
                          }
                          return null;
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Model Dropdown/TextField - conditional based on brand selection
                    const Text(
                      'Model',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      // Show dropdown if models available for brand, otherwise text field
                      child: _selectedBrand != null && _filteredModels.isNotEmpty
                        ? DropdownButtonFormField<String>(
                            value: _selectedModel,
                            decoration: const InputDecoration(
                              hintText: 'Select model',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                            ),
                            items: _filteredModels.map((model) {
                              return DropdownMenuItem<String>(
                                value: model,
                                child: Text(model),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedModel = value;
                                _modelController.text = value ?? '';
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please select a model';
                              }
                              return null;
                            },
                          )
                        : TextFormField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              hintText: 'Enter model',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a model';
                              }
                              return null;
                            },
                          ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Vehicle Number Plate
                    const Text(
                      'Vehicle Number Plate',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextFormField(
                        controller: _plateNumberController,
                        decoration: const InputDecoration(
                          hintText: 'Enter vehicle number plate',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a vehicle number plate';
                          }
                          return null;
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Default Vehicle Toggle Switch
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Set as Default?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Switch(
                          value: _isDefault,
                          onChanged: (value) {
                            setState(() {
                              _isDefault = value;
                            });
                          },
                          activeColor: Theme.of(context).primaryColor,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Action Buttons - Different layout for edit vs. add modes
                    if (isEditing)
                      Row(
                        children: [
                          // Delete button - only shown in edit mode
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _deleteVehicle,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Save button
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saveVehicle,
                              icon: const Icon(Icons.check),
                              label: const Text('Save'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      // Add button for new vehicle
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveVehicle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Add'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
} 