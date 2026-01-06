import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/report_service.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  final ReportService _reportService = ReportService();

  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  String? _error;

  // Filter variables
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCustomer;
  String? _selectedLocation;

  List<String> _customers = [];
  List<String> _locations = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadFilterOptions();
    await _loadReport();
  }

  Future<void> _loadFilterOptions() async {
    final customers = await _reportService.getCustomerList();
    final locations = await _reportService.getLocationList();

    setState(() {
      _customers = customers;
      _locations = locations;
    });
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _reportService.getSalesReport(
      startDate: _startDate,
      endDate: _endDate,
      customerDealer: _selectedCustomer,
      location: _selectedLocation,
    );

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _reportData = result['data'];
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _exportReport() async {
    if (_reportData == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    try {
      final filePath = await _reportService.exportSalesReportToCSV(
        _reportData!,
      );

      if (filePath != null) {
        if (mounted) {
          _showExportSuccessDialog(filePath);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to export report')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    }
  }

  void _showExportSuccessDialog(String filePath) {
    // If filePath is just "Downloads folder" or similar generic message (Web), show a simplified dialog
    final isGenericPath = !filePath.contains('/') && !filePath.contains('\\');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Export Successful!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGenericPath
                    ? 'Your sales report has been downloaded.'
                    : 'Your sales report has been saved to:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (!isGenericPath)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    filePath,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'How to open the CSV file:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. Go to your Downloads folder'),
              const Text('2. Find the CSV file and open it'),
              const Text('3. Compatible with Excel, Sheets, etc.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportReport,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadReport),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text('Error: $_error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadReport,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _buildReportContent(),
    );
  }

  Widget _buildReportContent() {
    if (_reportData == null) {
      return const Center(child: Text('No data available'));
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodInfo(),
            const SizedBox(height: 20),
            _buildSummaryCards(),
            const SizedBox(height: 20),
            _buildCustomerPurchaseDetails(), // NEW: Customer purchase details
            const SizedBox(height: 20),
            _buildTopCustomers(),
            const SizedBox(height: 20),
            _buildTopLocations(),
            const SizedBox(height: 20),
            _buildTopCategories(),
            const SizedBox(height: 20),
            _buildRecentOrders(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodInfo() {
    final period = _reportData!['period'] as Map<String, dynamic>?;
    if (period == null) return const SizedBox.shrink();

    final startDate = period['start_date'] as DateTime?;
    final endDate = period['end_date'] as DateTime?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.date_range, color: Colors.blue.shade600),
            const SizedBox(width: 12),
            Text(
              'Report Period: ${startDate != null ? DateFormat('MMM dd, yyyy').format(startDate) : 'N/A'} - ${endDate != null ? DateFormat('MMM dd, yyyy').format(endDate) : 'N/A'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _reportData!['summary'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sales Summary',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildSummaryCard(
              'Total Orders',
              '${summary['total_purchase_orders'] ?? 0}',
              Icons.shopping_cart,
              Colors.blue,
            ),
            _buildSummaryCard(
              'Invoiced Orders',
              '${summary['invoiced_orders'] ?? 0}',
              Icons.receipt,
              Colors.green,
            ),
            _buildSummaryCard(
              'Pending Orders',
              '${summary['pending_orders'] ?? 0}',
              Icons.pending,
              Colors.orange,
            ),
            _buildSummaryCard(
              'Items Sold',
              '${summary['total_items_sold'] ?? 0}',
              Icons.inventory,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Conversion Rate',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${summary['conversion_rate'] ?? '0.0'}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerPurchaseDetails() {
    final customerItems =
        _reportData!['customer_items'] as Map<String, dynamic>? ?? {};

    if (customerItems.isEmpty) {
      return const SizedBox.shrink();
    }

    // Convert to list and sort by item count
    final customerList = customerItems.entries.toList()
      ..sort(
        (a, b) => (b.value as List).length.compareTo((a.value as List).length),
      );

    final totalCustomers = customerList.length;
    final totalItemsDetailed = customerList.fold<int>(
      0,
      (sum, entry) => sum + (entry.value as List).length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Flexible(
              child: Text(
                'Customer Purchase Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$totalCustomers customers • $totalItemsDetailed items',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: customerList.take(20).map((entry) {
              final customerName = entry.key;
              final items = entry.value as List<dynamic>;

              // Count items by category
              final categoryCount = <String, int>{};
              for (final item in items) {
                final category = item['category'] as String? ?? 'Unknown';
                categoryCount[category] = (categoryCount[category] ?? 0) + 1;
              }

              return ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    customerName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  customerName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${items.length} items purchased'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category breakdown
                        if (categoryCount.isNotEmpty) ...[
                          Text(
                            'Categories:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: categoryCount.entries.map((cat) {
                              return Chip(
                                label: Text(
                                  '${cat.key}: ${cat.value}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Colors.blue.shade50,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Item details table
                        Text(
                          'Items Purchased:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              // Header
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    topRight: Radius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Serial Number',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Category',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Date',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Items
                              ...items.take(10).map((item) {
                                final date = item['date'] as DateTime?;
                                return Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          item['serial_number'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          item['category'] ?? 'Unknown',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          date != null
                                              ? DateFormat('MMM d').format(date)
                                              : 'N/A',
                                          style: const TextStyle(fontSize: 10),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              if (items.length > 10)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    '+ ${items.length - 10} more items',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopCustomers() {
    final topCustomers = _reportData!['top_customers'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Customers',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: topCustomers.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No customer data available'),
                    ),
                  ]
                : topCustomers.take(5).map((customer) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Icon(
                          Icons.business,
                          color: Colors.blue.shade600,
                        ),
                      ),
                      title: Text(customer['customer'] ?? 'Unknown'),
                      subtitle: Text('${customer['items']} items'),
                      trailing: Text(
                        '${customer['orders']} orders',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopLocations() {
    final topLocations = _reportData!['top_locations'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Locations',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: topLocations.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No location data available'),
                    ),
                  ]
                : topLocations.take(5).map((location) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: Icon(
                          Icons.location_on,
                          color: Colors.green.shade600,
                        ),
                      ),
                      title: Text(location['location'] ?? 'Unknown'),
                      subtitle: Text('${location['items']} items'),
                      trailing: Text(
                        '${location['transactions']} transactions',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopCategories() {
    final topCategories =
        _reportData!['top_categories'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Categories',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: topCategories.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No category data available'),
                    ),
                  ]
                : topCategories.take(5).map((category) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.shade100,
                        child: Icon(
                          Icons.category,
                          color: Colors.purple.shade600,
                        ),
                      ),
                      title: Text(category['category'] ?? 'Unknown'),
                      subtitle: Text('${category['items']} items'),
                      trailing: Text(
                        '${category['transactions']} transactions',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrders() {
    final orders = _reportData!['orders'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Orders',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: orders.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No orders found'),
                    ),
                  ]
                : orders.take(10).map((order) {
                    final status =
                        order['invoice_status'] as String? ??
                        order['status'] as String? ??
                        'Pending';
                    final createdDate = order['created_date'] as Timestamp?;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: status == 'Invoiced'
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          status == 'Invoiced' ? Icons.check : Icons.pending,
                          color: status == 'Invoiced'
                              ? Colors.green.shade600
                              : Colors.orange.shade600,
                        ),
                      ),
                      title: Text(order['order_number'] ?? 'Unknown Order'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order['customer_dealer'] ?? 'Unknown Customer'),
                          if (createdDate != null)
                            Text(
                              DateFormat(
                                'MMM dd, yyyy',
                              ).format(createdDate.toDate()),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            status,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: status == 'Invoiced'
                                  ? Colors.green.shade600
                                  : Colors.orange.shade600,
                            ),
                          ),
                          Text(
                            '${order['total_items'] ?? 0} items',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Filter Sales Report'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date range
                  ListTile(
                    title: const Text('Start Date'),
                    subtitle: Text(
                      _startDate != null
                          ? DateFormat('MMM dd, yyyy').format(_startDate!)
                          : 'Not selected',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate:
                            _startDate ??
                            DateTime.now().subtract(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() {
                          _startDate = date;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('End Date'),
                    subtitle: Text(
                      _endDate != null
                          ? DateFormat('MMM dd, yyyy').format(_endDate!)
                          : 'Not selected',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() {
                          _endDate = date;
                        });
                      }
                    },
                  ),
                  // Customer filter
                  DropdownButtonFormField<String>(
                    value: _selectedCustomer,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Customers'),
                      ),
                      ..._customers.map(
                        (customer) => DropdownMenuItem(
                          value: customer,
                          child: Text(customer),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCustomer = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Location filter
                  DropdownButtonFormField<String>(
                    value: _selectedLocation,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Locations'),
                      ),
                      ..._locations.map(
                        (location) => DropdownMenuItem(
                          value: location,
                          child: Text(location),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedLocation = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Update parent state
                  this.setState(() {
                    _startDate = null;
                    _endDate = null;
                    _selectedCustomer = null;
                    _selectedLocation = null;
                  });
                  Navigator.pop(context);
                  _loadReport();
                },
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadReport();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }
}
