import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/dashboard_service.dart';
import '../services/invoice_service.dart';
import '../services/monthly_inventory_service.dart';
import '../screens/login_screen.dart';
import 'sales_report_screen.dart';
import 'inventory_report_screen.dart';
import 'monthly_inventory_activity_screen.dart';
import 'stock_in_screen.dart';
import 'stock_out_screen.dart';
import 'invoice_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final analytics = await _dashboardService.getDashboardAnalytics();
      setState(() {
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading analytics: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            automaticallyImplyLeading:
                false, // Remove back button since this is main page
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAnalytics,
                tooltip: 'Refresh Data',
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
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
                },
                tooltip: 'Logout',
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _analytics == null
              ? const Center(child: Text('Failed to load analytics'))
              : RefreshIndicator(
                  onRefresh: _loadAnalytics,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome section
                        _buildWelcomeSection(authProvider),
                        const SizedBox(height: 24),

                        // Core navigation buttons
                        _buildCoreNavigationSection(),
                        const SizedBox(height: 24),

                        // Report buttons
                        _buildReportButtons(),
                        const SizedBox(height: 24),

                        // Data fix utilities
                        _buildDataFixSection(),
                        const SizedBox(height: 24),

                        // Debug section for inventory consistency
                        _buildDebugSection(),
                        const SizedBox(height: 24),

                        // Key metrics cards
                        _buildKeyMetricsSection(),
                        const SizedBox(height: 24),

                        // Inventory overview
                        _buildInventoryOverview(),
                        const SizedBox(height: 24),

                        // Sales & Purchase Orders
                        _buildSalesOverview(),
                        const SizedBox(height: 24),

                        // Monthly statistics
                        _buildMonthlyStats(),
                        const SizedBox(height: 24),

                        // Recent activity
                        _buildRecentActivity(),
                        const SizedBox(height: 24),

                        // Top categories
                        _buildTopCategories(),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildWelcomeSection(AuthProvider authProvider) {
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withValues(alpha: 0.8),
              Colors.blue.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, ${authProvider.userProfile?.displayName ?? 'Admin'}!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Admin Dashboard - ${DateFormat('EEEE, MMMM d, y').format(DateTime.now())}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reports',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SalesReportScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.analytics,
                          size: 32,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sales Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Purchase orders, customers, and sales analytics',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const InventoryReportScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 32,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Inventory Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stock levels, movements, and aging analysis',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Monthly Inventory Activity button (full width)
        Card(
          elevation: 2,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MonthlyInventoryActivityScreen(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_view_month,
                    size: 32,
                    color: Colors.purple.shade600,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monthly Inventory Activity',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'View monthly stock in, stock out, and remaining amounts by panel size',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataFixSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data Utilities',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            onTap: _fixInvoicedTransactionStatus,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.build_circle, size: 32, color: Colors.orange),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fix Transaction Status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Fix transactions with incorrect Invoiced status',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Debug Tools',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            onTap: _verifyInventoryConsistency,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.analytics, size: 32, color: Colors.blue),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify Inventory Consistency',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Check if Dashboard Active Stock matches Monthly Remaining',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _verifyInventoryConsistency() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Verifying inventory consistency...'),
          ],
        ),
      ),
    );

    try {
      // Get dashboard active stock
      final dashboardService = DashboardService();
      final dashboardStats = await dashboardService.getDashboardAnalytics();
      final dashboardActiveStock = dashboardStats['activeStock'] as int;

      // Get monthly remaining for current month
      final monthlyService = MonthlyInventoryService();
      final now = DateTime.now();
      final monthlyResult = await monthlyService.getMonthlyInventoryActivity(
        year: now.year,
        month: now.month,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      String message;
      bool isConsistent = false;

      if (monthlyResult['success'] == true) {
        final monthlyData = monthlyResult['data'] as Map<String, dynamic>;
        final monthlyRemaining =
            monthlyData['summary']['totalRemaining'] as int;

        if (dashboardActiveStock == monthlyRemaining) {
          message =
              '✅ SUCCESS: Numbers match perfectly!\n\n'
              'Dashboard Active Stock: $dashboardActiveStock\n'
              'Monthly Remaining: $monthlyRemaining\n\n'
              'The inventory consistency fix is working correctly.';
          isConsistent = true;
        } else {
          message =
              '❌ MISMATCH: Numbers still don\'t match\n\n'
              'Dashboard Active Stock: $dashboardActiveStock\n'
              'Monthly Remaining: $monthlyRemaining\n'
              'Difference: ${dashboardActiveStock - monthlyRemaining}\n\n'
              'There may be additional data inconsistencies to investigate.';
        }
      } else {
        message =
            '❌ ERROR: Failed to get monthly data\n\n'
            'Dashboard Active Stock: $dashboardActiveStock\n'
            'Monthly Error: ${monthlyResult['error']}\n\n'
            'Check the monthly inventory service for issues.';
      }

      // Show result
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              isConsistent
                  ? 'Consistency Check Passed'
                  : 'Consistency Check Failed',
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to verify inventory consistency: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _fixInvoicedTransactionStatus() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fix Transaction Status'),
        content: const Text(
          'This will fix transactions that have incorrect "Invoiced" status and change them to "Reserved" status.\n\n'
          'This is a one-time fix for the status system correction.\n\n'
          'Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fix Now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Fixing transaction status...'),
          ],
        ),
      ),
    );

    try {
      final invoiceService = InvoiceService();
      final result = await invoiceService.fixInvoicedTransactionStatus();

      // Close loading dialog
      Navigator.of(context).pop();

      // Show result
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result['success'] ? 'Success' : 'Error'),
          content: Text(result['message']),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (result['success']) {
                  // Reload dashboard data
                  _loadAnalytics();
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to fix transaction status: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCoreNavigationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Core Operations',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildNavigationCard(
              'Stock In',
              Icons.add_box,
              Colors.green,
              'Add new inventory items',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StockInScreen(),
                  ),
                );
              },
            ),
            _buildNavigationCard(
              'Stock Out',
              Icons.remove_circle_outline,
              Colors.red,
              'Create purchase orders',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StockOutScreen(),
                  ),
                );
              },
            ),
            _buildNavigationCard(
              'Invoice',
              Icons.receipt_long,
              Colors.blue,
              'Upload PDF invoices',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InvoiceScreen(),
                  ),
                );
              },
            ),
            _buildNavigationCard(
              'Delivery Order',
              Icons.local_shipping,
              Colors.orange,
              'Manage deliveries',
              () {
                // TODO: Navigate to Delivery Order screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Delivery Order feature coming soon!'),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNavigationCard(
    String title,
    IconData icon,
    Color color,
    String description,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
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

  Widget _buildKeyMetricsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key Metrics',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Items',
                _analytics!['totalInventoryItems'].toString(),
                Icons.inventory,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Active Stock',
                _analytics!['activeStock'].toString(),
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total POs',
                _analytics!['totalPurchaseOrders'].toString(),
                Icons.receipt_long,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Transactions',
                _analytics!['totalTransactions'].toString(),
                Icons.swap_horiz,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryOverview() {
    final activeStock = _analytics!['activeStock'] as int;
    final stockedOut = _analytics!['stockedOutItems'] as int;
    final total = activeStock + stockedOut;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inventory Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                total > 0
                                    ? '${((activeStock / total) * 100).toInt()}%'
                                    : '0%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$activeStock items'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                total > 0
                                    ? '${((stockedOut / total) * 100).toInt()}%'
                                    : '0%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              const Text(
                                'Stocked Out',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$stockedOut items'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesOverview() {
    final totalPOs = _analytics!['totalPurchaseOrders'] as int;
    final invoicedPOs = _analytics!['invoicedPOs'] as int;
    final pendingPOs = _analytics!['pendingPOs'] as int;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Purchase Orders & Sales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusIndicator(
                  'Invoiced',
                  invoicedPOs.toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
                _buildStatusIndicator(
                  'Pending',
                  pendingPOs.toString(),
                  Colors.orange,
                  Icons.pending,
                ),
                _buildStatusIndicator(
                  'Total POs',
                  totalPOs.toString(),
                  Colors.blue,
                  Icons.receipt_long,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMonthlyStats() {
    final monthlyStats = _analytics!['monthlyStats'] as Map<String, dynamic>;
    final monthlyStockIn = monthlyStats['monthlyStockIn'] as int;
    final monthlyStockOut = monthlyStats['monthlyStockOut'] as int;
    final monthlyTotal = monthlyStats['monthlyTotal'] as int;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This Month (${DateFormat('MMMM y').format(DateTime.now())})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Stock In',
                    monthlyStockIn.toString(),
                    Icons.add_box,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Stock Out',
                    monthlyStockOut.toString(),
                    Icons.remove_circle_outline,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Total',
                    monthlyTotal.toString(),
                    Icons.swap_horiz,
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    final recentTransactions =
        _analytics!['recentTransactions'] as List<Map<String, dynamic>>;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recentTransactions.isEmpty)
              const Center(
                child: Text(
                  'No recent transactions',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentTransactions.length > 5
                    ? 5
                    : recentTransactions.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final transaction = recentTransactions[index];
                  final type = transaction['type'] as String? ?? '';
                  final serialNumber =
                      transaction['serial_number'] as String? ?? 'N/A';
                  final uploadedAt = transaction['uploaded_at'];

                  String timeAgo = 'Unknown time';
                  if (uploadedAt != null) {
                    final timestamp = uploadedAt.toDate();
                    final now = DateTime.now();
                    final difference = now.difference(timestamp);

                    if (difference.inDays > 0) {
                      timeAgo = '${difference.inDays}d ago';
                    } else if (difference.inHours > 0) {
                      timeAgo = '${difference.inHours}h ago';
                    } else if (difference.inMinutes > 0) {
                      timeAgo = '${difference.inMinutes}m ago';
                    } else {
                      timeAgo = 'Just now';
                    }
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: type == 'Stock_In'
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      child: Icon(
                        type == 'Stock_In' ? Icons.add : Icons.remove,
                        color: type == 'Stock_In' ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(
                      type.replaceAll('_', ' '),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Serial: $serialNumber'),
                    trailing: Text(
                      timeAgo,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCategories() {
    final topCategories =
        _analytics!['topCategories'] as List<Map<String, dynamic>>;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Equipment Categories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (topCategories.isEmpty)
              const Center(
                child: Text(
                  'No categories found',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topCategories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final category = topCategories[index];
                  final name = category['category'] as String;
                  final count = category['count'] as int;
                  final maxCount = topCategories.isNotEmpty
                      ? topCategories[0]['count'] as int
                      : 1;
                  final percentage = (count / maxCount);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '$count items',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
