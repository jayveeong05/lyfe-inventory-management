import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/dashboard_service.dart';
import '../services/invoice_service.dart';
import '../services/monthly_inventory_service.dart';
import 'sales_report_screen.dart';
import 'inventory_report_screen.dart';
import 'monthly_inventory_activity_screen.dart';
import 'demo_report_screen.dart';
import 'stock_in_screen.dart';
import 'stock_out_screen.dart';
import 'invoice_screen.dart';
import 'delivery_order_screen.dart';
import 'inventory_management_screen.dart';
import 'user_management_screen.dart';
import 'file_history_screen.dart';
import 'demo_screen.dart';
import 'cancel_order_screen.dart';
import 'demo_return_screen.dart';
import 'key_metrics_screen.dart';
import 'category_details_screen.dart';
import 'item_returned_screen.dart';
import 'profile_screen.dart';
import 'update_reference_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  Timer? _refreshTimer;
  Map<String, dynamic>? _lastKnownActivity;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAnalytics();
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // Smart background checking - only refresh UI if data changed
      if (mounted && !_isLoading) {
        _checkForDataChanges();
      }
    });
  }

  Future<void> _checkForDataChanges() async {
    try {
      // Get lightweight activity info for comparison
      final currentActivity = await _dashboardService.getLatestActivityInfo();

      // If this is the first check, store the activity and return
      if (_lastKnownActivity == null) {
        _lastKnownActivity = currentActivity;
        return;
      }

      // Compare with last known activity
      if (_hasDataChanged(currentActivity)) {
        print('Data changed detected - refreshing dashboard UI...');
        _lastKnownActivity = currentActivity;
        _loadAnalytics();
      }
    } catch (e) {
      print('Error checking for data changes: $e');
    }
  }

  bool _hasDataChanged(Map<String, dynamic> currentActivity) {
    if (_lastKnownActivity == null) return true;

    // Compare basic counts
    final currentCounts =
        currentActivity['basicCounts'] as Map<String, dynamic>;
    final lastCounts =
        _lastKnownActivity!['basicCounts'] as Map<String, dynamic>;

    if (currentCounts['totalTransactions'] != lastCounts['totalTransactions'] ||
        currentCounts['totalOrders'] != lastCounts['totalOrders']) {
      return true;
    }

    // Compare order status counts (this will detect invoice uploads)
    final currentOrderCounts =
        currentActivity['orderStatusCounts'] as Map<String, dynamic>;
    final lastOrderCounts =
        _lastKnownActivity!['orderStatusCounts'] as Map<String, dynamic>;

    if (currentOrderCounts['reserved'] != lastOrderCounts['reserved'] ||
        currentOrderCounts['invoiced'] != lastOrderCounts['invoiced'] ||
        currentOrderCounts['issued'] != lastOrderCounts['issued'] ||
        currentOrderCounts['delivered'] != lastOrderCounts['delivered']) {
      return true;
    }

    // Compare latest transaction
    final currentTransaction = currentActivity['latestTransaction'];
    final lastTransaction = _lastKnownActivity!['latestTransaction'];

    // If one is null and the other isn't, data changed
    if ((currentTransaction == null) != (lastTransaction == null)) {
      return true;
    }

    // If both are null, no change
    if (currentTransaction == null && lastTransaction == null) {
      return false;
    }

    // Compare transaction IDs
    final currentId = currentTransaction['transaction_id'];
    final lastId = lastTransaction['transaction_id'];

    return currentId != lastId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - refresh immediately
      print('App resumed - refreshing dashboard...');
      _loadAnalytics();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
                icon: const Icon(Icons.person),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
                tooltip: 'Profile',
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _analytics == null
              ? const Center(child: Text('Failed to load analytics'))
              : _buildMainContent(authProvider),
          bottomNavigationBar: MediaQuery.of(context).size.width <= 768
              ? _buildBottomNavigation()
              : null,
        );
      },
    );
  }

  Widget _buildMainContent(AuthProvider authProvider) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      return Row(
        children: [
          _buildSideNavigation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(authProvider),
                    const SizedBox(height: 24),
                    _buildQuickActionsBar(),
                    const SizedBox(height: 24),
                    _buildTopCategories(),
                    const SizedBox(height: 24),
                    _buildRecentActivity(),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(authProvider),
              const SizedBox(height: 24),
              _buildQuickActionsBar(),
              const SizedBox(height: 24),
              _buildTopCategories(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildSideNavigation() {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(right: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildNavItem(Icons.flash_on, 'Actions', 0, _showActionsMenu),
          _buildNavItem(Icons.settings, 'Manage', 1, _showManageMenu),
          _buildNavItem(Icons.bar_chart, 'Reports', 2, _showReportsMenu),
          _buildNavItem(Icons.analytics, 'Analytics', 3, _showAnalyticsMenu),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    VoidCallback onTap,
  ) {
    final isSelected = _selectedNavIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.teal : Colors.grey[600]),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.teal : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedTileColor: Colors.teal.withValues(alpha: 0.1),
        onTap: () {
          setState(() => _selectedNavIndex = index);
          onTap();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedNavIndex,
      onTap: (index) {
        setState(() => _selectedNavIndex = index);
        switch (index) {
          case 0:
            _showActionsMenu();
            break;
          case 1:
            _showManageMenu();
            break;
          case 2:
            _showReportsMenu();
            break;
          case 3:
            _showAnalyticsMenu();
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'Actions'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Manage'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics),
          label: 'Analytics',
        ),
      ],
    );
  }

  void _showActionsMenu() {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      _showDesktopMenu(
        title: 'Core Operations',
        buttonIndex: 0, // Actions button is first (index 0)
        menuItems: [
          _buildMenuOption(
            'Stock In',
            Icons.add_box,
            Colors.green,
            'Add new inventory items',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const StockInScreen()),
            ),
          ),
          _buildMenuOption(
            'Order',
            Icons.remove_circle_outline,
            Colors.red,
            'Create orders',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const StockOutScreen()),
            ),
          ),
          _buildMenuOption(
            'Invoice',
            Icons.receipt,
            Colors.blue,
            'Upload PDF invoices',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InvoiceScreen()),
            ),
          ),
          _buildMenuOption(
            'Delivery Order',
            Icons.local_shipping,
            Colors.orange,
            'Upload delivery documents',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DeliveryOrderScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Demo',
            Icons.play_circle_outline,
            Colors.purple,
            'Record demo transactions',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DemoScreen()),
            ),
          ),
          _buildMenuOption(
            'Demo Return',
            Icons.keyboard_return,
            Colors.indigo,
            'Process demo returns',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DemoReturnScreen()),
            ),
          ),
        ],
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Core Operations',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMenuOption(
                        'Stock In',
                        Icons.add_box,
                        Colors.green,
                        'Add new inventory items',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StockInScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Order',
                        Icons.remove_circle_outline,
                        Colors.red,
                        'Create orders',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StockOutScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Invoice',
                        Icons.receipt,
                        Colors.blue,
                        'Upload PDF invoices',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const InvoiceScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Delivery Order',
                        Icons.local_shipping,
                        Colors.orange,
                        'Upload delivery documents',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DeliveryOrderScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Demo',
                        Icons.play_circle_outline,
                        Colors.purple,
                        'Record demo transactions',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DemoScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Demo Return',
                        Icons.undo,
                        Colors.indigo,
                        'Process demo returns',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DemoReturnScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Back button at the bottom
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showDesktopMenu({
    required String title,
    required List<Widget> menuItems,
    required int buttonIndex,
  }) {
    // Calculate position based on button index
    final double buttonHeight = 60.0; // Height of each nav button
    final double startY = 100.0; // Starting Y position of first button
    final double buttonY = startY + (buttonIndex * buttonHeight);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        200, // Right edge of sidebar
        buttonY, // Align with the clicked button
        MediaQuery.of(context).size.width - 400,
        buttonY + 300, // Menu height
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Container(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                ...menuItems,
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showManageMenu() {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      _showDesktopMenu(
        title: 'System Management',
        buttonIndex: 1, // Manage button is second (index 1)
        menuItems: [
          _buildMenuOption(
            'Inventory Management',
            Icons.inventory,
            Colors.teal,
            'Manage inventory items',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const InventoryManagementScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'User Management',
            Icons.people,
            Colors.blue,
            'Manage user accounts',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserManagementScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'File History',
            Icons.history,
            Colors.grey,
            'View uploaded files',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FileHistoryScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Item Returned',
            Icons.assignment_return,
            Colors.deepOrange,
            'Process returned items',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ItemReturnedScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Cancel Order',
            Icons.cancel,
            Colors.red,
            'Cancel existing orders',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CancelOrderScreen(),
              ),
            ),
          ),
          if (kDebugMode)
            _buildMenuOption(
              'Update References',
              Icons.edit_note,
              Colors.purple,
              'Update order/demo numbers',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UpdateReferenceScreen(),
                ),
              ),
            ),
        ],
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Management',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMenuOption(
                        'Inventory Management',
                        Icons.inventory,
                        Colors.teal,
                        'Manage inventory items',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const InventoryManagementScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'User Management',
                        Icons.people,
                        Colors.blue,
                        'Manage user accounts',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UserManagementScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'File History',
                        Icons.folder,
                        Colors.orange,
                        'View uploaded files',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FileHistoryScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Item Returned',
                        Icons.assignment_return,
                        Colors.deepOrange,
                        'Process returned items',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ItemReturnedScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Cancel Order',
                        Icons.cancel,
                        Colors.red,
                        'Cancel existing orders',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CancelOrderScreen(),
                          ),
                        ),
                      ),
                      if (kDebugMode)
                        _buildMenuOption(
                          'Update References',
                          Icons.edit_note,
                          Colors.purple,
                          'Update order/demo numbers',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const UpdateReferenceScreen(),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Back button at the bottom
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showReportsMenu() {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      _showDesktopMenu(
        title: 'Reports',
        buttonIndex: 2, // Reports button is third (index 2)
        menuItems: [
          _buildMenuOption(
            'Sales Report',
            Icons.trending_up,
            Colors.green,
            'View sales analytics',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SalesReportScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Inventory Report',
            Icons.inventory_2,
            Colors.blue,
            'View inventory analytics',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const InventoryReportScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Monthly Activity',
            Icons.calendar_month,
            Colors.orange,
            'View monthly activity report',
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MonthlyInventoryActivityScreen(),
              ),
            ),
          ),
          _buildMenuOption(
            'Demo Tracking',
            Icons.track_changes,
            Colors.purple,
            'Track active demo items',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DemoReportScreen()),
            ),
          ),
        ],
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reports',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMenuOption(
                        'Sales Report',
                        Icons.trending_up,
                        Colors.green,
                        'View sales analytics',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SalesReportScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Inventory Report',
                        Icons.assessment,
                        Colors.blue,
                        'View inventory status',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const InventoryReportScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Monthly Activity',
                        Icons.calendar_month,
                        Colors.purple,
                        'View monthly statistics',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const MonthlyInventoryActivityScreen(),
                          ),
                        ),
                      ),
                      _buildMenuOption(
                        'Demo Tracking',
                        Icons.track_changes,
                        Colors.indigo,
                        'Track active demo items',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DemoReportScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Back button at the bottom
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showAnalyticsMenu() {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      _showDesktopMenu(
        title: 'Analytics',
        buttonIndex: 3, // Analytics button is fourth (index 3)
        menuItems: [
          _buildMenuOption(
            'Key Metrics',
            Icons.dashboard,
            Colors.teal,
            'View detailed analytics',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const KeyMetricsScreen()),
            ),
          ),
        ],
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Analytics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMenuOption(
                        'Key Metrics',
                        Icons.dashboard,
                        Colors.teal,
                        'View detailed analytics',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const KeyMetricsScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Back button at the bottom
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMenuOption(
    String title,
    IconData icon,
    Color color,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildQuickActionsBar() {
    return Card(
      elevation: 2,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickActionButton(
              'Stock In',
              Icons.add_box,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StockInScreen()),
              ),
            ),
            _buildQuickActionButton(
              'Order',
              Icons.remove_circle_outline,
              Colors.red,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StockOutScreen()),
              ),
            ),
            _buildQuickActionButton(
              'Invoice',
              Icons.receipt,
              Colors.blue,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InvoiceScreen()),
              ),
            ),
            _buildQuickActionButton(
              'Delivery',
              Icons.local_shipping,
              Colors.orange,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DeliveryOrderScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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
        Column(
          children: [
            _buildNavigationListItem(
              'Sales Report',
              Icons.analytics,
              Colors.blue,
              'Orders, customers, and sales analytics',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SalesReportScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Inventory Report',
              Icons.inventory_2,
              Colors.green,
              'Stock levels, movements, and aging analysis',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InventoryReportScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Monthly Inventory Activity',
              Icons.calendar_view_month,
              Colors.purple,
              'View monthly stock in, stock out, and remaining amounts by panel size',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const MonthlyInventoryActivityScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // Widget _buildDataFixSection() {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       const Text(
  //         'Data Utilities',
  //         style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  //       ),
  //       const SizedBox(height: 12),
  //       Card(
  //         child: InkWell(
  //           onTap: _fixInvoicedTransactionStatus,
  //           borderRadius: BorderRadius.circular(12),
  //           child: const Padding(
  //             padding: EdgeInsets.all(16),
  //             child: Row(
  //               children: [
  //                 Icon(Icons.build_circle, size: 32, color: Colors.orange),
  //                 SizedBox(width: 16),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         'Fix Transaction Status',
  //                         style: TextStyle(
  //                           fontSize: 16,
  //                           fontWeight: FontWeight.bold,
  //                         ),
  //                       ),
  //                       SizedBox(height: 4),
  //                       Text(
  //                         'Fix transactions with incorrect Invoiced status',
  //                         style: TextStyle(fontSize: 12, color: Colors.grey),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //                 Icon(Icons.arrow_forward_ios, size: 16),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  // Widget _buildDebugSection() {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       const Text(
  //         'Debug Tools',
  //         style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  //       ),
  //       const SizedBox(height: 12),
  //       Card(
  //         child: InkWell(
  //           onTap: _verifyInventoryConsistency,
  //           borderRadius: BorderRadius.circular(12),
  //           child: const Padding(
  //             padding: EdgeInsets.all(16),
  //             child: Row(
  //               children: [
  //                 Icon(Icons.analytics, size: 32, color: Colors.blue),
  //                 SizedBox(width: 16),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         'Verify Inventory Consistency',
  //                         style: TextStyle(
  //                           fontSize: 16,
  //                           fontWeight: FontWeight.bold,
  //                         ),
  //                       ),
  //                       SizedBox(height: 4),
  //                       Text(
  //                         'Check if Dashboard Active Stock matches Monthly Remaining',
  //                         style: TextStyle(fontSize: 12, color: Colors.grey),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //                 Icon(Icons.arrow_forward_ios, size: 16),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

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
        Column(
          children: [
            _buildNavigationListItem(
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
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Order',
              Icons.remove_circle_outline,
              Colors.red,
              'Create orders',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StockOutScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
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
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Delivery Order',
              Icons.local_shipping,
              Colors.orange,
              'Manage deliveries',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DeliveryOrderScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDemoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Demo Management',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            _buildNavigationListItem(
              'Demo',
              Icons.science,
              Colors.amber,
              'Record items for demonstration',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DemoScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Demo Return',
              Icons.assignment_return,
              Colors.green,
              'Return demo items to active status',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DemoReturnScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'System Management',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            _buildNavigationListItem(
              'Inventory Management',
              Icons.inventory_2,
              Colors.purple,
              'View and manage all inventory items',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InventoryManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'User Management',
              Icons.people,
              Colors.indigo,
              'Manage users and permissions',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'File History',
              Icons.history,
              Colors.deepPurple,
              'View all uploaded files and version history',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FileHistoryScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildNavigationListItem(
              'Cancel Order',
              Icons.cancel_outlined,
              Colors.red,
              'Cancel orders and restore inventory (Admin only)',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CancelOrderScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNavigationListItem(
    String title,
    IconData icon,
    Color color,
    String description,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          description,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey.shade400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final recentTransactions =
        _analytics!['recentTransactions'] as List<Map<String, dynamic>>;

    return Card(
      elevation: 4,
      color: Colors.blueGrey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    DateTime? timestamp;
                    if (uploadedAt is Timestamp) {
                      timestamp = uploadedAt.toDate();
                    } else if (uploadedAt is String) {
                      try {
                        timestamp = DateTime.parse(uploadedAt);
                      } catch (e) {
                        // Ignore parse errors
                      }
                    }

                    if (timestamp != null) {
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
              'Top Active Categories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (topCategories.isEmpty)
              const Center(
                child: Text(
                  'No active categories found',
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
                  final activeCount = category['active_count'] as int;
                  final maxCount = topCategories.isNotEmpty
                      ? topCategories[0]['active_count'] as int
                      : 1;
                  final percentage = maxCount > 0
                      ? (activeCount / maxCount)
                      : 0.0;

                  return Card(
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CategoryDetailsScreen(categoryName: name),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    '$activeCount active',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.indigo.shade400,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Tap to view details',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
