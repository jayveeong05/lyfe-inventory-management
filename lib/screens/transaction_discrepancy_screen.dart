import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/transaction_discrepancy_analyzer.dart';

class TransactionDiscrepancyScreen extends StatefulWidget {
  const TransactionDiscrepancyScreen({super.key});

  @override
  State<TransactionDiscrepancyScreen> createState() =>
      _TransactionDiscrepancyScreenState();
}

class _TransactionDiscrepancyScreenState
    extends State<TransactionDiscrepancyScreen> {
  final TransactionDiscrepancyAnalyzer _analyzer =
      TransactionDiscrepancyAnalyzer();
  Map<String, dynamic>? _analysisResult;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _analyzer.findDiscrepantTransactions();

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _analysisResult = result['analysis'];
      } else {
        _error = result['error'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Discrepancy Analysis'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _runAnalysis),
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
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _runAnalysis,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _analysisResult != null
          ? _buildAnalysisResults()
          : const Center(child: Text('No data available')),
    );
  }

  Widget _buildAnalysisResults() {
    final analysis = _analysisResult!;
    final orphanedTransactions =
        analysis['orphaned_transactions'] as List<Map<String, dynamic>>;
    final multipleDeliveryTransactions =
        analysis['multiple_delivery_transactions']
            as List<Map<String, dynamic>>;
    final deliveredSerialsNotCurrentlyDelivered =
        analysis['delivered_serials_not_currently_delivered'] as List<String>;
    final breakdown = analysis['breakdown'] as Map<String, dynamic>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 Comprehensive Analysis',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  _buildSummaryRow(
                    'Firebase Delivered Count:',
                    '${analysis['firebase_delivered_count']}',
                  ),
                  _buildSummaryRow(
                    'Inventory Management Count:',
                    '${analysis['inventory_management_delivered_count']}',
                  ),
                  _buildSummaryRow(
                    'Discrepancy:',
                    '${analysis['discrepancy']} transactions',
                    isHighlight: true,
                  ),
                  const Divider(),
                  _buildSummaryRow(
                    'Total Inventory Items:',
                    '${analysis['total_inventory_items']}',
                  ),
                  _buildSummaryRow(
                    'Unique Delivered Serials:',
                    '${analysis['unique_delivered_serials']}',
                  ),
                  const Divider(),
                  Text(
                    '🔍 Discrepancy Breakdown:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    '• Orphaned Transactions:',
                    '${breakdown['orphaned_count']}',
                  ),
                  _buildSummaryRow(
                    '• Multiple Deliveries:',
                    '${breakdown['multiple_delivery_count']}',
                  ),
                  _buildSummaryRow(
                    '• Delivered but Not 1+1 Pattern:',
                    '${breakdown['serials_delivered_but_not_current']}',
                  ),
                  _buildSummaryRow(
                    '• With Inventory Records:',
                    '${breakdown['delivered_with_inventory_count']}',
                  ),
                  _buildSummaryRow(
                    '• Without Inventory Records:',
                    '${breakdown['delivered_without_inventory_count']}',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Orphaned Transactions
          if (orphanedTransactions.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 Orphaned Transactions (${orphanedTransactions.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Delivered transactions without corresponding inventory records',
                    ),
                    const SizedBox(height: 12),
                    ...orphanedTransactions.map(
                      (transaction) => _buildTransactionCard(transaction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Multiple Delivery Transactions
          if (multipleDeliveryTransactions.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔄 Multiple Delivery Transactions (${multipleDeliveryTransactions.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Extra delivery transactions for items already delivered',
                    ),
                    const SizedBox(height: 12),
                    ...multipleDeliveryTransactions.map(
                      (transaction) => _buildTransactionCard(transaction),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Delivered but Not Currently Delivered
          if (deliveredSerialsNotCurrentlyDelivered.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ Delivered Transactions but Not 1+1 Pattern (${deliveredSerialsNotCurrentlyDelivered.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Items with delivered transactions but do not follow the simple 1 Stock_In + 1 Stock_Out pattern',
                    ),
                    const SizedBox(height: 12),
                    ...deliveredSerialsNotCurrentlyDelivered.map((serial) {
                      final displaySerial = serial.toUpperCase();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text('Serial: $displaySerial'),
                          subtitle: const Text(
                            'Has delivered transactions but does not follow 1 Stock_In + 1 Stock_Out pattern',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy Serial Number',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: displaySerial),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Serial number copied to clipboard',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final serialNumber = transaction['original_serial'] ?? 'N/A';
    final displaySerial = serialNumber != 'N/A'
        ? serialNumber.toUpperCase()
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('Serial: $displaySerial'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document ID: ${transaction['document_id']}'),
            Text('Transaction ID: ${transaction['transaction_id'] ?? 'N/A'}'),
            Text('Category: ${transaction['equipment_category'] ?? 'N/A'}'),
            Text('Model: ${transaction['model'] ?? 'N/A'}'),
            Text('Status: ${transaction['status'] ?? 'N/A'}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Copy Serial Number Button
            IconButton(
              icon: const Icon(Icons.content_copy, size: 20),
              tooltip: 'Copy Serial Number',
              onPressed: () {
                final copySerial = serialNumber != 'N/A'
                    ? serialNumber.toUpperCase()
                    : serialNumber;
                Clipboard.setData(ClipboardData(text: copySerial));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Serial number copied to clipboard'),
                  ),
                );
              },
            ),
            // Copy Document ID Button
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: 'Copy Document ID',
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: transaction['document_id']),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Document ID copied to clipboard'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
