import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/admin_service.dart';
import '../../models/user.dart';

class AdminUsers extends StatefulWidget {
  const AdminUsers({Key? key}) : super(key: key);

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  String _searchQuery = '';
  String? _editingUserId; // Track which user is being edited, if any
  
  // Controllers for editing
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
  }
  
  Future<void> _loadUsers() async {
    try {
      await Provider.of<AdminService>(context, listen: false).loadAllUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load users: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Start editing a user
  void _startEditing(User user) {
    setState(() {
      _editingUserId = user.id;
      _firstNameController.text = user.firstName;
      _lastNameController.text = user.lastName;
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
    });
  }
  
  // Cancel editing
  void _cancelEditing() {
    setState(() {
      _editingUserId = null;
    });
  }
  
  // Save edited user
  void _saveUser(User originalUser) {
    final updatedUser = User(
      id: originalUser.id,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      createdAt: originalUser.createdAt,
      password: originalUser.password,
    );
    
    Provider.of<AdminService>(context, listen: false)
      .updateUser(updatedUser)
      .then((success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'User updated' : 'Update failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        
        if (success) {
          setState(() {
            _editingUserId = null; // Exit edit mode
          });
        }
      });
  }
  
  // Delete a user with confirmation
  void _deleteUser(User user) {
    // Use a simple showDialog without creating complex widgets
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${user.firstName} ${user.lastName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              // Pop dialog first
              Navigator.pop(context);
              
              // Then delete user
              Provider.of<AdminService>(context, listen: false)
                .deleteUser(user.id)
                .then((success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'User deleted' : 'Delete failed'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                });
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.indigo[800],
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search users...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Header text for users section
            const Text(
              'Users',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3949AB), // indigo[800] equivalent
              ),
            ),
            
            const SizedBox(height: 12),
            
            // User List
            Expanded(
              child: Consumer<AdminService>(
                builder: (context, adminService, child) {
                  if (adminService.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  final users = adminService.users.where((user) => 
                    user.firstName.toLowerCase().contains(_searchQuery) ||
                    user.lastName.toLowerCase().contains(_searchQuery) ||
                    user.email.toLowerCase().contains(_searchQuery)
                  ).toList();
                  
                  if (users.isEmpty) {
                    return const Center(child: Text('No users found'));
                  }
                  
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final isEditing = user.id == _editingUserId;
                      
                      // Show edit form if this user is being edited
                      if (isEditing) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          color: const Color(0xFFE8EAF6), // Light indigo background
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit User',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF3949AB),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(_firstNameController, 'First Name'),
                                const SizedBox(height: 12),
                                _buildTextField(_lastNameController, 'Last Name'),
                                const SizedBox(height: 12),
                                _buildTextField(_emailController, 'Email'),
                                const SizedBox(height: 12),
                                _buildTextField(_phoneController, 'Phone'),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _cancelEditing,
                                      child: const Text(
                                        'CANCEL',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton(
                                      onPressed: () => _saveUser(user),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF3949AB),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('SAVE'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      
                      // Show normal card if not editing
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            '${user.firstName} ${user.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(user.email),
                              Text(
                                user.phoneNumber != null && user.phoneNumber!.isNotEmpty 
                                    ? 'Phone: ${user.phoneNumber}' 
                                    : 'No phone number',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Color(0xFF3949AB)),
                                onPressed: () => _startEditing(user),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteUser(user),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
      ),
    );
  }
} 