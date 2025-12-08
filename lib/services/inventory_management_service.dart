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
      final statusInfo = _determineItemStatus(
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
  Map<String, dynamic> _determineItemStatus(
    Map<String, dynamic> inventoryData,
    List<Map<String, dynamic>> transactions,
  ) {
    // 1. Try to get status from inventory document first (Primary)
    String? status = inventoryData['status'] ?? inventoryData['current_status'];
    String? location =
        inventoryData['location'] ?? inventoryData['current_location'];

    // 2. Get last activity from transactions
    DateTime? lastActivity;
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

      // Fallback: if status is missing in inventory, calculate from latest transaction
      if (status == null || status == 'Unknown') {
        final type = latestTransaction['type'] as String?;
        final transactionStatus = latestTransaction['status'] as String?;
        location ??= latestTransaction['location'] as String? ?? 'Unknown';

        if (type == 'Stock_Out') {
          status = (transactionStatus == 'Delivered')
              ? 'Delivered'
              : 'Reserved';
        } else if (type == 'Stock_In') {
          status = 'Active';
        } else if (type == 'Demo') {
          status = 'Demo'; // Correctly map Demo type to Demo status
        } else if (type == 'Cancellation') {
          status = 'Active';
        } else if (type == 'Returned') {
          status = 'Returned';
        } else {
          status = 'Active';
        }
      }
    }

    return {
      'status': status ?? 'Active',
      'location': location ?? 'HQ', // Default location
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
        // Calculate current location for this item (case-insensitive)
        final statusInfo = _determineItemStatus(
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

        final statusInfo = _determineItemStatus(
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
}
