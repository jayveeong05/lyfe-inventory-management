import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/demo_service.dart';
import '../widgets/editable_item_card.dart';
import '../services/order_service.dart'; // Used for getItemsFromTransactionIds since it's shared transaction logic

class EditDemoScreen extends StatefulWidget {
  final Map<String, dynamic> demo;

  const EditDemoScreen({Key? key, required this.demo}) : super(key: key);

  @override
  State<EditDemoScreen> createState() => _EditDemoScreenState();
}

class _EditDemoScreenState extends State<EditDemoScreen> {
  final DemoService _demoService = DemoService();
  final OrderService _orderService = OrderService(); // For fetching items

  late TextEditingController _dealerController;
  late TextEditingController _clientController;
  late TextEditingController _purposeController;
  late TextEditingController _remarksController;
  String? _selectedLocation;
  DateTime? _expectedReturnDate;

  bool _isEditingDealer = false;
  bool _isEditingClient = false;
  bool _isEditingPurpose = false;
  bool _isEditingLocation = false;
  bool _isEditingRemarks = false;
  bool _isEditingDate = false;

  bool _isLoading = true;
  List<Map<String, dynamic>> _demoItems = [];

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
      text: widget.demo['customer_dealer'] ?? '',
    );
    _clientController = TextEditingController(
      text: widget.demo['customer_client'] ?? '',
    );
    _purposeController = TextEditingController(
      text: widget.demo['demo_purpose'] ?? '',
    );
    _remarksController = TextEditingController(
      text: widget.demo['remarks'] ?? '',
    );

    _selectedLocation = widget.demo['location'];
    if (_selectedLocation != null &&
        !_malaysianStates.any(
          (state) => state['abbreviation'] == _selectedLocation,
        )) {
      _selectedLocation = null;
    }

    if (widget.demo['expected_return_date'] != null) {
      _expectedReturnDate = widget.demo['expected_return_date'].toDate();
    }

    _loadItems();
  }

  @override
  void dispose() {
    _dealerController.dispose();
    _clientController.dispose();
    _purposeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final transactionIds = List<int>.from(widget.demo['transaction_ids'] ?? []);

    if (transactionIds.isNotEmpty) {
      final items = await _orderService.getItemsFromTransactionIds(
        transactionIds,
      );
      setState(() {
        _demoItems = items;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDemoField(String fieldName, dynamic value) async {
    try {
      Map<String, dynamic> updateData = {
        'demoNumber': widget.demo['demo_number'],
      };
      if (fieldName == 'dealer') updateData['customerDealer'] = value;
      if (fieldName == 'client') updateData['customerClient'] = value;
      if (fieldName == 'purpose') updateData['demoPurpose'] = value;
      if (fieldName == 'location') updateData['location'] = value;
      if (fieldName == 'remarks') updateData['remarks'] = value;
      if (fieldName == 'date')
        updateData['expectedReturnDate'] = value as DateTime;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saving changes...'),
          duration: Duration(seconds: 1),
        ),
      );

      final result = await _demoService.updateDemoDetails(
        demoNumber: widget.demo['demo_number'],
        customerDealer: updateData['customerDealer'],
        customerClient: updateData['customerClient'],
        demoPurpose: updateData['demoPurpose'],
        location: updateData['location'],
        remarks: updateData['remarks'],
        expectedReturnDate: updateData['expectedReturnDate'],
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
      appBar: AppBar(title: Text('Edit Demo: ${widget.demo['demo_number']}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Demo Details'),
                _buildEditableTextRow(
                  'Dealer Name',
                  _dealerController,
                  _isEditingDealer,
                  (val) {
                    setState(() => _isEditingDealer = val);
                    if (!val) _saveDemoField('dealer', _dealerController.text);
                  },
                  () {
                    setState(() {
                      _isEditingDealer = false;
                      _dealerController.text =
                          widget.demo['customer_dealer'] ?? '';
                    });
                  },
                ),
                _buildEditableTextRow(
                  'Client Name',
                  _clientController,
                  _isEditingClient,
                  (val) {
                    setState(() => _isEditingClient = val);
                    if (!val) _saveDemoField('client', _clientController.text);
                  },
                  () {
                    setState(() {
                      _isEditingClient = false;
                      _clientController.text =
                          widget.demo['customer_client'] ?? '';
                    });
                  },
                ),
                _buildEditableTextRow(
                  'Demo Purpose',
                  _purposeController,
                  _isEditingPurpose,
                  (val) {
                    setState(() => _isEditingPurpose = val);
                    if (!val)
                      _saveDemoField('purpose', _purposeController.text);
                  },
                  () {
                    setState(() {
                      _isEditingPurpose = false;
                      _purposeController.text =
                          widget.demo['demo_purpose'] ?? '';
                    });
                  },
                ),

                _buildEditableLocationRow(),
                _buildEditableDateRow(),

                _buildEditableTextRow(
                  'Remarks',
                  _remarksController,
                  _isEditingRemarks,
                  (val) {
                    setState(() => _isEditingRemarks = val);
                    if (!val)
                      _saveDemoField('remarks', _remarksController.text);
                  },
                  () {
                    setState(() {
                      _isEditingRemarks = false;
                      _remarksController.text = widget.demo['remarks'] ?? '';
                    });
                  },
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Items in Demo'),
                ..._demoItems
                    .map(
                      (item) => EditableItemCard(
                        item: item,
                        showWarranty: false,
                        onSave: (newSerial, warrantyType, warrantyPeriod) =>
                            _saveItemChanges(
                              transactionId: item['transaction_id'],
                              newSerial: newSerial,
                              warrantyType: 'No Warranty',
                              warrantyPeriod: 0,
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
                            setState(() => _selectedLocation = val);
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
                        _selectedLocation = widget.demo['location'];
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
                      _saveDemoField('location', _selectedLocation);
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

  Widget _buildEditableDateRow() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expected Return Date',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _isEditingDate
                      ? InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _expectedReturnDate ??
                                  DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => _expectedReturnDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: Text(
                              _expectedReturnDate != null
                                  ? DateFormat(
                                      'dd MMM yyyy',
                                    ).format(_expectedReturnDate!)
                                  : 'Select Date',
                            ),
                          ),
                        )
                      : Text(
                          _expectedReturnDate != null
                              ? DateFormat(
                                  'dd MMM yyyy',
                                ).format(_expectedReturnDate!)
                              : 'N/A',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
                if (_isEditingDate)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _isEditingDate = false;
                        if (widget.demo['expected_return_date'] != null) {
                          final exp = widget.demo['expected_return_date'];
                          _expectedReturnDate =
                              exp.runtimeType.toString() == 'Timestamp'
                              ? exp.toDate()
                              : (exp is DateTime ? exp : null);
                        } else {
                          _expectedReturnDate = null;
                        }
                      });
                    },
                  ),
                IconButton(
                  icon: Icon(
                    _isEditingDate ? Icons.check : Icons.edit,
                    color: _isEditingDate ? Colors.green : Colors.blue,
                  ),
                  onPressed: () {
                    if (_isEditingDate && _expectedReturnDate != null) {
                      _saveDemoField('date', _expectedReturnDate);
                    }
                    setState(() => _isEditingDate = !_isEditingDate);
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

    final result = await _demoService.updateTransactionItem(
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
      await _loadItems();
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
