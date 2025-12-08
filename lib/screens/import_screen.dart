import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/auth_provider.dart';
import '../services/import_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportService? _importService;
  bool _isLoading = false;
  String _importType = 'transactions'; // 'transactions' or 'inventory'
  File? _selectedFile;
  String? _selectedFileName;
  Map<String, dynamic>? _importResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_importService == null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _importService = ImportService(authService: authProvider.authService);
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _selectedFileName = result.files.single.name;
          _importResult = null; // Clear previous results
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _performImport() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _importResult = null;
    });

    try {
      Map<String, dynamic> result;

      if (_importType == 'transactions') {
        result = await _importService!.importTransactionLog(_selectedFile!);
      } else {
        result = await _importService!.importInventory(_selectedFile!);
      }

      setState(() {
        _importResult = result;
      });

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Import completed successfully',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Import failed'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _importResult = {
          'success': false,
          'error': 'Import failed: ${e.toString()}',
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
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
        title: const Text('Import Data'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Import Type Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Import Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<String>(
                      title: const Text('Transaction Log'),
                      subtitle: const Text(
                        'Import transaction data (Stock In/Out)',
                      ),
                      value: 'transactions',
                      groupValue: _importType,
                      onChanged: (value) {
                        setState(() {
                          _importType = value!;
                          _selectedFile = null;
                          _selectedFileName = null;
                          _importResult = null;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Inventory'),
                      subtitle: const Text('Import inventory items'),
                      value: 'inventory',
                      groupValue: _importType,
                      onChanged: (value) {
                        setState(() {
                          _importType = value!;
                          _selectedFile = null;
                          _selectedFileName = null;
                          _importResult = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // File Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'File Selection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedFileName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.insert_drive_file,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedFileName!,
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _selectedFile = null;
                                  _selectedFileName = null;
                                  _importResult = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.file_upload),
                      label: Text(
                        _selectedFileName == null
                            ? 'Select File (.xlsx, .xls, .csv)'
                            : 'Change File',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Import Button
            ElevatedButton.icon(
              onPressed: (_selectedFile != null && !_isLoading)
                  ? _performImport
                  : null,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isLoading ? 'Importing...' : 'Start Import'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Results Section
            if (_importResult != null) ...[
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _importResult!['success'] == true
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: _importResult!['success'] == true
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Import Results',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _importResult!['success'] == true
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_importResult!['success'] == true) ...[
                          Text(
                            _importResult!['message'] ??
                                'Import completed successfully',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          if (_importResult!['transactions_imported'] != null)
                            Text(
                              'Transactions imported: ${_importResult!['transactions_imported']}',
                            ),
                          if (_importResult!['inventory_imported'] != null)
                            Text(
                              'Inventory items imported: ${_importResult!['inventory_imported']}',
                            ),
                        ] else ...[
                          Text(
                            _importResult!['error'] ?? 'Import failed',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ],
                        if (_importResult!['errors'] != null &&
                            (_importResult!['errors'] as List).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Errors:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: ListView.builder(
                                itemCount:
                                    (_importResult!['errors'] as List).length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '• ${(_importResult!['errors'] as List)[index]}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
