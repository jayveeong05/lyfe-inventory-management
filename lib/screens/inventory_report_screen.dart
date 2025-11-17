import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/report_service.dart';

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  final ReportService _reportService = ReportService();

  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  String? _error;

  // Filter variables
  String? _selectedCategory;
  String? _selectedStatus;
  String? _selectedLocation;

  List<String> _categories = [];
  List<String> _locations = [];
  final List<String> _statusOptions = ['Active', 'Reserved', 'Delivered'];

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
    final categories = await _reportService.getCategoryList();
    final locations = await _reportService.getLocationList();

    setState(() {
      _categories = categories;
      _locations = locations;
    });
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _reportService.getInventoryReport(
      category: _selectedCategory,
      status: _selectedStatus,
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
      final filePath = await _reportService.exportInventoryReportToCSV(
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
                'Your inventory report has been saved to:',
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
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.green, size: 16),
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
        title: const Text('Inventory Report'),
        backgroundColor: Colors.green.shade600,
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
            _buildSummaryCards(),
            const SizedBox(height: 20),
            _buildStatusBreakdown(),
            const SizedBox(height: 20),
            _buildCategoryBreakdown(),
            const SizedBox(height: 20),
            _buildLocationBreakdown(),
            const SizedBox(height: 20),
            _buildAgingAnalysis(),
            const SizedBox(height: 20),
            _buildInventoryItems(),
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
          'Inventory Summary',
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
              'Total Items',
              '${summary['total_items'] ?? 0}',
              Icons.inventory,
              Colors.blue,
            ),
            _buildSummaryCard(
              'Active Items',
              '${summary['active_items'] ?? 0}',
              Icons.check_circle,
              Colors.green,
            ),
            _buildSummaryCard(
              'Reserved Items',
              '${summary['reserved_items'] ?? 0}',
              Icons.pending,
              Colors.orange,
            ),
            _buildSummaryCard(
              'Delivered Items',
              '${summary['delivered_items'] ?? 0}',
              Icons.local_shipping,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.category, color: Colors.indigo.shade600),
                      const SizedBox(height: 8),
                      Text(
                        '${summary['categories_count'] ?? 0}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                      const Text('Categories', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.location_on, color: Colors.teal.shade600),
                      const SizedBox(height: 8),
                      Text(
                        '${summary['locations_count'] ?? 0}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade600,
                        ),
                      ),
                      const Text('Locations', style: TextStyle(fontSize: 12)),
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

  Widget _buildStatusBreakdown() {
    final statusBreakdown =
        _reportData!['status_breakdown'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status Breakdown',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: statusBreakdown.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No status data available'),
                    ),
                  ]
                : statusBreakdown.map((status) {
                    final statusName = status['status'] as String? ?? 'Unknown';
                    final count = status['count'] as int? ?? 0;

                    MaterialColor statusColor;
                    IconData statusIcon;

                    switch (statusName) {
                      case 'Active':
                        statusColor = Colors.green;
                        statusIcon = Icons.check_circle;
                        break;
                      case 'Reserved':
                        statusColor = Colors.orange;
                        statusIcon = Icons.pending;
                        break;
                      case 'Delivered':
                        statusColor = Colors.purple;
                        statusIcon = Icons.local_shipping;
                        break;
                      default:
                        statusColor = Colors.grey;
                        statusIcon = Icons.help;
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.shade100,
                        child: Icon(statusIcon, color: statusColor.shade600),
                      ),
                      title: Text(statusName),
                      trailing: Text(
                        '$count items',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown() {
    final categoryBreakdown =
        _reportData!['category_breakdown'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category Breakdown',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: categoryBreakdown.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No category data available'),
                    ),
                  ]
                : categoryBreakdown.map((category) {
                    final categoryName =
                        category['category'] as String? ?? 'Unknown';
                    final total = category['total'] as int? ?? 0;
                    final active = category['active'] as int? ?? 0;
                    final stockedOut = category['stocked_out'] as int? ?? 0;
                    final activePercentage =
                        category['active_percentage'] as String? ?? '0.0';

                    return ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        child: Icon(
                          Icons.category,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                      title: Text(categoryName),
                      subtitle: Text(
                        '$total total items • $activePercentage% active',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    '$active',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade600,
                                    ),
                                  ),
                                  const Text(
                                    'Active',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    '$stockedOut',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade600,
                                    ),
                                  ),
                                  const Text(
                                    'Stocked Out',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    '$total',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade600,
                                    ),
                                  ),
                                  const Text(
                                    'Total',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
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

  Widget _buildLocationBreakdown() {
    final locationBreakdown =
        _reportData!['location_breakdown'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Location Breakdown',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: locationBreakdown.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No location data available'),
                    ),
                  ]
                : locationBreakdown.map((location) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: Icon(
                          Icons.location_on,
                          color: Colors.teal.shade600,
                        ),
                      ),
                      title: Text(location['location'] ?? 'Unknown'),
                      trailing: Text(
                        '${location['count']} items',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAgingAnalysis() {
    final agingAnalysis =
        _reportData!['aging_analysis'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aging Analysis',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: agingAnalysis.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No aging data available'),
                    ),
                  ]
                : agingAnalysis.map((age) {
                    final ageGroup = age['age_group'] as String? ?? 'Unknown';
                    final count = age['count'] as int? ?? 0;

                    MaterialColor ageColor;
                    IconData ageIcon;

                    if (ageGroup.contains('0-7')) {
                      ageColor = Colors.green;
                      ageIcon = Icons.new_releases;
                    } else if (ageGroup.contains('8-30')) {
                      ageColor = Colors.blue;
                      ageIcon = Icons.schedule;
                    } else if (ageGroup.contains('31-90')) {
                      ageColor = Colors.orange;
                      ageIcon = Icons.warning;
                    } else {
                      ageColor = Colors.red;
                      ageIcon = Icons.error;
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: ageColor.shade100,
                        child: Icon(ageIcon, color: ageColor.shade600),
                      ),
                      title: Text(ageGroup),
                      trailing: Text(
                        '$count items',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryItems() {
    final inventoryItems =
        _reportData!['inventory_items'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Inventory Items',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              '${inventoryItems.length} items',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: inventoryItems.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No inventory items found'),
                    ),
                  ]
                : inventoryItems.take(20).map((item) {
                    final serialNumber =
                        item['serial_number'] as String? ?? 'Unknown';
                    final category =
                        item['equipment_category'] as String? ?? 'Unknown';
                    final model = item['model'] as String? ?? 'Unknown';
                    final currentStatus =
                        item['current_status'] as String? ?? 'Unknown';
                    final currentLocation =
                        item['current_location'] as String? ?? 'Unknown';
                    final lastActivity = item['last_activity'] as DateTime?;

                    MaterialColor statusColor;
                    IconData statusIcon;

                    switch (currentStatus) {
                      case 'Active':
                        statusColor = Colors.green;
                        statusIcon = Icons.check_circle;
                        break;
                      case 'Reserved':
                        statusColor = Colors.orange;
                        statusIcon = Icons.pending;
                        break;
                      case 'Delivered':
                        statusColor = Colors.purple;
                        statusIcon = Icons.local_shipping;
                        break;
                      default:
                        statusColor = Colors.grey;
                        statusIcon = Icons.help;
                    }

                    return ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.shade100,
                        child: Icon(statusIcon, color: statusColor.shade600),
                      ),
                      title: Text(
                        serialNumber,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$category • $model'),
                          Text(
                            'Status: $currentStatus • Location: $currentLocation',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (lastActivity != null)
                                Text(
                                  'Last Activity: ${DateFormat('MMM dd, yyyy HH:mm').format(lastActivity)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Transaction History:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...((item['transaction_history']
                                          as List<dynamic>?) ??
                                      [])
                                  .take(3)
                                  .map((transaction) {
                                    final type =
                                        transaction['type'] as String? ??
                                        'Unknown';
                                    final status =
                                        transaction['status'] as String? ??
                                        'Unknown';

                                    // Handle uploaded_at which could be Timestamp or String
                                    DateTime? uploadedAtDate;
                                    final uploadedAtValue =
                                        transaction['uploaded_at'];
                                    if (uploadedAtValue != null) {
                                      if (uploadedAtValue is Timestamp) {
                                        uploadedAtDate = uploadedAtValue
                                            .toDate();
                                      } else if (uploadedAtValue is String) {
                                        try {
                                          uploadedAtDate = DateTime.parse(
                                            uploadedAtValue,
                                          );
                                        } catch (e) {
                                          // Ignore parse errors
                                        }
                                      }
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            type == 'Stock_In'
                                                ? Icons.add
                                                : Icons.remove,
                                            size: 16,
                                            color: type == 'Stock_In'
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '$type - $status',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (uploadedAtDate != null)
                                            Text(
                                              DateFormat(
                                                'MMM dd',
                                              ).format(uploadedAtDate),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
          ),
        ),
        if (inventoryItems.length > 20)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Showing first 20 of ${inventoryItems.length} items',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Inventory Report'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category filter
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All Categories'),
                  ),
                  ..._categories.map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Status filter
              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All Statuses'),
                  ),
                  ..._statusOptions.map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value;
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
                _selectedCategory = null;
                _selectedStatus = null;
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
