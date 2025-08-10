import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../services/admin_service.dart';
import 'package:provider/provider.dart';

class AdminTransactions extends StatefulWidget {
  const AdminTransactions({super.key});

  @override
  State<AdminTransactions> createState() => _AdminTransactionsState();
}

class _AdminTransactionsState extends State<AdminTransactions> {
  bool _isLoading = false;
  List<Transaction> _transactions = [];
  String _filterType = 'All';
  String _searchQuery = '';
  String? _selectedStation;
  List<String> _stations = [];
  bool _showAllTransactions = false;
  final int _initialTransactionCount = 10; // Show first 10 transactions by default
  
  // Map to cache usernames
  final Map<String, String> _usernameCache = {};

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  // Helper method to determine if a transaction should be excluded from admin view
  bool _shouldExcludeSystemTransaction(Transaction transaction) {
    final description = transaction.description.toLowerCase();
    
    // Exclude system-generated transactions that clutter the admin view
    if (description.contains('wallet created')) return true;
    if (description.contains('wallet initialized')) return true;
    if (description.contains('system generated')) return true;
    
    // Exclude zero-amount wallet creation transactions
    if (transaction.amount == 0.0 && description.contains('wallet created')) return true;
    
    return false;
  }

  // Helper function declarations needed early
  // Helper function to check if a transaction is a credit transaction (income)
  bool isTransactionCredit(Transaction transaction) {
    return transaction.transactionType == 'credit' && 
           !transaction.description.toLowerCase().contains('deposit');
  }

  // Helper function to check if a transaction is a refund
  bool isTransactionRefund(Transaction transaction) {
    final description = transaction.description.toLowerCase();
    
    // Check if it contains "refund" in description
    if (description.contains('refund')) return true;
    
    // Some refunds might be credits (money going back to user)
    // Check for other refund-related keywords
    if (description.contains('return') || 
        description.contains('reimburs') ||
        description.contains('cancel')) {
      return true;
    }
    
    return false;
  }
  
  // Helper function to check if a transaction is a deposit
  bool isTransactionDeposit(Transaction transaction) {
    return transaction.description.toLowerCase().contains('deposit');
  }
  
  // Helper function to check if a transaction is a payment (debit not refund or deposit)
  bool isTransactionPayment(Transaction transaction) {
    final isDebit = transaction.transactionType == 'debit';
    final isRefund = transaction.description.toLowerCase().contains('refund');
    final isDeposit = transaction.description.toLowerCase().contains('deposit');
    final isFine = transaction.description.toLowerCase().contains('overtime fine');
    
    return isDebit && !isRefund && !isDeposit && !isFine;
  }
  
  // Helper function to check if a transaction is a fine
  bool isTransactionFine(Transaction transaction) {
    final description = transaction.description.toLowerCase();
    
    // Check for various fine-related descriptions
    if (description.contains('overtime fine')) return true;
    if (description.contains('fine for charging')) return true;
    if (description.contains('charging session and fine')) return true;
    if (description.contains('fine via')) return true;
    
    // Also check if the transaction has fine-related data
    if (transaction.fineAmount != null && transaction.fineAmount! > 0) return true;
    if (transaction.overtimeMinutes != null && transaction.overtimeMinutes! > 0) return true;
    
    return false;
  }

  // Helper function to extract station name from transaction description
  String? extractStationName(String description) {
    // Try to extract station name using common patterns
    if (description.contains(' at ')) {
      // Format: "Something at Station Name"
      return description.split(' at ').last.trim();
    } else if (description.contains(' from ')) {
      // Format: "Something from Station Name"
      return description.split(' from ').last.trim();
    } else if (description.contains(' to ')) {
      // Format: "Something to Station Name"
      return description.split(' to ').last.trim();
    }
    return null;
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final adminService = Provider.of<AdminService>(context, listen: false);
      final transactions = await adminService.getAllTransactions();

      // Extract unique station names from transactions more robustly
      final stationSet = <String>{};
      for (var transaction in transactions) {
        final stationName = extractStationName(transaction.description);
        if (stationName != null && stationName.isNotEmpty) {
          stationSet.add(stationName);
        }
      }

      // Preload usernames for all transactions
      await _preloadUsernames(transactions, adminService);

      // Filter out system transactions that shouldn't be shown in admin view
      final filteredTransactions = transactions
          .where((transaction) => !_shouldExcludeSystemTransaction(transaction))
          .toList();

      setState(() {
        _transactions = filteredTransactions;
        _stations = stationSet.toList()..sort();
        _isLoading = false;
      });

      // Debug logging
      print('Original transactions: ${transactions.length}');
      print('Filtered transactions: ${filteredTransactions.length}');
      if (filteredTransactions.length != transactions.length) {
        final excluded = transactions.length - filteredTransactions.length;
        print('Excluded $excluded system transactions from admin view');
      }
    } catch (e) {
      print('Error loading transactions: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Preload usernames for all transactions to avoid individual lookups
  Future<void> _preloadUsernames(
    List<Transaction> transactions,
    AdminService adminService,
  ) async {
    // Get unique user IDs from transactions
    final userIds = transactions.map((t) => t.userId).toSet().toList();

    // Fetch usernames for each unique user ID
    for (final userId in userIds) {
      if (!_usernameCache.containsKey(userId)) {
        final username = await adminService.getUsernameById(userId);
        _usernameCache[userId] = username;
      }
    }
  }

  // Get username from cache or fallback to user ID
  String _getUsernameForDisplay(String userId) {
    return _usernameCache[userId] ?? 'User #$userId';
  }



  List<Transaction> _getFilteredTransactions() {
    print('Filtering ${_transactions.length} transactions with filter: $_filterType');
    
    // Sort transactions by date (newest first)
    _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    final filtered = _transactions.where((transaction) {
      // Filter by type
      if (_filterType != 'All') {
        final isCredit = isTransactionCredit(transaction);
        final isRefund = isTransactionRefund(transaction);
        final isDeposit = isTransactionDeposit(transaction);
        final isPayment = isTransactionPayment(transaction);
        final isFine = isTransactionFine(transaction);
        

        
        switch (_filterType) {
          case 'Revenue':
            if (!isCredit) return false;
            break;
          case 'Payment':
            if (!isPayment) return false;
            break;
          case 'Refund':
            if (!isRefund) return false;
            break;
          case 'Deposit':
            if (!isDeposit) return false;
            break;
          case 'Fine':
            if (!isFine) return false;
            break;
        }
      }
      
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!transaction.description.toLowerCase().contains(query) &&
            !transaction.amount.toString().contains(query) &&
            !transaction.userId.toString().contains(query)) {
          return false;
        }
      }

      // Filter by station
      if (_selectedStation != null && _selectedStation!.isNotEmpty) {
        final stationName = extractStationName(transaction.description);
        if (stationName == null || stationName != _selectedStation) return false;
      }

      return true;
    }).toList();

    print('Filtered result: ${filtered.length} transactions');

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredTransactions = _getFilteredTransactions();
    
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Consistent header
          AppBar(
            title: const Text(
              'Transaction Management',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.indigo[800],
            elevation: 0,
            actions: [],
          ),
          
          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search and filter card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search 
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Search transactions...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Filters row - wrap in SingleChildScrollView to handle overflow
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: _buildFilterDropdown(),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 150,
                                  child: _buildStationFilter(),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _filterType = 'All';
                                      _searchQuery = '';
                                      _selectedStation = null;
                                    });
                                  },
                                  icon: const Icon(Icons.clear, size: 18),
                                  label: const Text('Clear'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    foregroundColor: Colors.black87,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                                    // Transaction stats dashboard
                  _buildTransactionStats(filteredTransactions),
                  
                  const SizedBox(height: 16),
                  
                  // Transaction list header with count and See All button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transactions (${filteredTransactions.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (filteredTransactions.length > _initialTransactionCount)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAllTransactions = !_showAllTransactions;
                            });
                          },
                          icon: Icon(
                            _showAllTransactions
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          label: Text(
                            _showAllTransactions ? 'Show Less' : 'See All',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Transactions list - directly displays the filtered transactions based on the showAll toggle
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredTransactions.isEmpty
                            ? const Center(child: Text('No transactions found'))
                            : _buildTransactionList(
                              _showAllTransactions
                                  ? filteredTransactions
                                  : filteredTransactions
                                      .take(_initialTransactionCount)
                                      .toList(),
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Add resizeToAvoidBottomInset to handle keyboard
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filterType,
          icon: const Icon(Icons.arrow_drop_down),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          borderRadius: BorderRadius.circular(12),
          hint: const Text('Transaction Type'),
          items: ['All', 'Revenue', 'Payment', 'Refund', 'Deposit', 'Fine'].map((String value) {
            IconData icon;
            Color iconColor;
            
            if (value == 'Revenue') {
              icon = Icons.account_balance_wallet;
              iconColor = Colors.green;
            } else if (value == 'Payment') {
              icon = Icons.payment;
              iconColor = Colors.blue;
            } else if (value == 'Refund') {
              icon = Icons.money_off;
              iconColor = Colors.orange;
            } else if (value == 'Deposit') {
              icon = Icons.savings;
              iconColor = Colors.purple;
            } else if (value == 'Fine') {
              icon = Icons.warning;
              iconColor = Colors.red;
            } else {
              icon = Icons.swap_vert;
              iconColor = Colors.indigo;
            }
            
            return DropdownMenuItem<String>(
              value: value,
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const SizedBox(width: 8),
                  Text(value),
                ],
              ),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) {
              setState(() {
                _filterType = newValue;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildStationFilter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStation,
          icon: const Icon(Icons.arrow_drop_down),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          borderRadius: BorderRadius.circular(12),
          hint: Row(
            children: [
              Icon(Icons.ev_station, color: Colors.indigo[700], size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Select Station', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          items: [
            DropdownMenuItem<String>(
              value: '',
              child: Row(
                children: [
                  Icon(
                    Icons.all_inclusive,
                    color: Colors.indigo[700],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'All Stations',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ..._stations.map((String station) {
              return DropdownMenuItem<String>(
                value: station,
                child: Row(
                  children: [
                    Icon(Icons.ev_station, color: Colors.indigo[700], size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        station,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (newValue) {
            setState(() {
              _selectedStation = newValue;
            });
          },
        ),
      ),
    );
  }



  Widget _buildTransactionStats(List<Transaction> transactions) {
    double totalRevenue = 0;
    double totalPayments = 0;
    double totalRefunds = 0;
    double totalDeposits = 0; // Track deposits separately
    double totalFines = 0; // Track fines separately
    double netIncome = 0;
    int transactionCount = 0;
    
    // Debug logging for fine transactions

    
    // Process all transactions to calculate financial metrics
    for (var transaction in transactions) {
      // Count all transactions
      transactionCount++;
      
      final description = transaction.description.toLowerCase();
      final amount = transaction.amount;
      

      
      if (description.contains('deposit')) {
        // User deposits for reservations - temporary holding
        totalDeposits += amount;
        // Don't count in net income (not earned yet)
      } else if (description.contains('refund')) {
        // Money returned to users
        totalRefunds += amount;
        netIncome -= amount; // Reduces net income
      } else if (description.contains('overtime fine') || 
                 description.contains('fine for charging') ||
                 description.contains('charging session and fine') ||
                 description.contains('fine via') ||
                 (transaction.fineAmount != null && transaction.fineAmount! > 0)) {
        // Fines for overtime charging - check multiple patterns
        totalFines += amount;
        netIncome += amount; // Adds to net income
      } else if (description.contains('charging') && !description.contains('deposit')) {
        // Final payment after charging - this is actual revenue
        totalRevenue += amount;
        netIncome += amount;
      } else if (description.contains('top up') || description.contains('topup')) {
        // User wallet top-ups
        totalDeposits += amount;
        // Don't count in net income (not earned yet)
      } else if (transaction.transactionType == 'credit' && !description.contains('deposit')) {
        // Other credit transactions (could be revenue)
        totalRevenue += amount;
        netIncome += amount;
      } else if (transaction.transactionType == 'debit' && !description.contains('refund')) {
        // Other debit transactions (could be payments)
        totalPayments += amount;
        // Don't add to net income (outgoing money)
      }
    }
    

    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide layout for large screens (desktops) - reorganized for better grouping
            if (constraints.maxWidth >= 800) {
              return Row(
                children: [
                  // First group: Core metrics
                  _buildCompactStatIcon(
                    transactionCount.toString(),
                    'Transactions',
                    Icons.receipt_long,
                    Colors.indigo,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalRevenue.toStringAsFixed(2)}',
                    'Revenue',
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                  _buildVerticalDivider(),
                  // Second group: Income sources
                  _buildCompactStatIcon(
                    'RM ${totalPayments.toStringAsFixed(2)}',
                    'Payment',
                    Icons.payment,
                    Colors.blue,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalDeposits.toStringAsFixed(2)}',
                    'Deposit',
                    Icons.savings,
                    Colors.purple,
                  ),
                  _buildVerticalDivider(),
                  // Third group: Deductions
                  _buildCompactStatIcon(
                    'RM ${totalRefunds.toStringAsFixed(2)}',
                    'Refund',
                    Icons.money_off,
                    Colors.orange,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalFines.toStringAsFixed(2)}',
                    'Fine',
                    Icons.warning,
                    Colors.red,
                  ),
                  _buildVerticalDivider(),
                  // Fourth group: Net income
                  _buildCompactStatIcon(
                    'RM ${netIncome.toStringAsFixed(2)}',
                    'Net Income',
                    Icons.assessment,
                    netIncome >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              );
            } 
            // Medium layout for tablets - reorganized for better grouping
            else if (constraints.maxWidth >= 600) {
              return Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  // First row: Core metrics
                  _buildCompactStatIcon(
                    transactionCount.toString(), 
                    'Transactions',
                    Icons.receipt_long,
                    Colors.indigo,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalRevenue.toStringAsFixed(2)}',
                    'Revenue',
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                  // Second row: Income sources
                  _buildCompactStatIcon(
                    'RM ${totalPayments.toStringAsFixed(2)}',
                    'Payment',
                    Icons.payment,
                    Colors.blue,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalDeposits.toStringAsFixed(2)}',
                    'Deposit',
                    Icons.savings,
                    Colors.purple,
                  ),
                  // Third row: Deductions
                  _buildCompactStatIcon(
                    'RM ${totalRefunds.toStringAsFixed(2)}',
                    'Refund',
                    Icons.money_off,
                    Colors.orange,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalFines.toStringAsFixed(2)}',
                    'Fine',
                    Icons.warning,
                    Colors.red,
                  ),
                  // Fourth row: Net income
                  _buildCompactStatIcon(
                    'RM ${netIncome.toStringAsFixed(2)}',
                    'Net Income',
                    Icons.assessment,
                    netIncome >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              );
            } 
            // Most compact layout for phones - reorganized for better grouping
            else {
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  // First row: Core metrics
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      transactionCount.toString(),
                      'Transactions',
                      Icons.receipt_long,
                      Colors.indigo,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalRevenue.toStringAsFixed(2)}',
                      'Revenue',
                      Icons.account_balance_wallet,
                      Colors.green,
                    ),
                  ),
                  // Second row: Income sources
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalPayments.toStringAsFixed(2)}',
                      'Payment',
                      Icons.payment,
                      Colors.blue,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalDeposits.toStringAsFixed(2)}',
                      'Deposit',
                      Icons.savings,
                      Colors.purple,
                    ),
                  ),
                  // Third row: Deductions
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalRefunds.toStringAsFixed(2)}',
                      'Refund',
                      Icons.money_off,
                      Colors.orange,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalFines.toStringAsFixed(2)}',
                      'Fine',
                      Icons.warning,
                      Colors.red,
                    ),
                  ),
                  // Fourth row: Net income (full width)
                  SizedBox(
                    width: constraints.maxWidth * 0.95,
                    child: _buildTinyStatItem(
                      'RM ${netIncome.toStringAsFixed(2)}',
                      'Net Income',
                      Icons.assessment,
                      netIncome >= 0 ? Colors.green : Colors.red,
                      isHighlighted: true,
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
  

  
  // Very compact stat item for small screens
  Widget _buildTinyStatItem(String value, String label, IconData icon, Color color, {bool isHighlighted = false}) {
    return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isHighlighted ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.normal,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Horizontal stat item with icon for medium and large screens
  Widget _buildCompactStatIcon(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(List<Transaction> transactions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a more compact layout for smaller screens
        final isSmallScreen = constraints.maxWidth < 500;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Transaction list header
            if (!isSmallScreen) _buildTransactionListHeader(),
            
            // Transaction list
            Expanded(
              child: ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  return isSmallScreen 
                      ? _buildCompactTransactionCard(transaction)
                      : _buildTransactionCard(transaction);
                },
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildTransactionListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40), // Space for leading icon
          Expanded(
            flex: 4,
            child: Text(
              'Transaction Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Date & Time',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Amount',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    final isCredit = isTransactionCredit(transaction);
    final isRefund = isTransactionRefund(transaction);
    final isFine = isTransactionFine(transaction);
    final isDeposit = isTransactionDeposit(transaction);
    final isPayment = isTransactionPayment(transaction);
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final formattedDate = dateFormat.format(transaction.createdAt);
    
    // Determine transaction type and icon based on current filter selection
    IconData transactionIcon;
    Color iconColor;
    String transactionTypeLabel;
    
    // If a specific filter is selected, use that color theme for consistency
    if (_filterType == 'Fine' && isFine) {
      transactionIcon = Icons.warning;
      iconColor = Colors.red;
      transactionTypeLabel = 'Fine';
    } else if (_filterType == 'Refund' && isRefund) {
      transactionIcon = Icons.money_off;
      iconColor = Colors.orange;
      transactionTypeLabel = 'Refund';
    } else if (_filterType == 'Revenue' && isCredit) {
      transactionIcon = Icons.account_balance_wallet;
      iconColor = Colors.green;
      transactionTypeLabel = 'Revenue';
    } else if (_filterType == 'Deposit' && isDeposit) {
      transactionIcon = Icons.savings;
      iconColor = Colors.purple;
      transactionTypeLabel = 'Deposit';
    } else if (_filterType == 'Payment' && isPayment) {
      transactionIcon = Icons.payment;
      iconColor = Colors.blue;
      transactionTypeLabel = 'Payment';
    } else {
      // Fallback to transaction's inherent type if no specific filter is selected
      if (isRefund) {
        transactionIcon = Icons.money_off;
        iconColor = Colors.orange;
        transactionTypeLabel = 'Refund';
      } else if (isFine) {
        transactionIcon = Icons.warning;
        iconColor = Colors.red;
        transactionTypeLabel = 'Fine';
      } else if (isCredit) {
        transactionIcon = Icons.account_balance_wallet;
        iconColor = Colors.green;
        transactionTypeLabel = 'Revenue';
      } else if (isDeposit) {
        transactionIcon = Icons.savings;
        iconColor = Colors.purple;
        transactionTypeLabel = 'Deposit';
      } else {
        transactionIcon = Icons.payment;
        iconColor = Colors.blue;
        transactionTypeLabel = 'Payment';
      }
    }
    

    
    // Extract transaction type
    String actionType = 'Transaction';
    if (transaction.description.toLowerCase().contains('charging')) {
      actionType = 'Charging';
    } else if (transaction.description.toLowerCase().contains('top up')) {
      actionType = 'Top Up';
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(transaction),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  transactionIcon,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              
              // Transaction details
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Use Row with fixed constraints instead of SingleChildScrollView with Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            transactionTypeLabel,
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                        ),
                          child: Text(
                            actionType,
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _getUsernameForDisplay(transaction.userId),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Date and time
              Expanded(
                flex: 2,
                child: Text(
                  formattedDate,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
              
              // Amount
              Expanded(
                flex: 1,
                child: Text(
                  'RM ${transaction.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTransactionCard(Transaction transaction) {
    final isCredit = isTransactionCredit(transaction);
    final isRefund = isTransactionRefund(transaction);
    final isFine = isTransactionFine(transaction);
    final isDeposit = isTransactionDeposit(transaction);
    final isPayment = isTransactionPayment(transaction);
    final dateFormat = DateFormat('dd MMM yyyy');
    final formattedDate = dateFormat.format(transaction.createdAt);
    
    // Determine transaction type and icon based on current filter selection
    IconData transactionIcon;
    Color iconColor;
    String transactionTypeLabel;
    
    // If a specific filter is selected, use that color theme for consistency
    if (_filterType == 'Fine' && isFine) {
      transactionIcon = Icons.warning;
      iconColor = Colors.red;
      transactionTypeLabel = 'Fine';
    } else if (_filterType == 'Refund' && isRefund) {
      transactionIcon = Icons.money_off;
      iconColor = Colors.orange;
      transactionTypeLabel = 'Refund';
    } else if (_filterType == 'Revenue' && isCredit) {
      transactionIcon = Icons.account_balance_wallet;
      iconColor = Colors.green;
      transactionTypeLabel = 'Revenue';
    } else if (_filterType == 'Deposit' && isDeposit) {
      transactionIcon = Icons.savings;
      iconColor = Colors.purple;
      transactionTypeLabel = 'Deposit';
    } else if (_filterType == 'Payment' && isPayment) {
      transactionIcon = Icons.payment;
      iconColor = Colors.blue;
      transactionTypeLabel = 'Payment';
    } else {
      // Fallback to transaction's inherent type if no specific filter is selected
      if (isRefund) {
        transactionIcon = Icons.money_off;
        iconColor = Colors.orange;
        transactionTypeLabel = 'Refund';
      } else if (isFine) {
        transactionIcon = Icons.warning;
        iconColor = Colors.red;
        transactionTypeLabel = 'Fine';
      } else if (isCredit) {
        transactionIcon = Icons.account_balance_wallet;
        iconColor = Colors.green;
        transactionTypeLabel = 'Revenue';
      } else if (isDeposit) {
        transactionIcon = Icons.savings;
        iconColor = Colors.purple;
        transactionTypeLabel = 'Deposit';
      } else {
        transactionIcon = Icons.payment;
        iconColor = Colors.blue;
        transactionTypeLabel = 'Payment';
      }
    }
    
    // Extract transaction type
    String actionType = 'Transaction';
    if (transaction.description.toLowerCase().contains('charging')) {
      actionType = 'Charging';
    } else if (transaction.description.toLowerCase().contains('top up')) {
      actionType = 'Top Up';
    }
    

    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(transaction),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      transactionIcon,
                      color: iconColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction.description,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row with fixed-size containers instead of Spacer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left side - tags
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transactionTypeLabel,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          actionType,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Right side - amount
                  Text(
                    'RM ${transaction.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Row with fixed alignment instead of Spacer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    _getUsernameForDisplay(transaction.userId),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(Transaction transaction) {
    final isCredit = isTransactionCredit(transaction);
    final isRefund = isTransactionRefund(transaction);
    final isDeposit = isTransactionDeposit(transaction);
    final isPayment = isTransactionPayment(transaction);
    final isFine = isTransactionFine(transaction);
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm:ss');
    final formattedDate = dateFormat.format(transaction.createdAt);
    
    // Determine transaction type
    String transactionTypeLabel;
    Color typeColor;
    IconData typeIcon;
    
    if (isRefund) {
      transactionTypeLabel = 'Refund';
      typeColor = Colors.orange;
      typeIcon = Icons.money_off;
    } else if (isFine) {
      transactionTypeLabel = 'Fine';
      typeColor = Colors.red;
      typeIcon = Icons.warning;
    } else if (isCredit) {
      transactionTypeLabel = 'Revenue';
      typeColor = Colors.green;
      typeIcon = Icons.account_balance_wallet;
    } else if (isDeposit) {
      transactionTypeLabel = 'Deposit';
      typeColor = Colors.purple;
      typeIcon = Icons.savings;
    } else {
      transactionTypeLabel = 'Payment';
      typeColor = Colors.blue;
      typeIcon = Icons.payment;
    }
    
    // Calculate and display system impact
    String systemImpact = '';
    String financialImpact = '';
    
    if (isCredit) {
      systemImpact = 'This transaction represents revenue for the EV charging system.';
      financialImpact = '+RM ${transaction.amount.toStringAsFixed(2)} (income)';
    } else if (isFine) {
      systemImpact = 'This fine was charged for overtime usage of the charging station. It represents additional revenue for the system.';
      financialImpact = '+RM ${transaction.amount.toStringAsFixed(2)} (fine income)';
    } else if (isRefund) {
      // Get refund details
      final refundInfo = extractRefundInfo(transaction);
      final originalAmount = refundInfo['originalAmount'] ?? 0.0;
      final actualRevenue = refundInfo['actualRevenue'] ?? 0.0;
      
      if (actualRevenue > 0) {
        systemImpact = 'Partial refund: Of the original RM ${originalAmount.toStringAsFixed(2)} charge, '
            'RM ${transaction.amount.toStringAsFixed(2)} was refunded to the user. '
            'The system\'s actual revenue is RM ${actualRevenue.toStringAsFixed(2)}.';
        financialImpact = 'Net: RM ${actualRevenue.toStringAsFixed(2)} (after refund)';
      } else {
        systemImpact = 'This refund reduces the system\'s net income. The refunded amount was returned to the user.';
        financialImpact = '-RM ${transaction.amount.toStringAsFixed(2)} (outflow)';
      }
    } else if (isDeposit) {
      systemImpact = 'This is a deposit made by the user before starting a charging session. '
          'It will be applied to the final payment after charging is complete.';
      financialImpact = '±RM ${transaction.amount.toStringAsFixed(2)} (temporary holding)';
    } else if (isPayment) {
      systemImpact = 'This payment represents income from a charging session.';
      financialImpact = '+RM ${transaction.amount.toStringAsFixed(2)} (income)';
    }
    
    // Get the username
    final username = _getUsernameForDisplay(transaction.userId);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              typeIcon,
              color: typeColor,
            ),
            const SizedBox(width: 8),
            Text('Transaction Details'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('ID', transaction.id?.toString() ?? 'N/A'),
            _buildInfoRow('User', username),
            _buildInfoRow('Amount', 'RM ${transaction.amount.toStringAsFixed(2)}'),
            _buildInfoRow('Type', transactionTypeLabel, textColor: typeColor),
            _buildInfoRow('Financial Impact', financialImpact, 
                textColor: typeColor),
            _buildInfoRow('Date', formattedDate),
            _buildInfoRow('Description', transaction.description),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                systemImpact,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to extract refund information from description
  Map<String, double> extractRefundInfo(Transaction transaction) {
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




  // Add back the vertical divider method
  Widget _buildVerticalDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: VerticalDivider(
        color: Colors.grey[300],
        thickness: 1,
        width: 1,
      ),
    );
  }
}

// Add getter to Transaction class if not already present
extension TransactionExtension on Transaction {
  bool get isCredit => transactionType == 'credit';
}