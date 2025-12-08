import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class StockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  StockService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Stock in an item - adds to inventory and logs transaction
  Future<Map<String, dynamic>> stockInItem({
    required String serialNumber,
    required String equipmentCategory,
    required String model,
    String? size,
    required String batch,
    String? remarks,
  }) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return {'success': false, 'error': 'User not authenticated.'};
      }

      final currentDate = DateTime.now();
      final timestamp = Timestamp.fromDate(currentDate);

      // Check if item already exists in inventory
      final existingItem = await _firestore
          .collection('inventory')
          .where('serial_number', isEqualTo: serialNumber)
          .get();

      if (existingItem.docs.isNotEmpty) {
        return {
          'success': false,
          'error':
              'Item with serial number $serialNumber already exists in inventory.',
        };
      }

      // Get next transaction ID
      final nextTransactionId = await _getNextTransactionId();

      // Prepare inventory data
      final inventoryData = {
        'serial_number': serialNumber,
        'equipment_category': equipmentCategory,
        'model': model,
        'size': size ?? '',
        'batch': batch,
        'date': timestamp,
        'remark': remarks ?? '',
        'uploaded_at': FieldValue.serverTimestamp(),
        'source': 'stock_in_manual',
        'uploaded_by_uid': currentUser.uid,
        'status': 'Active', // Initial status
      };

      // Prepare transaction data (only include relevant fields for stock-in)
      final transactionData = {
        'transaction_id': nextTransactionId,
        'date': timestamp,
        'type': 'Stock_In',
        'location': 'HQ',
        'equipment_category': equipmentCategory,
        'model': model,
        'size': size ?? '',
        'serial_number': serialNumber,
        'quantity': 1,
        'remarks': remarks ?? '',
        'status': 'Active',
        'uploaded_at': FieldValue.serverTimestamp(),
        'source': 'stock_in_manual',
        'uploaded_by_uid': currentUser.uid,
      };

      // Use batch write to ensure both operations succeed or fail together
      final firestoreBatch = _firestore.batch();

      // Add to inventory collection
      final inventoryRef = _firestore.collection('inventory').doc();
      firestoreBatch.set(inventoryRef, {
        ...inventoryData,
        'status': 'Active', // Explicitly set status to Active
      });
      // Note: If item already exists, we return early above.
      // If we allowed re-stocking existing serials, we would use update here.
      // Since we check `existingItem.docs.isNotEmpty` at start, this is a NEW item.
      // So setting 'status': 'Active' in `inventoryData` or here is sufficient.
      // I added it explicitly above or I should add it to inventoryData map.
      // Let's check inventoryData map in code. It didn't have status. So I add it here.

      // Add to transactions collection
      final transactionRef = _firestore.collection('transactions').doc();
      firestoreBatch.set(transactionRef, transactionData);

      // Commit the batch
      await firestoreBatch.commit();

      return {
        'success': true,
        'message': 'Item successfully stocked in.',
        'inventory_id': inventoryRef.id,
        'transaction_id': transactionRef.id,
        'transaction_number': nextTransactionId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to stock in item: ${e.toString()}',
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

  /// Check if an item exists in inventory by serial number (case-insensitive)
  Future<bool> itemExistsInInventory(String serialNumber) async {
    try {
      // Get all inventory items and check case-insensitively
      final querySnapshot = await _firestore.collection('inventory').get();

      final normalizedSerial = serialNumber.toLowerCase();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final docSerial = data['serial_number'] as String?;
        if (docSerial != null && docSerial.toLowerCase() == normalizedSerial) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get inventory item by serial number (case-insensitive)
  Future<Map<String, dynamic>?> getInventoryItem(String serialNumber) async {
    try {
      // Get all inventory items and check case-insensitively
      final querySnapshot = await _firestore.collection('inventory').get();

      final normalizedSerial = serialNumber.toLowerCase();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final docSerial = data['serial_number'] as String?;
        if (docSerial != null && docSerial.toLowerCase() == normalizedSerial) {
          return {'id': doc.id, ...data};
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get transaction history for a serial number
  Future<List<Map<String, dynamic>>> getTransactionHistory(
    String serialNumber,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('transactions')
          .where('serial_number', isEqualTo: serialNumber)
          .orderBy('date', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      return [];
    }
  }
}
