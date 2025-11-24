import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/invoice_service.dart';
import '../services/invoice_ocr_service.dart';
import '../services/file_service.dart';
import '../services/order_service.dart';
import '../providers/auth_provider.dart';
import '../utils/platform_features.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumberController = TextEditingController();
  final _remarksController = TextEditingController();

  List<Map<String, dynamic>> _allPOs = [];
  String? _selectedPOId;
  Map<String, dynamic>? _currentInvoice;
  DateTime _selectedDate = DateTime.now();
  File? _selectedFile;
  String? _selectedFileName;

  bool _isLoadingPOs = false;
  bool _isUploading = false;
  bool _isReplaceMode = false;
  bool _isLoadingInvoice = false;
  bool _isExtractingOCR = false;

  final InvoiceOcrService _ocrService = InvoiceOcrService();
  late final FileService _fileService;
  late final OrderService _orderService;

  @override
  void initState() {
    super.initState();
    // Initialize services with AuthProvider
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _orderService = OrderService(authService: authProvider.authService);
    _fileService = FileService(authService: authProvider.authService);
    _loadAvailablePOs();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  // Helper method to get the selected PO object from ID
  Map<String, dynamic>? get _selectedPO {
    if (_selectedPOId == null) return null;
    try {
      return _allPOs.firstWhere((po) => po['id'] == _selectedPOId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadAvailablePOs() async {
    setState(() {
      _isLoadingPOs = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final invoiceService = InvoiceService(
        authService: authProvider.authService,
      );

      // Load orders with 'Reserved' or 'Invoiced' status only
      final orders = await invoiceService.getOrdersForInvoicing();

      setState(() {
        _allPOs = orders;
        _isLoadingPOs = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPOs = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading orders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadInvoiceForPO(String poId) async {
    setState(() {
      _isLoadingInvoice = true;
      _currentInvoice = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final invoiceService = InvoiceService(
        authService: authProvider.authService,
      );

      final invoice = await invoiceService.getInvoiceByOrderId(poId);

      setState(() {
        _currentInvoice = invoice;
        _isLoadingInvoice = false;

        // Find the matching PO from _allPOs list to ensure dropdown works correctly
        if (invoice != null) {
          if (_allPOs.any((po) => po['id'] == poId)) {
            _selectedPOId = poId;
          } else {
            // If no matching PO found in _allPOs, don't set _selectedPOId
            // This prevents dropdown assertion errors
            _selectedPOId = null;
            // Note: PO with ID $poId not found in available POs list
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingInvoice = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading invoice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewPDF(String pdfUrl) async {
    try {
      final uri = Uri.parse(pdfUrl);

      // Try different launch modes for better compatibility
      bool launched = false;

      try {
        // First try with external application mode
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        // External application mode failed, will try fallback
      }

      if (!launched) {
        try {
          // Fallback to platform default mode
          launched = await launchUrl(uri);
        } catch (e) {
          // Platform default mode failed, will try clipboard fallback
        }
      }

      if (!launched) {
        // Fallback: Copy URL to clipboard and show instructions
        await Clipboard.setData(ClipboardData(text: pdfUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'PDF URL copied to clipboard! Please paste it in your browser to view the PDF.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (e) {
      // Final fallback: Copy URL to clipboard
      try {
        await Clipboard.setData(ClipboardData(text: pdfUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not open PDF directly. URL copied to clipboard! Error: $e',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (clipboardError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening PDF: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  void _toggleReplaceMode() {
    setState(() {
      _isReplaceMode = !_isReplaceMode;
      if (!_isReplaceMode) {
        // Reset form when exiting replace mode
        _selectedFile = null;
        _selectedFileName = null;
        _invoiceNumberController.clear();
        _remarksController.clear();
        _selectedDate = DateTime.now();
      } else if (_currentInvoice != null) {
        // Pre-fill form with current invoice data when entering replace mode
        _invoiceNumberController.text =
            _currentInvoice!['invoice_number'] ?? '';
        _remarksController.text = _currentInvoice!['invoice_remarks'] ?? '';
        if (_currentInvoice!['invoice_date'] != null) {
          final timestamp = _currentInvoice!['invoice_date'] as Timestamp;
          _selectedDate = timestamp.toDate();
        }
      }
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _selectedFileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _extractInvoiceData() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a PDF file first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if PDF text extraction is supported
    if (!PlatformFeatures.supportsPDFOCR) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF text extraction not supported on ${PlatformFeatures.platformName}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isExtractingOCR = true;
    });

    try {
      // Initialize OCR service if needed
      await _ocrService.initialize();

      // Extract data from file
      final result = await _ocrService.extractInvoiceData(_selectedFile!);

      if (result['success'] == true) {
        final confidence = result['confidence'] as double;
        final confidencePercent = (confidence * 100).toInt();

        // Show validation dialog for low confidence results
        if (confidence < 0.5) {
          await _showLowConfidenceDialog(result, confidencePercent);
        } else {
          // Auto-fill the form fields with extracted data
          if (result['invoiceNumber'] != null) {
            _invoiceNumberController.text = result['invoiceNumber'];
          }

          if (result['invoiceDate'] != null) {
            setState(() {
              _selectedDate = result['invoiceDate'];
            });
          }

          // Show success message with confidence
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'PDF text extraction completed! Confidence: $confidencePercent%\n'
                  'Please review and correct the extracted data if needed.',
                ),
                backgroundColor: confidencePercent > 70
                    ? Colors.green
                    : Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'PDF text extraction failed'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF text extraction error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtractingOCR = false;
        });
      }
    }
  }

  Future<void> _showLowConfidenceDialog(
    Map<String, dynamic> result,
    int confidencePercent,
  ) async {
    final extractedNumber = result['invoiceNumber'] as String?;
    final extractedDate = result['invoiceDate'] as DateTime?;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('⚠️ Low Confidence Extraction Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PDF text extraction completed with low confidence ($confidencePercent%).\n'
                  'Please review the extracted data carefully:',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (extractedNumber != null) ...[
                  const Text(
                    'Invoice Number:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    extractedNumber,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (extractedDate != null) ...[
                  const Text(
                    'Invoice Date:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${extractedDate.day}/${extractedDate.month}/${extractedDate.year}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (extractedNumber == null && extractedDate == null) ...[
                  const Text(
                    'No invoice data could be extracted with sufficient confidence.',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Would you like to use this data or enter manually?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Don't fill any fields - user will enter manually
              },
              child: const Text('Enter Manually'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Fill the fields with extracted data
                if (extractedNumber != null) {
                  _invoiceNumberController.text = extractedNumber;
                }
                if (extractedDate != null) {
                  setState(() {
                    _selectedDate = extractedDate;
                  });
                }
                // Show reminder to review
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Data filled. Please review and correct if needed.',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Use Extracted Data'),
            ),
          ],
        );
      },
    );
  }

  /// New file-based invoice upload using FileService and OrderService
  Future<void> _uploadInvoiceWithFileService() async {
    if (!_formKey.currentState!.validate() ||
        _selectedPOId == null ||
        _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields and select a PDF file',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get the selected order to extract order_number
    final selectedOrder = _selectedPO;
    if (selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected order not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final orderNumber = selectedOrder['order_number'] as String?;
    if (orderNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order number not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Step 1: Validate file before upload
      final fileValidation = await _fileService.validateFile(
        _selectedFile!,
        'invoice',
      );
      if (!fileValidation['valid']) {
        throw Exception(fileValidation['error'] ?? 'File validation failed');
      }

      // Step 2: Upload file using FileService
      final uploadResult = await _fileService.uploadFile(
        file: _selectedFile!,
        orderNumber: orderNumber,
        fileType: 'invoice',
      );

      if (!uploadResult.success) {
        throw Exception(uploadResult.error ?? 'File upload failed');
      }

      // Step 3: Update order with file reference using OrderService
      final orderUpdateResult = await _orderService.updateOrderWithFile(
        orderNumber: orderNumber,
        fileId: uploadResult.fileId!,
        fileType: 'invoice',
      );

      if (!orderUpdateResult['success']) {
        // If order update fails, we should clean up the uploaded file
        // TODO: Implement file cleanup on order update failure
        throw Exception(orderUpdateResult['error'] ?? 'Order update failed');
      }

      // Step 4: Update order with invoice details (number, date, remarks)
      final invoiceData = <String, dynamic>{
        'invoice_number': _invoiceNumberController.text.trim(),
        'invoice_date': Timestamp.fromDate(_selectedDate),
        'invoice_remarks': _remarksController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Update the order document with invoice details
      final orderQuery = await FirebaseFirestore.instance
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isNotEmpty) {
        await orderQuery.docs.first.reference.update(invoiceData);
      }

      if (mounted) {
        // Get the new status from dual status system
        final newInvoiceStatus =
            orderUpdateResult['new_invoice_status'] ?? 'Unknown';
        final newDeliveryStatus =
            orderUpdateResult['new_delivery_status'] ?? 'Unknown';
        final displayStatus = _getDisplayStatusFromStatuses(
          newInvoiceStatus,
          newDeliveryStatus,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Success! Invoice uploaded successfully.\n'
              'Order status: $displayStatus\n'
              'File: ${uploadResult.fileModel?.originalFilename ?? 'Unknown'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Clear form and reload data
        _invoiceNumberController.clear();
        _remarksController.clear();
        setState(() {
          _selectedPOId = null;
          _selectedFile = null;
          _selectedFileName = null;
          _selectedDate = DateTime.now();
          _currentInvoice = null;
        });

        // Reload available orders to reflect status changes
        _loadAvailablePOs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading invoice: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  /// Delete invoice (development only)
  Future<void> _deleteInvoice() async {
    if (_currentInvoice == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final invoiceService = InvoiceService(
      authService: authProvider.authService,
    );

    // Show confirmation dialog
    final confirmed = await _showDeleteConfirmationDialog();
    if (!confirmed) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final result = await invoiceService.deleteInvoice(_currentInvoice!['id']);

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Invoice deleted successfully!\n'
                'Order status reverted to Reserved.',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Clear current invoice and reload data
          setState(() {
            _currentInvoice = null;
            _isReplaceMode = false;
          });

          // Reload available orders to reflect status changes
          _loadAvailablePOs();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error deleting invoice: ${result['error']}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error deleting invoice: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Delete order (development only)
  Future<void> _deleteOrder() async {
    if (_selectedPO == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orderService = OrderService(authService: authProvider.authService);

    // Show confirmation dialog
    final confirmed = await _showOrderDeleteConfirmationDialog();
    if (!confirmed) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final result = await orderService.deleteOrder(_selectedPO!['id']);

      if (mounted) {
        if (result['success']) {
          final deletionSummary =
              result['deletion_summary'] as Map<String, dynamic>;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Order deleted successfully!\n'
                '• Order: ${result['order_number']}\n'
                '• Transactions deleted: ${deletionSummary['transactions_deleted']}\n'
                '• Files deleted: ${deletionSummary['files_deleted']}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );

          // Clear current selection and reload data
          setState(() {
            _selectedPOId = null;
            _currentInvoice = null;
            _isReplaceMode = false;
          });

          // Reload available orders to reflect changes
          _loadAvailablePOs();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error deleting order: ${result['error']}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error deleting order: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Show order delete confirmation dialog
  Future<bool> _showOrderDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade600),
                const SizedBox(width: 8),
                const Text('⚠️ Delete Order'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will permanently delete:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('• Order: ${_selectedPO!['order_number'] ?? 'N/A'}'),
                Text('• Status: ${_getDisplayStatus(_selectedPO!)}'),
                Text('• All related transaction records'),
                Text('• All associated files (invoice/delivery PDFs)'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⚠️ IMPORTANT: This will NOT restore inventory quantities. '
                    'Items will remain in their current status (Reserved/Delivered). '
                    'Only the order and transaction records will be deleted.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This action cannot be undone. Are you sure?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete Order'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Show delete confirmation dialog
  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade600),
                const SizedBox(width: 8),
                const Text('⚠️ Delete Invoice'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will permanently delete:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Invoice: ${_currentInvoice!['invoice_number'] ?? 'N/A'}',
                ),
                Text('• PDF File: ${_currentInvoice!['file_name'] ?? 'N/A'}'),
                const Text('• All invoice data from the system'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'The order status will be reverted from "Invoiced" back to "Reserved".',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This action cannot be undone. Are you sure?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete Invoice'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Legacy invoice upload method (kept for replace functionality)
  Future<void> _uploadInvoice() async {
    if (!_formKey.currentState!.validate() ||
        _selectedPOId == null ||
        _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields and select a PDF file',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final invoiceService = InvoiceService(
        authService: authProvider.authService,
      );

      Map<String, dynamic> result;

      if (_isReplaceMode && _currentInvoice != null) {
        // Replace existing invoice using new FileService
        final orderNumber = _currentInvoice!['order_number'] as String;

        // Upload replacement file using FileService
        final uploadResult = await _fileService.replaceFile(
          orderNumber: orderNumber,
          fileType: 'invoice',
          newFile: _selectedFile!,
          originalFilename: _selectedFileName,
        );

        if (uploadResult.success && uploadResult.fileId != null) {
          // Update order with new file and invoice details using OrderService
          final orderUpdateResult = await _orderService
              .updateOrderWithInvoiceFile(
                orderNumber: orderNumber,
                fileId: uploadResult.fileId!,
                invoiceNumber: _invoiceNumberController.text.trim().isNotEmpty
                    ? _invoiceNumberController.text.trim()
                    : null,
                invoiceDate: _selectedDate,
                remarks: _remarksController.text.trim().isNotEmpty
                    ? _remarksController.text.trim()
                    : null,
              );

          result = {
            'success': orderUpdateResult['success'],
            'message': orderUpdateResult['success']
                ? 'Invoice replaced successfully'
                : orderUpdateResult['error'],
            'invoice_number': _invoiceNumberController.text.trim().isNotEmpty
                ? _invoiceNumberController.text.trim()
                : _currentInvoice!['invoice_number'],
          };
        } else {
          result = {
            'success': false,
            'error': uploadResult.error ?? 'Failed to upload replacement file',
          };
        }
      } else {
        // Upload new invoice
        result = await invoiceService.uploadInvoice(
          poId: _selectedPOId!,
          invoiceNumber: _invoiceNumberController.text.trim(),
          pdfFile: _selectedFile!,
          invoiceDate: _selectedDate,
          remarks: _remarksController.text.trim(),
        );
      }

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isReplaceMode
                    ? 'Success! Invoice replaced successfully.'
                    : 'Success! ${result['message']}\nInvoice: ${result['invoice_number'] ?? _invoiceNumberController.text.trim()}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          if (_isReplaceMode) {
            // Exit replace mode and reload invoice data
            setState(() {
              _isReplaceMode = false;
              _selectedFile = null;
              _selectedFileName = null;
            });
            // Reload invoice data to show updated information
            _loadInvoiceForPO(_selectedPOId!);
          } else {
            // Clear form for new upload
            _invoiceNumberController.clear();
            _remarksController.clear();
            setState(() {
              _selectedPOId = null;
              _selectedFile = null;
              _selectedFileName = null;
              _selectedDate = DateTime.now();
              _currentInvoice = null;
            });
          }

          // Reload available POs
          _loadAvailablePOs();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Upload'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingPOs
          ? const Center(child: CircularProgressIndicator())
          : _allPOs.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No Orders Available',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All orders have been invoiced\nor no orders exist.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Legend Card
                    _buildStatusLegendCard(),
                    const SizedBox(height: 16),

                    // Order Selection Card
                    _buildOrderSelectionCard(),
                    const SizedBox(height: 16),

                    // Selected Order Details Card
                    if (_selectedPO != null) ...[
                      _buildOrderDetailsCard(),
                      const SizedBox(height: 16),
                    ],

                    // Invoice Information Card (for invoiced orders)
                    if (_selectedPO != null &&
                        _isOrderInvoiced(_selectedPO!)) ...[
                      _buildInvoiceInformationCard(),
                      const SizedBox(height: 16),
                    ],

                    // Invoice Upload Card
                    if (_selectedPO != null &&
                        !_isOrderInvoiced(_selectedPO!)) ...[
                      _buildInvoiceUploadCard(),
                      const SizedBox(height: 16),
                    ],

                    // Replace Invoice Card (for invoiced orders in replace mode)
                    if (_selectedPO != null &&
                        _isOrderInvoiced(_selectedPO!) &&
                        _isReplaceMode) ...[
                      _buildReplaceInvoiceCard(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // Helper method to check if order is invoiced
  bool _isOrderInvoiced(Map<String, dynamic> order) {
    final invoiceStatus = order['invoice_status'] as String?;
    final legacyStatus = order['status'] as String?;
    return (invoiceStatus == 'Invoiced') || (legacyStatus == 'Invoiced');
  }

  // Status Legend Card
  Widget _buildStatusLegendCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '🟠 Reserved (Can upload) • 🟢 Invoiced (Processed)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Order Selection Card
  Widget _buildOrderSelectionCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment, size: 20, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text(
                  'Select Order',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedPOId,
                decoration: const InputDecoration(
                  hintText: 'Choose an Order',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                isExpanded: true,
                items: _allPOs.isEmpty
                    ? [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'No orders available',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ]
                    : _allPOs.map((po) {
                        // Support both old single status and new dual status system
                        final status = po['status'] as String? ?? 'Unknown';
                        final invoiceStatus =
                            po['invoice_status'] as String? ?? status;
                        final deliveryStatus =
                            po['delivery_status'] as String? ?? 'Pending';

                        final isReserved = invoiceStatus == 'Reserved';
                        final isInvoiced = invoiceStatus == 'Invoiced';

                        return DropdownMenuItem<String>(
                          value: po['id'] as String,
                          enabled: true, // Enable all POs for selection
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isReserved
                                      ? Colors.orange
                                      : isInvoiced
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Order: ${po['order_number'] ?? 'N/A'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isReserved
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isReserved
                                      ? Colors.orange.shade100
                                      : isInvoiced
                                      ? Colors.green.shade100
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  invoiceStatus,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: isReserved
                                        ? Colors.orange.shade800
                                        : isInvoiced
                                        ? Colors.green.shade800
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPOId = value;
                    _currentInvoice = null;
                    _isReplaceMode = false;
                    // Reset form
                    _selectedFile = null;
                    _selectedFileName = null;
                    _invoiceNumberController.clear();
                    _remarksController.clear();
                    _selectedDate = DateTime.now();
                  });

                  // Load invoice data if PO is invoiced
                  if (value != null) {
                    final selectedPO = _allPOs.firstWhere(
                      (po) => po['id'] == value,
                    );
                    // Check if order is invoiced (support both dual and legacy status)
                    final invoiceStatus =
                        selectedPO['invoice_status'] as String?;
                    final legacyStatus = selectedPO['status'] as String?;
                    final isInvoiced =
                        (invoiceStatus == 'Invoiced') ||
                        (legacyStatus == 'Invoiced');

                    if (isInvoiced) {
                      _loadInvoiceForPO(value);
                    }
                  }
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select an order';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Order Details Card
  Widget _buildOrderDetailsCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text(
                  'Selected Order Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              'Order Number',
              _selectedPO!['order_number'] ?? 'N/A',
            ),
            // Show separate status lines for dual status system
            ..._buildStatusRows(_selectedPO!),
            _buildDetailRow('Dealer', _selectedPO!['customer_dealer'] ?? 'N/A'),
            _buildDetailRow('Client', _selectedPO!['customer_client'] ?? 'N/A'),
            _buildItemDetails(_selectedPO!),
            if (_selectedPO!['created_date'] != null)
              _buildDetailRow(
                'Created Date',
                _formatDate(_selectedPO!['created_date']),
              ),
            if (_isOrderInvoiced(_selectedPO!) &&
                _selectedPO!['invoice_number'] != null)
              _buildDetailRow('Invoice Number', _selectedPO!['invoice_number']),

            // Development-only order delete button
            if (kDebugMode && !_isOrderDelivered(_selectedPO!)) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Development Mode: Delete entire order and all related data',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _deleteOrder,
                      icon: const Icon(Icons.delete_forever, size: 16),
                      label: const Text('Delete Order'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Detail Row Helper (matching demo screens)
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  // Invoice Information Card (for invoiced orders)
  Widget _buildInvoiceInformationCard() {
    if (_currentInvoice == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row
            Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 20,
                  color: Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Current Invoice Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _viewPDF(_currentInvoice!['pdf_url']),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isReplaceMode = true;
                    });
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Replace'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                if (kDebugMode)
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _deleteInvoice,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              'Invoice Number',
              _currentInvoice!['invoice_number'],
            ),
            _buildDetailRow(
              'Invoice Date',
              _formatDate(_currentInvoice!['invoice_date']),
            ),
            _buildDetailRow('File Name', _currentInvoice!['file_name']),
            _buildDetailRow(
              'Uploaded At',
              _formatDate(_currentInvoice!['invoice_uploaded_at']),
            ),
            if (_currentInvoice!['invoice_remarks'] != null &&
                _currentInvoice!['invoice_remarks'].toString().isNotEmpty)
              _buildDetailRow('Remarks', _currentInvoice!['invoice_remarks']),
          ],
        ),
      ),
    );
  }

  // Invoice Upload Card (for non-invoiced orders)
  Widget _buildInvoiceUploadCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, size: 20, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Text(
                  'Upload Invoice',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Invoice Number Field
            TextFormField(
              controller: _invoiceNumberController,
              decoration: const InputDecoration(
                labelText: 'Invoice Number *',
                border: OutlineInputBorder(),
                hintText: 'Enter invoice number',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter invoice number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Invoice Date Field
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Invoice Date *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File Selection
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedFile != null ? Colors.green : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedFile != null
                        ? Icons.picture_as_pdf
                        : Icons.upload_file,
                    size: 48,
                    color: _selectedFile != null ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedFileName ?? 'No file selected',
                    style: TextStyle(
                      fontWeight: _selectedFile != null
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _selectedFile != null ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      _selectedFile != null ? 'Change File' : 'Select PDF File',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),

                  // OCR Extraction Button (only show when file is selected)
                  if (_selectedFile != null) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isExtractingOCR ? null : _extractInvoiceData,
                      icon: _isExtractingOCR
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.text_fields),
                      label: Text(
                        _isExtractingOCR ? 'Extracting...' : 'Extract PDF Data',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Remarks Field
            TextFormField(
              controller: _remarksController,
              decoration: const InputDecoration(
                labelText: 'Remarks (Optional)',
                hintText: 'Enter any additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Upload Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadInvoiceWithFileService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                          Text('Uploading...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload),
                          SizedBox(width: 8),
                          Text(
                            'Upload Invoice',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Replace Invoice Card (for invoiced orders in replace mode)
  Widget _buildReplaceInvoiceCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_document,
                  size: 20,
                  color: Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Replace Invoice',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleReplaceMode,
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Invoice Number Field (optional in replace mode)
            TextFormField(
              controller: _invoiceNumberController,
              decoration: const InputDecoration(
                labelText:
                    'Invoice Number (optional - leave empty to keep current)',
                border: OutlineInputBorder(),
                hintText: 'Enter new invoice number or leave empty',
              ),
            ),
            const SizedBox(height: 16),

            // Invoice Date Field
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Invoice Date *',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File Selection (same as upload card)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedFile != null ? Colors.orange : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedFile != null
                        ? Icons.picture_as_pdf
                        : Icons.upload_file,
                    size: 48,
                    color: _selectedFile != null ? Colors.orange : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedFileName ?? 'No file selected',
                    style: TextStyle(
                      fontWeight: _selectedFile != null
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _selectedFile != null
                          ? Colors.orange
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      _selectedFile != null ? 'Change File' : 'Select PDF File',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),

                  // OCR Extraction Button (only show when file is selected)
                  if (_selectedFile != null) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isExtractingOCR ? null : _extractInvoiceData,
                      icon: _isExtractingOCR
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.text_fields),
                      label: Text(
                        _isExtractingOCR ? 'Extracting...' : 'Extract PDF Data',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Remarks Field
            TextFormField(
              controller: _remarksController,
              decoration: const InputDecoration(
                labelText: 'Remarks (Optional)',
                hintText: 'Enter any additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Replace Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadInvoiceWithFileService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                          Text('Replacing...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.update),
                          SizedBox(width: 8),
                          Text(
                            'Replace Invoice',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build item details section
  Widget _buildItemDetails(Map<String, dynamic> po) {
    final items = po['items'] as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return _buildDetailRow('Items', 'No items found');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Items (${items.length}):',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value as Map<String, dynamic>;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Serial Number',
                  item['serial_number']?.toString() ?? 'N/A',
                ),
                _buildDetailRow(
                  'Category',
                  item['equipment_category']?.toString() ?? 'N/A',
                ),
                _buildDetailRow('Model', item['model']?.toString() ?? 'N/A'),
                _buildDetailRow('Size', item['size']?.toString() ?? 'N/A'),
                _buildDetailRow('Batch', item['batch']?.toString() ?? 'N/A'),
                if (item['transaction_id'] != null)
                  _buildDetailRow(
                    'Transaction ID',
                    item['transaction_id'].toString(),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Helper method to build separate status rows for dual status system
  List<Widget> _buildStatusRows(Map<String, dynamic> order) {
    final invoiceStatus = order['invoice_status'] as String?;
    final deliveryStatus = order['delivery_status'] as String?;
    final legacyStatus = order['status'] as String?;

    // For dual status system, show separate lines
    if (invoiceStatus != null && deliveryStatus != null) {
      return [
        _buildDetailRow('Invoice Status', invoiceStatus),
        _buildDetailRow('Delivery Status', deliveryStatus),
      ];
    }

    // For legacy single status system, show single status
    if (legacyStatus != null) {
      return [_buildDetailRow('Status', legacyStatus)];
    }

    // Fallback
    return [_buildDetailRow('Status', 'Unknown')];
  }

  // Helper method to get display status from individual status values
  String _getDisplayStatusFromStatuses(
    String invoiceStatus,
    String deliveryStatus,
  ) {
    if (invoiceStatus == 'Reserved' && deliveryStatus == 'Pending') {
      return 'Reserved';
    } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Pending') {
      return 'Invoiced';
    } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Issued') {
      return 'Issued';
    } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Delivered') {
      return 'Delivered';
    } else {
      return '$invoiceStatus / $deliveryStatus';
    }
  }

  // Helper method to get display status for dual status system
  String _getDisplayStatus(Map<String, dynamic> order) {
    final invoiceStatus = order['invoice_status'] as String?;
    final deliveryStatus = order['delivery_status'] as String?;
    final legacyStatus = order['status'] as String?;

    // For dual status system, show combined status
    if (invoiceStatus != null && deliveryStatus != null) {
      if (invoiceStatus == 'Reserved' && deliveryStatus == 'Pending') {
        return 'Reserved';
      } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Pending') {
        return 'Invoiced';
      } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Issued') {
        return 'Issued';
      } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Delivered') {
        return 'Delivered';
      } else {
        return '$invoiceStatus / $deliveryStatus';
      }
    }

    // For legacy single status system
    if (legacyStatus != null) {
      return legacyStatus;
    }

    // Fallback
    return 'Unknown';
  }

  // Helper method to check if order is delivered (dual status system support)
  bool _isOrderDelivered(Map<String, dynamic> order) {
    final deliveryStatus = order['delivery_status'] as String?;
    final legacyStatus = order['status'] as String?;

    // For dual status system
    if (deliveryStatus != null) {
      return deliveryStatus == 'Delivered';
    }

    // For legacy single status system
    if (legacyStatus != null) {
      return legacyStatus == 'Delivered';
    }

    return false;
  }

  // Helper method to format date
  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';

    try {
      DateTime dateTime;
      if (date is Timestamp) {
        dateTime = date.toDate();
      } else if (date is DateTime) {
        dateTime = date;
      } else {
        return date.toString();
      }

      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'Invalid Date';
    }
  }
}
