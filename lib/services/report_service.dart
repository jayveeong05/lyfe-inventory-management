import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get appropriate directory for saving CSV files based on platform
  ///
  /// - Desktop: Uses application documents directory
  /// - Mobile: Uses downloads directory (user accessible) with permission handling
  Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // For mobile platforms, request storage permission first
      try {
        if (Platform.isAndroid) {
          // For Android, try to access public Downloads directory
          debugPrint('🤖 Android detected - trying public Downloads access...');

          // Approach 1: Try public Downloads directory directly
          try {
            final publicDownloads = Directory('/storage/emulated/0/Download');
            debugPrint('📁 Testing public Downloads: ${publicDownloads.path}');

            // Test write access by creating a test file
            final testFile = File('${publicDownloads.path}/.test_write_access');
            await testFile.writeAsString('test');
            await testFile.delete();

            debugPrint('✅ Public Downloads directory is writable!');
            return publicDownloads;
          } catch (e) {
            debugPrint('❌ Public Downloads not accessible: $e');
          }

          // Approach 2: Request storage permission and try again
          debugPrint('🔍 Requesting storage permission...');
          final permission = await Permission.storage.request();
          debugPrint('📋 Permission status: ${permission.toString()}');

          if (permission.isGranted) {
            try {
              final publicDownloads = Directory('/storage/emulated/0/Download');
              final testFile = File(
                '${publicDownloads.path}/.test_write_access',
              );
              await testFile.writeAsString('test');
              await testFile.delete();

              debugPrint('✅ Public Downloads accessible after permission!');
              return publicDownloads;
            } catch (e) {
              debugPrint('❌ Still cannot access public Downloads: $e');
            }
          } else {
            debugPrint('❌ Storage permission denied: ${permission.toString()}');
          }

          // Final fallback to external storage directory
          debugPrint('🔄 Falling back to external storage directory...');
          final directory = await getExternalStorageDirectory();
          if (directory != null) {
            // Create a subdirectory for our app
            final appDirectory = Directory(
              '${directory.path}/InventoryReports',
            );
            if (!await appDirectory.exists()) {
              await appDirectory.create(recursive: true);
            }
            debugPrint(
              '📂 Using external storage subdirectory: ${appDirectory.path}',
            );
            return appDirectory;
          }
        } else if (Platform.isIOS) {
          // On iOS, use application documents directory (accessible via Files app)
          final iosDirectory = await getApplicationDocumentsDirectory();
          debugPrint('🍎 Using iOS documents directory: ${iosDirectory.path}');
          return iosDirectory;
        }
      } catch (e) {
        // If external storage fails, fall back to application documents
        debugPrint('❌ External storage access failed: $e');
      }
    }

    // Desktop platforms or fallback: use application documents directory
    final fallbackDirectory = await getApplicationDocumentsDirectory();
    debugPrint(
      '💻 Using fallback documents directory: ${fallbackDirectory.path}',
    );
    return fallbackDirectory;
  }

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

      // Get all transactions for the same period
      Query transactionQuery = _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out');

      transactionQuery = transactionQuery
          .where(
            'uploaded_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            'uploaded_at',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          );

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

  /// Process sales data from orders and transactions
  Future<Map<String, dynamic>> _processSalesData(
    QuerySnapshot orderSnapshot,
    QuerySnapshot transactionSnapshot,
  ) async {
    final orders = <Map<String, dynamic>>[];
    final customerStats = <String, Map<String, dynamic>>{};
    final locationStats = <String, Map<String, dynamic>>{};
    final dailySales = <String, int>{};
    final categoryStats = <String, Map<String, dynamic>>{};

    int totalOrders = 0;
    int invoicedOrders = 0;
    int pendingOrders = 0;
    int totalItems = 0;

    // Process orders
    for (final doc in orderSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final orderData = {'id': doc.id, ...data};
      orders.add(orderData);

      totalOrders++;
      final status = data['status'] as String? ?? 'Pending';
      if (status == 'Invoiced') {
        invoicedOrders++;
      } else {
        pendingOrders++;
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
        'total_orders': totalOrders,
        'invoiced_orders': invoicedOrders,
        'pending_orders': pendingOrders,
        'total_items_sold': totalItems,
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
        currentLocation ??= latestTransaction['location'] as String?;

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
          'Status',
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
          order['status'] ?? '',
          order['total_items'] ?? 0,
          createdDate != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(createdDate.toDate())
              : '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Debug: Check CSV content
      debugPrint('📊 CSV Data Rows: ${csvData.length}');
      debugPrint('📝 CSV Content Length: ${csvString.length} characters');
      debugPrint(
        '🔍 CSV Preview (first 200 chars): ${csvString.length > 200 ? "${csvString.substring(0, 200)}..." : csvString}',
      );

      // Save to file using platform-appropriate directory
      final directory = await _getExportDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/sales_report_$timestamp.csv');

      // Write with explicit UTF-8 encoding
      await file.writeAsString(csvString, encoding: utf8);

      // Debug: Verify file was created
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      debugPrint('✅ File created: $fileExists');
      debugPrint('📏 File size: $fileSize bytes');
      debugPrint('📂 File path: ${file.path}');

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

      // Debug: Check CSV content
      debugPrint('📊 Inventory CSV Data Rows: ${csvData.length}');
      debugPrint(
        '📝 Inventory CSV Content Length: ${csvString.length} characters',
      );
      debugPrint(
        '🔍 Inventory CSV Preview (first 200 chars): ${csvString.length > 200 ? "${csvString.substring(0, 200)}..." : csvString}',
      );

      // Save to file using platform-appropriate directory
      final directory = await _getExportDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/inventory_report_$timestamp.csv');

      // Write with explicit UTF-8 encoding
      await file.writeAsString(csvString, encoding: utf8);

      // Debug: Verify file was created
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      debugPrint('✅ Inventory file created: $fileExists');
      debugPrint('📏 Inventory file size: $fileSize bytes');
      debugPrint('📂 Inventory file path: ${file.path}');

      return file.path;
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
      csvData.add(['Month: ${selectedMonth['label']}', '', '', '', '', '', '']);
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
      final summaryData =
          reportData['summaryData'] as Map<String, dynamic>? ?? {};
      summaryData.forEach((category, data) {
        if (data is Map<String, dynamic>) {
          csvData.add([
            category,
            data['stockIn'] ?? 0,
            data['stockOut'] ?? 0,
            data['remaining'] ?? 0,
            '',
            '',
            '',
          ]);
        }
      });

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
          item['serialNumber'] ?? '',
          item['equipmentCategory'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['location'] ?? '',
          item['createdAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd',
                ).format((item['createdAt'] as Timestamp).toDate())
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
          item['serialNumber'] ?? '',
          item['equipmentCategory'] ?? '',
          item['model'] ?? '',
          item['size'] ?? '',
          item['customerDealer'] ?? '',
          item['createdAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd',
                ).format((item['createdAt'] as Timestamp).toDate())
              : '',
          item['remark'] ?? '',
        ]);
      }

      csvData.add(['', '', '', '', '', '', '']); // Empty row
      csvData.add(['', '', '', '', '', '', '']); // Empty row

      // SECTION 4: REMAINING INVENTORY
      csvData.add(['REMAINING INVENTORY', '', '', '', '', '', '']);
      csvData.add(['Equipment Category', 'Size', 'Count', '', '', '', '']);

      for (var item in remainingItems) {
        csvData.add([
          item['category'] ?? '',
          item['size'] ?? '',
          item['count'] ?? 0,
          '',
          '',
          '',
          '',
        ]);
      }

      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(csvData);

      // Debug: Check CSV content
      debugPrint('📊 Monthly Activity CSV Data Rows: ${csvData.length}');
      debugPrint(
        '📝 Monthly Activity CSV Content Length: ${csvString.length} characters',
      );
      debugPrint(
        '🔍 Monthly Activity CSV Preview (first 200 chars): ${csvString.length > 200 ? "${csvString.substring(0, 200)}..." : csvString}',
      );

      // Save to file using platform-appropriate directory
      final directory = await _getExportDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final monthLabel =
          selectedMonth['label']?.toString().replaceAll(' ', '_') ?? 'unknown';
      final file = File(
        '${directory.path}/monthly_activity_${monthLabel}_$timestamp.csv',
      );

      // Write with explicit UTF-8 encoding
      await file.writeAsString(csvString, encoding: utf8);

      // Debug: Verify file was created
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      debugPrint('✅ Monthly Activity file created: $fileExists');
      debugPrint('📏 Monthly Activity file size: $fileSize bytes');
      debugPrint('📂 Monthly Activity file path: ${file.path}');

      return file.path;
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
}
