import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/user_management_service.dart';
import '../services/auth_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final UserManagementService _userService = UserManagementService();
  final TextEditingController _searchController = TextEditingController();

  List<UserProfile> _users = [];
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  UserRole? _roleFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.wait([_loadUsers(refresh: true), _loadStatistics()]);

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadUsers({bool refresh = false}) async {
    if (refresh) {
      _users.clear();
      _lastDocument = null;
      _hasMore = true;
    }

    if (!_hasMore) return;

    final result = await _userService.getUsers(
      limit: 20,
      lastDocument: _lastDocument,
      searchQuery: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      roleFilter: _roleFilter,
    );

    if (result['success']) {
      setState(() {
        if (refresh) {
          _users = List<UserProfile>.from(result['users']);
        } else {
          _users.addAll(List<UserProfile>.from(result['users']));
        }
        _lastDocument = result['lastDocument'];
        _hasMore = result['hasMore'] ?? false;
      });
    } else {
      setState(() {
        _errorMessage = result['error'];
      });
    }
  }

  Future<void> _loadStatistics() async {
    final result = await _userService.getUserStatistics();
    if (result['success']) {
      setState(() {
        _statistics = result;
      });
    }
  }

  void _onSearchChanged() {
    // Debounce search
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadUsers(refresh: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateUserDialog(),
            tooltip: 'Add New User',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorWidget()
          : Column(
              children: [
                _buildStatisticsCards(),
                _buildSearchAndFilters(),
                Expanded(child: _buildUsersList()),
              ],
            ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            'Error loading users',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    if (_statistics.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total Users',
              _statistics['totalUsers']?.toString() ?? '0',
              Icons.people,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Admins',
              _statistics['adminUsers']?.toString() ?? '0',
              Icons.admin_panel_settings,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Active',
              _statistics['activeUsers']?.toString() ?? '0',
              Icons.online_prediction,
              Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Recent',
              _statistics['recentUsers']?.toString() ?? '0',
              Icons.new_releases,
              Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => _onSearchChanged(),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<UserRole?>(
            value: _roleFilter,
            hint: const Text('Role'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Roles')),
              const DropdownMenuItem(
                value: UserRole.admin,
                child: Text('Admin'),
              ),
              const DropdownMenuItem(value: UserRole.user, child: Text('User')),
            ],
            onChanged: (value) {
              setState(() {
                _roleFilter = value;
              });
              _loadUsers(refresh: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    if (_users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No users found'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _users.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _users.length) {
          // Load more indicator
          if (!_isLoadingMore) {
            _loadUsers();
            _isLoadingMore = true;
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = _users[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(UserProfile user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isAdmin ? Colors.orange : Colors.blue,
          child: Icon(
            user.isAdmin ? Icons.admin_panel_settings : Icons.person,
            color: Colors.white,
          ),
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: user.isAdmin ? Colors.orange : Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user.role.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Joined: ${DateFormat('MMM dd, yyyy').format(user.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleUserAction(value, user),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reset_password',
              child: Row(
                children: [
                  Icon(Icons.lock_reset, size: 16),
                  SizedBox(width: 8),
                  Text('Reset Password'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleUserAction(String action, UserProfile user) {
    switch (action) {
      case 'edit':
        _showEditUserDialog(user);
        break;
      case 'reset_password':
        _resetUserPassword(user);
        break;
      case 'delete':
        _showDeleteUserDialog(user);
        break;
    }
  }

  void _showCreateUserDialog() {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController();
    UserRole selectedRole = UserRole.user;

    // Store the parent context for snackbar
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create New User'),
            content: SizedBox(
              width: double.maxFinite,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter full name';
                          }
                          if (value.trim().length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter email';
                          }
                          if (!RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          ).hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<UserRole>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.security),
                        ),
                        items: UserRole.values.map((role) {
                          return DropdownMenuItem(
                            value: role,
                            child: Text(role.name.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedRole = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    // Close the dialog immediately
                    Navigator.pop(context);

                    // Show loading indicator
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Creating user...'),
                          ],
                        ),
                        duration: Duration(seconds: 30),
                      ),
                    );

                    await _createUser(
                      email: emailController.text.trim(),
                      password: passwordController.text,
                      displayName: displayNameController.text.trim(),
                      role: selectedRole,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createUser({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    final result = await _userService.createUser(
      email: email,
      password: password,
      displayName: displayName,
      role: role,
    );

    // Dismiss the loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Show completion dialog
    if (mounted) {
      _showCreateUserCompletionDialog(result);
    }
  }

  void _showCreateUserCompletionDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result['success'] ? Icons.check_circle : Icons.error,
              color: result['success'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result['success'] ? 'User Created' : 'Creation Failed'),
          ],
        ),
        content: Text(
          result['success']
              ? result['message'] ?? 'User created successfully!'
              : 'Failed to create user: ${result['error']}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (result['success']) {
                _loadData(); // Refresh data
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: result['success'] ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(UserProfile user) {
    final formKey = GlobalKey<FormState>();
    final displayNameController = TextEditingController(text: user.displayName);
    UserRole selectedRole = user.role;

    // Store the parent context for snackbar
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit User: ${user.email}'),
            content: SizedBox(
              width: double.maxFinite,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter full name';
                        }
                        if (value.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<UserRole>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.security),
                      ),
                      items: UserRole.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Text(role.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedRole = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    // Close the dialog immediately
                    Navigator.pop(context);

                    // Show loading indicator
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Updating user...'),
                          ],
                        ),
                        duration: Duration(seconds: 30),
                      ),
                    );

                    await _updateUser(
                      user: user,
                      displayName: displayNameController.text.trim(),
                      role: selectedRole,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateUser({
    required UserProfile user,
    required String displayName,
    required UserRole role,
  }) async {
    final result = await _userService.updateUser(
      uid: user.uid,
      displayName: displayName != user.displayName ? displayName : null,
      role: role != user.role ? role : null,
    );

    // Dismiss the loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Show completion dialog
    if (mounted) {
      _showUpdateUserCompletionDialog(result);
    }
  }

  void _showUpdateUserCompletionDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result['success'] ? Icons.check_circle : Icons.error,
              color: result['success'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result['success'] ? 'User Updated' : 'Update Failed'),
          ],
        ),
        content: Text(
          result['success']
              ? result['message'] ?? 'User updated successfully!'
              : 'Failed to update user: ${result['error']}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (result['success']) {
                _loadData(); // Refresh data
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: result['success'] ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _resetUserPassword(UserProfile user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
          'Send a password reset email to "${user.email}"?\n\n'
          'The user will receive an email with instructions to reset their password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // Show loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Sending reset email...'),
                    ],
                  ),
                  duration: Duration(seconds: 30),
                ),
              );

              final result = await _userService.resetUserPassword(user.email);

              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['success']
                          ? 'Password reset email sent to ${user.email}'
                          : 'Failed to send reset email: ${result['error']}',
                    ),
                    backgroundColor: result['success']
                        ? Colors.green
                        : Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Reset Email'),
          ),
        ],
      ),
    );
  }

  void _showDeleteUserDialog(UserProfile user) {
    // Store the parent context for snackbar
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to delete user "${user.displayName}"?\n\n'
          'Email: ${user.email}\n'
          'Role: ${user.role.name.toUpperCase()}\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close the dialog immediately
              Navigator.pop(context);

              // Show loading indicator
              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Deleting user...'),
                    ],
                  ),
                  duration: Duration(seconds: 30),
                ),
              );

              await _deleteUser(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(UserProfile user) async {
    final result = await _userService.deleteUser(user.uid);

    // Dismiss the loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Show completion dialog
    if (mounted) {
      _showDeleteUserCompletionDialog(result, user);
    }
  }

  void _showDeleteUserCompletionDialog(
    Map<String, dynamic> result,
    UserProfile user,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result['success'] ? Icons.check_circle : Icons.error,
              color: result['success'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result['success'] ? 'User Deleted' : 'Delete Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result['success']
                  ? 'User "${user.displayName}" has been deleted successfully!'
                  : 'Failed to delete user: ${result['error']}',
            ),
            if (result['success']) ...[
              const SizedBox(height: 8),
              const Text(
                'The user profile has been removed from the system.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (result['success']) {
                _loadData(); // Refresh data
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: result['success'] ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
