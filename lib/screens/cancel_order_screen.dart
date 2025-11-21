import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/cancel_order_service.dart';

class CancelOrderScreen extends StatefulWidget {
  const CancelOrderScreen({super.key});

  @override
  State<CancelOrderScreen> createState() => _CancelOrderScreenState();
}

class _CancelOrderScreenState extends State<CancelOrderScreen> {
  List<Map<String, dynamic>> _cancellableOrders = [];
  Map<String, dynamic>? _selectedOrder;
  Map<String, dynamic>? _orderDetails;
  bool _isLoading = true;
  bool _isLoadingDetails = false;
  bool _isCancelling = false;

  final TextEditingController _reasonController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late CancelOrderService _cancelOrderService;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _cancelOrderService = CancelOrderService(
      authService: authProvider.authService,
    );
    _loadCancellableOrders();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadCancellableOrders() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final orders = await _cancelOrderService.getCancellableOrders();

      if (mounted) {
        setState(() {
          _cancellableOrders = orders;
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
            content: Text('Error loading orders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadOrderDetails(Map<String, dynamic> order) async {
    try {
      setState(() {
        _isLoadingDetails = true;
        _selectedOrder = order;
        _orderDetails = null;
      });

      final details = await _cancelOrderService.getOrderDetails(order['id']);

      if (mounted) {
        setState(() {
          _orderDetails = details;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading order details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelOrder() async {
    if (!_formKey.currentState!.validate() || _selectedOrder == null) {
      return;
    }

    final confirmed = await _showCancellationConfirmDialog();
    if (!confirmed) return;

    try {
      setState(() {
        _isCancelling = true;
      });

      final result = await _cancelOrderService.cancelOrder(
        orderId: _selectedOrder!['id'],
        orderNumber: _selectedOrder!['order_number'],
        cancellationReason: _reasonController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isCancelling = false;
        });

        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Reset form and reload orders
          _resetForm();
          _loadCancellableOrders();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['error']}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showCancellationConfirmDialog() async {
    final orderNumber = _selectedOrder?['order_number'] ?? 'Unknown';
    final itemCount = _orderDetails?['items']?.length ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Order Cancellation'),
          content: Text(
            'Are you sure you want to cancel order "$orderNumber"?\n\n'
            'This will:\n'
            '• Cancel $itemCount items\n'
            '• Return items to active status\n'
            '• Create cancellation audit trail\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cancel Order'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  void _resetForm() {
    setState(() {
      _selectedOrder = null;
      _orderDetails = null;
      _reasonController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cancel Order'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCancellableOrders,
            tooltip: 'Refresh Orders',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cancellableOrders.isEmpty
          ? _buildEmptyState()
          : _buildMainContent(),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cancel_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No Cancellable Orders',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'All orders are either delivered or already cancelled.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSelectionCard(),
            const SizedBox(height: 16),
            if (_selectedOrder != null) ...[
              _buildOrderDetailsCard(),
              const SizedBox(height: 16),
              _buildCancellationReasonCard(),
              const SizedBox(height: 24),
              _buildCancelButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSelectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Order to Cancel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Map<String, dynamic>>(
              key: ValueKey(
                '${_cancellableOrders.length}_${_selectedOrder?['id'] ?? 'none'}',
              ),
              value: _cancellableOrders.contains(_selectedOrder)
                  ? _selectedOrder
                  : null,
              isExpanded: true,
              menuMaxHeight: 300, // Limit dropdown height like other screens
              decoration: const InputDecoration(
                labelText: 'Select Order to Cancel',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.receipt_long),
                hintText: 'Choose an order to cancel',
              ),
              items: _cancellableOrders.map((order) {
                final orderNumber = order['order_number'] ?? 'N/A';
                final dealer = order['customer_dealer'] ?? 'Unknown';
                final itemCount = order['total_items'] ?? 0;
                final invoiceStatus = order['invoice_status'] ?? 'Reserved';
                final deliveryStatus = order['delivery_status'] ?? 'Pending';

                // Determine status color (same logic as invoice/delivery screens)
                final isInvoiced = invoiceStatus == 'Invoiced';

                return DropdownMenuItem<Map<String, dynamic>>(
                  value: order,
                  child: Row(
                    children: [
                      // Status indicator circle
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isInvoiced ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Order details (single line with Expanded to handle overflow)
                      Expanded(
                        child: Text(
                          '$orderNumber - $dealer ($itemCount items)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isInvoiced
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          deliveryStatus,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isInvoiced
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (order) {
                if (order != null) {
                  _loadOrderDetails(order);
                }
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select an order to cancel';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetailsCard() {
    if (_isLoadingDetails) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_orderDetails == null) {
      return const SizedBox.shrink();
    }

    final order = _orderDetails!['order'];
    final items = _orderDetails!['items'] as List<Map<String, dynamic>>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Order Number', order['order_number']),
            _buildDetailRow('Dealer', order['customer_dealer']),
            _buildDetailRow('Client', order['customer_client']),
            _buildDetailRow('Invoice Status', order['invoice_status']),
            _buildDetailRow('Delivery Status', order['delivery_status']),
            _buildDetailRow('Total Items', '${order['total_items']}'),
            const SizedBox(height: 16),
            const Text(
              'Items to be Cancelled',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildItemTile(item);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['serial_number'] ?? 'N/A',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item['status'] ?? 'N/A',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Category: ${item['category'] ?? 'N/A'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
              Expanded(
                child: Text(
                  'Model: ${item['model'] ?? 'N/A'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ],
          ),
          if (item['size'] != null && item['size'] != 'N/A') ...[
            const SizedBox(height: 2),
            Text(
              'Size: ${item['size']}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCancellationReasonCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancellation Reason',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation',
                hintText: 'Enter the reason for cancelling this order...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.comment),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a reason for cancellation';
                }
                if (value.trim().length < 10) {
                  return 'Reason must be at least 10 characters long';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isCancelling ? null : _cancelOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: _isCancelling
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.cancel),
        label: Text(_isCancelling ? 'Cancelling Order...' : 'Cancel Order'),
      ),
    );
  }
}
