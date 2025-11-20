import 'dart:io';
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
                    // Status Legend
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        '🟢 Invoiced → Issue • 🔵 Issued → Deliver • 🟣 Delivered',
                        style: TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order Selection
                    const Text(
                      'Select Order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                              final orderNumber =
                                  order['order_number'] ?? 'Unknown';
                              final dealer =
                                  order['customer_dealer'] ?? 'Unknown';
                              final client =
                                  order['customer_client'] ?? 'Unknown';
                              // Support both old single status and new dual status system
                              final status =
                                  order['status'] as String? ?? 'Unknown';
                              final invoiceStatus =
                                  order['invoice_status'] as String? ?? status;
                              final deliveryStatus =
                                  order['delivery_status'] as String? ??
                                  'Pending';

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
                                        isInvoiced
                                            ? 'Invoiced'
                                            : deliveryStatus,
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

                    const SizedBox(height: 16),

                    // Selected Order Information Card
                    if (_selectedOrder != null) ...[
                      // Basic Order Information
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              'Order Number',
                              _selectedOrder!['order_number'],
                            ),
                            // Show separate status lines for dual status system
                            ..._buildStatusRows(_selectedOrder!),
                            _buildInfoRow(
                              'Dealer',
                              _selectedOrder!['customer_dealer'],
                            ),
                            _buildInfoRow(
                              'Client',
                              _selectedOrder!['customer_client'],
                            ),
                            _buildItemDetails(_selectedOrder!),
                            if (_selectedOrder!['created_date'] != null)
                              _buildInfoRow(
                                'Created Date',
                                _formatDate(_selectedOrder!['created_date']),
                              ),
                            if ((_selectedOrder!['delivery_status'] ??
                                        _selectedOrder!['status']) ==
                                    'Delivered' &&
                                _selectedOrder!['delivery_number'] != null)
                              _buildInfoRow(
                                'Delivery Number',
                                _selectedOrder!['delivery_number'],
                              ),
                          ],
                        ),
                      ),

                      // Remove Delivery Data Button
                      if (_selectedOrder != null &&
                          (_currentDeliveryOrder != null)) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isUploading
                                ? null
                                : _deleteDeliveryData,
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                            ),
                            label: const Text('Remove Delivery Data'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // PDF Management Cards
                      const SizedBox(height: 16),

                      // Normal Delivery PDF Card
                      _buildNormalDeliveryCard(),

                      const SizedBox(height: 16),

                      // Signed Delivery PDF Card
                      _buildSignedDeliveryCard(),

                      // Show upload forms when requested
                      if (_showNormalUploadForm || _showSignedUploadForm) ...[
                        const SizedBox(height: 16),
                        if (_isLoadingDeliveryOrder)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Loading delivery order information...'),
                              ],
                            ),
                          ),
                      ],

                      // Show upload form only when user clicks "Add PDF" or "Replace" buttons
                      if (_showNormalUploadForm || _showSignedUploadForm) ...[
                        const SizedBox(height: 24),

                        // Delivery Number
                        TextFormField(
                          controller: _deliveryNumberController,
                          decoration: InputDecoration(
                            labelText:
                                (_isNormalReplaceMode || _isSignedReplaceMode)
                                ? 'Delivery Number (optional - leave empty to keep current)'
                                : 'Delivery Number *',
                            hintText:
                                (_isNormalReplaceMode || _isSignedReplaceMode)
                                ? 'Enter new delivery number or leave empty'
                                : 'Enter delivery number',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (!(_isNormalReplaceMode ||
                                    _isSignedReplaceMode) &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Please enter delivery number';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Delivery Date
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

                        // Show cancel button
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _showNormalUploadForm
                                    ? (_isNormalReplaceMode
                                          ? 'Replace Normal Delivery PDF'
                                          : 'Upload Normal Delivery PDF')
                                    : 'Upload Signed Delivery PDF',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
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
                              },
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
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

                        // Normal Delivery Order PDF Section (only show when normal form is active)
                        if (_showNormalUploadForm) ...[
                          const Text(
                            '1. Normal Delivery Order PDF (Status: Issued)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _normalDeliveryFile != null
                                    ? Colors.blue
                                    : Colors.grey,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _normalDeliveryFile != null
                                      ? Icons.picture_as_pdf
                                      : Icons.upload_file,
                                  size: 48,
                                  color: _normalDeliveryFile != null
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _normalDeliveryFileName ??
                                      'No normal delivery file selected',
                                  style: TextStyle(
                                    fontWeight: _normalDeliveryFile != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _normalDeliveryFile != null
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _selectNormalDeliveryFile,
                                  icon: const Icon(Icons.folder_open),
                                  label: Text(
                                    _normalDeliveryFile != null
                                        ? 'Change Normal Delivery File'
                                        : 'Select Normal Delivery PDF',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),

                                // OCR Extraction Button (only show when normal file is selected)
                                if (_normalDeliveryFile != null) ...[
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: _isExtractingOCR
                                        ? null
                                        : _extractDeliveryData,
                                    icon: _isExtractingOCR
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Icon(Icons.text_fields),
                                    label: Text(
                                      _isExtractingOCR
                                          ? 'Extracting...'
                                          : 'Extract PDF Data',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  // Platform capabilities info
                                  const SizedBox(height: 4),
                                  Text(
                                    PlatformFeatures.supportsPDFOCR
                                        ? 'PDF text extraction supported'
                                        : 'PDF text extraction not available on ${PlatformFeatures.platformName}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Signed Delivery Order PDF Section (only show when signed form is active)
                        if (_showSignedUploadForm) ...[
                          const Text(
                            '2. Signed Delivery Order PDF (Status: Delivered)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _signedDeliveryFile != null
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _signedDeliveryFile != null
                                      ? Icons.picture_as_pdf
                                      : Icons.upload_file,
                                  size: 48,
                                  color: _signedDeliveryFile != null
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _signedDeliveryFileName ??
                                      'No signed delivery file selected',
                                  style: TextStyle(
                                    fontWeight: _signedDeliveryFile != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _signedDeliveryFile != null
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _selectSignedDeliveryFile,
                                  icon: const Icon(Icons.folder_open),
                                  label: Text(
                                    _signedDeliveryFile != null
                                        ? 'Change Signed Delivery File'
                                        : 'Select Signed Delivery PDF',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Remarks (always show for both normal and signed forms)
                        TextFormField(
                          controller: _remarksController,
                          decoration: const InputDecoration(
                            labelText: 'Remarks (optional)',
                            hintText: 'Enter any additional notes',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),

                        const SizedBox(height: 24),

                        // Upload Button (always show for both normal and signed forms)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showNormalUploadForm
                                ? ((_isUploadingNormal ||
                                          _normalDeliveryFile == null)
                                      ? null
                                      : _uploadNormalDeliveryOrder)
                                : ((_isUploadingSigned ||
                                          _signedDeliveryFile == null)
                                      ? null
                                      : _uploadSignedDeliveryOrder),
                            icon:
                                (_showNormalUploadForm
                                    ? _isUploadingNormal
                                    : _isUploadingSigned)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    _showNormalUploadForm
                                        ? Icons.local_shipping
                                        : Icons.verified,
                                  ),
                            label: Text(
                              _showNormalUploadForm
                                  ? (_isUploadingNormal
                                        ? (_isNormalReplaceMode
                                              ? 'Replacing Normal Delivery...'
                                              : 'Uploading Normal Delivery...')
                                        : (_isNormalReplaceMode
                                              ? 'Replace Normal Delivery'
                                              : 'Upload Normal Delivery (Status: Issued)'))
                                  : (_isUploadingSigned
                                        ? (_isSignedReplaceMode
                                              ? 'Replacing Signed Delivery...'
                                              : 'Uploading Signed Delivery...')
                                        : (_isSignedReplaceMode
                                              ? 'Replace Signed Delivery'
                                              : 'Upload Signed Delivery (Status: Delivered)')),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showNormalUploadForm
                                  ? Colors.blue
                                  : Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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
        _buildInfoRow('Invoice Status', invoiceStatus),
        _buildInfoRow('Delivery Status', deliveryStatus),
      ];
    }

    // For legacy single status system, show single status
    if (legacyStatus != null) {
      return [_buildInfoRow('Status', legacyStatus)];
    }

    // Fallback
    return [_buildInfoRow('Status', 'Unknown')];
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';

    DateTime dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    } else {
      return 'Invalid Date';
    }

    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  String _formatFileSize(dynamic size) {
    if (size == null) return 'N/A';

    int bytes;
    if (size is int) {
      bytes = size;
    } else if (size is String) {
      bytes = int.tryParse(size) ?? 0;
    } else {
      return 'Unknown';
    }

    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildItemDetails(Map<String, dynamic> order) {
    final items = order['items'] as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return const Text(
        'No items found',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Items (${items.length}):',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value as Map<String, dynamic>;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                _buildItemRow(
                  'Serial Number',
                  item['serial_number']?.toString() ?? 'N/A',
                ),
                _buildItemRow(
                  'Category',
                  item['equipment_category']?.toString() ?? 'N/A',
                ),
                _buildItemRow('Model', item['model']?.toString() ?? 'N/A'),
                _buildItemRow('Size', item['size']?.toString() ?? 'N/A'),
                _buildItemRow('Batch', item['batch']?.toString() ?? 'N/A'),
                if (item['transaction_id'] != null)
                  _buildItemRow(
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

  // Helper method to build item property rows
  Widget _buildItemRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to check if order is issued or delivered (dual status system support)
  bool _isOrderIssuedOrDelivered(Map<String, dynamic> order) {
    final deliveryStatus = order['delivery_status'] as String?;
    final legacyStatus = order['status'] as String?;

    // For dual status system
    if (deliveryStatus != null) {
      return deliveryStatus == 'Issued' || deliveryStatus == 'Delivered';
    }

    // For legacy single status system
    if (legacyStatus != null) {
      return legacyStatus == 'Issued' || legacyStatus == 'Delivered';
    }

    return false;
  }

  // Build Normal Delivery PDF Card
  Widget _buildNormalDeliveryCard() {
    if (_selectedOrder == null) return const SizedBox.shrink();

    final hasNormalDelivery = _currentDeliveryOrder?['normal_delivery'] != null;
    final canUploadNormal =
        (_selectedOrder!['invoice_status'] ?? _selectedOrder!['status']) ==
        'Invoiced';

    if (!hasNormalDelivery && !canUploadNormal) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasNormalDelivery ? Colors.blue.shade50 : Colors.grey.shade50,
        border: Border.all(
          color: hasNormalDelivery
              ? Colors.blue.shade200
              : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasNormalDelivery ? Icons.local_shipping : Icons.add_box,
                size: 20,
                color: hasNormalDelivery
                    ? Colors.blue.shade600
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Normal Delivery Order',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: hasNormalDelivery
                        ? Colors.blue.shade800
                        : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (hasNormalDelivery) ...[
            // Show PDF details
            _buildInfoRow(
              'Delivery Number',
              _currentDeliveryOrder!['delivery_number'],
            ),
            _buildInfoRow(
              'Delivery Date',
              _formatDate(_currentDeliveryOrder!['delivery_date']),
            ),
            _buildInfoRow(
              'File Name',
              _currentDeliveryOrder!['normal_delivery']['file_name'],
            ),
            _buildInfoRow(
              'File Size',
              _formatFileSize(
                _currentDeliveryOrder!['normal_delivery']['file_size'],
              ),
            ),
            _buildInfoRow(
              'Upload Date',
              _formatDate(
                _currentDeliveryOrder!['normal_delivery']['upload_date'],
              ),
            ),
            if (_currentDeliveryOrder!['delivery_remarks'] != null &&
                _currentDeliveryOrder!['delivery_remarks']
                    .toString()
                    .isNotEmpty)
              _buildInfoRow(
                'Remarks',
                _currentDeliveryOrder!['delivery_remarks'],
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _viewPDF(
                    _currentDeliveryOrder!['normal_delivery']['download_url'],
                  ),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View PDF'),
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
                    setState(() {
                      _isNormalReplaceMode = true;
                      _showNormalUploadForm = true;
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
              ],
            ),
          ] else ...[
            // Show add PDF message and button
            Text(
              'No normal delivery PDF uploaded yet.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showNormalUploadForm = true;
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Normal Delivery PDF'),
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
    );
  }

  // Build Signed Delivery PDF Card
  Widget _buildSignedDeliveryCard() {
    if (_selectedOrder == null) return const SizedBox.shrink();

    final hasSignedDelivery = _currentDeliveryOrder?['signed_delivery'] != null;
    final canUploadSigned = _isOrderIssuedOrDelivered(_selectedOrder!);

    if (!hasSignedDelivery && !canUploadSigned) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasSignedDelivery ? Colors.green.shade50 : Colors.grey.shade50,
        border: Border.all(
          color: hasSignedDelivery
              ? Colors.green.shade200
              : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasSignedDelivery ? Icons.verified : Icons.add_box,
                size: 20,
                color: hasSignedDelivery
                    ? Colors.green.shade600
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Signed Delivery Order',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: hasSignedDelivery
                        ? Colors.green.shade800
                        : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (hasSignedDelivery) ...[
            // Show PDF details
            _buildInfoRow(
              'File Name',
              _currentDeliveryOrder!['signed_delivery']['file_name'],
            ),
            _buildInfoRow(
              'File Size',
              _formatFileSize(
                _currentDeliveryOrder!['signed_delivery']['file_size'],
              ),
            ),
            _buildInfoRow(
              'Upload Date',
              _formatDate(
                _currentDeliveryOrder!['signed_delivery']['upload_date'],
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _viewPDF(
                    _currentDeliveryOrder!['signed_delivery']['download_url'],
                  ),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View PDF'),
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
                      _isSignedReplaceMode = true;
                      _showSignedUploadForm = true;
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
              ],
            ),
          ] else ...[
            // Show add PDF message and button
            Text(
              'No signed delivery PDF uploaded yet.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showSignedUploadForm = true;
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Signed Delivery PDF'),
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
    );
  }
}
