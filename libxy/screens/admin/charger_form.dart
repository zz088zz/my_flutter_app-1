import 'package:flutter/material.dart';
import '../../models/charger.dart';

class ChargerForm extends StatefulWidget {
  final Charger? charger;
  final String stationId;
  final Future<bool> Function(Charger charger) onSave;

  const ChargerForm({
    Key? key,
    this.charger,
    required this.stationId,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ChargerForm> createState() => _ChargerFormState();
}

class _ChargerFormState extends State<ChargerForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _powerController = TextEditingController();
  final _pricePerKWhController = TextEditingController();
  String _type = 'AC';
  bool _isAvailable = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.charger != null) {
      _nameController.text = widget.charger!.name;
      _powerController.text = widget.charger!.power.toString();
      _pricePerKWhController.text = widget.charger!.pricePerKWh.toString();
      _type = widget.charger!.type;
      _isAvailable = widget.charger!.isAvailable;
    } else {
      // Set default values for new chargers
      _powerController.text = '11.0';
      _pricePerKWhController.text = '0.80';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _powerController.dispose();
    _pricePerKWhController.dispose();
    super.dispose();
  }

  void _updateDefaultValues() {
    // Update power and price when plug type changes
    if (_type == 'AC') {
      _powerController.text = '11.0';
      _pricePerKWhController.text = '0.80';
    } else {
      _powerController.text = '50.0';
      _pricePerKWhController.text = '1.30';
    }
  }

  Future<void> _saveCharger() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Create or update the charger
        final charger = Charger(
          id: widget.charger?.id,
          stationId: widget.stationId,
          name: _nameController.text,
          type: _type,
          power: double.parse(_powerController.text),
          pricePerKWh: double.parse(_pricePerKWhController.text),
          isAvailable: _isAvailable,
        );

        final result = await widget.onSave(charger);

        if (!mounted) return;

        if (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.charger == null
                  ? 'Charger added successfully'
                  : 'Charger updated successfully'),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save charger'),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.charger == null ? 'Add Charger' : 'Edit Charger'),
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
                        labelText: 'Charger Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a charger name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _type,
                      decoration: const InputDecoration(
                        labelText: 'Plug Type',
                        border: OutlineInputBorder(),
                      ),
                      items: ['AC', 'DC'].map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _type = value!;
                          _updateDefaultValues();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _powerController,
                      decoration: const InputDecoration(
                        labelText: 'Power (kW)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter power in kW';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pricePerKWhController,
                      decoration: const InputDecoration(
                        labelText: 'Price per kWh (RM)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter price per kWh';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Available'),
                      value: _isAvailable,
                      onChanged: (value) {
                        setState(() {
                          _isAvailable = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _saveCharger,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Charger'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
} 