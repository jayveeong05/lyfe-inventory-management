import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/warranty_type_service.dart';
import '../utils/platform_features.dart';
import '../screens/qr_scanner_screen.dart';

class EditableItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool showWarranty;
  final Future<bool> Function(
    String newSerial,
    String warrantyType,
    int warrantyPeriod,
  )
  onSave;

  const EditableItemCard({
    Key? key,
    required this.item,
    required this.onSave,
    this.showWarranty = true,
  }) : super(key: key);

  @override
  State<EditableItemCard> createState() => _EditableItemCardState();
}

class _EditableItemCardState extends State<EditableItemCard> {
  bool _isEditing = false;
  late TextEditingController _serialController;
  late String _warrantyType;
  late int _warrantyPeriod;
  bool _isSaving = false;

  // Dynamically loaded from Firestore via WarrantyTypeService
  List<Map<String, dynamic>> _warrantyTypes = [];

  // Search state
  List<Map<String, dynamic>> _activeItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _showSuggestions = false;
  bool _isLoadingItems = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initEditingState();
    _loadWarrantyTypes();
  }

  Future<void> _loadWarrantyTypes() async {
    final types = await WarrantyTypeService().getWarrantyTypes();
    if (mounted) {
      setState(() {
        _warrantyTypes = types;
        // If the current warranty type from the record is not in the loaded
        // list, add it so the dropdown doesn't show an invalid value.
        if (_warrantyType != 'No Warranty' &&
            !_warrantyTypes.any((w) => w['value'] == _warrantyType)) {
          _warrantyTypes.add({
            'display': _warrantyType,
            'value': _warrantyType,
            'period': _warrantyPeriod,
          });
        }
      });
    }
  }

  void _initEditingState() {
    _serialController = TextEditingController(
      text: widget.item['serial_number'],
    );
    _warrantyType = widget.item['warranty_type'] ?? 'No Warranty';
    _warrantyPeriod = widget.item['warranty_period'] ?? 0;
  }

  @override
  void didUpdateWidget(covariant EditableItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing &&
        (oldWidget.item['serial_number'] != widget.item['serial_number'] ||
            oldWidget.item['warranty_type'] != widget.item['warranty_type'])) {
      _initEditingState();
    }
  }

  @override
  void dispose() {
    _serialController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _showSuggestions = false;
      _initEditingState(); // Reset back to initial values
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _showSuggestions = false;
    });
    if (_activeItems.isEmpty) {
      _loadActiveItems();
    }
  }

  Future<void> _loadActiveItems() async {
    try {
      if (mounted) {
        setState(() => _isLoadingItems = true);
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('inventory')
          .where('status', isEqualTo: 'Active')
          .limit(100) // Lowered limit for individual card editing
          .get();

      final activeItems = snapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id, 'current_status': 'Active'};
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
        setState(() => _isLoadingItems = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _activeItems;
        _showSuggestions = false;
        _debounceTimer?.cancel();
      } else {
        // Local Filter
        _filteredItems = _activeItems.where((item) {
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
        _showSuggestions = true;

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
      final inventoryQuery = await FirebaseFirestore.instance
          .collection('inventory')
          .where('serial_number', isGreaterThanOrEqualTo: query)
          .where('serial_number', isLessThan: query + 'z')
          .limit(10)
          .get();

      if (inventoryQuery.docs.isEmpty) return;

      final List<Map<String, dynamic>> newCandidates = [];
      for (final doc in inventoryQuery.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber == null) continue;

        final isAlreadyLoaded = _activeItems.any(
          (item) =>
              (item['serial_number'] ?? '').toString().toLowerCase() ==
              serialNumber.toLowerCase(),
        );

        if (isAlreadyLoaded) continue;

        final status = data['status'] as String? ?? 'Unknown';

        if (status == 'Active') {
          newCandidates.add({
            'serial_number': serialNumber,
            'equipment_category': data['equipment_category'] ?? 'Unknown',
            'model': data['model'] ?? 'Unknown',
          });
        }
      }

      if (newCandidates.isNotEmpty && mounted) {
        setState(() {
          _activeItems.addAll(newCandidates);
          _filteredItems.addAll(newCandidates);
        });
      }
    } catch (e) {
      print('Error in backend search: $e');
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        _serialController.text = result;
      });
      _onSearchChanged(result);
    }
  }

  void _selectItem(Map<String, dynamic> item) {
    setState(() {
      _serialController.text = (item['serial_number'] ?? '').toString();
      _showSuggestions = false;
    });
  }

  Future<void> _handleSave() async {
    final newSerial = _serialController.text.trim();
    if (newSerial.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Serial number cannot be empty.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final success = await widget.onSave(
      newSerial,
      _warrantyType,
      _warrantyPeriod,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _isEditing = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String category = widget.item['equipment_category'] ?? 'N/A';
    final String model = widget.item['model'] ?? 'N/A';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _isEditing
            ? _buildEditForm()
            : _buildDisplayView(category, model),
      ),
    );
  }

  Widget _buildDisplayView(String category, String model) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item['serial_number'] ?? 'N/A',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$category - $model',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (widget.showWarranty)
                Row(
                  children: [
                    Icon(
                      Icons.security,
                      size: 16,
                      color: Colors.green.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Warranty: ${widget.item['warranty_type'] ?? 'No Warranty'}',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.blue),
          onPressed: _startEditing,
          tooltip: 'Edit Item',
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top row for Serial Number Search Field + QR scanner
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _serialController,
                decoration: InputDecoration(
                  labelText: 'Serial Number',
                  hintText: 'Type to search serial number, category, or model',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: _serialController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _serialController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: PlatformFeatures.supportsAnyQRFeature
                    ? Colors.blue.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                onPressed: PlatformFeatures.supportsAnyQRFeature
                    ? _scanQRCode
                    : null,
                icon: Icon(
                  Icons.qr_code_scanner,
                  color: PlatformFeatures.supportsAnyQRFeature
                      ? Colors.blue.shade700
                      : Colors.grey,
                ),
                tooltip: 'Scan QR Code',
              ),
            ),
          ],
        ),

        // Search Suggestions
        if (_showSuggestions && _filteredItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredItems.length > 5 ? 5 : _filteredItems.length,
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
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  onTap: () => _selectItem(item),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey[400],
                  ),
                );
              },
            ),
          ),
        ],

        // Loading indicator for items
        if (_isLoadingItems)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Warranty Section
        if (widget.showWarranty) ...[
          if (_warrantyTypes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading warranty types…'),
                    ],
                  ),
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Warranty Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              value: _warrantyTypes.any((w) => w['value'] == _warrantyType)
                  ? _warrantyType
                  : null,
              items: [
                const DropdownMenuItem(value: null, child: Text('No Warranty')),
                ..._warrantyTypes.map(
                  (w) => DropdownMenuItem(
                    value: w['value'] as String,
                    child: Text(w['display'] as String),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  if (val == null) {
                    _warrantyType = 'No Warranty';
                    _warrantyPeriod = 0;
                  } else {
                    _warrantyType = val;
                    _warrantyPeriod =
                        _warrantyTypes.firstWhere(
                              (w) => w['value'] == val,
                            )['period']
                            as int;
                  }
                });
              },
            ),
          const SizedBox(height: 16),
        ],

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isSaving ? null : _cancelEdit,
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ],
    );
  }
}
