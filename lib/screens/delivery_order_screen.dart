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
  File? _selectedFile;
  String? _selectedFileName;

  bool _isLoadingOrders = false;
  bool _isUploading = false;
  bool _isReplaceMode = false;
  bool _isLoadingDeliveryOrder = false;
  bool _isExtractingOCR = false;

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

      // Load orders with 'Invoiced' status (ready for delivery)
      final orders = await orderService.getAllOrders(status: 'Invoiced');

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

        if (orderData['status'] == 'Delivered' &&
            orderData['delivery_file_id'] != null) {
          // Load delivery order file information
          final fileDoc = await FirebaseFirestore.instance
              .collection('files')
              .doc(orderData['delivery_file_id'])
              .get();

          if (fileDoc.exists) {
            final fileData = fileDoc.data() as Map<String, dynamic>;
            setState(() {
              _currentDeliveryOrder = {
                'id': orderId,
                'order_number': orderData['order_number'],
                'delivery_number': orderData['delivery_number'],
                'delivery_date': orderData['delivery_date'],
                'delivery_remarks': orderData['delivery_remarks'],
                'file_name': fileData['original_filename'],
                'file_size': fileData['file_size'],
                'upload_date': fileData['upload_date'],
                'download_url': fileData['download_url'],
              };
            });
          }
        } else {
          setState(() {
            _currentDeliveryOrder = null;
          });
        }
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

  void _toggleReplaceMode() {
    setState(() {
      _isReplaceMode = !_isReplaceMode;
      if (!_isReplaceMode) {
        // Reset form when exiting replace mode
        _selectedFile = null;
        _selectedFileName = null;
        _deliveryNumberController.clear();
        _remarksController.clear();
        _selectedDate = DateTime.now();
      }
    });
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

  Future<void> _extractDeliveryData() async {
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
      final result = await _ocrService.extractDeliveryData(_selectedFile!);

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
                  'Delivery data extracted successfully! (${confidencePercent}% confidence)',
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

  /// Upload delivery order using FileService and OrderService
  Future<void> _uploadDeliveryOrderWithFileService() async {
    if (!_formKey.currentState!.validate() ||
        _selectedOrderId == null ||
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

    setState(() {
      _isUploading = true;
    });

    try {
      // Step 1: Validate file before upload
      final fileValidation = await _fileService.validateFile(
        _selectedFile!,
        'delivery_order',
      );
      if (!fileValidation['valid']) {
        throw Exception(fileValidation['error'] ?? 'File validation failed');
      }

      // Step 2: Upload file using FileService
      final uploadResult = await _fileService.uploadFile(
        file: _selectedFile!,
        orderNumber: orderNumber,
        fileType: 'delivery_order',
      );

      if (!uploadResult.success) {
        throw Exception(uploadResult.error ?? 'File upload failed');
      }

      // Step 3: Update order with file reference using OrderService
      final orderUpdateResult = await _orderService.updateOrderWithFile(
        orderNumber: orderNumber,
        fileId: uploadResult.fileId!,
        fileType: 'delivery_order',
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
              'Success! Delivery order uploaded successfully.\n'
              'Order status: ${orderUpdateResult['new_status']}\n'
              'File: ${uploadResult.fileModel?.originalFilename ?? 'Unknown'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Clear form and reload data
        _deliveryNumberController.clear();
        _remarksController.clear();
        setState(() {
          _selectedOrderId = null;
          _selectedFile = null;
          _selectedFileName = null;
          _selectedDate = DateTime.now();
          _currentDeliveryOrder = null;
        });

        // Reload available orders to reflect status changes
        _loadAvailableOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading delivery order: $e'),
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
                        '🟢 Invoiced (Can deliver) • 🔵 Delivered (Completed)',
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
                      items: _allOrders.map((order) {
                        final orderNumber = order['order_number'] ?? 'Unknown';
                        final dealer = order['customer_dealer'] ?? 'Unknown';
                        final client = order['customer_client'] ?? 'Unknown';

                        return DropdownMenuItem<String>(
                          value: order['id'],
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
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
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedOrderId = newValue;
                          _currentDeliveryOrder = null;
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
                            _buildInfoRow('Status', _selectedOrder!['status']),
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
                            if (_selectedOrder!['status'] == 'Delivered' &&
                                _selectedOrder!['delivery_number'] != null)
                              _buildInfoRow(
                                'Delivery Number',
                                _selectedOrder!['delivery_number'],
                              ),
                          ],
                        ),
                      ),

                      // Delivery Order Information Card (for delivered orders)
                      if (_selectedOrder!['status'] == 'Delivered') ...[
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
                          )
                        else if (_currentDeliveryOrder != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border.all(color: Colors.green.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.local_shipping,
                                      size: 20,
                                      color: Colors.green.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Delivery Order Information',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  'Delivery Number',
                                  _currentDeliveryOrder!['delivery_number'],
                                ),
                                _buildInfoRow(
                                  'Delivery Date',
                                  _formatDate(
                                    _currentDeliveryOrder!['delivery_date'],
                                  ),
                                ),
                                _buildInfoRow(
                                  'Remarks',
                                  _currentDeliveryOrder!['delivery_remarks'],
                                ),
                                _buildInfoRow(
                                  'File Name',
                                  _currentDeliveryOrder!['file_name'],
                                ),
                                _buildInfoRow(
                                  'File Size',
                                  _formatFileSize(
                                    _currentDeliveryOrder!['file_size'],
                                  ),
                                ),
                                _buildInfoRow(
                                  'Upload Date',
                                  _formatDate(
                                    _currentDeliveryOrder!['upload_date'],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () => _viewPDF(
                                        _currentDeliveryOrder!['download_url'],
                                      ),
                                      icon: const Icon(
                                        Icons.picture_as_pdf,
                                        size: 16,
                                      ),
                                      label: const Text('View PDF'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _toggleReplaceMode,
                                      icon: const Icon(
                                        Icons.swap_horiz,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _isReplaceMode ? 'Cancel' : 'Replace',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isReplaceMode
                                            ? Colors.grey
                                            : Colors.orange,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                      // Show form only for invoiced orders or when in replace mode
                      if (_selectedOrder != null &&
                          (_selectedOrder!['status'] == 'Invoiced' ||
                              _isReplaceMode)) ...[
                        const SizedBox(height: 24),

                        // Delivery Number
                        TextFormField(
                          controller: _deliveryNumberController,
                          decoration: InputDecoration(
                            labelText: _isReplaceMode
                                ? 'Delivery Number (optional - leave empty to keep current)'
                                : 'Delivery Number *',
                            hintText: _isReplaceMode
                                ? 'Enter new delivery number or leave empty'
                                : 'Enter delivery number',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (!_isReplaceMode &&
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

                        // PDF File Selection
                        const Text(
                          'Delivery Order PDF File',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _selectedFile != null
                                  ? Colors.green
                                  : Colors.grey,
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
                                color: _selectedFile != null
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedFileName ?? 'No file selected',
                                style: TextStyle(
                                  fontWeight: _selectedFile != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _selectedFile != null
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _pickFile,
                                icon: const Icon(Icons.folder_open),
                                label: Text(
                                  _selectedFile != null
                                      ? 'Change File'
                                      : 'Select PDF File',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),

                              // OCR Extraction Button (only show when file is selected)
                              if (_selectedFile != null) ...[
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

                        const SizedBox(height: 16),

                        // Remarks
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

                        // Upload Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isUploading
                                ? null
                                : _uploadDeliveryOrderWithFileService,
                            icon: _isUploading
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
                                : const Icon(Icons.local_shipping),
                            label: Text(
                              _isUploading
                                  ? 'Uploading...'
                                  : (_isReplaceMode
                                        ? 'Replace Delivery Order'
                                        : 'Upload Delivery Order'),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
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
}
