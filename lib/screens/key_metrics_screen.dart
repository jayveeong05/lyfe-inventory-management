import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dashboard_service.dart';
import 'transaction_discrepancy_screen.dart';

class KeyMetricsScreen extends StatefulWidget {
  const KeyMetricsScreen({super.key});

  @override
  State<KeyMetricsScreen> createState() => _KeyMetricsScreenState();
}

class _KeyMetricsScreenState extends State<KeyMetricsScreen> {
  final DashboardService _dashboardService = DashboardService();
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      final analytics = await _dashboardService.getDashboardAnalytics();
      if (mounted) {
        setState(() {
          _analytics = analytics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Metrics'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadAnalytics();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _analytics == null
          ? const Center(child: Text('Failed to load analytics'))
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Key metrics cards
                    _buildKeyMetricsSection(),
                    const SizedBox(height: 24),

                    // Inventory overview
                    _buildInventoryOverview(),
                    const SizedBox(height: 24),

                    // Sales & Orders
                    _buildSalesOverview(),
                    const SizedBox(height: 24),

                    // Monthly statistics
                    _buildMonthlyStats(),
                    const SizedBox(height: 24),

                    // Data Integrity section
                    _buildDataIntegritySection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKeyMetricsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key Metrics',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Items',
                _analytics!['totalInventoryItems'].toString(),
                Icons.inventory,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Active Stock',
                _analytics!['activeStock'].toString(),
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Total Orders',
                _analytics!['totalOrders'].toString(),
                Icons.receipt_long,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Transactions',
                _analytics!['totalTransactions'].toString(),
                Icons.swap_horiz,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.1),
        ),
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
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryOverview() {
    final activeStock = _analytics!['activeStock'] as int;
    final stockedOut = _analytics!['stockedOutItems'] as int;
    final total = activeStock + stockedOut;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inventory Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                total > 0
                                    ? '${((activeStock / total) * 100).toInt()}%'
                                    : '0%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$activeStock items'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                total > 0
                                    ? '${((stockedOut / total) * 100).toInt()}%'
                                    : '0%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              const Text(
                                'Stocked Out',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$stockedOut items'),
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

  Widget _buildSalesOverview() {
    final totalOrders = _analytics!['totalOrders'] as int? ?? 0;
    final invoicedOrders = _analytics!['invoicedOrders'] as int? ?? 0;
    final pendingOrders = _analytics!['pendingOrders'] as int? ?? 0;
    final issuedOrders = _analytics!['issuedOrders'] as int? ?? 0;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Orders & Sales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _buildStatusIndicator(
                    'Invoiced',
                    invoicedOrders.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
                Expanded(
                  child: _buildStatusIndicator(
                    'Pending',
                    pendingOrders.toString(),
                    Colors.orange,
                    Icons.pending,
                  ),
                ),
                Expanded(
                  child: _buildStatusIndicator(
                    'Issued',
                    issuedOrders.toString(),
                    Colors.blue,
                    Icons.local_shipping,
                  ),
                ),
                Expanded(
                  child: _buildStatusIndicator(
                    'Total Orders',
                    totalOrders.toString(),
                    Colors.purple,
                    Icons.receipt_long,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMonthlyStats() {
    final monthlyStats = _analytics!['monthlyStats'] as Map<String, dynamic>;
    final monthlyStockIn = monthlyStats['monthlyStockIn'] as int;
    final monthlyStockOut = monthlyStats['monthlyStockOut'] as int;
    final monthlyTotal = monthlyStats['monthlyTotal'] as int;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This Month (${DateFormat('MMMM y').format(DateTime.now())})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Stock In',
                    monthlyStockIn.toString(),
                    Icons.add_box,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Stock Out',
                    monthlyStockOut.toString(),
                    Icons.remove_circle_outline,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMonthlyStatCard(
                    'Total',
                    monthlyTotal.toString(),
                    Icons.swap_horiz,
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildDataIntegritySection() {
    final dataIntegrity = _analytics!['dataIntegrity'] as Map<String, dynamic>;
    final totalIssues = dataIntegrity['totalIssues'] as int;
    final lastChecked = dataIntegrity['lastChecked'] as DateTime;
    final summary = dataIntegrity['summary'] as Map<String, dynamic>;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  totalIssues > 0 ? Icons.warning : Icons.check_circle,
                  color: totalIssues > 0 ? Colors.orange : Colors.green,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Data Integrity Report',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: Text(
                    'Last checked: ${_formatTimeAgo(lastChecked)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: totalIssues > 0
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: totalIssues > 0
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.green.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    totalIssues > 0 ? Icons.error_outline : Icons.check,
                    color: totalIssues > 0 ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    totalIssues > 0
                        ? '$totalIssues data integrity issues found'
                        : 'All data integrity checks passed',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: totalIssues > 0
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),

            if (totalIssues > 0) ...[
              const SizedBox(height: 16),
              _buildIntegrityDetails(dataIntegrity),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntegrityDetails(Map<String, dynamic> dataIntegrity) {
    final deliveredAnalysis =
        dataIntegrity['deliveredAnalysis'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Delivered Analysis Section
        if (deliveredAnalysis['totalDeliveredTransactions'] > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Delivered Transaction Analysis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Firebase Query: ${deliveredAnalysis['totalDeliveredTransactions']} delivered transactions',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Inventory Management: ${deliveredAnalysis['deliveredInInventory']} delivered items',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Discrepancy: ${deliveredAnalysis['totalDeliveredTransactions'] - deliveredAnalysis['deliveredInInventory']} transactions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade700,
                  ),
                ),
                if (deliveredAnalysis['multipleDeliveredCount'] > 0)
                  Text(
                    'Multiple deliveries: ${deliveredAnalysis['multipleDeliveredCount']} duplicate transactions',
                    style: const TextStyle(fontSize: 12),
                  ),
                if ((deliveredAnalysis['orphanedDeliveredTransactions'] as List)
                    .isNotEmpty)
                  Text(
                    'Orphaned deliveries: ${(deliveredAnalysis['orphanedDeliveredTransactions'] as List).length} transactions without inventory',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const TransactionDiscrepancyScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
                label: Text(
                  'Find ${deliveredAnalysis['totalDeliveredTransactions'] - deliveredAnalysis['deliveredInInventory']}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _exportIntegrityReport(dataIntegrity),
                icon: const Icon(Icons.download),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIssueCard(
    String title,
    String description,
    int count,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  void _showDetailedReport(Map<String, dynamic> dataIntegrity) {
    final orphanedStockOuts =
        dataIntegrity['orphanedStockOuts'] as List<dynamic>;
    final missingStockIns = dataIntegrity['missingStockIns'] as List<dynamic>;
    final deliveredAnalysis =
        dataIntegrity['deliveredAnalysis'] as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Integrity Details'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Orphaned Stock-Outs'),
                    Tab(text: 'Missing Stock-Ins'),
                    Tab(text: 'Delivered Analysis'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildSerialList(
                        orphanedStockOuts,
                        'No orphaned stock-out transactions found.',
                      ),
                      _buildSerialList(
                        missingStockIns,
                        'No missing stock-in transactions found.',
                      ),
                      _buildDeliveredAnalysisTab(deliveredAnalysis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredAnalysisTab(Map<String, dynamic> deliveredAnalysis) {
    final totalDeliveredTransactions =
        deliveredAnalysis['totalDeliveredTransactions'] as int;
    final uniqueDeliveredSerials =
        deliveredAnalysis['uniqueDeliveredSerials'] as int;
    final deliveredInInventory =
        deliveredAnalysis['deliveredInInventory'] as int;
    final orphanedDeliveredTransactions =
        deliveredAnalysis['orphanedDeliveredTransactions'] as List<dynamic>;
    final multipleDeliveredCount =
        deliveredAnalysis['multipleDeliveredCount'] as int;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Statistics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivered Transaction Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildStatRow(
                  'Total Delivered Transactions:',
                  '$totalDeliveredTransactions',
                ),
                _buildStatRow(
                  'Unique Serial Numbers:',
                  '$uniqueDeliveredSerials',
                ),
                _buildStatRow(
                  'Items Currently Delivered:',
                  '$deliveredInInventory',
                ),
                _buildStatRow(
                  'Multiple Deliveries:',
                  '$multipleDeliveredCount',
                ),
                _buildStatRow(
                  'Orphaned Transactions:',
                  '${orphanedDeliveredTransactions.length}',
                ),
                const Divider(),
                _buildStatRow(
                  'Discrepancy:',
                  '${totalDeliveredTransactions - deliveredInInventory} transactions',
                  isHighlight: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Orphaned Delivered Transactions
          if (orphanedDeliveredTransactions.isNotEmpty) ...[
            const Text(
              'Orphaned Delivered Transactions:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'These ${orphanedDeliveredTransactions.length} serial numbers have delivered transactions but no inventory records:',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...orphanedDeliveredTransactions.map(
                    (serial) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            serial.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Explanation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why the discrepancy?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  '• Multiple deliveries: Some items were delivered, returned, then delivered again',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  '• Orphaned transactions: Delivered transactions for serial numbers not in inventory',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  '• Current status logic: Inventory Management shows current item status, not transaction count',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isHighlight ? Colors.red.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSerialList(List<dynamic> serials, String emptyMessage) {
    if (serials.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      itemCount: serials.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const Icon(Icons.inventory_2, size: 20),
          title: Text(serials[index].toString()),
          dense: true,
        );
      },
    );
  }

  void _exportIntegrityReport(Map<String, dynamic> dataIntegrity) {
    // TODO: Implement export functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export functionality will be implemented soon'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
