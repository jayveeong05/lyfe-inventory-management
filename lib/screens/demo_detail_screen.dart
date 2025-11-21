import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';

class DemoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> demo;

  const DemoDetailScreen({super.key, required this.demo});

  @override
  State<DemoDetailScreen> createState() => _DemoDetailScreenState();
}

class _DemoDetailScreenState extends State<DemoDetailScreen> {
  DateTime? _actualReturnDate;
  bool _isReturning = false;
  List<Map<String, dynamic>> _demoItems = [];
  bool _isLoadingItems = true;

  @override
  void initState() {
    super.initState();
    _actualReturnDate = DateTime.now(); // Default to today
    _loadDemoItems();
  }

  Future<void> _loadDemoItems() async {
    setState(() {
      _isLoadingItems = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      final items = await demoService.getDemoItems(widget.demo['id']);

      if (mounted) {
        setState(() {
          _demoItems = items;
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingItems = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading demo items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectReturnDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _actualReturnDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Actual Return Date',
    );

    if (picked != null && picked != _actualReturnDate) {
      setState(() {
        _actualReturnDate = picked;
      });
    }
  }

  Future<void> _confirmReturn() async {
    if (_actualReturnDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an actual return date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Demo Return'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo: ${widget.demo['demo_number']}'),
              Text('Items: ${_demoItems.length} items'),
              const SizedBox(height: 8),
              Text(
                'Actual Return Date: ${DateFormat('dd/MM/yyyy').format(_actualReturnDate!)}',
              ),
              const SizedBox(height: 16),
              const Text(
                'This will return all demo items back to active status.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Return'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _processReturn();
    }
  }

  Future<void> _processReturn() async {
    setState(() {
      _isReturning = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      final result = await demoService.returnDemoItems(
        demoId: widget.demo['id'],
        demoNumber: widget.demo['demo_number'],
        actualReturnDate: _actualReturnDate,
      );

      if (mounted) {
        setState(() {
          _isReturning = false;
        });

        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Navigate back to demo return screen
          Navigator.of(context).pop(true); // Return true to indicate success
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
          _isReturning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing return: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final demoNumber = widget.demo['demo_number'] ?? 'Unknown';
    final demoPurpose = widget.demo['demo_purpose'] ?? 'No purpose';
    final dealer = widget.demo['customer_dealer'] ?? 'Unknown';
    final client = widget.demo['customer_client'] ?? 'N/A';
    final location = widget.demo['location'] ?? 'Unknown';
    final createdDate = widget.demo['created_date'];
    final expectedReturnDate = widget.demo['expected_return_date'];
    final remarks = widget.demo['remarks'] ?? '';

    // Format dates
    String createdDateStr = 'Unknown';
    String expectedReturnStr = 'Not set';

    if (createdDate != null) {
      try {
        final date = createdDate.toDate();
        createdDateStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        createdDateStr = 'Invalid date';
      }
    }

    if (expectedReturnDate != null) {
      try {
        final date = expectedReturnDate.toDate();
        expectedReturnStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        expectedReturnStr = 'Invalid date';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Demo: $demoNumber'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Demo Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demo Information',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('Demo Number', demoNumber),
                    _buildDetailRow('Purpose', demoPurpose),
                    _buildDetailRow('Dealer', dealer),
                    _buildDetailRow('Client', client),
                    _buildDetailRow('Location', location),
                    _buildDetailRow('Created Date', createdDateStr),
                    _buildDetailRow('Expected Return', expectedReturnStr),
                    if (remarks.isNotEmpty) _buildDetailRow('Remarks', remarks),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Demo Items Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demo Items (${_demoItems.length})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingItems)
                      const Center(child: CircularProgressIndicator())
                    else if (_demoItems.isEmpty)
                      const Center(
                        child: Text(
                          'No items found for this demo',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _demoItems.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          return _buildItemTile(_demoItems[index]);
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Return Date Selection Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Return Information',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Actual Return Date',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _actualReturnDate != null
                                    ? DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_actualReturnDate!)
                                    : 'Not selected',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _actualReturnDate != null
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _selectReturnDate,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Select Date'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Return Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isReturning ? null : _confirmReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: _isReturning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.assignment_return),
                label: Text(
                  _isReturning ? 'Processing Return...' : 'Return Demo',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final serialNumber = item['serial_number'] ?? 'Unknown';
    final category = item['category'] ?? 'Unknown';
    final model = item['model'] ?? 'Unknown';
    final size = item['size'] ?? '';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.green.withOpacity(0.1),
        child: const Icon(Icons.inventory_2, color: Colors.green, size: 20),
      ),
      title: Text(
        serialNumber,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '$category - $model${size.isNotEmpty ? ' ($size)' : ''}',
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber),
        ),
        child: const Text(
          'Demo',
          style: TextStyle(
            color: Colors.amber,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
