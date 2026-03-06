import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/order_service.dart';

class ItemReturnedScreen extends StatefulWidget {
  const ItemReturnedScreen({super.key});

  @override
  State<ItemReturnedScreen> createState() => _ItemReturnedScreenState();
}

class _ItemReturnedScreenState extends State<ItemReturnedScreen> {
  // Controllers
  final TextEditingController _dealerSearchController = TextEditingController();
  final TextEditingController _clientSearchController = TextEditingController();
  final TextEditingController _replacementSearchController =
      TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _serialSearchController = TextEditingController();

  // State variables
  String? _selectedSerialNumber;
  List<String> _dealerSearchResults = [];
  List<String> _clientSearchResults = [];
  List<String> _replacementSearchResults = [];
  List<String> _serialSearchResults = [];
  bool _showDealerSearchList = false;
  bool _showClientSearchList = false;
  bool _showReplacementSearchList = false;
  bool _showSerialSearchList = false;
  bool _isLoading = true;
  bool _isBroken = true;

  // Data storage
  final Set<String> _allDealersAndClients = {};
  final Map<String, Set<String>> _dealerToSerialNumbers = {};
  final Map<String, Set<String>> _entityRoles =
      {}; // Tracks whether entity is Dealer, Client, or both
  List<String> _availableSerialNumbers = [];
  List<Map<String, dynamic>> _activeInventoryItems = [];

  @override
  void initState() {
    super.initState();
    _fetchDealersAndClients();
    _loadActiveInventoryItems();
  }

  Future<void> _loadActiveInventoryItems() async {
    try {
      // Query inventory directly for Active items (for replacements)
      final inventoryQuery = await FirebaseFirestore.instance
          .collection('inventory')
          .where('status', isEqualTo: 'Active')
          .limit(1000)
          .get();

      if (inventoryQuery.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _activeInventoryItems = [];
          });
        }
        return;
      }

      final allInventoryItems = inventoryQuery.docs
          .map((doc) => doc.data())
          .toList();

      if (mounted) {
        setState(() {
          _activeInventoryItems = allInventoryItems;
        });
      }
    } catch (e) {
      print('Error loading active items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading replacement items: $e')),
        );
      }
    }
  }

  Future<void> _fetchDealersAndClients() async {
    try {
      // 1. Fetch all orders to get current transaction_ids
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .get();

      // Collect all transaction IDs currently in orders
      final Set<int> activeTransactionIds = {};
      for (final orderDoc in ordersSnapshot.docs) {
        final data = orderDoc.data();
        final transIds = data['transaction_ids'] as List<dynamic>?;
        if (transIds != null) {
          for (final id in transIds) {
            if (id is int) {
              activeTransactionIds.add(id);
            } else if (id is num) {
              activeTransactionIds.add(id.toInt());
            }
          }
        }
      }

      if (activeTransactionIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 2. Fetch transactions matching those IDs
      // Firestore 'whereIn' has a limit of 30, so we batch the queries
      final transIdList = activeTransactionIds.toList();
      final allTransactionDocs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (int i = 0; i < transIdList.length; i += 30) {
        final batchIds = transIdList.sublist(
          i,
          i + 30 > transIdList.length ? transIdList.length : i + 30,
        );
        final batchSnapshot = await FirebaseFirestore.instance
            .collection('transactions')
            .where('transaction_id', whereIn: batchIds)
            .get();
        allTransactionDocs.addAll(batchSnapshot.docs);
      }

      // 3. Build dealer/client and serial number maps from active order items only
      for (final doc in allTransactionDocs) {
        final data = doc.data();
        final type = data['type'] as String?;
        if (type != 'Stock_Out')
          continue; // Only include Stock_Out transactions

        final dealer = data['customer_dealer'] as String?;
        final client = data['customer_client'] as String?;
        final serialNumber = data['serial_number']
            ?.toString()
            .trim()
            .toUpperCase();

        if (serialNumber != null && serialNumber.isNotEmpty) {
          if (dealer != null && dealer.isNotEmpty && dealer != 'N/A') {
            _allDealersAndClients.add(dealer);
            _dealerToSerialNumbers.putIfAbsent(dealer, () => {});
            _dealerToSerialNumbers[dealer]!.add(serialNumber);
            _entityRoles.putIfAbsent(dealer, () => {});
            _entityRoles[dealer]!.add('Dealer');
          }
          if (client != null && client.isNotEmpty && client != 'N/A') {
            _allDealersAndClients.add(client);
            _dealerToSerialNumbers.putIfAbsent(client, () => {});
            _dealerToSerialNumbers[client]!.add(serialNumber);
            _entityRoles.putIfAbsent(client, () => {});
            _entityRoles[client]!.add('Client');
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching order items: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  @override
  void dispose() {
    _dealerSearchController.dispose();
    _clientSearchController.dispose();
    _replacementSearchController.dispose();
    _remarkController.dispose();
    _serialSearchController.dispose();
    super.dispose();
  }

  void _onDealerSearchChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _dealerSearchResults = [];
        _showDealerSearchList = false;
      } else {
        final query = value.toLowerCase();
        _dealerSearchResults = _allDealersAndClients
            .where((name) => name.toLowerCase().contains(query))
            .toList();
        _showDealerSearchList = true;
      }
    });
  }

  void _onDealerSelected(String name) {
    setState(() {
      _dealerSearchController.text = name;
      _showDealerSearchList = false;
      _selectedSerialNumber = null;
      _serialSearchController.clear();
      // Combine serial numbers from both dealer and client if both are selected
      _updateAvailableSerialNumbers();
    });
  }

  void _onClientSearchChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _clientSearchResults = [];
        _showClientSearchList = false;
      } else {
        final query = value.toLowerCase();
        _clientSearchResults = _allDealersAndClients
            .where((name) => name.toLowerCase().contains(query))
            .toList();
        _showClientSearchList = true;
      }
    });
  }

  void _onClientSelected(String name) {
    setState(() {
      _clientSearchController.text = name;
      _showClientSearchList = false;
      _selectedSerialNumber = null;
      _serialSearchController.clear();
      // Combine serial numbers from both dealer and client if both are selected
      _updateAvailableSerialNumbers();
    });
  }

  void _updateAvailableSerialNumbers() {
    final dealerSerials =
        _dealerToSerialNumbers[_dealerSearchController.text] ?? {};
    final clientSerials =
        _dealerToSerialNumbers[_clientSearchController.text] ?? {};

    // Combine unique serial numbers from both
    final combinedSerials = <String>{...dealerSerials, ...clientSerials};
    _availableSerialNumbers = combinedSerials.toList();
    _availableSerialNumbers.sort();
    _serialSearchResults = List.from(_availableSerialNumbers);
  }

  void _onSerialSearchChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _serialSearchResults = List.from(_availableSerialNumbers);
      } else {
        final query = value.toLowerCase();
        _serialSearchResults = _availableSerialNumbers
            .where((serial) => serial.toLowerCase().contains(query))
            .toList();
      }
      _showSerialSearchList = true;
    });
  }

  void _onReplacementSearchChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _replacementSearchResults = [];
        _showReplacementSearchList = false;
      } else {
        final query = value.toLowerCase();
        _replacementSearchResults = _activeInventoryItems
            .where((item) {
              final serial =
                  item['serial_number']?.toString().toLowerCase() ?? '';
              return serial.contains(query);
            })
            .map((item) => item['serial_number'] as String)
            .toList();
        _showReplacementSearchList = true;
      }
    });
  }

  Future<void> _submitReturn() async {
    // Validate inputs - require at least dealer or client
    if (_dealerSearchController.text.isEmpty &&
        _clientSearchController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least a Dealer or Client'),
        ),
      );
      return;
    }
    if (_selectedSerialNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Returned Serial Number')),
      );
      return;
    }
    if (_replacementSearchController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Replacement Serial Number'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderService = OrderService(authService: authProvider.authService);
      final user = authProvider.user;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Use dealer if available, otherwise use client
      final dealerName = _dealerSearchController.text.isNotEmpty
          ? _dealerSearchController.text
          : _clientSearchController.text;

      final result = await orderService.processItemReturn(
        returnedSerial: _selectedSerialNumber!,
        replacementSerial: _replacementSearchController.text,
        dealerName: dealerName,
        remarks: _remarkController.text,
        userUid: user.uid,
        isBroken: _isBroken,
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Return processed successfully'),
              backgroundColor: Colors.green,
            ),
          );
          // Clear cached state before refetching
          _allDealersAndClients.clear();
          _dealerToSerialNumbers.clear();
          _entityRoles.clear();

          // Reload data first so list is up to date, then clear form
          await _fetchDealersAndClients();
          await _loadActiveInventoryItems();

          if (!mounted) return;

          _dealerSearchController.clear();
          _clientSearchController.clear();
          _serialSearchController.clear();
          _replacementSearchController.clear();
          _remarkController.clear();

          setState(() {
            _selectedSerialNumber = null;
            _availableSerialNumbers = [];
            _serialSearchResults =
                []; // Clear returned serial dropdown so it doesn't show stale list
            _replacementSearchResults =
                []; // Clear replacement dropdown so it doesn't show stale list
            _showReplacementSearchList = false;
            // Keep _activeInventoryItems as-is (already refreshed by await _loadActiveInventoryItems above)
            _isBroken = true; // Reset to default
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['error']}'),
              backgroundColor: Colors.red,
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Returned'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildReturnedSection(),
                  const SizedBox(height: 24),
                  const Divider(thickness: 2),
                  const SizedBox(height: 24),
                  _buildReplacementSection(),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitReturn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Submit'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildReturnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Returned Section',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
        const SizedBox(height: 16),

        // Dealer Search
        TextField(
          controller: _dealerSearchController,
          decoration: InputDecoration(
            labelText: 'Dealer Name',
            hintText: 'Search Dealer...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: () {
                setState(() {
                  if (!_showDealerSearchList) {
                    _dealerSearchResults = _allDealersAndClients.toList();
                    _dealerSearchResults.sort();
                    _showDealerSearchList = true;
                  } else {
                    _showDealerSearchList = false;
                  }
                });
              },
            ),
          ),
          onChanged: _onDealerSearchChanged,
          onTap: () {
            setState(() {
              _dealerSearchResults = _allDealersAndClients.toList();
              _dealerSearchResults.sort();
              _showDealerSearchList = true;
            });
          },
        ),

        if (_showDealerSearchList)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _dealerSearchResults.length,
              itemBuilder: (context, index) {
                final dealer = _dealerSearchResults[index];
                final roles = _entityRoles[dealer]?.join(', ') ?? 'Unknown';
                return ListTile(
                  title: Text(dealer),
                  subtitle: Text(
                    'Recorded as: $roles',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () => _onDealerSelected(dealer),
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Client Search
        TextField(
          controller: _clientSearchController,
          decoration: InputDecoration(
            labelText: 'Client Name (Optional)',
            hintText: 'Search Client...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.business),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: () {
                setState(() {
                  if (!_showClientSearchList) {
                    _clientSearchResults = _allDealersAndClients.toList();
                    _clientSearchResults.sort();
                    _showClientSearchList = true;
                  } else {
                    _showClientSearchList = false;
                  }
                });
              },
            ),
          ),
          onChanged: _onClientSearchChanged,
          onTap: () {
            setState(() {
              _clientSearchResults = _allDealersAndClients.toList();
              _clientSearchResults.sort();
              _showClientSearchList = true;
            });
          },
        ),

        if (_showClientSearchList)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _clientSearchResults.length,
              itemBuilder: (context, index) {
                final client = _clientSearchResults[index];
                final roles = _entityRoles[client]?.join(', ') ?? 'Unknown';
                return ListTile(
                  title: Text(client),
                  subtitle: Text(
                    'Recorded as: $roles',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () => _onClientSelected(client),
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Serial Number Selection (Searchable Dropdown)
        TextField(
          controller: _serialSearchController,
          decoration: InputDecoration(
            labelText: 'Select Returned Serial Number',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.qr_code),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: () {
                setState(() {
                  if (!_showSerialSearchList) {
                    _serialSearchResults = List.from(_availableSerialNumbers);
                    _showSerialSearchList = true;
                  } else {
                    _showSerialSearchList = false;
                  }
                });
              },
            ),
          ),
          onTap: () {
            setState(() {
              if (_serialSearchController.text.isEmpty) {
                _serialSearchResults = List.from(_availableSerialNumbers);
              }
              _showSerialSearchList = true;
            });
          },
          onChanged: _onSerialSearchChanged,
        ),

        if (_showSerialSearchList && _availableSerialNumbers.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _serialSearchResults.length,
              itemBuilder: (context, index) {
                final serial = _serialSearchResults[index];
                return ListTile(
                  title: Text(serial),
                  onTap: () {
                    setState(() {
                      _selectedSerialNumber = serial;
                      _serialSearchController.text = serial;
                      _showSerialSearchList = false;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildReplacementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Replacement Section',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
        const SizedBox(height: 16),

        // Replacement Serial Search
        TextField(
          controller: _replacementSearchController,
          decoration: InputDecoration(
            labelText: 'Search Replacement Serial Number',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _replacementSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _replacementSearchController.clear();
                      _onReplacementSearchChanged('');
                    },
                  )
                : null,
          ),
          onChanged: _onReplacementSearchChanged,
        ),

        if (_showReplacementSearchList)
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _replacementSearchResults.length,
              itemBuilder: (context, index) {
                final serial = _replacementSearchResults[index];
                return ListTile(
                  title: Text(serial),
                  onTap: () {
                    setState(() {
                      _replacementSearchController.text = serial;
                      _showReplacementSearchList = false;
                    });
                  },
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Remarks
        TextField(
          controller: _remarkController,
          decoration: const InputDecoration(
            labelText: 'Remarks',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          title: const Text('Item is Broken/Malfunctioning'),
          subtitle: const Text(
            'If checked, item status remains "Returned". If unchecked, status becomes "Active" and can be reused.',
          ),
          value: _isBroken,
          onChanged: (bool? value) {
            setState(() {
              _isBroken = value ?? true;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.teal,
        ),
      ],
    );
  }
}
