import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:path/path.dart' as path;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Service for extracting invoice data from PDF files using OCR
class InvoiceOcrService {
  static final InvoiceOcrService _instance = InvoiceOcrService._internal();
  factory InvoiceOcrService() => _instance;
  InvoiceOcrService._internal();

  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  /// Initialize the OCR service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _textRecognizer = TextRecognizer();
      _isInitialized = true;
      debugPrint('✅ InvoiceOcrService initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize InvoiceOcrService: $e');
      rethrow;
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    if (_isInitialized) {
      await _textRecognizer.close();
      _isInitialized = false;
      debugPrint('🗑️ InvoiceOcrService disposed');
    }
  }

  /// Extract invoice data from PDF or image file
  /// Returns a map with 'invoiceNumber', 'invoiceDate', 'confidence', and 'rawText'
  Future<Map<String, dynamic>> extractInvoiceData(File file) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      debugPrint('🔍 Starting OCR extraction for: ${file.path}');

      // Check file type and handle accordingly
      final fileExtension = path.extension(file.path).toLowerCase();
      late final InputImage inputImage;

      late final String extractedText;

      if (fileExtension == '.pdf') {
        // Use direct PDF text extraction (much faster and more accurate!)
        debugPrint('📄 Using direct PDF text extraction');
        extractedText = await _extractTextFromPdf(file);

        if (extractedText.isEmpty) {
          return _createErrorResult(
            'No text found in PDF. The PDF might be image-based or encrypted. '
            'Please convert to an image file and try again.',
          );
        }
      } else if (['.png', '.jpg', '.jpeg'].contains(fileExtension)) {
        // Handle image files with OCR
        debugPrint('📷 Processing image file with OCR');
        inputImage = InputImage.fromFilePath(file.path);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        extractedText = recognizedText.text;
      } else {
        return _createErrorResult(
          'Unsupported file format. Please use PDF, PNG, JPG, or JPEG files.',
        );
      }

      debugPrint(
        '📄 Extracted text length: ${extractedText.length} characters',
      );

      // Step 3: Parse the extracted text
      final parsedData = _parseInvoiceData(extractedText);

      return {
        'success': true,
        'invoiceNumber': parsedData['invoiceNumber'],
        'invoiceDate': parsedData['invoiceDate'],
        'confidence': parsedData['confidence'],
        'rawText': extractedText,
        'message': 'OCR extraction completed successfully',
      };
    } catch (e) {
      debugPrint('❌ OCR extraction failed: $e');
      return _createErrorResult('OCR extraction failed: ${e.toString()}');
    }
  }

  /// Extract text directly from PDF using Syncfusion PDF library
  Future<String> _extractTextFromPdf(File pdfFile) async {
    try {
      debugPrint('📄 Loading PDF document for text extraction...');

      // Read PDF file bytes
      final pdfBytes = await pdfFile.readAsBytes();

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
      debugPrint('❌ PDF text extraction failed: $e');
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

  /// Check if OCR service is available
  bool get isAvailable => _isInitialized;
}
