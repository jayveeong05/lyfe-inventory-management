import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/transaction_discrepancy_analyzer.dart';

class TransactionDiscrepancyScreen extends StatefulWidget {
  const TransactionDiscrepancyScreen({super.key});

  @override
  State<TransactionDiscrepancyScreen> createState() => _TransactionDiscrepancyScreenState();
}

class _TransactionDiscrepancyScreenState extends State<TransactionDiscrepancyScreen> {
  final TransactionDiscrepancyAnalyzer _analyzer = TransactionDiscrepancyAnalyzer();
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _runAnalysis,
          ),
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
    final orphanedTransactions = analysis['orphaned_transactions'] as List<Map<String, dynamic>>;
    final multipleDeliveryTransactions = analysis['multiple_delivery_transactions'] as List<Map<String, dynamic>>;
    final serialsWithMultipleDeliveries = analysis['serials_with_multiple_deliveries'] as Map<String, List<Map<String, dynamic>>>;

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
                  Text('📊 Analysis Summary', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  _buildSummaryRow('Total Delivered Transactions:', '${analysis['total_delivered_transactions']}'),
                  _buildSummaryRow('Currently Delivered Items:', '${analysis['currently_delivered_items']}'),
                  _buildSummaryRow('Discrepancy:', '${analysis['discrepancy']} transactions', isHighlight: true),
                  const Divider(),
                  _buildSummaryRow('Orphaned Transactions:', '${orphanedTransactions.length}'),
                  _buildSummaryRow('Multiple Delivery Transactions:', '${multipleDeliveryTransactions.length}'),
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
                    Text('🚨 Orphaned Transactions (${orphanedTransactions.length})', 
                         style: Theme.of(context).textTheme.titleLarge),
                    const Text('Delivered transactions without corresponding inventory records'),
                    const SizedBox(height: 12),
                    ...orphanedTransactions.map((transaction) => _buildTransactionCard(transaction)),
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
                    Text('🔄 Multiple Delivery Transactions (${multipleDeliveryTransactions.length})', 
                         style: Theme.of(context).textTheme.titleLarge),
                    const Text('Extra delivery transactions for items already delivered'),
                    const SizedBox(height: 12),
                    ...multipleDeliveryTransactions.map((transaction) => _buildTransactionCard(transaction)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false}) {
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('Serial: ${transaction['original_serial'] ?? 'N/A'}'),
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
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: transaction['document_id']));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Document ID copied to clipboard')),
            );
          },
        ),
      ),
    );
  }
}
