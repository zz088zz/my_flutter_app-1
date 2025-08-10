import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/payment_service.dart';
import '../services/auth_service.dart';
import '../models/payment_method.dart';

class PaymentMethodManagementScreen extends StatefulWidget {
  const PaymentMethodManagementScreen({Key? key}) : super(key: key);

  @override
  State<PaymentMethodManagementScreen> createState() => _PaymentMethodManagementScreenState();
}

class _PaymentMethodManagementScreenState extends State<PaymentMethodManagementScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final paymentService = Provider.of<PaymentService>(context, listen: false);

    // Ensure user is logged in
    if (authService.currentUser == null) {
      // Redirect to login screen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to manage your payment methods')),
        );
        Navigator.pop(context);
      }
      return;
    }

    // Load payment methods for logged in user
    await paymentService.loadUserPaymentMethods(authService.currentUser!.id!);

    setState(() {
      _isLoading = false;
    });
  }

  void _showAddCardDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const AddCardBottomSheet(),
    ).then((value) {
      // Refresh payment methods list
      _loadPaymentMethods();
    });
  }

  void _showCardOptions(PaymentMethod method) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!method.isDefault)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Set as Default'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _setAsDefault(method.id!);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit Card', style: TextStyle(color: Colors.blue)),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCardDialog(method);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Card', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  _showDeleteConfirmation(method.id!);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(String cardId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Are you sure you want to remove this card?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteCard(cardId);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showEditCardDialog(PaymentMethod method) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => EditCardBottomSheet(method: method),
    ).then((value) {
      if (value == true) {
        _loadPaymentMethods();
      }
    });
  }

  Future<void> _setAsDefault(String cardId) async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final paymentService = Provider.of<PaymentService>(context, listen: false);

    try {
      // Ensure user is logged in
      if (authService.currentUser == null) {
        throw Exception('User must be logged in to set default payment method');
      }
      
      final String userId = authService.currentUser!.id!;
      
      final success = await paymentService.setDefaultPaymentMethod(cardId, userId);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Default payment method updated')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update default payment method')),
          );
        }
      }
    } catch (e) {
      print('Error setting default payment method: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteCard(String cardId) async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final paymentService = Provider.of<PaymentService>(context, listen: false);

    try {
      // Ensure user is logged in
      if (authService.currentUser == null) {
        throw Exception('User must be logged in to delete payment method');
      }
      
      final String userId = authService.currentUser!.id!;
      
      final success = await paymentService.deletePaymentMethod(cardId, userId);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Card removed successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove card')),
          );
        }
      }
    } catch (e) {
      print('Error deleting payment method: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add new method to clear all payment methods
  Future<void> _clearAllCards() async {
    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final paymentService = Provider.of<PaymentService>(context, listen: false);

    try {
      // Ensure user is logged in
      if (authService.currentUser == null) {
        throw Exception('User must be logged in to manage payment methods');
      }
      
      // Get user ID
      final String userId = authService.currentUser!.id!;
      
      // Show confirmation dialog
      bool? confirmDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear All Cards'),
          content: const Text('Are you sure you want to remove all payment methods? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CLEAR ALL'),
            ),
          ],
        ),
      );
      
      if (confirmDelete != true) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      final success = await paymentService.clearAllPaymentMethods(userId);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All payment methods have been removed')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove all payment methods')),
          );
        }
      }
    } catch (e) {
      print('Error clearing payment methods: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      
      // Refresh payment methods list regardless of success
      _loadPaymentMethods();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Consumer<PaymentService>(
            builder: (context, paymentService, _) {
              // Only show clear all button if there are payment methods
              if (paymentService.paymentMethods.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Clear all cards',
                  onPressed: _clearAllCards,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<PaymentService>(
              builder: (context, paymentService, child) {
                // Sort payment methods to show default card at the top
                final paymentMethods = List<PaymentMethod>.from(paymentService.paymentMethods)
                  ..sort((a, b) => a.isDefault ? -1 : (b.isDefault ? 1 : 0));

                return paymentMethods.isEmpty
                          ? const Center(
                              child: Text(
                                'No payment methods added yet.\nTap the button below to add one.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: paymentMethods.length,
                              itemBuilder: (context, index) {
                                final method = paymentMethods[index];
                                return _buildPaymentMethodCard(method);
                              },
                            );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCardDialog,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildPaymentMethodCard(PaymentMethod method) {
    Widget cardLogo;
    
    if (method.cardType.toLowerCase().contains('visa')) {
      cardLogo = Container(
        width: 45,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.blue.shade900,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text(
            'VISA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else if (method.cardType.toLowerCase().contains('mastercard')) {
      cardLogo = Container(
        width: 45,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.orange.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text(
            'MC',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else {
      cardLogo = Container(
        width: 45,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(
            Icons.credit_card,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: method.isDefault
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showCardOptions(method),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              cardLogo,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${method.cardType} ${method.maskedCardNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expires ${method.expiryDate}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (method.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Default',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddCardBottomSheet extends StatefulWidget {
  const AddCardBottomSheet({Key? key}) : super(key: key);

  @override
  State<AddCardBottomSheet> createState() => _AddCardBottomSheetState();
}

class _AddCardBottomSheetState extends State<AddCardBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardholderNameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _cvvController = TextEditingController();
  bool _isDefault = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _cardholderNameController.dispose();
    _cardNumberController.dispose();
    _expiryDateController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  String _detectCardType(String cardNumber) {
    // Enhanced card type detection with better regex patterns
    cardNumber = cardNumber.replaceAll(' ', '');
    if (cardNumber.isEmpty) return 'Unknown';
    
    // Visa: Starts with 4
    if (RegExp(r'^4[0-9]{12}(?:[0-9]{3})?$').hasMatch(cardNumber)) {
      return 'Visa';
    } 
    // Mastercard: Starts with 51-55 or 2221-2720
    else if (RegExp(r'^5[1-5][0-9]{14}$').hasMatch(cardNumber) || 
             RegExp(r'^2(?:2(?:2[1-9]|[3-9][0-9])|[3-6][0-9][0-9]|7(?:[01][0-9]|20))[0-9]{12}$').hasMatch(cardNumber)) {
      return 'Mastercard';
    } 
    // American Express: Starts with 34 or 37
    else if (RegExp(r'^3[47][0-9]{13}$').hasMatch(cardNumber)) {
      return 'American Express';
    } 
    // Discover: Starts with 6011, 644-649, 65
    else if (RegExp(r'^6(?:011|5[0-9]{2})[0-9]{12}$').hasMatch(cardNumber) || 
             RegExp(r'^64[4-9][0-9]{13}$').hasMatch(cardNumber)) {
      return 'Discover';
    }
    
    return 'Unknown';
  }

  String _formatCardNumber(String text) {
    if (text.isEmpty) return '';
    
    // Remove all non-digit characters
    text = text.replaceAll(RegExp(r'\D'), '');
    
    // Limit to 16 digits (most common card length)
    if (text.length > 16) {
      text = text.substring(0, 16);
    }
    
    // Format with spaces
    List<String> chunks = [];
    for (int i = 0; i < text.length; i += 4) {
      int end = i + 4;
      if (end > text.length) end = text.length;
      chunks.add(text.substring(i, end));
    }
    
    return chunks.join(' ');
  }

  // Helper method to format expiry date
  String _formatExpiryDate(String text) {
    // Remove any existing slashes
    text = text.replaceAll('/', '');
    
    // Limit to 4 digits
    if (text.length > 4) {
      text = text.substring(0, 4);
    }
    
    // Add slash after 2 digits
    if (text.length >= 2) {
      return '${text.substring(0, 2)}/${text.substring(2)}';
    }
    
    return text;
  }

  // Helper method to determine card type

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Clean up and format card data before submission
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    final expiryDate = _expiryDateController.text;
    final holderName = _cardholderNameController.text.trim();
    final cvv = _cvvController.text.trim();
    final cardType = _detectCardType(cardNumber);

    // Additional validation before submission
    if (!_validateCardBeforeSubmission()) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final paymentService = Provider.of<PaymentService>(context, listen: false);
      
      // Ensure we have a user ID
      final String userId = authService.currentUser?.id ?? '1';
      
      print('Preparing to add payment method for user $userId');
      print('Card details: $cardType, $expiryDate, ${cardNumber.substring(0, 4)}...');
      
      final newPaymentMethod = PaymentMethod(
        userId: userId,
        cardType: cardType,
        cardNumber: cardNumber,
        expiryDate: expiryDate,
        holderName: holderName,
        isDefault: _isDefault,
        lastFourDigits: cardNumber.substring(cardNumber.length - 4),
      );
      
      final result = await paymentService.addPaymentMethod(newPaymentMethod);
      
      if (result != null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card added successfully')),
        );
      } else {
        throw Exception('Failed to add card');
      }
    } catch (e) {
      print('Error adding card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add card. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Additional validation method for card details
  bool _validateCardBeforeSubmission() {
    final cardNumber = _cardNumberController.text.replaceAll(' ', '');
    final expiryDate = _expiryDateController.text;
    final cvv = _cvvController.text;
    final holderName = _cardholderNameController.text.trim();

    // Check if all fields are filled
    if (cardNumber.isEmpty || expiryDate.isEmpty || cvv.isEmpty || holderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return false;
    }

    // Check for duplicate card number
    final existingCards = context.read<PaymentService>().paymentMethods;
    final isDuplicate = existingCards.any((card) => 
      card.cardNumber.replaceAll(' ', '') == cardNumber
    );
    
    if (isDuplicate) {
      // Show dialog instead of SnackBar for better visibility
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Duplicate Card'),
            content: const Text('This card is already saved in your account.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return false;
    }

    // Validate card number length
    if (cardNumber.length < 13 || cardNumber.length > 19) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid card number length')),
      );
      return false;
    }

    // Validate card number using Luhn algorithm
    if (!_passesLuhnCheck(cardNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid card number')),
      );
      return false;
    }

    // Validate expiry date format
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(expiryDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter expiry date in MM/YY format')),
      );
      return false;
    }

    // Validate expiry date is not in the past
    final parts = expiryDate.split('/');
    try {
      final month = int.parse(parts[0]);
      final year = int.parse(parts[1]);
      final now = DateTime.now();
      final currentYear = now.year % 100;
      final currentMonth = now.month;

      if (month < 1 || month > 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid month (01-12)')),
        );
        return false;
      }

      if (year < currentYear || (year == currentYear && month < currentMonth)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card has expired. Please enter a valid expiry date')),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid expiry date')),
      );
      return false;
    }

    // Validate CVV
    if (cvv.length < 3 || cvv.length > 4 || !RegExp(r'^\d{3,4}$').hasMatch(cvv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CVV must be 3-4 digits')),
      );
      return false;
    }

    // Validate cardholder name
    if (holderName.length < 3 || !RegExp(r'^[A-Za-z\s]+$').hasMatch(holderName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid cardholder name')),
      );
      return false;
    }

    return true;
  }

  // Implement Luhn algorithm for card number validation
  bool _passesLuhnCheck(String cardNumber) {
    int sum = 0;
    bool alternate = false;
    
    // Process from right to left
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  void _showExpiryDatePicker(BuildContext context) {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;
    
    int selectedMonth = currentMonth;
    int selectedYear = currentYear;
    
    // If there's already a value, parse it
    if (_expiryDateController.text.isNotEmpty) {
      final parts = _expiryDateController.text.split('/');
      if (parts.length == 2) {
        selectedMonth = int.tryParse(parts[0]) ?? currentMonth;
        selectedYear = 2000 + (int.tryParse(parts[1]) ?? (currentYear % 100));
      }
    }
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Select Expiry Date',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: Container(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    // Month Selection
                    const Text(
                      'Month',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final isSelected = month == selectedMonth;
                          final monthNames = [
                            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                          ];
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedMonth = month;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Theme.of(context).primaryColor 
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected 
                                      ? Theme.of(context).primaryColor 
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  monthNames[index],
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Year Selection
                    const Text(
                      'Year',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          childAspectRatio: 1.5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: 15, // Show next 15 years
                        itemBuilder: (context, index) {
                          final year = currentYear + index;
                          final isSelected = year == selectedYear;
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedYear = year;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Theme.of(context).primaryColor 
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected 
                                      ? Theme.of(context).primaryColor 
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  (year % 100).toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validate the selected date
                    if (selectedYear < currentYear || 
                        (selectedYear == currentYear && selectedMonth < currentMonth)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a future date'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    // Format and set the date
                    final formattedDate = '${selectedMonth.toString().padLeft(2, '0')}/${(selectedYear % 100).toString().padLeft(2, '0')}';
                    _expiryDateController.text = formattedDate;
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: const Text(
                    'Select',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add New Card',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Card Holder\'s Name',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cardholderNameController,
                  decoration: InputDecoration(
                    hintText: 'Name on card',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the cardholder\'s name';
                    }
                    if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(value)) {
                      return 'Name should contain only letters';
                    }
                    if (value.length < 3) {
                      return 'Name is too short';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Card Number',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cardNumberController,
                  decoration: InputDecoration(
                    hintText: '1234 5678 9012 3456',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.credit_card,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final formatted = _formatCardNumber(value);
                    if (formatted != value) {
                      _cardNumberController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the card number';
                    }
                    
                    final cardNumber = value.replaceAll(' ', '');
                    
                    // Check length
                    if (cardNumber.length < 13 || cardNumber.length > 19) {
                      return 'Card number should be 13-19 digits';
                    }
                    
                    // Check if all characters are digits
                    if (!RegExp(r'^\d+$').hasMatch(cardNumber)) {
                      return 'Card number should contain only digits';
                    }
                    
                    // Luhn algorithm check
                    if (!_passesLuhnCheck(cardNumber)) {
                      return 'Invalid card number';
                    }
                    
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Row for Expiry Date and CVV fields
                Row(
                  children: [
                    // Expiry Date Field
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expiry Date',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _expiryDateController,
                            decoration: InputDecoration(
                              hintText: 'MM/YY',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () => _showExpiryDatePicker(context),
                                tooltip: 'Select date',
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final formatted = _formatExpiryDate(value);
                              if (formatted != value) {
                                _expiryDateController.value = TextEditingValue(
                                  text: formatted,
                                  selection: TextSelection.collapsed(offset: formatted.length),
                                );
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
                                return 'Use MM/YY format';
                              }
                              
                              // Check validity
                              final parts = value.split('/');
                              try {
                                final month = int.parse(parts[0]);
                                final year = int.parse(parts[1]);
                                final now = DateTime.now();
                                final currentYear = now.year % 100;
                                final currentMonth = now.month;
                                
                                if (month < 1 || month > 12) {
                                  return 'Invalid month';
                                }
                                
                                if (year < currentYear || (year == currentYear && month < currentMonth)) {
                                  return 'Card expired';
                                }
                              } catch (e) {
                                return 'Invalid date';
                              }
                              
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16), // Space between fields
                    // CVV Field
                    Expanded(
                      child: TextFormField(
                        controller: _cvvController,
                        decoration: InputDecoration(
                          labelText: 'CVV',
                          hintText: '123',
                          border: OutlineInputBorder(),
                          counterText: '', // Hide the default counter if not needed
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter CVV';
                          }
                          if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
                            return 'CVV is 3-4 digits';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                // Helper text for CVV in a new row
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0, right: 4.0),
                    child: Text(
                      'Last 3-4 digits on back',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Checkbox
                Row(
                  children: [
                    Checkbox(
                      value: _isDefault,
                      onChanged: (value) {
                        setState(() {
                          _isDefault = value ?? false;
                        });
                      },
                      activeColor: Theme.of(context).primaryColor,
                    ),
                    const Text('Set as default payment method'),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: Colors.grey,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Add Card',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EditCardBottomSheet extends StatefulWidget {
  final PaymentMethod method;

  const EditCardBottomSheet({
    Key? key,
    required this.method,
  }) : super(key: key);

  @override
  State<EditCardBottomSheet> createState() => _EditCardBottomSheetState();
}

class _EditCardBottomSheetState extends State<EditCardBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryDateController = TextEditingController();
  final _cardHolderController = TextEditingController();
  
  String _selectedCardType = 'Visa';
  bool _isDefault = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    _selectedCardType = widget.method.cardType;
    _cardNumberController.text = widget.method.cardNumber;
    _formatCardNumber();
    _expiryDateController.text = widget.method.expiryDate;
    _cardHolderController.text = widget.method.holderName;
    _isDefault = widget.method.isDefault;
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryDateController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }

  void _formatCardNumber() {
    var text = _cardNumberController.text.replaceAll(' ', '');
    
    if (text.length > 16) {
      text = text.substring(0, 16);
    }
    
    // Format with spaces
    final chunks = <String>[];
    for (var i = 0; i < text.length; i += 4) {
      final end = i + 4 < text.length ? i + 4 : text.length;
      chunks.add(text.substring(i, end));
    }
    
    final formatted = chunks.join(' ');
    
    if (formatted != _cardNumberController.text) {
      _cardNumberController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _formatExpiryDate(String value) {
    var text = value.replaceAll('/', '');
    
    if (text.length > 4) {
      text = text.substring(0, 4);
    }
    
    if (text.length >= 2) {
      text = '${text.substring(0, 2)}/${text.substring(2)}';
    }
    
    if (text != _expiryDateController.text) {
      _expiryDateController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  // Implementation of Luhn algorithm for card number validation
  bool _passesLuhnCheck(String cardNumber) {
    int sum = 0;
    bool alternate = false;
    
    // Process from right to left
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  // Additional validation method for card details
  bool _validateCardBeforeSubmission(String cardNumber, String expiryDate, String holderName) {
    // Validate card number (should be 13-19 digits depending on card type)
    if (cardNumber.length < 13 || cardNumber.length > 19) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid card number length')),
      );
      return false;
    }

    // Luhn algorithm check (card number checksum)
    if (!_passesLuhnCheck(cardNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid card number')),
      );
      return false;
    }

    // Validate expiry date format
    final parts = expiryDate.split('/');
    if (parts.length != 2 || parts[0].length != 2 || parts[1].length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid expiry date format (MM/YY)')),
      );
      return false;
    }

    try {
      final month = int.parse(parts[0]);
      final year = int.parse(parts[1]);
      final now = DateTime.now();
      final currentYear = now.year % 100; // Get last two digits of year
      final currentMonth = now.month;

      // Check if the expiry date is in the past
      if (year < currentYear || (year == currentYear && month < currentMonth)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card has expired')),
        );
        return false;
      }

      // Check for valid month
      if (month < 1 || month > 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid month (1-12)')),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid expiry date')),
      );
      return false;
    }

    // Validate CVV (3-4 digits)
    if (holderName.length < 3 || !RegExp(r'^[A-Za-z\s]+$').hasMatch(holderName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid cardholder name')),
      );
      return false;
    }

    return true;
  }

  Future<void> _updatePaymentMethod() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Clean up and format card data
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final expiryDate = _expiryDateController.text;
      final holderName = _cardHolderController.text.trim();
      
      // Additional validation before submission
      if (!_validateCardBeforeSubmission(cardNumber, expiryDate, holderName)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Get services
      final paymentService = Provider.of<PaymentService>(context, listen: false);
      
      // Create updated payment method object
      final updatedMethod = PaymentMethod(
        id: widget.method.id,
        userId: widget.method.userId,
        cardType: _selectedCardType,
        cardNumber: cardNumber,
        expiryDate: expiryDate,
        holderName: holderName,
        isDefault: _isDefault,
        lastFourDigits: cardNumber.substring(cardNumber.length - 4),
      );
      
      print('Updating payment method ${updatedMethod.id} with card type: ${updatedMethod.cardType}');
      
      // Update in database
      final result = await paymentService.updatePaymentMethod(updatedMethod);
      
      if (result) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card updated successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update card')),
        );
      }
    } catch (e) {
      print('Error updating card: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Card',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Card Type Dropdown
            DropdownButtonFormField<String>(
              value: _selectedCardType,
              decoration: const InputDecoration(
                labelText: 'Card Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Visa', child: Text('Visa')),
                DropdownMenuItem(value: 'Mastercard', child: Text('Mastercard')),
                DropdownMenuItem(value: 'American Express', child: Text('American Express')),
                DropdownMenuItem(value: 'Discover', child: Text('Discover')),
                DropdownMenuItem(value: 'Unknown', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCardType = value;
                  });
                }
              },
              validator: (value) => value == null ? 'Please select a card type' : null,
            ),
            const SizedBox(height: 16),
            
            // Card Number Field
            TextFormField(
              controller: _cardNumberController,
              decoration: const InputDecoration(
                labelText: 'Card Number',
                border: OutlineInputBorder(),
                hintText: '1234 5678 9012 3456',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _formatCardNumber(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a card number';
                }
                
                final cardNumber = value.replaceAll(' ', '');
                
                // Check length
                if (cardNumber.length < 13 || cardNumber.length > 19) {
                  return 'Card number should be 13-19 digits';
                }
                
                // Check if all characters are digits
                if (!RegExp(r'^\d+$').hasMatch(cardNumber)) {
                  return 'Card number should contain only digits';
                }
                
                // Luhn algorithm check
                if (!_passesLuhnCheck(cardNumber)) {
                  return 'Invalid card number';
                }
                
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Expiry Date Field
            TextFormField(
              controller: _expiryDateController,
              decoration: const InputDecoration(
                labelText: 'Expiry Date',
                border: OutlineInputBorder(),
                hintText: 'MM/YY',
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => _formatExpiryDate(value),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter expiry date';
                }
                
                // Check format
                if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
                  return 'Use MM/YY format';
                }
                
                // Check validity
                final parts = value.split('/');
                try {
                  final month = int.parse(parts[0]);
                  final year = int.parse(parts[1]);
                  final now = DateTime.now();
                  final currentYear = now.year % 100; // Get last two digits
                  final currentMonth = now.month;
                  
                  // Check month
                  if (month < 1 || month > 12) {
                    return 'Invalid month (1-12)';
                  }
                  
                  // Check if card is expired
                  if (year < currentYear || (year == currentYear && month < currentMonth)) {
                    return 'Card has expired';
                  }
                } catch (e) {
                  return 'Invalid date';
                }
                
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Card Holder Field
            TextFormField(
              controller: _cardHolderController,
              decoration: const InputDecoration(
                labelText: 'Card Holder Name',
                border: OutlineInputBorder(),
                hintText: 'John Doe',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter card holder name';
                }
                if (!RegExp(r'^[A-Za-z\s]+$').hasMatch(value)) {
                  return 'Name should contain only letters';
                }
                if (value.length < 3) {
                  return 'Name is too short';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Default Card Checkbox
            CheckboxListTile(
              title: const Text('Set as default payment method'),
              value: _isDefault,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _isDefault = value ?? false;
                });
              },
            ),
            const SizedBox(height: 24),
            
            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updatePaymentMethod,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Update Card',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
} 