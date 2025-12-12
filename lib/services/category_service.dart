import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get detailed category information with models and active counts
  Future<Map<String, dynamic>> getCategoryDetails(String categoryName) async {
    try {
      // Get inventory items for this category
      final inventorySnapshot = await _firestore
          .collection('inventory')
          .where('equipment_category', isEqualTo: categoryName)
          .get();

      Map<String, int> modelActiveCount = {}; // normalized model -> count
      Map<String, String> modelCaseMapping =
          {}; // normalized model -> original case
      Map<String, Map<String, int>> sizeModelActiveCount =
          {}; // size -> {normalized model -> count}
      Map<String, Map<String, String>> sizeModelCaseMapping =
          {}; // size -> {normalized model -> original case}
      int totalItems = 0;
      int activeItems = 0;
      int reservedItems = 0;
      int deliveredItems = 0;

      // Process each inventory item in this category
      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        final model = data['model'] as String? ?? 'Unknown';
        final size = _extractSizeFromInventoryData(data);
        final status = data['status'] as String? ?? 'Active';

        totalItems++;

        // Count by status - read directly from inventory.status field
        switch (status) {
          case 'Active':
            activeItems++;

            // Use case-insensitive model grouping
            final normalizedModel = model.toLowerCase();
            modelActiveCount[normalizedModel] =
                (modelActiveCount[normalizedModel] ?? 0) + 1;
            modelCaseMapping[normalizedModel] = model; // Store original case

            // For Interactive Flat Panel, also count by size
            if (categoryName == 'Interactive Flat Panel' && size != null) {
              sizeModelActiveCount[size] ??= {};
              sizeModelCaseMapping[size] ??= {};

              sizeModelActiveCount[size]![normalizedModel] =
                  (sizeModelActiveCount[size]![normalizedModel] ?? 0) + 1;
              sizeModelCaseMapping[size]![normalizedModel] =
                  model; // Store original case
            }
            break;
          case 'Reserved':
            reservedItems++;
            break;
          case 'Delivered':
            deliveredItems++;
            break;
        }
      }

      // Sort models by active count and restore original case
      final sortedModels = modelActiveCount.entries.map((entry) {
        final normalizedModel = entry.key;
        final count = entry.value;
        final originalCase =
            modelCaseMapping[normalizedModel] ?? normalizedModel;
        return MapEntry(originalCase, count);
      }).toList()..sort((a, b) => b.value.compareTo(a.value));

      // Prepare size-based data for Interactive Flat Panel
      List<Map<String, dynamic>> sizeBreakdown = [];
      if (categoryName == 'Interactive Flat Panel') {
        // Sort sizes numerically
        final sortedSizes = sizeModelActiveCount.keys.toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a) ?? 0;
            final bNum = int.tryParse(b) ?? 0;
            return aNum.compareTo(bNum);
          });

        for (final size in sortedSizes) {
          final modelsInSize = sizeModelActiveCount[size]!;
          final modelCaseMappingForSize = sizeModelCaseMapping[size]!;

          // Restore original case and sort by count
          final sortedModelsInSize = modelsInSize.entries.map((entry) {
            final normalizedModel = entry.key;
            final count = entry.value;
            final originalCase =
                modelCaseMappingForSize[normalizedModel] ?? normalizedModel;
            return MapEntry(originalCase, count);
          }).toList()..sort((a, b) => b.value.compareTo(a.value));

          final totalActiveInSize = modelsInSize.values.fold(
            0,
            (total, itemCount) => total + itemCount,
          );

          sizeBreakdown.add({
            'size': size,
            'total_active': totalActiveInSize,
            'models': sortedModelsInSize
                .map(
                  (entry) => {'model': entry.key, 'active_count': entry.value},
                )
                .toList(),
          });
        }
      }

      return {
        'success': true,
        'category_name': categoryName,
        'total_items': totalItems,
        'active_items': activeItems,
        'reserved_items': reservedItems,
        'delivered_items': deliveredItems,
        'models': sortedModels
            .map((entry) => {'model': entry.key, 'active_count': entry.value})
            .toList(),
        'size_breakdown': sizeBreakdown, // New field for IFP size data
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
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

  /// Extract size information from inventory data
  String? _extractSizeFromInventoryData(Map<String, dynamic> data) {
    // 1. Check if there's a 'size' field
    final sizeField = data['size'] as String?;
    if (sizeField != null && sizeField.isNotEmpty && sizeField != 'Unknown') {
      // Extract numeric size from size field
      final sizeMatch = RegExp(r'(\d+)').firstMatch(sizeField);
      if (sizeMatch != null) {
        return sizeMatch.group(1);
      }
    }

    // 2. Check model field for size (e.g., "65M6APro" -> "65")
    final model = data['model'] as String?;
    if (model != null && model.isNotEmpty) {
      final sizeMatch = RegExp(r'^(\d+)').firstMatch(model);
      if (sizeMatch != null) {
        return sizeMatch.group(1);
      }
    }

    // 3. Check equipment_model field for size
    final equipmentModel = data['equipment_model'] as String?;
    if (equipmentModel != null && equipmentModel.isNotEmpty) {
      final sizeMatch = RegExp(r'(\d+)').firstMatch(equipmentModel);
      if (sizeMatch != null) {
        return sizeMatch.group(1);
      }
    }

    // 4. Check serial number for size patterns (common IFP sizes: 55, 65, 75, 86)
    final serialNumber = data['serial_number'] as String?;
    if (serialNumber != null && serialNumber.isNotEmpty) {
      final sizeMatch = RegExp(r'(55|65|75|86)').firstMatch(serialNumber);
      if (sizeMatch != null) {
        return sizeMatch.group(1);
      }
    }

    // 5. Check any other string fields for size information with "inch" or '"'
    for (final entry in data.entries) {
      if (entry.value is String) {
        final value = entry.value as String;
        if (value.contains('inch') || value.contains('"')) {
          final sizeMatch = RegExp(r'(\d+)\s*(?:inch|")').firstMatch(value);
          if (sizeMatch != null) {
            return sizeMatch.group(1);
          }
        }
      }
    }

    return null; // Could not determine size
  }
}
