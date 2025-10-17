import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sales Report Methods

  /// Get comprehensive sales report data
  Future<Map<String, dynamic>> getSalesReport({
    DateTime? startDate,
    DateTime? endDate,
    String? customerDealer,
    String? location,
  }) async {
    try {
      // Set default date range if not provided (last 30 days)
      endDate ??= DateTime.now();
      startDate ??= endDate.subtract(const Duration(days: 30));

      // Build query for purchase orders
      Query query = _firestore.collection('purchase_orders');

      if (endDate != null) {
        query = query
            .where(
              'created_date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
            )
            .where(
              'created_date',
              isLessThanOrEqualTo: Timestamp.fromDate(endDate),
            );
      }

      if (customerDealer != null && customerDealer.isNotEmpty) {
        query = query.where('customer_dealer', isEqualTo: customerDealer);
      }

      final poSnapshot = await query.get();

      // Get all transactions for the same period
      Query transactionQuery = _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out');

      if (endDate != null) {
        transactionQuery = transactionQuery
            .where(
              'uploaded_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
            )
            .where(
              'uploaded_at',
              isLessThanOrEqualTo: Timestamp.fromDate(endDate),
            );
      }

      final transactionSnapshot = await transactionQuery.get();

      // Process sales data
      final salesData = await _processSalesData(
        poSnapshot,
        transactionSnapshot,
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

  /// Process sales data from purchase orders and transactions
  Future<Map<String, dynamic>> _processSalesData(
    QuerySnapshot poSnapshot,
    QuerySnapshot transactionSnapshot,
  ) async {
    final purchaseOrders = <Map<String, dynamic>>[];
    final customerStats = <String, Map<String, dynamic>>{};
    final locationStats = <String, Map<String, dynamic>>{};
    final dailySales = <String, int>{};
    final categoryStats = <String, Map<String, dynamic>>{};

    int totalPOs = 0;
    int invoicedPOs = 0;
    int pendingPOs = 0;
    int totalItems = 0;

    // Process purchase orders
    for (final doc in poSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final poData = {'id': doc.id, ...data};
      purchaseOrders.add(poData);

      totalPOs++;
      final status = data['status'] as String? ?? 'Pending';
      if (status == 'Invoiced') {
        invoicedPOs++;
      } else {
        pendingPOs++;
      }

      final itemCount = data['total_items'] as int? ?? 0;
      totalItems += itemCount;

      // Customer statistics
      final customer = data['customer_dealer'] as String? ?? 'Unknown';
      customerStats[customer] =
          customerStats[customer] ?? {'orders': 0, 'items': 0};
      customerStats[customer]!['orders'] =
          (customerStats[customer]!['orders'] as int) + 1;
      customerStats[customer]!['items'] =
          (customerStats[customer]!['items'] as int) + itemCount;

      // Daily sales tracking
      final createdDate = data['created_date'] as Timestamp?;
      if (createdDate != null) {
        final dateKey = DateFormat('yyyy-MM-dd').format(createdDate.toDate());
        dailySales[dateKey] = (dailySales[dateKey] ?? 0) + 1;
      }
    }

    // Process transactions for additional insights
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Location statistics
      final location = data['location'] as String? ?? 'Unknown';
      locationStats[location] =
          locationStats[location] ?? {'transactions': 0, 'items': 0};
      locationStats[location]!['transactions'] =
          (locationStats[location]!['transactions'] as int) + 1;
      locationStats[location]!['items'] =
          (locationStats[location]!['items'] as int) + 1;

      // Category statistics
      final category = data['equipment_category'] as String? ?? 'Unknown';
      categoryStats[category] =
          categoryStats[category] ?? {'transactions': 0, 'items': 0};
      categoryStats[category]!['transactions'] =
          (categoryStats[category]!['transactions'] as int) + 1;
      categoryStats[category]!['items'] =
          (categoryStats[category]!['items'] as int) + 1;
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

    return {
      'summary': {
        'total_purchase_orders': totalPOs,
        'invoiced_orders': invoicedPOs,
        'pending_orders': pendingPOs,
        'total_items_sold': totalItems,
        'conversion_rate': totalPOs > 0
            ? (invoicedPOs / totalPOs * 100).toStringAsFixed(1)
            : '0.0',
      },
      'purchase_orders': purchaseOrders,
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
    };
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
          .orderBy('uploaded_at', descending: true)
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
    final agingAnalysis = <String, int>{};

    // Build transaction map for quick lookup
    final transactionsBySerial = <String, List<Map<String, dynamic>>>{};
    for (final doc in transactionSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String?;
      if (serialNumber != null) {
        transactionsBySerial[serialNumber] ??= [];
        transactionsBySerial[serialNumber]!.add({'id': doc.id, ...data});
      }
    }

    // Process each inventory item
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final serialNumber = data['serial_number'] as String?;

      if (serialNumber == null) continue;

      // Get transaction history for this item
      final itemTransactions = transactionsBySerial[serialNumber] ?? [];
      itemTransactions.sort(
        (a, b) =>
            (b['transaction_id'] as int).compareTo(a['transaction_id'] as int),
      );

      // Determine current status
      String currentStatus = 'Unknown';
      String? currentLocation;
      DateTime? lastActivity;

      if (itemTransactions.isNotEmpty) {
        final latestTransaction = itemTransactions.first;
        final type = latestTransaction['type'] as String?;
        final status = latestTransaction['status'] as String?;
        currentLocation = latestTransaction['location'] as String?;

        if (type == 'Stock_In' && status == 'Active') {
          currentStatus = 'Active';
        } else if (type == 'Stock_Out') {
          currentStatus = status ?? 'Reserved';
        }

        final uploadedAt = latestTransaction['uploaded_at'] as Timestamp?;
        if (uploadedAt != null) {
          lastActivity = uploadedAt.toDate();
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
      final category = data['equipment_category'] as String? ?? 'Unknown';
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

      // Aging analysis
      if (lastActivity != null) {
        final daysSinceActivity = DateTime.now()
            .difference(lastActivity)
            .inDays;
        String ageGroup;
        if (daysSinceActivity <= 7) {
          ageGroup = '0-7 days';
        } else if (daysSinceActivity <= 30) {
          ageGroup = '8-30 days';
        } else if (daysSinceActivity <= 90) {
          ageGroup = '31-90 days';
        } else {
          ageGroup = '90+ days';
        }
        agingAnalysis[ageGroup] = (agingAnalysis[ageGroup] ?? 0) + 1;
      }
    }

    return {
      'summary': {
        'total_items': inventoryItems.length,
        'active_items': statusStats['Active'] ?? 0,
        'reserved_items': statusStats['Reserved'] ?? 0,
        'delivered_items': statusStats['Delivered'] ?? 0,
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
      'aging_analysis': agingAnalysis.entries
          .map((e) => {'age_group': e.key, 'count': e.value})
          .toList(),
    };
  }

  /// Get list of unique customers for filtering
  Future<List<String>> getCustomerList() async {
    try {
      final snapshot = await _firestore.collection('purchase_orders').get();
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
      final purchaseOrders =
          reportData['purchase_orders'] as List<dynamic>? ?? [];

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Header row
        [
          'PO Number',
          'Customer Dealer',
          'Customer Client',
          'Status',
          'Total Items',
          'Created Date',
        ],
      ];

      // Data rows
      for (final po in purchaseOrders) {
        final createdDate = po['created_date'] as Timestamp?;
        csvData.add([
          po['po_number'] ?? '',
          po['customer_dealer'] ?? '',
          po['customer_client'] ?? '',
          po['status'] ?? '',
          po['total_items'] ?? 0,
          createdDate != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(createdDate.toDate())
              : '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/sales_report_$timestamp.csv');
      await file.writeAsString(csvString);

      return file.path;
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
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/inventory_report_$timestamp.csv');
      await file.writeAsString(csvString);

      return file.path;
    } catch (e) {
      print('Error exporting inventory report to CSV: $e');
      return null;
    }
  }
}
