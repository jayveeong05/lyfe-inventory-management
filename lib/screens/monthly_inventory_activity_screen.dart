import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/monthly_inventory_service.dart';
import '../services/report_service.dart';

class MonthlyInventoryActivityScreen extends StatefulWidget {
  const MonthlyInventoryActivityScreen({super.key});

  @override
  State<MonthlyInventoryActivityScreen> createState() =>
      _MonthlyInventoryActivityScreenState();
}

class _MonthlyInventoryActivityScreenState
    extends State<MonthlyInventoryActivityScreen>
    with SingleTickerProviderStateMixin {
  final MonthlyInventoryService _service = MonthlyInventoryService();
  final ReportService _reportService = ReportService();

  Map<String, dynamic>? _reportData;
  List<Map<String, dynamic>> _availableMonths = [];
  Map<String, dynamic>? _selectedMonth;
  bool _isLoading = false;
  String? _error;

  // Tab controller for switching between summary and detailed views
  TabController? _tabController;

  // Detailed data
  List<Map<String, dynamic>> _stockInItems = [];
  List<Map<String, dynamic>> _stockOutItems = [];
  List<Map<String, dynamic>> _remainingItems = [];
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAvailableMonths();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableMonths() async {
    setState(() {
      _isLoading = true;
    });

    final months = await _service.getAvailableMonths();
    setState(() {
      _availableMonths = months;
      if (months.isNotEmpty) {
        _selectedMonth = months.first; // Select current/latest month
        _loadReport();
      } else {
        _isLoading = false;
      }
    });
  }

  Future<void> _loadReport() async {
    if (_selectedMonth == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _service.getMonthlyInventoryActivity(
      year: _selectedMonth!['year'],
      month: _selectedMonth!['month'],
    );

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _reportData = result['data'];
        _loadDetailedData(); // Load detailed data after summary
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _loadDetailedData() async {
    if (_selectedMonth == null) return;

    setState(() {
      _isLoadingDetails = true;
    });

    try {
      final year = _selectedMonth!['year'] as int;
      final month = _selectedMonth!['month'] as int;
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

      final stockInItems = await _service.getDetailedStockInData(
        startOfMonth,
        endOfMonth,
      );
      final stockOutItems = await _service.getDetailedStockOutData(
        startOfMonth,
        endOfMonth,
      );
      final remainingItems = await _getRemainingItems(endOfMonth);

      setState(() {
        _stockInItems = stockInItems;
        _stockOutItems = stockOutItems;
        _remainingItems = remainingItems;
        _isLoadingDetails = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingDetails = false;
      });
    }
  }

  Future<void> _exportReport() async {
    if (_reportData == null || _selectedMonth == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No data to export')));
      }
      return;
    }

    try {
      final filePath = await _reportService.exportMonthlyActivityToCSV(
        _reportData!,
        _stockInItems,
        _stockOutItems,
        _remainingItems,
        _selectedMonth!,
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
          icon: const Icon(Icons.check_circle, color: Colors.purple, size: 48),
          title: const Text('Export Successful!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your monthly activity report has been saved to:',
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
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.purple, size: 16),
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
        title: const Text('Monthly Inventory Activity'),
        backgroundColor: Colors.purple.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportReport,
            tooltip: 'Export to CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'Refresh Data',
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController!,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Summary', icon: Icon(Icons.analytics)),
                  Tab(text: 'Stock In', icon: Icon(Icons.add_circle_outline)),
                  Tab(
                    text: 'Stock Out',
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                  Tab(
                    text: 'Remaining',
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          // Month selector
          _buildMonthSelector(),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading data',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadReport,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _reportData == null
                ? const Center(child: Text('No data available'))
                : _tabController != null
                ? TabBarView(
                    controller: _tabController!,
                    children: [
                      _buildSummaryTab(),
                      _buildStockInTab(),
                      _buildStockOutTab(),
                      _buildRemainingTab(),
                    ],
                  )
                : _buildSummaryTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.blue),
          const SizedBox(width: 12),
          const Text(
            'Select Month:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<Map<String, dynamic>>(
              initialValue: _selectedMonth,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: _availableMonths.map((month) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: month,
                  child: Text(month['displayName']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMonth = value;
                });
                if (value != null) {
                  _loadReport();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_reportData == null) return const SizedBox();

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            _buildSummaryCards(),
            const SizedBox(height: 24),

            // Size breakdown
            _buildSizeBreakdown(),
            const SizedBox(height: 24),

            // Category breakdown
            _buildCategoryBreakdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _reportData!['summary'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Summary for ${_reportData!['monthName']} ${_reportData!['year']}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Stock In',
                summary['totalStockIn'].toString(),
                Icons.add_box,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Stock Out',
                summary['totalStockOut'].toString(),
                Icons.remove_circle_outline,
                Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Remaining',
                summary['totalRemaining'].toString(),
                Icons.inventory,
                Colors.blue,
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
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeBreakdown() {
    final sizeBreakdown = _reportData!['sizeBreakdown'] as List<dynamic>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breakdown by Panel Size',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Custom responsive table layout
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'Size',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Stock In',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Stock Out',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Remaining',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Data rows
                ...sizeBreakdown.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final remaining = item['remaining'] as int;
                  final isLastRow = index == sizeBreakdown.length - 1;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: index % 2 == 0
                          ? Colors.white
                          : Colors.grey.shade50,
                      borderRadius: isLastRow
                          ? const BorderRadius.only(
                              bottomLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            )
                          : null,
                      border: isLastRow
                          ? null
                          : Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            item['size'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            item['stockIn'].toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: item['stockIn'] > 0
                                  ? Colors.green.shade600
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            item['stockOut'].toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: item['stockOut'] > 0
                                  ? Colors.red.shade600
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            remaining.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: remaining > 0
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    final categoryBreakdown =
        _reportData!['categoryBreakdown'] as List<dynamic>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breakdown by Category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...categoryBreakdown.map<Widget>((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        item['category'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      child: _buildCategoryMetric(
                        'In',
                        item['stockIn'],
                        Colors.green,
                      ),
                    ),
                    Expanded(
                      child: _buildCategoryMetric(
                        'Out',
                        item['stockOut'],
                        Colors.red,
                      ),
                    ),
                    Expanded(
                      child: _buildCategoryMetric(
                        'Remaining',
                        item['remaining'],
                        item['remaining'] >= 0 ? Colors.blue : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryMetric(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildStockInTab() {
    if (_isLoadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stockInItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No stock in items for this month',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Group items by category and size
    final groupedItems = _groupStockInItems(_stockInItems);

    return RefreshIndicator(
      onRefresh: _loadDetailedData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock In Items (${_stockInItems.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...groupedItems.entries.map((categoryEntry) {
              final category = categoryEntry.key;
              final sizeGroups = categoryEntry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                  ...sizeGroups.entries.map((sizeEntry) {
                    final size = sizeEntry.key;
                    final items = sizeEntry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Size Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 16,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$size (${items.length} items)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items in this size
                        ...items.map((item) => _buildStockInItemCard(item)),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Group stock in items by category and size
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupStockInItems(
    List<Map<String, dynamic>> items,
  ) {
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

    for (final item in items) {
      final category =
          item['equipment_category'] as String? ?? 'Unknown Category';
      final size = item['size'] as String? ?? 'Unknown Size';

      grouped.putIfAbsent(category, () => {});
      grouped[category]!.putIfAbsent(size, () => []);
      grouped[category]![size]!.add(item);
    }

    return grouped;
  }

  /// Build individual stock in item card with improved layout
  Widget _buildStockInItemCard(Map<String, dynamic> item) {
    final date = item['date']?.toDate();
    final dateStr = date != null
        ? DateFormat('MMM dd, yyyy').format(date)
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with stock in indicator and source
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          'STOCK IN',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.add_circle_outline,
                        size: 16,
                        color: Colors.green.shade400,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade300, width: 1),
                  ),
                  child: Text(
                    item['source'] ?? 'Manual',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Serial number (prominent)
            Text(
              item['serial_number'] ?? 'N/A',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Product details row
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.inventory_outlined,
                    label: 'Batch',
                    value: item['batch'] ?? 'N/A',
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: dateStr,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),

            // Remarks section (if available)
            if (item['remark']?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _buildRemarksCard(item['remark']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockOutTab() {
    if (_isLoadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stockOutItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.remove_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No stock out items for this month',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Group items by category and size
    final groupedItems = _groupStockOutItems(_stockOutItems);

    return RefreshIndicator(
      onRefresh: _loadDetailedData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock Out Items (${_stockOutItems.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...groupedItems.entries.map((categoryEntry) {
              final category = categoryEntry.key;
              final sizeGroups = categoryEntry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                  ...sizeGroups.entries.map((sizeEntry) {
                    final size = sizeEntry.key;
                    final items = sizeEntry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Size Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 16,
                                color: Colors.red.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$size (${items.length} items)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items in this size
                        ...items.map((item) => _buildStockOutItemCard(item)),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Group stock out items by category and size
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupStockOutItems(
    List<Map<String, dynamic>> items,
  ) {
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

    for (final item in items) {
      final category =
          item['equipment_category'] as String? ?? 'Unknown Category';
      final size = item['size'] as String? ?? 'Unknown Size';

      grouped.putIfAbsent(category, () => {});
      grouped[category]!.putIfAbsent(size, () => []);
      grouped[category]![size]!.add(item);
    }

    return grouped;
  }

  /// Build individual stock out item card with improved layout
  Widget _buildStockOutItemCard(Map<String, dynamic> item) {
    final date = item['date']?.toDate();
    final dateStr = date != null
        ? DateFormat('MMM dd, yyyy').format(date)
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with transaction ID and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          'TXN #${item['transaction_id']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.remove_circle_outline,
                        size: 16,
                        color: Colors.red.shade400,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(item['status']),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusBorderColor(item['status']),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    item['status'] ?? 'N/A',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getStatusTextColor(item['status']),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Serial number (prominent)
            Text(
              item['serial_number'] ?? 'N/A',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Product details row
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.category_outlined,
                    label: 'Model',
                    value: item['model'] ?? 'N/A',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'Qty',
                  value: '${item['quantity'] ?? 1}',
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Customer information
            _buildCustomerInfoCard(item),
            const SizedBox(height: 8),

            // Location and date row
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: item['location'] ?? 'N/A',
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: dateStr,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build info chip with icon and label
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _getColorShade700(color)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getColorShade700(color),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Build customer information card
  Widget _buildCustomerInfoCard(Map<String, dynamic> item) {
    final dealer = item['customer_dealer'] as String?;
    final client = item['customer_client'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.business_outlined,
                size: 16,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Customer Information',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (dealer != null && dealer.isNotEmpty && dealer != 'N/A') ...[
            _buildCustomerRow('Dealer', dealer, Icons.store_outlined),
            if (client != null && client.isNotEmpty && client != 'N/A')
              const SizedBox(height: 4),
          ],
          if (client != null && client.isNotEmpty && client != 'N/A')
            _buildCustomerRow('Client', client, Icons.person_outline),
          if ((dealer == null || dealer.isEmpty || dealer == 'N/A') &&
              (client == null || client.isEmpty || client == 'N/A'))
            _buildCustomerRow('Customer', 'N/A', Icons.help_outline),
        ],
      ),
    );
  }

  /// Build individual customer row
  Widget _buildCustomerRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.blue.shade600),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Get status border color
  Color _getStatusBorderColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'delivered':
        return Colors.green.shade300;
      case 'reserved':
        return Colors.orange.shade300;
      case 'demo':
        return Colors.purple.shade300;
      case 'active':
        return Colors.blue.shade300;
      default:
        return Colors.grey.shade300;
    }
  }

  /// Get status text color
  Color _getStatusTextColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'delivered':
        return Colors.green.shade700;
      case 'reserved':
        return Colors.orange.shade700;
      case 'demo':
        return Colors.purple.shade700;
      case 'active':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  /// Get color shade 700 equivalent
  Color _getColorShade700(Color color) {
    if (color == Colors.blue) return Colors.blue.shade700;
    if (color == Colors.green) return Colors.green.shade700;
    if (color == Colors.purple) return Colors.purple.shade700;
    if (color == Colors.orange) return Colors.orange.shade700;
    if (color == Colors.red) return Colors.red.shade700;
    if (color == Colors.indigo) return Colors.indigo.shade700;
    return Colors.grey.shade700;
  }

  /// Build remarks card for stock in items
  Widget _buildRemarksCard(String remark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.note_outlined, size: 16, color: Colors.amber.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remarks',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  remark,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'delivered':
        return Colors.green.shade100;
      case 'reserved':
        return Colors.orange.shade100;
      case 'demo':
        return Colors.purple.shade100;
      case 'inactive':
        return Colors.grey.shade100;
      default:
        return Colors.blue.shade100;
    }
  }

  /// Get remaining items (items that are currently active in inventory)
  Future<List<Map<String, dynamic>>> _getRemainingItems(
    DateTime endDate,
  ) async {
    try {
      // Get all inventory items
      final inventorySnapshot = await FirebaseFirestore.instance
          .collection('inventory')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // Get all stock out transactions to determine which items are no longer available
      final stockOutSnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // Create a set of serial numbers that have been stocked out
      final stockedOutSerials = <String>{};
      for (final doc in stockOutSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        final serialNumber = data['serial_number'] as String?;

        // Only consider items that are not 'Active' as stocked out
        if (status != null && status != 'Active' && serialNumber != null) {
          stockedOutSerials.add(serialNumber);
        }
      }

      // Filter inventory items to get only remaining ones
      List<Map<String, dynamic>> remainingItems = [];
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null && !stockedOutSerials.contains(serialNumber)) {
          remainingItems.add({
            'id': doc.id,
            'serial_number': serialNumber,
            'equipment_category': data['equipment_category'] ?? 'N/A',
            'model': _extractModelFromSerial(serialNumber),
            'size': data['size'] ?? 'Unknown',
            'batch': data['batch'] ?? 'N/A',
            'date': data['date'],
            'remark': data['remark'] ?? '',
            'source': data['source'] ?? 'Manual',
          });
        }
      }

      return remainingItems;
    } catch (e) {
      return [];
    }
  }

  /// Extract model from serial number (helper method)
  String _extractModelFromSerial(String serialNumber) {
    // Extract model from serial number (e.g., "65M6APRO-244H90171-000011" -> "65M6APRO")
    final parts = serialNumber.split('-');
    return parts.isNotEmpty ? parts[0] : 'N/A';
  }

  /// Format source for display
  String _formatSource(String source) {
    switch (source.toLowerCase()) {
      case 'stock_in_manual':
        return 'Manual';
      case 'inventory_dev.xlsx':
        return 'Import';
      case 'manual':
        return 'Manual';
      default:
        return source
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (word) => word.isNotEmpty
                  ? word[0].toUpperCase() + word.substring(1)
                  : word,
            )
            .join(' ');
    }
  }

  /// Build remaining tab
  Widget _buildRemainingTab() {
    if (_isLoadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_remainingItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No remaining items for this period',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Group items by category and size
    final groupedItems = _groupRemainingItems(_remainingItems);

    return RefreshIndicator(
      onRefresh: _loadDetailedData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Remaining Items (${_remainingItems.length})',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Grouped items
            ...groupedItems.entries.map((categoryEntry) {
              final category = categoryEntry.key;
              final sizeGroups = categoryEntry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 20,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${sizeGroups.values.fold<int>(0, (total, items) => total + items.length)} items',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Size groups
                  ...sizeGroups.entries.map((sizeEntry) {
                    final size = sizeEntry.key;
                    final items = sizeEntry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Size header
                        Container(
                          margin: const EdgeInsets.only(left: 16, bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.straighten_outlined,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$size (${items.length} items)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items in this size
                        ...items.map((item) => _buildRemainingItemCard(item)),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Group remaining items by category and size
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupRemainingItems(
    List<Map<String, dynamic>> items,
  ) {
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

    for (final item in items) {
      final category =
          item['equipment_category'] as String? ?? 'Unknown Category';
      final size = item['size'] as String? ?? 'Unknown Size';

      grouped.putIfAbsent(category, () => {});
      grouped[category]!.putIfAbsent(size, () => []);
      grouped[category]![size]!.add(item);
    }

    return grouped;
  }

  /// Build individual remaining item card
  Widget _buildRemainingItemCard(Map<String, dynamic> item) {
    final date = item['date']?.toDate();
    final dateStr = date != null
        ? DateFormat('MMM dd, yyyy').format(date)
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with remaining indicator and warranty
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'AVAILABLE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: Colors.blue.shade400,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.purple.shade300, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.source_outlined,
                        size: 14,
                        color: Colors.purple.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatSource(item['source'] ?? 'Manual'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Serial number (prominent)
            Text(
              item['serial_number'] ?? 'N/A',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Product details row
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.category_outlined,
                    label: 'Model',
                    value: item['model'] ?? 'N/A',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.inventory_outlined,
                    label: 'Batch',
                    value: item['batch'] ?? 'N/A',
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Date added
            _buildInfoChip(
              icon: Icons.calendar_today_outlined,
              label: 'Added',
              value: dateStr,
              color: Colors.orange,
            ),

            // Remarks section (if available)
            if (item['remark']?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _buildRemarksCard(item['remark']),
            ],
          ],
        ),
      ),
    );
  }
}
