import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import 'package:provider/provider.dart';
import '../screens/admin/admin_dashboard.dart';
import 'sign_in_page.dart'; // Corrected import for SignInPage

class AdminLoginPage extends StatefulWidget {
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool showPassword = false;
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _adminLogin(BuildContext context) async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Email and password cannot be empty");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final adminService = Provider.of<AdminService>(context, listen: false);
      final isAdmin = await adminService.adminLogin(email, password);
      
      if (isAdmin) {
        try {
          await adminService.init();
          await adminService.loadAllStations();
          
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => AdminDashboard()),
            (route) => false,
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Welcome, Admin"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (initError) {
          print("Error initializing admin service: $initError");
          _showError("Login successful but failed to load admin data. Please try again.");
        }
      } else {
        _showError("Invalid admin credentials or insufficient permissions");
      }
    } catch (e) {
      print("Admin login error: $e");
      String errorMessage = "An error occurred. Please try again.";
      
      // Provide more specific error messages
      if (e.toString().contains('user-not-found')) {
        errorMessage = "No account found with this email address.";
      } else if (e.toString().contains('wrong-password')) {
        errorMessage = "Incorrect password.";
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = "Invalid email format.";
      } else if (e.toString().contains('too-many-requests')) {
        errorMessage = "Too many failed attempts. Please try again later.";
      } else if (e.toString().contains('network')) {
        errorMessage = "Network error. Please check your internet connection.";
      }
      
      _showError(errorMessage);
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
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Text("Admin Login"),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              SizedBox(height: 50),
              Icon(
                Icons.admin_panel_settings,
                size: 80,
                color: Colors.indigo[700],
              ),
              SizedBox(height: 20),
              Text(
                "Administrator Access",
                style: TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
              SizedBox(height: 10),
              Text(
                "Enter admin credentials to login",
                style: TextStyle(
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 30),
              _inputField("Admin Email", controller: emailController),
              _inputField("Admin Password", controller: passwordController, isPassword: true),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _adminLogin(context),
                child: Text("Login as Admin"),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Colors.indigo[700],
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => SignInPage()),
                  (route) => false,
                ),
                child: Text("Back to User Login"),
              ),
            ],
          ),
        ),
    );
  }

  Widget _inputField(String label, {required TextEditingController controller, bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !showPassword,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(showPassword ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => showPassword = !showPassword),
          )
              : null,
        ),
      ),
    );
  }
} 