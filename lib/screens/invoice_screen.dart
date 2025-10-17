import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/invoice_service.dart';
import '../providers/auth_provider.dart';

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

  @override
  void initState() {
    super.initState();
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

      final pos = await invoiceService.getAllPurchaseOrders();

      setState(() {
        _allPOs = pos;
        _isLoadingPOs = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPOs = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading purchase orders: $e'),
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

      final invoice = await invoiceService.getInvoiceByPoId(poId);

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
        _remarksController.text = _currentInvoice!['remarks'] ?? '';
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
        // Replace existing invoice
        result = await invoiceService.replaceInvoice(
          poId: _currentInvoice!['id'],
          newPdfFile: _selectedFile!,
          newInvoiceNumber: _invoiceNumberController.text.trim().isNotEmpty
              ? _invoiceNumberController.text.trim()
              : null,
          newInvoiceDate: _selectedDate,
          remarks: _remarksController.text.trim().isNotEmpty
              ? _remarksController.text.trim()
              : null,
        );
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
                    'No Purchase Orders Available',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All purchase orders have been invoiced\nor no purchase orders exist.',
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
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        '🟠 Pending (Can upload) • 🟢 Invoiced (Processed)',
                        style: TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Purchase Order Selection
                    const Text(
                      'Select Purchase Order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Dropdown for PO Selection
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPOId,
                        decoration: const InputDecoration(
                          hintText: 'Choose a Purchase Order',
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
                                    'No purchase orders available',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ]
                            : _allPOs.map((po) {
                                final status =
                                    po['status'] as String? ?? 'Unknown';
                                final isPending = status == 'Pending';
                                final isInvoiced = status == 'Invoiced';

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
                                          color: isPending
                                              ? Colors.orange
                                              : isInvoiced
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'PO: ${po['po_number']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: isPending
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
                                          color: isPending
                                              ? Colors.orange.shade100
                                              : isInvoiced
                                              ? Colors.green.shade100
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: isPending
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
                            if (selectedPO['status'] == 'Invoiced') {
                              _loadInvoiceForPO(value);
                            }
                          }
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a purchase order';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Selected PO Information Card
                    if (_selectedPO != null) ...[
                      // Basic PO Information
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
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
                                  color: Colors.blue.shade600,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Selected Purchase Order Details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              'PO Number',
                              _selectedPO!['po_number'],
                            ),
                            _buildInfoRow('Status', _selectedPO!['status']),
                            _buildInfoRow(
                              'Dealer',
                              _selectedPO!['customer_dealer'],
                            ),
                            _buildInfoRow(
                              'Client',
                              _selectedPO!['customer_client'],
                            ),
                            _buildItemDetails(_selectedPO!),
                            if (_selectedPO!['created_date'] != null)
                              _buildInfoRow(
                                'Created Date',
                                _formatDate(_selectedPO!['created_date']),
                              ),
                            if (_selectedPO!['status'] == 'Invoiced' &&
                                _selectedPO!['invoice_number'] != null)
                              _buildInfoRow(
                                'Invoice Number',
                                _selectedPO!['invoice_number'],
                              ),
                          ],
                        ),
                      ),

                      // Invoice Information Card (for invoiced POs)
                      if (_selectedPO!['status'] == 'Invoiced') ...[
                        const SizedBox(height: 16),
                        if (_isLoadingInvoice)
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
                                Text('Loading invoice information...'),
                              ],
                            ),
                          )
                        else if (_currentInvoice != null)
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
                                      Icons.receipt_long,
                                      size: 20,
                                      color: Colors.green.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Invoice Information',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                    if (!_isReplaceMode) ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _viewPDF(
                                          _currentInvoice!['pdf_url'],
                                        ),
                                        icon: const Icon(
                                          Icons.visibility,
                                          size: 16,
                                        ),
                                        label: const Text('View PDF'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
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
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: const Text('Replace'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
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
                                    ] else ...[
                                      ElevatedButton.icon(
                                        onPressed: _toggleReplaceMode,
                                        icon: const Icon(Icons.close, size: 16),
                                        label: const Text('Cancel'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
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
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  'Invoice Number',
                                  _currentInvoice!['invoice_number'] ?? 'N/A',
                                ),
                                _buildInfoRow(
                                  'Invoice Date',
                                  _formatDate(_currentInvoice!['invoice_date']),
                                ),
                                _buildInfoRow(
                                  'File Name',
                                  _currentInvoice!['file_name'] ?? 'N/A',
                                ),
                                _buildInfoRow(
                                  'File Size',
                                  _formatFileSize(
                                    _currentInvoice!['file_size'],
                                  ),
                                ),
                                _buildInfoRow(
                                  'Uploaded At',
                                  _formatDate(
                                    _currentInvoice!['invoice_uploaded_at'],
                                  ),
                                ),
                                if (_currentInvoice!['invoice_remarks'] !=
                                        null &&
                                    _currentInvoice!['invoice_remarks']
                                        .toString()
                                        .isNotEmpty)
                                  _buildInfoRow(
                                    'Remarks',
                                    _currentInvoice!['invoice_remarks'],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_upward,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Please select a purchase order from the dropdown above to view details',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Show form only for pending POs or when in replace mode
                    if (_selectedPO != null &&
                        (_selectedPO!['status'] == 'Pending' ||
                            _isReplaceMode)) ...[
                      const SizedBox(height: 24),

                      // Invoice Number
                      TextFormField(
                        controller: _invoiceNumberController,
                        decoration: InputDecoration(
                          labelText: _isReplaceMode
                              ? 'Invoice Number (optional - leave empty to keep current)'
                              : 'Invoice Number *',
                          hintText: _isReplaceMode
                              ? 'Enter new invoice number or leave empty'
                              : 'Enter invoice number',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (!_isReplaceMode &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Please enter invoice number';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Invoice Date
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

                      // PDF File Selection
                      const Text(
                        'Invoice PDF File',
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
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Remarks
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          hintText: 'Enter any additional notes',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),

                      const SizedBox(height: 32),

                      // Upload Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _uploadInvoice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Uploading...'),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.cloud_upload),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isReplaceMode
                                          ? 'Replace Invoice'
                                          : 'Upload Invoice',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // Helper method to build item details section
  Widget _buildItemDetails(Map<String, dynamic> po) {
    final items = po['items'] as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return _buildInfoRow('Items', 'No items found');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Items (${items.length}):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
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
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build info rows in the PO details card
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
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

  // Helper method to format file size
  String _formatFileSize(dynamic fileSize) {
    if (fileSize == null) return 'N/A';

    try {
      final size = fileSize is int
          ? fileSize
          : int.tryParse(fileSize.toString()) ?? 0;
      if (size < 1024) {
        return '$size B';
      } else if (size < 1024 * 1024) {
        return '${(size / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (e) {
      return 'N/A';
    }
  }
}
