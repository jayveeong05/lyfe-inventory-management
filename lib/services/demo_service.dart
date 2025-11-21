import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class DemoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  DemoService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Create a multi-item demo record
  /// This creates multiple transaction records (status: Demo) and a single demo record
  Future<Map<String, dynamic>> createDemo({
    required String demoNumber,
    required String demoPurpose,
    required String dealerName,
    required String clientName,
    required String location,
    required List<Map<String, dynamic>> selectedItems,
    DateTime? expectedReturnDate,
    String? remarks,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      if (selectedItems.isEmpty) {
        return {'success': false, 'error': 'No items selected for the demo.'};
      }

      // Handle optional client name - use default if empty
      final effectiveClientName = clientName.trim().isEmpty
          ? 'N/A'
          : clientName.trim();

      final currentDate = DateTime.now();
      final timestamp = Timestamp.fromDate(currentDate);
      final expectedReturnTimestamp = expectedReturnDate != null
          ? Timestamp.fromDate(expectedReturnDate)
          : null;

      // Check if demo number already exists
      final existingDemo = await _firestore
          .collection('demos')
          .where('demo_number', isEqualTo: demoNumber)
          .get();

      if (existingDemo.docs.isNotEmpty) {
        return {
          'success': false,
          'error': 'Demo number $demoNumber already exists.',
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
                'Item with serial number $serialNumber is not available or already in use.',
          };
        }

        // Create Demo transaction record
        final transactionData = {
          'transaction_id': transactionId,
          'serial_number': serialNumber,
          'type': 'Demo',
          'status': 'Demo', // Status is Demo
          'location': location,
          'customer_dealer': dealerName,
          'customer_client': effectiveClientName,
          'date': timestamp,
          'uploaded_at': FieldValue.serverTimestamp(),
          'source': 'demo_manual',
          'uploaded_by_uid': currentUser.uid,
          'demo_purpose': demoPurpose,
          'expected_return_date': expectedReturnTimestamp,
          'remarks': remarks ?? '',
        };

        // Add transaction to batch
        final transactionRef = _firestore.collection('transactions').doc();
        batch.set(transactionRef, transactionData);
      }

      // Prepare demo data
      final demoData = {
        'demo_number': demoNumber,
        'demo_purpose': demoPurpose,
        'status': 'Active', // Active | Returned
        'created_date': timestamp,
        'expected_return_date': expectedReturnTimestamp,
        'actual_return_date': null, // Will be set when items are returned
        'customer_dealer': dealerName,
        'customer_client': effectiveClientName,
        'location': location,
        'transaction_ids': transactionIds, // Store transaction IDs
        'total_items': selectedItems.length,
        'created_by_uid': currentUser.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'remarks': remarks ?? '',
      };

      // Add demo to batch
      final demoRef = _firestore.collection('demos').doc();
      batch.set(demoRef, demoData);

      // Commit all operations
      await batch.commit();

      return {
        'success': true,
        'message': 'Demo created successfully.',
        'demo_id': demoRef.id,
        'demo_number': demoNumber,
        'transaction_ids': transactionIds,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create demo: ${e.toString()}',
      };
    }
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
      debugPrint('Error getting next transaction ID: $e');
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
      debugPrint('Error getting next entry number: $e');
      return 1; // Default to 1 if there's an error
    }
  }

  /// Return demo items back to active status
  Future<Map<String, dynamic>> returnDemoItems({
    required String demoId,
    required String demoNumber,
    DateTime? actualReturnDate,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get the demo record
      final demoDoc = await _firestore.collection('demos').doc(demoId).get();

      if (!demoDoc.exists) {
        return {'success': false, 'error': 'Demo record not found.'};
      }

      final demoData = demoDoc.data()!;
      final transactionIds = List<int>.from(demoData['transaction_ids'] ?? []);

      if (transactionIds.isEmpty) {
        return {
          'success': false,
          'error': 'No transaction IDs found for this demo.',
        };
      }

      // Get all demo transactions
      final demoTransactions = await _firestore
          .collection('transactions')
          .where('transaction_id', whereIn: transactionIds)
          .where('type', isEqualTo: 'Demo')
          .where('status', isEqualTo: 'Demo')
          .get();

      if (demoTransactions.docs.isEmpty) {
        return {
          'success': false,
          'error': 'No active demo transactions found.',
        };
      }

      final batch = _firestore.batch();
      final currentDate = DateTime.now();
      final returnDate = actualReturnDate ?? currentDate;
      final timestamp = Timestamp.fromDate(returnDate);

      // Create return transactions for each demo item
      for (final demoDoc in demoTransactions.docs) {
        final demoTransaction = demoDoc.data();
        final serialNumber = demoTransaction['serial_number'] as String;

        // Get next transaction ID for the return transaction
        final nextTransactionId = await getNextTransactionId();

        // Create Stock_In return transaction
        final returnTransactionData = {
          'transaction_id': nextTransactionId,
          'serial_number': serialNumber,
          'type': 'Stock_In',
          'status': 'Active', // Return to active status
          'location': demoTransaction['location'],
          'customer_dealer': 'Demo Return',
          'customer_client': 'N/A',
          'date': timestamp,
          'uploaded_at': FieldValue.serverTimestamp(),
          'source': 'demo_return',
          'uploaded_by_uid': currentUser.uid,
          'returned_from_demo': demoNumber,
          'original_demo_transaction_id': demoTransaction['transaction_id'],
        };

        // Add return transaction to batch
        final returnTransactionRef = _firestore
            .collection('transactions')
            .doc();
        batch.set(returnTransactionRef, returnTransactionData);
      }

      // Update demo record status
      final demoRef = _firestore.collection('demos').doc(demoId);
      batch.update(demoRef, {
        'status': 'Returned',
        'actual_return_date': timestamp,
        'updated_at': FieldValue.serverTimestamp(),
        'returned_by_uid': currentUser.uid,
      });

      // Commit all operations
      await batch.commit();

      return {
        'success': true,
        'message': 'Demo items returned successfully.',
        'demo_number': demoNumber,
        'returned_items': demoTransactions.docs.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to return demo items: ${e.toString()}',
      };
    }
  }

  /// Get demo history/records
  Future<List<Map<String, dynamic>>> getDemoHistory({
    int limit = 50,
    String? status,
  }) async {
    try {
      Query query = _firestore
          .collection('demos')
          .orderBy('created_date', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      final querySnapshot = await query.limit(limit).get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error getting demo history: $e');
      return [];
    }
  }

  /// Get recent demos for development/admin purposes
  Future<List<Map<String, dynamic>>> getRecentDemosForDeletion({
    int limit = 10,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('demos')
          .orderBy('created_date', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error getting recent demos: $e');
      return [];
    }
  }

  /// Get active demo items count
  Future<int> getActiveDemoItemsCount() async {
    try {
      final querySnapshot = await _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Demo')
          .where('status', isEqualTo: 'Demo')
          .get();

      return querySnapshot.docs.length;
    } catch (e) {
      debugPrint('Error getting active demo items count: $e');
      return 0;
    }
  }

  /// Get demo items for a specific demo
  Future<List<Map<String, dynamic>>> getDemoItems(String demoId) async {
    try {
      // Get demo record to find transaction IDs
      final demoDoc = await _firestore.collection('demos').doc(demoId).get();

      if (!demoDoc.exists) {
        throw Exception('Demo not found');
      }

      final demoData = demoDoc.data()!;
      final transactionIds = List<int>.from(demoData['transaction_ids'] ?? []);

      if (transactionIds.isEmpty) {
        return [];
      }

      // Get transaction details for each demo item
      List<Map<String, dynamic>> items = [];

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
            'transaction_id': doc.id,
            'serial_number': data['serial_number'],
            'category': data['category'],
            'model': data['model'],
            'size': data['size'],
            'status': data['status'],
            'created_date': data['created_date'],
          });
        }
      }

      // Sort by serial number for consistent display
      items.sort(
        (a, b) =>
            (a['serial_number'] ?? '').compareTo(b['serial_number'] ?? ''),
      );

      return items;
    } catch (e) {
      throw Exception('Failed to get demo items: $e');
    }
  }

  /// Get demo statistics
  Future<Map<String, dynamic>> getDemoStatistics() async {
    try {
      // Get all demo records
      final allDemos = await _firestore.collection('demos').get();

      // Get active demo transactions
      final activeDemoTransactions = await _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Demo')
          .where('status', isEqualTo: 'Demo')
          .get();

      final totalDemos = allDemos.docs.length;
      final activeDemos = allDemos.docs
          .where((doc) => doc.data()['status'] == 'Active')
          .length;
      final returnedDemos = allDemos.docs
          .where((doc) => doc.data()['status'] == 'Returned')
          .length;
      final activeDemoItems = activeDemoTransactions.docs.length;

      return {
        'total_demos': totalDemos,
        'active_demos': activeDemos,
        'returned_demos': returnedDemos,
        'active_demo_items': activeDemoItems,
      };
    } catch (e) {
      debugPrint('Error getting demo statistics: $e');
      return {
        'total_demos': 0,
        'active_demos': 0,
        'returned_demos': 0,
        'active_demo_items': 0,
      };
    }
  }

  /// Delete demo transactions and demo document (Development only)
  /// WARNING: This permanently deletes demo records - for development use only
  Future<Map<String, dynamic>> deleteDemo({
    required String demoId,
    required String demoNumber,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      // Get the demo record
      final demoDoc = await _firestore.collection('demos').doc(demoId).get();

      if (!demoDoc.exists) {
        return {'success': false, 'error': 'Demo record not found.'};
      }

      final demoData = demoDoc.data()!;
      final transactionIds = List<int>.from(demoData['transaction_ids'] ?? []);

      final batch = _firestore.batch();
      final deletedItems = <String>[];

      // Delete demo transactions if they exist
      if (transactionIds.isNotEmpty) {
        // Get all demo transactions
        final demoTransactions = await _firestore
            .collection('transactions')
            .where('transaction_id', whereIn: transactionIds)
            .where('type', isEqualTo: 'Demo')
            .get();

        // Delete each demo transaction
        for (final transactionDoc in demoTransactions.docs) {
          final transactionData = transactionDoc.data();
          final serialNumber = transactionData['serial_number'] as String;
          deletedItems.add(serialNumber);

          // Add transaction deletion to batch
          batch.delete(transactionDoc.reference);
        }
      }

      // Delete the demo record
      batch.delete(_firestore.collection('demos').doc(demoId));

      // Commit all deletions
      await batch.commit();

      return {
        'success': true,
        'message':
            'Demo "$demoNumber" deleted successfully. ${deletedItems.length} demo transactions removed.',
        'demo_number': demoNumber,
        'deleted_items': deletedItems,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to delete demo: ${e.toString()}',
      };
    }
  }
}
