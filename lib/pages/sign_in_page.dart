import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'sign_up_page.dart';
import 'forgot_password_page.dart';
import 'package:provider/provider.dart';
import 'admin_login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class SignInPage extends StatefulWidget {
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool showPassword = false;
  bool _isLoading = false;

  void _login(BuildContext context) async {
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
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await authService.login(email, password);

      switch (result) {
        case LoginResult.success:
          Navigator.pushAndRemoveUntil(
            context, 
            MaterialPageRoute(builder: (_) => MainScreen()), 
            (route) => false
          );
          break;
        case LoginResult.accountDisabled:
          _showError("Your account has been disabled. Please contact support for assistance.");
          break;
        case LoginResult.invalidCredentials:
          _showError("Invalid email or password. Please check your credentials.");
          break;
        case LoginResult.userNotFound:
          _showError("No account found with this email address.");
          break;
        case LoginResult.error:
          _showError("An error occurred during login. Please try again.");
          break;
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = "No account found with this email address.";
          break;
        case 'wrong-password':
          errorMessage = "Incorrect password. Please try again.";
          break;
        case 'invalid-email':
          errorMessage = "Please enter a valid email address.";
          break;
        case 'user-disabled':
          errorMessage = "This account has been disabled.";
          break;
        case 'too-many-requests':
          errorMessage = "Too many failed attempts. Please try again later.";
          break;
        default:
          errorMessage = "Login failed: ${e.message}";
      }
      _showError(errorMessage);
    } catch (e) {
      print('Login error: $e');
      _showError("An error occurred. Please check your internet connection and try again.");
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
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              SizedBox(height: 100),
              Text("Sign in", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              _inputField("Email", controller: emailController),
              _inputField("Password", controller: passwordController, isPassword: true),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordPage())),
                  child: Text("Forgot Password?"),
                ),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _login(context),
                child: Text("Sign In"),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SignUpPage())),
                child: Text("Don't have an account yet?", style: TextStyle(decoration: TextDecoration.underline)),
              ),
              SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLoginPage())),
                icon: Icon(Icons.admin_panel_settings),
                label: Text("Admin Login"),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(200, 40),
                  side: BorderSide(color: Colors.grey),
                ),
              )
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