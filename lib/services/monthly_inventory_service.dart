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
    final snapshot = await _firestore
        .collection('inventory')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockInBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final category = data['equipment_category'] as String? ?? 'Unknown';
      final size = data['size'] as String? ?? '';

      // Skip items from "Others" category as they don't have meaningful sizes
      if (category.toLowerCase() == 'others') {
        continue;
      }

      // Handle empty or null sizes for non-Others categories
      final displaySize = size.isEmpty ? 'Unknown' : size;
      stockInBySize[displaySize] = (stockInBySize[displaySize] ?? 0) + 1;
    }

    return stockInBySize;
  }

  /// Get ALL stock in data (including Others category) for summary calculation
  Future<Map<String, int>> _getAllStockInData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('inventory')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockInBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
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
  Future<List<Map<String, dynamic>>> getDetailedStockInData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('inventory')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .orderBy('date', descending: true)
        .get();

    List<Map<String, dynamic>> items = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      items.add({
        'id': doc.id,
        'serial_number': data['serial_number'] ?? 'N/A',
        'equipment_category': data['equipment_category'] ?? 'N/A',
        'size': data['size'] ?? 'Unknown',
        'batch': data['batch'] ?? 'N/A',
        'date': data['date'],
        'remark': data['remark'] ?? '',
        'source': data['source'] ?? 'Manual',
      });
    }

    return items;
  }

  /// Get stock out data from transactions collection for the specified month
  Future<Map<String, int>> _getStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('transactions')
        .where('type', isEqualTo: 'Stock_Out')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockOutBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;

      // Exclude 'Active' status as requested
      if (status != null && status != 'Active') {
        // Get size from the serial number or model (we need to match with inventory)
        final serialNumber = data['serial_number'] as String?;
        if (serialNumber != null) {
          final size = await _getSizeFromSerialNumber(serialNumber);
          // Only include if size is not null (excludes "Others" category)
          if (size != null) {
            stockOutBySize[size] = (stockOutBySize[size] ?? 0) + 1;
          }
        }
      }
    }

    return stockOutBySize;
  }

  /// Get ALL stock out data (including Others category) for summary calculation
  Future<Map<String, int>> _getAllStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('transactions')
        .where('type', isEqualTo: 'Stock_Out')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockOutBySize = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;

      // Exclude 'Active' status as requested
      if (status != null && status != 'Active') {
        // Get category and size information
        final category = data['equipment_category'] as String? ?? 'Unknown';

        String displayKey;
        if (category.toLowerCase() == 'others') {
          displayKey = 'Others'; // Group Others by category
          final quantity = data['quantity'] as int? ?? 1;
          stockOutBySize[displayKey] =
              (stockOutBySize[displayKey] ?? 0) + quantity;
        } else {
          // For non-Others, get size from serial number
          final serialNumber = data['serial_number'] as String?;
          if (serialNumber != null) {
            final size = await _getSizeFromSerialNumber(serialNumber);
            if (size != null) {
              final quantity = data['quantity'] as int? ?? 1;
              stockOutBySize[size] = (stockOutBySize[size] ?? 0) + quantity;
            }
          }
        }
      }
    }

    return stockOutBySize;
  }

  /// Get detailed stock out items for the specified month
  Future<List<Map<String, dynamic>>> getDetailedStockOutData(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('transactions')
        .where('type', isEqualTo: 'Stock_Out')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .orderBy('date', descending: true)
        .get();

    List<Map<String, dynamic>> items = [];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;

      // Exclude 'Active' status as requested
      if (status != null && status != 'Active') {
        final serialNumber = data['serial_number'] as String?;
        final size = serialNumber != null
            ? (await _getSizeFromSerialNumber(serialNumber) ?? 'Unknown')
            : 'Unknown';

        items.add({
          'id': doc.id,
          'transaction_id': data['transaction_id'] ?? 0,
          'serial_number': serialNumber ?? 'N/A',
          'equipment_category': data['equipment_category'] ?? 'N/A',
          'model': data['model'] ?? 'N/A',
          'size': size,
          'quantity': data['quantity'] ?? 1,
          'date': data['date'],
          'status': status,
          'customer_dealer': data['customer_dealer'] ?? 'N/A',
          'customer_client': data['customer_client'] ?? 'N/A',
          'location': data['location'] ?? 'N/A',
        });
      }
    }

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
        return size.isEmpty ? 'Unknown' : size;
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
          // Use cached data if available
          final cachedStockIn = _cumulativeStockInCache[cacheKey] ?? {};
          final cachedStockOut = _cumulativeStockOutCache[cacheKey] ?? {};

          if (cachedStockIn.isNotEmpty || cachedStockOut.isNotEmpty) {
            return _calculateRemainingFromCachedData(
              cachedStockIn,
              cachedStockOut,
            );
          }
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

  /// Optimized cumulative calculation using incremental approach
  Future<Map<String, int>> _calculateCumulativeRemainingOptimized(
    DateTime endDate,
  ) async {
    // For performance, we'll use a different approach:
    // 1. Get aggregated counts by size using efficient queries
    // 2. Use batch processing for better performance

    final stockInData = await _getOptimizedCumulativeStockIn(endDate);
    final stockOutData = await _getOptimizedCumulativeStockOut(endDate);

    return _calculateRemainingFromCachedData(stockInData, stockOutData);
  }

  /// Calculate remaining from cached/processed data
  Map<String, int> _calculateRemainingFromCachedData(
    Map<String, int> stockIn,
    Map<String, int> stockOut,
  ) {
    Map<String, int> remaining = {};
    final allSizes = <String>{...stockIn.keys, ...stockOut.keys};

    for (final size in allSizes) {
      final stockInCount = stockIn[size] ?? 0;
      final stockOutCount = stockOut[size] ?? 0;
      remaining[size] = stockInCount - stockOutCount;
    }

    return remaining;
  }

  /// Fallback: Calculate remaining for current month only
  Future<Map<String, int>> _calculateCurrentMonthRemaining(
    DateTime endDate,
  ) async {
    final startOfMonth = DateTime(endDate.year, endDate.month, 1);
    final stockInData = await _getStockInData(startOfMonth, endDate);
    final stockOutData = await _getStockOutData(startOfMonth, endDate);

    return _calculateRemainingFromCachedData(stockInData, stockOutData);
  }

  /// Calculate remaining amounts (stock in - stock out) - DEPRECATED
  Map<String, int> _calculateRemainingAmounts(
    Map<String, int> stockIn,
    Map<String, int> stockOut,
  ) {
    Map<String, int> remaining = {};

    // Get all unique sizes
    final allSizes = <String>{...stockIn.keys, ...stockOut.keys};

    for (final size in allSizes) {
      final stockInCount = stockIn[size] ?? 0;
      final stockOutCount = stockOut[size] ?? 0;
      remaining[size] = stockInCount - stockOutCount;
    }

    return remaining;
  }

  /// Get size breakdown with detailed information
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

    return allSizes
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
    final snapshot = await _firestore
        .collection('inventory')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockInData = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final category = data['equipment_category'] as String? ?? 'Unknown';
      stockInData[category] = (stockInData[category] ?? 0) + 1;
    }

    return stockInData;
  }

  /// Get stock out data grouped by category
  Future<Map<String, int>> _getStockOutDataByCategory(
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) async {
    final snapshot = await _firestore
        .collection('transactions')
        .where('type', isEqualTo: 'Stock_Out')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    Map<String, int> stockOutData = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;

      // Exclude 'Active' status as requested
      if (status != null && status != 'Active') {
        final category = data['equipment_category'] as String? ?? 'Unknown';
        final quantity = data['quantity'] as int? ?? 1;
        stockOutData[category] = (stockOutData[category] ?? 0) + quantity;
      }
    }

    return stockOutData;
  }

  /// Get remaining data grouped by category (cumulative)
  Future<Map<String, int>> _getRemainingDataByCategory(DateTime endDate) async {
    // Get cumulative stock in by category
    final stockInSnapshot = await _firestore
        .collection('inventory')
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<String, int> stockInByCategory = {};
    for (final doc in stockInSnapshot.docs) {
      final data = doc.data();
      final category = data['equipment_category'] as String? ?? 'Unknown';
      stockInByCategory[category] = (stockInByCategory[category] ?? 0) + 1;
    }

    // Get cumulative stock out by category
    final stockOutSnapshot = await _firestore
        .collection('transactions')
        .where('type', isEqualTo: 'Stock_Out')
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<String, int> stockOutByCategory = {};
    for (final doc in stockOutSnapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String?;

      if (status != null && status != 'Active') {
        final category = data['equipment_category'] as String? ?? 'Unknown';
        final quantity = data['quantity'] as int? ?? 1;
        stockOutByCategory[category] =
            (stockOutByCategory[category] ?? 0) + quantity;
      }
    }

    // Calculate remaining by category
    final allCategories = <String>{
      ...stockInByCategory.keys,
      ...stockOutByCategory.keys,
    };

    Map<String, int> remainingByCategory = {};
    for (final category in allCategories) {
      final stockIn = stockInByCategory[category] ?? 0;
      final stockOut = stockOutByCategory[category] ?? 0;
      remainingByCategory[category] = stockIn - stockOut;
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

        final size = data['size'] as String? ?? '';
        final displaySize = size.isEmpty ? 'Unknown' : size;
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
            cache[serialNumber] = size.isEmpty ? 'Unknown' : size;
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
