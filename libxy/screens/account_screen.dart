import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import 'vehicle_screen.dart';
import 'payment_method_management_screen.dart';
import '../models/user.dart';
import 'wallet_screen.dart';
import '../pages/edit_profile_page.dart';
import '../pages/change_password_page.dart';
import '../pages/sign_in_page.dart';
import '../screens/rewards_screen.dart';

// Main account screen showing user profile, wallet, and account settings
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // Track loading state for UI feedback
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Load user data when screen initializes
    _loadUserData();
  }

  // Fetches user information and wallet balance from services
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      // Access services through Provider
      final authService = Provider.of<AuthService>(context, listen: false);
      final walletService = Provider.of<WalletService>(context, listen: false);

      // Get user ID (use demo user ID if not logged in)
      final userId = authService.currentUser?.id ?? '1';

      // Load wallet data for the user
      await walletService.loadWalletForUser(userId);
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      // Only update state if widget is still mounted
      if (mounted) {
        setState(() {
          _isLoading = false; // Hide loading indicator
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Access required services through Provider
    final authService = Provider.of<AuthService>(context);
    final walletService = Provider.of<WalletService>(context);

    // Get current user or fall back to demo user if not logged in
    final user =
        authService.currentUser ??
        User(
          id: '1',
          email: 'demo@example.com',
          firstName: 'Demo',
          lastName: 'User',
          phoneNumber: '1234567890',
        );

    // Format wallet balance with currency
    final formattedBalance = 'RM ${walletService.balance.toStringAsFixed(2)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(),
              ) // Show loading state
              : RefreshIndicator(
                onRefresh: _loadUserData, // Pull to refresh functionality
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // User profile card with name, email and avatar
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // User avatar with initials
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  child: Text(
                                    '${user.firstName.isNotEmpty ? user.firstName[0] : '?'}${user.lastName.isNotEmpty ? user.lastName[0] : '?'}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // User name and email
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${user.firstName} ${user.lastName}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      user.email,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            // Additional user information row
                            _buildInfoRow(
                              Icons.phone,
                              'Phone',
                              user.phoneNumber,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Wallet Card with balance and top-up button
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const WalletScreen(),
                              ),
                            ),
                        child: Container(
                          padding: const EdgeInsets.all(16.0),
                          // Gradient background for visual appeal
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'My Wallet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Icon(
                                    Icons.account_balance_wallet,
                                    color: Colors.white.withOpacity(0.8),
                                    size: 24,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // Display wallet balance
                              Text(
                                formattedBalance,
                                style: const TextStyle(
                                  fontSize: 28,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Available Balance',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Top-up button
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Top Up',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Account options section header
                    const Text(
                      'Account Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Edit Profile tile - navigates to profile editing page
                    _buildSettingsTile(
                      context,
                      Icons.person_outline,
                      'Edit Profile',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfilePage(),
                        ),
                      ),
                    ),

                    // Change Password tile - navigates to password change page
                    _buildSettingsTile(
                      context,
                      Icons.lock_outline,
                      'Change Password',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChangePasswordPage(),
                        ),
                      ),
                    ),

                    // My Vehicles tile - navigates to vehicle management
                    _buildSettingsTile(
                      context,
                      Icons.directions_car_outlined,
                      'My Vehicles',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const VehicleScreen(),
                        ),
                      ),
                    ),

                    // Payment Methods tile - navigates to payment method management
                    _buildSettingsTile(
                      context,
                      Icons.credit_card_outlined,
                      'Payment Methods',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaymentMethodManagementScreen(),
                        ),
                      ),
                    ),

                    // Rewards tile - navigates to rewards screen
                    _buildSettingsTile(
                      context,
                      Icons.stars_outlined,
                      'Rewards',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RewardsScreen(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Logout button - signs user out and navigates to login
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            final authService = Provider.of<AuthService>(
                              context,
                              listen: false,
                            );
                            await authService.logout();

                            // Navigate to sign-in page and remove all previous routes
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SignInPage(),
                              ),
                              (route) => false,
                            );
                          } catch (e) {
                            // Display error message if logout fails
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error logging out: $e')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Log Out',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
    );
  }

  // Helper method to build consistent info rows with icon, label and value
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // Helper method to build consistent settings list tiles
  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
