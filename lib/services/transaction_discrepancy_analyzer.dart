import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionDiscrepancyAnalyzer {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Find discrepant transactions between Firebase delivered count and Inventory Management delivered count
  Future<Map<String, dynamic>> findDiscrepantTransactions() async {
    try {
      // Get all inventory items (case-insensitive)
      final inventorySnapshot = await _firestore.collection('inventory').get();
      final Set<String> inventorySerials = {};
      final Map<String, Map<String, dynamic>> inventoryBySerial = {};

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();
          inventorySerials.add(normalizedSerial);
          inventoryBySerial[normalizedSerial] = {
            ...data,
            'inventory_doc_id': doc.id,
            'original_serial': serialNumber,
          };
        }
      }

      // Get all transactions for comprehensive analysis
      final allTransactionsSnapshot = await _firestore
          .collection('transactions')
          .get();

      // Group ALL transactions by serial number (case-insensitive) for status calculation
      final Map<String, List<Map<String, dynamic>>> allTransactionsBySerial =
          {};

      for (final doc in allTransactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();
          allTransactionsBySerial.putIfAbsent(normalizedSerial, () => []);
          allTransactionsBySerial[normalizedSerial]!.add({
            ...data,
            'document_id': doc.id,
            'original_serial': serialNumber,
            'normalized_serial': normalizedSerial,
          });
        }
      }

      // Get specifically delivered transactions for Firebase count
      final deliveredTransactionsSnapshot = await _firestore
          .collection('transactions')
          .where('status', isEqualTo: 'Delivered')
          .get();

      final List<Map<String, dynamic>> allDeliveredTransactions = [];

      for (final doc in deliveredTransactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();

          final transactionData = {
            ...data,
            'document_id': doc.id,
            'original_serial': serialNumber,
            'normalized_serial': normalizedSerial,
          };

          allDeliveredTransactions.add(transactionData);
        }
      }

      // Calculate currently delivered items using simplified logic:
      // If a serial has exactly 1 Stock_In and 1 Stock_Out, count it as delivered
      int actualDeliveredItems = 0;
      final List<String> currentlyDeliveredSerials = [];

      for (final serial in inventorySerials) {
        final transactions = allTransactionsBySerial[serial] ?? [];

        // Count Stock_In and Stock_Out transactions
        int stockInCount = 0;
        int stockOutCount = 0;

        for (final transaction in transactions) {
          final type = transaction['type'] as String?;
          if (type == 'Stock_In') {
            stockInCount++;
          } else if (type == 'Stock_Out') {
            stockOutCount++;
          }
        }

        // Enhanced 1+1 logic: Check Stock_Out status for 1 Stock_In + 1 Stock_Out
        if (stockInCount == 1 && stockOutCount == 1) {
          // Check the status of the Stock_Out transaction
          final stockOutTransaction = transactions.firstWhere(
            (t) => t['type'] == 'Stock_Out',
            orElse: () => <String, dynamic>{},
          );
          final stockOutStatus = stockOutTransaction['status'] as String?;

          // Only count as delivered if Stock_Out status is 'Delivered'
          if (stockOutStatus == 'Delivered') {
            actualDeliveredItems++;
            currentlyDeliveredSerials.add(serial);
          }
        }
      }

      // Find discrepant transactions
      final List<Map<String, dynamic>> orphanedTransactions = [];
      final List<Map<String, dynamic>> multipleDeliveryTransactions = [];
      final Map<String, List<Map<String, dynamic>>>
      serialsWithMultipleDeliveries = {};

      // Check for orphaned transactions (delivered transactions without inventory records)
      for (final transaction in allDeliveredTransactions) {
        final normalizedSerial = transaction['normalized_serial'] as String;
        if (!inventorySerials.contains(normalizedSerial)) {
          orphanedTransactions.add(transaction);
        }
      }

      // Group delivered transactions by serial for multiple delivery analysis
      final Map<String, List<Map<String, dynamic>>>
      deliveredTransactionsBySerial = {};
      for (final transaction in allDeliveredTransactions) {
        final normalizedSerial = transaction['normalized_serial'] as String;
        deliveredTransactionsBySerial.putIfAbsent(normalizedSerial, () => []);
        deliveredTransactionsBySerial[normalizedSerial]!.add(transaction);
      }

      // Check for multiple deliveries of the same item
      for (final entry in deliveredTransactionsBySerial.entries) {
        final serial = entry.key;
        final transactions = entry.value;

        if (transactions.length > 1) {
          serialsWithMultipleDeliveries[serial] = transactions;
          // Add all but the most recent transaction as "extra" deliveries
          final sortedTransactions = List<Map<String, dynamic>>.from(
            transactions,
          );
          sortedTransactions.sort((a, b) {
            final aTime = a['date'];
            final bTime = b['date'];

            DateTime aDate;
            DateTime bDate;

            if (aTime is Timestamp) {
              aDate = aTime.toDate();
            } else if (aTime is String) {
              aDate = DateTime.tryParse(aTime) ?? DateTime.now();
            } else {
              aDate = DateTime.now();
            }

            if (bTime is Timestamp) {
              bDate = bTime.toDate();
            } else if (bTime is String) {
              bDate = DateTime.tryParse(bTime) ?? DateTime.now();
            } else {
              bDate = DateTime.now();
            }

            return bDate.compareTo(aDate); // Most recent first
          });

          // All transactions except the first (most recent) are considered "extra"
          for (int i = 1; i < sortedTransactions.length; i++) {
            multipleDeliveryTransactions.add(sortedTransactions[i]);
          }
        }
      }

      // Additional analysis for better understanding
      final List<Map<String, dynamic>> deliveredTransactionsWithInventory = [];
      final List<Map<String, dynamic>> deliveredTransactionsWithoutInventory =
          [];
      final Set<String> uniqueDeliveredSerials = {};

      for (final transaction in allDeliveredTransactions) {
        final normalizedSerial = transaction['normalized_serial'] as String;
        uniqueDeliveredSerials.add(normalizedSerial);

        if (inventorySerials.contains(normalizedSerial)) {
          deliveredTransactionsWithInventory.add(transaction);
        } else {
          deliveredTransactionsWithoutInventory.add(transaction);
        }
      }

      // Since we now count 1 Stock_In + 1 Stock_Out as delivered,
      // this section will find items that have delivered transactions but don't follow the 1+1 pattern
      final List<String> deliveredSerialsNotCurrentlyDelivered = [];

      // Find items that have delivered transactions but are not in our currentlyDeliveredSerials list
      for (final serial in uniqueDeliveredSerials) {
        if (inventorySerials.contains(serial) &&
            !currentlyDeliveredSerials.contains(serial)) {
          // Get the original serial number for display
          final transactions = allTransactionsBySerial[serial] ?? [];
          final originalSerial = transactions.isNotEmpty
              ? transactions.first['original_serial']
              : serial;
          deliveredSerialsNotCurrentlyDelivered.add(originalSerial);
        }
      }

      return {
        'success': true,
        'analysis': {
          'firebase_delivered_count': allDeliveredTransactions.length,
          'inventory_management_delivered_count': actualDeliveredItems,
          'discrepancy': allDeliveredTransactions.length - actualDeliveredItems,
          'total_inventory_items': inventorySerials.length,
          'unique_delivered_serials': uniqueDeliveredSerials.length,
          'orphaned_transactions': orphanedTransactions,
          'multiple_delivery_transactions': multipleDeliveryTransactions,
          'delivered_transactions_with_inventory':
              deliveredTransactionsWithInventory,
          'delivered_transactions_without_inventory':
              deliveredTransactionsWithoutInventory,
          'delivered_serials_not_currently_delivered':
              deliveredSerialsNotCurrentlyDelivered,
          'currently_delivered_serials': currentlyDeliveredSerials,
          'breakdown': {
            'orphaned_count': orphanedTransactions.length,
            'multiple_delivery_count': multipleDeliveryTransactions.length,
            'delivered_with_inventory_count':
                deliveredTransactionsWithInventory.length,
            'delivered_without_inventory_count':
                deliveredTransactionsWithoutInventory.length,
            'serials_delivered_but_not_current':
                deliveredSerialsNotCurrentlyDelivered.length,
          },
        },
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to analyze discrepant transactions: ${e.toString()}',
      };
    }
  }
}
