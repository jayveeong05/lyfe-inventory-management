import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_upload_service.dart';
import '../providers/auth_provider.dart';

class DataUploadScreen extends StatefulWidget {
  const DataUploadScreen({super.key});

  @override
  State<DataUploadScreen> createState() => _DataUploadScreenState();
}

class _DataUploadScreenState extends State<DataUploadScreen> {
  DataUploadService? _uploadService;
  bool _isUploading = false;
  final List<Map<String, dynamic>> _uploadResults = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uploadService == null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _uploadService = DataUploadService(authService: authProvider.authService);
    }
  }

  Future<void> _uploadInventoryData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.hasAdminAccess()) {
      _showErrorDialog(
        'Access Denied',
        'Admin privileges required to upload data.',
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadResults.clear();
    });

    try {
      final result = await _uploadService!.uploadInventoryData();
      setState(() {
        _uploadResults.add(result);
      });

      if (result['success']) {
        _showSuccessDialog('Inventory Data Upload', result);
      } else {
        _showErrorDialog(
          'Inventory Data Upload Failed',
          result['message'] ?? result['error'],
        );
      }
    } catch (e) {
      _showErrorDialog('Upload Error', e.toString());
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _uploadTransactionData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.hasAdminAccess()) {
      _showErrorDialog(
        'Access Denied',
        'Admin privileges required to upload data.',
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadResults.clear();
    });

    try {
      final result = await _uploadService!.uploadTransactionData();
      setState(() {
        _uploadResults.add(result);
      });

      if (result['success']) {
        _showSuccessDialog('Transaction Data Upload', result);
      } else {
        _showErrorDialog(
          'Transaction Data Upload Failed',
          result['message'] ?? result['error'],
        );
      }
    } catch (e) {
      _showErrorDialog('Upload Error', e.toString());
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _uploadAllData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.hasAdminAccess()) {
      _showErrorDialog(
        'Access Denied',
        'Admin privileges required to upload data.',
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadResults.clear();
    });

    try {
      final results = await _uploadService!.uploadAllData();
      setState(() {
        _uploadResults.addAll(results);
      });

      _showAllResultsDialog(results);
    } catch (e) {
      _showErrorDialog('Upload Error', e.toString());
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _clearData(String collection) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.hasAdminAccess()) {
      _showErrorDialog(
        'Access Denied',
        'Admin privileges required to clear data.',
      );
      return;
    }

    final confirmed = await _showConfirmDialog(
      'Clear Data',
      'Are you sure you want to delete all data from the "$collection" collection? This action cannot be undone.',
    );

    if (confirmed) {
      setState(() {
        _isUploading = true;
      });

      try {
        final result = await _uploadService!.clearCollection(collection);
        if (result['success']) {
          _showSuccessDialog('Data Cleared', result);
        } else {
          _showErrorDialog(
            'Clear Data Failed',
            result['message'] ?? result['error'],
          );
        }
      } catch (e) {
        _showErrorDialog('Clear Error', e.toString());
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showSuccessDialog(String title, Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ Upload completed successfully!'),
            const SizedBox(height: 8),
            Text('Collection: ${result['collection']}'),
            Text('Total Records: ${result['total_records']}'),
            Text('Successful: ${result['successful_uploads']}'),
            Text('Failed: ${result['failed_uploads']}'),
            if (result['errors'] != null &&
                (result['errors'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(result['errors'] as List)
                  .take(3)
                  .map((error) => Text('• $error')),
              if ((result['errors'] as List).length > 3)
                Text(
                  '... and ${(result['errors'] as List).length - 3} more errors',
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text('❌ $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAllResultsDialog(List<Map<String, dynamic>> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Results'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: results.map((result) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result['collection']} Collection',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(result['success'] ? '✅ Success' : '❌ Failed'),
                      if (result['success']) ...[
                        Text('Total: ${result['total_records']}'),
                        Text('Uploaded: ${result['successful_uploads']}'),
                        Text('Failed: ${result['failed_uploads']}'),
                      ] else
                        Text('Error: ${result['error']}'),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Upload Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload Excel Data to Firestore',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will upload data from your Excel files to Firebase Firestore collections.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Upload buttons
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadInventoryData,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Inventory Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadTransactionData,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Transaction Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadAllData,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload All Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Clear data section
            const Text(
              'Clear Data (Danger Zone)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isUploading ? null : () => _clearData('inventory'),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Clear Inventory Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _isUploading ? null : () => _clearData('transactions'),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Clear Transaction Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            if (_isUploading) ...[
              const SizedBox(height: 24),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Uploading data...'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
