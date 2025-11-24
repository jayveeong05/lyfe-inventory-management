import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/file_service.dart';
import '../services/order_service.dart';
import '../services/invoice_ocr_service.dart';
import '../providers/auth_provider.dart';
import '../utils/platform_features.dart';

class DeliveryOrderScreen extends StatefulWidget {
  const DeliveryOrderScreen({super.key});

  @override
  State<DeliveryOrderScreen> createState() => _DeliveryOrderScreenState();
}

class _DeliveryOrderScreenState extends State<DeliveryOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deliveryNumberController = TextEditingController();
  final _remarksController = TextEditingController();

  List<Map<String, dynamic>> _allOrders = [];
  String? _selectedOrderId;
  Map<String, dynamic>? _currentDeliveryOrder;
  DateTime _selectedDate = DateTime.now();

  // Normal Delivery Order PDF
  File? _normalDeliveryFile;
  String? _normalDeliveryFileName;

  // Signed Delivery Order PDF
  File? _signedDeliveryFile;
  String? _signedDeliveryFileName;

  bool _isLoadingOrders = false;
  bool _isUploadingNormal = false;
  bool _isUploadingSigned = false;
  bool _isNormalReplaceMode = false;
  bool _isSignedReplaceMode = false;
  bool _isLoadingDeliveryOrder = false;
  bool _isExtractingOCR = false;
  bool _isUploading = false; // For delete operations

  // New state variables for showing upload forms
  bool _showNormalUploadForm = false;
  bool _showSignedUploadForm = false;

  final InvoiceOcrService _ocrService = InvoiceOcrService();
  late final FileService _fileService;
  late final OrderService _orderService;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadAvailableOrders();
  }

  void _initializeServices() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _fileService = FileService(authService: authProvider.authService);
    _orderService = OrderService(authService: authProvider.authService);
  }

  // Helper method to get the selected order object from ID
  Map<String, dynamic>? get _selectedOrder {
    if (_selectedOrderId == null) return null;
    try {
      return _allOrders.firstWhere((order) => order['id'] == _selectedOrderId);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _deliveryNumberController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableOrders() async {
    setState(() {
      _isLoadingOrders = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderService = OrderService(authService: authProvider.authService);

      // Load orders for delivery operations using new dual status system:
      // Only orders with Invoiced invoice status can proceed to delivery operations
      final ordersForDelivery = await orderService.getOrdersForDelivery();

      final orders = ordersForDelivery;

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _isLoadingOrders = false;
        });

        // If there was a previously selected order, try to maintain selection
        if (_selectedOrderId != null) {
          final orderExists = _allOrders.any(
            (order) => order['id'] == _selectedOrderId,
          );
          if (orderExists) {
            _loadDeliveryOrderForOrder(_selectedOrderId!);
          } else {
            // If no matching order found in _allOrders, don't set _selectedOrderId
            // This prevents dropdown assertion errors
            _selectedOrderId = null;
            // Note: Order with ID $_selectedOrderId not found in available orders list
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading orders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadDeliveryOrderForOrder(String orderId) async {
    setState(() {
      _isLoadingDeliveryOrder = true;
    });

    try {
      // Get delivery order information for the selected order
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      if (orderDoc.exists && mounted) {
        final orderData = orderDoc.data() as Map<String, dynamic>;
        final status = orderData['status'] as String?;

        Map<String, dynamic>? deliveryOrderInfo;

        // Load normal delivery order info (for Issued and Delivered delivery status)
        final deliveryStatus =
            orderData['delivery_status'] as String? ?? 'Pending';
        if ((deliveryStatus == 'Issued' || deliveryStatus == 'Delivered') &&
            orderData['delivery_file_id'] != null) {
          final fileDoc = await FirebaseFirestore.instance
              .collection('files')
              .doc(orderData['delivery_file_id'])
              .get();

          if (fileDoc.exists) {
            final fileData = fileDoc.data() as Map<String, dynamic>;
            deliveryOrderInfo = {
              'id': orderId,
              'order_number': orderData['order_number'],
              'status': status,
              'delivery_number': orderData['delivery_number'],
              'delivery_date': orderData['delivery_date'],
              'delivery_remarks': orderData['delivery_remarks'],
              'normal_delivery': {
                'file_name': fileData['original_filename'],
                'file_size': fileData['file_size'],
                'upload_date': fileData['upload_date'],
                'download_url': fileData['storage_url'],
              },
            };
          }
        }

        // Load signed delivery order info (for Delivered delivery status)
        if (deliveryStatus == 'Delivered' &&
            orderData['signed_delivery_file_id'] != null) {
          final signedFileDoc = await FirebaseFirestore.instance
              .collection('files')
              .doc(orderData['signed_delivery_file_id'])
              .get();

          if (signedFileDoc.exists) {
            final signedFileData = signedFileDoc.data() as Map<String, dynamic>;
            if (deliveryOrderInfo != null) {
              deliveryOrderInfo['signed_delivery'] = {
                'file_name': signedFileData['original_filename'],
                'file_size': signedFileData['file_size'],
                'upload_date': signedFileData['upload_date'],
                'download_url': signedFileData['storage_url'],
              };
            }
          }
        }

        setState(() {
          _currentDeliveryOrder = deliveryOrderInfo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading delivery order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDeliveryOrder = false;
        });
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
        // Final fallback: copy URL to clipboard
        await Clipboard.setData(ClipboardData(text: pdfUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open PDF. URL copied to clipboard - paste in browser to view.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening PDF: $e'),
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

  Future<void> _selectNormalDeliveryFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _normalDeliveryFile = File(result.files.single.path!);
          _normalDeliveryFileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting normal delivery file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectSignedDeliveryFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _signedDeliveryFile = File(result.files.single.path!);
          _signedDeliveryFileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting signed delivery file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _extractDeliveryData() async {
    if (_normalDeliveryFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a normal delivery PDF file first'),
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
      final result = await _ocrService.extractDeliveryData(
        _normalDeliveryFile!,
      );

      if (result['success'] == true) {
        final confidence = result['confidence'] as double;
        final confidencePercent = (confidence * 100).toInt();

        // Show validation dialog for low confidence results
        if (confidence < 0.5) {
          await _showLowConfidenceDialog(result, confidencePercent);
        } else {
          // Auto-fill the form fields with extracted data
          _fillFormWithExtractedData(result);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Delivery data extracted successfully! ($confidencePercent% confidence)',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Failed to extract delivery data',
              ),
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
            content: Text('Error extracting delivery data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
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
    final extractedNumber = result['deliveryNumber'] as String?;
    final extractedDate = result['deliveryDate'] as DateTime?;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Low Confidence Extraction'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'The extraction confidence is low ($confidencePercent%). Please verify the extracted data:',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (extractedNumber != null && extractedNumber.isNotEmpty) ...[
                  const Text(
                    'Delivery Number:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(extractedNumber),
                  const SizedBox(height: 8),
                ],
                if (extractedDate != null) ...[
                  const Text(
                    'Delivery Date:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${extractedDate.day}/${extractedDate.month}/${extractedDate.year}',
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'Would you like to use this extracted data?',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _fillFormWithExtractedData(result);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Delivery data applied! ($confidencePercent% confidence)',
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Use Data'),
            ),
          ],
        );
      },
    );
  }

  void _fillFormWithExtractedData(Map<String, dynamic> result) {
    final deliveryNumber = result['deliveryNumber'] as String?;
    final deliveryDate = result['deliveryDate'] as DateTime?;

    if (deliveryNumber != null && deliveryNumber.isNotEmpty) {
      _deliveryNumberController.text = deliveryNumber;
    }

    if (deliveryDate != null) {
      setState(() {
        _selectedDate = deliveryDate;
      });
    }
  }

  /// Upload normal delivery order - changes status to "Issued"
  Future<void> _uploadNormalDeliveryOrder() async {
    if (!_formKey.currentState!.validate() ||
        _selectedOrderId == null ||
        _normalDeliveryFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields and select a normal delivery PDF file',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _uploadDeliveryFile(
      file: _normalDeliveryFile!,
      fileType: 'delivery_order',
      targetStatus: 'Issued',
      uploadingFlag: 'normal',
      isReplaceMode: _isNormalReplaceMode,
    );
  }

  /// Upload signed delivery order - changes status to "Delivered"
  Future<void> _uploadSignedDeliveryOrder() async {
    if (!_formKey.currentState!.validate() ||
        _selectedOrderId == null ||
        _signedDeliveryFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields and select a signed delivery PDF file',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _uploadDeliveryFile(
      file: _signedDeliveryFile!,
      fileType: 'signed_delivery_order',
      targetStatus: 'Delivered',
      uploadingFlag: 'signed',
      isReplaceMode: _isSignedReplaceMode,
    );
  }

  /// Common upload logic for both delivery order types
  Future<void> _uploadDeliveryFile({
    required File file,
    required String fileType,
    required String targetStatus,
    required String uploadingFlag,
    bool isReplaceMode = false,
  }) async {
    // Get the selected order to extract order_number
    final selectedOrder = _selectedOrder;
    if (selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected order not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final orderNumber = selectedOrder['order_number'] as String;

    // Set the appropriate uploading flag
    setState(() {
      if (uploadingFlag == 'normal') {
        _isUploadingNormal = true;
      } else {
        _isUploadingSigned = true;
      }
    });

    try {
      // Step 1: Validate file before upload
      final fileValidation = await _fileService.validateFile(file, fileType);
      if (!fileValidation['valid']) {
        throw Exception(fileValidation['error'] ?? 'File validation failed');
      }

      // Step 2: Upload or replace file using FileService
      final uploadResult = isReplaceMode
          ? await _fileService.replaceFile(
              orderNumber: orderNumber,
              fileType: fileType,
              newFile: file,
              originalFilename: uploadingFlag == 'normal'
                  ? _normalDeliveryFileName
                  : _signedDeliveryFileName,
            )
          : await _fileService.uploadFile(
              file: file,
              orderNumber: orderNumber,
              fileType: fileType,
            );

      if (!uploadResult.success) {
        throw Exception(uploadResult.error ?? 'File upload failed');
      }

      // Step 3: Update order with file reference using OrderService (for both new uploads and replacements)
      final orderUpdateResult = await _orderService.updateOrderWithFile(
        orderNumber: orderNumber,
        fileId: uploadResult.fileId!,
        fileType: fileType,
      );

      if (!orderUpdateResult['success']) {
        throw Exception(orderUpdateResult['error'] ?? 'Order update failed');
      }

      // Step 4: Update order with delivery details (number, date, remarks)
      final deliveryData = <String, dynamic>{
        'delivery_number': _deliveryNumberController.text.trim(),
        'delivery_date': Timestamp.fromDate(_selectedDate),
        'delivery_remarks': _remarksController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Update the order document with delivery details
      final orderQuery = await FirebaseFirestore.instance
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .limit(1)
          .get();

      if (orderQuery.docs.isNotEmpty) {
        await orderQuery.docs.first.reference.update(deliveryData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Success! ${fileType == 'delivery_order'
                  ? 'Normal'
                  : fileType == 'signed_delivery_order'
                  ? 'Signed'
                  : 'Unknown'} delivery order ${isReplaceMode ? 'replaced' : 'uploaded'} successfully.\n'
              '${isReplaceMode ? '' : 'Order status: $targetStatus\n'}'
              'File: ${uploadResult.fileModel?.originalFilename ?? 'Unknown'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Clear the uploaded file, exit replace mode, and hide upload forms
        setState(() {
          // Clear the appropriate file based on upload type
          if (uploadingFlag == 'normal') {
            _normalDeliveryFile = null;
            _normalDeliveryFileName = null;
            _showNormalUploadForm = false;
            if (isReplaceMode) {
              _isNormalReplaceMode = false;
            }
          } else {
            _signedDeliveryFile = null;
            _signedDeliveryFileName = null;
            _showSignedUploadForm = false;
            if (isReplaceMode) {
              _isSignedReplaceMode = false;
            }
          }
        });

        // Reload delivery order data to show updated information
        if (_selectedOrderId != null) {
          _loadDeliveryOrderForOrder(_selectedOrderId!);
        }

        // Reload available orders to reflect status changes
        _loadAvailableOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error uploading ${fileType == 'delivery_order'
                  ? 'normal'
                  : fileType == 'signed_delivery_order'
                  ? 'signed'
                  : 'unknown'} delivery order: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          // Clear the appropriate uploading flag
          if (uploadingFlag == 'normal') {
            _isUploadingNormal = false;
          } else {
            _isUploadingSigned = false;
          }
        });
      }
    }
  }

  /// Delete delivery PDFs and revert status
  Future<void> _deleteDeliveryData() async {
    if (_selectedOrder == null) return;

    // Show confirmation dialog
    final confirmed = await _showDeliveryDeleteConfirmationDialog();
    if (!confirmed) return;

    setState(() {
      _isUploading = true;
    });

    try {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderService = OrderService(authService: authProvider.authService);

      final result = await orderService.deleteDeliveryData(
        _selectedOrder!['id'],
      );

      if (mounted) {
        if (result['success']) {
          final deletionSummary =
              result['deletion_summary'] as Map<String, dynamic>;

          // Show success SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Delivery data removed successfully!\n'
                'Order status reverted to Invoiced.\n'
                'Files deleted: ${deletionSummary['files_deleted_from_storage'] ?? 0}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Reset form and reload data
          setState(() {
            _currentDeliveryOrder = null;
            _normalDeliveryFile = null;
            _normalDeliveryFileName = null;
            _signedDeliveryFile = null;
            _signedDeliveryFileName = null;
            _isNormalReplaceMode = false;
            _isSignedReplaceMode = false;
            _showNormalUploadForm = false;
            _showSignedUploadForm = false;
          });
          _deliveryNumberController.clear();
          _remarksController.clear();

          // Reload the selected order data
          if (_selectedOrderId != null) {
            _loadDeliveryOrderForOrder(_selectedOrderId!);
          }
          _loadAvailableOrders();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Error removing delivery data: ${result['error']}',
              ),
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
            content: Text('❌ Error removing delivery data: $e'),
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

  Future<bool> _showDeliveryDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade600),
                const SizedBox(width: 8),
                const Flexible(child: Text('⚠️ Remove Delivery Data')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to remove delivery data for order ${_selectedOrder!['order_number']}?',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info,
                              size: 16,
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'This action will:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Revert delivery_status to "Pending"',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                        Text(
                          '• Delete delivery order PDF files',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                        Text(
                          '• Delete signed delivery PDF files',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Order and invoice data will remain intact.',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Remove Delivery Data'),
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
        title: const Text('Delivery Order'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingOrders
          ? const Center(child: CircularProgressIndicator())
          : _allOrders.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
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
                    'All orders have been delivered\nor no orders exist.',
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
                    // Order Details Card (only show when order is selected)
                    if (_selectedOrder != null) ...[
                      _buildOrderDetailsCard(),
                      const SizedBox(height: 16),
                    ],

                    // Delivery Information Card (only show when delivery order exists)
                    if (_currentDeliveryOrder != null) ...[
                      _buildDeliveryInformationCard(),
                      const SizedBox(height: 16),
                    ],

                    // Normal Delivery Upload Card
                    if (_selectedOrder != null &&
                        _shouldShowNormalUpload()) ...[
                      _buildNormalDeliveryUploadCard(),
                      const SizedBox(height: 16),
                    ],

                    // Signed Delivery Upload Card
                    if (_selectedOrder != null &&
                        _shouldShowSignedUpload()) ...[
                      _buildSignedDeliveryUploadCard(),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // Status Legend Card
  Widget _buildStatusLegendCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '🟢 Invoiced → Issue • 🔵 Issued → Deliver • 🟣 Delivered',
                style: TextStyle(fontSize: 11),
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
                Icon(
                  Icons.local_shipping,
                  size: 20,
                  color: Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select Order for Delivery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedOrderId,
              decoration: const InputDecoration(
                labelText: 'Select Invoiced Order *',
                border: OutlineInputBorder(),
                hintText: 'Choose an order to deliver',
              ),
              isExpanded: true,
              menuMaxHeight: 300,
              items: _allOrders.isEmpty
                  ? [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'No orders available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ]
                  : _allOrders.map((order) {
                      final orderNumber = order['order_number'] ?? 'Unknown';
                      final dealer = order['customer_dealer'] ?? 'Unknown';
                      final client = order['customer_client'] ?? 'Unknown';
                      // Support both old single status and new dual status system
                      final status = order['status'] as String? ?? 'Unknown';
                      final invoiceStatus =
                          order['invoice_status'] as String? ?? status;
                      final deliveryStatus =
                          order['delivery_status'] as String? ?? 'Pending';

                      // Define status colors based on delivery status
                      final isReserved = invoiceStatus == 'Reserved';
                      final isInvoiced =
                          invoiceStatus == 'Invoiced' &&
                          deliveryStatus == 'Pending';
                      final isIssued = deliveryStatus == 'Issued';
                      final isDelivered = deliveryStatus == 'Delivered';

                      return DropdownMenuItem<String>(
                        value: order['id'],
                        child: Row(
                          children: [
                            // Status color indicator
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isReserved
                                    ? Colors.orange
                                    : isInvoiced
                                    ? Colors.green
                                    : isIssued
                                    ? Colors.blue
                                    : isDelivered
                                    ? Colors.purple
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Order details
                            Expanded(
                              child: Text(
                                '$orderNumber - $dealer → $client',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            // Status label
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
                                    : isIssued
                                    ? Colors.blue.shade100
                                    : isDelivered
                                    ? Colors.purple.shade100
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isInvoiced ? 'Invoiced' : deliveryStatus,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isReserved
                                      ? Colors.orange.shade800
                                      : isInvoiced
                                      ? Colors.green.shade800
                                      : isIssued
                                      ? Colors.blue.shade800
                                      : isDelivered
                                      ? Colors.purple.shade800
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedOrderId = newValue;
                  _currentDeliveryOrder = null;
                  // Reset upload form states when order changes
                  _showNormalUploadForm = false;
                  _showSignedUploadForm = false;
                  _isNormalReplaceMode = false;
                  _isSignedReplaceMode = false;
                  // Clear selected files
                  _normalDeliveryFile = null;
                  _normalDeliveryFileName = null;
                  _signedDeliveryFile = null;
                  _signedDeliveryFileName = null;
                });
                if (newValue != null) {
                  _loadDeliveryOrderForOrder(newValue);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select an order';
                }
                return null;
              },
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
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Selected Order Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              'Order Number',
              _selectedOrder!['order_number'] ?? 'N/A',
            ),
            // Show separate status lines for dual status system
            ..._buildStatusRows(_selectedOrder!),
            _buildDetailRow(
              'Dealer',
              _selectedOrder!['customer_dealer'] ?? 'N/A',
            ),
            _buildDetailRow(
              'Client',
              _selectedOrder!['customer_client'] ?? 'N/A',
            ),
            _buildItemDetails(_selectedOrder!),
            if (_selectedOrder!['created_date'] != null)
              _buildDetailRow(
                'Created Date',
                _formatDate(_selectedOrder!['created_date']),
              ),
            // Invoice Information Section
            if (_isOrderInvoiced(_selectedOrder!)) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.receipt, size: 16, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Invoice Information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_selectedOrder!['invoice_number'] != null)
                _buildDetailRow(
                  'Invoice Number',
                  _selectedOrder!['invoice_number'],
                ),
              if (_selectedOrder!['invoice_date'] != null)
                _buildDetailRow(
                  'Invoice Date',
                  _formatDate(_selectedOrder!['invoice_date']),
                ),
              if (_selectedOrder!['invoice_remarks'] != null &&
                  _selectedOrder!['invoice_remarks'].toString().isNotEmpty)
                _buildDetailRow(
                  'Invoice Remarks',
                  _selectedOrder!['invoice_remarks'],
                ),
              if (_selectedOrder!['file_name'] != null)
                _buildDetailRow('Invoice File', _selectedOrder!['file_name']),
            ],
            if ((_selectedOrder!['delivery_status'] ??
                        _selectedOrder!['status']) ==
                    'Delivered' &&
                _selectedOrder!['delivery_number'] != null)
              _buildDetailRow(
                'Delivery Number',
                _selectedOrder!['delivery_number'],
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to build detail rows (similar to demo screens)
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build item details section
  Widget _buildItemDetails(Map<String, dynamic> order) {
    final items = order['items'] as List<dynamic>? ?? [];

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

  // Helper method to check if order is invoiced
  bool _isOrderInvoiced(Map<String, dynamic> order) {
    final invoiceStatus = order['invoice_status'] as String?;
    final legacyStatus = order['status'] as String?;
    return (invoiceStatus == 'Invoiced') || (legacyStatus == 'Invoiced');
  }

  // Delivery Information Card
  Widget _buildDeliveryInformationCard() {
    if (_currentDeliveryOrder == null) {
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
                  Icons.local_shipping,
                  size: 20,
                  color: Colors.orange.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Current Delivery Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action Buttons Row - Only general actions
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Debug Delete Button
                if (kDebugMode)
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _deleteDeliveryData,
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
            if (_currentDeliveryOrder!['delivery_number'] != null)
              _buildDetailRow(
                'Delivery Number',
                _currentDeliveryOrder!['delivery_number'],
              ),
            if (_currentDeliveryOrder!['delivery_date'] != null)
              _buildDetailRow(
                'Delivery Date',
                _formatDate(_currentDeliveryOrder!['delivery_date']),
              ),
            if (_currentDeliveryOrder!['delivery_remarks'] != null &&
                _currentDeliveryOrder!['delivery_remarks']
                    .toString()
                    .isNotEmpty)
              _buildDetailRow(
                'Remarks',
                _currentDeliveryOrder!['delivery_remarks'],
              ),
            // Show PDF status
            _buildDetailRow(
              'Normal Delivery PDF',
              _currentDeliveryOrder!['normal_delivery'] != null
                  ? 'Uploaded'
                  : 'Not uploaded',
            ),
            _buildDetailRow(
              'Signed Delivery PDF',
              _currentDeliveryOrder!['signed_delivery'] != null
                  ? 'Uploaded'
                  : 'Not uploaded',
            ),
          ],
        ),
      ),
    );
  }

  // Normal Delivery Upload Card
  Widget _buildNormalDeliveryUploadCard() {
    if (!_shouldShowNormalUpload()) {
      return const SizedBox.shrink();
    }

    final hasNormalDelivery =
        _currentDeliveryOrder != null &&
        _currentDeliveryOrder!['normal_delivery'] != null;

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
                  hasNormalDelivery ? Icons.check_circle : Icons.upload_file,
                  size: 20,
                  color: hasNormalDelivery ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Normal Delivery PDF',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasNormalDelivery ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
                if (hasNormalDelivery) ...[
                  ElevatedButton.icon(
                    onPressed: () => _viewPDF(
                      _currentDeliveryOrder!['normal_delivery']['download_url'],
                    ),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
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
                      // Pre-populate form with existing delivery data
                      _deliveryNumberController.text =
                          _currentDeliveryOrder!['delivery_number'] ?? '';
                      if (_currentDeliveryOrder!['delivery_date'] != null) {
                        _selectedDate =
                            (_currentDeliveryOrder!['delivery_date']
                                    as Timestamp)
                                .toDate();
                      }
                      _remarksController.text =
                          _currentDeliveryOrder!['delivery_remarks'] ?? '';

                      setState(() {
                        _isNormalReplaceMode = true;
                        _showNormalUploadForm = true;
                        _showSignedUploadForm = false;
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
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isNormalReplaceMode = false;
                        _showNormalUploadForm = true;
                        _showSignedUploadForm = false;
                      });
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            if (hasNormalDelivery) ...[
              const SizedBox(height: 12),
              _buildDetailRow(
                'File Name',
                _currentDeliveryOrder!['normal_delivery']['file_name'],
              ),
              _buildDetailRow(
                'Delivery Number',
                _currentDeliveryOrder!['delivery_number'],
              ),
              _buildDetailRow(
                'Delivery Date',
                _formatDate(_currentDeliveryOrder!['delivery_date']),
              ),
              _buildDetailRow(
                'Uploaded At',
                _formatDate(
                  _currentDeliveryOrder!['normal_delivery']['upload_date'],
                ),
              ),
              if (_currentDeliveryOrder!['delivery_remarks'] != null &&
                  _currentDeliveryOrder!['delivery_remarks']
                      .toString()
                      .isNotEmpty)
                _buildDetailRow(
                  'Remarks',
                  _currentDeliveryOrder!['delivery_remarks'],
                ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Upload normal delivery PDF to update order status to "Issued"',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // Upload Form (when _showNormalUploadForm is true)
            if (_showNormalUploadForm) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Delivery Number Field (Editable for Normal Delivery)
              TextFormField(
                controller: _deliveryNumberController,
                decoration: InputDecoration(
                  labelText: 'Delivery Number *',
                  border: const OutlineInputBorder(),
                  hintText: _isNormalReplaceMode
                      ? 'Modify delivery number or keep current'
                      : 'Enter delivery number',
                  helperText: _isNormalReplaceMode
                      ? 'Pre-filled with original delivery number'
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter delivery number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Delivery Date Field
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Delivery Date *',
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
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _normalDeliveryFile != null
                          ? Icons.picture_as_pdf
                          : Icons.upload_file,
                      size: 48,
                      color: _normalDeliveryFile != null
                          ? Colors.red
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _normalDeliveryFile != null
                          ? _normalDeliveryFileName ?? 'Selected file'
                          : 'No file selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: _normalDeliveryFile != null
                            ? Colors.black87
                            : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _selectNormalDeliveryFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                        _normalDeliveryFile != null
                            ? 'Change File'
                            : 'Select PDF',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Remarks Field
              TextFormField(
                controller: _remarksController,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Enter any remarks',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Upload Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _normalDeliveryFile != null && !_isUploadingNormal
                      ? _uploadNormalDeliveryOrder
                      : null,
                  icon: _isUploadingNormal
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
                      : const Icon(Icons.upload),
                  label: Text(
                    _isUploadingNormal
                        ? 'Uploading...'
                        : 'Upload Normal Delivery',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showNormalUploadForm = false;
                      _normalDeliveryFile = null;
                      _normalDeliveryFileName = null;
                    });
                    _deliveryNumberController.clear();
                    _remarksController.clear();
                  },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Signed Delivery Upload Card
  Widget _buildSignedDeliveryUploadCard() {
    if (!_shouldShowSignedUpload()) {
      return const SizedBox.shrink();
    }

    final hasSignedDelivery =
        _currentDeliveryOrder != null &&
        _currentDeliveryOrder!['signed_delivery'] != null;

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
                  hasSignedDelivery ? Icons.check_circle : Icons.upload_file,
                  size: 20,
                  color: hasSignedDelivery ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Signed Delivery PDF',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasSignedDelivery ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                if (hasSignedDelivery) ...[
                  ElevatedButton.icon(
                    onPressed: () => _viewPDF(
                      _currentDeliveryOrder!['signed_delivery']['download_url'],
                    ),
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
                      // Pre-populate form with existing delivery data (except delivery number - now read-only)
                      if (_currentDeliveryOrder!['delivery_date'] != null) {
                        _selectedDate =
                            (_currentDeliveryOrder!['delivery_date']
                                    as Timestamp)
                                .toDate();
                      }
                      _remarksController.text =
                          _currentDeliveryOrder!['delivery_remarks'] ?? '';

                      setState(() {
                        _isSignedReplaceMode = true;
                        _showSignedUploadForm = true;
                        _showNormalUploadForm = false;
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
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSignedReplaceMode = false;
                        _showSignedUploadForm = true;
                        _showNormalUploadForm = false;
                      });
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add PDF'),
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
                ],
              ],
            ),
            if (hasSignedDelivery) ...[
              const SizedBox(height: 12),
              _buildDetailRow(
                'File Name',
                _currentDeliveryOrder!['signed_delivery']['file_name'],
              ),
              _buildDetailRow(
                'Delivery Number',
                _currentDeliveryOrder!['delivery_number'],
              ),
              _buildDetailRow(
                'Delivery Date',
                _formatDate(_currentDeliveryOrder!['delivery_date']),
              ),
              _buildDetailRow(
                'Uploaded At',
                _formatDate(
                  _currentDeliveryOrder!['signed_delivery']['upload_date'],
                ),
              ),
              if (_currentDeliveryOrder!['delivery_remarks'] != null &&
                  _currentDeliveryOrder!['delivery_remarks']
                      .toString()
                      .isNotEmpty)
                _buildDetailRow(
                  'Remarks',
                  _currentDeliveryOrder!['delivery_remarks'],
                ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Upload signed delivery PDF to update order status to "Delivered"',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // Upload Form (when _showSignedUploadForm is true)
            if (_showSignedUploadForm) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Delivery Number Display (Read-only)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey.shade50,
                ),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Number',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentDeliveryOrder!['delivery_number'] ?? 'Not set',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Delivery Date Field
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Delivery Date *',
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
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _signedDeliveryFile != null
                          ? Icons.picture_as_pdf
                          : Icons.upload_file,
                      size: 48,
                      color: _signedDeliveryFile != null
                          ? Colors.red
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _signedDeliveryFile != null
                          ? _signedDeliveryFileName ?? 'Selected file'
                          : 'No file selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: _signedDeliveryFile != null
                            ? Colors.black87
                            : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _selectSignedDeliveryFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                        _signedDeliveryFile != null
                            ? 'Change File'
                            : 'Select PDF',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Remarks Field
              TextFormField(
                controller: _remarksController,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Enter any remarks',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Upload Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signedDeliveryFile != null && !_isUploadingSigned
                      ? _uploadSignedDeliveryOrder
                      : null,
                  icon: _isUploadingSigned
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
                      : const Icon(Icons.upload),
                  label: Text(
                    _isUploadingSigned
                        ? 'Uploading...'
                        : 'Upload Signed Delivery',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showSignedUploadForm = false;
                      _signedDeliveryFile = null;
                      _signedDeliveryFileName = null;
                    });
                    _remarksController.clear();
                  },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Helper methods for upload logic
  bool _shouldShowNormalUpload() {
    if (_selectedOrder == null) return false;

    // Show if order is invoiced (can upload normal delivery)
    final invoiceStatus =
        _selectedOrder!['invoice_status'] ?? _selectedOrder!['status'];
    return invoiceStatus == 'Invoiced';
  }

  bool _shouldShowSignedUpload() {
    if (_selectedOrder == null) return false;

    // Show if order is issued or delivered (can upload signed delivery)
    final deliveryStatus =
        _selectedOrder!['delivery_status'] ?? _selectedOrder!['status'];
    return deliveryStatus == 'Issued' || deliveryStatus == 'Delivered';
  }
}
