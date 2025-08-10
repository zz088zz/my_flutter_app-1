import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailScreen({Key? key, required this.transaction}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.transactionType == 'credit';
    final amountText = isCredit 
        ? '+ RM ${transaction.amount.toStringAsFixed(2)}'
        : '- RM ${transaction.amount.toStringAsFixed(2)}';
    
    final dateFormat = DateFormat('dd MMMM yyyy, HH:mm');
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
      backgroundColor = isCredit ? Colors.green.shade50 : Colors.red.shade50;
    }
    
    // Check if this is a fine-related transaction
    final bool hasFine = transaction.fineAmount != null && transaction.fineAmount! > 0;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Transaction header card - updated to match the screenshot
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        iconData,
                        color: iconColor,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      amountText,
                      style: TextStyle(
                        color: isCredit ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      transaction.description,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    if (transaction.transactionSource != null) ...[  
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getTransactionSourceLabel(transaction.transactionSource!),
                          style: TextStyle(
                            color: iconColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Transaction details section
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Transaction Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildDetailRow(
                      'Transaction Type', 
                      isCredit ? 'Credit' : 'Debit',
                      valueColor: isCredit ? Colors.green : Colors.red,
                    ),
                    const Divider(height: 20),
                    _buildDetailRow(
                      'Date', 
                      DateFormat('dd MMMM yyyy').format(transaction.createdAt),
                    ),
                    const Divider(height: 20),
                    _buildDetailRow(
                      'Time', 
                      DateFormat('HH:mm:ss').format(transaction.createdAt),
                    ),
                    if (transaction.sessionId != null) ...[  
                      const Divider(height: 20),
                      _buildDetailRow('Session ID', transaction.sessionId!),
                    ],
                    if (transaction.paymentMethodId != null) ...[  
                      const Divider(height: 20),
                      _buildDetailRow('Payment Method ID', transaction.paymentMethodId!),
                    ],
                  ],
                ),
              ),
            ),
            
            // Fine details section (if applicable)
            if (hasFine) ...[  
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Fine Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        'Fine Amount', 
                        'RM ${transaction.fineAmount!.toStringAsFixed(2)}',
                        valueColor: Colors.orange.shade800,
                        valueFontWeight: FontWeight.bold,
                      ),
                      if (transaction.overtimeMinutes != null) ...[  
                        const Divider(height: 20),
                        _buildDetailRow(
                          'Overtime', 
                          '${transaction.overtimeMinutes} minutes',
                          valueColor: Colors.orange.shade700,
                        ),
                      ],
                      if (transaction.gracePeriodMinutes != null) ...[  
                        const Divider(height: 20),
                        _buildDetailRow(
                          'Grace Period', 
                          '${transaction.gracePeriodMinutes} minutes',
                          valueColor: Colors.green,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Removed transaction ID display as per user request
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? valueColor, FontWeight? valueFontWeight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: valueFontWeight ?? FontWeight.w500,
              fontSize: 14,
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