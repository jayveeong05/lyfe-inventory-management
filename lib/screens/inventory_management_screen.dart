import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/inventory_management_service.dart';
import 'stock_in_screen.dart';
import 'stock_out_screen.dart';

class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({super.key});

  @override
  State<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  final InventoryManagementService _inventoryService =
      InventoryManagementService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Data state
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _summary;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  DocumentSnapshot? _lastDocument;

  // Filter state
  String? _selectedCategory;
  String? _selectedStatus;
  String? _selectedLocation;
  String? _selectedSize;
  String _searchQuery = '';

  // Filter options
  List<String> _categories = [];
  List<String> _locations = [];
  List<String> _sizes = [];
  final List<String> _statusOptions = [
    'Active',
    'Reserved',
    'Invoiced',
    'Issued',
    'Delivered',
    'Demo',
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  Future<void> _initializeData() async {
    await _loadFilterOptions();
    await _loadSummary();
    await _loadItems(refresh: true);
  }

  Future<void> _loadFilterOptions() async {
    final result = await _inventoryService.getFilterOptions();
    if (result['success'] == true) {
      setState(() {
        _categories = List<String>.from(result['categories'] ?? []);
        _locations = List<String>.from(result['locations'] ?? []);
        _sizes = List<String>.from(result['sizes'] ?? []);
      });
    }
  }

  Future<void> _loadSummary() async {
    final result = await _inventoryService.getInventorySummary();
    if (result['success'] == true && mounted) {
      setState(() {
        _summary = result;
      });
    }
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (refresh) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _items.clear();
        _lastDocument = null;
        _hasMore = true;
        _error = null;
      });
    } else if (_isLoadingMore || !_hasMore) {
      return;
    } else {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    final result = await _inventoryService.getInventoryItems(
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      categoryFilter: _selectedCategory,
      statusFilter: _selectedStatus,
      locationFilter: _selectedLocation,
      sizeFilter: _selectedSize,
      lastDocument: _lastDocument,
      limit: 20,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;

      if (result['success'] == true) {
        final newItems = List<Map<String, dynamic>>.from(result['items'] ?? []);
        if (refresh) {
          _items = newItems;
        } else {
          _items.addAll(newItems);
        }
        _hasMore = result['hasMore'] ?? false;
        _lastDocument = result['lastDocument'];
        _error = null;
      } else {
        _error = result['error'];
      }
    });
  }

  Future<void> _loadMoreItems() async {
    if (!_isLoadingMore && _hasMore) {
      await _loadItems();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _debounceSearch();
  }

  Timer? _debounceTimer;
  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _loadItems(refresh: true);
    });
  }

  void _onFilterChanged() {
    _loadItems(refresh: true);
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedStatus = null;
      _selectedLocation = null;
      _selectedSize = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadItems(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadItems(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCards(),
          _buildSearchAndFilters(),
          Expanded(child: _buildItemsList()),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "stock_in",
            onPressed: () => _navigateToStockIn(),
            backgroundColor: Colors.green,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "stock_out",
            onPressed: () => _navigateToStockOut(),
            backgroundColor: Colors.orange,
            child: const Icon(Icons.remove, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (_summary == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Total',
                  '${_summary!['total_items'] ?? 0}',
                  Icons.inventory,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryCard(
                  'Active',
                  '${_summary!['active_items'] ?? 0}',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Reserved',
                  '${_summary!['reserved_items'] ?? 0}',
                  Icons.pending,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryCard(
                  'Delivered',
                  '${_summary!['delivered_items'] ?? 0}',
                  Icons.local_shipping,
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by serial number, model, category...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Category', _selectedCategory, _categories, (
                  value,
                ) {
                  setState(() => _selectedCategory = value);
                  _onFilterChanged();
                }),
                _buildFilterChip('Status', _selectedStatus, _statusOptions, (
                  value,
                ) {
                  setState(() => _selectedStatus = value);
                  _onFilterChanged();
                }),
                _buildFilterChip('Location', _selectedLocation, _locations, (
                  value,
                ) {
                  setState(() => _selectedLocation = value);
                  _onFilterChanged();
                }),
                _buildFilterChip('Size', _selectedSize, _sizes, (value) {
                  setState(() => _selectedSize = value);
                  _onFilterChanged();
                }),
                if (_hasActiveFilters())
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ActionChip(
                      label: const Text('Clear All'),
                      onPressed: _clearFilters,
                      backgroundColor: Colors.red.shade100,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedCategory != null ||
        _selectedStatus != null ||
        _selectedLocation != null ||
        _selectedSize != null ||
        _searchQuery.isNotEmpty;
  }

  Widget _buildFilterChip(
    String label,
    String? selectedValue,
    List<String> options,
    Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(selectedValue ?? label),
        selected: selectedValue != null,
        onSelected: (selected) {
          if (selected) {
            _showFilterDialog(label, options, selectedValue, onChanged);
          } else {
            onChanged(null);
          }
        },
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue.shade600,
      ),
    );
  }

  void _showFilterDialog(
    String title,
    List<String> options,
    String? currentValue,
    Function(String?) onChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select $title'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('All'),
                leading: Radio<String?>(
                  value: null,
                  groupValue: currentValue,
                  onChanged: (value) {
                    onChanged(value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  onChanged(null);
                  Navigator.pop(context);
                },
              ),
              ...options.map(
                (option) => ListTile(
                  title: Text(option),
                  leading: Radio<String?>(
                    value: option,
                    groupValue: currentValue,
                    onChanged: (value) {
                      onChanged(value);
                      Navigator.pop(context);
                    },
                  ),
                  onTap: () {
                    onChanged(option);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadItems(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _hasActiveFilters()
                  ? 'No items match your filters'
                  : 'No inventory items found',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_hasActiveFilters()) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _clearFilters,
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadItems(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return _buildLoadMoreIndicator();
          }
          return _buildInventoryItem(_items[index]);
        },
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    final status = item['current_status'] as String? ?? 'Unknown';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.shade100,
          child: Icon(statusIcon, color: statusColor.shade600, size: 20),
        ),
        title: Text(
          item['serial_number'] ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item['equipment_category']} • ${item['model']}'),
            Text(
              'Status: $status • Location: ${item['current_location']}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleItemAction(value, item),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'details', child: Text('View Details')),
            if (status == 'Active')
              const PopupMenuItem(value: 'stock_out', child: Text('Stock Out')),
            const PopupMenuItem(value: 'edit', child: Text('Edit Item')),
            const PopupMenuItem(value: 'delete', child: Text('Delete Item')),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Size', item['size'] ?? 'N/A'),
                _buildDetailRow('Batch', item['batch'] ?? 'N/A'),
                _buildDetailRow(
                  'Transaction Count',
                  '${item['transaction_count'] ?? 0}',
                ),
                if (item['last_activity'] != null)
                  _buildDetailRow(
                    'Last Activity',
                    _formatDate(item['last_activity']),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  MaterialColor _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'reserved':
        return Colors.orange;
      case 'delivered':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.check_circle;
      case 'reserved':
        return Icons.pending;
      case 'invoiced':
        return Icons.receipt;
      case 'issued':
        return Icons.assignment_turned_in;
      case 'delivered':
        return Icons.local_shipping;
      case 'demo':
        return Icons.play_circle_outline;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _handleItemAction(String action, Map<String, dynamic> item) {
    switch (action) {
      case 'details':
        _showItemDetails(item);
        break;
      case 'stock_out':
        _navigateToStockOutWithItem(item);
        break;
      case 'edit':
        _showEditItemDialog(item);
        break;
      case 'delete':
        _showDeleteConfirmationDialog(item);
        break;
    }
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Item Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Serial Number', item['serial_number'] ?? 'N/A'),
            _buildDetailRow('Category', item['equipment_category'] ?? 'N/A'),
            _buildDetailRow('Model', item['model'] ?? 'N/A'),
            _buildDetailRow('Size', item['size'] ?? 'N/A'),
            _buildDetailRow('Batch', item['batch'] ?? 'N/A'),
            _buildDetailRow('Status', item['current_status'] ?? 'N/A'),
            _buildDetailRow('Location', item['current_location'] ?? 'N/A'),
            _buildDetailRow(
              'Transactions',
              '${item['transaction_count'] ?? 0}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateToStockIn() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StockInScreen()),
    );
    if (result == true) {
      _loadItems(refresh: true);
      _loadSummary();
    }
  }

  void _navigateToStockOut() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StockOutScreen()),
    );
    if (result == true) {
      _loadItems(refresh: true);
      _loadSummary();
    }
  }

  void _navigateToStockOutWithItem(Map<String, dynamic> item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StockOutScreen()),
    );
    if (result == true) {
      _loadItems(refresh: true);
      _loadSummary();
    }
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    final formKey = GlobalKey<FormState>();
    final serialController = TextEditingController(
      text: item['serial_number'] ?? '',
    );
    final categoryController = TextEditingController(
      text: item['equipment_category'] ?? '',
    );
    final modelController = TextEditingController(text: item['model'] ?? '');
    final sizeController = TextEditingController(text: item['size'] ?? '');
    final batchController = TextEditingController(text: item['batch'] ?? '');
    final remarksController = TextEditingController(text: item['remark'] ?? '');

    // Store the parent context for snackbar
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing during update
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          bool isUpdating = false;

          return AlertDialog(
            title: const Text('Edit Item'),
            content: SizedBox(
              width: double.maxFinite,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Serial Number field (similar to stock-in)
                      TextFormField(
                        controller: serialController,
                        decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Serial number is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Equipment Category field
                      TextFormField(
                        controller: categoryController,
                        decoration: const InputDecoration(
                          labelText: 'Equipment Category',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                          hintText: 'e.g., Interactive Flat Panel',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Equipment category is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Model field
                      TextFormField(
                        controller: modelController,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.precision_manufacturing),
                          hintText: 'e.g., 65M6APRO, 9002',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Model is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Size field (optional)
                      TextFormField(
                        controller: sizeController,
                        decoration: const InputDecoration(
                          labelText: 'Size (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.straighten),
                          hintText:
                              'e.g., 65 Inch, 75 Inch (leave empty if not applicable)',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Batch field
                      TextFormField(
                        controller: batchController,
                        decoration: const InputDecoration(
                          labelText: 'Batch',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory),
                          hintText: 'e.g., 成品出库-EDS01',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Batch is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Remarks field (optional)
                      TextFormField(
                        controller: remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.note),
                          hintText: 'Additional notes or comments',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isUpdating
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          // Show loading indicator first (before closing dialog)
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Updating item...'),
                                ],
                              ),
                              duration: Duration(seconds: 30),
                            ),
                          );

                          // Close the edit dialog after showing snackbar
                          Navigator.pop(context);

                          final updatedData = {
                            'serial_number': serialController.text.trim(),
                            'equipment_category': categoryController.text
                                .trim(),
                            'model': modelController.text.trim(),
                            'size': sizeController.text.trim().isEmpty
                                ? null
                                : sizeController.text.trim(),
                            'batch': batchController.text.trim(),
                            'remark': remarksController.text.trim().isEmpty
                                ? null
                                : remarksController.text.trim(),
                          };

                          print(
                            'DEBUG: About to update item with data: $updatedData',
                          );
                          await _updateItem(item, updatedData);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteConfirmationDialog(Map<String, dynamic> item) {
    // Store the parent context for snackbar
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Are you sure you want to delete item "${item['serial_number']}"?\n\n'
          'This will also delete all related transactions and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close the delete dialog immediately
              Navigator.pop(context);

              // Show loading indicator using the parent context
              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Deleting item...'),
                    ],
                  ),
                  duration: Duration(seconds: 30),
                ),
              );

              await _deleteItem(item);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateItem(
    Map<String, dynamic> item,
    Map<String, dynamic> updatedData,
  ) async {
    print(
      'DEBUG: _updateItem called with item: ${item['id']}, updatedData: $updatedData',
    );

    // Prepare original data for transaction log
    final originalData = {
      'serial_number': item['serial_number'],
      'equipment_category': item['equipment_category'],
      'model': item['model'],
      'size': item['size'],
      'batch': item['batch'],
      'remark': item['remark'] ?? '',
    };

    print('DEBUG: Calling updateInventoryItem service...');
    final result = await _inventoryService.updateInventoryItem(
      item['id'] ?? '',
      updatedData,
      originalData,
    );

    print('DEBUG: Service returned result: $result');

    // Dismiss the loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Show completion dialog with options
    if (mounted) {
      _showUpdateCompletionDialog(result, item, updatedData);
    }
  }

  void _showUpdateCompletionDialog(
    Map<String, dynamic> result,
    Map<String, dynamic> item,
    Map<String, dynamic> updatedData,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result['success'] ? Icons.check_circle : Icons.error,
              color: result['success'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result['success'] ? 'Update Successful' : 'Update Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result['success']
                  ? 'Item has been updated successfully!'
                  : 'Failed to update item: ${result['error']}',
            ),
            if (result['success']) ...[
              const SizedBox(height: 8),
              Text(
                'Transaction ID: ${result['transaction_id']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          if (result['success']) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close completion dialog
                // Create updated item data for the edit dialog
                final updatedItem = Map<String, dynamic>.from(item);
                updatedItem.addAll(updatedData);
                _showEditItemDialog(updatedItem);
              },
              child: const Text('Edit Again'),
            ),
          ],
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close completion dialog
              // Refresh data
              if (mounted) {
                _loadItems(refresh: true);
                _loadSummary();
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: result['success'] ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    print('DEBUG: _deleteItem called with item: ${item['id']}');

    print('DEBUG: Calling deleteInventoryItem service...');
    final result = await _inventoryService.deleteInventoryItem(
      item['id'] ?? '',
      item['serial_number'] ?? '',
    );

    print('DEBUG: Delete service returned result: $result');

    // Dismiss the loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    // Show completion dialog with options
    if (mounted) {
      _showDeleteCompletionDialog(result, item);
    }
  }

  void _showDeleteCompletionDialog(
    Map<String, dynamic> result,
    Map<String, dynamic> item,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result['success'] ? Icons.check_circle : Icons.error,
              color: result['success'] ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result['success'] ? 'Delete Successful' : 'Delete Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result['success']
                  ? 'Item "${item['serial_number']}" has been deleted successfully!'
                  : 'Failed to delete item: ${result['error']}',
            ),
            if (result['success']) ...[
              const SizedBox(height: 8),
              const Text(
                'All related transactions have also been removed.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close completion dialog
              // Refresh data
              if (mounted) {
                _loadItems(refresh: true);
                _loadSummary();
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: result['success'] ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
