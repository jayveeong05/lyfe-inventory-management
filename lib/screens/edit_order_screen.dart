import 'package:flutter/material.dart';
import '../services/order_service.dart';
import '../widgets/editable_item_card.dart';

class EditOrderScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const EditOrderScreen({Key? key, required this.order}) : super(key: key);

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  final OrderService _orderService = OrderService();

  // order level editors
  late TextEditingController _dealerController;
  late TextEditingController _clientController;
  late TextEditingController _remarksController;
  String? _selectedLocation;

  bool _isEditingDealer = false;
  bool _isEditingClient = false;
  bool _isEditingRemarks = false;
  bool _isEditingLocation = false;

  bool _isLoading = true;
  List<Map<String, dynamic>> _orderItems = [];

  // Malaysian states with their abbreviations
  final List<Map<String, String>> _malaysianStates = [
    {'name': 'Johor Darul Ta\'zim', 'abbreviation': 'JHR'},
    {'name': 'Kedah Darul Aman', 'abbreviation': 'KDH'},
    {'name': 'Kelantan Darul Naim', 'abbreviation': 'KTN'},
    {'name': 'Melaka', 'abbreviation': 'MLK'},
    {'name': 'Negeri Sembilan Darul Khusus', 'abbreviation': 'NSN'},
    {'name': 'Pahang Darul Makmur', 'abbreviation': 'PHG'},
    {'name': 'Pulau Pinang', 'abbreviation': 'PNG'},
    {'name': 'Perak Darul Ridzuan', 'abbreviation': 'PRK'},
    {'name': 'Perlis Indera Kayangan', 'abbreviation': 'PLS'},
    {'name': 'Selangor Darul Ehsan', 'abbreviation': 'SGR'},
    {'name': 'Terengganu Darul Iman', 'abbreviation': 'TRG'},
    {'name': 'Sabah', 'abbreviation': 'SBH'},
    {'name': 'Sarawak', 'abbreviation': 'SWK'},
    {'name': 'Wilayah Persekutuan Kuala Lumpur', 'abbreviation': 'KUL'},
    {'name': 'Wilayah Persekutuan Labuan', 'abbreviation': 'LBN'},
    {'name': 'Wilayah Persekutuan Putrajaya', 'abbreviation': 'PJY'},
  ];

  @override
  void initState() {
    super.initState();
    _dealerController = TextEditingController(
      text: widget.order['customer_dealer'] ?? '',
    );
    _clientController = TextEditingController(
      text: widget.order['customer_client'] ?? '',
    );
    _remarksController = TextEditingController(
      text: widget.order['order_remarks'] ?? '',
    );
    _selectedLocation = widget.order['location'];

    // Default location if not in valid list
    if (_selectedLocation != null &&
        !_malaysianStates.any(
          (state) => state['abbreviation'] == _selectedLocation,
        )) {
      _selectedLocation = null;
    }

    _loadItems();
  }

  @override
  void dispose() {
    _dealerController.dispose();
    _clientController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final transactionIds = List<int>.from(
      widget.order['transaction_ids'] ?? [],
    );

    if (transactionIds.isNotEmpty) {
      final items = await _orderService.getItemsFromTransactionIds(
        transactionIds,
      );
      setState(() {
        _orderItems = items;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOrderField(String fieldName, dynamic value) async {
    try {
      Map<String, dynamic> updateData = {
        'orderNumber': widget.order['order_number'],
      };
      if (fieldName == 'dealer') updateData['customerDealer'] = value;
      if (fieldName == 'client') updateData['customerClient'] = value;
      if (fieldName == 'remarks') updateData['orderRemarks'] = value;
      if (fieldName == 'location') updateData['location'] = value;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saving changes...'),
          duration: Duration(seconds: 1),
        ),
      );

      final result = await _orderService.updateOrderDetails(
        orderNumber: widget.order['order_number'],
        customerDealer: updateData['customerDealer'],
        customerClient: updateData['customerClient'],
        orderRemarks: updateData['orderRemarks'],
        location: updateData['location'],
      );

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw result['error'] ?? 'Unknown error';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Order: ${widget.order['order_number']}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Order Details'),
                _buildEditableTextRow(
                  'Dealer Name',
                  _dealerController,
                  _isEditingDealer,
                  (val) {
                    setState(() => _isEditingDealer = val);
                    if (!val) _saveOrderField('dealer', _dealerController.text);
                  },
                  () {
                    setState(() {
                      _isEditingDealer = false;
                      _dealerController.text =
                          widget.order['customer_dealer'] ?? '';
                    });
                  },
                ),
                _buildEditableTextRow(
                  'Client Name',
                  _clientController,
                  _isEditingClient,
                  (val) {
                    setState(() => _isEditingClient = val);
                    if (!val) _saveOrderField('client', _clientController.text);
                  },
                  () {
                    setState(() {
                      _isEditingClient = false;
                      _clientController.text =
                          widget.order['customer_client'] ?? '';
                    });
                  },
                ),
                _buildEditableLocationRow(),
                _buildEditableTextRow(
                  'Remarks',
                  _remarksController,
                  _isEditingRemarks,
                  (val) {
                    setState(() => _isEditingRemarks = val);
                    if (!val)
                      _saveOrderField('remarks', _remarksController.text);
                  },
                  () {
                    setState(() {
                      _isEditingRemarks = false;
                      _remarksController.text =
                          widget.order['order_remarks'] ?? '';
                    });
                  },
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Items in Order'),
                ..._orderItems
                    .map(
                      (item) => EditableItemCard(
                        item: item,
                        onSave: (newSerial, warrantyType, warrantyPeriod) =>
                            _saveItemChanges(
                              transactionId: item['transaction_id'],
                              newSerial: newSerial,
                              warrantyType: warrantyType,
                              warrantyPeriod: warrantyPeriod,
                            ),
                      ),
                    )
                    .toList(),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEditableTextRow(
    String label,
    TextEditingController controller,
    bool isEditing,
    Function(bool) onEditToggle,
    VoidCallback onCancel,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: isEditing
                      ? TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : Text(
                          controller.text.isEmpty ? 'N/A' : controller.text,
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
                if (isEditing)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: onCancel,
                  ),
                IconButton(
                  icon: Icon(
                    isEditing ? Icons.check : Icons.edit,
                    color: isEditing ? Colors.green : Colors.blue,
                  ),
                  onPressed: () => onEditToggle(!isEditing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableLocationRow() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _isEditingLocation
                      ? DropdownButtonFormField<String>(
                          value: _selectedLocation,
                          items: _malaysianStates.map((state) {
                            return DropdownMenuItem<String>(
                              value: state['abbreviation'],
                              child: Text(state['name']!),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedLocation = val;
                            });
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : Text(
                          _malaysianStates.firstWhere(
                                (state) =>
                                    state['abbreviation'] == _selectedLocation,
                                orElse: () => {
                                  'name': _selectedLocation ?? 'N/A',
                                },
                              )['name'] ??
                              'N/A',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
                if (_isEditingLocation)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _isEditingLocation = false;
                        _selectedLocation = widget.order['location'];
                      });
                    },
                  ),
                IconButton(
                  icon: Icon(
                    _isEditingLocation ? Icons.check : Icons.edit,
                    color: _isEditingLocation ? Colors.green : Colors.blue,
                  ),
                  onPressed: () {
                    if (_isEditingLocation) {
                      _saveOrderField('location', _selectedLocation);
                    }
                    setState(() => _isEditingLocation = !_isEditingLocation);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _saveItemChanges({
    required int transactionId,
    required String newSerial,
    required String warrantyType,
    required int warrantyPeriod,
  }) async {
    setState(() => _isLoading = true);

    final result = await _orderService.updateTransactionItem(
      transactionId: transactionId,
      newSerialNumber: newSerial,
      warrantyType: warrantyType,
      warrantyPeriod: warrantyPeriod,
    );

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadItems(); // Refresh the list
      return true;
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }
}
