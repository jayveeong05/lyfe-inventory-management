import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'auth_service.dart';

class ImportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  ImportService({required AuthService authService})
    : _authService = authService;

  /// Get the latest transaction ID from Firebase
  Future<int> getLatestTransactionId() async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('transactions')
          .orderBy('transaction_id', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return 0;

      final data = snapshot.docs.first.data() as Map<String, dynamic>;
      return data['transaction_id'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get Malaysia timezone timestamp (UTC+8)
  String getMalaysiaTimestamp() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return now.toIso8601String().replaceAll('T', ' ').substring(0, 19);
  }

  /// Parse Excel file and return rows
  Future<List<List<dynamic>>> parseExcelFile(File file) async {
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final List<List<dynamic>> rows = [];

    // Get the first sheet
    final sheet = excel.tables.keys.first;
    final table = excel.tables[sheet];

    if (table != null) {
      for (final row in table.rows) {
        final List<dynamic> rowData = [];
        for (final cell in row) {
          rowData.add(cell?.value?.toString() ?? '');
        }
        rows.add(rowData);
      }
    }

    return rows;
  }

  /// Parse CSV file and return rows
  Future<List<List<dynamic>>> parseCsvFile(File file) async {
    final input = await file.readAsString();
    final List<List<dynamic>> rows = const CsvToListConverter().convert(input);
    return rows;
  }

  /// Create column mapping from header row
  Map<String, int> createColumnMapping(List<String> header) {
    final Map<String, int> columnMap = {};

    for (int i = 0; i < header.length; i++) {
      final columnName = header[i]
          .toLowerCase()
          .replaceAll(' ', '_')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .trim();
      columnMap[columnName] = i;
    }

    return columnMap;
  }

  /// Get value from row using column mapping
  String getColumnValue(
    List<dynamic> row,
    Map<String, int> columnMap,
    String columnName,
  ) {
    final index = columnMap[columnName];
    if (index != null && index < row.length) {
      return row[index]?.toString().trim() ?? '';
    }
    return '';
  }

  /// Validate required columns for transaction import
  List<String> validateTransactionColumns(Map<String, int> columnMap) {
    final List<String> errors = [];
    final requiredColumns = [
      'transaction_id',
      'date',
      'type',
      'equipment_category',
      'model',
      'serial_number',
      'quantity',
    ];

    for (final column in requiredColumns) {
      if (!columnMap.containsKey(column)) {
        errors.add('Missing required column: $column');
      }
    }

    return errors;
  }

  /// Validate required columns for inventory import
  List<String> validateInventoryColumns(Map<String, int> columnMap) {
    final List<String> errors = [];
    final requiredColumns = [
      'serial_number',
      'equipment_category',
      'model',
      'size',
      'batch',
      'date',
      'remark',
    ];

    for (final column in requiredColumns) {
      if (!columnMap.containsKey(column)) {
        errors.add('Missing required column: $column');
      }
    }

    return errors;
  }

  /// Create transaction data from row
  Map<String, dynamic> createTransactionData(
    List<dynamic> row,
    Map<String, int> columnMap,
    int transactionId,
  ) {
    final currentUser = _authService.currentUser;
    final timestamp = getMalaysiaTimestamp();

    return {
      'transaction_id': transactionId,
      'date': getColumnValue(row, columnMap, 'date'),
      'type': getColumnValue(row, columnMap, 'type'),
      'equipment_category': getColumnValue(
        row,
        columnMap,
        'equipment_category',
      ),
      'model': getColumnValue(row, columnMap, 'model'),
      'serial_number': getColumnValue(row, columnMap, 'serial_number'),
      'quantity': int.tryParse(getColumnValue(row, columnMap, 'quantity')) ?? 1,
      'entry_no': getColumnValue(row, columnMap, 'entry_no'),
      'customer_dealer': getColumnValue(row, columnMap, 'customer_dealer'),
      'customer_client': getColumnValue(row, columnMap, 'customer_client'),
      'location': getColumnValue(row, columnMap, 'location'),
      'unit_price':
          double.tryParse(getColumnValue(row, columnMap, 'unit_price')) ?? 0.0,
      'warranty_type': getColumnValue(row, columnMap, 'warranty_type'),
      'warranty_period': getColumnValue(row, columnMap, 'warranty_period'),
      'delivery_date': getColumnValue(row, columnMap, 'delivery_date'),
      'invoice_number': getColumnValue(row, columnMap, 'invoice_number'),
      'remarks': getColumnValue(row, columnMap, 'remarks'),
      'status': getColumnValue(row, columnMap, 'status').isEmpty
          ? 'Active'
          : getColumnValue(row, columnMap, 'status'),
      'size': getColumnValue(row, columnMap, 'size'),
      'source': 'bulk_upload',
      'uploaded_at': timestamp,
      'uploaded_by_uid': currentUser?.uid ?? '',
    };
  }

  /// Create inventory data from row
  Map<String, dynamic> createInventoryData(
    List<dynamic> row,
    Map<String, int> columnMap,
  ) {
    final currentUser = _authService.currentUser;
    final timestamp = getMalaysiaTimestamp();

    return {
      'serial_number': getColumnValue(row, columnMap, 'serial_number'),
      'equipment_category': getColumnValue(
        row,
        columnMap,
        'equipment_category',
      ),
      'model': getColumnValue(row, columnMap, 'model'),
      'size': getColumnValue(row, columnMap, 'size'),
      'batch': getColumnValue(row, columnMap, 'batch'),
      'date': getColumnValue(row, columnMap, 'date'),
      'remark': getColumnValue(row, columnMap, 'remark'),
      'source': 'inventory_upload',
      'uploaded_at': timestamp,
      'uploaded_by_uid': currentUser?.uid ?? '',
    };
  }

  /// Import transaction log from file
  Future<Map<String, dynamic>> importTransactionLog(File file) async {
    try {
      // Parse file based on extension
      List<List<dynamic>> rows;
      final extension = file.path.toLowerCase();

      if (extension.endsWith('.csv')) {
        rows = await parseCsvFile(file);
      } else if (extension.endsWith('.xlsx') || extension.endsWith('.xls')) {
        rows = await parseExcelFile(file);
      } else {
        return {
          'success': false,
          'error':
              'Unsupported file format. Please use .xlsx, .xls, or .csv files.',
        };
      }

      if (rows.isEmpty) {
        return {
          'success': false,
          'error': 'File is empty or could not be parsed.',
        };
      }

      // Create column mapping from header row
      final header = rows[0].map((e) => e.toString()).toList();
      final columnMap = createColumnMapping(header);

      // Validate required columns
      final validationErrors = validateTransactionColumns(columnMap);
      if (validationErrors.isNotEmpty) {
        return {
          'success': false,
          'error': 'Column validation failed:\n${validationErrors.join('\n')}',
        };
      }

      // Get starting transaction ID
      int currentTransactionId = await getLatestTransactionId() + 1;

      final List<String> errors = [];
      int successCount = 0;

      // Process rows in batches
      final batch = _firestore.batch();
      int batchCount = 0;

      for (int i = 1; i < rows.length; i++) {
        try {
          final transactionData = createTransactionData(
            rows[i],
            columnMap,
            currentTransactionId,
          );

          // Validate required fields
          if (transactionData['serial_number'].toString().isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
            continue;
          }

          final docRef = _firestore.collection('transactions').doc();
          batch.set(docRef, transactionData);

          batchCount++;
          currentTransactionId++;
          successCount++;

          // Commit batch when it reaches 500 documents (Firestore limit)
          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      // Commit remaining documents
      if (batchCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'transactions_imported': successCount,
        'errors': errors,
        'message': 'Successfully imported $successCount transactions',
      };
    } catch (e) {
      return {'success': false, 'error': 'Import failed: ${e.toString()}'};
    }
  }

  /// Import inventory from file
  Future<Map<String, dynamic>> importInventory(File file) async {
    try {
      // Parse file based on extension
      List<List<dynamic>> rows;
      final extension = file.path.toLowerCase();

      if (extension.endsWith('.csv')) {
        rows = await parseCsvFile(file);
      } else if (extension.endsWith('.xlsx') || extension.endsWith('.xls')) {
        rows = await parseExcelFile(file);
      } else {
        return {
          'success': false,
          'error':
              'Unsupported file format. Please use .xlsx, .xls, or .csv files.',
        };
      }

      if (rows.isEmpty) {
        return {
          'success': false,
          'error': 'File is empty or could not be parsed.',
        };
      }

      // Create column mapping from header row
      final header = rows[0].map((e) => e.toString()).toList();
      final columnMap = createColumnMapping(header);

      // Validate required columns
      final validationErrors = validateInventoryColumns(columnMap);
      if (validationErrors.isNotEmpty) {
        return {
          'success': false,
          'error': 'Column validation failed:\n${validationErrors.join('\n')}',
        };
      }

      final List<String> errors = [];
      int successCount = 0;

      // Process rows in batches
      final batch = _firestore.batch();
      int batchCount = 0;

      for (int i = 1; i < rows.length; i++) {
        try {
          final inventoryData = createInventoryData(rows[i], columnMap);

          // Validate required fields
          if (inventoryData['serial_number'].toString().isEmpty) {
            errors.add('Row ${i + 1}: Missing serial number');
            continue;
          }

          final docRef = _firestore.collection('inventory').doc();
          batch.set(docRef, inventoryData);

          batchCount++;
          successCount++;

          // Commit batch when it reaches 500 documents (Firestore limit)
          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      // Commit remaining documents
      if (batchCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'inventory_imported': successCount,
        'errors': errors,
        'message': 'Successfully imported $successCount inventory items',
      };
    } catch (e) {
      return {'success': false, 'error': 'Import failed: ${e.toString()}'};
    }
  }
}
