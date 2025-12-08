import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/demo_service.dart';

import '../utils/platform_features.dart';
import 'qr_scanner_screen.dart';

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _demoNumberController = TextEditingController();
  final _demoPurposeController = TextEditingController();
  final _dealerNameController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _remarksController = TextEditingController();

  String? _selectedLocation;
  DateTime? _expectedReturnDate;
  final List<Map<String, dynamic>> _selectedItems = [];
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

  @override
  void initState() {
    super.initState();
    _loadActiveItems();
    _loadNextEntryNumber();
  }

  @override
  void dispose() {
    _demoNumberController.dispose();
    _demoPurposeController.dispose();
    _dealerNameController.dispose();
    _clientNameController.dispose();
    _serialNumberController.dispose();
    _remarksController.dispose();
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
      if (mounted) {
        setState(() {
          _isLoadingItems = true;
        });
      }

      // Query inventory collection directly for active items
      final snapshot = await FirebaseFirestore.instance
          .collection('inventory')
          .where('status', isEqualTo: 'Active')
          .limit(1000)
          .get();

      final activeItems = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          ...data,
          'id': doc.id,
          'current_status': 'Active',
          'location': 'HQ', // Default location
          'transaction_id': null, // Not strictly needed
        };
      }).toList();

      if (mounted) {
        setState(() {
          _activeItems = activeItems;
          _filteredItems = activeItems;
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeItems = [];
          _filteredItems = [];
          _isLoadingItems = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadNextEntryNumber() async {
    try {
      // Get the count of all transactions + 1
      final querySnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Query timeout',
                const Duration(seconds: 10),
              );
            },
          );

      if (mounted) {
        setState(() {
          _nextEntryNumber = querySnapshot.docs.length + 1;
        });
      }
    } catch (e) {
      // Silently handle error and use default value
      if (mounted) {
        setState(() {
          _nextEntryNumber = 1;
        });
      }
    }
  }

  Timer? _debounceTimer;

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _activeItems;
        _showSuggestions = false;
        _debounceTimer?.cancel();
      } else {
        // 1. Local Search (Immediate)
        // Filter out items that are already selected (case-insensitive)
        final availableItems = _activeItems.where((item) {
          final serialNumber = (item['serial_number'] ?? '')
              .toString()
              .toLowerCase();
          return !_selectedItems.any(
            (selected) =>
                (selected['serial_number'] ?? '').toString().toLowerCase() ==
                serialNumber,
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
        _showSuggestions = true; // Always show suggestions when typing

        // 2. Backend Search (Debounced)
        // Only search backend if query is at least 3 characters to avoid spam
        if (query.length >= 3) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 500), () {
            _performBackendSearch(query);
          });
        }
      }
    });
  }

  Future<void> _performBackendSearch(String query) async {
    try {
      // Search in inventory collection for serial numbers starting with query
      // Note: Firestore range queries are case-sensitive.
      // We'll try to match exact case or common variations if needed,
      // but for now we'll rely on the user typing somewhat correctly or exact matches.
      // A better approach for case-insensitive search in Firestore requires a separate lowercase field.
      // Assuming 'serial_number' is stored as is.

      // We will fetch items where serial_number >= query AND serial_number < query + 'z'
      // This performs a prefix search.
      final inventoryQuery = await FirebaseFirestore.instance
          .collection('inventory')
          .where('serial_number', isGreaterThanOrEqualTo: query)
          .where('serial_number', isLessThan: query + 'z')
          .limit(20) // Limit results
          .get();

      if (inventoryQuery.docs.isEmpty) return;

      final List<Map<String, dynamic>> newCandidates = [];

      for (final doc in inventoryQuery.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber == null) continue;

        // Check if this item is already in our _activeItems list (avoid duplicates)
        final isAlreadyLoaded = _activeItems.any(
          (item) =>
              (item['serial_number'] ?? '').toString().toLowerCase() ==
              serialNumber.toLowerCase(),
        );

        if (isAlreadyLoaded) continue;

        // Check if this item is already selected
        final isSelected = _selectedItems.any(
          (item) =>
              (item['serial_number'] ?? '').toString().toLowerCase() ==
              serialNumber.toLowerCase(),
        );

        if (isSelected) continue;

        // Check status directly from inventory document
        final status = data['status'] as String? ?? 'Unknown';

        if (status == 'Active') {
          newCandidates.add({
            'serial_number': serialNumber,
            'equipment_category': data['equipment_category'] ?? 'Unknown',
            'model': data['model'] ?? 'Unknown',
            'size': data['size'],
            'status': status,
            'transaction_id': null, // Not needed
            'location': 'HQ', // Default
          });
        }
      }

      if (newCandidates.isNotEmpty && mounted) {
        setState(() {
          // Add new candidates to _activeItems so they stay available
          _activeItems.addAll(newCandidates);

          // Re-run filter to include them in current view
          // (We just append them to filtered items to avoid resetting the view abruptly)
          _filteredItems.addAll(newCandidates);
        });
      }
    } catch (e) {
      print('Error in backend search: $e');
    }
  }

  void _addItemToSelection(Map<String, dynamic> item) {
    setState(() {
      // Check if item is already selected (case-insensitive)
      final serialNumber = (item['serial_number'] ?? '')
          .toString()
          .toLowerCase();
      final isAlreadySelected = _selectedItems.any(
        (selected) =>
            (selected['serial_number'] ?? '').toString().toLowerCase() ==
            serialNumber,
      );

      if (!isAlreadySelected) {
        _selectedItems.add(Map<String, dynamic>.from(item));
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
        // Show already selected message
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed: ${removedItem['serial_number']}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _selectReturnDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReturnDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Expected Return Date',
    );
    if (picked != null && picked != _expectedReturnDate) {
      setState(() {
        _expectedReturnDate = picked;
      });
    }
  }

  Future<void> _saveDemo() async {
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
      // Get auth provider for service
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      // Create the demo
      final result = await demoService.createDemo(
        demoNumber: _demoNumberController.text.trim(),
        demoPurpose: _demoPurposeController.text.trim(),
        dealerName: _dealerNameController.text.trim(),
        clientName: _clientNameController.text.trim(),
        location: _selectedLocation!,
        selectedItems: _selectedItems,
        expectedReturnDate: _expectedReturnDate,
        remarks: _remarksController.text.trim().isEmpty
            ? null
            : _remarksController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success']) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Demo "${result['demo_number']}" created successfully!\n'
                'Items: ${result['transaction_ids'].length}\n'
                'Demo ID: ${result['demo_id']}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Clear the form
          _demoNumberController.clear();
          _demoPurposeController.clear();
          _dealerNameController.clear();
          _clientNameController.clear();
          _serialNumberController.clear();
          _remarksController.clear();
          setState(() {
            _selectedItems.clear();
            _selectedLocation = null;
            _expectedReturnDate = null;
            _showSuggestions = false;
          });

          // Reload active items and next entry number
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
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating demo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showDeleteDemoDialog() async {
    try {
      // Get auth provider for service
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      // Get recent demos
      final recentDemos = await demoService.getRecentDemosForDeletion(
        limit: 10,
      );

      if (!mounted) return;

      if (recentDemos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No demo records found to delete.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show dialog with list of recent demos
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text('Delete Demo Records'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'WARNING: This will permanently delete demo records and restore items to active status.',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select a demo to delete:'),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    child: ListView.builder(
                      itemCount: recentDemos.length,
                      itemBuilder: (context, index) {
                        final demo = recentDemos[index];
                        final demoNumber = demo['demo_number'] ?? 'Unknown';
                        final demoPurpose =
                            demo['demo_purpose'] ?? 'No purpose';
                        final status = demo['status'] ?? 'Unknown';
                        final itemCount = demo['total_items'] ?? 0;

                        return Card(
                          child: ListTile(
                            title: Text(demoNumber),
                            subtitle: Text(
                              '$demoPurpose\nStatus: $status | Items: $itemCount',
                            ),
                            trailing: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _confirmDeleteDemo(demo['id'], demoNumber);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Delete'),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading demos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteDemo(String demoId, String demoNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to delete demo "$demoNumber"?\n\n'
            'This action cannot be undone. All associated items will be restored to active status.',
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
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteDemo(demoId, demoNumber);
    }
  }

  Future<void> _deleteDemo(String demoId, String demoNumber) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get auth provider for service
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final demoService = DemoService(authService: authProvider.authService);

      // Delete the demo
      final result = await demoService.deleteDemo(
        demoId: demoId,
        demoNumber: demoNumber,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Reload active items to reflect the restored items
          _loadActiveItems();
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
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting demo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo'),
        backgroundColor: Colors.amber,
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
                    // Demo Number Input
                    TextFormField(
                      controller: _demoNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Demo Number *',
                        hintText: 'Enter demo reference number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Demo Number is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Demo Purpose Input
                    TextFormField(
                      controller: _demoPurposeController,
                      decoration: const InputDecoration(
                        labelText: 'Demo Purpose *',
                        hintText:
                            'e.g., Client presentation, trade show, training',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Demo Purpose is required';
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

                    // Client Name Input (Optional)
                    TextFormField(
                      controller: _clientNameController,
                      decoration: const InputDecoration(
                        labelText: 'Client Name (Optional)',
                        hintText: 'Enter client name (optional)',
                        border: OutlineInputBorder(),
                      ),
                      // No validator - field is optional
                    ),
                    const SizedBox(height: 16),

                    // Location Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLocation,
                      decoration: const InputDecoration(
                        labelText: 'Demo Location *',
                        hintText: 'Select demo location',
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
                          return 'Demo Location is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Expected Return Date
                    InkWell(
                      onTap: _selectReturnDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Expected Return Date (Optional)',
                          hintText: 'Tap to select return date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _expectedReturnDate != null
                              ? DateFormat(
                                  'dd/MM/yyyy',
                                ).format(_expectedReturnDate!)
                              : 'No date selected',
                          style: TextStyle(
                            color: _expectedReturnDate != null
                                ? Colors.black87
                                : Colors.grey[600],
                          ),
                        ),
                      ),
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
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: PlatformFeatures.supportsAnyQRFeature
                                  ? _scanQRCode
                                  : null,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: Text(
                                PlatformFeatures.supportsAnyQRFeature
                                    ? 'Scan'
                                    : 'N/A',
                              ),
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
                                    Icons.science,
                                    color: Colors.amber[700],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Selected Items for Demo (${_selectedItems.length})',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber[700],
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
                                    color: Colors.amber[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.amber[200]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.confirmation_number,
                                        color: Colors.amber[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Entry Number: $_nextEntryNumber',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber[700],
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
                                              backgroundColor:
                                                  Colors.amber[100],
                                              child: Text(
                                                '${index + 1}',
                                                style: TextStyle(
                                                  color: Colors.amber[700],
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
                                      ],
                                    ),
                                  );
                                },
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
                                'No items selected. Search and tap on items to add them to the demo.',
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

                    // Remarks Input (Optional)
                    TextFormField(
                      controller: _remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (Optional)',
                        hintText: 'Enter any additional notes or remarks',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Development Section - Delete Recent Demos
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning,
                                color: Colors.red[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Development Tools',
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Delete recent demo records for testing purposes',
                            style: TextStyle(
                              color: Colors.red[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _showDeleteDemoDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[600],
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.delete_forever, size: 18),
                              label: const Text('Delete Recent Demos'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveDemo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Create Demo',
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
}
