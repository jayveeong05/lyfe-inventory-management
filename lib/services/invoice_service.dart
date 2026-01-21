import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'order_service.dart';

class InvoiceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService;
  late final OrderService _orderService;

  InvoiceService({AuthService? authService})
    : _authService = authService ?? AuthService() {
    _orderService = OrderService(authService: _authService);
  }

  /// Get all orders (regardless of status)
  Future<List<Map<String, dynamic>>> getAllOrders() async {
    return await _orderService.getAllOrders();
  }

  /// Get orders with Reserved status (available for invoicing)
  Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    // Use new dual status system - get orders for invoicing operations
    return await _orderService.getOrdersForInvoicing();
  }

  /// Get orders for invoicing (Reserved and Invoiced status only)
  Future<List<Map<String, dynamic>>> getOrdersForInvoicing({
    bool fetchItems = true,
  }) async {
    try {
      // Use OrderService method that handles both dual status and legacy single status systems
      return await _orderService.getOrdersForInvoicing(fetchItems: fetchItems);
    } catch (e) {
      return [];
    }
  }

  /// Get order by ID
  Future<Map<String, dynamic>?> getOrderById(String orderId) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final orderData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs using order service logic
        if (data['transaction_ids'] != null) {
          final items = await _orderService.getItemsFromTransactionIds(
            List<int>.from(data['transaction_ids']),
          );
          orderData['items'] = items;
        } else {
          // Fallback for old format (items array)
          orderData['items'] = data['items'] ?? [];
        }

        return orderData;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Upload invoice PDF and create invoice record
  Future<Map<String, dynamic>> uploadInvoice({
    required String poId,
    required String invoiceNumber,
    required File pdfFile,
    required DateTime invoiceDate,
    String? remarks,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Validate file is PDF
      if (!pdfFile.path.toLowerCase().endsWith('.pdf')) {
        return {'success': false, 'error': 'Only PDF files are allowed.'};
      }

      // Check file size (limit to 10MB)
      final fileSize = await pdfFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        return {'success': false, 'error': 'File size must be less than 10MB.'};
      }

      // Get order details
      final orderData = await getOrderById(poId);
      if (orderData == null) {
        return {'success': false, 'error': 'Order not found.'};
      }

      // Check if invoice number already exists
      final existingInvoice = await _firestore
          .collection('orders')
          .where('invoice_number', isEqualTo: invoiceNumber)
          .get();

      if (existingInvoice.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Invoice number $invoiceNumber already exists.',
        };
      }

      // Create unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'invoice_${invoiceNumber}_$timestamp.pdf';
      final filePath = 'invoices/$fileName';

      // Upload file to Firebase Storage
      final uploadTask = _storage.ref().child(filePath).putFile(pdfFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Prepare invoice data to add to PO document
      final invoiceData = <String, dynamic>{
        'invoice_number': invoiceNumber,
        'invoice_date': Timestamp.fromDate(invoiceDate),
        'pdf_url': downloadUrl,
        'pdf_path': filePath,
        'file_name': fileName,
        'file_size': fileSize,
        'invoice_remarks': remarks ?? '',
        'invoice_uploaded_by_uid': currentUser.uid,
        'invoice_uploaded_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Update status based on system type
      if (orderData.containsKey('invoice_status')) {
        // New dual status system
        invoiceData['invoice_status'] = 'Invoiced';
      } else {
        // Legacy single status system
        invoiceData['status'] = 'Invoiced';
      }

      // Update order with invoice data
      final orderRef = _firestore.collection('orders').doc(poId);
      await orderRef.update(invoiceData);

      // Update related transactions with invoice information (but keep status as 'Reserved')
      final batch = _firestore.batch();
      List<int> transactionIds = [];

      // Handle new format (transaction_ids) and old format (items array)
      if (orderData['transaction_ids'] != null) {
        transactionIds = List<int>.from(orderData['transaction_ids']);
      } else if (orderData['items'] != null) {
        final items = orderData['items'] as List<dynamic>;
        for (final item in items) {
          final transactionId = item['transaction_id'] as int?;
          if (transactionId != null) {
            transactionIds.add(transactionId);
          }
        }
      }

      for (final transactionId in transactionIds) {
        final transactionQuery = await _firestore
            .collection('transactions')
            .where('transaction_id', isEqualTo: transactionId)
            .get();

        for (final transactionDoc in transactionQuery.docs) {
          // Only update invoice information, keep status as 'Reserved'
          batch.update(transactionDoc.reference, {
            'invoice_number': invoiceNumber,
            'invoice_date': Timestamp.fromDate(invoiceDate),
            'updated_at': FieldValue.serverTimestamp(),
            // Note: status remains 'Reserved' - only changes to 'Delivered' when actually delivered
          });
        }
      }

      if (transactionIds.isNotEmpty) {
        await batch.commit();
      }

      return {
        'success': true,
        'message': 'Invoice uploaded successfully.',
        'po_id': poId,
        'download_url': downloadUrl,
        'invoice_number': invoiceNumber,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to upload invoice: ${e.toString()}',
      };
    }
  }

  /// Get all invoices (from orders with invoice data)
  Future<List<Map<String, dynamic>>> getAllInvoices({
    String? status, // Legacy status filter
    String? invoiceStatus, // New invoice status filter
    String? deliveryStatus, // New delivery status filter
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection('orders')
          .where('invoice_number', isNull: false)
          .orderBy('invoice_uploaded_at', descending: true);

      // Apply filters based on available parameters
      if (status != null) {
        // Legacy single status filter (for backward compatibility)
        query = query.where('status', isEqualTo: status);
      }

      if (invoiceStatus != null) {
        // New invoice status filter
        query = query.where('invoice_status', isEqualTo: invoiceStatus);
      }

      if (deliveryStatus != null) {
        // New delivery status filter
        query = query.where('delivery_status', isEqualTo: deliveryStatus);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get invoice by invoice number (from orders)
  Future<Map<String, dynamic>?> getInvoiceByNumber(String invoiceNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('orders')
          .where('invoice_number', isEqualTo: invoiceNumber)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        return {'id': doc.id, ...doc.data()};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete invoice data from order and associated file (updated for new file-based system)
  Future<Map<String, dynamic>> deleteInvoice(String orderId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get order data
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();

      if (!orderDoc.exists) {
        return {'success': false, 'error': 'Order not found.'};
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final orderNumber = orderData['order_number'] as String?;

      if (orderNumber == null) {
        return {'success': false, 'error': 'Order number not found.'};
      }

      // Check if order has invoice status (support both dual and legacy status)
      final invoiceStatus = orderData['invoice_status'] as String?;
      final legacyStatus = orderData['status'] as String?;

      bool canDeleteInvoice = false;
      if (invoiceStatus != null) {
        // New dual status system
        canDeleteInvoice = invoiceStatus == 'Invoiced';
      } else if (legacyStatus != null) {
        // Legacy single status system
        canDeleteInvoice = legacyStatus == 'Invoiced';
      }

      if (!canDeleteInvoice) {
        return {'success': false, 'error': 'Order is not in Invoiced status.'};
      }

      // Use batch for atomic operations
      final batch = _firestore.batch();

      // Step 1: Remove invoice data from order and revert status
      final orderUpdateData = <String, dynamic>{
        'invoice_number': FieldValue.delete(),
        'invoice_date': FieldValue.delete(),
        'invoice_remarks': FieldValue.delete(),
        'invoice_file_id': FieldValue.delete(),
        'invoice_uploaded_at': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Revert status based on system type
      if (invoiceStatus != null) {
        // New dual status system - revert invoice_status to Reserved
        orderUpdateData['invoice_status'] = 'Reserved';
      } else {
        // Legacy single status system - revert status to Reserved
        orderUpdateData['status'] = 'Reserved';
      }

      batch.update(orderDoc.reference, orderUpdateData);

      // Step 2: Delete ALL invoice files (all versions) from files collection and storage
      final allInvoiceFiles = await _firestore
          .collection('files')
          .where('order_number', isEqualTo: orderNumber)
          .where('file_type', isEqualTo: 'invoice')
          .get();

      for (final fileDoc in allInvoiceFiles.docs) {
        final fileData = fileDoc.data();
        final filePath = fileData['file_path'] as String?;

        // Delete file record from files collection
        batch.delete(fileDoc.reference);

        // Delete file from Firebase Storage
        if (filePath != null) {
          try {
            await _storage.ref().child(filePath).delete();
            debugPrint('🗂️ Deleted invoice file from storage: $filePath');
          } catch (e) {
            // File might not exist in storage, continue anyway
            debugPrint('⚠️ Warning: Failed to delete file from storage: $e');
          }
        }
      }

      debugPrint(
        '📁 Deleted ${allInvoiceFiles.docs.length} invoice file versions for order $orderNumber',
      );

      // Step 3: Remove invoice information from related transactions (but keep status as 'Reserved')
      List<int> transactionIds = [];

      // Handle new format (transaction_ids) and old format (items array)
      if (orderData['transaction_ids'] != null) {
        transactionIds = List<int>.from(orderData['transaction_ids']);
      } else if (orderData['items'] != null) {
        final items = orderData['items'] as List<dynamic>;
        for (final item in items) {
          final transactionId = item['transaction_id'] as int?;
          if (transactionId != null) {
            transactionIds.add(transactionId);
          }
        }
      }

      for (final transactionId in transactionIds) {
        final transactionQuery = await _firestore
            .collection('transactions')
            .where('transaction_id', isEqualTo: transactionId)
            .get();

        for (final transactionDoc in transactionQuery.docs) {
          // Remove invoice information, keep status as 'Reserved'
          batch.update(transactionDoc.reference, {
            'invoice_number': FieldValue.delete(),
            'invoice_date': FieldValue.delete(),
            'updated_at': FieldValue.serverTimestamp(),
            // Note: status remains 'Reserved' - not changed back from 'Invoiced'
          });
        }
      }

      // Commit all changes atomically
      await batch.commit();

      return {'success': true, 'message': 'Invoice deleted successfully.'};
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to delete invoice: ${e.toString()}',
      };
    }
  }

  /// Check if invoice number exists
  Future<bool> invoiceNumberExists(String invoiceNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('orders')
          .where('invoice_number', isEqualTo: invoiceNumber)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Fix existing transactions with incorrect 'Invoiced' status
  /// This method corrects transactions that were incorrectly set to 'Invoiced' status
  /// and changes them back to 'Reserved' status (as they should be until delivery)
  Future<Map<String, dynamic>> fixInvoicedTransactionStatus() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Find all transactions with 'Invoiced' status
      final invoicedTransactionsQuery = await _firestore
          .collection('transactions')
          .where('status', isEqualTo: 'Invoiced')
          .get();

      if (invoicedTransactionsQuery.docs.isEmpty) {
        return {
          'success': true,
          'message': 'No transactions with incorrect Invoiced status found.',
          'fixed_count': 0,
        };
      }

      // Update all 'Invoiced' transactions to 'Reserved'
      final batch = _firestore.batch();
      int fixedCount = 0;

      for (final transactionDoc in invoicedTransactionsQuery.docs) {
        final transactionData = transactionDoc.data();
        final type = transactionData['type'] as String?;

        // Only fix Stock_Out transactions (Stock_In should never be Invoiced)
        if (type == 'Stock_Out') {
          batch.update(transactionDoc.reference, {
            'status': 'Reserved',
            'updated_at': FieldValue.serverTimestamp(),
            'status_fix_note':
                'Fixed from incorrect Invoiced status to Reserved',
            'status_fixed_at': FieldValue.serverTimestamp(),
            'status_fixed_by_uid': currentUser.uid,
          });
          fixedCount++;
        }
      }

      if (fixedCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'message':
            'Fixed $fixedCount transactions from Invoiced to Reserved status.',
        'fixed_count': fixedCount,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fix transaction status: ${e.toString()}',
      };
    }
  }

  /// Get invoice by order ID (from files collection and order document)
  Future<Map<String, dynamic>?> getInvoiceByOrderId(String orderId) async {
    try {
      // First get the order document to get order_number
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();

      if (!orderDoc.exists) {
        return null;
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final orderNumber = orderData['order_number'] as String?;

      if (orderNumber == null) {
        return null;
      }

      // Now get the active invoice file from files collection
      final filesQuery = await _firestore
          .collection('files')
          .where('order_number', isEqualTo: orderNumber)
          .where('file_type', isEqualTo: 'invoice')
          .where('is_active', isEqualTo: true)
          .limit(1)
          .get();

      if (filesQuery.docs.isEmpty) {
        return null;
      }

      final fileDoc = filesQuery.docs.first;
      final fileData = fileDoc.data();

      // Combine order data with file data for backward compatibility
      return {
        'id': orderId, // Keep order ID for compatibility
        'order_number': orderNumber,
        'status': orderData['status'],
        // Map file data to expected invoice fields
        'invoice_number':
            orderData['invoice_number'] ?? 'N/A', // From order if available
        'invoice_date':
            orderData['invoice_date'] ??
            fileData['upload_date'], // Use order invoice date if available, fallback to upload date
        'invoice_uploaded_at': fileData['upload_date'],
        'invoice_remarks': orderData['invoice_remarks'] ?? '',
        'pdf_url': fileData['storage_url'],
        'file_name': fileData['original_filename'],
        'file_size': fileData['file_size'],
        'uploaded_by': fileData['uploaded_by'],
        // Include file metadata
        'file_id': fileDoc.id,
        'file_path': fileData['file_path'],
        'version': fileData['version'],
      };
    } catch (e) {
      // Log error for debugging
      debugPrint('Error getting invoice by order ID: $e');
      return null;
    }
  }

  /// Replace existing invoice with new PDF
  Future<Map<String, dynamic>> replaceInvoice({
    required String poId,
    required File newPdfFile,
    String? newInvoiceNumber,
    DateTime? newInvoiceDate,
    String? remarks,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Validate file is PDF
      if (!newPdfFile.path.toLowerCase().endsWith('.pdf')) {
        return {'success': false, 'error': 'Only PDF files are allowed.'};
      }

      // Check file size (limit to 10MB)
      final fileSize = await newPdfFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        return {'success': false, 'error': 'File size must be less than 10MB.'};
      }

      // Get existing order with invoice data
      final orderDoc = await _firestore.collection('orders').doc(poId).get();
      if (!orderDoc.exists) {
        return {'success': false, 'error': 'Order not found.'};
      }

      final orderData = orderDoc.data() as Map<String, dynamic>;
      final oldPdfPath = orderData['pdf_path'] as String?;
      final currentInvoiceNumber = orderData['invoice_number'] as String?;

      if (currentInvoiceNumber == null) {
        return {'success': false, 'error': 'No invoice found for this PO.'};
      }

      // If new invoice number is provided, check if it already exists (and it's not the current one)
      if (newInvoiceNumber != null &&
          newInvoiceNumber != currentInvoiceNumber) {
        final existingInvoice = await _firestore
            .collection('orders')
            .where('invoice_number', isEqualTo: newInvoiceNumber)
            .get();

        if (existingInvoice.docs.isNotEmpty) {
          return {
            'success': false,
            'error': 'Invoice number $newInvoiceNumber already exists.',
          };
        }
      }

      // Create unique filename for new PDF
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final invoiceNumber = newInvoiceNumber ?? currentInvoiceNumber;
      final fileName = 'invoice_${invoiceNumber}_$timestamp.pdf';
      final filePath = 'invoices/$fileName';

      // Upload new file to Firebase Storage
      final uploadTask = _storage.ref().child(filePath).putFile(newPdfFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Prepare updated invoice data
      final updatedData = <String, dynamic>{
        'pdf_url': downloadUrl,
        'pdf_path': filePath,
        'file_name': fileName,
        'file_size': fileSize,
        'invoice_updated_by_uid': currentUser.uid,
        'invoice_updated_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (newInvoiceNumber != null) {
        updatedData['invoice_number'] = newInvoiceNumber;
      }

      if (newInvoiceDate != null) {
        updatedData['invoice_date'] = Timestamp.fromDate(newInvoiceDate);
      }

      if (remarks != null) {
        updatedData['invoice_remarks'] = remarks;
      }

      // Update order with new invoice data
      await orderDoc.reference.update(updatedData);

      // Update related transactions if invoice number changed
      if (newInvoiceNumber != null) {
        final batch = _firestore.batch();
        List<int> transactionIds = [];

        // Handle new format (transaction_ids) and old format (items array)
        if (orderData['transaction_ids'] != null) {
          transactionIds = List<int>.from(orderData['transaction_ids']);
        } else if (orderData['items'] != null) {
          final items = orderData['items'] as List<dynamic>;
          for (final item in items) {
            final transactionId = item['transaction_id'] as int?;
            if (transactionId != null) {
              transactionIds.add(transactionId);
            }
          }
        }

        for (final transactionId in transactionIds) {
          final transactionQuery = await _firestore
              .collection('transactions')
              .where('transaction_id', isEqualTo: transactionId)
              .get();

          for (final transactionDoc in transactionQuery.docs) {
            batch.update(transactionDoc.reference, {
              'invoice_number': newInvoiceNumber,
              'updated_at': FieldValue.serverTimestamp(),
            });
          }
        }

        if (transactionIds.isNotEmpty) {
          await batch.commit();
        }
      }

      // Delete old file from storage
      if (oldPdfPath != null) {
        try {
          await _storage.ref().child(oldPdfPath).delete();
        } catch (e) {
          // File might not exist, continue anyway
        }
      }

      return {
        'success': true,
        'message': 'Invoice replaced successfully.',
        'download_url': downloadUrl,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to replace invoice: ${e.toString()}',
      };
    }
  }
}
