import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class InventoryManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  /// Get inventory items with advanced filtering and pagination
  Future<Map<String, dynamic>> getInventoryItems({
    String? searchQuery,
    String? categoryFilter,
    String? statusFilter,
    String? locationFilter,
    String? sizeFilter,
    int limit = 20,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      // Start with base query
      Query query = _firestore.collection('inventory');

      // Apply category filter
      if (categoryFilter != null && categoryFilter.isNotEmpty) {
        query = query.where('equipment_category', isEqualTo: categoryFilter);
      }

      // Apply size filter
      if (sizeFilter != null && sizeFilter.isNotEmpty) {
        query = query.where('size', isEqualTo: sizeFilter);
      }

      // Order by date for consistent pagination
      query = query.orderBy('date', descending: true);

      // Apply pagination
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      // Increase limit when using search or status filters to ensure we fetch enough items
      int effectiveLimit = limit;
      if ((searchQuery != null && searchQuery.isNotEmpty) ||
          (statusFilter != null && statusFilter.isNotEmpty) ||
          (locationFilter != null && locationFilter.isNotEmpty)) {
        effectiveLimit =
            1000; // Fetch more items when post-processing filters are used
      }

      query = query.limit(effectiveLimit);

      // Execute query
      final snapshot = await query.get();

      // Get all transactions for status calculation
      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      // Process items with current status
      final processedItems = await _processInventoryItems(
        snapshot.docs,
        transactionSnapshot.docs,
        searchQuery: searchQuery,
        statusFilter: statusFilter,
        locationFilter: locationFilter,
      );

      return {
        'success': true,
        'items': processedItems['items'],
        'hasMore': snapshot.docs.length == limit,
        'lastDocument': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        'totalFiltered': processedItems['totalFiltered'],
      };
    } catch (e) {
      print('Error getting inventory items: $e');
      return {
        'success': false,
        'error': e.toString(),
        'items': <Map<String, dynamic>>[],
        'hasMore': false,
        'lastDocument': null,
        'totalFiltered': 0,
      };
    }
  }

  /// Process inventory items with current status and apply additional filters
  Future<Map<String, dynamic>> _processInventoryItems(
    List<QueryDocumentSnapshot> inventoryDocs,
    List<QueryDocumentSnapshot> transactionDocs, {
    String? searchQuery,
    String? statusFilter,
    String? locationFilter,
  }) async {
    final items = <Map<String, dynamic>>[];
    int totalFiltered = 0;

    // Create transaction lookup map for performance (case-insensitive)
    final Map<String, List<Map<String, dynamic>>> transactionsBySerial = {};
    for (final doc in transactionDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String?;
      if (serialNumber != null) {
        final normalizedSerial = serialNumber.toLowerCase();
        transactionsBySerial.putIfAbsent(normalizedSerial, () => []);
        transactionsBySerial[normalizedSerial]!.add({...data, 'id': doc.id});
      }
    }

    for (final doc in inventoryDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String? ?? '';

      // Use stored status from inventory document as primary source of truth
      final statusInfo = await _determineItemStatus(
        data,
        transactionsBySerial[serialNumber.toLowerCase()] ?? [],
      );

      final item = {
        'id': doc.id,
        'serial_number': serialNumber,
        'equipment_category': data['equipment_category'] ?? 'Unknown',
        'model': data['model'] ?? 'Unknown',
        'size': data['size'] ?? '',
        'batch': data['batch'] ?? '',
        'remark': data['remark'] ?? '',
        'date': data['date'],
        'current_status': statusInfo['status'],
        'current_location': statusInfo['location'],
        'last_activity': statusInfo['lastActivity'],
        'transaction_count':
            (transactionsBySerial[serialNumber.toLowerCase()] ?? []).length,
      };

      // Apply search filter
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final searchableText = [
          item['serial_number'] ?? '',
          item['equipment_category'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['batch'] ?? '',
          item['remark'] ?? '',
          item['current_location'] ?? '',
        ].where((text) => text.isNotEmpty).join(' ').toLowerCase();

        if (!searchableText.contains(query)) {
          continue; // Skip this item
        }
      }

      // Apply status filter
      if (statusFilter != null && statusFilter.isNotEmpty) {
        if (item['current_status'] != statusFilter) {
          continue; // Skip this item
        }
      }

      // Apply location filter
      if (locationFilter != null && locationFilter.isNotEmpty) {
        if (item['current_location'] != locationFilter) {
          continue; // Skip this item
        }
      }

      items.add(item);
      totalFiltered++;
    }

    return {'items': items, 'totalFiltered': totalFiltered};
  }

  /// Determine item status using stored data as primary source
  /// Queries orders collection to check invoice_status and delivery_status
  Future<Map<String, dynamic>> _determineItemStatus(
    Map<String, dynamic> inventoryData,
    List<Map<String, dynamic>> transactions,
  ) async {
    String? location =
        inventoryData['location'] ?? inventoryData['current_location'];

    // Get last activity from transactions
    DateTime? lastActivity;
    String? status;

    if (transactions.isNotEmpty) {
      // Sort transactions by date (most recent first) to find last activity
      transactions.sort((a, b) {
        final aTime = a['date'];
        final bTime = b['date'];
        DateTime aDate = (aTime is Timestamp)
            ? aTime.toDate()
            : DateTime.tryParse(aTime.toString()) ?? DateTime.now();
        DateTime bDate = (bTime is Timestamp)
            ? bTime.toDate()
            : DateTime.tryParse(bTime.toString()) ?? DateTime.now();
        return bDate.compareTo(aDate);
      });

      final latestTransaction = transactions.first;
      final dateValue = latestTransaction['date'];
      if (dateValue is Timestamp) {
        lastActivity = dateValue.toDate();
      } else if (dateValue is String) {
        lastActivity = DateTime.tryParse(dateValue);
      }

      final type = latestTransaction['type'] as String?;
      final transactionStatus = latestTransaction['status'] as String?;
      final transactionId = latestTransaction['transaction_id'] as int?;
      location ??= latestTransaction['location'] as String? ?? 'Unknown';

      // For Stock_Out, ALWAYS check orders for current invoice/delivery status
      if (type == 'Stock_Out' && transactionId != null) {
        // Query orders to get invoice_status and delivery_status
        final ordersQuery = await _firestore
            .collection('orders')
            .where('transaction_ids', arrayContains: transactionId)
            .limit(1)
            .get();

        if (ordersQuery.docs.isNotEmpty) {
          final orderData = ordersQuery.docs.first.data();
          final invoiceStatus = orderData['invoice_status'] as String?;
          final deliveryStatus = orderData['delivery_status'] as String?;

          // Determine status based on order statuses (priority order)
          if (deliveryStatus == 'Delivered') {
            status = 'Delivered';
          } else if (deliveryStatus == 'Issued') {
            status = 'Issued';
          } else if (invoiceStatus == 'Invoiced') {
            status = 'Invoiced';
          } else if (transactionStatus == 'Reserved') {
            status = 'Reserved';
          } else {
            status = 'Reserved'; // Default for Stock_Out
          }
        } else {
          // No order found, use transaction status
          status = transactionStatus ?? 'Reserved';
        }
      } else if (type == 'Stock_In') {
        status = 'Active';
      } else if (type == 'Demo') {
        status = 'Demo';
      } else if (type == 'Cancellation') {
        status = 'Active';
      } else if (type == 'Returned') {
        status = 'Returned';
      } else {
        status = 'Active';
      }
    }

    // Fallback to stored status if no transactions
    status ??=
        inventoryData['status'] ?? inventoryData['current_status'] ?? 'Active';

    return {
      'status': status,
      'location': location ?? 'HQ',
      'lastActivity': lastActivity,
    };
  }

  /// Get filter options for dropdowns
  Future<Map<String, dynamic>> getFilterOptions() async {
    try {
      // Get categories and sizes from inventory
      final inventorySnapshot = await _firestore.collection('inventory').get();

      final categories = <String>{};
      final sizes = <String>{};

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final category = data['equipment_category'] as String?;
        final size = data['size'] as String?;

        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
        if (size != null && size.isNotEmpty) {
          sizes.add(size);
        }
      }

      // Get current locations by calculating them from transactions
      // This ensures filter options match what users actually see
      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      // Calculate current locations for all items
      final Map<String, List<Map<String, dynamic>>> transactionsBySerial = {};
      for (final doc in transactionSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null) {
          final normalizedSerial = serialNumber.toLowerCase();
          transactionsBySerial.putIfAbsent(normalizedSerial, () => []);
          transactionsBySerial[normalizedSerial]!.add({...data, 'id': doc.id});
        }
      }

      final currentLocations = <String>{};
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String? ?? '';

        // Calculate current location for this item (case-insensitive)
        final statusInfo = await _determineItemStatus(
          data,
          transactionsBySerial[serialNumber.toLowerCase()] ?? [],
        );

        final location = statusInfo['location'] as String?;
        if (location != null && location.isNotEmpty) {
          currentLocations.add(location);
        }
      }

      return {
        'success': true,
        'categories': categories.toList()..sort(),
        'sizes': sizes.toList()..sort(),
        'locations': currentLocations.toList()..sort(),
        'statuses': ['Active', 'Reserved', 'Delivered'],
      };
    } catch (e) {
      print('Error getting filter options: $e');
      return {
        'success': false,
        'error': e.toString(),
        'categories': <String>[],
        'sizes': <String>[],
        'locations': <String>[],
        'statuses': <String>[],
      };
    }
  }

  /// Get inventory summary statistics
  /// Enhanced to include Reserved status tracking
  Future<Map<String, dynamic>> getInventorySummary() async {
    try {
      final inventorySnapshot = await _firestore.collection('inventory').get();
      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      // Create transaction lookup map
      final Map<String, List<Map<String, dynamic>>> transactionsBySerial = {};
      for (final doc in transactionSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null) {
          final normalizedSerial = serialNumber.toLowerCase();
          transactionsBySerial.putIfAbsent(normalizedSerial, () => []);
          transactionsBySerial[normalizedSerial]!.add(data);
        }
      }

      int totalItems = 0;
      int activeItems = 0;
      int reservedItems = 0;
      int deliveredItems = 0;

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String? ?? '';

        final statusInfo = await _determineItemStatus(
          data,
          transactionsBySerial[serialNumber.toLowerCase()] ?? [],
        );

        totalItems++;
        switch (statusInfo['status']) {
          case 'Active':
            activeItems++;
            break;
          case 'Reserved':
            reservedItems++;
            break;
          case 'Delivered':
            deliveredItems++;
            break;
        }
      }

      return {
        'success': true,
        'total_items': totalItems,
        'active_items': activeItems,
        'reserved_items': reservedItems,
        'delivered_items': deliveredItems,
      };
    } catch (e) {
      print('Error getting inventory summary: $e');
      return {
        'success': false,
        'error': e.toString(),
        'total_items': 0,
        'active_items': 0,
        'reserved_items': 0,
        'delivered_items': 0,
      };
    }
  }

  /// Update an inventory item and its related Stock_In transaction
  /// This method updates both inventory and transaction records to maintain data consistency
  Future<Map<String, dynamic>> updateInventoryItem(
    String documentId,
    Map<String, dynamic> updatedData,
    Map<String, dynamic> originalData,
  ) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get the serial number to find the related transaction
      final serialNumber = updatedData['serial_number'] as String?;
      if (serialNumber == null) {
        return {'success': false, 'error': 'Serial number is required.'};
      }

      // Prepare updated inventory data with metadata
      final inventoryUpdateData = {
        ...updatedData,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by_uid': currentUser.uid,
      };

      // Prepare transaction update data (note: transactions use 'remarks' not 'remark')
      final transactionUpdateData = {
        'serial_number': updatedData['serial_number'],
        'equipment_category': updatedData['equipment_category'],
        'model': updatedData['model'],
        'size': updatedData['size'],
        'batch': updatedData['batch'],
        'remarks':
            updatedData['remark'], // Note: transactions use 'remarks' field
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by_uid': currentUser.uid,
      };

      // Use a batch to update both collections atomically
      final batch = _firestore.batch();

      // Update inventory record
      final inventoryRef = _firestore.collection('inventory').doc(documentId);
      batch.update(inventoryRef, inventoryUpdateData);

      // Find and update the related Stock_In transaction
      final transactionQuery = await _firestore
          .collection('transactions')
          .where('serial_number', isEqualTo: serialNumber)
          .where('type', isEqualTo: 'Stock_In')
          .limit(1)
          .get();

      if (transactionQuery.docs.isNotEmpty) {
        final transactionRef = transactionQuery.docs.first.reference;
        batch.update(transactionRef, transactionUpdateData);
      }

      // Commit the batch
      await batch.commit();

      return {
        'success': true,
        'message': 'Item updated successfully',
        'transaction_id': documentId,
      };
    } catch (e) {
      print('Error updating inventory item: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Delete an inventory item and its related transactions
  Future<Map<String, dynamic>> deleteInventoryItem(
    String documentId,
    String serialNumber,
  ) async {
    try {
      // Start a batch operation
      final batch = _firestore.batch();

      // Delete the inventory item
      batch.delete(_firestore.collection('inventory').doc(documentId));

      // Delete all related transactions
      final transactionsSnapshot = await _firestore
          .collection('transactions')
          .where('serial_number', isEqualTo: serialNumber)
          .get();

      for (final doc in transactionsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Commit the batch
      await batch.commit();

      return {
        'success': true,
        'message': 'Item and related transactions deleted successfully',
      };
    } catch (e) {
      print('Error deleting inventory item: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get inventory item details by document ID
  Future<Map<String, dynamic>> getInventoryItemById(String documentId) async {
    try {
      final doc = await _firestore
          .collection('inventory')
          .doc(documentId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return {'success': true, 'item': data};
      } else {
        return {'success': false, 'error': 'Item not found'};
      }
    } catch (e) {
      print('Error getting inventory item: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get complete activity history for an item by serial number
  /// Shows all transactions chronologically with customer details
  /// Uses case-insensitive matching for serial numbers
  Future<Map<String, dynamic>> getItemActivityHistory(
    String serialNumber,
  ) async {
    try {
      // Fetch all transactions and filter in-memory for case-insensitive match
      // This approach is necessary because Firestore where clause is case-sensitive
      final transactionsQuery = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      if (transactionsQuery.docs.isEmpty) {
        return {
          'success': true,
          'activities': <Map<String, dynamic>>[],
          'serial_number': serialNumber,
          'message': 'No activity history found',
        };
      }

      // Normalize serial number for case-insensitive comparison
      final normalizedSerial = serialNumber.toLowerCase();

      // Filter transactions by serial number (case-insensitive)
      final matchingDocs = transactionsQuery.docs.where((doc) {
        final data = doc.data();
        final docSerial = data['serial_number'] as String?;
        return docSerial != null && docSerial.toLowerCase() == normalizedSerial;
      }).toList();

      if (matchingDocs.isEmpty) {
        return {
          'success': true,
          'activities': <Map<String, dynamic>>[],
          'serial_number': serialNumber,
          'message': 'No activity history found',
        };
      }

      final activities = <Map<String, dynamic>>[];

      for (final doc in matchingDocs) {
        final data = doc.data();

        final type = data['type'] as String? ?? 'Unknown';
        final status = data['status'] as String? ?? 'Unknown';
        final dateValue = data['date'];
        final customerDealer = data['customer_dealer'] as String? ?? '';
        final customerClient = data['customer_client'] as String? ?? '';
        final location = data['location'] as String? ?? '';
        final invoiceNumber = data['invoice_number'] as String? ?? '';
        final demoNumber = data['demo_number'] as String? ?? '';
        final remarks = data['remarks'] as String? ?? '';
        final uploadedByUid = data['uploaded_by_uid'] as String? ?? '';

        // Parse date
        DateTime? activityDate;
        if (dateValue is Timestamp) {
          activityDate = dateValue.toDate();
        } else if (dateValue is String) {
          activityDate = DateTime.tryParse(dateValue);
        }

        // Determine who has the item (customer info)
        String customerInfo = '';
        if (customerDealer.isNotEmpty) {
          customerInfo = customerClient.isNotEmpty
              ? '$customerDealer → $customerClient'
              : customerDealer;
        }

        // Build activity description
        String activityDescription = '';
        if (type == 'Stock_In') {
          activityDescription = 'Item received into inventory';
          if (location.isNotEmpty) {
            activityDescription += ' at $location';
          }
        } else if (type == 'Stock_Out') {
          if (status == 'Reserved') {
            activityDescription = 'Order reserved';
          } else if (status == 'Invoiced' || status == 'Issued') {
            activityDescription = 'Invoice generated';
          } else if (status == 'Delivered') {
            activityDescription = 'Delivered to customer';
          } else {
            activityDescription = 'Item ordered';
          }
          if (customerInfo.isNotEmpty) {
            activityDescription += ' for $customerInfo';
          }
        } else if (type == 'Demo') {
          if (status == 'Demo') {
            activityDescription = 'Sent out for demo';
          } else if (status == 'Returned') {
            activityDescription = 'Demo returned';
          } else {
            activityDescription = 'Demo activity';
          }
          if (customerInfo.isNotEmpty) {
            activityDescription += ' to $customerInfo';
          }
        } else if (type == 'Returned') {
          activityDescription = 'Item returned from customer';
          if (customerInfo.isNotEmpty) {
            activityDescription += ' ($customerInfo)';
          }
        } else if (type == 'Cancellation') {
          activityDescription = 'Order cancelled';
          if (customerInfo.isNotEmpty) {
            activityDescription += ' for $customerInfo';
          }
        } else {
          activityDescription = '$type - $status';
        }

        activities.add({
          'id': doc.id,
          'type': type,
          'status': status,
          'date': activityDate,
          'customer_dealer': customerDealer,
          'customer_client': customerClient,
          'customer_info': customerInfo,
          'location': location,
          'invoice_number': invoiceNumber,
          'demo_number': demoNumber,
          'remarks': remarks,
          'description': activityDescription,
          'uploaded_by_uid': uploadedByUid,
        });
      }

      return {
        'success': true,
        'activities': activities,
        'serial_number': serialNumber,
        'total_activities': activities.length,
      };
    } catch (e) {
      print('Error getting item activity history: $e');
      return {
        'success': false,
        'error': e.toString(),
        'activities': <Map<String, dynamic>>[],
      };
    }
  }
}
