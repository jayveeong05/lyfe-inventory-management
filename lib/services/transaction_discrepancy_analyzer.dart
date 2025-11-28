import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionDiscrepancyAnalyzer {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Find the exact 24 discrepant transactions between Firebase count (370) and Inventory Management count (346)
  Future<Map<String, dynamic>> findDiscrepantTransactions() async {
    try {
      // Get all inventory items (case-insensitive)
      final inventorySnapshot = await _firestore.collection('inventory').get();
      final Set<String> inventorySerials = {};
      
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null && serialNumber.isNotEmpty) {
          inventorySerials.add(serialNumber.toLowerCase());
        }
      }

      // Get all delivered transactions
      final transactionsSnapshot = await _firestore
          .collection('transactions')
          .where('status', isEqualTo: 'Delivered')
          .get();

      // Group transactions by serial number (case-insensitive)
      final Map<String, List<Map<String, dynamic>>> transactionsBySerial = {};
      final List<Map<String, dynamic>> allDeliveredTransactions = [];
      
      for (final doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        
        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();
          transactionsBySerial.putIfAbsent(normalizedSerial, () => []);
          
          final transactionData = {
            ...data,
            'document_id': doc.id,
            'original_serial': serialNumber,
            'normalized_serial': normalizedSerial,
          };
          
          transactionsBySerial[normalizedSerial]!.add(transactionData);
          allDeliveredTransactions.add(transactionData);
        }
      }

      // Calculate current status for each inventory item
      int actualDeliveredItems = 0;
      final List<String> currentlyDeliveredSerials = [];
      
      for (final serial in inventorySerials) {
        final transactions = transactionsBySerial[serial] ?? [];
        final currentStatus = _calculateCurrentStatus(serial, transactions);
        if (currentStatus == 'Delivered') {
          actualDeliveredItems++;
          currentlyDeliveredSerials.add(serial);
        }
      }

      // Find discrepant transactions
      final List<Map<String, dynamic>> orphanedTransactions = [];
      final List<Map<String, dynamic>> multipleDeliveryTransactions = [];
      final Map<String, List<Map<String, dynamic>>> serialsWithMultipleDeliveries = {};

      // Check for orphaned transactions (delivered transactions without inventory records)
      for (final transaction in allDeliveredTransactions) {
        final normalizedSerial = transaction['normalized_serial'] as String;
        if (!inventorySerials.contains(normalizedSerial)) {
          orphanedTransactions.add(transaction);
        }
      }

      // Check for multiple deliveries of the same item
      for (final entry in transactionsBySerial.entries) {
        final serial = entry.key;
        final transactions = entry.value;
        
        if (transactions.length > 1) {
          serialsWithMultipleDeliveries[serial] = transactions;
          // Add all but the most recent transaction as "extra" deliveries
          final sortedTransactions = List<Map<String, dynamic>>.from(transactions);
          sortedTransactions.sort((a, b) {
            final aDate = a['date'] as Timestamp?;
            final bDate = b['date'] as Timestamp?;
            if (aDate == null || bDate == null) return 0;
            return bDate.compareTo(aDate); // Most recent first
          });
          
          // All transactions except the first (most recent) are considered "extra"
          for (int i = 1; i < sortedTransactions.length; i++) {
            multipleDeliveryTransactions.add(sortedTransactions[i]);
          }
        }
      }

      return {
        'success': true,
        'analysis': {
          'total_delivered_transactions': allDeliveredTransactions.length,
          'inventory_items_count': inventorySerials.length,
          'currently_delivered_items': actualDeliveredItems,
          'discrepancy': allDeliveredTransactions.length - actualDeliveredItems,
          'orphaned_transactions': orphanedTransactions,
          'multiple_delivery_transactions': multipleDeliveryTransactions,
          'serials_with_multiple_deliveries': serialsWithMultipleDeliveries,
          'currently_delivered_serials': currentlyDeliveredSerials,
        }
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to analyze discrepant transactions: ${e.toString()}',
      };
    }
  }

  /// Calculate current status using the same logic as Inventory Management Service
  String _calculateCurrentStatus(String serialNumber, List<Map<String, dynamic>> transactions) {
    if (transactions.isEmpty) {
      return 'Active';
    }

    // Sort transactions by date (most recent first)
    transactions.sort((a, b) {
      final aDate = a['date'] as Timestamp?;
      final bDate = b['date'] as Timestamp?;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    final mostRecentTransaction = transactions.first;
    final transactionType = mostRecentTransaction['type'] as String? ?? '';
    final transactionStatus = mostRecentTransaction['status'] as String? ?? '';

    String status;
    if (transactionType == 'Stock_Out') {
      switch (transactionStatus.toLowerCase()) {
        case 'reserved':
          status = 'Reserved';
          break;
        case 'delivered':
          status = 'Delivered';
          break;
        case 'active':
        default:
          status = 'Active';
          break;
      }
    } else {
      status = 'Active';
    }

    return status;
  }
}
