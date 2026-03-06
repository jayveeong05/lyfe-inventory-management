import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/order_service.dart';

class ItemDisposeScreen extends StatefulWidget {
  const ItemDisposeScreen({super.key});

  @override
  State<ItemDisposeScreen> createState() => _ItemDisposeScreenState();
}

class _ItemDisposeScreenState extends State<ItemDisposeScreen> {
  final TextEditingController _serialSearchController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  /// List of full item maps (from inventory) for items to dispose
  List<Map<String, dynamic>> _disposeList = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allInventoryItems = [];
  bool _showSearchList = false;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadInventoryItems();
  }

  Future<void> _loadInventoryItems() async {
    try {
      // Only allow disposing items that are in stock (Active). Returned/Demo items
      // are not shown—they follow a different workflow (inspection, etc.).
      final snapshot = await FirebaseFirestore.instance
          .collection('inventory')
          .where('status', isEqualTo: 'Active')
          .limit(2000)
          .get();

      if (mounted) {
        setState(() {
          _allInventoryItems = snapshot.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading inventory: $e')),
        );
      }
    }
  }

  void _onSerialSearchChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _searchResults = List.from(_allInventoryItems);
      } else {
        final lower = value.toLowerCase();
        _searchResults = _allInventoryItems.where((item) {
          final serial =
              item['serial_number']?.toString().toLowerCase() ?? '';
          return serial.contains(lower);
        }).toList();
      }
      _showSearchList = true;
    });
  }

  void _addToDisposeList(Map<String, dynamic> item) {
    final serial = (item['serial_number'] ?? '').toString().trim().toUpperCase();
    if (serial.isEmpty) return;
    final alreadyIn = _disposeList.any((e) =>
        (e['serial_number'] ?? '').toString().trim().toUpperCase() == serial);
    if (alreadyIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$serial is already in the list')),
      );
      return;
    }
    setState(() {
      _disposeList = [..._disposeList, Map<String, dynamic>.from(item)];
      _serialSearchController.clear();
      _searchResults = [];
      _showSearchList = false;
    });
  }

  void _removeFromDisposeList(String serial) {
    final normalized = serial.trim().toUpperCase();
    setState(() {
      _disposeList = _disposeList.where((e) =>
          (e['serial_number'] ?? '').toString().trim().toUpperCase() !=
          normalized).toList();
    });
  }

  Future<void> _submitDispose() async {
    if (_disposeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one serial number to dispose'),
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final orderService = OrderService(authService: authProvider.authService);
      // Pass serials exactly as stored in inventory so the service can find and update the doc
      final serialNumbers = _disposeList
          .map((e) => (e['serial_number'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final result = await orderService.processDisposeItems(
        serialNumbers: serialNumbers,
        remarks: _remarksController.text.trim(),
        userUid: user.uid,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] as String? ?? 'Items disposed successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );
          _disposeList = <Map<String, dynamic>>[];
          _remarksController.clear();
          _loadInventoryItems();
        } else {
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _serialSearchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispose Item'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add items to dispose',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only items currently in stock (Active) can be disposed here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serialSearchController,
                    decoration: InputDecoration(
                      labelText: 'Search serial number',
                      hintText: 'Type to search...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _serialSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _serialSearchController.clear();
                                _onSerialSearchChanged('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _onSerialSearchChanged,
                    onTap: () {
                      if (_serialSearchController.text.isEmpty) {
                        setState(() {
                          _searchResults = List.from(_allInventoryItems);
                          _showSearchList = true;
                        });
                      }
                    },
                  ),
                  if (_showSearchList && _searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
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
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          final serial = item['serial_number']?.toString() ?? '';
                          final status = item['status']?.toString() ?? '';
                          final category = item['equipment_category']?.toString() ?? '—';
                          final model = item['model']?.toString() ?? '—';
                          final alreadyInList = _disposeList.any((e) =>
                              (e['serial_number'] ?? '')
                                  .toString()
                                  .trim()
                                  .toUpperCase() ==
                              serial.trim().toUpperCase());
                          return ListTile(
                            title: Text(
                              serial,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '$category • $model\nStatus: $status',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: alreadyInList
                                ? const Icon(Icons.check, color: Colors.green)
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => _addToDisposeList(item),
                                  ),
                            onTap: alreadyInList
                                ? null
                                : () => _addToDisposeList(item),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Items to dispose',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_disposeList.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'No items added. Search and add serial numbers above.',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    )
                  else
                    ..._disposeList.map((item) {
                      final serial = item['serial_number']?.toString() ?? '';
                      final category = item['equipment_category']?.toString() ?? '—';
                      final model = item['model']?.toString() ?? '—';
                      final status = item['status']?.toString() ?? '—';
                      final size = item['size']?.toString();
                      final location = item['location']?.toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          title: Text(
                            serial,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$category • $model',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (size != null && size.isNotEmpty)
                                  Text(
                                    'Size: $size',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                Text(
                                  'Status: $status${location != null && location.isNotEmpty ? ' • $location' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _removeFromDisposeList(serial),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSubmitting || _disposeList.isEmpty
                        ? null
                        : _submitDispose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Dispose items'),
                  ),
                ],
              ),
            ),
    );
  }
}
