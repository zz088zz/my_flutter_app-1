import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class ChangePasswordPage extends StatefulWidget {
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final currentPasswordCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();
  bool showCurrent = false;
  bool showNew = false;
  bool showConfirm = false;
  bool _isLoading = false;

  @override
  void dispose() {
    currentPasswordCtrl.dispose();
    newPasswordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _changePassword() async {
    final currentPassword = currentPasswordCtrl.text.trim();
    final newPassword = newPasswordCtrl.text.trim();
    final confirmPassword = confirmPasswordCtrl.text.trim();

    // Validate inputs
    if ([currentPassword, newPassword, confirmPassword].any((e) => e.isEmpty)) {
      _showError("All fields are required");
      return;
    }

    if (currentPassword == newPassword) {
      _showError("New password must be different from current password");
      return;
    }

    if (newPassword != confirmPassword) {
      _showError("New passwords do not match");
      return;
    }

    if (newPassword.length < 6) {
      _showError("Password must be at least 6 characters");
      return;
    }
    
    // Simple password strength check
    bool hasUppercase = newPassword.contains(RegExp(r'[A-Z]'));
    bool hasDigit = newPassword.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = newPassword.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    
    if (!(hasUppercase && hasDigit) && !hasSpecialChar) {
      _showError("Password should contain uppercase letters, numbers or special characters");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Verify current password
      final isCorrect = await authService.verifyPassword(currentPassword);
      if (!isCorrect) {
        _showError("Current password is incorrect");
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Change password
      final success = await authService.changePassword(newPassword);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password updated successfully"))
        );
        Navigator.pop(context);
      } else {
        _showError("Failed to update password. Please try again.");
      }
    } catch (e) {
      _showError("An error occurred: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
        title: const Text("Change Password"),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Update your password",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Your new password must be different from your current password.",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _passwordField(
                  "Current Password", 
                  currentPasswordCtrl, 
                  showCurrent, 
                  () => setState(() => showCurrent = !showCurrent)
                ),
                _passwordField(
                  "New Password", 
                  newPasswordCtrl, 
                  showNew, 
                  () => setState(() => showNew = !showNew)
                ),
                _passwordField(
                  "Confirm New Password", 
                  confirmPasswordCtrl, 
                  showConfirm, 
                  () => setState(() => showConfirm = !showConfirm)
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Update Password",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _passwordField(
    String label, 
    TextEditingController controller, 
    bool showPassword, 
    VoidCallback toggleVisibility
  ) {
    final isNewPassword = label.contains("New");
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: !showPassword,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          helperText: isNewPassword ? 'At least 6 characters with uppercase & numbers or special characters' : null,
          helperMaxLines: 2,
          suffixIcon: IconButton(
            icon: Icon(showPassword ? Icons.visibility : Icons.visibility_off),
            onPressed: toggleVisibility,
          ),
        ),
      ),
    );
  }
} 