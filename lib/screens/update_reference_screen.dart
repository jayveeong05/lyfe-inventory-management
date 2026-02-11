import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';
import '../services/order_service.dart';

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
          final dealer =
              (order['customer_dealer'] ?? '').toString().toLowerCase();
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
          final dealer =
              (demo['customer_dealer'] ?? '').toString().toLowerCase();
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
        _orderService.getOrdersPage(limit: _pageSize),
        _demoService.getDemosPage(limit: _pageSize),
      ]);

      final orderResult = results[0];
      final demoResult = results[1];

      final orders = (orderResult['orders'] ?? <Map<String, dynamic>>[]) as List<Map<String, dynamic>>;
      final demos = (demoResult['demos'] ?? <Map<String, dynamic>>[]) as List<Map<String, dynamic>>;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
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
    final orderNumberController = TextEditingController(
      text: order['order_number']?.toString() ?? '',
    );
    final dealerController = TextEditingController(
      text: order['customer_dealer']?.toString() ?? '',
    );
    final clientController = TextEditingController(
      text: order['customer_client']?.toString() ?? '',
    );
    final remarksController = TextEditingController(
      text: order['order_remarks']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Order'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orderNumberController,
                decoration: const InputDecoration(
                  labelText: 'Order Number *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dealerController,
                decoration: const InputDecoration(
                  labelText: 'Dealer Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: clientController,
                decoration: const InputDecoration(
                  labelText: 'Client Name (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (orderNumberController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    setState(() => _isUpdating = true);
    final oldNumber = order['order_number']?.toString() ?? '';
    final newNumber = orderNumberController.text.trim();
    final dealer = dealerController.text.trim();
    final client = clientController.text.trim();
    final remarks = remarksController.text.trim();

    try {
      if (newNumber != oldNumber) {
        final numberResult = await _orderService.updateOrderNumber(
          oldOrderNumber: oldNumber,
          newOrderNumber: newNumber,
        );
        if (numberResult['success'] != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(numberResult['error'] ?? 'Failed to update number'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isUpdating = false);
          return;
        }
      }

      final detailsResult = await _orderService.updateOrderDetails(
        orderNumber: newNumber,
        customerDealer: dealer.isNotEmpty ? dealer : null,
        customerClient: client.isNotEmpty ? client : null,
        orderRemarks: remarks.isNotEmpty ? remarks : null,
      );

      if (mounted) {
        if (detailsResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order updated.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadFirstPage();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(detailsResult['error'] ?? 'Update failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _openEditDemo(Map<String, dynamic> demo) async {
    DateTime? expectedReturnDate;
    final exp = demo['expected_return_date'];
    if (exp != null) {
      if (exp is DateTime) {
        expectedReturnDate = exp;
      } else if (exp.runtimeType.toString() == 'Timestamp') {
        expectedReturnDate = (exp as dynamic).toDate();
      }
    }

    final demoNumberController = TextEditingController(
      text: demo['demo_number']?.toString() ?? '',
    );
    final dealerController = TextEditingController(
      text: demo['customer_dealer']?.toString() ?? '',
    );
    final clientController = TextEditingController(
      text: demo['customer_client']?.toString() ?? '',
    );
    final purposeController = TextEditingController(
      text: demo['demo_purpose']?.toString() ?? '',
    );
    final locationController = TextEditingController(
      text: demo['location']?.toString() ?? '',
    );
    final remarksController = TextEditingController(
      text: demo['remarks']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Demo'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: demoNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Demo Number *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dealerController,
                    decoration: const InputDecoration(
                      labelText: 'Dealer Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: clientController,
                    decoration: const InputDecoration(
                      labelText: 'Client Name (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: purposeController,
                    decoration: const InputDecoration(
                      labelText: 'Demo Purpose',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Expected return date'),
                    subtitle: Text(
                      expectedReturnDate != null
                          ? DateFormat('yyyy-MM-dd').format(expectedReturnDate!)
                          : 'Not set',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            expectedReturnDate ?? DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => expectedReturnDate = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (demoNumberController.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true || !mounted) return;

    setState(() => _isUpdating = true);
    final oldNumber = demo['demo_number']?.toString() ?? '';
    final newNumber = demoNumberController.text.trim();

    try {
      if (newNumber != oldNumber) {
        final numberResult = await _demoService.updateDemoNumber(
          oldDemoNumber: oldNumber,
          newDemoNumber: newNumber,
        );
        if (numberResult['success'] != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(numberResult['error'] ?? 'Failed to update number'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isUpdating = false);
          return;
        }
      }

      final detailsResult = await _demoService.updateDemoDetails(
        demoNumber: newNumber,
        customerDealer: dealerController.text.trim().isNotEmpty
            ? dealerController.text.trim()
            : null,
        customerClient: clientController.text.trim().isNotEmpty
            ? clientController.text.trim()
            : null,
        demoPurpose: purposeController.text.trim().isNotEmpty
            ? purposeController.text.trim()
            : null,
        location: locationController.text.trim().isNotEmpty
            ? locationController.text.trim()
            : null,
        remarks: remarksController.text.trim().isNotEmpty
            ? remarksController.text.trim()
            : null,
        expectedReturnDate: expectedReturnDate,
      );

      if (mounted) {
        if (detailsResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demo updated.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadFirstPage();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(detailsResult['error'] ?? 'Update failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
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
