import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import 'stock_in_screen.dart';
import 'stock_out_screen.dart';
import 'invoice_screen.dart';
import 'delivery_order_screen.dart';
import 'inventory_management_screen.dart';
import 'demo_screen.dart';
import 'demo_return_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('👤 USER DASHBOARD'),
            backgroundColor: Colors.blue.shade600,
            automaticallyImplyLeading:
                false, // Remove back button since this is main page
            actions: [
              // User menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle),
                onSelected: (value) async {
                  switch (value) {
                    case 'profile':
                      _showUserProfile(context, authProvider);
                      break;
                    case 'logout':
                      try {
                        await authProvider.signOut();
                        // Force navigation to login screen
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Logout failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        const Icon(Icons.person),
                        const SizedBox(width: 8),
                        Text(
                          authProvider.userProfile?.displayName ?? 'Profile',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome section
                _buildWelcomeSection(authProvider),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: [
                      _buildDashboardButton(
                        context,
                        'Stock In',
                        'Add new inventory items',
                        Icons.add_box,
                        Colors.green,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StockInScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Order',
                        'Create orders',
                        Icons.remove_circle_outline,
                        Colors.red,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StockOutScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Demo',
                        'Record demo items',
                        Icons.science,
                        Colors.amber,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DemoScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Demo Return',
                        'Return demo items',
                        Icons.assignment_return,
                        Colors.green,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DemoReturnScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Invoice',
                        'Upload PDF invoices',
                        Icons.receipt_long,
                        Colors.blue,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const InvoiceScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Delivery Order',
                        'Upload delivery PDFs',
                        Icons.local_shipping,
                        Colors.orange,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DeliveryOrderScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Inventory',
                        'View all inventory items',
                        Icons.inventory_2,
                        Colors.purple,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const InventoryManagementScreen(),
                            ),
                          );
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        'Profile',
                        'View profile and settings',
                        Icons.person,
                        Colors.teal,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeSection(AuthProvider authProvider) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.waving_hand,
                  color: Colors.orange.shade600,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Welcome back!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hello, ${authProvider.userProfile?.displayName ?? 'User'}',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your inventory operations below',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserProfile(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  authProvider.userProfile?.displayName ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.email, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(authProvider.userProfile?.email ?? 'Unknown'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.security, color: Colors.orange),
                const SizedBox(width: 8),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardButton(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
