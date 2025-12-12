import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Service for extracting invoice data from PDF files using direct text extraction
class InvoiceOcrService {
  static final InvoiceOcrService _instance = InvoiceOcrService._internal();
  factory InvoiceOcrService() => _instance;
  InvoiceOcrService._internal();

  bool _isInitialized = false;

  /// Initialize the service (simplified - no ML Kit needed)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('✅ InvoiceOcrService initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize InvoiceOcrService: $e');
      rethrow;
    }
  }

  /// Dispose of resources (simplified - no ML Kit to dispose)
  Future<void> dispose() async {
    if (_isInitialized) {
      _isInitialized = false;
      debugPrint('🗑️ InvoiceOcrService disposed');
    }
  }

  /// Extract invoice data from PDF files using direct text extraction
  /// Returns a map with 'invoiceNumber', 'invoiceDate', 'confidence', and 'rawText'
  Future<Map<String, dynamic>> extractInvoiceData(File file) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      debugPrint('🔍 Starting PDF text extraction for: ${file.path}');

      // Check file type - only PDF supported now
      final fileExtension = path.extension(file.path).toLowerCase();

      if (fileExtension != '.pdf') {
        return _createErrorResult(
          'Only PDF files are supported. Please select a PDF file.',
        );
      }

      // Read bytes
      final bytes = await file.readAsBytes();
      return await extractInvoiceDataFromBytes(bytes);
    } catch (e) {
      debugPrint('❌ PDF text extraction failed: $e');
      return _createErrorResult('PDF text extraction failed: ${e.toString()}');
    }
  }

  /// Extract invoice data from PDF bytes
  Future<Map<String, dynamic>> extractInvoiceDataFromBytes(
    Uint8List bytes,
  ) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Use direct PDF text extraction
      debugPrint('📄 Using direct PDF text extraction from bytes');
      final extractedText = await _extractTextFromBytes(bytes);

      if (extractedText.isEmpty) {
        return _createErrorResult(
          'No text found in PDF. The PDF might be image-based or encrypted.',
        );
      }

      debugPrint(
        '📄 Extracted text length: ${extractedText.length} characters',
      );

      // Parse the extracted text
      final parsedData = _parseInvoiceData(extractedText);

      return {
        'success': true,
        'invoiceNumber': parsedData['invoiceNumber'],
        'invoiceDate': parsedData['invoiceDate'],
        'confidence': parsedData['confidence'],
        'rawText': extractedText,
        'message': 'PDF text extraction completed successfully',
      };
    } catch (e) {
      debugPrint('❌ PDF text extraction from bytes failed: $e');
      return _createErrorResult('PDF text extraction failed: ${e.toString()}');
    }
  }

  /// Extract text directly from PDF bytes
  Future<String> _extractTextFromBytes(Uint8List pdfBytes) async {
    try {
      debugPrint('📄 Loading PDF document for text extraction...');

      // Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: pdfBytes);

      // Create text extractor
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      // Extract text from first page (where invoice data usually is)
      final String extractedText = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: 0,
      );

      // Dispose the document
      document.dispose();

      debugPrint(
        '✅ PDF text extraction completed. Text length: ${extractedText.length}',
      );
      return extractedText;
    } catch (e) {
      debugPrint('❌ PDF text extraction from bytes failed: $e');
      return '';
    }
  }

  /// Parse extracted text to find invoice number and date
  Map<String, dynamic> _parseInvoiceData(String text) {
    debugPrint('🔍 Parsing invoice data from text...');

    String? invoiceNumber;
    DateTime? invoiceDate;
    double confidence = 0.0;

    // Clean up the text
    final cleanText = text
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    // Invoice Number Patterns
    final invoiceNumberPatterns = [
      RegExp(
        r'invoice\s*(?:no|number|#)[\s:]*([A-Z0-9\-/]+)',
        caseSensitive: false,
      ),
      RegExp(r'inv\s*(?:no|#)[\s:]*([A-Z0-9\-/]+)', caseSensitive: false),
      RegExp(
        r'bill\s*(?:no|number|#)[\s:]*([A-Z0-9\-/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:^|\s)([A-Z]{2,}\d{4,}|\d{4,}[A-Z]{2,})(?:\s|$)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in invoiceNumberPatterns) {
      final match = pattern.firstMatch(cleanText);
      if (match != null) {
        final candidate = match.group(1) ?? match.group(0);
        if (candidate != null && candidate.length >= 3) {
          invoiceNumber = candidate.trim().toUpperCase();
          debugPrint('📋 Found invoice number: $invoiceNumber');
          break;
        }
      }
    }

    // Date Patterns
    final datePatterns = [
      RegExp(
        r'(?:invoice\s*)?date[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:bill\s*)?date[\s:]*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(r'(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{4})'),
      RegExp(r'(\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})'),
    ];

    for (final pattern in datePatterns) {
      final match = pattern.firstMatch(cleanText);
      if (match != null) {
        final dateStr = match.group(1);
        if (dateStr != null) {
          final parsedDate = _parseDate(dateStr);
          if (parsedDate != null) {
            invoiceDate = parsedDate;
            debugPrint('📅 Found invoice date: $invoiceDate');
            break;
          }
        }
      }
    }

    // Calculate confidence based on matches found
    if (invoiceNumber != null && invoiceDate != null) {
      confidence = 0.9; // High confidence when both found
    } else if (invoiceNumber != null || invoiceDate != null) {
      confidence = 0.6; // Medium confidence when one found
    } else {
      confidence = 0.1; // Low confidence when none found
    }

    debugPrint(
      '🎯 OCR Results - Invoice: $invoiceNumber, Date: $invoiceDate, Confidence: $confidence',
    );

    return {
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate,
      'confidence': confidence,
    };
  }

  /// Parse date string to DateTime
  DateTime? _parseDate(String dateStr) {
    try {
      // Remove extra spaces and normalize separators
      final normalized = dateStr.trim().replaceAll(RegExp(r'[\/\-\.]'), '/');

      final parts = normalized.split('/');
      if (parts.length != 3) return null;

      int day, month, year;

      // Try different date formats
      if (parts[0].length == 4) {
        // YYYY/MM/DD format
        year = int.parse(parts[0]);
        month = int.parse(parts[1]);
        day = int.parse(parts[2]);
      } else {
        // DD/MM/YYYY or MM/DD/YYYY format
        // Assume DD/MM/YYYY for most invoices
        day = int.parse(parts[0]);
        month = int.parse(parts[1]);
        year = int.parse(parts[2]);

        // Handle 2-digit years
        if (year < 100) {
          year += (year < 50) ? 2000 : 1900;
        }
      }

      // Validate ranges
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        return null;
      }

      return DateTime(year, month, day);
    } catch (e) {
      debugPrint('❌ Date parsing failed for: $dateStr - $e');
      return null;
    }
  }

  /// Create error result map
  Map<String, dynamic> _createErrorResult(String error) {
    return {
      'success': false,
      'invoiceNumber': null,
      'invoiceDate': null,
      'confidence': 0.0,
      'rawText': '',
      'message': error,
    };
  }

  /// Extract delivery order data from PDF files using direct text extraction
  /// Returns a map with 'deliveryNumber', 'deliveryDate', 'confidence', and 'rawText'
  Future<Map<String, dynamic>> extractDeliveryData(File file) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      debugPrint(
        '🔍 Starting PDF text extraction for delivery order: ${file.path}',
      );

      // Check file type - only PDF supported now
      final fileExtension = path.extension(file.path).toLowerCase();

      if (fileExtension != '.pdf') {
        return _createErrorResult(
          'Only PDF files are supported. Please select a PDF file.',
        );
      }

      // Extract delivery data from bytes
      final bytes = await file.readAsBytes();
      return await extractDeliveryDataFromBytes(bytes);
    } catch (e) {
      debugPrint('❌ Error extracting delivery data: $e');
      return _createErrorResult('Failed to extract delivery data: $e');
    }
  }

  /// Extract delivery order data from PDF bytes
  Future<Map<String, dynamic>> extractDeliveryDataFromBytes(
    Uint8List bytes,
  ) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Extract text from PDF
      final extractedText = await _extractTextFromBytes(bytes);

      if (extractedText.isEmpty) {
        return _createErrorResult(
          'No text could be extracted from the PDF. The file might be image-based or corrupted.',
        );
      }

      debugPrint(
        '📄 Extracted text length: ${extractedText.length} characters',
      );

      // Extract delivery number and date
      final deliveryNumber = _extractDeliveryNumber(extractedText);
      final deliveryDate = _extractDeliveryDate(extractedText);

      // Calculate confidence based on successful extractions
      double confidence = 0.0;
      if (deliveryNumber.isNotEmpty) confidence += 0.5;
      if (deliveryDate != null) confidence += 0.5;

      debugPrint('🎯 Extraction results:');
      debugPrint('   Delivery Number: $deliveryNumber');
      debugPrint('   Delivery Date: $deliveryDate');
      debugPrint('   Confidence: ${(confidence * 100).toInt()}%');

      return {
        'success': true,
        'deliveryNumber': deliveryNumber,
        'deliveryDate': deliveryDate,
        'confidence': confidence,
        'rawText': extractedText,
      };
    } catch (e) {
      debugPrint('❌ Error extracting delivery data from bytes: $e');
      return _createErrorResult('Failed to extract delivery data: $e');
    }
  }

  /// Extract delivery number from text using various patterns
  String _extractDeliveryNumber(String text) {
    final patterns = [
      // Common delivery number patterns
      RegExp(
        r'delivery\s*(?:order\s*)?(?:no\.?|number)\s*:?\s*([A-Z0-9\-/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'do\s*(?:no\.?|number)\s*:?\s*([A-Z0-9\-/]+)',
        caseSensitive: false,
      ),
      RegExp(r'delivery\s*:?\s*([A-Z0-9\-/]+)', caseSensitive: false),
      RegExp(
        r'order\s*(?:no\.?|number)\s*:?\s*([A-Z0-9\-/]+)',
        caseSensitive: false,
      ),
      // Generic patterns for alphanumeric codes
      RegExp(r'\b([A-Z]{2,}\d{3,}|\d{3,}[A-Z]{2,})\b'),
      RegExp(r'\b([A-Z0-9]{6,})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final number = match.group(1)!.trim();
        if (number.length >= 3) {
          debugPrint(
            '✅ Found delivery number with pattern: ${pattern.pattern}',
          );
          return number;
        }
      }
    }

    debugPrint('⚠️ No delivery number found');
    return '';
  }

  /// Extract delivery date from text using various patterns
  DateTime? _extractDeliveryDate(String text) {
    final patterns = [
      // Date patterns with delivery context
      RegExp(
        r'delivery\s*date\s*:?\s*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(
        r'delivered\s*(?:on\s*)?:?\s*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(
        r'date\s*:?\s*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
        caseSensitive: false,
      ),
      // Generic date patterns
      RegExp(r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b'),
      RegExp(r'\b(\d{2,4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        final dateStr = match.group(1)!;
        final parsedDate = _parseDate(dateStr);
        if (parsedDate != null) {
          debugPrint('✅ Found delivery date with pattern: ${pattern.pattern}');
          return parsedDate;
        }
      }
    }

    debugPrint('⚠️ No delivery date found');
    return null;
  }

  /// Check if OCR service is available
  bool get isAvailable => _isInitialized;
}
