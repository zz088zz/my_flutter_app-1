import 'package:flutter/material.dart';
import 'station_management.dart';
import 'admin_transactions.dart';
import 'admin_stats.dart';
import 'admin_users.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../pages/admin_login_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  // Static method to navigate to a specific page
  static void navigateToPage(BuildContext context, int pageIndex) {
    final state = context.findAncestorStateOfType<_AdminDashboardState>();
    if (state != null) {
      state.setSelectedIndex(pageIndex);
    }
  }

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  
  // Method to update the selected index from outside
  void setSelectedIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  
  final List<Widget> _screens = [
    const AdminStats(),
    const StationManagement(),
    const AdminTransactions(),
    AdminUsers(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.indigo[700],
        child: const Icon(Icons.logout, color: Colors.white),
        onPressed: () async {
          await FirebaseAuth.instance.signOut();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => AdminLoginPage()),
            (route) => false,
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: Colors.white,
        selectedItemColor: Colors.indigo[700],
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.ev_station),
            label: 'Stations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Users',
          ),
        ],
      ),
    );
  }
} 