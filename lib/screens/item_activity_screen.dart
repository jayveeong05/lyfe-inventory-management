import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/inventory_management_service.dart';

class ItemActivityScreen extends StatefulWidget {
  final String serialNumber;

  const ItemActivityScreen({super.key, required this.serialNumber});

  @override
  State<ItemActivityScreen> createState() => _ItemActivityScreenState();
}

class _ItemActivityScreenState extends State<ItemActivityScreen> {
  final InventoryManagementService _service = InventoryManagementService();

  List<Map<String, dynamic>> _activities = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.getItemActivityHistory(widget.serialNumber);

      if (result['success'] == true) {
        setState(() {
          _activities = List<Map<String, dynamic>>.from(
            result['activities'] ?? [],
          );
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Failed to load history';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Color _getActivityColor(String type, String status) {
    if (type == 'Stock_In') return Colors.green;
    if (type == 'Stock_Out') {
      if (status == 'Reserved') return Colors.blue;
      if (status == 'Invoiced' || status == 'Issued') return Colors.purple;
      if (status == 'Delivered') return Colors.orange;
    }
    if (type == 'Demo') return Colors.indigo;
    if (type == 'Returned') return Colors.teal;
    if (type == 'Cancellation') return Colors.red;
    return Colors.grey;
  }

  IconData _getActivityIcon(String type, String status) {
    if (type == 'Stock_In') return Icons.add_box;
    if (type == 'Stock_Out') {
      if (status == 'Reserved') return Icons.assignment;
      if (status == 'Invoiced' || status == 'Issued') return Icons.receipt;
      if (status == 'Delivered') return Icons.local_shipping;
      return Icons.remove_circle_outline;
    }
    if (type == 'Demo') return Icons.play_circle_outline;
    if (type == 'Returned') return Icons.keyboard_return;
    if (type == 'Cancellation') return Icons.cancel;
    return Icons.circle;
  }

  String _getRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year${(difference.inDays / 365).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item Activity History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadHistory,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _activities.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No activity history found',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Serial Number Header
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.qr_code_2, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Serial Number',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.serialNumber,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_activities.length} activities',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Timeline
                    ..._activities.asMap().entries.map((entry) {
                      final index = entry.key;
                      final activity = entry.value;
                      final isLast = index == _activities.length - 1;

                      return _buildTimelineItem(activity, isLast);
                    }),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> activity, bool isLast) {
    final type = activity['type'] as String? ?? '';
    final status = activity['status'] as String? ?? '';
    final date = activity['date'] as DateTime?;
    final description = activity['description'] as String? ?? '';
    final customerInfo = activity['customer_info'] as String? ?? '';
    final location = activity['location'] as String? ?? '';
    final invoiceNumber = activity['invoice_number'] as String? ?? '';
    final demoNumber = activity['demo_number'] as String? ?? '';
    final remarks = activity['remarks'] as String? ?? '';

    final color = _getActivityColor(type, status);
    final icon = _getActivityIcon(type, status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            if (!isLast)
              Container(width: 2, height: 60, color: Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 16),

        // Activity card
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row with description and time
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            description,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (date != null)
                          Text(
                            _getRelativeTime(date),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Details
                    if (date != null)
                      _buildDetailRow(
                        Icons.calendar_today,
                        DateFormat('MMM d, yyyy • h:mm a').format(date),
                      ),

                    if (customerInfo.isNotEmpty)
                      _buildDetailRow(Icons.person, customerInfo),

                    if (location.isNotEmpty)
                      _buildDetailRow(Icons.location_on, location),

                    if (invoiceNumber.isNotEmpty)
                      _buildDetailRow(Icons.receipt, 'Invoice: $invoiceNumber'),

                    if (demoNumber.isNotEmpty)
                      _buildDetailRow(Icons.tag, 'Demo: $demoNumber'),

                    if (remarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.note,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                remarks,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
