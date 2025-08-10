import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../models/transaction.dart';
import 'package:intl/intl.dart';
import 'transaction_history_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final walletService = Provider.of<WalletService>(context, listen: false);
      final paymentService = Provider.of<PaymentService>(
        context,
        listen: false,
      );

      // Always use the actual logged-in user's ID as a string
      final userId = authService.currentUser?.id;
      if (userId == null) {
        throw Exception('No logged-in user');
      }
      // Load wallet data (this also loads transactions)
      await walletService.loadWalletForUser(userId);
      // Load payment methods
      await paymentService.loadUserPaymentMethods(userId);
    } catch (e) {
      print('Error loading wallet data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading wallet data')),
        );
      }
    }
  }

  Future<void> _topUpWallet(double amount) async {
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final walletService = Provider.of<WalletService>(context, listen: false);

      // Get user ID and ensure user is logged in
      final userId = authService.currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to top up your wallet')),
        );
        return;
      }

      // Top up wallet
      final success = await walletService.topUpWallet(
        userId,
        amount,
        'Manual top-up',
      );

      if (success) {
        // Clear the text field
        _amountController.clear();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully added RM ${amount.toStringAsFixed(2)} to your wallet',
              ),
            ),
          );

          // Refresh transactions after successful top-up
          await walletService.refreshTransactions();
        }
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to top up wallet')),
          );
        }
      }
    } catch (e) {
      print('Error topping up wallet: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('An error occurred')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletService = Provider.of<WalletService>(context);

    // Format wallet balance
    final formattedBalance = 'RM ${walletService.balance.toStringAsFixed(2)}';

    // Get only recent transactions (maximum 5)
    final recentTransactions = walletService.getRecentTransactions(5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body:
          walletService.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadWalletData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Balance card
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
                              const Text(
                                'Current Balance',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                formattedBalance,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          () => _showTopUpDialog(context),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Top Up'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Theme.of(context).primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Transaction history with See All button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Transaction History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) =>
                                          const TransactionHistoryScreen(),
                                ),
                              );
                            },
                            child: const Text('See All'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      recentTransactions.isEmpty
                          ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Text(
                                'No transactions yet',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          )
                          : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: recentTransactions.length,
                            itemBuilder: (context, index) {
                              final transaction = recentTransactions[index];
                              return _buildTransactionItem(transaction);
                            },
                          ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isCredit = transaction.transactionType == 'credit';
    final amountText =
        isCredit
            ? '+ RM ${transaction.amount.toStringAsFixed(2)}'
            : '- RM ${transaction.amount.toStringAsFixed(2)}';

    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final formattedDate = dateFormat.format(transaction.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCredit ? Colors.green.shade100 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isCredit ? Icons.add : Icons.remove,
            color: isCredit ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          formattedDate,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Text(
          amountText,
          style: TextStyle(
            color: isCredit ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _showTopUpDialog(BuildContext context) {
    String _selectedPaymentMethod = 'card';
    String? _selectedCardId;
    bool _cardsExpanded = true;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              final paymentService = Provider.of<PaymentService>(context);
              final paymentMethods = paymentService.paymentMethods;

              return AlertDialog(
                title: const Text('Top Up Wallet'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount (RM)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Select Payment Method',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      // Saved Cards
                      Column(
                        children: [
                          if (paymentMethods.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Text(
                                'No saved cards. Add cards in your account settings.',
                              ),
                            )
                          else
                            ...paymentMethods.map((method) {
                              return RadioListTile(
                                title: Text(
                                  '${method.cardType} ${method.maskedCardNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text('Expires ${method.expiryDate}'),
                                value: method.id,
                                groupValue: _selectedCardId,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCardId = value as String;
                                    _selectedPaymentMethod = 'card';
                                  });
                                },
                              );
                            }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed:
                        _selectedCardId == null
                            ? null
                            : () {
                              final amount = double.tryParse(
                                _amountController.text,
                              );
                              if (amount != null && amount > 0) {
                                Navigator.pop(context);
                                _topUpWallet(amount);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please enter a valid amount',
                                    ),
                                  ),
                                );
                              }
                            },
                    child: const Text('TOP UP'),
                  ),
                ],
              );
            },
          ),
    );
  }
}
