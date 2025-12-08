import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'auth_service.dart';

class DataUploadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  DataUploadService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Get the latest transaction ID from Firestore
  /// Matches PHP: getLatestTransactionId()
  Future<int> _getLatestTransactionId() async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('transactions')
          .orderBy('transaction_id', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return 0;
      }

      final data = snapshot.docs.first.data() as Map<String, dynamic>;
      return (data['transaction_id'] as num?)?.toInt() ?? 0;
    } catch (e) {
      print('Error getting latest transaction ID: $e');
      return 0;
    }
  }

  /// Get current timestamp in Malaysia Time (UTC+8)
  /// Matches PHP: date_default_timezone_set('Asia/Kuala_Lumpur')
  Timestamp _getMalaysiaTimestamp() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return Timestamp.fromDate(now);
  }

  /// Normalize header name for column mapping
  /// Matches PHP: strtolower, str_replace([' ', '(', ')'], ['_', '', ''])
  String _normalizeHeader(String header) {
    return header
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .trim();
  }

  /// Parse date from various formats
  /// Matches PHP: tryParseDate()
  dynamic _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }

    if (value is num) {
      // Excel serial date
      // Excel epoch is Dec 30, 1899
      final excelEpoch = DateTime(1899, 12, 30);
      final days = value.toInt();
      final fraction = value.toDouble() - days;
      final milliseconds = (fraction * 24 * 60 * 60 * 1000).round();
      final date = excelEpoch.add(
        Duration(days: days, milliseconds: milliseconds),
      );
      return Timestamp.fromDate(date);
    }

    if (value is String) {
      final formats = [
        RegExp(r'^\d{4}-\d{2}-\d{2}$'), // YYYY-MM-DD
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'), // YYYY-MM-DD HH:MM:SS
        RegExp(r'^\d{2}/\d{2}/\d{4}$'), // DD/MM/YYYY
        RegExp(r'^\d{2}-\d{2}-\d{4}$'), // DD-MM-YYYY
      ];

      for (final regex in formats) {
        if (regex.hasMatch(value)) {
          try {
            // Simple parsing attempt - for production might need more robust parsing
            // depending on exact format variations
            if (value.contains('/')) {
              final parts = value.split('/');
              // Assume DD/MM/YYYY
              if (parts.length == 3) {
                return Timestamp.fromDate(
                  DateTime(
                    int.parse(parts[2]),
                    int.parse(parts[1]),
                    int.parse(parts[0]),
                  ),
                );
              }
            }
            return Timestamp.fromDate(DateTime.parse(value));
          } catch (_) {
            continue;
          }
        }
      }
    }

    return null;
  }

  /// Validate inventory data before upload
  Future<Map<String, dynamic>> validateInventoryData(
    Uint8List fileBytes,
    String fileName,
  ) async {
    try {
      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        return {
          'valid': false,
          'message': 'No sheets found in Excel file',
          'errors': ['Empty file'],
        };
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        return {
          'valid': false,
          'message': 'Sheet is empty',
          'errors': ['Empty sheet'],
        };
      }

      // Process headers
      final headers = sheet.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      final columnMap = <String, int>{};
      for (int i = 0; i < headers.length; i++) {
        columnMap[_normalizeHeader(headers[i])] = i;
      }

      // Validate required columns
      final requiredColumns = ['serial_number', 'equipment_category'];
      final missingColumns = requiredColumns
          .where((col) => !columnMap.containsKey(col))
          .toList();

      if (missingColumns.isNotEmpty) {
        return {
          'valid': false,
          'message': 'Missing required columns: ${missingColumns.join(', ')}',
          'errors': missingColumns.map((c) => 'Missing column: $c').toList(),
        };
      }

      int totalRecords = 0;
      List<String> errors = [];

      // Process rows
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        totalRecords++;
        try {
          String getValue(String key) {
            if (!columnMap.containsKey(key)) return '';
            final index = columnMap[key]!;
            if (index >= row.length) return '';
            return row[index]?.value?.toString().trim() ?? '';
          }

          final serialNumber = getValue('serial_number');
          final equipmentCategory = getValue('equipment_category');

          if (serialNumber.isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
          }

          if (equipmentCategory.isEmpty) {
            errors.add('Row ${i + 1}: Missing equipment category');
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      return {
        'valid': errors.isEmpty,
        'total_records': totalRecords,
        'errors': errors,
      };
    } catch (e) {
      return {
        'valid': false,
        'message': e.toString(),
        'errors': [e.toString()],
      };
    }
  }

  /// Validate transaction data before upload
  Future<Map<String, dynamic>> validateTransactionData(
    Uint8List fileBytes,
    String fileName,
  ) async {
    try {
      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        return {
          'valid': false,
          'message': 'No sheets found in Excel file',
          'errors': ['Empty file'],
        };
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        return {
          'valid': false,
          'message': 'Sheet is empty',
          'errors': ['Empty sheet'],
        };
      }

      // Process headers
      final headers = sheet.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      final columnMap = <String, int>{};
      for (int i = 0; i < headers.length; i++) {
        columnMap[_normalizeHeader(headers[i])] = i;
      }

      // Validate required columns
      final requiredColumns = [
        'date',
        'type',
        'equipment_category',
        'model',
        'serial_number',
        'quantity',
      ];
      final missingColumns = requiredColumns
          .where((col) => !columnMap.containsKey(col))
          .toList();

      if (missingColumns.isNotEmpty) {
        return {
          'valid': false,
          'message': 'Missing required columns: ${missingColumns.join(', ')}',
          'errors': missingColumns.map((c) => 'Missing column: $c').toList(),
        };
      }

      int totalRecords = 0;
      List<String> errors = [];

      // Process rows
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        totalRecords++;
        try {
          String getValue(String key) {
            if (!columnMap.containsKey(key)) return '';
            final index = columnMap[key]!;
            if (index >= row.length) return '';
            return row[index]?.value?.toString().trim() ?? '';
          }

          final serialNumber = getValue('serial_number');
          final dateStr = getValue('date');

          if (serialNumber.isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
          }

          if (dateStr.isEmpty) {
            errors.add('Row ${i + 1}: Missing date');
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      return {
        'valid': errors.isEmpty,
        'total_records': totalRecords,
        'errors': errors,
      };
    } catch (e) {
      return {
        'valid': false,
        'message': e.toString(),
        'errors': [e.toString()],
      };
    }
  }

  /// Upload inventory data from Excel file bytes
  Future<Map<String, dynamic>> uploadInventoryData(
    Uint8List fileBytes,
    String fileName,
  ) async {
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required.',
        'errors': ['Unauthorized access'],
      };
    }

    try {
      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        return {
          'success': false,
          'message': 'No sheets found in Excel file',
          'errors': ['Empty file'],
        };
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        return {
          'success': false,
          'message': 'Sheet is empty',
          'errors': ['Empty sheet'],
        };
      }

      // Process headers
      final headers = sheet.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      final columnMap = <String, int>{};
      for (int i = 0; i < headers.length; i++) {
        columnMap[_normalizeHeader(headers[i])] = i;
      }

      // Validate required columns
      final requiredColumns = ['serial_number', 'equipment_category'];
      final missingColumns = requiredColumns
          .where((col) => !columnMap.containsKey(col))
          .toList();

      if (missingColumns.isNotEmpty) {
        return {
          'success': false,
          'message': 'Missing required columns: ${missingColumns.join(', ')}',
          'errors': missingColumns.map((c) => 'Missing column: $c').toList(),
        };
      }

      int totalRecords = 0;
      int successfulUploads = 0;
      List<String> errors = [];
      final batch = _firestore.batch();
      int batchCount = 0;
      final malaysiaTime = _getMalaysiaTimestamp();

      // Get starting transaction ID for auto-generated transactions
      int currentTransactionId = (await _getLatestTransactionId()) + 1;

      // Process rows
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        totalRecords++;
        try {
          String getValue(String key) {
            if (!columnMap.containsKey(key)) return '';
            final index = columnMap[key]!;
            if (index >= row.length) return '';
            return row[index]?.value?.toString().trim() ?? '';
          }

          final serialNumber = getValue('serial_number');
          final equipmentCategory = getValue('equipment_category');
          final model = getValue('model');

          if (serialNumber.isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
            continue;
          }

          if (equipmentCategory.isEmpty) {
            errors.add('Row ${i + 1}: Missing equipment category');
            continue;
          }

          // Parse date if present
          dynamic parsedDate;
          if (columnMap.containsKey('date')) {
            final dateIndex = columnMap['date']!;
            if (dateIndex < row.length) {
              parsedDate = _parseDate(row[dateIndex]?.value);
            }
          }

          // 1. Create Inventory Document
          final inventoryDocRef = _firestore.collection('inventory').doc();
          final inventoryData = {
            'batch': getValue('batch'),
            'date': parsedDate,
            'equipment_category': equipmentCategory,
            'model': model,
            'remark': getValue('remark'),
            'serial_number': serialNumber,
            'size': getValue('size'),
            'source': 'inventory_upload',
            'uploaded_at': malaysiaTime,
            'uploaded_by_uid': _authService.currentUser?.uid ?? '',
          };

          batch.set(inventoryDocRef, inventoryData);
          batchCount++;

          // 2. Auto-create Stock_In Transaction
          final transactionDocRef = _firestore.collection('transactions').doc();
          final transactionData = {
            'transaction_id': currentTransactionId,
            'date':
                parsedDate ??
                malaysiaTime, // Use inventory date or current time
            'type': 'Stock_In',
            'equipment_category': equipmentCategory,
            'model': model,
            'serial_number': serialNumber,
            'quantity': 1,
            'location': 'HQ',
            'status': 'Active',
            'remarks': 'Auto-generated from inventory upload',
            'source': 'bulk_upload',
            'uploaded_at': malaysiaTime,
            'uploaded_by_uid': _authService.currentUser?.uid ?? '',
            'size': getValue('size'),
            // Optional fields
            'batch': getValue('batch'),
          };

          batch.set(transactionDocRef, transactionData);
          batchCount++;
          currentTransactionId++;

          successfulUploads++;

          if (batchCount >= 400) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'collection': 'inventory',
        'total_records': totalRecords,
        'successful_uploads': successfulUploads,
        'failed_uploads': totalRecords - successfulUploads,
        'errors': errors,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
        'errors': [e.toString()],
      };
    }
  }

  /// Upload transaction data from Excel file bytes
  Future<Map<String, dynamic>> uploadTransactionData(
    Uint8List fileBytes,
    String fileName,
  ) async {
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required.',
        'errors': ['Unauthorized access'],
      };
    }

    try {
      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        return {
          'success': false,
          'message': 'No sheets found in Excel file',
          'errors': ['Empty file'],
        };
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        return {
          'success': false,
          'message': 'Sheet is empty',
          'errors': ['Empty sheet'],
        };
      }

      // Process headers
      final headers = sheet.rows.first
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();
      final columnMap = <String, int>{};
      for (int i = 0; i < headers.length; i++) {
        columnMap[_normalizeHeader(headers[i])] = i;
      }

      // Validate required columns
      final requiredColumns = [
        'date',
        'type',
        'equipment_category',
        'model',
        'serial_number',
        'quantity',
      ];
      final missingColumns = requiredColumns
          .where((col) => !columnMap.containsKey(col))
          .toList();

      if (missingColumns.isNotEmpty) {
        return {
          'success': false,
          'message': 'Missing required columns: ${missingColumns.join(', ')}',
          'errors': missingColumns.map((c) => 'Missing column: $c').toList(),
        };
      }

      int totalRecords = 0;
      int successfulUploads = 0;
      List<String> errors = [];
      final batch = _firestore.batch();
      int batchCount = 0;
      final malaysiaTime = _getMalaysiaTimestamp();

      // Get starting transaction ID
      int currentTransactionId = (await _getLatestTransactionId()) + 1;

      // Process rows
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        totalRecords++;
        try {
          String getValue(String key) {
            if (!columnMap.containsKey(key)) return '';
            final index = columnMap[key]!;
            if (index >= row.length) return '';
            return row[index]?.value?.toString().trim() ?? '';
          }

          final serialNumber = getValue('serial_number');
          final dateStr = getValue('date');

          if (serialNumber.isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
            continue;
          }

          if (dateStr.isEmpty) {
            errors.add('Row ${i + 1}: Missing date');
            continue;
          }

          // Parse date
          dynamic parsedDate;
          if (columnMap.containsKey('date')) {
            final dateIndex = columnMap['date']!;
            if (dateIndex < row.length) {
              parsedDate = _parseDate(row[dateIndex]?.value);
            }
          }

          if (parsedDate == null) {
            errors.add('Row ${i + 1}: Invalid date format');
            continue;
          }

          // Parse delivery date if present
          dynamic parsedDeliveryDate;
          if (columnMap.containsKey('delivery_date')) {
            final dateIndex = columnMap['delivery_date']!;
            if (dateIndex < row.length) {
              parsedDeliveryDate = _parseDate(row[dateIndex]?.value);
            }
          }

          final docRef = _firestore.collection('transactions').doc();
          final data = {
            'transaction_id': currentTransactionId,
            'date': parsedDate,
            'type': getValue('type'),
            'equipment_category': getValue('equipment_category'),
            'model': getValue('model'),
            'serial_number': serialNumber,
            'quantity': int.tryParse(getValue('quantity')) ?? 1,
            'location': getValue('location'),
            'status': getValue('status').isEmpty
                ? 'Active'
                : getValue('status'),
            'remarks': getValue('remarks'),
            'source': 'bulk_upload',
            'uploaded_at': malaysiaTime,
            'uploaded_by_uid': _authService.currentUser?.uid ?? '',

            // Additional fields
            'entry_no': getValue('entry_no'),
            'customer_dealer': getValue('customer_dealer'),
            'customer_client': getValue('customer_client'),
            'unit_price': double.tryParse(getValue('unit_price')) ?? 0.0,
            'warranty_type': getValue('warranty_type'),
            'warranty_period': getValue('warranty_period'),
            'delivery_date': parsedDeliveryDate,
            'invoice_number': getValue('invoice_number'),
            'size': '', // Explicitly empty as per specs
          };

          batch.set(docRef, data);
          batchCount++;
          successfulUploads++;
          currentTransactionId++;

          if (batchCount >= 400) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'collection': 'transactions',
        'total_records': totalRecords,
        'successful_uploads': successfulUploads,
        'failed_uploads': totalRecords - successfulUploads,
        'errors': errors,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
        'errors': [e.toString()],
      };
    }
  }

  /// Clear all uploaded data (use with caution!) - Admin only
  Future<Map<String, dynamic>> clearCollection(String collectionName) async {
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required.',
        'deleted_count': 0,
      };
    }

    try {
      var collection = _firestore.collection(collectionName);
      var snapshots = await collection.get();

      int deletedCount = 0;
      final batch = _firestore.batch();
      int batchCount = 0;

      for (var doc in snapshots.docs) {
        batch.delete(doc.reference);
        deletedCount++;
        batchCount++;

        if (batchCount >= 400) {
          await batch.commit();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'deleted_count': deletedCount,
        'collection': collectionName,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'collection': collectionName,
      };
    }
  }
}
