import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/order_service.dart';
import '../services/demo_service.dart';
import 'package:intl/intl.dart';

class UpdateReferenceScreen extends StatefulWidget {
  const UpdateReferenceScreen({super.key});

  @override
  State<UpdateReferenceScreen> createState() => _UpdateReferenceScreenState();
}

class _UpdateReferenceScreenState extends State<UpdateReferenceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late OrderService _orderService;
  late DemoService _demoService;

  final TextEditingController _orderSearchController = TextEditingController();
  final TextEditingController _demoSearchController = TextEditingController();

  // Data sources
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _allDemos = [];

  // Filtered results
  List<Map<String, dynamic>> _filteredOrders = [];
  List<Map<String, dynamic>> _filteredDemos = [];

  bool _isLoadingData = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orderService = OrderService(authService: authProvider.authService);
    _demoService = DemoService(authService: authProvider.authService);

    // Setup listeners for search-as-you-type
    _orderSearchController.addListener(_filterOrders);
    _demoSearchController.addListener(_filterDemos);

    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderSearchController.dispose();
    _demoSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoadingData = true);
    try {
      // Fetch all orders and demos once for client-side filtering
      // This enables "quicker" search experience (instant feedback)
      final orders = await _orderService.getAllOrders();
      final demos = await _demoService.getDemoHistory(
        limit: 1000,
      ); // 1000 limit for now

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _allDemos = demos;
          _filteredOrders =
              orders; // Show all initially or none? Let's show all or recent.
          _filteredDemos = demos;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  void _filterOrders() {
    final query = _orderSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = _allOrders;
      } else {
        _filteredOrders = _allOrders.where((order) {
          final number = (order['order_number'] ?? '').toString().toLowerCase();
          final dealer = (order['customer_dealer'] ?? '')
              .toString()
              .toLowerCase();
          return number.contains(query) || dealer.contains(query);
        }).toList();
      }
    });
  }

  void _filterDemos() {
    final query = _demoSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredDemos = _allDemos;
      } else {
        _filteredDemos = _allDemos.where((demo) {
          final number = (demo['demo_number'] ?? '').toString().toLowerCase();
          final dealer = (demo['customer_dealer'] ?? '')
              .toString()
              .toLowerCase();
          return number.contains(query) || dealer.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _updateOrderNumber(Map<String, dynamic> order) async {
    final oldNumber = order['order_number'];
    final newNumberController = TextEditingController(text: oldNumber);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Order Number'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Number: $oldNumber'),
            const SizedBox(height: 16),
            TextField(
              controller: newNumberController,
              decoration: const InputDecoration(
                labelText: 'New Order Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Warning: This checks uniqueness and updates all related files.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newNumberController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newNumber = newNumberController.text.trim();
      if (newNumber == oldNumber) return;

      setState(() => _isUpdating = true);

      try {
        final result = await _orderService.updateOrderNumber(
          oldOrderNumber: oldNumber,
          newOrderNumber: newNumber,
        );

        if (mounted) {
          if (result['success']) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.green,
              ),
            );
            // Reload data to reflect changes
            _loadAllData();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['error']),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _updateDemoNumber(Map<String, dynamic> demo) async {
    final oldNumber = demo['demo_number'];
    final newNumberController = TextEditingController(text: oldNumber);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Demo Number'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Number: $oldNumber'),
            const SizedBox(height: 16),
            TextField(
              controller: newNumberController,
              decoration: const InputDecoration(
                labelText: 'New Demo Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Warning: This checks uniqueness and updates return transactions.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newNumberController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newNumber = newNumberController.text.trim();
      if (newNumber == oldNumber) return;

      setState(() => _isUpdating = true);

      try {
        final result = await _demoService.updateDemoNumber(
          oldDemoNumber: oldNumber,
          newDemoNumber: newNumber,
        );

        if (mounted) {
          if (result['success']) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message']),
                backgroundColor: Colors.green,
              ),
            );
            // Reload data
            _loadAllData();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['error']),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating demo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Reference Numbers'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Orders', icon: Icon(Icons.shopping_cart)),
            Tab(text: 'Demos', icon: Icon(Icons.inventory)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [_buildOrderTab(), _buildDemoTab()],
          ),
          if (_isUpdating || _isLoadingData)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _orderSearchController,
            decoration: const InputDecoration(
              labelText: 'Search Orders',
              hintText: 'Search by Order Number or Dealer',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _filteredOrders.isEmpty
              ? const Center(child: Text('No matching orders found'))
              : ListView.builder(
                  itemCount: _filteredOrders.length,
                  itemBuilder: (context, index) {
                    final order = _filteredOrders[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(
                          order['order_number'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${order['customer_dealer'] ?? 'N/A'} • ${_formatDate(order['created_date'])}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _updateOrderNumber(order),
                        ),
                        onTap: () => _updateOrderNumber(order),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDemoTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _demoSearchController,
            decoration: const InputDecoration(
              labelText: 'Search Demos',
              hintText: 'Search by Demo Number or Dealer',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _filteredDemos.isEmpty
              ? const Center(child: Text('No matching demos found'))
              : ListView.builder(
                  itemCount: _filteredDemos.length,
                  itemBuilder: (context, index) {
                    final demo = _filteredDemos[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(
                          demo['demo_number'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${demo['customer_dealer'] ?? 'N/A'} • ${_formatDate(demo['created_date'])}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _updateDemoNumber(demo),
                        ),
                        onTap: () => _updateDemoNumber(demo),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('yyyy-MM-dd').format(date);
    }
    try {
      if (date.runtimeType.toString() == 'Timestamp') {
        return DateFormat('yyyy-MM-dd').format(date.toDate());
      }
    } catch (_) {}
    return date.toString();
  }
}
