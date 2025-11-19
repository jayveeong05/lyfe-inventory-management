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

      return analytics;
    } catch (e) {
      print('Error fetching dashboard analytics: $e');
      return _getEmptyAnalytics();
    }
  }

  // Get inventory statistics
  Future<Map<String, dynamic>> _getInventoryStats() async {
    try {
      // Get all inventory items (use current date as cutoff for consistency)
      final now = DateTime.now();
      final inventorySnapshot = await _firestore
          .collection('inventory')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .get();
      final totalInventoryItems = inventorySnapshot.docs.length;

      // Get all stock out transactions to determine which items are no longer available
      final stockOutSnapshot = await _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .get();

      // Get stocked out serial numbers (excluding 'Active' status)
      Set<String> stockedOutSerials = {};
      for (final doc in stockOutSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        final serialNumber = data['serial_number'] as String?;

        if (status != null && status != 'Active' && serialNumber != null) {
          stockedOutSerials.add(serialNumber);
        }
      }

      // Count active and stocked out items using inventory-based logic
      int activeStock = 0;
      int stockedOutItems = stockedOutSerials.length;

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;

        if (serialNumber != null && !stockedOutSerials.contains(serialNumber)) {
          // Item is still active (in inventory and not stocked out)
          activeStock++;
        }
      }

      return {
        'totalInventoryItems': totalInventoryItems,
        'activeStock': activeStock,
        'stockedOutItems': stockedOutItems,
      };
    } catch (e) {
      print('Error fetching inventory stats: $e');
      return {'totalInventoryItems': 0, 'activeStock': 0, 'stockedOutItems': 0};
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
        final data = doc.data();
        final type = data['type'] as String?;

        if (type == 'Stock_In') {
          stockInTransactions++;
        } else if (type == 'Stock_Out') {
          stockOutTransactions++;
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

      for (final doc in orderSnapshot.docs) {
        final data = doc.data();
        // Support both old single status and new dual status system
        final status = data['status'] as String?;
        final invoiceStatus = data['invoice_status'] as String? ?? status;

        if (invoiceStatus == 'Invoiced') {
          invoicedOrders++;
        } else {
          pendingOrders++;
        }
      }

      return {
        'totalOrders': totalOrders,
        'invoicedOrders': invoicedOrders,
        'pendingOrders': pendingOrders,
      };
    } catch (e) {
      print('Error fetching order stats: $e');
      return {'totalOrders': 0, 'invoicedOrders': 0, 'pendingOrders': 0};
    }
  }

  // Get recent transactions (last 10)
  Future<List<Map<String, dynamic>>> _getRecentTransactions() async {
    try {
      // Get all transactions without ordering first (to avoid mixed type issues)
      final snapshot = await _firestore.collection('transactions').get();

      // Convert all transactions and normalize timestamps
      final allTransactions = snapshot.docs.map((doc) {
        final data = {'id': doc.id, ...doc.data()};

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
        return data;
      }).toList();

      // Sort by normalized timestamp (most recent first), then by transaction_id (highest first)
      allTransactions.sort((a, b) {
        final aTime = a['_normalized_uploaded_at'] as DateTime;
        final bTime = b['_normalized_uploaded_at'] as DateTime;

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

  // Get top equipment categories
  Future<List<Map<String, dynamic>>> _getTopCategories() async {
    try {
      final snapshot = await _firestore.collection('inventory').get();

      Map<String, int> categoryCount = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final category = data['equipment_category'] as String?;
        if (category != null) {
          categoryCount[category] = (categoryCount[category] ?? 0) + 1;
        }
      }

      // Sort by count and return top 5
      final sortedCategories = categoryCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedCategories
          .take(5)
          .map((entry) => {'category': entry.key, 'count': entry.value})
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
        final aTime = a['_normalized_uploaded_at'] as DateTime;
        final bTime = b['_normalized_uploaded_at'] as DateTime;
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
          counts['reserved'] = counts['reserved']! + 1;
        } else if (invoiceStatus == 'Invoiced' && deliveryStatus == 'Pending') {
          counts['invoiced'] = counts['invoiced']! + 1;
        } else if (deliveryStatus == 'Issued') {
          counts['issued'] = counts['issued']! + 1;
        } else if (deliveryStatus == 'Delivered') {
          counts['delivered'] = counts['delivered']! + 1;
        }
      }

      return counts;
    } catch (e) {
      print('Error fetching order status counts: $e');
      return {'reserved': 0, 'invoiced': 0, 'issued': 0, 'delivered': 0};
    }
  }
}
