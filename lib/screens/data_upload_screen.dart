import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
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

  Future<void> _pickAndUploadFile(
    String type,
    Future<Map<String, dynamic>> Function(Uint8List, String) uploadFunction, {
    Future<Map<String, dynamic>> Function(Uint8List, String)? validateFunction,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.hasAdminAccess()) {
      _showErrorDialog(
        'Access Denied',
        'Admin privileges required to upload data.',
      );
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null) {
        final fileBytes = result.files.first.bytes;
        final fileName = result.files.first.name;

        if (fileBytes == null) {
          _showErrorDialog('Error', 'Could not read file data.');
          return;
        }

        // Validation Step
        if (validateFunction != null) {
          setState(() => _isUploading = true);
          try {
            final validationResult = await validateFunction(
              fileBytes,
              fileName,
            );
            setState(() => _isUploading = false);

            if (validationResult['valid'] == false &&
                validationResult.containsKey('message')) {
              _showErrorDialog('Validation Error', validationResult['message']);
              return;
            }

            final bool confirmed = await _showValidationDialog(
              type,
              validationResult,
            );
            if (!confirmed) return;
          } catch (e) {
            setState(() => _isUploading = false);
            _showErrorDialog('Validation Error', e.toString());
            return;
          }
        }

        setState(() {
          _isUploading = true;
          _uploadResults.clear();
        });

        try {
          final uploadResult = await uploadFunction(fileBytes, fileName);
          setState(() {
            _uploadResults.add(uploadResult);
          });

          if (uploadResult['success']) {
            _showSuccessDialog('$type Upload', uploadResult);
          } else {
            _showErrorDialog(
              '$type Upload Failed',
              uploadResult['message'] ?? uploadResult['error'],
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
    } catch (e) {
      _showErrorDialog('File Picker Error', e.toString());
    }
  }

  Future<bool> _showValidationDialog(
    String type,
    Map<String, dynamic> result,
  ) async {
    final totalRecords = result['total_records'] ?? 0;
    final errors = (result['errors'] as List?) ?? [];
    final hasErrors = errors.isNotEmpty;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$type Validation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Found $totalRecords records.'),
                  if (hasErrors) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Found ${errors.length} issues:',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: errors.length,
                        itemBuilder: (context, index) => Text(
                          '• ${errors[index]}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Do you want to proceed anyway?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Text(
                      'File looks good! Ready to upload?',
                      style: TextStyle(color: Colors.green),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasErrors ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(hasErrors ? 'Proceed Anyway' : 'Upload Now'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSuccessDialog(String title, Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✅ Operation completed successfully!'),
              const SizedBox(height: 8),
              Text('Collection: ${result['collection']}'),
              if (result.containsKey('total_records'))
                Text('Total Records: ${result['total_records']}'),
              if (result.containsKey('successful_uploads'))
                Text('Successful: ${result['successful_uploads']}'),
              if (result.containsKey('failed_uploads'))
                Text('Failed: ${result['failed_uploads']}'),
              if (result['errors'] != null &&
                  (result['errors'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Errors:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (result['errors'] as List)
                          .map((error) => Text('• $error'))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Data Import'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
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
                        'Upload Excel Data',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Select an Excel file (.xlsx) to upload data to Firestore. Ensure the file format matches the specifications below.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Upload buttons
              ElevatedButton.icon(
                onPressed: _isUploading
                    ? null
                    : () => _pickAndUploadFile(
                        'Inventory',
                        _uploadService!.uploadInventoryData,
                        validateFunction: _uploadService?.validateInventoryData,
                      ),
                icon: const Icon(Icons.inventory),
                label: const Text('Upload Inventory Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isUploading
                    ? null
                    : () => _pickAndUploadFile(
                        'Transaction',
                        _uploadService!.uploadTransactionData,
                        validateFunction:
                            _uploadService?.validateTransactionData,
                      ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Upload Transaction Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 32),

              // Instructions Section
              const Text(
                'File Requirements',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.inventory, color: Colors.blue),
                  title: const Text('Inventory Upload Requirements'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Required Columns:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('• Serial_Number (Text)'),
                          Text('• Equipment_Category (Text)'),
                          SizedBox(height: 8),
                          Text(
                            'Optional Columns:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('• Model (Text)'),
                          Text('• Size (Text)'),
                          Text('• Batch (Text)'),
                          Text('• Date (YYYY-MM-DD or DD/MM/YYYY)'),
                          Text('• Remark (Text)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.green),
                  title: const Text('Transaction Upload Requirements'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Required Columns:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('• Date (YYYY-MM-DD or DD/MM/YYYY)'),
                          Text('• Type (Stock_In / Stock_Out)'),
                          Text('• Equipment_Category (Text)'),
                          Text('• Model (Text)'),
                          Text('• Serial_Number (Text)'),
                          Text('• Quantity (Number)'),
                          SizedBox(height: 8),
                          Text(
                            'Optional Columns:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('• Location, Status, Remarks'),
                          Text('• Customer_Dealer, Customer_Client'),
                          Text('• Unit_Price, Warranty_Type, Warranty_Period'),
                          Text('• Delivery_Date, Invoice_Number, Entry_No'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_isUploading) ...[
                const SizedBox(height: 24),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Processing data... Please wait.'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
