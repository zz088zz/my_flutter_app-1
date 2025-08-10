import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/transaction_history_service.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import 'transaction_detail_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isLoading = true;
  String? _error;


  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final transactionHistoryService = Provider.of<TransactionHistoryService>(context, listen: false);
      
      final userId = authService.currentUser?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      print('Transaction History Screen - Loading ALL transactions for user: $userId');

      // Load ALL transactions (wallet, credit cards, Apple Pay, charging sessions)
      await transactionHistoryService.loadAllUserTransactions(userId);
      
      if (!mounted) return;
      
      print('Loaded ${transactionHistoryService.allTransactions.length} total transactions for user $userId');
      
    } catch (e) {
      print('Error loading transactions: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load transactions. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTransactions,
              child: Consumer<TransactionHistoryService>(
                builder: (context, transactionHistoryService, child) {
                  if (_error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadTransactions,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    );
                  }

                  // Filter out charging session transactions
                  final transactions = transactionHistoryService.allTransactions
                    .where((transaction) => transaction.transactionSource != 'charging_session')
                    .toList();
                  
                  if (transactions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions yet',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your transaction history will appear here',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return Column(
                    children: [
                      // Transaction count summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        margin: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${transactions.length} transaction${transactions.length == 1 ? '' : 's'} found',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                      // Transactions list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final transaction = transactions[index];
                            return _buildTransactionItem(transaction);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isCredit = transaction.transactionType == 'credit';
    final amountText = isCredit 
        ? '+ RM ${transaction.amount.toStringAsFixed(2)}'
        : '- RM ${transaction.amount.toStringAsFixed(2)}';
    
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final formattedDate = dateFormat.format(transaction.createdAt);
    
    // Determine icon and color based on transaction source and type
    IconData iconData;
    Color iconColor;
    Color backgroundColor;
    
    if (transaction.transactionSource == 'payment_method') {
      // Credit card payment
      iconData = Icons.credit_card;
      iconColor = Colors.blue;
      backgroundColor = Colors.blue.shade100;
    } else if (transaction.transactionSource == 'apple_pay') {
      // Apple Pay payment
      iconData = Icons.apple;
      iconColor = Colors.black;
      backgroundColor = Colors.grey.shade100;
    } else if (transaction.transactionSource == 'charging_session') {
      // Charging session
      iconData = Icons.ev_station;
      iconColor = Colors.orange;
      backgroundColor = Colors.orange.shade100;
    } else {
      // Wallet transaction (default)
      iconData = isCredit ? Icons.account_balance_wallet : Icons.payment;
      iconColor = isCredit ? Colors.green : Colors.red;
      backgroundColor = isCredit ? Colors.green.shade100 : Colors.red.shade100;
    }
    
    // Check if this is a fine-related transaction
    final bool hasFine = transaction.fineAmount != null && transaction.fineAmount! > 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            iconData,
            color: iconColor,
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedDate,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (transaction.transactionSource != null)
              Text(
                _getTransactionSourceLabel(transaction.transactionSource!),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            if (hasFine)
              Text(
                'Includes fine',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              amountText,
              style: TextStyle(
                color: isCredit ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransactionDetailScreen(transaction: transaction),
                  ),
                );
              },
            ),
          ],
        ),
        children: [
          // Additional details section
          if (hasFine) ...[  
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Text(
                    'Fine Details:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fine Amount:', style: TextStyle(color: Colors.grey[600])),
                      Text('RM ${transaction.fineAmount!.toStringAsFixed(2)}', 
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (transaction.overtimeMinutes != null) ...[  
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Overtime:', style: TextStyle(color: Colors.grey[600])),
                        Text('${transaction.overtimeMinutes} minutes', 
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                  if (transaction.gracePeriodMinutes != null) ...[  
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Grace Period:', style: TextStyle(color: Colors.grey[600])),
                        Text('${transaction.gracePeriodMinutes} minutes', 
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Session ID if available
          if (transaction.sessionId != null) ...[  
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Session ID:', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  Text(transaction.sessionId!, 
                    style: TextStyle(fontSize: 12, color: Colors.grey[800])),
                ],
              ),
            ),
          ],
          
          // View Details button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransactionDetailScreen(transaction: transaction),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('View Full Details'),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getTransactionSourceLabel(String source) {
    switch (source) {
      case 'wallet':
        return 'E-Wallet';
      case 'payment_method':
        return 'Credit Card';
      case 'apple_pay':
        return 'Apple Pay';
      case 'charging_session':
        return 'Charging Session';
      default:
        return 'Transaction';
    }
  }
}