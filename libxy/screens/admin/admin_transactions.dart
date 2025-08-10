import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../services/admin_service.dart';
import 'package:provider/provider.dart';

class AdminTransactions extends StatefulWidget {
  const AdminTransactions({Key? key}) : super(key: key);

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
  final int _initialTransactionCount =
      10; // Show first 10 transactions by default

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
    if (transaction.amount == 0.0 && description.contains('wallet created'))
      return true;

    return false;
  }

  // Helper function declarations needed early
  // Helper function to check if a transaction is a credit transaction (income)
  bool isTransactionCredit(Transaction transaction) {
    return transaction.transactionType == 'credit' &&
        !transaction.description.toLowerCase().contains('deposit') &&
        !transaction.description.toLowerCase().contains('refund');
  }

  // Helper function to check if a transaction is a refund
  bool isTransactionRefund(Transaction transaction) {
    final description = transaction.description.toLowerCase();

    // Check if it contains "refund" in description
    if (description.contains('refund')) {
      return true;
    }

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
    final isFine = transaction.description.toLowerCase().contains(
      'overtime fine',
    );

    return isDebit && !isRefund && !isDeposit && !isFine;
  }

  // Helper function to check if a transaction is a fine
  bool isTransactionFine(Transaction transaction) {
    return transaction.description.toLowerCase().contains('overtime fine');
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
      final filteredTransactions =
          transactions
              .where(
                (transaction) => !_shouldExcludeSystemTransaction(transaction),
              )
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

  List<Transaction> _getFilteredTransactions() {
    print(
      'Filtering ${_transactions.length} transactions with filter: $_filterType',
    );

    final filtered =
        _transactions.where((transaction) {
          // Filter by type
          if (_filterType != 'All') {
            final isCredit = isTransactionCredit(transaction);
            final isRefund = isTransactionRefund(transaction);
            final isDeposit = isTransactionDeposit(transaction);
            final isPayment = isTransactionPayment(transaction);
            final isFine = isTransactionFine(transaction);

            // Debug logging
            if (_filterType == 'Refund') {
              print('Transaction: ${transaction.description}');
              print(
                '  isCredit: $isCredit, isRefund: $isRefund, isDeposit: $isDeposit, isPayment: $isPayment, isFine: $isFine',
              );
            }

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
            if (stationName == null || stationName != _selectedStation)
              return false;
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.indigo[800],
            elevation: 0,
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
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 0,
                                horizontal: 12,
                              ),
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
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

                  // Transaction stats cards
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
                      if (filteredTransactions.length >
                          _initialTransactionCount)
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
                    child:
                        _isLoading
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
          items:
              ['All', 'Revenue', 'Payment', 'Refund', 'Deposit', 'Fine'].map((
                String value,
              ) {
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
            }).toList(),
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

    // Process all transactions to calculate financial metrics
    for (var transaction in transactions) {
      // Count all transactions
      transactionCount++;

      if (isTransactionDeposit(transaction)) {
        // Deposits are tracked separately since they will be deducted when user pays after charging
        totalDeposits += transaction.amount;
        // Don't count deposits in net income until they become actual payments
      } else if (isTransactionCredit(transaction)) {
        // Credit transactions represent revenue to the system
        totalRevenue += transaction.amount;
        netIncome += transaction.amount;
      } else if (isTransactionRefund(transaction)) {
        // Track refunds separately - refunds should NOT be counted as revenue
        totalRefunds += transaction.amount;
        netIncome -= transaction.amount;

        // Note: Refunds are not added to totalRevenue as they represent money returned to customers
        // The original payment that was refunded should have already been counted as revenue when it was made
      } else if (isTransactionFine(transaction)) {
        // Track fines separately - fines represent additional revenue
        totalFines += transaction.amount;
        netIncome += transaction.amount;
      } else if (isTransactionPayment(transaction)) {
        // Regular payments for charging sessions
        totalPayments += transaction.amount;
        netIncome += transaction.amount; // Payments add to our net income
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide layout for large screens (desktops)
            if (constraints.maxWidth >= 800) {
              return Row(
                children: [
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
                  _buildCompactStatIcon(
                    'RM ${totalPayments.toStringAsFixed(2)}',
                    'Payments',
                    Icons.payment,
                    Colors.blue,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalDeposits.toStringAsFixed(2)}',
                    'Deposits',
                    Icons.savings,
                    Colors.purple,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalRefunds.toStringAsFixed(2)}',
                    'Refunds',
                    Icons.money_off,
                    Colors.orange,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${totalFines.toStringAsFixed(2)}',
                    'Fines',
                    Icons.warning,
                    Colors.red,
                  ),
                  _buildVerticalDivider(),
                  _buildCompactStatIcon(
                    'RM ${netIncome.toStringAsFixed(2)}',
                    'Net Income',
                    Icons.assessment,
                    netIncome >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              );
            }
            // Medium layout for tablets
            else if (constraints.maxWidth >= 600) {
              return Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
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
                  _buildCompactStatIcon(
                    'RM ${totalPayments.toStringAsFixed(2)}',
                    'Payments',
                    Icons.payment,
                    Colors.blue,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalDeposits.toStringAsFixed(2)}',
                    'Deposits',
                    Icons.savings,
                    Colors.purple,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalRefunds.toStringAsFixed(2)}',
                    'Refunds',
                    Icons.money_off,
                    Colors.orange,
                  ),
                  _buildCompactStatIcon(
                    'RM ${totalFines.toStringAsFixed(2)}',
                    'Fines',
                    Icons.warning,
                    Colors.red,
                  ),
                  _buildCompactStatIcon(
                    'RM ${netIncome.toStringAsFixed(2)}',
                    'Net Income',
                    Icons.assessment,
                    netIncome >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              );
            }
            // Most compact layout for phones
            else {
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
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
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalPayments.toStringAsFixed(2)}',
                      'Payments',
                      Icons.payment,
                      Colors.blue,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalDeposits.toStringAsFixed(2)}',
                      'Deposits',
                      Icons.savings,
                      Colors.purple,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalRefunds.toStringAsFixed(2)}',
                      'Refunds',
                      Icons.money_off,
                      Colors.orange,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth * 0.45,
                    child: _buildTinyStatItem(
                      'RM ${totalFines.toStringAsFixed(2)}',
                      'Fines',
                      Icons.warning,
                      Colors.red,
                    ),
                  ),
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
  Widget _buildTinyStatItem(
    String value,
    String label,
    IconData icon,
    Color color, {
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
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
  Widget _buildCompactStatIcon(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Expanded(
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
      },
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
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final formattedDate = dateFormat.format(transaction.createdAt);

    // Determine transaction type and icon - prioritize refunds first
    IconData transactionIcon;
    Color iconColor;
    String transactionTypeLabel;

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
    } else {
      transactionIcon = Icons.payment;
      iconColor = Colors.blue;
      transactionTypeLabel = 'Payment';
    }

    // Extract station name if available
    String stationName = 'Unknown Station';
    final extractedStationName = extractStationName(transaction.description);
    if (extractedStationName != null) {
      stationName = extractedStationName;
    }

    // Extract transaction type for action label
    String actionType = 'Transaction';
    if (transaction.description.toLowerCase().contains('charging')) {
      actionType = 'Charging';
    } else if (transaction.description.toLowerCase().contains('refund')) {
      actionType = 'Refund';
    } else if (transaction.description.toLowerCase().contains('top up')) {
      actionType = 'Top Up';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(transactionIcon, color: iconColor),
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
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Use Row with fixed constraints instead of SingleChildScrollView with Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.1),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
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
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
    final dateFormat = DateFormat('dd MMM yyyy');
    final formattedDate = dateFormat.format(transaction.createdAt);

    // Determine transaction type and icon - prioritize refunds first
    IconData transactionIcon;
    Color iconColor;
    String transactionTypeLabel;

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
    } else {
      transactionIcon = Icons.payment;
      iconColor = Colors.blue;
      transactionTypeLabel = 'Payment';
    }

    // Extract transaction type for action label
    String actionType = 'Transaction';
    if (transaction.description.toLowerCase().contains('charging')) {
      actionType = 'Charging';
    } else if (transaction.description.toLowerCase().contains('refund')) {
      actionType = 'Refund';
    } else if (transaction.description.toLowerCase().contains('top up')) {
      actionType = 'Top Up';
    }

    // Extract station name if available
    String? stationName = extractStationName(transaction.description);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(transactionIcon, color: iconColor, size: 16),
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
                        if (stationName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              stationName,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.1),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
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
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  Text(
                    _getUsernameForDisplay(transaction.userId),
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
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

    if (isCredit) {
      transactionTypeLabel = 'Revenue';
      typeColor = Colors.green;
      typeIcon = Icons.account_balance_wallet;
    } else if (isRefund) {
      transactionTypeLabel = 'Refund';
      typeColor = Colors.orange;
      typeIcon = Icons.money_off;
    } else if (isFine) {
      transactionTypeLabel = 'Fine';
      typeColor = Colors.red;
      typeIcon = Icons.warning;
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
      systemImpact =
          'This transaction represents revenue for the EV charging system.';
      financialImpact = '+RM ${transaction.amount.toStringAsFixed(2)} (income)';
    } else if (isRefund) {
      systemImpact =
          'This refund reduces the system\'s net income. The refunded amount was returned to the user.';
      financialImpact =
          '-RM ${transaction.amount.toStringAsFixed(2)} (outflow)';
    } else if (isFine) {
      systemImpact =
          'This fine was charged for overtime usage of the charging station. It represents additional revenue for the system.';
      financialImpact =
          '+RM ${transaction.amount.toStringAsFixed(2)} (fine income)';
    } else if (isDeposit) {
      systemImpact =
          'This is a deposit made by the user before starting a charging session. '
          'It will be applied to the final payment after charging is complete.';
      financialImpact =
          '±RM ${transaction.amount.toStringAsFixed(2)} (temporary holding)';
    } else if (isPayment) {
      systemImpact = 'This payment represents income from a charging session.';
      financialImpact = '+RM ${transaction.amount.toStringAsFixed(2)} (income)';
    }

    // Get the username
    final username = _getUsernameForDisplay(transaction.userId);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(typeIcon, color: typeColor),
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
                _buildInfoRow(
                  'Amount',
                  'RM ${transaction.amount.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Type',
                  transactionTypeLabel,
                  textColor: typeColor,
                ),
                _buildInfoRow(
                  'Financial Impact',
                  financialImpact,
                  textColor: typeColor,
                ),
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, style: TextStyle(color: textColor))),
        ],
      ),
    );
  }

  // Note: extractRefundInfo function removed as refunds are no longer counted as revenue

  // Creates a stat item that takes full width of container
  Widget _buildStatItemFullWidth(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add back the vertical divider method
  Widget _buildVerticalDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: VerticalDivider(color: Colors.grey[300], thickness: 1, width: 1),
    );
  }
}

// Add getter to Transaction class if not already present
extension TransactionExtension on Transaction {
  bool get isCredit => transactionType == 'credit';
}
