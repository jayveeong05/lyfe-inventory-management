import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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

      // Get one entry number for the entire order
      final int entryNo = await getNextEntryNumber();

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
        // final entryNo = nextEntryNumbers[i]; // Removed: now using single entryNo

        transactionIds.add(transactionId);

        // Check if the item is still active and available
        final activeTransactions = await _firestore
            .collection('transactions')
            .where('serial_number', isEqualTo: serialNumber)
            .where('status', isEqualTo: 'Active')
            .where('type', isEqualTo: 'Stock_In')
            .get();

        if (activeTransactions.docs.isEmpty) {
          // Fallback: Check inventory status directly
          final invCheck = await _firestore
              .collection('inventory')
              .where('serial_number', isEqualTo: serialNumber)
              .limit(1)
              .get();
          bool isAvailable = false;
          if (invCheck.docs.isNotEmpty) {
            final status = invCheck.docs.first.data()['status'];
            if (status == 'Active') isAvailable = true;
          }

          if (!isAvailable) {
            return {
              'success': false,
              'error':
                  'Item with serial number $serialNumber is not active or available.',
            };
          }
        }

        // Update inventory status
        final inventoryDoc = await _firestore
            .collection('inventory')
            .where('serial_number', isEqualTo: serialNumber)
            .limit(1)
            .get();
        if (inventoryDoc.docs.isNotEmpty) {
          batch.update(inventoryDoc.docs.first.reference, {
            'status': 'Reserved',
          });
        }

        // Create Stock_Out transaction record
        final transactionData = {
          'transaction_id': transactionId,
          'entry_no': entryNo,
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
        // DUAL STATUS SYSTEM
        'invoice_status': 'Reserved', // Reserved | Invoiced
        'delivery_status': 'Pending', // Pending | Issued | Delivered
        'created_date': timestamp,
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'transaction_ids': transactionIds, // Only store transaction IDs
        'entry_no': entryNo, // Store entry_no in order as well for reference
        'total_items': selectedItems.length,
        'total_quantity': selectedItems.length,
        'created_by_uid': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        // File reference fields for new file-based status system
        'invoice_file_id': null, // Will be set when invoice PDF is uploaded
        'delivery_file_id':
            null, // Will be set when normal delivery order PDF is uploaded
        'signed_delivery_file_id':
            null, // Will be set when signed delivery order PDF is uploaded
        'invoice_uploaded_at': null, // Timestamp when invoice was uploaded
        'delivery_uploaded_at':
            null, // Timestamp when delivery order was uploaded
        'signed_delivery_uploaded_at':
            null, // Timestamp when signed delivery order was uploaded
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

  /// Process an item return and replacement
  /// Creates a 'Returned' transaction for the old item
  /// Creates a 'Stock_Out' transaction for the replacement item
  Future<Map<String, dynamic>> processItemReturn({
    required String returnedSerial,
    required String replacementSerial,
    required String dealerName,
    required String remarks,
    required String userUid,
  }) async {
    try {
      final batch = _firestore.batch();
      final timestamp = Timestamp.now();

      // 0. Fetch original transaction to get correct dealer/client info and entry_no
      final originalTransactionQuery = await _firestore
          .collection('transactions')
          .where('serial_number', isEqualTo: returnedSerial)
          .where('type', isEqualTo: 'Stock_Out')
          .orderBy('date', descending: true)
          .limit(1)
          .get();

      String customerDealer = dealerName;
      String customerClient = 'N/A';
      int? originalEntryNo;
      String? invoiceNumber;
      String? equipmentCategory;
      String? model;
      String? location;
      double? unitPrice;
      String? warrantyType;
      int? warrantyPeriod;
      Timestamp? deliveryDate;

      if (originalTransactionQuery.docs.isNotEmpty) {
        final originalData = originalTransactionQuery.docs.first.data();
        customerDealer = originalData['customer_dealer'] ?? dealerName;
        customerClient = originalData['customer_client'] ?? 'N/A';
        originalEntryNo = originalData['entry_no'];
        invoiceNumber = originalData['invoice_number'] as String?;
        equipmentCategory = originalData['equipment_category'] as String?;
        model = originalData['model'] as String?;
        location = originalData['location'] as String?;
        unitPrice = (originalData['unit_price'] as num?)?.toDouble();
        warrantyType = originalData['warranty_type'] as String?;
        warrantyPeriod = originalData['warranty_period'] as int?;
        deliveryDate = originalData['delivery_date'] as Timestamp?;
      }

      // 1. Create 'Returned' transaction for the old item
      final returnedTransactionId = await getNextTransactionId();
      final returnedTransactionRef = _firestore
          .collection('transactions')
          .doc();

      final returnedData = {
        'transaction_id': returnedTransactionId,
        'serial_number': returnedSerial.trim().toUpperCase(),
        'type': 'Returned',
        'status': 'Returned',
        'customer_dealer': customerDealer,
        'customer_client': customerClient,
        'remarks': 'Replaced by $replacementSerial. $remarks',
        'date': timestamp,
        'uploaded_at': FieldValue.serverTimestamp(),
        'uploaded_by_uid': userUid,
      };

      batch.set(returnedTransactionRef, returnedData);

      // 2. Create 'Stock_Out' transaction for the replacement item
      // We need a new transaction ID (incremented)
      final replacementTransactionId = returnedTransactionId + 1;
      // Use original entry_no if available, otherwise generate new one
      final replacementEntryNo = originalEntryNo ?? await getNextEntryNumber();
      final replacementTransactionRef = _firestore
          .collection('transactions')
          .doc();

      final replacementData = {
        'transaction_id': replacementTransactionId,
        'entry_no': replacementEntryNo,
        'serial_number': replacementSerial.trim().toUpperCase(),
        'type': 'Stock_Out',
        'status': 'Delivered', // Status is Delivered as requested
        'customer_dealer': customerDealer,
        'customer_client': customerClient,
        'remarks': 'Replacement for $returnedSerial',
        'date': timestamp,
        'uploaded_at': FieldValue.serverTimestamp(),
        'uploaded_by_uid': userUid,
        'source': 'item_replacement',
        // Copy fields from original transaction
        if (invoiceNumber != null) 'invoice_number': invoiceNumber,
        if (equipmentCategory != null) 'equipment_category': equipmentCategory,
        if (model != null) 'model': model,
        if (location != null) 'location': location,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (warrantyType != null) 'warranty_type': warrantyType,
        if (warrantyPeriod != null) 'warranty_period': warrantyPeriod,
        if (deliveryDate != null) 'delivery_date': deliveryDate,
      };

      batch.set(replacementTransactionRef, replacementData);

      // 3. Update Inventory Status
      // Returned item becomes 'Returned' (needs inspection/action)
      final returnedInventoryQuery = await _firestore
          .collection('inventory')
          .where('serial_number', isEqualTo: returnedSerial)
          .limit(1)
          .get();

      if (returnedInventoryQuery.docs.isNotEmpty) {
        batch.update(returnedInventoryQuery.docs.first.reference, {
          'status': 'Returned',
        });
      }

      // Replacement item becomes 'Reserved' (out of stock)
      final replacementInventoryQuery = await _firestore
          .collection('inventory')
          .where('serial_number', isEqualTo: replacementSerial)
          .limit(1)
          .get();

      if (replacementInventoryQuery.docs.isNotEmpty) {
        batch.update(replacementInventoryQuery.docs.first.reference, {
          'status': 'Reserved',
        });
      }

      await batch.commit();

      return {'success': true, 'message': 'Return processed successfully'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to process return: $e'};
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

  /// Get next entry number for Stock_Out transactions only
  Future<int> getNextEntryNumber() async {
    try {
      // Get the highest entry_no from Stock_Out transactions only
      final querySnapshot = await _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out')
          .orderBy('entry_no', descending: true)
          .limit(1)
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

      if (querySnapshot.docs.isNotEmpty) {
        final highestEntryNo =
            querySnapshot.docs.first.data()['entry_no'] as int?;
        return (highestEntryNo ?? 0) + 1;
      } else {
        return 1; // First Stock_Out entry
      }
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
  /// Supports both old single status and new dual status system
  Future<List<Map<String, dynamic>>> getAllOrders({
    String? status, // Legacy single status filter
    String? invoiceStatus, // New invoice status filter
    String? deliveryStatus, // New delivery status filter
    int? limit,
  }) async {
    try {
      print('🔍 getAllOrders: Starting query...');
      Query query = _firestore
          .collection('orders')
          .orderBy('created_date', descending: true);

      // Apply filters based on available parameters
      if (status != null) {
        // Legacy single status filter (for backward compatibility)
        query = query.where('status', isEqualTo: status);
      }

      if (invoiceStatus != null) {
        // New invoice status filter with fallback to legacy status
        // This handles orders that might not have invoice_status field yet
        query = query.where('invoice_status', isEqualTo: invoiceStatus);
      }

      if (deliveryStatus != null) {
        // New delivery status filter
        query = query.where('delivery_status', isEqualTo: deliveryStatus);
      }

      if (limit != null) {
        query = query.limit(limit);
      }
      print('🔍 getAllOrders: Executing query...');
      final querySnapshot = await query.get();
      print('🔍 getAllOrders: Got ${querySnapshot.docs.length} docs');
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
      print('🔍 getAllOrders: Returning ${orders.length} orders');
      return orders;
    } catch (e) {
      print('🔍 getAllOrders: Error: $e');
      return [];
    }
  }

  /// Get orders for invoice operations (Reserved and Invoiced invoice status)
  Future<List<Map<String, dynamic>>> getOrdersForInvoicing() async {
    try {
      print('🔍 getOrdersForInvoicing: Starting...');
      // Get all orders and filter for invoice operations
      // This handles both new dual status and legacy single status systems
      final allOrders = await getAllOrders();
      print('🔍 getOrdersForInvoicing: Got ${allOrders.length} orders');
      final invoiceOrders = allOrders.where((order) {
        // First check if order is cancelled - exclude cancelled orders
        final orderStatus = order['order_status'] as String?;
        if (orderStatus == 'Cancelled') {
          return false;
        }

        // Support both new dual status and legacy single status
        final invoiceStatus = order['invoice_status'] as String?;
        final legacyStatus = order['status'] as String?;

        if (invoiceStatus != null) {
          // New dual status system: invoice_status can be 'Reserved' or 'Invoiced'
          return ['Reserved', 'Invoiced'].contains(invoiceStatus);
        } else if (legacyStatus != null) {
          // Legacy single status system: all statuses are valid for invoice operations
          return [
            'Reserved',
            'Invoiced',
            'Issued',
            'Delivered',
          ].contains(legacyStatus);
        }

        return false;
      }).toList();

      // Sort by created_date (newest first)
      invoiceOrders.sort((a, b) {
        final aDate = a['created_date'] as Timestamp?;
        final bDate = b['created_date'] as Timestamp?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });
      print('🔍 getOrdersForInvoicing: Final count = ${invoiceOrders.length}');
      return invoiceOrders;
    } catch (e) {
      print('🔍 getOrdersForInvoicing: Error: $e');
      return [];
    }
  }

  /// Get orders for delivery operations (Invoiced invoice status with various delivery statuses)
  Future<List<Map<String, dynamic>>> getOrdersForDelivery() async {
    try {
      // Get all orders and filter for delivery operations
      // This handles both new dual status and legacy single status systems
      final allOrders = await getAllOrders();

      final deliveryOrders = allOrders.where((order) {
        // First check if order is cancelled - exclude cancelled orders
        final orderStatus = order['order_status'] as String?;
        if (orderStatus == 'Cancelled') {
          return false;
        }

        // Support both new dual status and legacy single status
        final invoiceStatus = order['invoice_status'] as String?;
        final legacyStatus = order['status'] as String?;

        if (invoiceStatus != null) {
          // New dual status system: invoice_status must be 'Invoiced'
          return invoiceStatus == 'Invoiced';
        } else if (legacyStatus != null) {
          // Legacy single status system: status must be 'Invoiced', 'Issued', or 'Delivered'
          return ['Invoiced', 'Issued', 'Delivered'].contains(legacyStatus);
        }

        return false;
      }).toList();

      // Sort by created_date (newest first)
      deliveryOrders.sort((a, b) {
        final aDate = a['created_date'] as Timestamp?;
        final bDate = b['created_date'] as Timestamp?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });

      return deliveryOrders;
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

              // [PATCH] Update Inventory Status to 'Delivered' as well
              // This fixes the "Reserved" vs "Delivered" sync issue
              final serialNumber =
                  transactionDoc.data()['serial_number'] as String?;
              if (serialNumber != null) {
                final inventoryQuery = await _firestore
                    .collection('inventory')
                    .where('serial_number', isEqualTo: serialNumber)
                    .limit(1)
                    .get();

                if (inventoryQuery.docs.isNotEmpty) {
                  batch.update(inventoryQuery.docs.first.reference, {
                    'status': 'Delivered',
                    'updated_at': FieldValue.serverTimestamp(),
                  });
                }
              }
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
    required String
    fileType, // 'invoice', 'delivery_order', or 'signed_delivery_order'
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

      // Get current statuses
      final currentInvoiceStatus =
          orderData['invoice_status'] as String? ?? 'Reserved';
      final currentDeliveryStatus =
          orderData['delivery_status'] as String? ?? 'Pending';

      // Prepare update data based on file type
      final updateData = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };

      String newInvoiceStatus = currentInvoiceStatus;
      String newDeliveryStatus = currentDeliveryStatus;

      if (fileType == 'invoice') {
        updateData['invoice_file_id'] = fileId;
        updateData['invoice_uploaded_at'] = FieldValue.serverTimestamp();

        // Update invoice status to Invoiced if currently Reserved
        if (currentInvoiceStatus == 'Reserved') {
          newInvoiceStatus = 'Invoiced';
          updateData['invoice_status'] = newInvoiceStatus;
        }
      } else if (fileType == 'delivery_order') {
        // Handle normal delivery order
        updateData['delivery_file_id'] = fileId;
        updateData['delivery_uploaded_at'] = FieldValue.serverTimestamp();

        // Update delivery status to Issued if invoice is ready and delivery is pending
        if (currentInvoiceStatus == 'Invoiced' &&
            currentDeliveryStatus == 'Pending') {
          newDeliveryStatus = 'Issued';
          updateData['delivery_status'] = newDeliveryStatus;
        }
      } else if (fileType == 'signed_delivery_order') {
        // Handle signed delivery order
        updateData['signed_delivery_file_id'] = fileId;
        updateData['signed_delivery_uploaded_at'] =
            FieldValue.serverTimestamp();

        // Update delivery status to Delivered if currently Issued
        if (currentDeliveryStatus == 'Issued') {
          newDeliveryStatus = 'Delivered';
          updateData['delivery_status'] = newDeliveryStatus;

          // Create new 'Delivered' transaction instead of updating existing ones
          await _createDeliveredTransaction(orderNumber);
        }
      }

      // Update the order
      await orderDoc.reference.update(updateData);

      return {
        'success': true,
        'message': 'Order $orderNumber updated with $fileType file.',
        'new_invoice_status': newInvoiceStatus,
        'new_delivery_status': newDeliveryStatus,
        'file_id': fileId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update order with file: ${e.toString()}',
      };
    }
  }

  /// Update order with file reference and invoice details (for replace operations)
  Future<Map<String, dynamic>> updateOrderWithInvoiceFile({
    required String orderNumber,
    required String fileId,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? remarks,
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
        'invoice_file_id': fileId,
        'invoice_uploaded_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Add invoice details if provided
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        updateData['invoice_number'] = invoiceNumber;
      }
      if (invoiceDate != null) {
        updateData['invoice_date'] = Timestamp.fromDate(invoiceDate);
      }
      if (remarks != null && remarks.isNotEmpty) {
        updateData['invoice_remarks'] = remarks;
      }

      // Update the order
      await orderDoc.reference.update(updateData);

      // Update related transactions with invoice details if provided
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        await _updateTransactionInvoiceDetails(
          orderNumber,
          invoiceNumber,
          invoiceDate,
        );
      }

      return {
        'success': true,
        'message': 'Order $orderNumber updated with invoice file and details.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update order: ${e.toString()}',
      };
    }
  }

  /// Update transaction invoice details
  Future<void> _updateTransactionInvoiceDetails(
    String orderNumber,
    String invoiceNumber,
    DateTime? invoiceDate,
  ) async {
    try {
      // Find the order to get transaction IDs
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) return;

      final orderData = orderQuery.docs.first.data();
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

      // Update transactions with invoice details
      final batch = _firestore.batch();
      for (final transactionId in transactionIds) {
        final transactionQuery = await _firestore
            .collection('transactions')
            .where('transaction_id', isEqualTo: transactionId)
            .get();

        for (final transactionDoc in transactionQuery.docs) {
          final updateData = <String, dynamic>{
            'invoice_number': invoiceNumber,
            'updated_at': FieldValue.serverTimestamp(),
          };

          if (invoiceDate != null) {
            updateData['invoice_date'] = Timestamp.fromDate(invoiceDate);
          }

          batch.update(transactionDoc.reference, updateData);
        }
      }

      if (transactionIds.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      // Log error but don't fail the main operation
      debugPrint('Warning: Failed to update transaction invoice details: $e');
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
        'has_signed_delivery_order':
            orderData['signed_delivery_file_id'] != null,
        'invoice_file_id': orderData['invoice_file_id'],
        'delivery_file_id': orderData['delivery_file_id'],
        'signed_delivery_file_id': orderData['signed_delivery_file_id'],
        'invoice_uploaded_at': orderData['invoice_uploaded_at'],
        'delivery_uploaded_at': orderData['delivery_uploaded_at'],
        'signed_delivery_uploaded_at': orderData['signed_delivery_uploaded_at'],
        'is_complete':
            orderData['invoice_file_id'] != null &&
            (orderData['delivery_file_id'] != null ||
                orderData['signed_delivery_file_id'] != null),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to get order file status: ${e.toString()}',
      };
    }
  }

  /// Helper method to create new 'Delivered' transaction for signed delivery
  Future<void> _createDeliveredTransaction(String orderNumber) async {
    try {
      // Get the order to find transaction IDs and details
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        print(
          'Order $orderNumber not found for delivered transaction creation',
        );
        return;
      }

      final orderData = orderQuery.docs.first.data();
      final transactionIds = List<int>.from(orderData['transaction_ids'] ?? []);

      if (transactionIds.isEmpty) {
        print('No transaction IDs found for order $orderNumber');
        return;
      }

      // Get the first transaction to copy details from
      final firstTransactionQuery = await _firestore
          .collection('transactions')
          .where('transaction_id', isEqualTo: transactionIds.first)
          .get();

      if (firstTransactionQuery.docs.isEmpty) {
        print('First transaction not found for order $orderNumber');
        return;
      }

      final firstTransactionData = firstTransactionQuery.docs.first.data();
      final currentUser = _authService.currentUser;

      // Get next transaction ID
      final nextTransactionId = await getNextTransactionId();

      // Create new 'Delivered' transaction with same details but different status
      final deliveredTransactionData = {
        ...firstTransactionData,
        'transaction_id': nextTransactionId,
        'status': 'Delivered',
        'transaction_type': 'Stock_Out',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'created_by_uid':
            currentUser?.uid ?? firstTransactionData['created_by_uid'],
      };

      // Create the new transaction document
      final deliveredTransactionRef = _firestore
          .collection('transactions')
          .doc();

      await deliveredTransactionRef.set(deliveredTransactionData);

      // Add the new transaction ID to the order's transaction_ids array
      await orderQuery.docs.first.reference.update({
        'transaction_ids': FieldValue.arrayUnion([nextTransactionId]),
        'updated_at': FieldValue.serverTimestamp(),
      });

      print(
        'Created new Delivered transaction ${deliveredTransactionRef.id} for order $orderNumber',
      );
    } catch (e) {
      print('Error creating delivered transaction for order $orderNumber: $e');
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

  /// Delete order and all related data (development only)
  /// This is a comprehensive deletion that:
  /// 1. Deletes order document from orders collection
  /// 2. Deletes related transaction records from transactions collection
  /// 3. Deletes associated files (invoice/delivery PDFs) from Storage and files collection
  /// 4. Does NOT restore inventory quantities (inventory records remain unchanged)
  /// 5. Uses batch operations for data consistency
  /// 6. Advanced safety checks to prevent deletion of delivered orders
  Future<Map<String, dynamic>> deleteOrder(String orderId) async {
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
      final orderStatus = orderData['status'] as String?;
      final transactionIds = orderData['transaction_ids'] as List<dynamic>?;

      if (orderNumber == null) {
        return {'success': false, 'error': 'Order number not found.'};
      }

      // Safety check: Prevent deletion of delivered orders
      if (orderStatus == 'Delivered') {
        return {
          'success': false,
          'error':
              'Cannot delete delivered orders. Only Reserved and Invoiced orders can be deleted.',
        };
      }

      debugPrint(
        '🗑️ Starting deletion of order: $orderNumber (Status: $orderStatus)',
      );

      // Use batch for atomic operations
      final batch = _firestore.batch();
      final deletionSummary = <String, dynamic>{
        'order_deleted': false,
        'transactions_deleted': 0,
        'files_deleted': 0,
        'storage_files_deleted': 0,
      };

      // Step 1: Delete order document
      batch.delete(orderDoc.reference);
      deletionSummary['order_deleted'] = true;
      debugPrint('📄 Marked order document for deletion');

      // Step 2: Delete related transaction records
      if (transactionIds != null && transactionIds.isNotEmpty) {
        final transactionIdsInt = transactionIds.cast<int>();

        for (final transactionId in transactionIdsInt) {
          final transactionQuery = await _firestore
              .collection('transactions')
              .where('transaction_id', isEqualTo: transactionId)
              .get();

          for (final transactionDoc in transactionQuery.docs) {
            final transactionData = transactionDoc.data();
            final serialNumber = transactionData['serial_number'] as String?;

            // Revert inventory status to 'Active' if serial number exists
            if (serialNumber != null) {
              final inventoryQuery = await _firestore
                  .collection('inventory')
                  .where('serial_number', isEqualTo: serialNumber)
                  .limit(1)
                  .get();

              if (inventoryQuery.docs.isNotEmpty) {
                batch.update(inventoryQuery.docs.first.reference, {
                  'status': 'Active',
                });
                debugPrint(
                  '🔄 Marked inventory status for $serialNumber to Active',
                );
              }
            }

            batch.delete(transactionDoc.reference);
            deletionSummary['transactions_deleted']++;
            debugPrint('🔄 Marked transaction $transactionId for deletion');
          }
        }
      }

      // Step 3: Delete ALL associated files (all versions) from files collection and storage
      final allOrderFiles = await _firestore
          .collection('files')
          .where('order_number', isEqualTo: orderNumber)
          .get();

      for (final fileDoc in allOrderFiles.docs) {
        final fileData = fileDoc.data();
        final filePath = fileData['file_path'] as String?;
        final fileType = fileData['file_type'] as String?;

        // Delete file record from files collection
        batch.delete(fileDoc.reference);
        deletionSummary['files_deleted']++;
        debugPrint(
          '📁 Marked file record ${fileDoc.id} ($fileType) for deletion',
        );

        // Delete file from Firebase Storage
        if (filePath != null) {
          try {
            await FirebaseStorage.instance.ref().child(filePath).delete();
            deletionSummary['storage_files_deleted']++;
            debugPrint('🗂️ Deleted file from storage: $filePath');
          } catch (e) {
            // Continue even if storage deletion fails
            debugPrint('⚠️ Warning: Failed to delete file from storage: $e');
          }
        }
      }

      debugPrint(
        '📁 Deleted ${allOrderFiles.docs.length} file versions for order $orderNumber',
      );

      // Commit all changes atomically
      await batch.commit();
      debugPrint('✅ Order deletion completed successfully');

      return {
        'success': true,
        'message': 'Order deleted successfully.',
        'order_number': orderNumber,
        'deletion_summary': deletionSummary,
      };
    } catch (e) {
      debugPrint('❌ Error deleting order: $e');
      return {
        'success': false,
        'error': 'Failed to delete order: ${e.toString()}',
      };
    }
  }

  /// Migrate existing orders from single status to dual status system
  /// This method should be called once during the migration process
  Future<Map<String, dynamic>> migrateOrdersToDualStatus() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get all orders that don't have dual status fields yet
      final ordersQuery = await _firestore
          .collection('orders')
          .where('invoice_status', isNull: true)
          .get();

      if (ordersQuery.docs.isEmpty) {
        return {
          'success': true,
          'message': 'No orders need migration.',
          'migrated_count': 0,
        };
      }

      final batch = _firestore.batch();
      int migratedCount = 0;

      for (final doc in ordersQuery.docs) {
        final data = doc.data();
        final currentStatus = data['status'] as String? ?? 'Reserved';

        // Map single status to dual status
        String invoiceStatus;
        String deliveryStatus;

        switch (currentStatus) {
          case 'Reserved':
            invoiceStatus = 'Reserved';
            deliveryStatus = 'Pending';
            break;
          case 'Invoiced':
            invoiceStatus = 'Invoiced';
            deliveryStatus = 'Pending';
            break;
          case 'Issued':
            invoiceStatus = 'Invoiced';
            deliveryStatus = 'Issued';
            break;
          case 'Delivered':
            invoiceStatus = 'Invoiced';
            deliveryStatus = 'Delivered';
            break;
          default:
            invoiceStatus = 'Reserved';
            deliveryStatus = 'Pending';
        }

        // Update the document with dual status fields
        batch.update(doc.reference, {
          'invoice_status': invoiceStatus,
          'delivery_status': deliveryStatus,
          'updated_at': FieldValue.serverTimestamp(),
        });

        migratedCount++;
      }

      // Commit all updates
      await batch.commit();

      return {
        'success': true,
        'message':
            'Successfully migrated $migratedCount orders to dual status system.',
        'migrated_count': migratedCount,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to migrate orders: ${e.toString()}',
      };
    }
  }

  /// Delete delivery data and revert delivery status to Pending
  /// This method:
  /// 1. Deletes delivery PDF files from Firebase Storage
  /// 2. Deletes file records from 'files' collection
  /// 3. Deletes delivery_orders document
  /// 4. Reverts order delivery status to 'Pending' (or legacy status to 'Invoiced')
  /// 5. Reverts transaction status back to 'Invoiced'
  Future<Map<String, dynamic>> deleteDeliveryData(String orderId) async {
    try {
      final batch = _firestore.batch();
      final deletedFiles = <String>[];
      int filesCollectionDeleted = 0;

      // Get order document
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) {
        return {'success': false, 'error': 'Order not found'};
      }

      final orderData = orderDoc.data()!;
      final orderNumber = orderData['order_number'] as String?;

      if (orderNumber == null) {
        return {'success': false, 'error': 'Order number not found'};
      }

      // Step 1: Delete ALL delivery-related files from 'files' collection and Firebase Storage
      final deliveryFiles = await _firestore
          .collection('files')
          .where('order_number', isEqualTo: orderNumber)
          .where(
            'file_type',
            whereIn: ['delivery_order', 'signed_delivery_order'],
          )
          .get();

      for (final fileDoc in deliveryFiles.docs) {
        final fileData = fileDoc.data();
        final filePath = fileData['file_path'] as String?;
        final fileName = fileData['original_filename'] as String?;

        // Delete file record from files collection
        batch.delete(fileDoc.reference);
        filesCollectionDeleted++;

        // Delete file from Firebase Storage
        if (filePath != null) {
          try {
            await FirebaseStorage.instance.ref().child(filePath).delete();
            deletedFiles.add(fileName ?? filePath);
            debugPrint('🗂️ Deleted delivery file from storage: $filePath');
          } catch (e) {
            debugPrint(
              '⚠️ Warning: Could not delete file from storage $filePath: $e',
            );
          }
        }
      }

      // Step 2: Delete delivery order document (legacy cleanup)
      final deliveryOrderQuery = await _firestore
          .collection('delivery_orders')
          .where('order_id', isEqualTo: orderId)
          .get();

      String? deliveryOrderId;
      if (deliveryOrderQuery.docs.isNotEmpty) {
        deliveryOrderId = deliveryOrderQuery.docs.first.id;
        batch.delete(
          _firestore.collection('delivery_orders').doc(deliveryOrderId),
        );
      }

      // Step 3: Update order status - revert delivery_status to Pending
      final orderUpdateData = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
        // Clear delivery file references
        'delivery_file_id': null,
        'delivery_uploaded_at': null,
        'signed_delivery_file_id': null,
        'signed_delivery_uploaded_at': null,
        // Clear delivery information
        'delivery_number': null,
        'delivery_date': null,
        'delivery_remarks': null,
      };

      // For dual status system
      if (orderData.containsKey('delivery_status')) {
        orderUpdateData['delivery_status'] = 'Pending';
      }

      // For legacy single status system - revert to Invoiced
      if (orderData.containsKey('status') &&
          !orderData.containsKey('delivery_status')) {
        orderUpdateData['status'] = 'Invoiced';
      }

      batch.update(
        _firestore.collection('orders').doc(orderId),
        orderUpdateData,
      );

      // Step 4: Revert transaction status back to 'Invoiced'
      await _updateTransactionStatusForOrder(orderNumber, 'Invoiced');

      // Commit the batch
      await batch.commit();

      debugPrint('✅ Delivery data deletion completed for order $orderNumber');

      return {
        'success': true,
        'deletion_summary': {
          'files_deleted_from_storage': deletedFiles.length,
          'files_deleted_from_collection': filesCollectionDeleted,
          'deleted_files': deletedFiles,
          'delivery_order_removed': deliveryOrderId != null,
          'status_reverted': true,
          'transactions_reverted': true,
        },
      };
    } catch (e) {
      debugPrint('❌ Error deleting delivery data: $e');
      return {'success': false, 'error': 'Failed to delete delivery data: $e'};
    }
  }

  /// Update order number
  /// This updates the order number in the orders collection and all associated files
  Future<Map<String, dynamic>> updateOrderNumber({
    required String oldOrderNumber,
    required String newOrderNumber,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // 1. Check if new order number already exists
      if (newOrderNumber != oldOrderNumber) {
        final existing = await _firestore
            .collection('orders')
            .where('order_number', isEqualTo: newOrderNumber)
            .get();

        if (existing.docs.isNotEmpty) {
          return {
            'success': false,
            'error': 'Order number $newOrderNumber already exists.',
          };
        }
      }

      // 2. Find the order by old order number
      final orderQuery = await _firestore
          .collection('orders')
          .where('order_number', isEqualTo: oldOrderNumber)
          .get();

      if (orderQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Order $oldOrderNumber not found.'};
      }

      final orderDoc = orderQuery.docs.first;
      final batch = _firestore.batch();

      // 3. Update order document
      batch.update(orderDoc.reference, {
        'order_number': newOrderNumber,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 4. Update associated files in 'files' collection
      final filesQuery = await _firestore
          .collection('files')
          .where('order_number', isEqualTo: oldOrderNumber)
          .get();

      for (final fileDoc in filesQuery.docs) {
        batch.update(fileDoc.reference, {
          'order_number': newOrderNumber,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      return {
        'success': true,
        'message':
            'Order number updated from $oldOrderNumber to $newOrderNumber',
        'files_updated': filesQuery.docs.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update order number: ${e.toString()}',
      };
    }
  }
}
