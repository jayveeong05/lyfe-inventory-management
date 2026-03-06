import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';
import '../services/order_service.dart';
import 'edit_order_screen.dart';
import 'edit_demo_screen.dart';

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
  final ScrollController _orderScrollController = ScrollController();
  final ScrollController _demoScrollController = ScrollController();

  static const int _pageSize = 25;

  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _allDemos = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  List<Map<String, dynamic>> _filteredDemos = [];

  DocumentSnapshot? _ordersLastDoc;
  DocumentSnapshot? _demosLastDoc;
  bool _hasMoreOrders = true;
  bool _hasMoreDemos = true;
  bool _isLoadingData = true;
  bool _loadingMoreOrders = false;
  bool _loadingMoreDemos = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orderService = OrderService(authService: authProvider.authService);
    _demoService = DemoService(authService: authProvider.authService);

    _orderSearchController.addListener(_applyOrderFilter);
    _demoSearchController.addListener(_applyDemoFilter);

    _orderScrollController.addListener(_onOrderScroll);
    _demoScrollController.addListener(_onDemoScroll);

    _loadFirstPage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderSearchController.dispose();
    _demoSearchController.dispose();
    _orderScrollController.dispose();
    _demoScrollController.dispose();
    super.dispose();
  }

  void _applyOrderFilter() {
    final query = _orderSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = List.from(_allOrders);
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

  void _applyDemoFilter() {
    final query = _demoSearchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredDemos = List.from(_allDemos);
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

  void _onOrderScroll() {
    if (_loadingMoreOrders || !_hasMoreOrders) return;
    final pos = _orderScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreOrders();
    }
  }

  void _onDemoScroll() {
    if (_loadingMoreDemos || !_hasMoreDemos) return;
    final pos = _demoScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreDemos();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoadingData = true;
      _allOrders = [];
      _allDemos = [];
      _filteredOrders = [];
      _filteredDemos = [];
      _ordersLastDoc = null;
      _demosLastDoc = null;
      _hasMoreOrders = true;
      _hasMoreDemos = true;
    });

    try {
      final results = await Future.wait([
        _orderService.getOrdersPage(
          limit: _pageSize,
          invoiceStatus: 'Reserved',
          deliveryStatus: 'Pending',
        ),
        _demoService.getDemosPage(limit: _pageSize),
      ]);

      final orderResult = results[0];
      final demoResult = results[1];

      final orders =
          (orderResult['orders'] ?? <Map<String, dynamic>>[])
              as List<Map<String, dynamic>>;
      final demos =
          (demoResult['demos'] ?? <Map<String, dynamic>>[])
              as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _allDemos = demos;
          _filteredOrders = List.from(orders);
          _filteredDemos = List.from(demos);
          _ordersLastDoc = orderResult['lastDoc'] as DocumentSnapshot?;
          _demosLastDoc = demoResult['lastDoc'] as DocumentSnapshot?;
          _hasMoreOrders = orders.length >= _pageSize;
          _hasMoreDemos = demos.length >= _pageSize;
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

  Future<void> _loadMoreOrders() async {
    if (_loadingMoreOrders || !_hasMoreOrders || _ordersLastDoc == null) return;
    setState(() => _loadingMoreOrders = true);
    try {
      final result = await _orderService.getOrdersPage(
        limit: _pageSize,
        startAfter: _ordersLastDoc,
        invoiceStatus: 'Reserved',
        deliveryStatus: 'Pending',
      );
      final orders = result['orders'] as List<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          if (orders.isNotEmpty) {
            _allOrders = [..._allOrders, ...orders];
            _ordersLastDoc = result['lastDoc'] as DocumentSnapshot?;
          }
          _hasMoreOrders = orders.length >= _pageSize;
          _loadingMoreOrders = false;
        });
        _applyOrderFilter();
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMoreOrders = false);
    }
  }

  Future<void> _loadMoreDemos() async {
    if (_loadingMoreDemos || !_hasMoreDemos || _demosLastDoc == null) return;
    setState(() => _loadingMoreDemos = true);
    try {
      final result = await _demoService.getDemosPage(
        limit: _pageSize,
        startAfter: _demosLastDoc,
      );
      final demos = result['demos'] as List<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          if (demos.isNotEmpty) {
            _allDemos = [..._allDemos, ...demos];
            _demosLastDoc = result['lastDoc'] as DocumentSnapshot?;
          }
          _hasMoreDemos = demos.length >= _pageSize;
          _loadingMoreDemos = false;
        });
        _applyDemoFilter();
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMoreDemos = false);
    }
  }

  Future<void> _openEditOrder(Map<String, dynamic> order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditOrderScreen(order: order)),
    );
    // Refresh the list after editing just in case something major changed
    _loadFirstPage();
  }

  Future<void> _openEditDemo(Map<String, dynamic> demo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditDemoScreen(demo: demo)),
    );
    // Refresh the list after editing
    _loadFirstPage();
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
            onPressed: _isLoadingData ? null : _loadFirstPage,
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
          if (_isUpdating)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderTab() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
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
                  controller: _orderScrollController,
                  itemCount: _filteredOrders.length + (_hasMoreOrders ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _filteredOrders.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _loadingMoreOrders
                            ? const Center(child: CircularProgressIndicator())
                            : const SizedBox.shrink(),
                      );
                    }
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
                          onPressed: () => _openEditOrder(order),
                        ),
                        onTap: () => _openEditOrder(order),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDemoTab() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
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
                  controller: _demoScrollController,
                  itemCount: _filteredDemos.length + (_hasMoreDemos ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _filteredDemos.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _loadingMoreDemos
                            ? const Center(child: CircularProgressIndicator())
                            : const SizedBox.shrink(),
                      );
                    }
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
                          onPressed: () => _openEditDemo(demo),
                        ),
                        onTap: () => _openEditDemo(demo),
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
