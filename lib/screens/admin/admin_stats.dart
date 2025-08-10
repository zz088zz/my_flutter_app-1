import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/admin_service.dart';
import 'package:intl/intl.dart';
import 'admin_dashboard.dart';
import '../../models/transaction.dart' as app_transaction;
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'fine_management_screen.dart';

class AdminStats extends StatefulWidget {
  const AdminStats({Key? key}) : super(key: key);

  @override
  State<AdminStats> createState() => _AdminStatsState();
}

class _AdminStatsState extends State<AdminStats> {
  bool _isLoading = true;
  int _stationCount = 0;
  int _totalChargers = 0;
  int _transactionCount = 0;
  double _totalRevenue = 0;
  double _totalEnergyImpact = 0;
  
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }
  
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final adminService = Provider.of<AdminService>(context, listen: false);
      
      // Load stations and their chargers
      await adminService.loadAllStations();
      
      // Get transaction data
      final transactions = await adminService.getAllTransactions();
      
      // Calculate stats
      final stationCount = adminService.stations.length;
      int totalChargers = 0;
      for (final station in adminService.stations) {
        totalChargers += station.chargers.length;
      }
      
      // Calculate using the same methods as in admin_transactions.dart
      // Helper function to check if a transaction is a credit transaction (income)
      bool isTransactionCredit(app_transaction.Transaction transaction) {
        return transaction.transactionType == 'credit' && 
               !transaction.description.toLowerCase().contains('deposit');
      }

      // Helper function to check if a transaction is a refund
      bool isTransactionRefund(app_transaction.Transaction transaction) {
        return !isTransactionCredit(transaction) && 
            transaction.description.toLowerCase().contains('refund');
      }
      
      // Helper function to check if a transaction is a deposit
      bool isTransactionDeposit(app_transaction.Transaction transaction) {
        return transaction.description.toLowerCase().contains('deposit');
      }
      
      // Helper function to check if a transaction is a payment (debit not refund or deposit)
      bool isTransactionPayment(app_transaction.Transaction transaction) {
        final isDebit = transaction.transactionType == 'debit';
        final isRefund = transaction.description.toLowerCase().contains('refund');
        final isDeposit = transaction.description.toLowerCase().contains('deposit');
        
        return isDebit && !isRefund && !isDeposit;
      }

      // Extract refund info exactly as in admin_transactions.dart
      Map<String, double> extractRefundInfo(app_transaction.Transaction transaction) {
        double originalAmount = 0.0;
        double refundAmount = transaction.amount;
        double actualRevenue = 0.0;
        
        final description = transaction.description.toLowerCase();
        
        try {
          // Try to extract original amount with different patterns
          if (description.contains('original') && description.contains('rm')) {
            // Find all currency amounts in the description
            final regex = RegExp(r'rm\s*(\d+(\.\d+)?)');
            final matches = regex.allMatches(description);
            
            if (matches.length >= 2) {
              // If we have at least two matches, assume first is original, second is refund
              final originalStr = matches.elementAt(0).group(1);
              if (originalStr != null) {
                originalAmount = double.tryParse(originalStr) ?? 0.0;
              }
            } else if (matches.length == 1) {
              // If only one match, check if it's different from the transaction amount
              final amountStr = matches.first.group(1);
              if (amountStr != null) {
                final extractedAmount = double.tryParse(amountStr) ?? 0.0;
                if (extractedAmount > transaction.amount) {
                  originalAmount = extractedAmount;
                }
              }
            }
          }
          
          // Calculate actual revenue if we have an original amount
          if (originalAmount > 0 && originalAmount > refundAmount) {
            actualRevenue = originalAmount - refundAmount;
          }
        } catch (e) {
          print('Error parsing refund amount: $e');
        }
        
        return {
          'originalAmount': originalAmount,
          'refundAmount': refundAmount,
          'actualRevenue': actualRevenue,
        };
      }
      
      // Calculate metrics using same algorithm as transaction page
      double totalRevenue = 0;
      double totalPayments = 0;
      double totalRefunds = 0;
      double totalDeposits = 0;
      double netIncome = 0;
      
      // Process all transactions to calculate financial metrics
      for (var transaction in transactions) {
        if (isTransactionDeposit(transaction)) {
          // Deposits are tracked separately since they will be deducted when user pays after charging
          totalDeposits += transaction.amount;
          // Don't count deposits in net income until they become actual payments
        } else if (isTransactionCredit(transaction)) {
          // Credit transactions represent revenue to the system
          totalRevenue += transaction.amount;
          netIncome += transaction.amount;
        } else if (isTransactionRefund(transaction)) {
          // Track refunds separately
          totalRefunds += transaction.amount;
          netIncome -= transaction.amount;
          
          // Handle partial refunds
          final refundInfo = extractRefundInfo(transaction);
          final actualRevenue = refundInfo['actualRevenue'] ?? 0.0;
          
          // If we determined this was a partial refund with some revenue kept
          if (actualRevenue > 0) {
            // Add this partial revenue to our totals
            totalRevenue += actualRevenue;
            netIncome += actualRevenue;
          }
        } else if (isTransactionPayment(transaction)) {
          // Regular payments for charging sessions
          totalPayments += transaction.amount;
          netIncome += transaction.amount; // Payments add to our net income
        }
      }
      
      // Calculate energy impact in kWh
      double totalEnergyConsumed = 0;
      
      try {
        // Query charging sessions from Firestore to calculate energy consumption
        final chargingSessionsQuery = await firestore.FirebaseFirestore.instance
            .collection('charging_sessions')
            .get();
        
        print('Found ${chargingSessionsQuery.docs.length} charging sessions');
        
        // Calculate total energy consumed from all charging sessions
        for (var doc in chargingSessionsQuery.docs) {
          final data = doc.data();
          final energyConsumed = data['energy_consumed'];
          
          if (energyConsumed != null) {
            double energy = 0.0;
            if (energyConsumed is num) {
              energy = energyConsumed.toDouble();
            } else if (energyConsumed is String) {
              energy = double.tryParse(energyConsumed) ?? 0.0;
            }
            
            totalEnergyConsumed += energy;
            
            // Debug logging for first few sessions
            if (totalEnergyConsumed <= 50.0) {
              print('Session ${doc.id}: ${energy} kWh');
            }
          }
        }
        
        print('Total energy consumed: ${totalEnergyConsumed.toStringAsFixed(2)} kWh');
        
      } catch (e) {
        print('Error loading energy consumption data: $e');
        
        // Fallback: Estimate energy consumption from payment transactions
        try {
          double estimatedEnergy = 0.0;
          
          for (var transaction in transactions) {
            if (isTransactionPayment(transaction) && 
                transaction.description.toLowerCase().contains('charging')) {
              // Estimate energy based on payment amount
              // Average price is around RM 1.00 per kWh
              final estimatedKWh = transaction.amount / 1.0;
              estimatedEnergy += estimatedKWh;
            }
          }
          
          if (estimatedEnergy > 0) {
            totalEnergyConsumed = estimatedEnergy;
            print('Estimated energy consumption from transactions: ${totalEnergyConsumed.toStringAsFixed(2)} kWh');
          }
          
        } catch (estimationError) {
          print('Error estimating energy consumption: $estimationError');
        }
      }
      
      setState(() {
        _isLoading = false;
        _stationCount = stationCount;
        _totalChargers = totalChargers;
        _transactionCount = transactions.length;
        _totalRevenue = netIncome;
        _totalEnergyImpact = totalEnergyConsumed;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard data: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current time for greeting
    final hour = DateTime.now().hour;
    String greeting;
    
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }
    
    // Get current date
    final today = DateTime.now();
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final formattedDate = dateFormat.format(today);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.indigo[800],
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.admin_panel_settings,
                                color: Colors.indigo,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$greeting, Admin',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome to EV Charging Admin Dashboard',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage stations, monitor transactions, and view system statistics.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Statistics grid
                  const Text(
                    'System Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStatCard(
                        'Stations',
                        _stationCount.toString(),
                        Icons.ev_station,
                        Colors.blue,
                      ),
                      _buildStatCard(
                        'Chargers',
                        _totalChargers.toString(),
                        Icons.electric_bolt,
                        Colors.green,
                      ),
                      _buildStatCard(
                        'Transactions',
                        _transactionCount.toString(),
                        Icons.receipt_long,
                        Colors.orange,
                      ),
                      _buildStatCard(
                        'Net Income',
                        'RM ${_totalRevenue.toStringAsFixed(2)}',
                        Icons.account_balance_wallet,
                        _totalRevenue >= 0 ? Colors.green : Colors.red,
                      ),
                      _buildStatCard(
                        'Energy Impact',
                        '${_totalEnergyImpact.toStringAsFixed(2)} kWh',
                        Icons.electric_bolt,
                        Colors.orange,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Quick access links
                  const Text(
                    'Quick Access',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Quick access cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          'Manage Stations',
                          'Add or edit charging stations',
                          Icons.place,
                          Colors.indigo,
                          () => _navigateToIndex(1),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildActionCard(
                          'View Transactions',
                          'See all financial activity',
                          Icons.receipt_long,
                          Colors.teal,
                          () => _navigateToIndex(2),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Fine management card
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          'Fine Management',
                          'Monitor and manage overtime fines',
                          Icons.warning,
                          Colors.red,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FineManagementScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Tips or announcements
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          color: Colors.amber.shade800,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pro Tip',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Check transaction statistics regularly to monitor system performance and revenue growth.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: color,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _navigateToIndex(int index) {
    AdminDashboard.navigateToPage(context, index);
  }
}