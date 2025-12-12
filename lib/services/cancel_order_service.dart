import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class CancelOrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  CancelOrderService({required AuthService authService})
    : _authService = authService;

  /// Get all cancellable orders (admin only)
  /// Returns orders that can be cancelled (not delivered or already cancelled)
  Future<List<Map<String, dynamic>>> getCancellableOrders() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Check if user is admin
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userDoc.data();
      final userRole = userData?['role'] ?? 'user';

      if (userRole != 'admin') {
        throw Exception('Access denied. Admin privileges required.');
      }

      // Get orders that are not delivered or cancelled
      final ordersQuery = await _firestore
          .collection('orders')
          .where('delivery_status', whereNotIn: ['Delivered'])
          .orderBy('created_date', descending: true)
          .get();

      List<Map<String, dynamic>> cancellableOrders = [];

      for (final doc in ordersQuery.docs) {
        final data = doc.data();

        // Skip if already cancelled
        if (data['order_status'] == 'Cancelled') {
          continue;
        }

        cancellableOrders.add({
          'id': doc.id,
          'order_number': data['order_number'],
          'customer_dealer': data['customer_dealer'],
          'customer_client': data['customer_client'],
          'invoice_status': data['invoice_status'],
          'delivery_status': data['delivery_status'],
          'total_items': data['total_items'],
          'created_date': data['created_date'],
          'transaction_ids': data['transaction_ids'],
        });
      }

      return cancellableOrders;
    } catch (e) {
      debugPrint('Error getting cancellable orders: $e');
      throw Exception('Failed to get cancellable orders: $e');
    }
  }

  /// Get detailed order information for cancellation review
  Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    try {
      // Get order document
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();

      if (!orderDoc.exists) {
        throw Exception('Order not found');
      }

      final orderData = orderDoc.data()!;
      final transactionIds = List<int>.from(orderData['transaction_ids'] ?? []);

      // Get transaction details for order items
      List<Map<String, dynamic>> items = [];

      if (transactionIds.isNotEmpty) {
        // Process in batches of 10 (Firestore whereIn limit)
        for (int i = 0; i < transactionIds.length; i += 10) {
          final batch = transactionIds.skip(i).take(10).toList();

          final transactionQuery = await _firestore
              .collection('transactions')
              .where('transaction_id', whereIn: batch)
              .get();

          for (final doc in transactionQuery.docs) {
            final data = doc.data();
            items.add({
              'transaction_id': data['transaction_id'],
              'serial_number': data['serial_number'] ?? 'N/A',
              'category':
                  data['equipment_category'] ?? data['category'] ?? 'N/A',
              'model': data['model'] ?? 'N/A',
              'size': data['size'] ?? 'N/A',
              'status': data['status'] ?? 'N/A',
              'warranty_type': data['warranty_type'] ?? 'N/A',
              'warranty_period': data['warranty_period'] ?? 'N/A',
            });
          }
        }
      }

      // Sort items by serial number
      items.sort(
        (a, b) =>
            (a['serial_number'] ?? '').compareTo(b['serial_number'] ?? ''),
      );

      return {
        'order': {'id': orderId, ...orderData},
        'items': items,
      };
    } catch (e) {
      debugPrint('Error getting order details: $e');
      throw Exception('Failed to get order details: $e');
    }
  }

  /// Get next available transaction ID
  Future<int> _getNextTransactionId() async {
    try {
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
        return 1;
      }
    } catch (e) {
      return 1;
    }
  }

  /// Get multiple sequential transaction IDs
  Future<List<int>> _getNextTransactionIds(int count) async {
    final startId = await _getNextTransactionId();
    return List.generate(count, (index) => startId + index);
  }

  /// Cancel an order with reason (admin only)
  /// Creates cancellation transactions and updates order status
  Future<Map<String, dynamic>> cancelOrder({
    required String orderId,
    required String orderNumber,
    required String cancellationReason,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated'};
      }

      // Check if user is admin
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userDoc.data();
      final userRole = userData?['role'] ?? 'user';

      if (userRole != 'admin') {
        return {
          'success': false,
          'error': 'Access denied. Admin privileges required.',
        };
      }

      // Get order details
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) {
        return {'success': false, 'error': 'Order not found'};
      }

      final orderData = orderDoc.data()!;

      // Check if order is already cancelled
      if (orderData['order_status'] == 'Cancelled') {
        return {'success': false, 'error': 'Order is already cancelled'};
      }

      // Check if order is delivered (cannot cancel delivered orders)
      if (orderData['delivery_status'] == 'Delivered') {
        return {'success': false, 'error': 'Cannot cancel delivered orders'};
      }

      final transactionIds = List<int>.from(orderData['transaction_ids'] ?? []);

      if (transactionIds.isEmpty) {
        return {
          'success': false,
          'error': 'No transaction IDs found for this order',
        };
      }

      // Get next transaction IDs for cancellation records
      final cancellationTransactionIds = await _getNextTransactionIds(
        transactionIds.length,
      );

      final batch = _firestore.batch();
      final timestamp = Timestamp.fromDate(DateTime.now());

      // Create cancellation transactions for each original transaction
      for (int i = 0; i < transactionIds.length; i++) {
        final originalTransactionId = transactionIds[i];
        final cancellationTransactionId = cancellationTransactionIds[i];

        // Get original transaction details
        final originalTransactionQuery = await _firestore
            .collection('transactions')
            .where('transaction_id', isEqualTo: originalTransactionId)
            .get();

        if (originalTransactionQuery.docs.isNotEmpty) {
          final originalData = originalTransactionQuery.docs.first.data();

          // Create cancellation transaction
          final cancellationData = {
            'transaction_id': cancellationTransactionId,
            'serial_number': originalData['serial_number'],
            'type': 'Cancellation',
            'status': 'Active', // Items become active again
            'original_transaction_id': originalTransactionId,
            'cancelled_from_order': orderNumber,
            'cancellation_reason': cancellationReason,
            'location': originalData['location'],
            'customer_dealer': originalData['customer_dealer'],
            'customer_client': originalData['customer_client'],
            'equipment_category':
                originalData['equipment_category'] ?? originalData['category'],
            'model': originalData['model'],
            'size': originalData['size'],
            'warranty_type': originalData['warranty_type'],
            'warranty_period': originalData['warranty_period'],
            'date': timestamp,
            'uploaded_at': FieldValue.serverTimestamp(),
            'source': 'order_cancellation',
            'uploaded_by_uid': currentUser.uid,
            'cancelled_by_uid': currentUser.uid,
            'cancelled_at': FieldValue.serverTimestamp(),
          };

          final cancellationRef = _firestore.collection('transactions').doc();
          batch.set(cancellationRef, cancellationData);

          // Inventory Status Sync: Update inventory item status back to 'Active'
          final inventoryQuery = await _firestore
              .collection('inventory')
              .where('serial_number', isEqualTo: originalData['serial_number'])
              .limit(1)
              .get();

          if (inventoryQuery.docs.isNotEmpty) {
            batch.update(inventoryQuery.docs.first.reference, {
              'status': 'Active',
            });
          }
        }
      }

      // Update order document with cancellation information
      final orderUpdateData = {
        'order_status': 'Cancelled',
        'cancellation_reason': cancellationReason,
        'cancelled_by_uid': currentUser.uid,
        'cancelled_at': FieldValue.serverTimestamp(),
        'original_invoice_status': orderData['invoice_status'],
        'original_delivery_status': orderData['delivery_status'],
        'updated_at': FieldValue.serverTimestamp(),
        'cancellation_transaction_ids': cancellationTransactionIds,
      };

      batch.update(
        _firestore.collection('orders').doc(orderId),
        orderUpdateData,
      );

      // Commit all operations
      await batch.commit();

      return {
        'success': true,
        'message': 'Order $orderNumber cancelled successfully',
        'cancelled_items': transactionIds.length,
        'cancellation_transaction_ids': cancellationTransactionIds,
      };
    } catch (e) {
      debugPrint('Error cancelling order: $e');
      return {'success': false, 'error': 'Failed to cancel order: $e'};
    }
  }
}
