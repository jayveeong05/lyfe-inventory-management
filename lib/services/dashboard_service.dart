import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get dashboard analytics data
  Future<Map<String, dynamic>> getDashboardAnalytics() async {
    try {
      // Initialize analytics data
      Map<String, dynamic> analytics = {
        'totalInventoryItems': 0,
        'activeStock': 0,
        'stockedOutItems': 0,
        'totalOrders': 0,
        'invoicedOrders': 0,
        'pendingOrders': 0,
        'totalTransactions': 0,
        'stockInTransactions': 0,
        'stockOutTransactions': 0,
        'recentTransactions': <Map<String, dynamic>>[],
        'lowStockItems': <Map<String, dynamic>>[],
        'topCategories': <Map<String, dynamic>>[],
        'monthlyStats': <Map<String, dynamic>>{},
      };

      // Fetch all data in parallel for better performance
      final futures = await Future.wait([
        _getInventoryStats(),
        _getTransactionStats(),
        _getOrderStats(),
        _getRecentTransactions(),
        _getTopCategories(),
        _getMonthlyStats(),
      ]);

      // Combine all results
      analytics.addAll(futures[0] as Map<String, dynamic>); // Inventory stats
      analytics.addAll(futures[1] as Map<String, dynamic>); // Transaction stats
      analytics.addAll(
        futures[2] as Map<String, dynamic>,
      ); // Purchase order stats
      analytics['recentTransactions'] = futures[3]; // Recent transactions
      analytics['topCategories'] = futures[4]; // Top categories
      analytics['monthlyStats'] = futures[5]; // Monthly stats

      // Add data integrity check
      final integrityCheck = await _getDataIntegrityReport();
      analytics['dataIntegrity'] = integrityCheck;

      return analytics;
    } catch (e) {
      print('Error fetching dashboard analytics: $e');
      return _getEmptyAnalytics();
    }
  }

  // Get inventory statistics using new 1+1 logic
  Future<Map<String, dynamic>> _getInventoryStats() async {
    try {
      // Get all inventory items
      final inventorySnapshot = await _firestore.collection('inventory').get();
      final totalInventoryItems = inventorySnapshot.docs.length;

      // Get all transactions for status calculation
      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      // Create transaction lookup map (case-insensitive)
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

      // Count items by status using new 1+1 logic
      int activeStock = 0;
      int reservedItems = 0;
      int deliveredItems = 0;

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null) {
          final normalizedSerial = serialNumber.toLowerCase();
          final transactions = transactionsBySerial[normalizedSerial] ?? [];
          final status = _calculateCurrentStatus(serialNumber, transactions);

          switch (status) {
            case 'Active':
              activeStock++;
              break;
            case 'Reserved':
              reservedItems++;
              break;
            case 'Delivered':
              deliveredItems++;
              break;
          }
        }
      }

      return {
        'totalInventoryItems': totalInventoryItems,
        'activeStock': activeStock,
        'stockedOutItems':
            deliveredItems, // For backward compatibility with Key Metrics
        'reservedItems': reservedItems,
        'deliveredItems': deliveredItems,
      };
    } catch (e) {
      print('Error fetching inventory stats: $e');
      return {
        'totalInventoryItems': 0,
        'activeStock': 0,
        'stockedOutItems': 0,
        'reservedItems': 0,
        'deliveredItems': 0,
      };
    }
  }

  // Get transaction statistics
  Future<Map<String, dynamic>> _getTransactionStats() async {
    try {
      final transactionsSnapshot = await _firestore
          .collection('transactions')
          .get();
      final totalTransactions = transactionsSnapshot.docs.length;

      int stockInTransactions = 0;
      int stockOutTransactions = 0;

      for (final doc in transactionsSnapshot.docs) {
        try {
          final data = doc.data();
          if (data == null) continue;

          final type = data['type'] as String?;

          if (type == 'Stock_In') {
            stockInTransactions++;
          } else if (type == 'Stock_Out') {
            stockOutTransactions++;
          }
        } catch (e) {
          print('Error processing transaction doc ${doc.id}: $e');
          continue;
        }
      }

      return {
        'totalTransactions': totalTransactions,
        'stockInTransactions': stockInTransactions,
        'stockOutTransactions': stockOutTransactions,
      };
    } catch (e) {
      print('Error fetching transaction stats: $e');
      return {
        'totalTransactions': 0,
        'stockInTransactions': 0,
        'stockOutTransactions': 0,
      };
    }
  }

  // Get order statistics
  Future<Map<String, dynamic>> _getOrderStats() async {
    try {
      final orderSnapshot = await _firestore.collection('orders').get();
      final totalOrders = orderSnapshot.docs.length;

      int invoicedOrders = 0;
      int pendingOrders = 0;
      int issuedOrders = 0;

      for (final doc in orderSnapshot.docs) {
        final data = doc.data();
        // Support both old single status and new dual status system
        final status = data['status'] as String?;
        final invoiceStatus = data['invoice_status'] as String? ?? status;
        final deliveryStatus = data['delivery_status'] as String? ?? 'Pending';

        // Count based on combined status logic
        if (invoiceStatus == 'Reserved') {
          pendingOrders++;
        } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Pending') {
          invoicedOrders++;
        } else if (deliveryStatus == 'Issued') {
          issuedOrders++;
        } else if (deliveryStatus == 'Delivered') {
          // Count delivered orders as issued for display purposes
          issuedOrders++;
        }
      }

      return {
        'totalOrders': totalOrders,
        'invoicedOrders': invoicedOrders,
        'pendingOrders': pendingOrders,
        'issuedOrders': issuedOrders,
      };
    } catch (e) {
      print('Error fetching order stats: $e');
      return {
        'totalOrders': 0,
        'invoicedOrders': 0,
        'pendingOrders': 0,
        'issuedOrders': 0,
      };
    }
  }

  // Get recent transactions (last 10)
  Future<List<Map<String, dynamic>>> _getRecentTransactions() async {
    try {
      // Get all transactions without ordering first (to avoid mixed type issues)
      final snapshot = await _firestore.collection('transactions').get();

      // Convert all transactions and normalize timestamps
      final allTransactions = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        try {
          final docData = doc.data();
          if (docData == null) continue;

          final data = {'id': doc.id, ...docData};

          // Normalize uploaded_at to DateTime for consistent sorting
          DateTime? uploadedAt;
          final uploadedAtField = data['uploaded_at'];

          if (uploadedAtField is Timestamp) {
            uploadedAt = uploadedAtField.toDate();
          } else if (uploadedAtField is String) {
            try {
              uploadedAt = DateTime.parse(uploadedAtField);
            } catch (e) {
              // If parsing fails, use a very old date so it appears last
              uploadedAt = DateTime(2000);
            }
          } else {
            // If no valid timestamp, use a very old date
            uploadedAt = DateTime(2000);
          }

          data['_normalized_uploaded_at'] = uploadedAt;
          allTransactions.add(data);
        } catch (e) {
          print('Error processing transaction doc ${doc.id}: $e');
          continue;
        }
      }

      // Sort by normalized timestamp (most recent first), then by transaction_id (highest first)
      allTransactions.sort((a, b) {
        final aTime =
            a['_normalized_uploaded_at'] as DateTime? ?? DateTime(2000);
        final bTime =
            b['_normalized_uploaded_at'] as DateTime? ?? DateTime(2000);

        // Primary sort: by timestamp (most recent first)
        final timeComparison = bTime.compareTo(aTime);
        if (timeComparison != 0) {
          return timeComparison;
        }

        // Secondary sort: by transaction_id (highest first) for same timestamps
        final aId = a['transaction_id'] as int? ?? 0;
        final bId = b['transaction_id'] as int? ?? 0;
        return bId.compareTo(aId); // Descending order (highest ID first)
      });

      // Take the 10 most recent
      final recentTransactions = allTransactions.take(10).toList();

      // Remove the temporary normalized field before returning
      for (final transaction in recentTransactions) {
        transaction.remove('_normalized_uploaded_at');
      }

      return recentTransactions;
    } catch (e) {
      print('Error fetching recent transactions: $e');
      return [];
    }
  }

  // Get top equipment categories by active items count
  Future<List<Map<String, dynamic>>> _getTopCategories() async {
    try {
      // Get all inventory items and all transactions to calculate active status
      final futures = await Future.wait([
        _firestore.collection('inventory').get(),
        _firestore.collection('transactions').get(),
      ]);

      final inventorySnapshot = futures[0];
      final transactionSnapshot = futures[1];

      // Group transactions by serial number (case-insensitive)
      final transactionsBySerial = <String, List<Map<String, dynamic>>>{};
      for (final doc in transactionSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null) {
          final normalizedSerial = serialNumber.toLowerCase();
          transactionsBySerial[normalizedSerial] ??= [];
          transactionsBySerial[normalizedSerial]!.add({'id': doc.id, ...data});
        }
      }

      Map<String, int> categoryActiveCount = {};

      // Process each inventory item to check if it's currently active
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final category = data['equipment_category'] as String?;
        final serialNumber = data['serial_number'] as String?;

        if (category != null && serialNumber != null) {
          final normalizedSerial = serialNumber.toLowerCase();
          final transactions = transactionsBySerial[normalizedSerial] ?? [];

          // Calculate current status using enhanced 1+1 logic
          final currentStatus = _calculateCurrentStatus(
            serialNumber,
            transactions,
          );

          // Only count active items
          if (currentStatus == 'Active') {
            categoryActiveCount[category] =
                (categoryActiveCount[category] ?? 0) + 1;
          }
        }
      }

      // Sort by active count and return top 5
      final sortedCategories = categoryActiveCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedCategories
          .take(5)
          .map((entry) => {'category': entry.key, 'active_count': entry.value})
          .toList();
    } catch (e) {
      print('Error fetching top categories: $e');
      return [];
    }
  }

  // Get monthly statistics (current month)
  Future<Map<String, dynamic>> _getMonthlyStats() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      final snapshot = await _firestore
          .collection('transactions')
          .where(
            'uploaded_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .where(
            'uploaded_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth),
          )
          .get();

      int monthlyStockIn = 0;
      int monthlyStockOut = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String?;

        if (type == 'Stock_In') {
          monthlyStockIn++;
        } else if (type == 'Stock_Out') {
          monthlyStockOut++;
        }
      }

      return {
        'monthlyStockIn': monthlyStockIn,
        'monthlyStockOut': monthlyStockOut,
        'monthlyTotal': monthlyStockIn + monthlyStockOut,
      };
    } catch (e) {
      print('Error fetching monthly stats: $e');
      return {'monthlyStockIn': 0, 'monthlyStockOut': 0, 'monthlyTotal': 0};
    }
  }

  // Get lightweight data for background checking (just latest activity info)
  Future<Map<String, dynamic>> getLatestActivityInfo() async {
    try {
      // Get just the most recent transaction, basic counts, and order status info
      final futures = await Future.wait([
        _getLatestTransaction(),
        _getBasicCounts(),
        _getOrderStatusCounts(),
      ]);

      return {
        'latestTransaction': futures[0],
        'basicCounts': futures[1],
        'orderStatusCounts': futures[2],
      };
    } catch (e) {
      print('Error fetching latest activity info: $e');
      return {
        'latestTransaction': null,
        'basicCounts': {'totalTransactions': 0, 'totalOrders': 0},
        'orderStatusCounts': {
          'reserved': 0,
          'invoiced': 0,
          'issued': 0,
          'delivered': 0,
        },
      };
    }
  }

  // Get just the most recent transaction for comparison
  Future<Map<String, dynamic>?> _getLatestTransaction() async {
    try {
      final snapshot = await _firestore
          .collection('transactions')
          .limit(50) // Get more to handle mixed timestamp types
          .get();

      if (snapshot.docs.isEmpty) return null;

      // Convert and normalize timestamps like in _getRecentTransactions
      final allTransactions = snapshot.docs.map((doc) {
        final data = {'id': doc.id, ...doc.data()};

        DateTime? uploadedAt;
        final uploadedAtField = data['uploaded_at'];

        if (uploadedAtField is Timestamp) {
          uploadedAt = uploadedAtField.toDate();
        } else if (uploadedAtField is String) {
          try {
            uploadedAt = DateTime.parse(uploadedAtField);
          } catch (e) {
            uploadedAt = DateTime(2000);
          }
        } else {
          uploadedAt = DateTime(2000);
        }

        data['_normalized_uploaded_at'] = uploadedAt;
        return data;
      }).toList();

      // Sort and get the most recent
      allTransactions.sort((a, b) {
        final aTime =
            a['_normalized_uploaded_at'] as DateTime? ?? DateTime(2000);
        final bTime =
            b['_normalized_uploaded_at'] as DateTime? ?? DateTime(2000);
        final timeComparison = bTime.compareTo(aTime);
        if (timeComparison != 0) return timeComparison;

        final aId = a['transaction_id'] as int? ?? 0;
        final bId = b['transaction_id'] as int? ?? 0;
        return bId.compareTo(aId);
      });

      final latest = allTransactions.first;
      latest.remove('_normalized_uploaded_at');
      return latest;
    } catch (e) {
      print('Error fetching latest transaction: $e');
      return null;
    }
  }

  // Get basic counts for comparison
  Future<Map<String, int>> _getBasicCounts() async {
    try {
      final futures = await Future.wait([
        _firestore.collection('transactions').count().get(),
        _firestore.collection('orders').count().get(),
      ]);

      return {
        'totalTransactions': futures[0].count ?? 0,
        'totalOrders': futures[1].count ?? 0,
      };
    } catch (e) {
      print('Error fetching basic counts: $e');
      return {'totalTransactions': 0, 'totalOrders': 0};
    }
  }

  // Return empty analytics in case of error
  Map<String, dynamic> _getEmptyAnalytics() {
    return {
      'totalInventoryItems': 0,
      'activeStock': 0,
      'stockedOutItems': 0,
      'reservedItems': 0,
      'deliveredItems': 0,
      'totalOrders': 0,
      'invoicedOrders': 0,
      'pendingOrders': 0,
      'totalTransactions': 0,
      'stockInTransactions': 0,
      'stockOutTransactions': 0,
      'recentTransactions': <Map<String, dynamic>>[],
      'lowStockItems': <Map<String, dynamic>>[],
      'topCategories': <Map<String, dynamic>>[],
      'monthlyStats': {
        'monthlyStockIn': 0,
        'monthlyStockOut': 0,
        'monthlyTotal': 0,
      },
    };
  }

  // Get order status counts for change detection (using dual status system)
  Future<Map<String, int>> _getOrderStatusCounts() async {
    try {
      final snapshot = await _firestore.collection('orders').get();

      final counts = {
        'reserved': 0,
        'invoiced': 0,
        'issued': 0,
        'delivered': 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Support both old single status and new dual status system
        final status = data['status'] as String?;
        final invoiceStatus = data['invoice_status'] as String? ?? status;
        final deliveryStatus = data['delivery_status'] as String? ?? 'Pending';

        // Count based on combined status logic
        if (invoiceStatus == 'Reserved') {
          counts['reserved'] = (counts['reserved'] ?? 0) + 1;
        } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Pending') {
          counts['invoiced'] = (counts['invoiced'] ?? 0) + 1;
        } else if (deliveryStatus == 'Issued') {
          counts['issued'] = (counts['issued'] ?? 0) + 1;
        } else if (deliveryStatus == 'Delivered') {
          counts['delivered'] = (counts['delivered'] ?? 0) + 1;
        }
      }

      return counts;
    } catch (e) {
      print('Error fetching order status counts: $e');
      return {'reserved': 0, 'invoiced': 0, 'issued': 0, 'delivered': 0};
    }
  }

  // Get data integrity report
  Future<Map<String, dynamic>> _getDataIntegrityReport() async {
    try {
      // Get all inventory items and transactions in parallel
      final futures = await Future.wait([
        _firestore.collection('inventory').get(),
        _firestore.collection('transactions').get(),
      ]);

      final inventorySnapshot = futures[0];
      final transactionsSnapshot = futures[1];

      // Create sets for comparison
      final Set<String> inventorySerials = {};
      final Set<String> stockInSerials = {};
      final Set<String> stockOutSerials = {};

      // Process inventory items (case-insensitive)
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null && serialNumber.isNotEmpty) {
          inventorySerials.add(serialNumber.toLowerCase());
        }
      }

      // Process transactions (case-insensitive)
      for (final doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        final type = data['type'] as String?;

        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();
          if (type == 'Stock_In') {
            stockInSerials.add(normalizedSerial);
          } else if (type == 'Stock_Out') {
            stockOutSerials.add(normalizedSerial);
          }
        }
      }

      // Find discrepancies
      final orphanedStockOuts = stockOutSerials
          .difference(inventorySerials)
          .toList();
      final missingStockIns = inventorySerials
          .difference(stockInSerials)
          .toList();
      final stockOutWithoutStockIn = stockOutSerials
          .difference(stockInSerials)
          .toList();

      // Additional analysis: Check delivered transaction discrepancy (case-insensitive)
      final deliveredTransactions = <String>[];
      for (final doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        final status = data['status'] as String?;

        if (serialNumber != null &&
            serialNumber.isNotEmpty &&
            status?.toLowerCase() == 'delivered') {
          deliveredTransactions.add(serialNumber.toLowerCase());
        }
      }

      final uniqueDeliveredSerials = deliveredTransactions.toSet();
      final orphanedDeliveredTransactions = uniqueDeliveredSerials
          .difference(inventorySerials)
          .toList();

      // Calculate actual delivered items using Inventory Management logic
      // Group transactions by serial number (case-insensitive)
      final Map<String, List<Map<String, dynamic>>> transactionsBySerial = {};
      for (final doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null && serialNumber.isNotEmpty) {
          final normalizedSerial = serialNumber.toLowerCase();
          transactionsBySerial.putIfAbsent(normalizedSerial, () => []);
          transactionsBySerial[normalizedSerial]!.add(data);
        }
      }

      // Count inventory items with current status = 'Delivered' (case-insensitive)
      int actualDeliveredItems = 0;
      for (final serial in inventorySerials) {
        final transactions = transactionsBySerial[serial] ?? [];
        final currentStatus = _calculateCurrentStatus(serial, transactions);
        if (currentStatus == 'Delivered') {
          actualDeliveredItems++;
        }
      }

      // Calculate summary
      final totalIssues = orphanedStockOuts.length + missingStockIns.length;
      final lastChecked = DateTime.now();

      return {
        'totalIssues': totalIssues,
        'lastChecked': lastChecked,
        'orphanedStockOuts': orphanedStockOuts,
        'missingStockIns': missingStockIns,
        'stockOutWithoutStockIn': stockOutWithoutStockIn,
        'deliveredAnalysis': {
          'totalDeliveredTransactions': deliveredTransactions.length,
          'uniqueDeliveredSerials': uniqueDeliveredSerials.length,
          'deliveredInInventory': actualDeliveredItems,
          'orphanedDeliveredTransactions': orphanedDeliveredTransactions,
          'multipleDeliveredCount':
              deliveredTransactions.length - uniqueDeliveredSerials.length,
        },
        'summary': {
          'totalInventoryItems': inventorySerials.length,
          'totalStockInTransactions': stockInSerials.length,
          'totalStockOutTransactions': stockOutSerials.length,
          'orphanedStockOutsCount': orphanedStockOuts.length,
          'missingStockInsCount': missingStockIns.length,
          'deliveredDiscrepancy':
              deliveredTransactions.length - actualDeliveredItems,
        },
      };
    } catch (e) {
      print('Error generating data integrity report: $e');
      return {
        'totalIssues': 0,
        'lastChecked': DateTime.now(),
        'orphanedStockOuts': <String>[],
        'missingStockIns': <String>[],
        'stockOutWithoutStockIn': <String>[],
        'summary': {
          'totalInventoryItems': 0,
          'totalStockInTransactions': 0,
          'totalStockOutTransactions': 0,
          'orphanedStockOutsCount': 0,
          'missingStockInsCount': 0,
        },
      };
    }
  }

  // Helper method to calculate current status using enhanced logic to handle dual Stock_Out transactions
  String _calculateCurrentStatus(
    String serialNumber,
    List<Map<String, dynamic>> transactions,
  ) {
    if (transactions.isEmpty) {
      return 'Active';
    }

    // Count Stock_In and Stock_Out transactions
    int stockInCount = 0;
    int stockOutCount = 0;
    bool hasDeliveredStockOut = false;
    bool hasReservedStockOut = false;

    for (final transaction in transactions) {
      final type = transaction['type'] as String?;
      final status = transaction['status'] as String?;

      if (type == 'Stock_In') {
        stockInCount++;
      } else if (type == 'Stock_Out') {
        stockOutCount++;
        if (status == 'Delivered') {
          hasDeliveredStockOut = true;
        } else if (status == 'Reserved') {
          hasReservedStockOut = true;
        }
      }
    }

    // Enhanced logic to handle dual Stock_Out transaction system:
    // - 1 Stock_In + Stock_Out(s) with any 'Delivered' status = Delivered
    // - 1 Stock_In + Stock_Out(s) with only 'Reserved' status = Reserved
    // - Stock_Out without matching Stock_In = Reserved (pending delivery)
    // - Stock_In without Stock_Out = Active (in stock)
    // - No transactions = Active
    if (stockInCount == 1 && stockOutCount >= 1) {
      if (hasDeliveredStockOut) {
        return 'Delivered';
      } else if (hasReservedStockOut) {
        return 'Reserved';
      } else {
        return 'Reserved'; // Default for Stock_Out without clear status
      }
    } else if (stockOutCount > 0 && stockInCount == 0) {
      return 'Reserved'; // Ordered but not received
    } else if (stockOutCount > stockInCount) {
      return 'Reserved'; // More orders than received
    } else {
      return 'Active'; // In stock or default
    }
  }
}
