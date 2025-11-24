import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/file_history_service.dart';
import '../models/file_model.dart';

class FileHistoryScreen extends StatefulWidget {
  const FileHistoryScreen({super.key});

  @override
  State<FileHistoryScreen> createState() => _FileHistoryScreenState();
}

class _FileHistoryScreenState extends State<FileHistoryScreen>
    with SingleTickerProviderStateMixin {
  final FileHistoryService _fileHistoryService = FileHistoryService();
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;

  List<Map<String, dynamic>> _ordersWithFiles = [];
  List<FileModel> _selectedOrderFiles = [];
  String? _selectedOrderNumber;
  bool _isLoading = false;
  bool _isLoadingFiles = false;
  String? _errorMessage;

  // Tab indices for file types
  static const int _tabAll = 0;
  static const int _tabInvoice = 1;
  static const int _tabDelivery = 2;
  static const int _tabSignedDelivery = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadOrdersWithFiles();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_selectedOrderNumber != null) {
      _loadOrderFiles(_selectedOrderNumber!);
    }
  }

  Future<void> _loadOrdersWithFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await _fileHistoryService.getOrdersWithFiles();
      setState(() {
        _ordersWithFiles = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _searchOrders(String query) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await _fileHistoryService.searchOrdersWithFiles(query);
      setState(() {
        _ordersWithFiles = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOrderFiles(String orderNumber) async {
    setState(() {
      _isLoadingFiles = true;
      _selectedOrderNumber = orderNumber;
      _selectedOrderFiles = [];
    });

    try {
      List<FileModel> files;

      switch (_tabController.index) {
        case _tabInvoice:
          files = await _fileHistoryService.getOrderFileHistoryByType(
            orderNumber,
            FileConstants.fileTypeInvoice,
          );
          break;
        case _tabDelivery:
          files = await _fileHistoryService.getOrderFileHistoryByType(
            orderNumber,
            FileConstants.fileTypeDeliveryOrder,
          );
          break;
        case _tabSignedDelivery:
          files = await _fileHistoryService.getOrderFileHistoryByType(
            orderNumber,
            FileConstants.fileTypeSignedDeliveryOrder,
          );
          break;
        default:
          files = await _fileHistoryService.getOrderFileHistory(orderNumber);
      }

      setState(() {
        _selectedOrderFiles = files;
        _isLoadingFiles = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _restoreFileVersion(FileModel file) async {
    final confirmed = await _showRestoreConfirmationDialog(file);
    if (!confirmed) return;

    try {
      final success = await _fileHistoryService.restoreFileVersion(file.fileId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File version ${file.version} restored successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload files to show updated active status
        _loadOrderFiles(_selectedOrderNumber!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showRestoreConfirmationDialog(FileModel file) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Restore File Version'),
            content: Text(
              'Are you sure you want to restore version ${file.version} of this ${file.fileType}?\n\n'
              'This will make it the active version and deactivate the current version.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _viewFile(FileModel file) async {
    try {
      final uri = Uri.parse(file.storageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch file URL');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Check admin access
        if (!authProvider.hasAdminAccess()) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Access Denied'),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Admin Access Required',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You need administrator privileges to access file history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('File History Management'),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadOrdersWithFiles,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchSection(),
              _buildOrdersList(),
              if (_selectedOrderNumber != null) ...[
                const Divider(height: 1),
                _buildFileTypeTabs(),
                Expanded(child: _buildFilesList()),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search Orders',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter order number...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchOrders('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: _searchOrders,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error: $_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadOrdersWithFiles,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_ordersWithFiles.isEmpty) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No orders with files found',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      flex: _selectedOrderNumber == null ? 1 : 0,
      child: Container(
        constraints: _selectedOrderNumber == null
            ? null
            : const BoxConstraints(maxHeight: 200),
        child: ListView.builder(
          itemCount: _ordersWithFiles.length,
          itemBuilder: (context, index) {
            final order = _ordersWithFiles[index];
            return _buildOrderCard(order);
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderNumber = order['orderNumber'] as String;
    final totalFiles = order['totalFiles'] as int;
    final invoiceCount = order['invoiceCount'] as int;
    final deliveryCount = order['deliveryCount'] as int;
    final signedDeliveryCount = order['signedDeliveryCount'] as int;
    final lastUploadDate = order['lastUploadDate'] as DateTime;

    final isSelected = _selectedOrderNumber == orderNumber;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.deepPurple[50] : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSelected ? Colors.deepPurple : Colors.blue,
          child: Text(
            totalFiles.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          orderNumber,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.deepPurple : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Files: $totalFiles'),
            Row(
              children: [
                if (invoiceCount > 0) ...[
                  Icon(Icons.receipt, size: 16, color: Colors.blue[600]),
                  Text(' $invoiceCount', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                ],
                if (deliveryCount > 0) ...[
                  Icon(
                    Icons.assignment_turned_in,
                    size: 16,
                    color: Colors.green[600],
                  ),
                  Text(' $deliveryCount', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                ],
                if (signedDeliveryCount > 0) ...[
                  Icon(
                    Icons.local_shipping,
                    size: 16,
                    color: Colors.orange[600],
                  ),
                  Text(
                    ' $signedDeliveryCount',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
            Text(
              'Last Upload: ${DateFormat('dd/MM/yyyy HH:mm').format(lastUploadDate)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Icon(
          isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: isSelected ? Colors.deepPurple : Colors.grey,
        ),
        onTap: () {
          if (isSelected) {
            setState(() {
              _selectedOrderNumber = null;
              _selectedOrderFiles = [];
            });
          } else {
            _loadOrderFiles(orderNumber);
          }
        },
      ),
    );
  }

  Widget _buildFileTypeTabs() {
    return Container(
      color: Colors.grey[100],
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.deepPurple,
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: Colors.deepPurple,
        tabs: const [
          Tab(text: 'All Files'),
          Tab(text: 'Invoices'),
          Tab(text: 'Issued'),
          Tab(text: 'Delivered'),
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    if (_isLoadingFiles) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedOrderFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No files found for this filter',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _selectedOrderFiles.length,
      itemBuilder: (context, index) {
        final file = _selectedOrderFiles[index];
        return _buildFileCard(file);
      },
    );
  }

  Widget _buildFileCard(FileModel file) {
    final isActive = file.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isActive ? 3 : 1,
      color: isActive ? Colors.green[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getFileTypeIcon(file.fileType),
                  color: _getFileTypeColor(file.fileType),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getFileTypeDisplayName(file.fileType),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green : Colors.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isActive ? 'ACTIVE' : 'v${file.version}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        file.originalFilename,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        'Upload Date',
                        DateFormat('dd/MM/yyyy HH:mm').format(file.uploadDate),
                      ),
                      _buildInfoRow(
                        'File Size',
                        '${(file.fileSize / 1024).toStringAsFixed(1)} KB',
                      ),
                      _buildInfoRow('Version', file.version.toString()),
                    ],
                  ),
                ),
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _viewFile(file),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('View'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!isActive)
                      ElevatedButton.icon(
                        onPressed: () => _restoreFileVersion(file),
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Restore'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(100, 36),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  IconData _getFileTypeIcon(String fileType) {
    switch (fileType) {
      case FileConstants.fileTypeInvoice:
        return Icons.receipt;
      case FileConstants.fileTypeDeliveryOrder:
        return Icons.assignment_turned_in;
      case FileConstants.fileTypeSignedDeliveryOrder:
        return Icons.local_shipping;
      default:
        return Icons.description;
    }
  }

  Color _getFileTypeColor(String fileType) {
    switch (fileType) {
      case FileConstants.fileTypeInvoice:
        return Colors.blue;
      case FileConstants.fileTypeDeliveryOrder:
        return Colors.green;
      case FileConstants.fileTypeSignedDeliveryOrder:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getFileTypeDisplayName(String fileType) {
    switch (fileType) {
      case FileConstants.fileTypeInvoice:
        return 'Invoice';
      case FileConstants.fileTypeDeliveryOrder:
        return 'Issued Order';
      case FileConstants.fileTypeSignedDeliveryOrder:
        return 'Delivered Order';
      default:
        return 'Unknown';
    }
  }
}
