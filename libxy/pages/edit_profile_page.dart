import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class EditProfilePage extends StatefulWidget {
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController firstNameCtrl;
  late TextEditingController lastNameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController phoneCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser!;
    
    firstNameCtrl = TextEditingController(text: user.firstName);
    lastNameCtrl = TextEditingController(text: user.lastName);
    emailCtrl = TextEditingController(text: user.email);
    phoneCtrl = TextEditingController(text: user.phoneNumber);
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    final fname = firstNameCtrl.text.trim();
    final lname = lastNameCtrl.text.trim();
    final email = emailCtrl.text.trim(); // Keep existing email, don't change it
    final phone = phoneCtrl.text.trim();

    if ([fname, lname, phone].any((e) => e.isEmpty)) {
      _showError("All required fields must be filled");
      return;
    }
    
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      _showError("Phone number must be between 10-15 digits");
      return;
    }
    
    final formattedPhone = _formatPhoneForStorage(phone);
    
    final nameRegex = RegExp(r'^[a-zA-Z\s\-]+$');
    if (!nameRegex.hasMatch(fname)) {
      _showError("First name should contain only letters, spaces and hyphens");
      return;
    }
    
    if (!nameRegex.hasMatch(lname)) {
      _showError("Last name should contain only letters, spaces and hyphens");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser!;
      
      print('Updating user profile - ID: ${currentUser.id}, Email: $email');
      
      final updatedUser = User(
        id: currentUser.id,
        firstName: fname,
        lastName: lname,
        email: email,
        phoneNumber: formattedPhone,
        password: currentUser.password,
      );

      final success = await authService.updateUserProfile(updatedUser);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully"))
        );
        Navigator.pop(context);
      } else {
        _showError("Failed to update profile. Please try again.");
      }
    } catch (e) {
      print('Error in _save: $e');
      _showError("An error occurred: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatPhoneForStorage(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // If it's a standard 10-digit number starting with 0 (Malaysian format)
    if (digits.length == 10 && digits.startsWith('0')) {
      // Remove the leading 0 and add +60
      return '+60${digits.substring(1)}';
    }
    
    // If it's a 9-digit number (already without leading 0)
    if (digits.length == 9) {
      return '+60$digits';
    }
    
    if (phone.startsWith('+') && digits.length >= 11) {
      return phone;
    }
    
    // If it has 12 digits and starts with 60 (Malaysian country code)
    if (digits.length == 12 && digits.startsWith('60')) {
      return '+$digits';
    }
    
    if (digits.length >= 11) {
      if (digits.startsWith('60')) {
        return '+$digits';
      } else {
        return '+60$digits';
      }
    }
    
    return '+60$digits';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message), 
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _input("First Name", controller: firstNameCtrl),
                _input("Last Name", controller: lastNameCtrl),
                _input("Email", controller: emailCtrl, keyboardType: TextInputType.emailAddress, readOnly: true),
                _input("Phone", controller: phoneCtrl, keyboardType: TextInputType.phone),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Save Changes",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
    );
  }

  Widget _input(String label, {
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    String? hintText;
    List<TextInputFormatter>? inputFormatters;
    
    if (label == "Email") {
      hintText = "example@email.com";
    } else if (label == "Phone") {
      hintText = "e.g., +60 12 345 6789";
      
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\(\) ]')),
        LengthLimitingTextInputFormatter(20),
      ];
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: readOnly ? Colors.grey[100] : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          hintText: hintText,
          helperText: label == "Phone" ? "Enter a valid phone number with country code" : 
                      label == "Email" ? "Email cannot be changed" : null,
          helperMaxLines: 2,
          prefixIcon: label == "Phone" ? Icon(Icons.phone) : 
                      label == "Email" ? Icon(Icons.email) :
                      label.contains("Name") ? Icon(Icons.person) : null,
        ),
      ),
    );
  }
} 