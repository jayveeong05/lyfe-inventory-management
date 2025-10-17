import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'auth_service.dart';
import 'purchase_order_service.dart';

class InvoiceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService;
  late final PurchaseOrderService _purchaseOrderService;

  InvoiceService({AuthService? authService})
    : _authService = authService ?? AuthService() {
    _purchaseOrderService = PurchaseOrderService(authService: _authService);
  }

  /// Get all purchase orders (regardless of status)
  Future<List<Map<String, dynamic>>> getAllPurchaseOrders() async {
    return await _purchaseOrderService.getAllPurchaseOrders();
  }

  /// Get purchase orders with Pending status (available for invoicing)
  Future<List<Map<String, dynamic>>> getAvailablePurchaseOrders() async {
    return await _purchaseOrderService.getAllPurchaseOrders(status: 'Pending');
  }

  /// Get purchase order by ID
  Future<Map<String, dynamic>?> getPurchaseOrderById(String poId) async {
    try {
      final doc = await _firestore
          .collection('purchase_orders')
          .doc(poId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final poData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs using purchase order service logic
        if (data['transaction_ids'] != null) {
          final items = await _purchaseOrderService.getItemsFromTransactionIds(
            List<int>.from(data['transaction_ids']),
          );
          poData['items'] = items;
        } else {
          // Fallback for old format (items array)
          poData['items'] = data['items'] ?? [];
        }

        return poData;
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

      // Get purchase order details
      final poData = await getPurchaseOrderById(poId);
      if (poData == null) {
        return {'success': false, 'error': 'Purchase order not found.'};
      }

      // Check if invoice number already exists
      final existingInvoice = await _firestore
          .collection('purchase_orders')
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
      final invoiceData = {
        'status': 'Invoiced',
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

      // Update purchase order with invoice data
      final poRef = _firestore.collection('purchase_orders').doc(poId);
      await poRef.update(invoiceData);

      // Update related transactions with invoice information (but keep status as 'Reserved')
      final batch = _firestore.batch();
      List<int> transactionIds = [];

      // Handle new format (transaction_ids) and old format (items array)
      if (poData['transaction_ids'] != null) {
        transactionIds = List<int>.from(poData['transaction_ids']);
      } else if (poData['items'] != null) {
        final items = poData['items'] as List<dynamic>;
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

  /// Get all invoices (from purchase orders with invoice data)
  Future<List<Map<String, dynamic>>> getAllInvoices({
    String? status,
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection('purchase_orders')
          .where('invoice_number', isNull: false)
          .orderBy('invoice_uploaded_at', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
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

  /// Get invoice by invoice number (from purchase orders)
  Future<Map<String, dynamic>?> getInvoiceByNumber(String invoiceNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('purchase_orders')
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

  /// Delete invoice data from PO and associated file
  Future<Map<String, dynamic>> deleteInvoice(String poId) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get PO data
      final poDoc = await _firestore
          .collection('purchase_orders')
          .doc(poId)
          .get();

      if (!poDoc.exists) {
        return {'success': false, 'error': 'Purchase Order not found.'};
      }

      final poData = poDoc.data() as Map<String, dynamic>;
      final pdfPath = poData['pdf_path'] as String?;

      // Remove invoice data from PO and revert status
      await poDoc.reference.update({
        'status': 'Pending',
        'invoice_number': FieldValue.delete(),
        'invoice_date': FieldValue.delete(),
        'pdf_url': FieldValue.delete(),
        'pdf_path': FieldValue.delete(),
        'file_name': FieldValue.delete(),
        'file_size': FieldValue.delete(),
        'invoice_remarks': FieldValue.delete(),
        'invoice_uploaded_by_uid': FieldValue.delete(),
        'invoice_uploaded_at': FieldValue.delete(),
        'invoice_updated_by_uid': FieldValue.delete(),
        'invoice_updated_at': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Remove invoice information from related transactions (but keep status as 'Reserved')
      final batch = _firestore.batch();
      List<int> transactionIds = [];

      // Handle new format (transaction_ids) and old format (items array)
      if (poData['transaction_ids'] != null) {
        transactionIds = List<int>.from(poData['transaction_ids']);
      } else if (poData['items'] != null) {
        final items = poData['items'] as List<dynamic>;
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

      if (transactionIds.isNotEmpty) {
        await batch.commit();
      }

      // Delete file from storage
      if (pdfPath != null) {
        try {
          await _storage.ref().child(pdfPath).delete();
        } catch (e) {
          // File might not exist, continue anyway
        }
      }

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
          .collection('purchase_orders')
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

  /// Get invoice by PO ID (from purchase order document)
  Future<Map<String, dynamic>?> getInvoiceByPoId(String poId) async {
    try {
      final doc = await _firestore
          .collection('purchase_orders')
          .doc(poId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Only return if it has invoice data
        if (data['invoice_number'] != null) {
          return {'id': doc.id, ...data};
        }
      }
      return null;
    } catch (e) {
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

      // Get existing PO with invoice data
      final poDoc = await _firestore
          .collection('purchase_orders')
          .doc(poId)
          .get();
      if (!poDoc.exists) {
        return {'success': false, 'error': 'Purchase Order not found.'};
      }

      final poData = poDoc.data() as Map<String, dynamic>;
      final oldPdfPath = poData['pdf_path'] as String?;
      final currentInvoiceNumber = poData['invoice_number'] as String?;

      if (currentInvoiceNumber == null) {
        return {'success': false, 'error': 'No invoice found for this PO.'};
      }

      // If new invoice number is provided, check if it already exists (and it's not the current one)
      if (newInvoiceNumber != null &&
          newInvoiceNumber != currentInvoiceNumber) {
        final existingInvoice = await _firestore
            .collection('purchase_orders')
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

      // Update PO with new invoice data
      await poDoc.reference.update(updatedData);

      // Update related transactions if invoice number changed
      if (newInvoiceNumber != null) {
        final batch = _firestore.batch();
        List<int> transactionIds = [];

        // Handle new format (transaction_ids) and old format (items array)
        if (poData['transaction_ids'] != null) {
          transactionIds = List<int>.from(poData['transaction_ids']);
        } else if (poData['items'] != null) {
          final items = poData['items'] as List<dynamic>;
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
