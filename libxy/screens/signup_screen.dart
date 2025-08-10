import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmailValidationResult {
  final bool isValid;
  final String errorMessage;
  
  EmailValidationResult(this.isValid, this.errorMessage);
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registerUser() async {
    // Get all input values and trim whitespace
    final email = _emailController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    
    // Check for empty fields
    if (email.isEmpty || firstName.isEmpty || lastName.isEmpty || 
        phone.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'All fields are required';
      });
      return;
    }
    
    // Validate email format
    final emailValidation = _validateEmail(email);
    if (!emailValidation.isValid) {
      setState(() {
        _errorMessage = emailValidation.errorMessage;
      });
      return;
    }
    
    // Validate phone number (allow different formats but require at least 10 digits)
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      setState(() {
        _errorMessage = 'Phone number must be between 10-15 digits';
      });
      return;
    }
    
    // Format phone number for storage (adding +60 country code if needed)
    final formattedPhone = _formatPhoneForStorage(phone);
    
    // Validate password - at least 6 characters
    if (password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters long';
      });
      return;
    }
    
    // Simple password strength check
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasDigit = password.contains(RegExp(r'[0-9]'));
    bool hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    
    if (!(hasUppercase && hasDigit) && !hasSpecialChar) {
      setState(() {
        _errorMessage = 'Password should contain uppercase letters, numbers or special characters';
      });
      return;
    }
    // Show loading indicator
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // Call your registration service here
      // For now, just simulate a successful registration
      await Future.delayed(const Duration(seconds: 1));
      
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home',
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Registration failed: ${e.toString()}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Text(
                  'Sign Up',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _lastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\(\) ]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: 'e.g., +60 12 345 6789',
                    helperText: 'Enter a valid phone number with country code',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 6 characters with uppercase & numbers or special characters',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _registerUser,
                        child: const Text('Create Account'),
                      ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already a member?',
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text(
                        'Sign in',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 