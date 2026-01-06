import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/report_service.dart';
import 'customer_details_screen.dart';

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
            // 1. Sales Over Time (Chart) - MOVED TO TOP
            _buildSalesTrends(),
            const SizedBox(height: 20),
            // 2. Summary Cards
            _buildSummaryCards(),
            const SizedBox(height: 20),
            // 3. Who to Focus On (Customer Intelligence)
            _buildCustomerIntelligence(),
            const SizedBox(height: 20),
            // 4. Customer Purchase Details
            _buildCustomerPurchaseDetails(),
            const SizedBox(height: 20),
            // 5. Top Customers
            _buildTopCustomers(),
            const SizedBox(height: 20),
            // 6. What's Selling (Product Performance)
            _buildProductPerformance(),
            const SizedBox(height: 20),
            // 7. Sales by State (Top Locations)
            _buildTopLocations(),
            const SizedBox(height: 20),
            // 8. Equipment Types (Top Categories)
            _buildTopCategories(),
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

    final totalOrders = summary['total_orders'] ?? 0;
    final itemsSold = summary['total_items_sold'] ?? 0;
    final conversionRate = summary['conversion_rate'] ?? '0.0';

    // Calculate avg order size
    final avgOrderSize = totalOrders > 0
        ? (itemsSold / totalOrders).toStringAsFixed(1)
        : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sales Summary',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // Horizontal scrollable cards
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildModernSummaryCard(
                title: 'Total Orders',
                value: totalOrders.toString(),
                icon: Icons.shopping_cart_outlined,
                accentColor: Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildModernSummaryCard(
                title: 'Items Sold',
                value: itemsSold.toString(),
                icon: Icons.inventory_2_outlined,
                accentColor: Colors.purple,
              ),
              const SizedBox(width: 12),
              _buildModernSummaryCard(
                title: 'Conversion Rate',
                value: '$conversionRate%',
                icon: Icons.check_circle_outline,
                accentColor: Colors.green,
              ),
              const SizedBox(width: 12),
              _buildModernSummaryCard(
                title: 'Avg Order Size',
                value: avgOrderSize,
                subtitle: 'items/order',
                icon: Icons.analytics_outlined,
                accentColor: Colors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernSummaryCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
            ],
          ),
        ],
      ),
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

                        // View Details Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CustomerDetailsScreen(
                                    customerName: customerName,
                                    items: items,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('View Full History'),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: topCustomers.isEmpty
                  ? [const Text('No customer data available')]
                  : [
                      ...topCustomers.take(5).map((customer) {
                        final name = customer['customer'] ?? 'Unknown';
                        final orders = customer['orders'] as int;
                        final items = customer['items'] as int;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$orders orders',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$items items',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      if (topCustomers.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () {
                              // Show all customers dialog
                              _showAllCustomersDialog(topCustomers);
                            },
                            child: Text(
                              'Show all ${topCustomers.length} customers',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAllCustomersDialog(List<dynamic> customers) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('All Customers'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customer = customers[index];
              final name = customer['customer'] ?? 'Unknown';
              final orders = customer['orders'] as int;
              final items = customer['items'] as int;

              return ListTile(
                title: Text(name),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$orders orders',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '$items items',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLocations() {
    final topLocations = _reportData!['top_locations'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sales by State',
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
                : topLocations.map((location) {
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
                        '${location['transactions']} sales',
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
          'Equipment Types',
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
                : topCategories.map((category) {
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
                        '${category['transactions']} sales',
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

  String _selectedGranularity = 'Day'; // Add state variable for granularity

  Widget _buildSalesTrends() {
    final trends = _reportData!['trends'] as Map<String, dynamic>? ?? {};
    final dailySales = trends['daily_sales'] as Map<String, dynamic>? ?? {};

    if (dailySales.isEmpty) {
      return const SizedBox.shrink();
    }

    final peakDay = trends['peak_day'] as String? ?? '';
    final avgOrders = trends['avg_daily_orders'] as String? ?? '0.0';

    // Aggregate data based on granularity
    final aggregatedData = _aggregateSalesData(
      dailySales,
      _selectedGranularity,
    );
    final sortedDates = aggregatedData.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final orders = aggregatedData[sortedDates[i]] as double;
      spots.add(FlSpot(i.toDouble(), orders));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Sales Over Time',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            // Granularity Toggle
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: ['Day', 'Week', 'Month'].map((granularity) {
                  final isSelected = _selectedGranularity == granularity;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedGranularity = granularity;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        granularity,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chart
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: 1, // Force integer intervals
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(), // Integer only
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: sortedDates.length > 10
                                ? (sortedDates.length / 5).ceilToDouble()
                                : 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= sortedDates.length)
                                return const Text('');
                              final dateStr = sortedDates[value.toInt()];
                              return Text(
                                _formatDateLabel(dateStr, _selectedGranularity),
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      // Add touch/hover tooltips
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (touchedSpot) =>
                              Colors.blue.shade700,
                          tooltipRoundedRadius: 8,
                          tooltipPadding: const EdgeInsets.all(8),
                          getTooltipItems: (List<LineBarSpot> touchedSpots) {
                            return touchedSpots.map((spot) {
                              final dateStr = sortedDates[spot.x.toInt()];
                              final date = DateTime.parse(dateStr);
                              final orders = spot.y.toInt();

                              String dateDisplay;
                              if (_selectedGranularity == 'Day') {
                                dateDisplay = DateFormat(
                                  'MMM dd, yyyy',
                                ).format(date);
                              } else if (_selectedGranularity == 'Week') {
                                // Show date range for week
                                final weekEnd = date.add(
                                  const Duration(days: 6),
                                );
                                dateDisplay =
                                    '${DateFormat('MMM dd').format(date)}-${DateFormat('dd, yyyy').format(weekEnd)}';
                              } else {
                                dateDisplay = DateFormat(
                                  'MMMM yyyy',
                                ).format(date);
                              }

                              return LineTooltipItem(
                                '$dateDisplay\n$orders orders',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.blue,
                          barWidth: 3,
                          dotData: FlDotData(show: spots.length <= 31),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.blue.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Metrics
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTrendMetric(
                      'Best Day',
                      peakDay.isNotEmpty
                          ? DateFormat('MMM dd').format(DateTime.parse(peakDay))
                          : 'N/A',
                      Icons.trending_up,
                      Colors.green,
                    ),
                    _buildTrendMetric(
                      'Daily Avg',
                      avgOrders,
                      Icons.show_chart,
                      Colors.blue,
                    ),
                    _buildTrendMetric(
                      'Total Days',
                      dailySales.length.toString(),
                      Icons.calendar_today,
                      Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Map<String, double> _aggregateSalesData(
    Map<String, dynamic> dailySales,
    String granularity,
  ) {
    if (granularity == 'Day') {
      // Return daily data as-is
      return dailySales.map((key, value) {
        final data = value as Map<String, dynamic>;
        return MapEntry(key, (data['orders'] as int).toDouble());
      });
    }

    final aggregated = <String, double>{};

    dailySales.forEach((dateStr, value) {
      final date = DateTime.parse(dateStr);
      final data = value as Map<String, dynamic>;
      final orders = (data['orders'] as int).toDouble();

      String key;
      if (granularity == 'Week') {
        // Get Monday of the week
        final monday = date.subtract(Duration(days: date.weekday - 1));
        key = DateFormat('yyyy-MM-dd').format(monday);
      } else {
        // Month
        key = '${date.year}-${date.month.toString().padLeft(2, '0')}-01';
      }

      aggregated[key] = (aggregated[key] ?? 0) + orders;
    });

    return aggregated;
  }

  String _formatDateLabel(String dateStr, String granularity) {
    final date = DateTime.parse(dateStr);
    if (granularity == 'Day') {
      return DateFormat('MMM dd').format(date);
    } else if (granularity == 'Week') {
      // Show start date of week instead of week number
      return DateFormat('MMM dd').format(date);
    } else {
      return DateFormat('MMM').format(date);
    }
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return (daysSinceFirstDay / 7).ceil() + 1;
  }

  Widget _buildTrendMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildCustomerIntelligence() {
    final intelligence =
        _reportData!['customer_intelligence'] as Map<String, dynamic>? ?? {};

    if (intelligence.isEmpty) {
      return const SizedBox.shrink();
    }

    final newCustomers = intelligence['new_customers'] ?? 0;
    final repeatCustomers = intelligence['repeat_customers'] ?? 0;
    final loyaltyRate = intelligence['loyalty_rate'] ?? '0.0';
    final newCustomersList = intelligence['new_customers_list'] as List? ?? [];
    final repeatCustomersList =
        intelligence['repeat_customers_list'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Who to Focus On',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        // Metrics Cards
        Row(
          children: [
            Expanded(
              child: _buildIntelligenceCard(
                'New Customers',
                newCustomers.toString(),
                Icons.person_add,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildIntelligenceCard(
                'Repeat Customers',
                repeatCustomers.toString(),
                Icons.repeat,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildIntelligenceCard(
                'Loyalty Rate',
                '$loyaltyRate%',
                Icons.favorite,
                Colors.purple,
              ),
            ),
          ],
        ),
        // Customer Lists in Separate Rows
        if (newCustomersList.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCustomerSegmentCard(
            'First-Time Buyers',
            newCustomersList,
            Colors.blue,
            Icons.person_add_outlined,
            showOrders: false,
          ),
        ],
        if (repeatCustomersList.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCustomerSegmentCard(
            'Returning Customers',
            repeatCustomersList,
            Colors.green,
            Icons.repeat,
            showOrders: true,
          ),
        ],
      ],
    );
  }

  Widget _buildCustomerSegmentCard(
    String title,
    List customers,
    Color color,
    IconData icon, {
    required bool showOrders,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...customers.take(5).map((customer) {
              final name = customer['customer'] as String;
              final items = customer['items'] as int;
              final orders = showOrders ? customer['orders'] as int : 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showOrders) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$orders orders',
                          style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$items items',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            if (customers.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: () {
                    // Show dialog with all customers
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(title),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: customers.length,
                            itemBuilder: (context, index) {
                              final customer = customers[index];
                              final name = customer['customer'] as String;
                              final orders = showOrders
                                  ? customer['orders'] as int
                                  : 1;
                              final items = customer['items'] as int;

                              return ListTile(
                                title: Text(name),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (showOrders)
                                      Text(
                                        '$orders orders',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    Text(
                                      '$items items',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(
                    'Show all ${customers.length} customers',
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntelligenceCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductPerformance() {
    final performance =
        _reportData!['product_performance'] as Map<String, dynamic>? ?? {};

    if (performance.isEmpty) {
      return const SizedBox.shrink();
    }

    final bestSelling = performance['best_selling_models'] as List? ?? [];
    final categoryBreakdown =
        performance['category_breakdown'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What\'s Selling',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Best-Selling Models
            if (bestSelling.isNotEmpty)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Best-Selling Models',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...bestSelling.take(5).map((product) {
                          final model = product['model'] as String;
                          final count = product['count'] as int;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$count sold',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            if (bestSelling.isNotEmpty && categoryBreakdown.isNotEmpty)
              const SizedBox(width: 16),
            // Category Breakdown
            if (categoryBreakdown.isNotEmpty)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.category,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Category Mix',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...categoryBreakdown.entries.take(5).map((entry) {
                          final category = entry.key;
                          final data = entry.value as Map<String, dynamic>;
                          final items = data['items'] as int;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    category,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$items items',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
