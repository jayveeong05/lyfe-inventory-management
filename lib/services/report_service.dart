import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import '../utils/file_saver/file_saver.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FileSaver _fileSaver = FileSaver();

  // Export path helper removed as it's now handled by FileSaver

  // Sales Report Methods

  /// Get comprehensive sales report data
  Future<Map<String, dynamic>> getSalesReport({
    DateTime? startDate,
    DateTime? endDate,
    String? customerDealer,
    String? location,
  }) async {
    try {
      // Set default date range if not provided (all time from 2020)
      endDate ??= DateTime.now();
      startDate ??= DateTime(2020, 1, 1); // All-time default

      // Build query for orders
      Query query = _firestore.collection('orders');

      query = query
          .where(
            'created_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            'created_date',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          );

      if (customerDealer != null && customerDealer.isNotEmpty) {
        query = query.where('customer_dealer', isEqualTo: customerDealer);
      }

      final poSnapshot = await query.get();

      // Collect all transaction IDs from the filtered orders
      final allTransactionIds = <int>[];
      for (final doc in poSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final transactionIds = List<dynamic>.from(
          data['transaction_ids'] ?? [],
        );
        for (final id in transactionIds) {
          if (id is int) {
            allTransactionIds.add(id);
          }
        }
      }

      // Fetch transactions by transaction_id (batched due to Firestore whereIn limit of 30)
      final List<DocumentSnapshot> allTransactionDocs = [];

      if (allTransactionIds.isNotEmpty) {
        // Split into batches of 30
        const batchSize = 30;
        for (int i = 0; i < allTransactionIds.length; i += batchSize) {
          final batch = allTransactionIds.skip(i).take(batchSize).toList();

          final batchQuery = _firestore
              .collection('transactions')
              .where('type', isEqualTo: 'Stock_Out')
              .where('transaction_id', whereIn: batch);

          final batchSnapshot = await batchQuery.get();
          allTransactionDocs.addAll(batchSnapshot.docs);
        }
      }

      // Create a QuerySnapshot-like object from collected docs
      final transactionSnapshot = _createQuerySnapshot(allTransactionDocs);

      // Process sales data
      final salesData = await _processSalesData(
        poSnapshot,
        transactionSnapshot,
        locationFilter: location,
      );

      return {
        'success': true,
        'data': salesData,
        'period': {'start_date': startDate, 'end_date': endDate},
      };
    } catch (e) {
      print('Error generating sales report: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Process sales data from orders and transactions
  Future<Map<String, dynamic>> _processSalesData(
    QuerySnapshot orderSnapshot,
    QuerySnapshot transactionSnapshot, {
    String? locationFilter,
  }) async {
    final orders = <Map<String, dynamic>>[];
    final customerStats = <String, Map<String, dynamic>>{};
    final customerItems =
        <String, List<Map<String, dynamic>>>{}; // NEW: Track items per customer
    final locationStats = <String, Map<String, dynamic>>{};
    final dailySales = <String, int>{};
    final categoryStats = <String, Map<String, dynamic>>{};

    // Phase 2: Enhanced analytics tracking
    final dailySalesDetailed =
        <
          String,
          Map<String, dynamic>
        >{}; // Track orders, items, customers per day
    final customerOrderDates =
        <String, List<DateTime>>{}; // Track order dates per customer
    final modelStats = <String, int>{}; // Track sales by model

    int totalOrders = 0;
    int invoicedOrders = 0;
    int pendingOrders = 0;
    // Note: totalItems removed - now calculated from customerItems

    // Create a map of transaction locations for quick lookup
    final transactionLocations = <int, String>{};
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final transactionId = data['transaction_id'] as int?;
      final location = data['location'] as String?;
      if (transactionId != null && location != null) {
        transactionLocations[transactionId] = location;
      }
    }

    final validTransactionIds = <int>{};

    // Process orders
    for (final doc in orderSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Filter by location if requested
      if (locationFilter != null && locationFilter.isNotEmpty) {
        final transactionIds = List<dynamic>.from(
          data['transaction_ids'] ?? [],
        );
        bool locationMatch = false;

        // Check if any transaction in this order matches the location filter
        for (final tId in transactionIds) {
          if (tId is int && transactionLocations[tId] == locationFilter) {
            locationMatch = true;
            break;
          }
        }

        if (!locationMatch) continue;
      }

      // Collect valid transaction IDs from this order
      final tIds = List<dynamic>.from(data['transaction_ids'] ?? []);
      for (final id in tIds) {
        if (id is int) {
          validTransactionIds.add(id);
        }
      }

      final orderData = {'id': doc.id, ...data};
      orders.add(orderData);

      totalOrders++;
      // Use invoice_status if available, fallback to status or Pending
      final status =
          data['invoice_status'] as String? ??
          data['status'] as String? ??
          'Pending';

      if (status == 'Invoiced') {
        invoicedOrders++;
      } else {
        pendingOrders++;
      }

      // Customer statistics (order count only, items will be calculated from customerItems)
      final customer = data['customer_dealer'] as String? ?? 'Unknown';
      customerStats[customer] =
          customerStats[customer] ?? {'orders': 0, 'items': 0};
      customerStats[customer]!['orders'] =
          (customerStats[customer]!['orders'] as int) + 1;
      // Note: items count will be updated after processing all transactions

      // Daily sales tracking (basic)
      final createdDate = data['created_date'] as Timestamp?;
      if (createdDate != null) {
        final dateKey = DateFormat('yyyy-MM-dd').format(createdDate.toDate());
        dailySales[dateKey] = (dailySales[dateKey] ?? 0) + 1;

        // Phase 2: Enhanced daily sales tracking
        final itemCount = data['total_items'] as int? ?? 0;
        dailySalesDetailed[dateKey] =
            dailySalesDetailed[dateKey] ??
            {'orders': 0, 'items': 0, 'customers': <String>{}};
        dailySalesDetailed[dateKey]!['orders'] =
            (dailySalesDetailed[dateKey]!['orders'] as int) + 1;
        dailySalesDetailed[dateKey]!['items'] =
            (dailySalesDetailed[dateKey]!['items'] as int) + itemCount;
        (dailySalesDetailed[dateKey]!['customers'] as Set<String>).add(
          customer,
        );

        // Track customer order dates for segmentation
        customerOrderDates[customer] = customerOrderDates[customer] ?? [];
        customerOrderDates[customer]!.add(createdDate.toDate());
      }
    }

    // Gather all serial numbers from transactions to fetch inventory details in batch
    final serialNumbers = <String>{};
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['serial_number'] != null) {
        serialNumbers.add(data['serial_number'] as String);
      }
    }

    // Fetch inventory details for these serials to fill in missing info
    final inventoryMap = <String, Map<String, dynamic>>{};
    if (serialNumbers.isNotEmpty) {
      // split into chunks of 10 if needed (firestore limit is 10 for some 'in' queries, but here we might just query all or iterate)
      // For simplicity in this report service, let's fetch inventory items that match.
      // Optimally we'd do a whereIn query, but with potentially large lists, let's just do a collection scan or assume we only need those missing data.
      // Actually, let's just fetch ALL inventory for now as the dataset seems small enough, OR better, fetch by chunk.
      // Given the constraints and likely size, let's iterate and fetch if category is missing? No that's N+1.
      // Let's optimize: checking missing categories is only needed if data is missing.

      // Let's just fetch all inventory. It's an "Expensive" report anyway.
      // Or better:
      final invSnapshot = await _firestore.collection('inventory').get();
      for (final doc in invSnapshot.docs) {
        final data = doc.data();
        if (data['serial_number'] != null) {
          inventoryMap[data['serial_number'] as String] = data;
        }
      }
    }

    // Process transactions for additional insights
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final serial = data['serial_number'] as String?;
      final transactionId = data['transaction_id'] as int?;

      // Skip if transaction does not belong to any of the filtered orders
      if (transactionId == null ||
          !validTransactionIds.contains(transactionId)) {
        continue;
      }

      // Location statistics
      // If location is missing in transaction, try to find it in inventory or fallback
      String location = data['location'] as String? ?? '';
      if ((location.isEmpty || location == 'Unknown') &&
          serial != null &&
          inventoryMap.containsKey(serial)) {
        location = inventoryMap[serial]!['location'] as String? ?? '';
      }
      if (location.isEmpty) location = 'Unknown';

      // Skip if location filter does not match
      if (locationFilter != null &&
          locationFilter.isNotEmpty &&
          location != locationFilter) {
        continue;
      }

      locationStats[location] =
          locationStats[location] ?? {'transactions': 0, 'items': 0};
      locationStats[location]!['transactions'] =
          (locationStats[location]!['transactions'] as int) + 1;
      locationStats[location]!['items'] =
          (locationStats[location]!['items'] as int) + 1;

      // Category statistics
      // If category is missing in transaction, try to find it in inventory
      String category = data['equipment_category'] as String? ?? '';
      if ((category.isEmpty || category == 'Unknown') &&
          serial != null &&
          inventoryMap.containsKey(serial)) {
        category = inventoryMap[serial]!['equipment_category'] as String? ?? '';
      }
      if (category.isEmpty) category = 'Unknown';

      // Normalize category name (handle spaces, underscores, case inconsistencies)
      category = _normalizeCategory(category);

      categoryStats[category] =
          categoryStats[category] ?? {'transactions': 0, 'items': 0};
      categoryStats[category]!['transactions'] =
          (categoryStats[category]!['transactions'] as int) + 1;
      categoryStats[category]!['items'] =
          (categoryStats[category]!['items'] as int) + 1;

      // NEW: Collect customer item details
      // Find the order that contains this transaction to get customer name
      final orderContainingTransaction = orders.firstWhere((order) {
        final tIds = List<dynamic>.from(order['transaction_ids'] ?? []);
        return tIds.contains(transactionId);
      }, orElse: () => <String, dynamic>{});

      if (orderContainingTransaction.isNotEmpty) {
        final customerName =
            orderContainingTransaction['customer_dealer'] as String? ??
            'Unknown';
        final orderNumber =
            orderContainingTransaction['order_number'] as String? ?? 'N/A';

        // Handle uploaded_at - can be Timestamp or String (for backfilled data)
        DateTime? uploadedAtDate;
        final uploadedAtValue = data['uploaded_at'];
        if (uploadedAtValue is Timestamp) {
          uploadedAtDate = uploadedAtValue.toDate();
        } else if (uploadedAtValue is String) {
          uploadedAtDate = DateTime.tryParse(uploadedAtValue);
        }

        final model =
            data['model'] as String? ??
            (serial != null && inventoryMap.containsKey(serial)
                ? inventoryMap[serial]!['model'] as String? ?? 'Unknown'
                : 'Unknown');

        // Track model sales for product performance
        if (model != 'Unknown') {
          modelStats[model] = (modelStats[model] ?? 0) + 1;
        }

        // Initialize customer items list if not exists
        customerItems[customerName] = customerItems[customerName] ?? [];

        // Get order delivery status to determine priority
        final orderDeliveryStatus =
            orderContainingTransaction['delivery_status'] as String? ?? '';

        // Check if this serial number already exists for this order (deduplication)
        final existingItemIndex = customerItems[customerName]!.indexWhere(
          (item) =>
              item['serial_number'] == serial &&
              item['order_number'] == orderNumber,
        );

        final itemDetail = {
          'serial_number': serial ?? 'N/A',
          'category': category,
          'model': model,
          'date': uploadedAtDate ?? DateTime.now(),
          'order_number': orderNumber,
          'transaction_id': transactionId,
          'delivery_status': orderDeliveryStatus,
        };

        if (existingItemIndex != -1) {
          // Serial already exists for this order
          // Priority: Delivered > Reserved
          final existingStatus =
              customerItems[customerName]![existingItemIndex]['delivery_status']
                  as String? ??
              '';

          // Replace if:
          // 1. New status is "Delivered" and existing is not "Delivered"
          // 2. Both have same status but new is more recent
          final shouldReplace =
              (orderDeliveryStatus == 'Delivered' &&
                  existingStatus != 'Delivered') ||
              (orderDeliveryStatus == existingStatus &&
                  (uploadedAtDate?.isAfter(
                        customerItems[customerName]![existingItemIndex]['date']
                                as DateTime? ??
                            DateTime(1970),
                      ) ??
                      false));

          if (shouldReplace) {
            customerItems[customerName]![existingItemIndex] = itemDetail;
          }
        } else {
          // New item, add it
          customerItems[customerName]!.add(itemDetail);
        }
      }
    }

    // Update customerStats items count from actual deduplicated transactions
    for (final entry in customerItems.entries) {
      final customerName = entry.key;
      final items = entry.value as List;
      if (customerStats.containsKey(customerName)) {
        customerStats[customerName]!['items'] = items.length;
      }
    }

    // Sort and limit top results
    final topCustomers = customerStats.entries.toList()
      ..sort(
        (a, b) =>
            (b.value['orders'] as int).compareTo(a.value['orders'] as int),
      );

    final topLocations = locationStats.entries.toList()
      ..sort(
        (a, b) => (b.value['transactions'] as int).compareTo(
          a.value['transactions'] as int,
        ),
      );

    final topCategories = categoryStats.entries.toList()
      ..sort(
        (a, b) => (b.value['transactions'] as int).compareTo(
          a.value['transactions'] as int,
        ),
      );

    // Calculate actual items sold from deduplicated customer items
    final actualItemsSold = customerItems.values.fold<int>(
      0,
      (sum, items) => sum + (items as List).length,
    );

    return {
      'summary': {
        'total_orders': totalOrders,
        'invoiced_orders': invoicedOrders,
        'pending_orders': pendingOrders,
        'total_items_sold':
            actualItemsSold, // Use actual count from transactions
        'conversion_rate': totalOrders > 0
            ? (invoicedOrders / totalOrders * 100).toStringAsFixed(1)
            : '0.0',
      },
      'orders': orders,
      'top_customers': topCustomers
          .take(10)
          .map(
            (e) => {
              'customer': e.key,
              'orders': e.value['orders'],
              'items': e.value['items'],
            },
          )
          .toList(),
      'top_locations': topLocations
          .take(10)
          .map(
            (e) => {
              'location': e.key,
              'transactions': e.value['transactions'],
              'items': e.value['items'],
            },
          )
          .toList(),
      'top_categories': topCategories
          .take(10)
          .map(
            (e) => {
              'category': e.key,
              'transactions': e.value['transactions'],
              'items': e.value['items'],
            },
          )
          .toList(),
      'daily_sales': dailySales,
      'customer_items': customerItems, // NEW: Customer item details
      'trends': {
        'daily_sales': dailySalesDetailed.map(
          (key, value) => MapEntry(key, {
            'orders': value['orders'],
            'items': value['items'],
            'customers': (value['customers'] as Set).length,
          }),
        ),
        'peak_day': _findPeakDay(dailySalesDetailed),
        'avg_daily_orders': dailySalesDetailed.isNotEmpty
            ? (dailySalesDetailed.values.fold<int>(
                        0,
                        (sum, day) => sum + (day['orders'] as int),
                      ) /
                      dailySalesDetailed.length)
                  .toStringAsFixed(1)
            : '0.0',
      },
      'customer_intelligence': _calculateCustomerIntelligence(
        customerOrderDates,
        customerStats,
      ),
      'product_performance': {
        'best_selling_models':
            modelStats.entries
                .map((e) => {'model': e.key, 'count': e.value})
                .toList()
              ..sort(
                (a, b) => (b['count'] as int).compareTo(a['count'] as int),
              ),
        'category_breakdown': categoryStats,
      },
    };
  }

  Map<String, dynamic> _calculateCustomerIntelligence(
    Map<String, List<DateTime>> customerOrderDates,
    Map<String, Map<String, dynamic>> customerStats,
  ) {
    int newCustomers = 0;
    int repeatCustomers = 0;
    final newCustomersList = <Map<String, dynamic>>[];
    final repeatCustomersList = <Map<String, dynamic>>[];

    customerOrderDates.forEach((customer, dates) {
      final orderCount = dates.length;
      final items = customerStats[customer]?['items'] ?? 0;

      if (orderCount == 1) {
        newCustomers++;
        newCustomersList.add({'customer': customer, 'items': items});
      } else {
        repeatCustomers++;
        repeatCustomersList.add({
          'customer': customer,
          'orders': orderCount,
          'items': items,
        });
      }
    });

    // Sort repeat customers by order count (descending)
    repeatCustomersList.sort(
      (a, b) => (b['orders'] as int).compareTo(a['orders'] as int),
    );

    final totalCustomers = newCustomers + repeatCustomers;
    final loyaltyRate = totalCustomers > 0
        ? (repeatCustomers / totalCustomers * 100).toStringAsFixed(1)
        : '0.0';

    return {
      'new_customers': newCustomers,
      'repeat_customers': repeatCustomers,
      'loyalty_rate': loyaltyRate,
      'new_customers_list': newCustomersList,
      'repeat_customers_list': repeatCustomersList,
    };
  }

  String _normalizeCategory(String category) {
    if (category == 'Unknown') return category;

    // Convert to lowercase, replace underscores and hyphens with spaces
    String normalized = category
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();

    // Convert to title case
    return normalized
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  String _findPeakDay(Map<String, Map<String, dynamic>> dailySales) {
    if (dailySales.isEmpty) return '';

    String peakDay = '';
    int maxOrders = 0;

    dailySales.forEach((date, data) {
      final orders = data['orders'] as int;
      if (orders > maxOrders) {
        maxOrders = orders;
        peakDay = date;
      }
    });

    return peakDay;
  }

  // Inventory Report Methods

  /// Get comprehensive inventory report data
  Future<Map<String, dynamic>> getInventoryReport({
    String? category,
    String? status,
    String? location,
  }) async {
    try {
      // Get all inventory items
      Query inventoryQuery = _firestore.collection('inventory');

      if (category != null && category.isNotEmpty) {
        inventoryQuery = inventoryQuery.where(
          'equipment_category',
          isEqualTo: category,
        );
      }

      final inventorySnapshot = await inventoryQuery.get();

      // Get all transactions for movement analysis
      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      // Process inventory data
      final inventoryData = await _processInventoryData(
        inventorySnapshot,
        transactionSnapshot,
        status,
        location,
      );

      return {'success': true, 'data': inventoryData};
    } catch (e) {
      print('Error generating inventory report: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Process inventory data with current status and movement history
  Future<Map<String, dynamic>> _processInventoryData(
    QuerySnapshot inventorySnapshot,
    QuerySnapshot transactionSnapshot,
    String? statusFilter,
    String? locationFilter,
  ) async {
    final inventoryItems = <Map<String, dynamic>>[];
    final categoryStats = <String, Map<String, dynamic>>{};
    final statusStats = <String, int>{};
    final locationStats = <String, int>{};

    // Build transaction map for history (not for status calculation)
    final transactionsBySerial = <String, List<Map<String, dynamic>>>{};
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String?;
      if (serialNumber != null) {
        final normalizedSerial = serialNumber.toLowerCase();
        transactionsBySerial[normalizedSerial] ??= [];
        transactionsBySerial[normalizedSerial]!.add({'id': doc.id, ...data});
      }
    }

    // Process each inventory item
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String?;

      if (serialNumber == null) continue;

      // Get transaction history for this item (for activity tracking only)
      final normalizedSerial = serialNumber.toLowerCase();
      final itemTransactions = transactionsBySerial[normalizedSerial] ?? [];

      // Sort transactions by date (most recent first)
      itemTransactions.sort((a, b) {
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

      // Use direct status from inventory collection
      String currentStatus = data['status'] as String? ?? 'Active';
      String? currentLocation = data['location'] as String?;
      DateTime? lastActivity;

      // Get last activity from most recent transaction
      if (itemTransactions.isNotEmpty) {
        final latestTransaction = itemTransactions.first;

        // If current location is missing or Unknown, try to get from last transaction
        if (currentLocation == null ||
            currentLocation.isEmpty ||
            currentLocation == 'Unknown') {
          final transactionLoc = latestTransaction['location'] as String?;
          if (transactionLoc != null &&
              transactionLoc.isNotEmpty &&
              transactionLoc != 'Unknown') {
            currentLocation = transactionLoc;
          }
        }

        // Handle date field for last activity
        final dateValue = latestTransaction['date'];
        if (dateValue is Timestamp) {
          lastActivity = dateValue.toDate();
        } else if (dateValue is String) {
          lastActivity = DateTime.tryParse(dateValue);
        }
      }

      // Apply filters
      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          currentStatus != statusFilter) {
        continue;
      }

      if (locationFilter != null &&
          locationFilter.isNotEmpty &&
          currentLocation != locationFilter) {
        continue;
      }

      // Build item data
      final itemData = {
        'id': doc.id,
        ...data,
        'current_status': currentStatus,
        'current_location': currentLocation ?? 'Unknown',
        'last_activity': lastActivity,
        'transaction_count': itemTransactions.length,
        'transaction_history': itemTransactions
            .take(5)
            .toList(), // Last 5 transactions
      };

      inventoryItems.add(itemData);

      // Update statistics
      String category = data['equipment_category'] as String? ?? 'Unknown';
      if (category == 'Unknown' && itemTransactions.isNotEmpty) {
        final transactionCat =
            itemTransactions.first['equipment_category'] as String?;
        if (transactionCat != null &&
            transactionCat.isNotEmpty &&
            transactionCat != 'Unknown') {
          category = transactionCat;
        }
      }

      categoryStats[category] =
          categoryStats[category] ??
          {'total': 0, 'active': 0, 'stocked_out': 0};
      categoryStats[category]!['total'] =
          (categoryStats[category]!['total'] as int) + 1;

      if (currentStatus == 'Active') {
        categoryStats[category]!['active'] =
            (categoryStats[category]!['active'] as int) + 1;
      } else {
        categoryStats[category]!['stocked_out'] =
            (categoryStats[category]!['stocked_out'] as int) + 1;
      }

      statusStats[currentStatus] = (statusStats[currentStatus] ?? 0) + 1;
      locationStats[currentLocation ?? 'Unknown'] =
          (locationStats[currentLocation ?? 'Unknown'] ?? 0) + 1;
    }

    return {
      'summary': {
        'total_items': inventoryItems.length,
        'active_items': statusStats['Active'] ?? 0,
        'reserved_items': statusStats['Reserved'] ?? 0,
        'delivered_items': statusStats['Delivered'] ?? 0,
        'demo_items': statusStats['Demo'] ?? 0,
        'returned_items': statusStats['Returned'] ?? 0,
        'categories_count': categoryStats.length,
        'locations_count': locationStats.length,
      },
      'inventory_items': inventoryItems,
      'category_breakdown': categoryStats.entries
          .map(
            (e) => {
              'category': e.key,
              'total': e.value['total'],
              'active': e.value['active'],
              'stocked_out': e.value['stocked_out'],
              'active_percentage': e.value['total'] > 0
                  ? ((e.value['active'] as int) /
                            (e.value['total'] as int) *
                            100)
                        .toStringAsFixed(1)
                  : '0.0',
            },
          )
          .toList(),
      'status_breakdown': statusStats.entries
          .map((e) => {'status': e.key, 'count': e.value})
          .toList(),
      'location_breakdown': locationStats.entries
          .map((e) => {'location': e.key, 'count': e.value})
          .toList(),
    };
  }

  /// Get list of unique customers for filtering
  Future<List<String>> getCustomerList() async {
    try {
      final snapshot = await _firestore.collection('orders').get();
      final customers = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final customer = data['customer_dealer'] as String?;
        if (customer != null && customer.isNotEmpty) {
          customers.add(customer);
        }
      }

      return customers.toList()..sort();
    } catch (e) {
      print('Error fetching customer list: $e');
      return [];
    }
  }

  /// Get list of unique locations for filtering
  Future<List<String>> getLocationList() async {
    try {
      final snapshot = await _firestore.collection('transactions').get();
      final locations = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final location = data['location'] as String?;
        if (location != null && location.isNotEmpty) {
          locations.add(location);
        }
      }

      return locations.toList()..sort();
    } catch (e) {
      print('Error fetching location list: $e');
      return [];
    }
  }

  /// Get list of unique categories for filtering
  Future<List<String>> getCategoryList() async {
    try {
      final snapshot = await _firestore.collection('inventory').get();
      final categories = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final category = data['equipment_category'] as String?;
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }

      return categories.toList()..sort();
    } catch (e) {
      print('Error fetching category list: $e');
      return [];
    }
  }

  // Export Methods

  /// Export sales report to CSV
  Future<String?> exportSalesReportToCSV(
    Map<String, dynamic> reportData,
  ) async {
    try {
      final orders = reportData['orders'] as List<dynamic>? ?? [];

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Header row
        [
          'Order Number',
          'Customer Dealer',
          'Customer Client',
          'Invoice Status',
          'Delivery Status',
          'Total Items',
          'Created Date',
        ],
      ];

      // Data rows
      for (final order in orders) {
        final createdDate = order['created_date'] as Timestamp?;
        csvData.add([
          order['order_number'] ?? '',
          order['customer_dealer'] ?? '',
          order['customer_client'] ?? '',
          order['invoice_status'] ?? order['status'] ?? '',
          order['delivery_status'] ?? '',
          order['total_items'] ?? 0,
          createdDate != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(createdDate.toDate())
              : '',
        ]);
      }

      // NEW: Add customer purchase details section
      final customerItems =
          reportData['customer_items'] as Map<String, dynamic>? ?? {};
      if (customerItems.isNotEmpty) {
        // Add separator and header for customer details
        csvData.add([]); // Empty row
        csvData.add(['Customer Purchase Details']);
        csvData.add([]); // Empty row
        csvData.add([
          'Customer Name',
          'Order Number',
          'Serial Number',
          'Category',
          'Model',
          'Date',
          'Transaction ID',
        ]);

        // Sort customers by name
        final sortedCustomers = customerItems.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        // Add items for each customer
        for (final entry in sortedCustomers) {
          final customerName = entry.key;
          final items = entry.value as List<dynamic>;

          // Sort items by date (newest first)
          final sortedItems = List<Map<String, dynamic>>.from(items)
            ..sort((a, b) {
              final dateA = a['date'] as DateTime?;
              final dateB = b['date'] as DateTime?;
              if (dateA == null && dateB == null) return 0;
              if (dateA == null) return 1;
              if (dateB == null) return -1;
              return dateB.compareTo(dateA);
            });

          for (final item in sortedItems) {
            final date = item['date'] as DateTime?;
            csvData.add([
              customerName,
              item['order_number'] ?? '',
              item['serial_number'] ?? '',
              item['category'] ?? '',
              item['model'] ?? '',
              date != null ? DateFormat('yyyy-MM-dd').format(date) : '',
              item['transaction_id']?.toString() ?? '',
            ]);
          }
        }
      }

      // Add Summary Section
      final summary = reportData['summary'] as Map<String, dynamic>? ?? {};
      if (summary.isNotEmpty) {
        csvData.add([]); // Empty row
        csvData.add(['Summary Metrics']);
        csvData.add([]); // Empty row
        csvData.add(['Metric', 'Value']);
        csvData.add(['Total Orders', summary['total_orders'] ?? 0]);
        csvData.add(['Items Sold', summary['total_items_sold'] ?? 0]);
        csvData.add(['Conversion Rate', '${summary['conversion_rate'] ?? 0}%']);
        csvData.add(['Average Order Size', summary['avg_order_size'] ?? '0.0']);
      }

      // Add Sales Trends Section
      final trends = reportData['trends'] as Map<String, dynamic>? ?? {};
      if (trends.isNotEmpty) {
        csvData.add([]); // Empty row
        csvData.add(['Sales Trends']);
        csvData.add([]); // Empty row
        csvData.add(['Date', 'Orders', 'Items', 'Customers']);

        final dailySales = trends['daily_sales'] as Map<String, dynamic>? ?? {};
        final sortedDates = dailySales.keys.toList()..sort();

        for (final date in sortedDates) {
          final data = dailySales[date] as Map<String, dynamic>;
          csvData.add([
            date,
            data['orders'] ?? 0,
            data['items'] ?? 0,
            data['customers'] ?? 0,
          ]);
        }

        csvData.add([]); // Empty row
        csvData.add(['Peak Day', trends['peak_day'] ?? 'N/A']);
        csvData.add([
          'Average Daily Orders',
          trends['avg_daily_orders'] ?? '0.0',
        ]);
      }

      // Add Customer Intelligence Section
      final intelligence =
          reportData['customer_intelligence'] as Map<String, dynamic>? ?? {};
      if (intelligence.isNotEmpty) {
        csvData.add([]); // Empty row
        csvData.add(['Customer Intelligence']);
        csvData.add([]); // Empty row
        csvData.add(['Metric', 'Value']);
        csvData.add(['First-Time Buyers', intelligence['new_customers'] ?? 0]);
        csvData.add([
          'Returning Customers',
          intelligence['repeat_customers'] ?? 0,
        ]);
        csvData.add(['Loyalty Rate', '${intelligence['loyalty_rate'] ?? 0}%']);

        final newCustomersList =
            intelligence['new_customers_list'] as List? ?? [];
        final repeatCustomersList =
            intelligence['repeat_customers_list'] as List? ?? [];

        if (newCustomersList.isNotEmpty) {
          csvData.add([]); // Empty row
          csvData.add(['First-Time Buyers List']);
          csvData.add(['Customer Name', 'Items']);
          for (final customer in newCustomersList) {
            csvData.add([customer['customer'] ?? '', customer['items'] ?? 0]);
          }
        }

        if (repeatCustomersList.isNotEmpty) {
          csvData.add([]); // Empty row
          csvData.add(['Returning Customers List']);
          csvData.add(['Customer Name', 'Orders', 'Items']);
          for (final customer in repeatCustomersList) {
            csvData.add([
              customer['customer'] ?? '',
              customer['orders'] ?? 0,
              customer['items'] ?? 0,
            ]);
          }
        }
      }

      // Add Product Performance Section
      final performance =
          reportData['product_performance'] as Map<String, dynamic>? ?? {};
      if (performance.isNotEmpty) {
        csvData.add([]); // Empty row
        csvData.add(['Product Performance']);
        csvData.add([]); // Empty row

        final bestSelling = performance['best_selling_models'] as List? ?? [];
        if (bestSelling.isNotEmpty) {
          csvData.add(['Best-Selling Models']);
          csvData.add(['Model', 'Units Sold']);
          for (final product in bestSelling) {
            csvData.add([product['model'] ?? '', product['count'] ?? 0]);
          }
        }

        final categoryBreakdown =
            performance['category_breakdown'] as Map<String, dynamic>? ?? {};
        if (categoryBreakdown.isNotEmpty) {
          csvData.add([]); // Empty row
          csvData.add(['Category Mix']);
          csvData.add(['Category', 'Items', 'Sales']);
          for (final entry in categoryBreakdown.entries) {
            final data = entry.value as Map<String, dynamic>;
            csvData.add([
              entry.key,
              data['items'] ?? 0,
              data['transactions'] ?? 0,
            ]);
          }
        }
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      return await _fileSaver.saveFile(
        'sales_report_$timestamp.csv',
        csvString,
      );
    } catch (e) {
      print('Error exporting sales report to CSV: $e');
      return null;
    }
  }

  /// Export inventory report to CSV
  Future<String?> exportInventoryReportToCSV(
    Map<String, dynamic> reportData,
  ) async {
    try {
      final inventoryItems =
          reportData['inventory_items'] as List<dynamic>? ?? [];

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Header row
        [
          'Serial Number',
          'Equipment Category',
          'Model',
          'Size',
          'Current Status',
          'Current Location',
          'Last Activity',
          'Transaction Count',
        ],
      ];

      // Data rows
      for (final item in inventoryItems) {
        final lastActivity = item['last_activity'] as DateTime?;
        csvData.add([
          item['serial_number'] ?? '',
          item['equipment_category'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['current_status'] ?? '',
          item['current_location'] ?? '',
          lastActivity != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(lastActivity)
              : '',
          item['transaction_count'] ?? 0,
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      return await _fileSaver.saveFile(
        'inventory_report_$timestamp.csv',
        csvString,
      );
    } catch (e) {
      print('Error exporting inventory report to CSV: $e');
      return null;
    }
  }

  /// Export monthly activity report to CSV
  Future<String?> exportMonthlyActivityToCSV(
    Map<String, dynamic> reportData,
    List<Map<String, dynamic>> stockInItems,
    List<Map<String, dynamic>> stockOutItems,
    List<Map<String, dynamic>> remainingItems,
    Map<String, dynamic> selectedMonth,
  ) async {
    try {
      // Create comprehensive CSV data with multiple sheets in one file
      List<List<dynamic>> csvData = [];

      // Add header with report information
      csvData.add([
        'Monthly Inventory Activity Report',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
      csvData.add([
        'Month: ${selectedMonth['displayName']}',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
      csvData.add([
        'Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
      csvData.add(['', '', '', '', '', '', '']); // Empty row

      // SECTION 1: SUMMARY DATA
      csvData.add(['SUMMARY', '', '', '', '', '', '']);
      csvData.add([
        'Category',
        'Stock In',
        'Stock Out',
        'Remaining',
        '',
        '',
        '',
      ]);

      // Add summary data by category
      final categoryBreakdown =
          reportData['categoryBreakdown'] as List<dynamic>? ?? [];
      for (final item in categoryBreakdown) {
        csvData.add([
          item['category'] ?? '',
          item['stockIn'] ?? 0,
          item['stockOut'] ?? 0,
          item['remaining'] ?? 0,
          '',
          '',
          '',
        ]);
      }

      csvData.add(['', '', '', '', '', '', '']); // Empty row
      csvData.add(['', '', '', '', '', '', '']); // Empty row

      // SECTION 2: STOCK IN DETAILS
      csvData.add(['STOCK IN DETAILS', '', '', '', '', '', '']);
      csvData.add([
        'Serial Number',
        'Equipment Category',
        'Model',
        'Size',
        'Location',
        'Date',
        'Remark',
      ]);

      for (var item in stockInItems) {
        csvData.add([
          item['serial_number'] ?? '',
          item['equipment_category'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['location'] ?? '',
          item['date'] != null
              ? DateFormat(
                  'yyyy-MM-dd',
                ).format((item['date'] as Timestamp).toDate())
              : '',
          item['remark'] ?? '',
        ]);
      }

      csvData.add(['', '', '', '', '', '', '']); // Empty row
      csvData.add(['', '', '', '', '', '', '']); // Empty row

      // SECTION 3: STOCK OUT DETAILS
      csvData.add(['STOCK OUT DETAILS', '', '', '', '', '', '']);
      csvData.add([
        'Serial Number',
        'Equipment Category',
        'Model',
        'Size',
        'Customer/Dealer',
        'Date',
        'Remark',
      ]);

      for (var item in stockOutItems) {
        csvData.add([
          item['serial_number'] ?? '',
          item['equipment_category'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['customer_dealer'] ?? '',
          item['date'] != null
              ? DateFormat(
                  'yyyy-MM-dd',
                ).format((item['date'] as Timestamp).toDate())
              : '',
          item['remark'] ?? '',
        ]);
      }

      csvData.add(['', '', '', '', '', '', '']); // Empty row
      csvData.add(['', '', '', '', '', '', '']); // Empty row

      // SECTION 4: REMAINING INVENTORY
      csvData.add(['REMAINING INVENTORY', '', '', '', '', '', '']);
      csvData.add(['Equipment Category', 'Size', 'Count', '', '', '', '']);

      // Group remaining items by category and size
      final Map<String, Map<String, int>> groupedRemaining = {};
      for (var item in remainingItems) {
        final category = item['equipment_category'] ?? 'Unknown';
        final size = item['size'] ?? 'Unknown';
        final key = '$category|$size';
        groupedRemaining[key] = groupedRemaining[key] ?? {'count': 0};
        groupedRemaining[key]!['count'] =
            (groupedRemaining[key]!['count'] ?? 0) + 1;
      }

      // Sort and add to CSV
      final sortedKeys = groupedRemaining.keys.toList()..sort();
      for (final key in sortedKeys) {
        final parts = key.split('|');
        final category = parts[0];
        final size = parts.length > 1 ? parts[1] : 'Unknown';
        csvData.add([
          category,
          size,
          groupedRemaining[key]!['count'] ?? 0,
          '',
          '',
          '',
          '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final monthLabel =
          selectedMonth['displayName']?.toString().replaceAll(' ', '_') ??
          'unknown';

      return await _fileSaver.saveFile(
        'monthly_activity_${monthLabel}_$timestamp.csv',
        csvString,
      );
    } catch (e) {
      debugPrint('Error exporting monthly activity report to CSV: $e');
      return null;
    }
  }

  /// Calculate current status using enhanced logic to handle dual Stock_Out transactions
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

  // Demo Tracking Report Methods

  /// Get comprehensive demo tracking report (grouped by client/dealer)
  /// Uses demos collection for accurate demo_number and status tracking
  Future<Map<String, dynamic>> getDemoTrackingReport({
    String? customerFilter,
    String? categoryFilter,
    bool overdueOnly = false,
    int overdueThresholdDays = 30,
  }) async {
    try {
      // Query active demos from demos collection
      Query demosQuery = _firestore
          .collection('demos')
          .where('status', whereIn: ['active', 'Active']);
      final demosSnapshot = await demosQuery.get();
      // Group by client or dealer
      final groupedDemos = <String, Map<String, dynamic>>{};
      final categoryStats = <String, Map<String, dynamic>>{};
      int totalItemsOut = 0;
      int overdueCount = 0;
      int totalDaysOut = 0;
      // Fetch inventory details for enrichment
      final inventoryMap = <String, Map<String, dynamic>>{};
      // Process each active demo
      for (final demoDoc in demosSnapshot.docs) {
        final demoData = demoDoc.data() as Map<String, dynamic>;
        final demoNumber = demoData['demo_number'] as String? ?? '';
        final customerDealer =
            demoData['customer_dealer'] as String? ?? 'Unknown';
        final customerClient = demoData['customer_client'] as String? ?? '';
        final transactionIds = demoData['transaction_ids'] as List? ?? [];
        final demoDateValue = demoData['created_at'];
        // Calculate demo age
        DateTime demoDate;
        if (demoDateValue is Timestamp) {
          demoDate = demoDateValue.toDate();
        } else {
          demoDate = DateTime.now();
        }
        // Determine grouping key: client if available, otherwise dealer
        final groupKey = customerClient.isNotEmpty
            ? '$customerDealer → $customerClient'
            : customerDealer;
        // Apply customer filter
        if (customerFilter != null &&
            customerFilter.isNotEmpty &&
            customerDealer != customerFilter) {
          continue;
        }
        // Get transaction details for this demo
        final demoItems = <Map<String, dynamic>>[];
        int demoOverdueCount = 0;
        int oldestDays = 0;
        for (final transId in transactionIds) {
          // Query transaction by transaction_id
          final transQuery = await _firestore
              .collection('transactions')
              .where('transaction_id', isEqualTo: transId)
              .limit(1)
              .get();
          if (transQuery.docs.isEmpty) continue;
          final transData = transQuery.docs.first.data();
          // Only include items still in Demo status
          if (transData['status'] != 'Demo') continue;
          final serialNumber =
              transData['serial_number'] as String? ?? 'Unknown';
          String category = transData['equipment_category'] as String? ?? '';
          String model = transData['model'] as String? ?? '';
          final location = transData['location'] as String? ?? 'Demo';
          final transDateValue = transData['date'];
          // Get item sent date (use transaction date if available)
          DateTime itemDate;
          if (transDateValue is Timestamp) {
            itemDate = transDateValue.toDate();
          } else if (transDateValue is String) {
            itemDate = DateTime.tryParse(transDateValue) ?? demoDate;
          } else {
            itemDate = demoDate;
          }
          // Enrich from inventory if needed
          if (category.isEmpty || model.isEmpty) {
            if (!inventoryMap.containsKey(serialNumber)) {
              final invQuery = await _firestore
                  .collection('inventory')
                  .where('serial_number', isEqualTo: serialNumber)
                  .limit(1)
                  .get();
              if (invQuery.docs.isNotEmpty) {
                inventoryMap[serialNumber] = invQuery.docs.first.data();
              }
            }
            if (inventoryMap.containsKey(serialNumber)) {
              final invData = inventoryMap[serialNumber]!;
              category = category.isEmpty
                  ? (invData['equipment_category'] as String? ?? 'Unknown')
                  : category;
              model = model.isEmpty
                  ? (invData['model'] as String? ?? 'Unknown')
                  : model;
            }
          }
          if (category.isEmpty) category = 'Unknown';
          if (model.isEmpty) model = 'Unknown';
          // Apply category filter
          if (categoryFilter != null &&
              categoryFilter.isNotEmpty &&
              category != categoryFilter) {
            continue;
          }
          final daysOut = DateTime.now().difference(itemDate).inDays;
          final isOverdue = daysOut > overdueThresholdDays;
          // Apply overdue filter
          if (overdueOnly && !isOverdue) {
            continue;
          }
          // Track statistics
          if (daysOut > oldestDays) oldestDays = daysOut;
          if (isOverdue) demoOverdueCount++;
          totalItemsOut++;
          totalDaysOut += daysOut;
          if (isOverdue) overdueCount++;
          // Category stats
          categoryStats[category] =
              categoryStats[category] ?? {'items': 0, 'overdue': 0};
          categoryStats[category]!['items'] =
              (categoryStats[category]!['items'] as int) + 1;
          if (isOverdue) {
            categoryStats[category]!['overdue'] =
                (categoryStats[category]!['overdue'] as int) + 1;
          }
          demoItems.add({
            'serial_number': serialNumber,
            'equipment_category': category,
            'model': model,
            'demo_number': demoNumber,
            'date_sent': itemDate,
            'days_out': daysOut,
            'is_overdue': isOverdue,
            'location': location,
          });
        }
        // Skip if no items passed filters
        if (demoItems.isEmpty) continue;
        // Initialize or update group
        if (!groupedDemos.containsKey(groupKey)) {
          groupedDemos[groupKey] = {
            'group_key': groupKey,
            'customer_dealer': customerDealer,
            'customer_client': customerClient,
            'items': <Map<String, dynamic>>[],
            'total_items': 0,
            'overdue_items': 0,
            'oldest_days': 0,
            'demo_numbers': <String>{},
          };
        }
        // Add items to group
        groupedDemos[groupKey]!['items'].addAll(demoItems);
        groupedDemos[groupKey]!['total_items'] =
            (groupedDemos[groupKey]!['total_items'] as int) + demoItems.length;
        groupedDemos[groupKey]!['overdue_items'] =
            (groupedDemos[groupKey]!['overdue_items'] as int) +
            demoOverdueCount;
        if (oldestDays > (groupedDemos[groupKey]!['oldest_days'] as int)) {
          groupedDemos[groupKey]!['oldest_days'] = oldestDays;
        }
        if (demoNumber.isNotEmpty) {
          (groupedDemos[groupKey]!['demo_numbers'] as Set<String>).add(
            demoNumber,
          );
        }
      }
      // Convert grouped demos to list and sort
      final groupedDemosList = groupedDemos.values.toList();
      groupedDemosList.sort(
        (a, b) => (b['oldest_days'] as int).compareTo(a['oldest_days'] as int),
      );
      final averageDaysOut = totalItemsOut > 0
          ? (totalDaysOut / totalItemsOut).round()
          : 0;
      return {
        'success': true,
        'summary': {
          'total_items_out': totalItemsOut,
          'total_customers': groupedDemos.length,
          'overdue_count': overdueCount,
          'average_days_out': averageDaysOut,
          'overdue_threshold': overdueThresholdDays,
        },
        'grouped_demos': groupedDemosList,
        'category_breakdown':
            categoryStats.entries
                .map(
                  (e) => {
                    'category': e.key,
                    'items': e.value['items'],
                    'overdue': e.value['overdue'],
                  },
                )
                .toList()
              ..sort(
                (a, b) => (b['items'] as int).compareTo(a['items'] as int),
              ),
      };
    } catch (e) {
      print('Error generating demo tracking report: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Export demo tracking report to CSV
  Future<String?> exportDemoTrackingReportToCSV(
    Map<String, dynamic> reportData,
  ) async {
    try {
      final activeDemos = reportData['active_demos'] as List<dynamic>? ?? [];

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Header row
        [
          'Serial Number',
          'Equipment Category',
          'Model',
          'Customer (Dealer)',
          'Customer (Client)',
          'Demo Number',
          'Date Sent Out',
          'Days Out',
          'Status',
          'Location',
        ],
      ];

      // Data rows
      for (final demo in activeDemos) {
        final dateSent = demo['date_sent'] as DateTime?;
        final isOverdue = demo['is_overdue'] as bool? ?? false;

        csvData.add([
          demo['serial_number'] ?? '',
          demo['equipment_category'] ?? '',
          demo['model'] ?? '',
          demo['customer_dealer'] ?? '',
          demo['customer_client'] ?? '',
          demo['demo_number'] ?? '',
          dateSent != null ? DateFormat('yyyy-MM-dd').format(dateSent) : '',
          demo['days_out'] ?? 0,
          isOverdue ? 'OVERDUE' : 'Active',
          demo['location'] ?? '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      return await _fileSaver.saveFile(
        'demo_tracking_report_$timestamp.csv',
        csvString,
      );
    } catch (e) {
      print('Error exporting demo tracking report to CSV: $e');
      return null;
    }
  }

  /// Helper to create a QuerySnapshot-like object from a list of documents
  QuerySnapshot _createQuerySnapshot(List<DocumentSnapshot> docs) {
    return _MockQuerySnapshot(docs);
  }
}

/// Mock QuerySnapshot class to wrap batched document results
class _MockQuerySnapshot implements QuerySnapshot {
  final List<DocumentSnapshot> _docs;

  _MockQuerySnapshot(this._docs);

  @override
  List<QueryDocumentSnapshot> get docs => _docs.cast<QueryDocumentSnapshot>();

  @override
  List<DocumentChange> get docChanges => [];

  @override
  SnapshotMetadata get metadata => const _MockSnapshotMetadata();

  @override
  int get size => _docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mock SnapshotMetadata
class _MockSnapshotMetadata implements SnapshotMetadata {
  const _MockSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
