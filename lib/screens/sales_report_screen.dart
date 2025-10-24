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
              const Text(
                'Your sales report has been saved to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  filePath,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'How to open the CSV file:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. Go to Downloads folder in your file manager'),
              const Text('2. Find the CSV file and tap on it'),
              const Text('3. If it shows "Can\'t open file":'),
              const Text('   • Tap "Open with" or "Share"'),
              const Text('   • Choose Excel, Sheets, or WPS Office'),
              const Text('   • Install a spreadsheet app if needed'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recommended apps: Microsoft Excel, Google Sheets, WPS Office',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
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
    final purchaseOrders =
        _reportData!['purchase_orders'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Purchase Orders',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: purchaseOrders.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No purchase orders found'),
                    ),
                  ]
                : purchaseOrders.take(10).map((po) {
                    final status = po['status'] as String? ?? 'Unknown';
                    final createdDate = po['created_date'] as Timestamp?;

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
                      title: Text(po['po_number'] ?? 'Unknown PO'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(po['customer_dealer'] ?? 'Unknown Customer'),
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
                            '${po['total_items'] ?? 0} items',
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
      builder: (context) => AlertDialog(
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
                initialValue: _selectedCustomer,
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
                initialValue: _selectedLocation,
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
              setState(() {
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
      ),
    );
  }
}
