import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'files_collection_service.dart';

class OrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;
  final FilesCollectionService _filesService = FilesCollectionService();

  OrderService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Create a multi-item stock-out order
  /// This creates multiple transaction records (status: Reserved) and a single order record
  /// Each item can have its own warranty type and period
  Future<Map<String, dynamic>> createMultiItemStockOutOrder({
    required String orderNumber,
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
        return {'success': false, 'error': 'No items selected for the order.'};
      }

      // Handle optional client name - use default if empty
      final effectiveClientName = clientName.trim().isEmpty
          ? 'N/A'
          : clientName.trim();

      final currentDate = DateTime.now();
      final timestamp = Timestamp.fromDate(currentDate);

      // Check if order number already exists
      final existingOrder = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (existingOrder.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Order number $orderNumber already exists.',
        };
      }

      // Get the next available transaction IDs for all items
      final nextTransactionIds = await _getNextTransactionIds(
        selectedItems.length,
      );

      // Prepare batch operations
      final batch = _firestore.batch();
      final transactionIds = <int>[];

      // Create transaction records for each selected item
      for (int i = 0; i < selectedItems.length; i++) {
        final item = selectedItems[i];
        final serialNumber = item['serial_number'] as String;
        final warrantyType = item['warranty_type'] as String? ?? 'No Warranty';
        final warrantyPeriod = item['warranty_period'] as int? ?? 0;
        final transactionId = nextTransactionIds[i];

        transactionIds.add(transactionId);

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
                'Item with serial number $serialNumber is not available or already reserved.',
          };
        }

        // Create Stock_Out transaction record
        final transactionData = {
          'transaction_id': transactionId,
          'serial_number': serialNumber,
          'type': 'Stock_Out',
          'status': 'Reserved', // Initial status is Reserved
          'location': location,
          'customer_dealer': dealerName,
          'customer_client': effectiveClientName,
          'date': timestamp,
          'uploaded_at': FieldValue.serverTimestamp(),
          'source': 'stock_out_manual',
          'uploaded_by_uid': currentUser.uid,
          'warranty_type': warrantyType,
          'warranty_period': warrantyPeriod,
        };

        // Add transaction to batch
        final transactionRef = _firestore.collection('transactions').doc();
        batch.set(transactionRef, transactionData);
      }

      // Prepare order data (simplified - only store transaction IDs)
      final orderData = {
        'order_number': orderNumber,
        'status':
            'Reserved', // Changed from 'Pending' to 'Reserved' for new file-based system
        'created_date': timestamp,
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'transaction_ids': transactionIds, // Only store transaction IDs
        'total_items': selectedItems.length,
        'total_quantity': selectedItems.length,
        'created_by_uid': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        // File reference fields for new file-based status system
        'invoice_file_id': null, // Will be set when invoice PDF is uploaded
        'delivery_file_id':
            null, // Will be set when delivery order PDF is uploaded
        'invoice_uploaded_at': null, // Timestamp when invoice was uploaded
        'delivery_uploaded_at':
            null, // Timestamp when delivery order was uploaded
      };

      // Add order to batch
      final orderRef = _firestore.collection('orders').doc();
      batch.set(orderRef, orderData);

      // Commit all operations
      await batch.commit();

      return {
        'success': true,
        'message': 'Multi-item order created successfully.',
        'order_id': orderRef.id,
        'order_number': orderNumber,
        'transaction_ids': transactionIds,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create order: ${e.toString()}',
      };
    }
  }

  /// Create a single-item stock-out order (legacy method for backward compatibility)
  Future<Map<String, dynamic>> createStockOutOrder({
    required String orderNumber,
    required String serialNumber,
    required String dealerName,
    required String clientName,
    required String location,
    String warrantyType = 'No Warranty',
    int warrantyPeriod = 0,
  }) async {
    // Convert to multi-item format and call the multi-item method
    final selectedItems = [
      {
        'serial_number': serialNumber,
        'warranty_type': warrantyType,
        'warranty_period': warrantyPeriod,
      },
    ];

    return await createMultiItemStockOutOrder(
      orderNumber: orderNumber,
      dealerName: dealerName,
      clientName: clientName,
      location: location,
      selectedItems: selectedItems,
    );
  }

  /// Get the next available transaction ID
  Future<int> getNextTransactionId() async {
    try {
      // Get the highest transaction_id from the transactions collection
      final querySnapshot = await _firestore
          .collection('transactions')
          .orderBy('transaction_id', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final highestId =
            querySnapshot.docs.first.data()['transaction_id'] as int;
        return highestId + 1;
      } else {
        return 1; // Start from 1 if no transactions exist
      }
    } catch (e) {
      return 1; // Default to 1 if there's an error
    }
  }

  /// Get multiple sequential transaction IDs
  Future<List<int>> _getNextTransactionIds(int count) async {
    final startId = await getNextTransactionId();
    return List.generate(count, (index) => startId + index);
  }

  /// Get next entry number for display purposes
  Future<int> getNextEntryNumber() async {
    try {
      // Get the count of all transactions + 1 with timeout
      final querySnapshot = await _firestore
          .collection('transactions')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Query timeout',
                const Duration(seconds: 10),
              );
            },
          );

      return querySnapshot.docs.length + 1;
    } catch (e) {
      // Log error silently and return default value
      return 1; // Default to 1 if there's an error
    }
  }

  /// Get order by order number
  Future<Map<String, dynamic>?> getOrder(String orderNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        final orderData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs
        if (data['transaction_ids'] != null) {
          final items = await getItemsFromTransactionIds(
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

  /// Get all orders (with optional status filter)
  Future<List<Map<String, dynamic>>> getAllOrders({
    String? status,
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection('orders')
          .orderBy('created_date', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final querySnapshot = await query.get();

      final orders = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final orderData = <String, dynamic>{'id': doc.id, ...data};

        // Get item details from transaction IDs
        if (data['transaction_ids'] != null) {
          final items = await getItemsFromTransactionIds(
            List<int>.from(data['transaction_ids']),
          );
          orderData['items'] = items;
        } else {
          // Fallback for old format (items array)
          orderData['items'] = data['items'] ?? [];
        }

        orders.add(orderData);
      }

      return orders;
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

      if (serialNumbers.isEmpty) return [];

      // Get inventory details for these serial numbers
      final inventorySnapshot = await _firestore
          .collection('inventory')
          .where('serial_number', whereIn: serialNumbers)
          .get();

      final items = <Map<String, dynamic>>[];

      for (final doc in inventorySnapshot.docs) {
        final inventoryData = doc.data();
        final serialNumber =
            inventoryData['serial_number'] ?? inventoryData['Serial_Number'];

        if (serialNumber != null && transactionMap.containsKey(serialNumber)) {
          final transactionData = transactionMap[serialNumber]!;

          // Combine inventory and transaction data
          final item = <String, dynamic>{
            ...inventoryData,
            'transaction_id': transactionData['transaction_id'],
            'transaction_status': transactionData['status'],
            'transaction_date': transactionData['date'],
            'warranty_type': transactionData['warranty_type'] ?? 'No Warranty',
            'warranty_period': transactionData['warranty_period'] ?? 0,
          };

          items.add(item);
        }
      }

      return items;
    } catch (e) {
      return [];
    }
  }

  /// Update order status
  Future<Map<String, dynamic>> updateOrderStatus({
    required String orderNumber,
    required String newStatus,
    String? invoiceNumber,
    DateTime? deliveryDate,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Find the order
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Order $orderNumber not found.'};
      }

      final orderDoc = orderQuery.docs.first;
      final orderData = orderDoc.data();

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

      // Use batch to update both order and related transactions
      final batch = _firestore.batch();

      // Update order
      batch.update(orderDoc.reference, updateData);

      // Update related transactions if status is changing to Delivered
      if (newStatus == 'Delivered') {
        final items = orderData['items'] as List<dynamic>? ?? [];
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
        'message': 'Order $orderNumber updated to $newStatus.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update order: ${e.toString()}',
      };
    }
  }

  /// Check if order number exists
  Future<bool> orderNumberExists(String orderNumber) async {
    try {
      final querySnapshot = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Update order with file reference and automatically update status
  Future<Map<String, dynamic>> updateOrderWithFile({
    required String orderNumber,
    required String fileId,
    required String fileType, // 'invoice' or 'delivery_order'
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Find the order
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Order $orderNumber not found.'};
      }

      final orderDoc = orderQuery.docs.first;
      final orderData = orderDoc.data();
      final currentStatus = orderData['status'] as String;

      // Prepare update data based on file type
      final updateData = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };

      String newStatus = currentStatus;

      if (fileType == 'invoice') {
        updateData['invoice_file_id'] = fileId;
        updateData['invoice_uploaded_at'] = FieldValue.serverTimestamp();

        // Update status to Invoiced if currently Reserved
        if (currentStatus == 'Reserved') {
          newStatus = 'Invoiced';
          updateData['status'] = newStatus;
        }
      } else if (fileType == 'delivery_order') {
        updateData['delivery_file_id'] = fileId;
        updateData['delivery_uploaded_at'] = FieldValue.serverTimestamp();

        // Update status to Delivered if currently Invoiced and has invoice file
        if (currentStatus == 'Invoiced' ||
            orderData['invoice_file_id'] != null) {
          newStatus = 'Delivered';
          updateData['status'] = newStatus;

          // Also update related transactions to Delivered
          await _updateTransactionStatusForOrder(orderNumber, 'Delivered');
        }
      }

      // Update the order
      await orderDoc.reference.update(updateData);

      return {
        'success': true,
        'message': 'Order $orderNumber updated with $fileType file.',
        'new_status': newStatus,
        'file_id': fileId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update order with file: ${e.toString()}',
      };
    }
  }

  /// Remove file reference from order and update status if needed
  Future<Map<String, dynamic>> removeFileFromOrder({
    required String orderNumber,
    required String fileType, // 'invoice' or 'delivery_order'
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Find the order
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Order $orderNumber not found.'};
      }

      final orderDoc = orderQuery.docs.first;

      // Prepare update data
      final updateData = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (fileType == 'invoice') {
        updateData['invoice_file_id'] = null;
        updateData['invoice_uploaded_at'] = null;
      } else if (fileType == 'delivery_order') {
        updateData['delivery_file_id'] = null;
        updateData['delivery_uploaded_at'] = null;
      }

      // Update the order (status remains unchanged as per requirements)
      await orderDoc.reference.update(updateData);

      return {
        'success': true,
        'message': 'File reference removed from order $orderNumber.',
        'warning':
            'Order status remains unchanged. File deletion does not affect order status.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to remove file from order: ${e.toString()}',
      };
    }
  }

  /// Get order file status
  Future<Map<String, dynamic>> getOrderFileStatus(String orderNumber) async {
    try {
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Order $orderNumber not found.'};
      }

      final orderData = orderQuery.docs.first.data();

      return {
        'success': true,
        'order_number': orderNumber,
        'status': orderData['status'],
        'has_invoice': orderData['invoice_file_id'] != null,
        'has_delivery_order': orderData['delivery_file_id'] != null,
        'invoice_file_id': orderData['invoice_file_id'],
        'delivery_file_id': orderData['delivery_file_id'],
        'invoice_uploaded_at': orderData['invoice_uploaded_at'],
        'delivery_uploaded_at': orderData['delivery_uploaded_at'],
        'is_complete':
            orderData['invoice_file_id'] != null &&
            orderData['delivery_file_id'] != null,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to get order file status: ${e.toString()}',
      };
    }
  }

  /// Helper method to update transaction status for an order
  Future<void> _updateTransactionStatusForOrder(
    String orderNumber,
    String newStatus,
  ) async {
    try {
      // Get the order to find transaction IDs
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) return;

      final orderData = orderQuery.docs.first.data();
      final transactionIds = List<int>.from(orderData['transaction_ids'] ?? []);

      if (transactionIds.isEmpty) return;

      // Update all related transactions
      final batch = _firestore.batch();

      for (final transactionId in transactionIds) {
        final transactionQuery = await _firestore
            .collection('transactions')
            .where('transaction_id', isEqualTo: transactionId)
            .get();

        for (final transactionDoc in transactionQuery.docs) {
          batch.update(transactionDoc.reference, {
            'status': newStatus,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
    } catch (e) {
      // Log error but don't throw - this is a helper method
      // In production, use a proper logging framework instead of print
      // ignore: avoid_print
      print('Warning: Failed to update transaction status: ${e.toString()}');
    }
  }

  /// Stream order file status for real-time updates
  Stream<Map<String, dynamic>> streamOrderFileStatus(String orderNumber) {
    return _firestore
        .collection('orders')
        .where('order_number', isEqualTo: orderNumber)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return {'success': false, 'error': 'Order $orderNumber not found.'};
          }

          final orderData = snapshot.docs.first.data();

          return {
            'success': true,
            'order_number': orderNumber,
            'status': orderData['status'],
            'has_invoice': orderData['invoice_file_id'] != null,
            'has_delivery_order': orderData['delivery_file_id'] != null,
            'invoice_file_id': orderData['invoice_file_id'],
            'delivery_file_id': orderData['delivery_file_id'],
            'invoice_uploaded_at': orderData['invoice_uploaded_at'],
            'delivery_uploaded_at': orderData['delivery_uploaded_at'],
            'is_complete':
                orderData['invoice_file_id'] != null &&
                orderData['delivery_file_id'] != null,
          };
        });
  }
}
