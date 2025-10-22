import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class PurchaseOrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  PurchaseOrderService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Create a multi-item stock-out purchase order
  /// This creates multiple transaction records (status: Reserved) and a single purchase order record
  /// Each item can have its own warranty type and period
  Future<Map<String, dynamic>> createMultiItemStockOutOrder({
    required String poNumber,
    required String dealerName,
    required String clientName,
    required String location,
    required List<Map<String, dynamic>> selectedItems,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      if (selectedItems.isEmpty) {
        return {
          'success': false,
          'error': 'No items selected for the purchase order.',
        };
      }

      // Handle optional client name - use default if empty
      final effectiveClientName = clientName.trim().isEmpty
          ? 'N/A'
          : clientName.trim();

      final currentDate = DateTime.now();
      final timestamp = Timestamp.fromDate(currentDate);

      // Check if PO number already exists
      final existingPO = await _firestore
          .collection('purchase_orders')
          .where('po_number', isEqualTo: poNumber)
          .get();

      if (existingPO.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Purchase Order number $poNumber already exists.',
        };
      }

      // Validate all items are still available
      for (final item in selectedItems) {
        final serialNumber = item['serial_number'];
        final activeTransactions = await _firestore
            .collection('transactions')
            .where('serial_number', isEqualTo: serialNumber)
            .where('status', isEqualTo: 'Active')
            .where('type', isEqualTo: 'Stock_In')
            .get();

        if (activeTransactions.docs.isEmpty) {
          return {
            'success': false,
            'error': 'Item $serialNumber is no longer available.',
          };
        }
      }

      // Get next entry number
      final nextEntryNumber = await _getNextEntryNumber();

      // Get starting transaction ID and generate sequential IDs for all items
      final startingTransactionId = await _getNextTransactionId();

      // Prepare transaction IDs list
      final List<int> transactionIds = [];

      // Use batch write to ensure all operations succeed or fail together
      final firestoreBatch = _firestore.batch();

      // Create transaction records for each item
      for (int i = 0; i < selectedItems.length; i++) {
        final item = selectedItems[i];
        final serialNumber = item['serial_number'];

        // Use sequential transaction IDs to avoid duplicates
        final nextTransactionId = startingTransactionId + i;
        transactionIds.add(nextTransactionId);

        // Prepare transaction data for stock-out (status: Reserved)
        final transactionData = {
          'transaction_id': nextTransactionId,
          'date': timestamp,
          'type': 'Stock_Out',
          'entry_no': nextEntryNumber,
          'customer_dealer': dealerName,
          'customer_client': effectiveClientName,
          'location': location,
          'equipment_category': item['equipment_category'],
          'model': item['model'],
          'serial_number': serialNumber,
          'quantity': 1,
          'unit_price': null, // Can be added later
          'total_price': null, // Can be calculated later
          'warranty_type':
              item['warranty_type'] ?? '1 year', // Use item's warranty type
          'warranty_period':
              item['warranty_period'] ?? 1, // Use item's warranty period
          'delivery_date': null, // Can be set later
          'invoice_number': null, // Can be set later
          'remarks': 'Reserved for PO: $poNumber',
          'status': 'Reserved',
          'uploaded_at': FieldValue.serverTimestamp(),
          'source': 'stock_out_manual',
          'uploaded_by_uid': currentUser.uid,
        };

        // Add transaction record to batch
        final transactionRef = _firestore.collection('transactions').doc();
        firestoreBatch.set(transactionRef, transactionData);
      }

      // Prepare purchase order data (store multiple transaction IDs)
      final purchaseOrderData = {
        'po_number': poNumber,
        'status': 'Pending',
        'created_date': timestamp,
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'transaction_ids': transactionIds, // Store all transaction IDs
        'total_items': selectedItems.length,
        'total_quantity': selectedItems.length,
        'created_by_uid': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Add purchase order record to batch
      final purchaseOrderRef = _firestore.collection('purchase_orders').doc();
      firestoreBatch.set(purchaseOrderRef, purchaseOrderData);

      // Commit the batch
      await firestoreBatch.commit();

      return {
        'success': true,
        'message':
            'Purchase Order $poNumber created successfully with ${selectedItems.length} items.',
        'po_id': purchaseOrderRef.id,
        'transaction_ids': transactionIds,
        'po_number': poNumber,
        'total_items': selectedItems.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create purchase order: ${e.toString()}',
      };
    }
  }

  /// Create a stock-out purchase order
  /// This creates both a transaction record (status: Reserved) and a purchase order record
  Future<Map<String, dynamic>> createStockOutOrder({
    required String poNumber,
    required String dealerName,
    required String clientName,
    required String serialNumber,
    required String location,
    required String warrantyType,
    required int warrantyPeriod,
    required Map<String, dynamic> itemDetails,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Handle optional client name - use default if empty
      final effectiveClientName = clientName.trim().isEmpty
          ? 'N/A'
          : clientName.trim();

      final currentDate = DateTime.now();
      final timestamp = Timestamp.fromDate(currentDate);

      // Check if PO number already exists
      final existingPO = await _firestore
          .collection('purchase_orders')
          .where('po_number', isEqualTo: poNumber)
          .get();

      if (existingPO.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Purchase Order number $poNumber already exists.',
        };
      }

      // Check if the item is still active and available
      final activeTransactions = await _firestore
          .collection('transactions')
          .where('serial_number', isEqualTo: serialNumber)
          .where('status', isEqualTo: 'Active')
          .where('type', isEqualTo: 'Stock_In')
          .get();

      if (activeTransactions.docs.isEmpty) {
        return {
          'success': false,
          'error':
              'Item with serial number $serialNumber is not available for stock-out.',
        };
      }

      // Get next transaction ID and entry number
      final nextTransactionId = await _getNextTransactionId();
      final nextEntryNumber = await _getNextEntryNumber();

      // Prepare transaction data for stock-out (status: Reserved)
      final transactionData = {
        'transaction_id': nextTransactionId,
        'date': timestamp,
        'type': 'Stock_Out',
        'entry_no': nextEntryNumber,
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'location': location,
        'equipment_category': itemDetails['equipment_category'],
        'model': itemDetails['model'],
        'serial_number': serialNumber,
        'quantity': 1,
        'unit_price': null, // Can be added later
        'total_price': null, // Can be calculated later
        'warranty_type': warrantyType,
        'warranty_period': warrantyPeriod,
        'delivery_date': null, // Can be set later
        'invoice_number': null, // Can be set later
        'remarks': 'Reserved for PO: $poNumber',
        'status': 'Reserved',
        'uploaded_at': FieldValue.serverTimestamp(),
        'source': 'stock_out_manual',
        'uploaded_by_uid': currentUser.uid,
      };

      // Prepare purchase order data (simplified - only store transaction IDs)
      final purchaseOrderData = {
        'po_number': poNumber,
        'status': 'Pending',
        'created_date': timestamp,
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'transaction_ids': [nextTransactionId], // Only store transaction IDs
        'total_items': 1,
        'total_quantity': 1,
        'created_by_uid': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Use batch write to ensure both operations succeed or fail together
      final firestoreBatch = _firestore.batch();

      // Add transaction record
      final transactionRef = _firestore.collection('transactions').doc();
      firestoreBatch.set(transactionRef, transactionData);

      // Add purchase order record
      final purchaseOrderRef = _firestore.collection('purchase_orders').doc();
      firestoreBatch.set(purchaseOrderRef, purchaseOrderData);

      // Commit the batch
      await firestoreBatch.commit();

      return {
        'success': true,
        'message': 'Purchase Order $poNumber created successfully.',
        'po_id': purchaseOrderRef.id,
        'transaction_id': transactionRef.id,
        'transaction_number': nextTransactionId,
        'po_number': poNumber,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create purchase order: ${e.toString()}',
      };
    }
  }

  /// Get the next transaction ID by finding the highest existing ID
  Future<int> _getNextTransactionId() async {
    try {
      final querySnapshot = await _firestore
          .collection('transactions')
          .orderBy('transaction_id', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return 1; // Start with 1 if no transactions exist
      }

      final lastTransactionId =
          querySnapshot.docs.first.data()['transaction_id'] as int;
      return lastTransactionId + 1;
    } catch (e) {
      // If there's an error or no transaction_id field, start with 1
      return 1;
    }
  }

  /// Get the next entry number by finding the highest existing entry_no and adding 1
  Future<int> _getNextEntryNumber() async {
    try {
      final querySnapshot = await _firestore
          .collection('transactions')
          .orderBy('entry_no', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return 1; // Start from 1 if no transactions exist
      }

      final highestEntryNo =
          querySnapshot.docs.first.data()['entry_no'] as int?;
      return (highestEntryNo ?? 0) + 1;
    } catch (e) {
      // If there's an error, fall back to 1
      return 1;
    }
  }

  /// Get the next entry number for display purposes (public method)
  Future<int> getNextEntryNumber() async {
    return await _getNextEntryNumber();
  }

  /// Get purchase order by PO number
  Future<Map<String, dynamic>?> getPurchaseOrder(String poNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('purchase_orders')
          .where('po_number', isEqualTo: poNumber)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        final poData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs
        if (data['transaction_ids'] != null) {
          final items = await getItemsFromTransactionIds(
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

  /// Get all purchase orders (with optional status filter)
  Future<List<Map<String, dynamic>>> getAllPurchaseOrders({
    String? status,
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection('purchase_orders')
          .orderBy('created_date', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final querySnapshot = await query.get();

      final purchaseOrders = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final poData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs
        if (data['transaction_ids'] != null) {
          final items = await getItemsFromTransactionIds(
            List<int>.from(data['transaction_ids']),
          );
          poData['items'] = items;
        } else {
          // Fallback for old format (items array)
          poData['items'] = data['items'] ?? [];
        }

        purchaseOrders.add(poData);
      }

      return purchaseOrders;
    } catch (e) {
      return [];
    }
  }

  /// Get item details from transaction IDs
  Future<List<Map<String, dynamic>>> getItemsFromTransactionIds(
    List<int> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return [];

    try {
      final querySnapshot = await _firestore
          .collection('transactions')
          .where('transaction_id', whereIn: transactionIds)
          .get();

      // Collect all serial numbers from transactions
      final serialNumbers = <String>[];
      final transactionMap = <String, Map<String, dynamic>>{};

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] ?? data['Serial_Number'];
        if (serialNumber != null) {
          serialNumbers.add(serialNumber);
          transactionMap[serialNumber] = data;
        }
      }

      // Batch query inventory for all serial numbers
      final inventoryMap = <String, Map<String, dynamic>>{};

      // Process in batches of 10 (Firestore 'in' query limitation)
      for (int i = 0; i < serialNumbers.length; i += 10) {
        final batch = serialNumbers.skip(i).take(10).toList();

        final inventoryQuery = await _firestore
            .collection('inventory')
            .where('serial_number', whereIn: batch)
            .get();

        for (final doc in inventoryQuery.docs) {
          final data = doc.data();
          final serialNumber = data['serial_number'] ?? data['Serial_Number'];
          if (serialNumber != null) {
            inventoryMap[serialNumber] = data;
          }
        }
      }

      // Build final items list with batch information
      final items = <Map<String, dynamic>>[];

      for (final serialNumber in serialNumbers) {
        final transactionData = transactionMap[serialNumber]!;
        final inventoryData = inventoryMap[serialNumber];

        items.add({
          'transaction_id': transactionData['transaction_id'],
          'serial_number': serialNumber,
          'equipment_category':
              transactionData['equipment_category'] ??
              transactionData['Equipment_Category'] ??
              transactionData['category'],
          'model': transactionData['model'] ?? transactionData['Model'],
          'size':
              transactionData['size'] ??
              transactionData['Size'] ??
              transactionData['specifications'] ??
              '-',
          'batch': inventoryData?['batch'] ?? inventoryData?['Batch'] ?? '-',
          'quantity':
              transactionData['quantity'] ?? transactionData['Quantity'] ?? 1,
        });
      }

      return items;
    } catch (e) {
      return [];
    }
  }

  /// Update purchase order status
  Future<Map<String, dynamic>> updatePurchaseOrderStatus({
    required String poNumber,
    required String newStatus,
    String? invoiceNumber,
    DateTime? deliveryDate,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Find the purchase order
      final poQuery = await _firestore
          .collection('purchase_orders')
          .where('po_number', isEqualTo: poNumber)
          .get();

      if (poQuery.docs.isEmpty) {
        return {
          'success': false,
          'error': 'Purchase Order $poNumber not found.',
        };
      }

      final poDoc = poQuery.docs.first;
      final poData = poDoc.data();

      // Prepare update data
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (invoiceNumber != null) {
        updateData['invoice_number'] = invoiceNumber;
      }

      if (deliveryDate != null) {
        updateData['delivery_date'] = Timestamp.fromDate(deliveryDate);
      }

      // Use batch to update both PO and related transactions
      final batch = _firestore.batch();

      // Update purchase order
      batch.update(poDoc.reference, updateData);

      // Update related transactions if status is changing to Delivered
      if (newStatus == 'Delivered') {
        final items = poData['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final transactionId = item['transaction_id'] as int?;
          if (transactionId != null) {
            final transactionQuery = await _firestore
                .collection('transactions')
                .where('transaction_id', isEqualTo: transactionId)
                .get();

            for (final transactionDoc in transactionQuery.docs) {
              final transactionUpdateData = <String, dynamic>{
                'status': 'Delivered',
                'updated_at': FieldValue.serverTimestamp(),
              };

              if (invoiceNumber != null) {
                transactionUpdateData['invoice_number'] = invoiceNumber;
              }

              if (deliveryDate != null) {
                transactionUpdateData['delivery_date'] = Timestamp.fromDate(
                  deliveryDate,
                );
              }

              batch.update(transactionDoc.reference, transactionUpdateData);
            }
          }
        }
      }

      await batch.commit();

      return {
        'success': true,
        'message': 'Purchase Order $poNumber updated to $newStatus.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update purchase order: ${e.toString()}',
      };
    }
  }

  /// Check if PO number exists
  Future<bool> poNumberExists(String poNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('purchase_orders')
          .where('po_number', isEqualTo: poNumber)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
