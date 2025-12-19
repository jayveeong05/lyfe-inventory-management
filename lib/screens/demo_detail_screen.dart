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
  final TextEditingController _returnRemarksController =
      TextEditingController();
  Set<String> _selectedSerialNumbers = {};
  bool _selectAllItems = false;

  @override
  void initState() {
    super.initState();
    _actualReturnDate = DateTime.now(); // Default to today
    _loadDemoItems();
  }

  void _toggleItemSelection(String serialNumber) {
    setState(() {
      if (_selectedSerialNumbers.contains(serialNumber)) {
        _selectedSerialNumbers.remove(serialNumber);
        _selectAllItems = false;
      } else {
        _selectedSerialNumbers.add(serialNumber);
        if (_selectedSerialNumbers.length == _demoItems.length) {
          _selectAllItems = true;
        }
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAllItems) {
        _selectedSerialNumbers.clear();
        _selectAllItems = false;
      } else {
        // Only select items that haven't been returned
        _selectedSerialNumbers = _demoItems
            .where((item) => item['is_returned'] != true)
            .map((item) => item['serial_number'] as String)
            .toSet();
        _selectAllItems = true;
      }
    });
  }

  @override
  void dispose() {
    _returnRemarksController.dispose();
    super.dispose();
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
    // Validate that at least one item is selected
    if (_selectedSerialNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one item to return'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_actualReturnDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an actual return date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isFullReturn = _selectedSerialNumbers.length == _demoItems.length;
    final selectedCount = _selectedSerialNumbers.length;
    final totalCount = _demoItems.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            isFullReturn
                ? 'Confirm Full Demo Return'
                : 'Confirm Partial Demo Return',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo: ${widget.demo['demo_number']}'),
              Text('Returning: $selectedCount of $totalCount items'),
              const SizedBox(height: 8),
              Text(
                'Actual Return Date: ${DateFormat('dd/MM/yyyy').format(_actualReturnDate!)}',
              ),
              const SizedBox(height: 16),
              Text(
                isFullReturn
                    ? 'This will return all demo items back to active status.'
                    : 'This will return selected items. ${totalCount - selectedCount} item(s) will remain in demo.',
                style: const TextStyle(fontWeight: FontWeight.w500),
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
        serialNumbersToReturn: _selectedSerialNumbers.toList(),
        actualReturnDate: _actualReturnDate,
        returnRemarks: _returnRemarksController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isReturning = false;
        });

        if (result['success']) {
          final isFullReturn = result['is_full_return'] ?? false;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          if (isFullReturn) {
            // Full return - navigate back to demo return screen
            Navigator.of(context).pop(true);
          } else {
            // Partial return - reload the demo items to show updated list
            _selectedSerialNumbers.clear();
            _selectAllItems = false;
            await _loadDemoItems();
          }
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Demo Items (${_demoItems.length})',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                        ),
                        if (_demoItems.isNotEmpty && !_isLoadingItems)
                          TextButton.icon(
                            onPressed: _toggleSelectAll,
                            icon: Icon(
                              _selectAllItems
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 20,
                            ),
                            label: Text(
                              _selectAllItems ? 'Deselect All' : 'Select All',
                            ),
                          ),
                      ],
                    ),
                    if (_demoItems.isNotEmpty && !_isLoadingItems)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          '${_selectedSerialNumbers.length} of ${_demoItems.where((item) => item['is_returned'] != true).length} available items selected',
                          style: TextStyle(
                            color: _selectedSerialNumbers.isEmpty
                                ? Colors.grey
                                : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _returnRemarksController,
                      decoration: const InputDecoration(
                        labelText: 'Return Remarks (Optional)',
                        hintText: 'Enter any remarks about the return...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                      ),
                      maxLines: 3,
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
                onPressed: (_isReturning || _selectedSerialNumbers.isEmpty)
                    ? null
                    : _confirmReturn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
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
                  _isReturning
                      ? 'Processing Return...'
                      : _selectedSerialNumbers.isEmpty
                      ? 'Select Items to Return'
                      : _selectedSerialNumbers.length == _demoItems.length
                      ? 'Return All Items (${_demoItems.length})'
                      : 'Return Selected Items (${_selectedSerialNumbers.length} of ${_demoItems.length})',
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
    final isReturned = item['is_returned'] == true;
    final isSelected = _selectedSerialNumbers.contains(serialNumber);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !isReturned, // Disable interaction for returned items
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: isReturned ? false : isSelected, // Uncheck returned items
            onChanged: isReturned
                ? null
                : (bool? value) {
                    _toggleItemSelection(serialNumber);
                  },
            activeColor: Colors.green,
          ),
          CircleAvatar(
            backgroundColor: isReturned
                ? Colors.grey.withOpacity(0.3)
                : Colors.green.withOpacity(0.1),
            child: Icon(
              Icons.inventory_2,
              color: isReturned ? Colors.grey : Colors.green,
              size: 20,
            ),
          ),
        ],
      ),
      title: Text(
        serialNumber,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isReturned ? Colors.grey : Colors.black,
          decoration: isReturned ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '$category - $model${size.isNotEmpty ? ' ($size)' : ''}',
        style: TextStyle(
          color: isReturned ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isReturned
              ? Colors.green.withOpacity(0.1)
              : Colors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isReturned ? Colors.green : Colors.amber),
        ),
        child: Text(
          isReturned ? 'Returned' : 'Demo',
          style: TextStyle(
            color: isReturned ? Colors.green : Colors.amber,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      onTap: isReturned
          ? null
          : () {
              _toggleItemSelection(serialNumber);
            },
    );
  }
}
