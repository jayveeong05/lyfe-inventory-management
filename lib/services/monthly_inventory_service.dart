import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyInventoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for cumulative calculations to improve performance
  static final Map<String, Map<String, int>> _cumulativeStockInCache = {};
  static final Map<String, Map<String, int>> _cumulativeStockOutCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  /// Clear cache for performance optimization (call when data changes)
  static void clearCache() {
    _cumulativeStockInCache.clear();
    _cumulativeStockOutCache.clear();
    _cacheTimestamps.clear();
  }

  /// Normalize date field to DateTime (handles both Timestamp and String formats)
  DateTime? _normalizeDate(dynamic dateField) {
    if (dateField is Timestamp) {
      return dateField.toDate();
    } else if (dateField is String) {
      try {
        return DateTime.parse(dateField);
      } catch (e) {
        return null; // Invalid date string
      }
    }
    return null; // Unsupported date type
  }

  /// Normalize category name to handle spaces and underscores consistently
  String _normalizeCategory(String? category) {
    if (category == null || category.isEmpty) {
      return 'Unknown';
    }

    // Convert to lowercase and replace underscores with spaces for consistency
    return category.toLowerCase().replaceAll('_', ' ');
  }

  /// Get the delivery transaction (Stock_Out with 'Delivered' status) from a list of transactions
  Map<String, dynamic>? _getDeliveryTransaction(
    List<Map<String, dynamic>> transactions,
  ) {
    // Find the most recent Stock_Out transaction with 'Delivered' status
    Map<String, dynamic>? deliveryTransaction;
    DateTime? latestDate;

    for (final transaction in transactions) {
      final type = transaction['type'] as String?;
      final status = transaction['status'] as String?;
      // Only consider Stock_Out transactions with Delivered status
      if (type == 'Stock_Out' && status == 'Delivered') {
        final date = _normalizeDate(transaction['date']);
        if (date != null) {
          if (latestDate == null || date.isAfter(latestDate)) {
            latestDate = date;
            deliveryTransaction = transaction;
          }
        }
      }
    }

    return deliveryTransaction;
  }

  /// Get monthly inventory activity data
  Future<Map<String, dynamic>> getMonthlyInventoryActivity({
    required int year,
    required int month,
  }) async {
    try {
      // Calculate date range for the month
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

      // Get ALL stock in data (for summary calculation)
      final allStockInData = await _getAllStockInData(startOfMonth, endOfMonth);

      // Get ALL stock out data (for summary calculation)
      final allStockOutData = await _getAllStockOutData(
        startOfMonth,
        endOfMonth,
      );

      // Get stock in data by size (for size breakdown - excludes Others)
      final stockInDataBySize = await _getStockInData(startOfMonth, endOfMonth);

      // Get stock out data by size (for size breakdown - excludes Others)
      final stockOutDataBySize = await _getStockOutData(
        startOfMonth,
        endOfMonth,
      );

      // Calculate remaining amounts (cumulative from beginning until end of selected month)
      final remainingData = await _calculateCumulativeRemainingAmounts(
        endOfMonth,
      );

      // Get size breakdown (using size-filtered data)
      final sizeBreakdown = _getSizeBreakdown(
        stockInDataBySize,
        stockOutDataBySize,
        remainingData,
      );

      // Get category breakdown
      final categoryBreakdown = await _getCategoryBreakdown(
        startOfMonth,
        endOfMonth,
      );

      return {
        'success': true,
        'data': {
          'year': year,
          'month': month,
          'monthName': _getMonthName(month),
          'stockIn': stockInDataBySize,
          'stockOut': stockOutDataBySize,
          'remaining': remainingData,
          'sizeBreakdown': sizeBreakdown,
          'categoryBreakdown': categoryBreakdown,
          'summary': {
            'totalStockIn': allStockInData.values.fold<int>(
              0,
              (sum, count) => sum + (count),
            ),
            'totalStockOut': allStockOutData.values.fold<int>(
              0,
              (sum, count) => sum + (count),
            ),
            'totalRemaining': remainingData.values.fold<int>(
              0,
              (sum, count) => sum + (count),
            ),
          },
        },
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to get monthly inventory activity: ${e.toString()}',
      };
    }
  }

  /// Get stock in data from inventory collection for the specified month
  Future<Map<String, int>> _getStockInData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get all inventory records and filter client-side to handle mixed date formats
    final snapshot = await _firestore.collection('inventory').get();

    Map<String, int> stockInBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // Normalize date field to DateTime for comparison
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null) continue;

      // Filter by date range
      if (itemDate.isBefore(startOfMonth) || itemDate.isAfter(endOfMonth)) {
        continue;
      }

      final category = data['equipment_category'] as String? ?? 'Unknown';
      final size = data['size'] as String? ?? '';

      // Skip items from "Others" category as they don't have meaningful sizes
      if (category.toLowerCase() == 'others') {
        continue;
      }

      // Only include Interactive Flat Panel items with actual sizes,
      // or items with unknown/missing category that have sizes
      String displaySize;

      if (category.toLowerCase() == 'interactive flat panel' ||
          category.toLowerCase() == 'ifp') {
        // IFP items: use actual size or 'Unknown' if no size
        displaySize = size.isEmpty ? 'Unknown' : size;
      } else if (category.toLowerCase() == 'unknown' && size.isNotEmpty) {
        // Unknown category items with size: use actual size
        displaySize = size;
      } else {
        // Non-IFP items without proper size: group as 'Unknown'
        displaySize = 'Unknown';
      }

      stockInBySize[displaySize] = (stockInBySize[displaySize] ?? 0) + 1;
    }

    return stockInBySize;
  }

  /// Get ALL stock in data (including Others category) for summary calculation
  Future<Map<String, int>> _getAllStockInData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get all inventory records and filter client-side to handle mixed date formats
    final snapshot = await _firestore.collection('inventory').get();

    Map<String, int> stockInBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // Normalize date field to DateTime for comparison
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null) continue;

      // Filter by date range
      if (itemDate.isBefore(startOfMonth) || itemDate.isAfter(endOfMonth)) {
        continue;
      }

      final category = data['equipment_category'] as String? ?? 'Unknown';
      final size = data['size'] as String? ?? '';

      // Include ALL items for summary calculation
      String displayKey;
      if (category.toLowerCase() == 'others') {
        displayKey = 'Others'; // Group Others by category
      } else {
        displayKey = size.isEmpty ? 'Unknown' : size;
      }

      stockInBySize[displayKey] = (stockInBySize[displayKey] ?? 0) + 1;
    }

    return stockInBySize;
  }

  /// Get detailed stock in items for the specified month
  /// Handles mixed date formats (Timestamp and String)
  Future<List<Map<String, dynamic>>> getDetailedStockInData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get all inventory items (can't filter by date at DB level due to mixed formats)
    final snapshot = await _firestore.collection('inventory').get();

    List<Map<String, dynamic>> items = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // Normalize date field to DateTime for comparison
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null) continue;

      // Filter by date range
      if (itemDate.isBefore(startOfMonth) || itemDate.isAfter(endOfMonth)) {
        continue;
      }

      items.add({
        'id': doc.id,
        'serial_number': data['serial_number'] ?? 'N/A',
        'equipment_category': data['equipment_category'] ?? 'N/A',
        'model': data['model'] ?? 'N/A',
        'size': data['size'] ?? 'Unknown',
        'batch': data['batch'] ?? 'N/A',
        'date': data['date'],
        'remark': data['remark'] ?? '',
        'source': data['source'] ?? 'Manual',
      });
    }

    // Sort by date (most recent first)
    items.sort((a, b) {
      final aDate = _normalizeDate(a['date']) ?? DateTime.now();
      final bDate = _normalizeDate(b['date']) ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    return items;
  }

  /// Get stock out data from transactions collection for the specified month
  /// Uses direct status field to find delivered items
  Future<Map<String, int>> _getStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Fetch all inventory and all transactions at once (optimized!)
    final futures = await Future.wait([
      _firestore.collection('inventory').get(),
      _firestore.collection('transactions').get(),
    ]);

    final inventorySnapshot = futures[0];
    final transactionSnapshot = futures[1];

    // Group transactions by serial number for quick lookup
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

    Map<String, int> stockOutBySize = {};

    // Check each inventory item to see if it was delivered in the specified month
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data();
      final serialNumber = data['serial_number'] as String?;
      final category = data['equipment_category'] as String? ?? 'Unknown';
      final size = data['size'] as String? ?? '';

      if (serialNumber == null) continue;

      // Use direct status field
      final status = data['status'] as String? ?? 'Active';

      // Only count items that are currently delivered
      if (status == 'Delivered') {
        // Get transactions for this item from our pre-fetched map
        final normalizedSerial = serialNumber.toLowerCase();
        final transactions = transactionsBySerial[normalizedSerial] ?? [];

        // Find the delivery transaction
        final deliveryTransaction = _getDeliveryTransaction(transactions);

        if (deliveryTransaction != null) {
          final deliveryDate = _normalizeDate(deliveryTransaction['date']);
          if (deliveryDate != null &&
              !deliveryDate.isBefore(startOfMonth) &&
              !deliveryDate.isAfter(endOfMonth)) {
            // Skip items from "Others" category as they don't have meaningful sizes
            if (category.toLowerCase() != 'others') {
              String displaySize;
              if (category.toLowerCase() == 'interactive flat panel' ||
                  category.toLowerCase() == 'ifp') {
                displaySize = size.isEmpty ? 'Unknown' : size;
              } else if (category.toLowerCase() == 'unknown' &&
                  size.isNotEmpty) {
                displaySize = size;
              } else {
                displaySize = 'Unknown';
              }

              stockOutBySize[displaySize] =
                  (stockOutBySize[displaySize] ?? 0) + 1;
            }
          }
        }
      }
    }

    return stockOutBySize;
  }

  /// Get ALL stock out data (including Others category) for summary calculation
  /// Uses direct status field to find delivered items
  Future<Map<String, int>> _getAllStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Fetch all inventory and all transactions at once (optimized!)
    final futures = await Future.wait([
      _firestore.collection('inventory').get(),
      _firestore.collection('transactions').get(),
    ]);

    final inventorySnapshot = futures[0];
    final transactionSnapshot = futures[1];

    // Group transactions by serial number for quick lookup
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

    Map<String, int> stockOutBySize = {};

    // Check each inventory item to see if it was delivered in the specified month
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data();
      final serialNumber = data['serial_number'] as String?;
      final category = _normalizeCategory(
        data['equipment_category'] as String?,
      );

      if (serialNumber == null) continue;

      // Use direct status field
      final status = data['status'] as String? ?? 'Active';

      // Only count items that are currently delivered
      if (status == 'Delivered') {
        // Get transactions for this item from our pre-fetched map
        final normalizedSerial = serialNumber.toLowerCase();
        final transactions = transactionsBySerial[normalizedSerial] ?? [];

        // Find the delivery transaction
        final deliveryTransaction = _getDeliveryTransaction(transactions);

        if (deliveryTransaction != null) {
          final deliveryDate = _normalizeDate(deliveryTransaction['date']);
          if (deliveryDate != null &&
              !deliveryDate.isBefore(startOfMonth) &&
              !deliveryDate.isAfter(endOfMonth)) {
            String displayKey;
            if (category == 'others') {
              displayKey = 'Others'; // Group Others by category
              stockOutBySize[displayKey] =
                  (stockOutBySize[displayKey] ?? 0) + 1;
            } else {
              // For non-Others, get size from inventory data
              final size = data['size'] as String? ?? '';
              displayKey = size.isEmpty ? 'Unknown' : size;
              stockOutBySize[displayKey] =
                  (stockOutBySize[displayKey] ?? 0) + 1;
            }
          }
        }
      }
    }

    return stockOutBySize;
  }

  /// Get detailed stock out items for the specified month
  /// Uses direct status field to show delivered items
  /// Gets size information directly from inventory collection
  Future<List<Map<String, dynamic>>> getDetailedStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Fetch all inventory and all transactions at once (optimized!)
    final futures = await Future.wait([
      _firestore.collection('inventory').get(),
      _firestore.collection('transactions').get(),
    ]);

    final inventorySnapshot = futures[0];
    final transactionSnapshot = futures[1];

    // Group transactions by serial number for quick lookup
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

    List<Map<String, dynamic>> items = [];

    // Check each inventory item to see if it was delivered in the specified month
    for (final doc in inventorySnapshot.docs) {
      final inventoryData = doc.data();
      final serialNumber = inventoryData['serial_number'] as String?;

      if (serialNumber == null) continue;

      // Use direct status field
      final status = inventoryData['status'] as String? ?? 'Active';

      // Only include items that are currently "Delivered"
      if (status != 'Delivered') continue;

      // Get transactions for this item from our pre-fetched map
      final normalizedSerial = serialNumber.toLowerCase();
      final transactions = transactionsBySerial[normalizedSerial] ?? [];

      // Find the delivery transaction (Stock_Out with "Delivered" status)
      Map<String, dynamic>? deliveryTransaction;
      for (final transaction in transactions) {
        if (transaction['type'] == 'Stock_Out' &&
            transaction['status'] == 'Delivered') {
          deliveryTransaction = transaction;
          break;
        }
      }

      if (deliveryTransaction == null) continue;

      // Check if the delivery happened within the specified month
      DateTime? deliveryDate = _normalizeDate(deliveryTransaction['date']);
      if (deliveryDate == null) continue;

      if (deliveryDate.isBefore(startOfMonth) ||
          deliveryDate.isAfter(endOfMonth)) {
        continue;
      }

      // Use inventory data for size and other information (more reliable)
      items.add({
        'id': deliveryTransaction['id'],
        'transaction_id': deliveryTransaction['transaction_id'] ?? 0,
        'serial_number': serialNumber,
        'equipment_category': inventoryData['equipment_category'] ?? 'N/A',
        'model':
            inventoryData['model'] ?? deliveryTransaction['model'] ?? 'N/A',
        'size':
            inventoryData['size'] ??
            'Unknown', // Get size directly from inventory
        'quantity': deliveryTransaction['quantity'] ?? 1,
        'date': deliveryTransaction['date'],
        'status': deliveryTransaction['status'],
        'customer_dealer': deliveryTransaction['customer_dealer'] ?? 'N/A',
        'customer_client': deliveryTransaction['customer_client'] ?? 'N/A',
        'location': deliveryTransaction['location'] ?? 'N/A',
      });
    }

    // Sort by date (most recent first)
    items.sort((a, b) {
      final aDate = _normalizeDate(a['date']) ?? DateTime.now();
      final bDate = _normalizeDate(b['date']) ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    return items;
  }

  /// Get size information from inventory based on serial number
  /// Returns null for "Others" category items to exclude them from size breakdown
  Future<String?> _getSizeFromSerialNumber(String serialNumber) async {
    try {
      final snapshot = await _firestore
          .collection('inventory')
          .where('serial_number', isEqualTo: serialNumber)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final category = data['equipment_category'] as String? ?? 'Unknown';

        // Return null for "Others" category to exclude from size breakdown
        if (category.toLowerCase() == 'others') {
          return null;
        }

        final size = data['size'] as String? ?? '';

        // Apply consistent category logic
        if (category.toLowerCase() == 'interactive flat panel' ||
            category.toLowerCase() == 'ifp') {
          // IFP items: use actual size or 'Unknown' if no size
          return size.isEmpty ? 'Unknown' : size;
        } else if (category.toLowerCase() == 'unknown' && size.isNotEmpty) {
          // Unknown category items with size: use actual size
          return size;
        } else {
          // Non-IFP items without proper size: group as 'Unknown'
          return 'Unknown';
        }
      }
    } catch (e) {
      // If error, return Unknown
    }
    return 'Unknown';
  }

  /// Calculate cumulative remaining amounts from beginning until specified date (OPTIMIZED)
  Future<Map<String, int>> _calculateCumulativeRemainingAmounts(
    DateTime endDate,
  ) async {
    try {
      final cacheKey = '${endDate.year}-${endDate.month}';

      // Check if we have cached data that's still valid (within 5 minutes)
      if (_cacheTimestamps.containsKey(cacheKey)) {
        final cacheTime = _cacheTimestamps[cacheKey]!;
        final now = DateTime.now();
        if (now.difference(cacheTime).inMinutes < 5) {
          // For now, skip cache and always use fresh 1+1 logic calculation
          // TODO: Implement proper caching for 1+1 logic results
        }
      }

      // Use optimized incremental calculation instead of fetching all data
      final result = await _calculateCumulativeRemainingOptimized(endDate);

      // Cache the results
      _cacheTimestamps[cacheKey] = DateTime.now();

      return result;
    } catch (e) {
      // Fallback to simple calculation for current month only if optimization fails
      return await _calculateCurrentMonthRemaining(endDate);
    }
  }

  /// Optimized cumulative calculation using 1+1 logic
  Future<Map<String, int>> _calculateCumulativeRemainingOptimized(
    DateTime endDate,
  ) async {
    // Use 1+1 logic: count items that are currently active up to the specified date
    return await _calculateRemainingUsing1Plus1Logic(endDate);
  }

  /// Calculate remaining using direct status field: counts items that are currently active
  Future<Map<String, int>> _calculateRemainingUsing1Plus1Logic(
    DateTime endDate,
  ) async {
    // Get all inventory items (no need to fetch transactions!)
    final inventorySnapshot = await _firestore.collection('inventory').get();

    Map<String, int> remainingBySize = {};

    // Check each inventory item to see if it's currently active
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data();
      final category = data['equipment_category'] as String? ?? 'Unknown';
      final size = data['size'] as String? ?? '';

      // Check if inventory item was created before or on the end date
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null || itemDate.isAfter(endDate)) {
        continue; // Skip items created after the end date
      }

      // Use direct status from inventory collection (single source of truth)
      final status = data['status'] as String? ?? 'Active';

      // Only count items that are currently active
      if (status == 'Active') {
        // Skip items from "Others" category as they don't have meaningful sizes
        if (category.toLowerCase() != 'others') {
          String displaySize;
          if (category.toLowerCase() == 'interactive flat panel' ||
              category.toLowerCase() == 'ifp') {
            displaySize = size.isEmpty ? 'Unknown' : size;
          } else if (category.toLowerCase() == 'unknown' && size.isNotEmpty) {
            displaySize = size;
          } else {
            displaySize = 'Unknown';
          }

          remainingBySize[displaySize] =
              (remainingBySize[displaySize] ?? 0) + 1;
        }
      }
    }

    return remainingBySize;
  }

  /// Fallback: Calculate remaining for current month only using 1+1 logic
  Future<Map<String, int>> _calculateCurrentMonthRemaining(
    DateTime endDate,
  ) async {
    // Use the same 1+1 logic as the optimized method
    return await _calculateRemainingUsing1Plus1Logic(endDate);
  }

  /// Get size breakdown with detailed information
  /// Filters out 'Unknown' size items as they should not appear in Panel Size breakdown
  List<Map<String, dynamic>> _getSizeBreakdown(
    Map<String, int> stockIn,
    Map<String, int> stockOut,
    Map<String, int> remaining,
  ) {
    // Include all sizes from stockIn, stockOut, AND remaining
    final allSizes = <String>{
      ...stockIn.keys,
      ...stockOut.keys,
      ...remaining.keys,
    };

    // Filter out 'Unknown' size items from Panel Size breakdown
    // Panel Size breakdown should only show IFP items with actual sizes (65 Inch, 75 Inch, etc.)
    final filteredSizes = allSizes.where((size) => size != 'Unknown').toSet();

    return filteredSizes
        .map(
          (size) => {
            'size': size,
            'stockIn': stockIn[size] ?? 0,
            'stockOut': stockOut[size] ?? 0,
            'remaining': remaining[size] ?? 0,
          },
        )
        .toList()
      ..sort((a, b) => (a['size'] as String).compareTo(b['size'] as String));
  }

  /// Get category breakdown based on actual data
  Future<List<Map<String, dynamic>>> _getCategoryBreakdown(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get category-based data
    final stockInByCategory = await _getStockInDataByCategory(
      startOfMonth,
      endOfMonth,
    );
    final stockOutByCategory = await _getStockOutDataByCategory(
      startOfMonth,
      endOfMonth,
    );
    final remainingByCategory = await _getRemainingDataByCategory(endOfMonth);

    // Combine all categories
    final allCategories = <String>{
      ...stockInByCategory.keys,
      ...stockOutByCategory.keys,
      ...remainingByCategory.keys,
    };

    return allCategories.map((category) {
      return {
        'category': category,
        'stockIn': stockInByCategory[category] ?? 0,
        'stockOut': stockOutByCategory[category] ?? 0,
        'remaining': remainingByCategory[category] ?? 0,
      };
    }).toList()..sort(
      (a, b) => (a['category'] as String).compareTo(b['category'] as String),
    );
  }

  /// Get stock in data grouped by category
  Future<Map<String, int>> _getStockInDataByCategory(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get all inventory records and filter client-side to handle mixed date formats
    final snapshot = await _firestore.collection('inventory').get();

    Map<String, int> stockInData = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // Normalize date field to DateTime for comparison
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null) continue;

      // Filter by date range
      if (itemDate.isBefore(startOfMonth) || itemDate.isAfter(endOfMonth)) {
        continue;
      }

      final category = _normalizeCategory(
        data['equipment_category'] as String?,
      );
      stockInData[category] = (stockInData[category] ?? 0) + 1;
    }

    return stockInData;
  }

  /// Get stock out data grouped by category
  /// Uses direct status field to find delivered items
  Future<Map<String, int>> _getStockOutDataByCategory(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    // Get all inventory items and all transactions
    final futures = await Future.wait([
      _firestore.collection('inventory').get(),
      _firestore.collection('transactions').get(),
    ]);

    final inventorySnapshot = futures[0];
    final transactionSnapshot = futures[1];

    // Group transactions by serial number for quick lookup
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

    Map<String, int> stockOutData = {};

    // Check each inventory item to see if it was delivered in the specified month
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data();
      final serialNumber = data['serial_number'] as String?;
      final category = _normalizeCategory(
        data['equipment_category'] as String?,
      );

      if (serialNumber == null) continue;

      // Use direct status field (single source of truth)
      final status = data['status'] as String? ?? 'Active';

      // Only count items that are currently delivered
      if (status == 'Delivered') {
        // Get transactions from pre-fetched map
        final normalizedSerial = serialNumber.toLowerCase();
        final transactions = transactionsBySerial[normalizedSerial] ?? [];

        // Check if the delivery happened within the specified month
        final deliveryTransaction = _getDeliveryTransaction(transactions);
        if (deliveryTransaction != null) {
          final deliveryDate = _normalizeDate(deliveryTransaction['date']);
          if (deliveryDate != null &&
              !deliveryDate.isBefore(startOfMonth) &&
              !deliveryDate.isAfter(endOfMonth)) {
            stockOutData[category] = (stockOutData[category] ?? 0) + 1;
          }
        }
      }
    }

    return stockOutData;
  }

  /// Get remaining data grouped by category (cumulative)
  /// Uses direct status field: counts items that are currently active
  Future<Map<String, int>> _getRemainingDataByCategory(DateTime endDate) async {
    // Get all inventory items (no need for transactions!)
    final inventorySnapshot = await _firestore.collection('inventory').get();

    Map<String, int> remainingByCategory = {};

    // Check each inventory item to see if it's currently active
    for (final doc in inventorySnapshot.docs) {
      final data = doc.data();
      final category = _normalizeCategory(
        data['equipment_category'] as String?,
      );

      // Check if inventory item was created before or on the end date
      DateTime? itemDate = _normalizeDate(data['date']);
      if (itemDate == null || itemDate.isAfter(endDate)) {
        continue; // Skip items created after the end date
      }

      // Use direct status from inventory collection (single source of truth)
      final status = data['status'] as String? ?? 'Active';

      // Only count items that are currently active
      if (status == 'Active') {
        remainingByCategory[category] =
            (remainingByCategory[category] ?? 0) + 1;
      }
    }

    return remainingByCategory;
  }

  /// Get month name from month number
  String _getMonthName(int month) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return monthNames[month - 1];
  }

  /// Get available months with data
  Future<List<Map<String, dynamic>>> getAvailableMonths() async {
    try {
      // Get earliest and latest dates from both collections
      final inventorySnapshot = await _firestore
          .collection('inventory')
          .orderBy('date')
          .limit(1)
          .get();

      final transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('date')
          .limit(1)
          .get();

      DateTime? earliestDate;

      if (inventorySnapshot.docs.isNotEmpty) {
        final timestamp =
            inventorySnapshot.docs.first.data()['date'] as Timestamp?;
        if (timestamp != null) {
          earliestDate = timestamp.toDate();
        }
      }

      if (transactionSnapshot.docs.isNotEmpty) {
        final timestamp =
            transactionSnapshot.docs.first.data()['date'] as Timestamp?;
        if (timestamp != null) {
          final transactionDate = timestamp.toDate();
          if (earliestDate == null || transactionDate.isBefore(earliestDate)) {
            earliestDate = transactionDate;
          }
        }
      }

      earliestDate ??= DateTime.now();

      // Generate list of months from earliest date to current month
      final now = DateTime.now();
      final months = <Map<String, dynamic>>[];

      DateTime current = DateTime(earliestDate.year, earliestDate.month);
      final currentMonth = DateTime(now.year, now.month);

      while (current.isBefore(currentMonth) ||
          current.isAtSameMomentAs(currentMonth)) {
        months.add({
          'year': current.year,
          'month': current.month,
          'monthName': _getMonthName(current.month),
          'displayName': '${_getMonthName(current.month)} ${current.year}',
        });

        // Move to next month
        if (current.month == 12) {
          current = DateTime(current.year + 1, 1);
        } else {
          current = DateTime(current.year, current.month + 1);
        }
      }

      return months.reversed.toList(); // Most recent first
    } catch (e) {
      // Return current month if error
      final now = DateTime.now();
      return [
        {
          'year': now.year,
          'month': now.month,
          'monthName': _getMonthName(now.month),
          'displayName': '${_getMonthName(now.month)} ${now.year}',
        },
      ];
    }
  }

  /// OPTIMIZED: Get cumulative stock in data with better performance
  Future<Map<String, int>> _getOptimizedCumulativeStockIn(
    DateTime endDate,
  ) async {
    final cacheKey = '${endDate.year}-${endDate.month}';

    // Check cache first
    if (_cumulativeStockInCache.containsKey(cacheKey)) {
      return _cumulativeStockInCache[cacheKey]!;
    }

    // Use limit and pagination for better performance
    Map<String, int> stockInData = {};
    DocumentSnapshot? lastDoc;
    const int batchSize = 500; // Process in smaller batches

    bool hasMore = true;
    while (hasMore) {
      Query query = _firestore
          .collection('inventory')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .limit(batchSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final category = data['equipment_category'] as String? ?? 'Unknown';

        // Skip items from "Others" category as they don't have meaningful sizes
        if (category.toLowerCase() == 'others') {
          continue;
        }

        // Only include Interactive Flat Panel items with actual sizes,
        // or items with unknown/missing category that have sizes
        final size = data['size'] as String? ?? '';
        String displaySize;

        if (category.toLowerCase() == 'interactive flat panel' ||
            category.toLowerCase() == 'ifp') {
          // IFP items: use actual size or 'Unknown' if no size
          displaySize = size.isEmpty ? 'Unknown' : size;
        } else if (category.toLowerCase() == 'unknown' && size.isNotEmpty) {
          // Unknown category items with size: use actual size
          displaySize = size;
        } else {
          // Non-IFP items without proper size: group as 'Unknown'
          displaySize = 'Unknown';
        }

        stockInData[displaySize] = (stockInData[displaySize] ?? 0) + 1;
      }

      if (snapshot.docs.length < batchSize) {
        hasMore = false;
      } else {
        lastDoc = snapshot.docs.last;
      }
    }

    // Cache the result
    _cumulativeStockInCache[cacheKey] = stockInData;
    return stockInData;
  }

  /// OPTIMIZED: Get cumulative stock out data with better performance
  Future<Map<String, int>> _getOptimizedCumulativeStockOut(
    DateTime endDate,
  ) async {
    final cacheKey = '${endDate.year}-${endDate.month}';

    // Check cache first
    if (_cumulativeStockOutCache.containsKey(cacheKey)) {
      return _cumulativeStockOutCache[cacheKey]!;
    }

    // Use batch processing and size lookup optimization
    Map<String, int> stockOutData = {};
    Map<String, String> serialToSizeCache =
        {}; // Cache serial number to size mapping

    DocumentSnapshot? lastDoc;
    const int batchSize = 500;

    bool hasMore = true;
    while (hasMore) {
      Query query = _firestore
          .collection('transactions')
          .where('type', isEqualTo: 'Stock_Out')
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .limit(batchSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      // Collect all serial numbers for batch lookup
      final serialNumbers = <String>[];
      final transactionData = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status != null && status != 'Active') {
          final serialNumber = data['serial_number'] as String?;
          if (serialNumber != null) {
            serialNumbers.add(serialNumber);
            transactionData.add(data);
          }
        }
      }

      // Batch lookup sizes for all serial numbers
      await _batchLookupSizes(serialNumbers, serialToSizeCache);

      // Process the transactions with cached sizes
      for (final data in transactionData) {
        final serialNumber = data['serial_number'] as String;
        final size = serialToSizeCache[serialNumber] ?? 'Unknown';

        // Skip items marked for exclusion (Others category)
        if (size == '__EXCLUDE__') {
          continue;
        }

        final quantity = data['quantity'] as int? ?? 1;
        stockOutData[size] = (stockOutData[size] ?? 0) + quantity;
      }

      if (snapshot.docs.length < batchSize) {
        hasMore = false;
      } else {
        lastDoc = snapshot.docs.last;
      }
    }

    // Cache the result
    _cumulativeStockOutCache[cacheKey] = stockOutData;
    return stockOutData;
  }

  /// Batch lookup sizes for multiple serial numbers to reduce Firestore calls
  Future<void> _batchLookupSizes(
    List<String> serialNumbers,
    Map<String, String> cache,
  ) async {
    final uncachedSerials = serialNumbers
        .where((serial) => !cache.containsKey(serial))
        .toList();

    if (uncachedSerials.isEmpty) return;

    // Process in batches of 10 (Firestore 'in' query limit)
    for (int i = 0; i < uncachedSerials.length; i += 10) {
      final batch = uncachedSerials.skip(i).take(10).toList();

      final snapshot = await _firestore
          .collection('inventory')
          .where('serial_number', whereIn: batch)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final serialNumber = data['serial_number'] as String?;
        final category = data['equipment_category'] as String? ?? 'Unknown';

        if (serialNumber != null) {
          // Mark "Others" category items with null to exclude from size breakdown
          if (category.toLowerCase() == 'others') {
            cache[serialNumber] = '__EXCLUDE__'; // Special marker for exclusion
          } else {
            final size = data['size'] as String? ?? '';
            String displaySize;

            if (category.toLowerCase() == 'interactive flat panel' ||
                category.toLowerCase() == 'ifp') {
              // IFP items: use actual size or 'Unknown' if no size
              displaySize = size.isEmpty ? 'Unknown' : size;
            } else if (category.toLowerCase() == 'unknown' && size.isNotEmpty) {
              // Unknown category items with size: use actual size
              displaySize = size;
            } else {
              // Non-IFP items without proper size: group as 'Unknown'
              displaySize = 'Unknown';
            }

            cache[serialNumber] = displaySize;
          }
        }
      }
    }

    // Set 'Unknown' for any serials not found (unless they should be excluded)
    for (final serial in uncachedSerials) {
      if (!cache.containsKey(serial)) {
        cache[serial] = 'Unknown';
      }
    }
  }
}
