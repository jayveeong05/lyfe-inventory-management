import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Header Card
                _buildProfileHeaderCard(authProvider),
                const SizedBox(height: 16),
                
                // Account Information Card
                _buildAccountInfoCard(user),
                const SizedBox(height: 16),
                
                // App Information Card
                _buildAppInfoCard(),
                const SizedBox(height: 16),
                
                // Actions Card
                _buildActionsCard(authProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeaderCard(AuthProvider authProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Profile Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: authProvider.isAdmin ? Colors.green : Colors.blue,
              child: Icon(
                Icons.person,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authProvider.user?.email ?? 'Unknown User',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: authProvider.isAdmin ? Colors.green : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      authProvider.isAdmin ? 'ADMIN' : 'USER',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard(user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Email', user?.email ?? 'Not available'),
            _buildInfoRow('User ID', user?.uid ?? 'Not available'),
            _buildInfoRow('Account Created', 
              user?.metadata.creationTime?.toString().split(' ')[0] ?? 'Not available'),
            _buildInfoRow('Last Sign In', 
              user?.metadata.lastSignInTime?.toString().split(' ')[0] ?? 'Not available'),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('App Name', 'Inventory Management System'),
            _buildInfoRow('Version', '1.0.0'),
            _buildInfoRow('Platform', 'Flutter'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(AuthProvider authProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showSignOutDialog(authProvider),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignOutDialog(AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await authProvider.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
