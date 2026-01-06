import 'package:flutter/material.dart';
import '../services/report_service.dart';

class DemoReportScreen extends StatefulWidget {
  const DemoReportScreen({super.key});

  @override
  State<DemoReportScreen> createState() => _DemoReportScreenState();
}

class _DemoReportScreenState extends State<DemoReportScreen> {
  final ReportService _reportService = ReportService();

  Map<String, dynamic>? _reportData;
  bool _isLoading = false;
  bool _isExporting = false;

  String? _selectedCustomer;
  String? _selectedCategory;
  bool _overdueOnly = false;
  int _overdueThreshold = 30; // User-configurable threshold

  List<String> _customers = [];
  List<String> _categories = [];

  // Track expanded groups
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _reportService.getDemoTrackingReport(
        customerFilter: _selectedCustomer,
        categoryFilter: _selectedCategory,
        overdueOnly: _overdueOnly,
        overdueThresholdDays: _overdueThreshold,
      );

      if (result['success'] == true) {
        // Extract unique customers and categories for filters
        final categoryBreakdown = result['category_breakdown'] as List? ?? [];

        // Get unique customers from grouped demos
        final groupedDemos = result['grouped_demos'] as List? ?? [];
        final uniqueCustomers = <String>{};
        for (final group in groupedDemos) {
          final dealer = group['customer_dealer'] as String?;
          if (dealer != null && dealer.isNotEmpty) {
            uniqueCustomers.add(dealer);
          }
        }

        setState(() {
          _reportData = result;
          _customers = uniqueCustomers.toList()..sort();
          _categories = categoryBreakdown
              .map((c) => c['category'] as String)
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['error'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToCSV() async {
    if (_reportData == null) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final filePath = await _reportService.exportDemoTrackingReportToCSV(
        _reportData!,
      );

      setState(() {
        _isExporting = false;
      });

      if (mounted && filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report exported to: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to export report'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isExporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showThresholdDialog() {
    int tempThreshold = _overdueThreshold;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set Overdue Threshold'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Items out for more than $tempThreshold days are marked as overdue.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Days:', style: TextStyle(fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: tempThreshold > 1
                                ? () => setState(() => tempThreshold--)
                                : null,
                          ),
                          Container(
                            width: 60,
                            alignment: Alignment.center,
                            child: Text(
                              '$tempThreshold',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: tempThreshold < 365
                                ? () => setState(() => tempThreshold++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    this.setState(() {
                      _overdueThreshold = tempThreshold;
                    });
                    _loadReport();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _reportData?['summary'] as Map<String, dynamic>?;
    final groupedDemos = _reportData?['grouped_demos'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Tracking Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Set Overdue Threshold',
            onPressed: _showThresholdDialog,
          ),
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.download),
            tooltip: 'Export to CSV',
            onPressed: _isExporting ? null : _exportToCSV,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    if (summary != null) ...[
                      _buildSummaryCards(summary),
                      const SizedBox(height: 24),
                    ],

                    // Filters
                    _buildFilters(),
                    const SizedBox(height: 16),

                    // Grouped Demos List
                    Text(
                      'Demo Groups (${groupedDemos.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (groupedDemos.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No active demo items',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...groupedDemos.map((group) => _buildGroupCard(group)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> summary) {
    final totalItems = summary['total_items_out'] ?? 0;
    final totalCustomers = summary['total_customers'] ?? 0;
    final overdueCount = summary['overdue_count'] ?? 0;
    final averageDays = summary['average_days_out'] ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildSummaryCard(
          'Total Items Out',
          '$totalItems',
          Icons.inventory_2,
          Colors.blue,
        ),
        _buildSummaryCard(
          'Total Customers',
          '$totalCustomers',
          Icons.people,
          Colors.green,
        ),
        _buildSummaryCard(
          'Overdue Items',
          '$overdueCount',
          Icons.warning_amber,
          Colors.orange,
        ),
        _buildSummaryCard(
          'Avg Days Out',
          '$averageDays',
          Icons.calendar_today,
          Colors.purple,
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
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Customer Filter
            DropdownButtonFormField<String>(
              value: _selectedCustomer,
              decoration: const InputDecoration(
                labelText: 'Customer',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Customers'),
                ),
                ..._customers.map(
                  (customer) =>
                      DropdownMenuItem(value: customer, child: Text(customer)),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCustomer = value;
                });
                _loadReport();
              },
            ),
            const SizedBox(height: 12),

            // Category Filter
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Categories'),
                ),
                ..._categories.map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value;
                });
                _loadReport();
              },
            ),
            const SizedBox(height: 12),

            // Overdue Only Toggle
            SwitchListTile(
              title: const Text('Show Overdue Only'),
              subtitle: Text('> $_overdueThreshold days'),
              value: _overdueOnly,
              onChanged: (value) {
                setState(() {
                  _overdueOnly = value;
                });
                _loadReport();
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final groupKey = group['group_key'] as String? ?? '';
    final customerDealer = group['customer_dealer'] as String? ?? 'Unknown';
    final customerClient = group['customer_client'] as String? ?? '';
    final totalItems = group['total_items'] as int? ?? 0;
    final overdueItems = group['overdue_items'] as int? ?? 0;
    final oldestDays = group['oldest_days'] as int? ?? 0;
    final items = group['items'] as List? ?? [];
    final demoNumbers = group['demo_numbers'] as Set? ?? <String>{};

    final isExpanded = _expandedGroups.contains(groupKey);
    final hasOverdue = overdueItems > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: hasOverdue ? Colors.orange.shade50 : null,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: hasOverdue ? Colors.orange : Colors.blue,
              child: Text(
                '$totalItems',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              customerClient.isNotEmpty
                  ? '$customerDealer → $customerClient'
                  : customerDealer,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('$totalItems item${totalItems > 1 ? 's' : ''} out'),
                if (hasOverdue)
                  Text(
                    '$overdueItems overdue',
                    style: const TextStyle(color: Colors.orange),
                  ),
                if (demoNumbers.isNotEmpty)
                  Text(
                    'Demo: ${demoNumbers.join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$oldestDays days',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasOverdue ? Colors.orange : null,
                      ),
                    ),
                    const Text(
                      'oldest',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedGroups.remove(groupKey);
                } else {
                  _expandedGroups.add(groupKey);
                }
              });
            },
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const Text(
                    'Items:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((item) => _buildItemTile(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final serialNumber = item['serial_number'] ?? '';
    final category = item['equipment_category'] ?? '';
    final model = item['model'] ?? '';
    final daysOut = item['days_out'] as int? ?? 0;
    final isOverdue = item['is_overdue'] as bool? ?? false;
    final dateSent = item['date_sent'] as DateTime?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOverdue ? Colors.orange.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  serialNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isOverdue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'OVERDUE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('$category - $model', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$daysOut days out',
                style: TextStyle(
                  fontSize: 11,
                  color: isOverdue ? Colors.orange : Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (dateSent != null)
                Text(
                  '${dateSent.day}/${dateSent.month}/${dateSent.year}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
