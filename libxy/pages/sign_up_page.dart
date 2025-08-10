import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'sign_in_page.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class EmailValidationResult {
  final bool isValid;
  final String errorMessage;
  
  EmailValidationResult(this.isValid, this.errorMessage);
}

class SignUpPage extends StatefulWidget {
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneController = TextEditingController();
  bool showPassword = false;
  bool showConfirmPassword = false;
  bool _isLoading = false;

  void _register(BuildContext context) async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final phone = phoneController.text.trim();

    // Validation
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty || 
        firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      _showError("All fields are required");
      return;
    }
    
    // Validate email format
    final emailValidation = _validateEmail(email);
    if (!emailValidation.isValid) {
      _showError(emailValidation.errorMessage);
      return;
    }
    
    // Validate phone number
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      _showError("Phone number must be between 10-15 digits");
      return;
    }
    
    // Format phone number consistently
    final formattedPhone = _formatPhoneForStorage(phone);
    
    // Validate name fields
    final nameRegex = RegExp(r'^[a-zA-Z\s\-]+$');
    if (!nameRegex.hasMatch(firstName)) {
      _showError("First name should contain only letters, spaces and hyphens");
      return;
    }
    
    if (!nameRegex.hasMatch(lastName)) {
      _showError("Last name should contain only letters, spaces and hyphens");
      return;
    }

    if (password != confirmPassword) {
      _showError("Passwords do not match");
      return;
    }
    
    // Validate password strength
    if (password.length < 6) {
      _showError("Password must be at least 6 characters");
      return;
    }
    
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasDigit = password.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    
    if (!(hasUppercase && hasDigit) && !hasSpecialChar) {
      _showError("Password should contain uppercase letters, numbers or special characters");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final success = await authService.register(
        email, 
        password, 
        firstName, 
        lastName, 
        formattedPhone // use the formatted phone number
      );

      if (success) {
        _showSuccess("Registration successful! Please sign in.");
        Future.delayed(Duration(seconds: 2), () {
          Navigator.pushAndRemoveUntil(
            context, 
            MaterialPageRoute(builder: (_) => SignInPage()),
            (route) => false, // Remove all previous routes
          );
        });
      } else {
        _showError("Registration failed. Please try again.");
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = "This email is already registered. Please use a different email or sign in.";
          break;
        case 'weak-password':
          errorMessage = "Password is too weak. Please use a stronger password.";
          break;
        case 'invalid-email':
          errorMessage = "Please enter a valid email address.";
          break;
        case 'operation-not-allowed':
          errorMessage = "Email registration is not enabled. Please contact support.";
          break;
        default:
          errorMessage = "Registration failed: ${e.message}";
      }
      _showError(errorMessage);
    } catch (e) {
      print('Registration error: $e');
      _showError("Registration failed. Please check your internet connection and try again.");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Basic email validation
  EmailValidationResult _validateEmail(String email) {
    // Basic format validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      return EmailValidationResult(false, "Please enter a valid email address");
    }
    
    // Check for suspicious patterns
    if (email.contains('..') || email.startsWith('.') || email.endsWith('.')) {
      return EmailValidationResult(false, "Email contains invalid characters");
    }
    
    return EmailValidationResult(true, "");
  }

  // Helper method to format phone number consistently for storage
  String _formatPhoneForStorage(String phone) {
    // Remove all non-digit characters
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
    
    // If it already has a country code (starting with + and 11+ digits)
    if (phone.startsWith('+') && digits.length >= 11) {
      return phone;
    }
    
    // If it has 12 digits and starts with 60 (Malaysian country code)
    if (digits.length == 12 && digits.startsWith('60')) {
      return '+$digits';
    }
    
    // If it has 11+ digits but no + prefix, assume it needs +
    if (digits.length >= 11) {
      if (digits.startsWith('60')) {
        return '+$digits';
      } else {
        return '+60$digits';
      }
    }
    
    // Default case - just return with +60 prefix
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message), 
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Create Account", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _inputField("First Name", controller: firstNameController)),
                  SizedBox(width: 16),
                  Expanded(child: _inputField("Last Name", controller: lastNameController)),
                ],
              ),
              _inputField("Email", controller: emailController),
              _inputField("Phone", controller: phoneController),
              _inputField("Password", controller: passwordController, isPassword: true),
              _inputField("Confirm Password", controller: confirmPasswordController, isPassword: true),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _register(context),
                child: Text("Sign Up"),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text("Already have an account? Sign In", 
                    style: TextStyle(decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _inputField(String label, {required TextEditingController controller, bool isPassword = false}) {
    // Define type-specific configurations
    TextInputType? keyboardType;
    List<TextInputFormatter>? inputFormatters;
    String? hintText;
    String? helperText;
    
    if (label == "Email") {
      keyboardType = TextInputType.emailAddress;
      hintText = "example@email.com";
    } else if (label == "Phone") {
      keyboardType = TextInputType.phone;
      hintText = "e.g., +60 12 345 6789";
      helperText = "Enter a valid phone number with country code";
      inputFormatters = [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\(\) ]')),
        LengthLimitingTextInputFormatter(20),
      ];
    } else if (label.contains("Password")) {
      helperText = isPassword ? "At least 6 characters with uppercase & numbers or special characters" : null;
    }
    
    // Determine which password visibility state to use
    bool isVisible = false;
    VoidCallback toggleVisibility;
    
    if (label == "Password") {
      isVisible = showPassword;
      toggleVisibility = () => setState(() => showPassword = !showPassword);
    } else if (label == "Confirm Password") {
      isVisible = showConfirmPassword;
      toggleVisibility = () => setState(() => showConfirmPassword = !showConfirmPassword);
    } else {
      // Dummy function for non-password fields
      toggleVisibility = () {};
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          hintText: hintText,
          helperText: helperText,
          helperMaxLines: 2,
          prefixIcon: _getIconForField(label),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off),
            onPressed: toggleVisibility,
          )
              : null,
        ),
      ),
    );
  }
  
  // Helper method to get appropriate icon for each field
  Widget? _getIconForField(String label) {
    if (label == "Email") {
      return Icon(Icons.email_outlined);
    } else if (label == "Phone") {
      return Icon(Icons.phone_outlined);
    } else if (label.contains("Name")) {
      return Icon(Icons.person_outline);
    } else if (label.contains("Password")) {
      return Icon(Icons.lock_outline);
    }
    return null;
  }
} 