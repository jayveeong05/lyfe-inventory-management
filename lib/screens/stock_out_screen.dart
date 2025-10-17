import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/purchase_order_service.dart';
import '../providers/auth_provider.dart';
import 'qr_scanner_screen.dart';

class StockOutScreen extends StatefulWidget {
  const StockOutScreen({super.key});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _poNumberController = TextEditingController();
  final _dealerNameController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _serialNumberController = TextEditingController();

  String? _selectedLocation;
  final List<Map<String, dynamic>> _selectedItems =
      []; // Changed to list for multiple items
  List<Map<String, dynamic>> _activeItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = false;
  bool _isLoadingItems = true;
  bool _showSuggestions = false;
  int? _nextEntryNumber;

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
    {'name': 'Wilayah Persekutuan Putra Jaya', 'abbreviation': 'PJY'},
  ];

  // Warranty type options with their periods
  final List<Map<String, dynamic>> _warrantyTypes = [
    {'display': '1 Year', 'value': '1 year', 'period': 1},
    {'display': '1+2 Year', 'value': '1+2 year', 'period': 3},
    {'display': '1+3 Year', 'value': '1+3 year', 'period': 4},
  ];

  @override
  void initState() {
    super.initState();
    _loadActiveItems();
    _loadNextEntryNumber();
  }

  @override
  void dispose() {
    _poNumberController.dispose();
    _dealerNameController.dispose();
    _clientNameController.dispose();
    _serialNumberController.dispose();
    super.dispose();
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        _serialNumberController.text = result;
      });
      // Trigger search with the scanned result
      _onSearchChanged(result);
    }
  }

  Future<void> _loadActiveItems() async {
    try {
      setState(() {
        _isLoadingItems = true;
      });

      // Step 1: Get ALL transactions (both Stock_In and Stock_Out) to determine latest status
      final allTransactionsQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy(
            'transaction_id',
            descending: true,
          ) // Get latest transactions first
          .get();

      if (allTransactionsQuery.docs.isEmpty) {
        setState(() {
          _activeItems = [];
          _isLoadingItems = false;
        });
        return;
      }

      // Step 2: Find the latest transaction for each serial number
      final Map<String, Map<String, dynamic>> latestTransactionBySerial = {};

      for (final doc in allTransactionsQuery.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null &&
            !latestTransactionBySerial.containsKey(serialNumber)) {
          // This is the latest transaction for this serial number
          latestTransactionBySerial[serialNumber] = data;
        }
      }

      // Step 3: Filter to only include items that are truly available (latest status is Active from Stock_In)
      final availableSerialNumbers = <String>[];
      final availableTransactions = <Map<String, dynamic>>[];

      for (final entry in latestTransactionBySerial.entries) {
        final serialNumber = entry.key;
        final transaction = entry.value;

        // Item is available if:
        // 1. Latest transaction type is Stock_In AND status is Active
        // OR
        // 2. No Stock_Out transaction exists for this item yet
        if (transaction['type'] == 'Stock_In' &&
            transaction['status'] == 'Active') {
          availableSerialNumbers.add(serialNumber);
          availableTransactions.add(transaction);
        }
      }

      if (availableSerialNumbers.isEmpty) {
        setState(() {
          _activeItems = [];
          _isLoadingItems = false;
        });
        return;
      }

      // Step 3: Get all inventory items in batches (Firestore 'in' query limit is 10)
      List<Map<String, dynamic>> allInventoryItems = [];

      // Process in batches of 10 (Firestore 'in' query limitation)
      for (int i = 0; i < availableSerialNumbers.length; i += 10) {
        final batch = availableSerialNumbers.skip(i).take(10).toList();

        final inventoryQuery = await FirebaseFirestore.instance
            .collection('inventory')
            .where('serial_number', whereIn: batch)
            .get();

        allInventoryItems.addAll(
          inventoryQuery.docs.map((doc) => doc.data()).toList(),
        );
      }

      // Step 4: Create a map for quick inventory lookup
      final inventoryMap = <String, Map<String, dynamic>>{};
      for (final item in allInventoryItems) {
        final serialNumber = item['serial_number'] as String?;
        if (serialNumber != null) {
          inventoryMap[serialNumber] = item;
        }
      }

      // Step 5: Combine transaction and inventory data efficiently
      List<Map<String, dynamic>> activeItems = [];

      for (final transactionData in availableTransactions) {
        final serialNumber = transactionData['serial_number'] as String?;

        if (serialNumber != null && inventoryMap.containsKey(serialNumber)) {
          final inventoryData = inventoryMap[serialNumber]!;

          activeItems.add({
            'serial_number': serialNumber,
            'equipment_category':
                inventoryData['equipment_category'] ??
                transactionData['equipment_category'],
            'model': transactionData['model'],
            'size': inventoryData['size'],
            'batch': inventoryData['batch'],
            'date': inventoryData['date'],
            'remark': inventoryData['remark'],
            'transaction_id': transactionData['transaction_id'],
            'location': transactionData['location'],
          });
        }
      }

      setState(() {
        _activeItems = activeItems;
        _filteredItems = activeItems; // Initialize filtered items
        _isLoadingItems = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingItems = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading active items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadNextEntryNumber() async {
    try {
      // Get the AuthService from the provider
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final purchaseOrderService = PurchaseOrderService(
        authService: authProvider.authService,
      );

      final nextEntryNumber = await purchaseOrderService.getNextEntryNumber();

      if (mounted) {
        setState(() {
          _nextEntryNumber = nextEntryNumber;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nextEntryNumber = 1; // Default to 1 if error
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _activeItems;
        _showSuggestions = false;
      } else {
        // Filter out items that are already selected
        final availableItems = _activeItems.where((item) {
          final serialNumber = item['serial_number'] ?? '';
          return !_selectedItems.any(
            (selected) => selected['serial_number'] == serialNumber,
          );
        }).toList();

        _filteredItems = availableItems.where((item) {
          final serialNumber =
              item['serial_number']?.toString().toLowerCase() ?? '';
          final equipmentCategory =
              item['equipment_category']?.toString().toLowerCase() ?? '';
          final model = item['model']?.toString().toLowerCase() ?? '';
          final searchQuery = query.toLowerCase();

          return serialNumber.contains(searchQuery) ||
              equipmentCategory.contains(searchQuery) ||
              model.contains(searchQuery);
        }).toList();
        _showSuggestions = _filteredItems.isNotEmpty;
      }
    });
  }

  void _addItemToSelection(Map<String, dynamic> item) {
    setState(() {
      // Check if item is already selected
      final serialNumber = item['serial_number'] ?? '';
      final isAlreadySelected = _selectedItems.any(
        (selected) => selected['serial_number'] == serialNumber,
      );

      if (!isAlreadySelected) {
        // Add warranty information to the item
        final itemWithWarranty = Map<String, dynamic>.from(item);
        itemWithWarranty['warranty_type'] = '1 year'; // Default warranty type
        itemWithWarranty['warranty_period'] = 1; // Default warranty period

        _selectedItems.add(itemWithWarranty);
        _serialNumberController.clear();
        _showSuggestions = false;

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added: $serialNumber'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // Show warning if already selected
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Item $serialNumber is already selected'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _removeItemFromSelection(int index) {
    setState(() {
      final removedItem = _selectedItems.removeAt(index);
      final serialNumber = removedItem['serial_number'] ?? '';

      // Show removal message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed: $serialNumber'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  /// Update warranty type for a specific item
  void _updateItemWarranty(int index, String warrantyType) {
    setState(() {
      final warranty = _warrantyTypes.firstWhere(
        (w) => w['value'] == warrantyType,
        orElse: () => {'value': '1 year', 'period': 1}, // Default
      );

      _selectedItems[index]['warranty_type'] = warrantyType;
      _selectedItems[index]['warranty_period'] = warranty['period'];
    });
  }

  Future<void> _saveStockOut() async {
    if (!_formKey.currentState!.validate() ||
        _selectedItems.isEmpty ||
        _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields, select location, and add at least one item',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Get the AuthService from the provider
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final purchaseOrderService = PurchaseOrderService(
        authService: authProvider.authService,
      );

      // Create the multi-item stock-out purchase order
      final result = await purchaseOrderService.createMultiItemStockOutOrder(
        poNumber: _poNumberController.text.trim(),
        dealerName: _dealerNameController.text.trim(),
        clientName: _clientNameController.text.trim(),
        location: _selectedLocation!,
        selectedItems: _selectedItems,
      );

      if (mounted) {
        if (result['success'] == true) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Success! ${result['message']}\nTransaction IDs: ${result['transaction_ids']?.join(', ') ?? 'N/A'}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Clear the form
          _poNumberController.clear();
          _dealerNameController.clear();
          _clientNameController.clear();
          _serialNumberController.clear();
          setState(() {
            _selectedItems.clear();
            _selectedLocation = null;
            _showSuggestions = false;
          });

          // Reload active items and next entry number to reflect the change
          _loadActiveItems();
          _loadNextEntryNumber();
        } else {
          // Show error message
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Out'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingItems
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PO Number Input
                    TextFormField(
                      controller: _poNumberController,
                      decoration: const InputDecoration(
                        labelText: 'PO Number *',
                        hintText: 'Enter purchase order number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'PO Number is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Dealer Name Input
                    TextFormField(
                      controller: _dealerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Dealer Name *',
                        hintText: 'Enter dealer name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Dealer Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Client Name Input
                    TextFormField(
                      controller: _clientNameController,
                      decoration: const InputDecoration(
                        labelText: 'Client Name *',
                        hintText: 'Enter client name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Client Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Location Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLocation,
                      decoration: const InputDecoration(
                        labelText: 'Location *',
                        hintText: 'Select state location',
                        border: OutlineInputBorder(),
                      ),
                      items: _malaysianStates.map((state) {
                        return DropdownMenuItem<String>(
                          value: state['abbreviation'],
                          child: Text(
                            '${state['name']} (${state['abbreviation']})',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedLocation = newValue;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Location is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Serial Number Search Field with QR scan button
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _serialNumberController,
                                decoration: InputDecoration(
                                  labelText: 'Serial Number *',
                                  hintText:
                                      'Type to search serial number, category, or model',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.qr_code),
                                  suffixIcon:
                                      _serialNumberController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _serialNumberController.clear();
                                            _onSearchChanged('');
                                          },
                                        )
                                      : const Icon(Icons.search),
                                ),
                                onChanged: _onSearchChanged,
                                validator: (value) {
                                  // No validation needed for search field
                                  // Validation is done on selected items list
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: _scanQRCode,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scan'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Search Suggestions
                        if (_showSuggestions && _filteredItems.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredItems.length > 5
                                  ? 5
                                  : _filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item['serial_number'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item['equipment_category'] ?? 'N/A'} - ${item['model'] ?? 'N/A'}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => _addItemToSelection(item),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey[400],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Selected Items List
                    if (_selectedItems.isNotEmpty) ...[
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    color: Colors.blue[700],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Selected Items (${_selectedItems.length})',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Entry Number Information
                              if (_nextEntryNumber != null)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.blue[200]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.confirmation_number,
                                        color: Colors.blue[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Entry Number: $_nextEntryNumber',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue[700],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // Items List
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _selectedItems.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final item = _selectedItems[index];
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Item header with number and remove button
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Colors.blue[100],
                                              child: Text(
                                                '${index + 1}',
                                                style: TextStyle(
                                                  color: Colors.blue[700],
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item['serial_number'] ??
                                                        'N/A',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${item['equipment_category'] ?? 'N/A'} - ${item['model'] ?? 'N/A'}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.remove_circle,
                                                color: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  _removeItemFromSelection(
                                                    index,
                                                  ),
                                              tooltip: 'Remove item',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Item details
                                        Text(
                                          'Size: ${item['size'] ?? 'N/A'} | Batch: ${item['batch'] ?? 'N/A'}',
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Warranty dropdown
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.security,
                                              size: 16,
                                              color: Colors.green[700],
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Warranty:',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: DropdownButtonFormField<String>(
                                                initialValue:
                                                    item['warranty_type'] ??
                                                    '1 year',
                                                decoration:
                                                    const InputDecoration(
                                                      border:
                                                          OutlineInputBorder(),
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      isDense: true,
                                                    ),
                                                items: _warrantyTypes.map((
                                                  warranty,
                                                ) {
                                                  return DropdownMenuItem<
                                                    String
                                                  >(
                                                    value: warranty['value'],
                                                    child: Text(
                                                      warranty['display'],
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (String? newValue) {
                                                  if (newValue != null) {
                                                    _updateItemWarranty(
                                                      index,
                                                      newValue,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              // Summary Information
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  children: [
                                    _buildInfoRow(
                                      'Total Items',
                                      '${_selectedItems.length}',
                                    ),
                                    _buildInfoRow(
                                      'Location',
                                      _selectedLocation ?? 'Not selected',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      // No items selected message
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No items selected. Search and tap on items to add them to the purchase order.',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveStockOut,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Save Stock Out',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
