import 'package:flutter/services.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class DataUploadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService;

  DataUploadService({AuthService? authService})
    : _authService = authService ?? AuthService();

  /// Convert Excel serial date to DateTime
  /// Excel uses 1900-01-01 as day 1, but has a leap year bug where 1900 is treated as a leap year
  /// So we need to account for this when converting
  DateTime? _convertExcelSerialDate(dynamic value) {
    if (value == null) return null;

    // Try to parse as number (Excel serial date)
    double? serialDate;
    if (value is num) {
      serialDate = value.toDouble();
    } else if (value is String) {
      serialDate = double.tryParse(value);
    }

    if (serialDate == null) return null;

    // Excel epoch starts at 1900-01-01, but Excel incorrectly treats 1900 as a leap year
    // So dates after Feb 28, 1900 need to be adjusted by subtracting 1 day
    // Excel serial date 1 = 1900-01-01
    final excelEpoch = DateTime(1899, 12, 30); // Day 0 in Excel

    // Convert serial date to DateTime
    final days = serialDate.floor();
    final timeFraction = serialDate - days;
    final hours = (timeFraction * 24).floor();
    final minutes = ((timeFraction * 24 - hours) * 60).floor();
    final seconds = (((timeFraction * 24 - hours) * 60 - minutes) * 60).floor();

    return excelEpoch.add(
      Duration(days: days, hours: hours, minutes: minutes, seconds: seconds),
    );
  }

  /// Check if a header name indicates a date field
  bool _isDateField(String header) {
    final lowerHeader = header.toLowerCase();
    return lowerHeader.contains('date') ||
        lowerHeader == 'delivery_date' ||
        lowerHeader == 'uploaded_at';
  }

  /// Upload inventory data from Excel file to Firestore (Admin only)
  Future<Map<String, dynamic>> uploadInventoryData() async {
    // Check admin access
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required to upload data.',
        'errors': ['Unauthorized access'],
        'total_records': 0,
        'successful_uploads': 0,
        'failed_uploads': 0,
      };
    }

    try {
      // Load the Excel file from assets
      ByteData data = await rootBundle.load('tables/inventory_dev.xlsx');
      var bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      var decoder = SpreadsheetDecoder.decodeBytes(bytes);

      int totalRecords = 0;
      int successfulUploads = 0;
      List<String> errors = [];

      // Get the first sheet (assuming data is in the first sheet)
      if (decoder.tables.isEmpty) {
        throw Exception('No sheets found in the Excel file');
      }

      String sheetName = decoder.tables.keys.first;
      var sheet = decoder.tables[sheetName];
      if (sheet == null) {
        throw Exception('Sheet "$sheetName" not found in the Excel file');
      }

      // Get headers from the first row
      List<String> headers = [];
      if (sheet.rows.isEmpty) {
        throw Exception('Excel sheet is empty - no data found');
      }

      for (var cell in sheet.rows[0]) {
        headers.add(cell?.toString() ?? '');
      }

      // Headers found and processed

      // Check if there are data rows beyond the header
      if (sheet.rows.length <= 1) {
        throw Exception(
          'Excel sheet only contains headers - no data rows found',
        );
      }

      // Process each row (skip header row)
      for (int i = 1; i < sheet.rows.length; i++) {
        try {
          totalRecords++;
          var row = sheet.rows[i];

          // Create a map for the document
          Map<String, dynamic> documentData = {};

          // Map each cell to its corresponding header
          for (int j = 0; j < headers.length && j < row.length; j++) {
            String header = headers[j].toLowerCase().replaceAll(' ', '_');
            var cellValue = row[j];

            // Skip warranty field for inventory table
            if (header == 'warranty') {
              continue;
            }

            // Convert cell value to appropriate type
            if (cellValue != null) {
              // Check if this is a date field and convert Excel serial date
              if (_isDateField(header)) {
                final dateTime = _convertExcelSerialDate(cellValue);
                if (dateTime != null) {
                  documentData[header] = Timestamp.fromDate(dateTime);
                } else {
                  // If conversion fails, store as string
                  documentData[header] = cellValue.toString();
                }
              } else if (cellValue is int || cellValue is double) {
                documentData[header] = cellValue;
              } else {
                documentData[header] = cellValue.toString();
              }
            }
          }

          // Add metadata
          documentData['uploaded_at'] = FieldValue.serverTimestamp();
          documentData['source'] = 'inventory_dev.xlsx';

          // Add user information
          final currentUser = _authService.currentUser;
          if (currentUser != null) {
            documentData['uploaded_by_uid'] = currentUser.uid;
          }

          // Upload to Firestore
          await _firestore.collection('inventory').add(documentData);
          successfulUploads++;

          // Row uploaded successfully
        } catch (e) {
          errors.add('Row $i: ${e.toString()}');
          // Error uploading row, added to errors list
        }
      }

      return {
        'success': true,
        'total_records': totalRecords,
        'successful_uploads': successfulUploads,
        'failed_uploads': totalRecords - successfulUploads,
        'errors': errors,
        'collection': 'inventory',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'collection': 'inventory',
        'errors': <String>[],
        'total_records': 0,
        'successful_uploads': 0,
        'failed_uploads': 0,
      };
    }
  }

  /// Upload transaction log data from Excel file to Firestore (Admin only)
  Future<Map<String, dynamic>> uploadTransactionData() async {
    // Check admin access
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required to upload data.',
        'errors': ['Unauthorized access'],
        'total_records': 0,
        'successful_uploads': 0,
        'failed_uploads': 0,
      };
    }

    try {
      // Load the Excel file from assets
      ByteData data = await rootBundle.load('tables/transaction_log.xlsx');
      var bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      // Decode the Excel file using spreadsheet_decoder
      SpreadsheetDecoder decoder = SpreadsheetDecoder.decodeBytes(bytes);

      int totalRecords = 0;
      int successfulUploads = 0;
      List<String> errors = [];

      // Get the first sheet
      if (decoder.tables.isEmpty) {
        throw Exception('No sheets found in the Excel file');
      }

      String sheetName = decoder.tables.keys.first;
      var sheet = decoder.tables[sheetName];
      if (sheet == null) {
        throw Exception('Sheet "$sheetName" not found in the Excel file');
      }

      // Get headers from the first row
      List<String> headers = [];
      if (sheet.rows.isEmpty) {
        throw Exception('Excel sheet is empty - no data found');
      }

      for (var cell in sheet.rows[0]) {
        headers.add(cell?.toString() ?? '');
      }

      // Transaction headers found and processed

      // Check if there are data rows beyond the header
      if (sheet.rows.length <= 1) {
        throw Exception(
          'Excel sheet only contains headers - no data rows found',
        );
      }

      // Process each row (skip header row)
      for (int i = 1; i < sheet.rows.length; i++) {
        try {
          totalRecords++;
          var row = sheet.rows[i];

          // Create a map for the document
          Map<String, dynamic> documentData = {};

          // Map each cell to its corresponding header
          for (int j = 0; j < headers.length && j < row.length; j++) {
            String header = headers[j].toLowerCase().replaceAll(' ', '_');
            var cellValue = row[j];

            // Convert cell value to appropriate type
            if (cellValue != null) {
              // Check if this is a date field and convert Excel serial date
              if (_isDateField(header)) {
                final dateTime = _convertExcelSerialDate(cellValue);
                if (dateTime != null) {
                  documentData[header] = Timestamp.fromDate(dateTime);
                } else {
                  // If conversion fails, store as string
                  documentData[header] = cellValue.toString();
                }
              } else if (cellValue is int || cellValue is double) {
                documentData[header] = cellValue;
              } else {
                documentData[header] = cellValue.toString();
              }
            }
          }

          // Add metadata
          documentData['uploaded_at'] = FieldValue.serverTimestamp();
          documentData['source'] = 'transaction_log.xlsx';

          // Add user information
          final currentUser = _authService.currentUser;
          if (currentUser != null) {
            documentData['uploaded_by_uid'] = currentUser.uid;
          }

          // Upload to Firestore
          await _firestore.collection('transactions').add(documentData);
          successfulUploads++;

          // Transaction row uploaded successfully
        } catch (e) {
          errors.add('Row $i: ${e.toString()}');
          // Error uploading transaction row, added to errors list
        }
      }

      return {
        'success': true,
        'total_records': totalRecords,
        'successful_uploads': successfulUploads,
        'failed_uploads': totalRecords - successfulUploads,
        'errors': errors,
        'collection': 'transactions',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'collection': 'transactions',
        'errors': <String>[],
        'total_records': 0,
        'successful_uploads': 0,
        'failed_uploads': 0,
      };
    }
  }

  /// Upload both files
  Future<List<Map<String, dynamic>>> uploadAllData() async {
    List<Map<String, dynamic>> results = [];

    // Starting inventory data upload
    results.add(await uploadInventoryData());

    // Starting transaction data upload
    results.add(await uploadTransactionData());

    return results;
  }

  /// Clear all uploaded data (use with caution!) - Admin only
  Future<Map<String, dynamic>> clearCollection(String collectionName) async {
    // Check admin access
    if (!await _authService.isCurrentUserAdmin()) {
      return {
        'success': false,
        'message': 'Access denied. Admin privileges required to clear data.',
        'deleted_count': 0,
      };
    }

    try {
      var collection = _firestore.collection(collectionName);
      var snapshots = await collection.get();

      int deletedCount = 0;
      for (var doc in snapshots.docs) {
        await doc.reference.delete();
        deletedCount++;
      }

      return {
        'success': true,
        'deleted_count': deletedCount,
        'collection': collectionName,
        'errors': <String>[],
        'total_records': deletedCount,
        'successful_uploads': deletedCount,
        'failed_uploads': 0,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'collection': collectionName,
        'errors': <String>[],
        'total_records': 0,
        'successful_uploads': 0,
        'failed_uploads': 0,
      };
    }
  }
}
