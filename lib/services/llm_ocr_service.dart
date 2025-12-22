import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/image_utils.dart';

/// Service for OCR using OpenRouter's Gemini Flash vision model
class LlmOcrService {
  static final LlmOcrService _instance = LlmOcrService._internal();
  factory LlmOcrService() => _instance;
  LlmOcrService._internal();

  // Hardcoded model - Gemini Flash 2.0
  static const String _model = 'google/gemini-3-flash-preview';
  static const String _apiEndpoint =
      'https://openrouter.ai/api/v1/chat/completions';

  // API configuration from environment
  String? _apiKey;
  String? _siteUrl;
  String? _siteName;

  bool _isInitialized = false;

  /// Initialize the service with API credentials from .env
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load environment variables
      await dotenv.load(fileName: '.env');

      _apiKey = dotenv.env['OPENROUTER_API_KEY'];
      _siteUrl =
          dotenv.env['OPENROUTER_SITE_URL'] ?? 'https://inventorypro.app';
      _siteName = dotenv.env['OPENROUTER_SITE_NAME'] ?? 'InventoryPro';

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw Exception(
          'OPENROUTER_API_KEY not found in .env file. '
          'Please create a .env file with your API key.',
        );
      }

      _isInitialized = true;
      debugPrint('✅ LlmOcrService initialized successfully');
      debugPrint('   Model: $_model');
      debugPrint('   Site: $_siteName');
    } catch (e) {
      debugPrint('❌ Failed to initialize LlmOcrService: $e');
      rethrow;
    }
  }

  /// Extract invoice or delivery data from image bytes
  Future<Map<String, dynamic>> extractFromImage(
    Uint8List imageBytes,
    String documentType, {
    bool compress = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('🔍 Extracting $documentType data from image...');

      // Compress image if needed
      Uint8List processedBytes = imageBytes;
      if (compress) {
        processedBytes = await ImageUtils.compressImage(
          imageBytes,
          maxSizeKB: 500,
        );
      }

      // Convert to base64
      final base64Image = ImageUtils.convertToBase64(processedBytes);

      // Build prompt
      final prompt = _buildPrompt(documentType);

      // Call Gemini Flash API
      final result = await _callGeminiFlash(base64Image, prompt);

      return result;
    } catch (e) {
      debugPrint('❌ Image extraction failed: $e');
      return _createErrorResult('Image extraction failed: ${e.toString()}');
    }
  }

  /// Extract data from scanned PDF
  Future<Map<String, dynamic>> extractFromPdf(
    Uint8List pdfBytes,
    String documentType,
  ) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('🔍 Extracting from PDF for $documentType...');

      // Send PDF directly to Gemini Flash (works on all platforms)
      debugPrint('📄 Sending PDF directly to Gemini Flash...');
      final base64Pdf = ImageUtils.convertToBase64(pdfBytes);
      final prompt = _buildPrompt(documentType);

      // Gemini Flash can process PDFs natively
      return await _callGeminiFlashWithPdf(base64Pdf, prompt);
    } catch (e) {
      debugPrint('❌ PDF extraction failed: $e');
      return _createErrorResult('PDF extraction failed: ${e.toString()}');
    }
  }

  /// Build extraction prompt based on document type
  String _buildPrompt(String documentType) {
    switch (documentType.toLowerCase()) {
      case 'invoice':
        return '''
You are an expert at extracting data from invoice documents.
Extract the following fields from this invoice image:
- invoice_number: The invoice or bill number
- invoice_date: The invoice date in DD/MM/YYYY format

Return ONLY a JSON object with these fields. If a field cannot be found, use null.
Example response: {"invoice_number": "INV-12345", "invoice_date": "15/12/2024"}
Do not include any explanatory text, only the JSON object.
''';

      case 'delivery':
      case 'delivery_order':
        return '''
You are an expert at extracting data from delivery order documents.
Extract the following fields from this delivery order image:
- delivery_number: The delivery order number or reference
- delivery_date: The delivery date in DD/MM/YYYY format

Return ONLY a JSON object with these fields. If a field cannot be found, use null.
Example response: {"delivery_number": "DO-67890", "delivery_date": "20/12/2024"}
Do not include any explanatory text, only the JSON object.
''';

      default:
        return '''
You are an expert at extracting data from business documents.
Extract key information from this document and return as a JSON object.
Focus on document number and date fields.
''';
    }
  }

  /// Call Gemini Flash via OpenRouter API
  Future<Map<String, dynamic>> _callGeminiFlash(
    String base64Image,
    String prompt,
  ) async {
    try {
      debugPrint('🌐 Calling Gemini Flash API via OpenRouter...');

      final startTime = DateTime.now();

      // Build request
      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': _siteUrl ?? '',
          'X-Title': _siteName ?? '',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
        }),
      );

      final duration = DateTime.now().difference(startTime);
      debugPrint('⏱️ API call completed in ${duration.inMilliseconds}ms');

      if (response.statusCode != 200) {
        throw Exception(
          'API request failed with status ${response.statusCode}: ${response.body}',
        );
      }

      // Parse response
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract content from OpenRouter response
      final choices = jsonResponse['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('No choices in API response');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;

      if (content == null || content.isEmpty) {
        throw Exception('No content in API response');
      }

      debugPrint('📥 Received response: $content');

      // Parse JSON from response
      return _parseExtractedData(content);
    } catch (e) {
      debugPrint('❌ API call failed: $e');
      return _createErrorResult('API call failed: ${e.toString()}');
    }
  }

  /// Call Gemini Flash with PDF file (for web platform)
  Future<Map<String, dynamic>> _callGeminiFlashWithPdf(
    String base64Pdf,
    String prompt,
  ) async {
    try {
      debugPrint('🌐 Calling Gemini Flash API with PDF via OpenRouter...');

      final startTime = DateTime.now();

      // Build request - send PDF as document
      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': _siteUrl ?? '',
          'X-Title': _siteName ?? '',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  // Send PDF as data URL - Gemini can process PDFs
                  'image_url': {
                    'url': 'data:application/pdf;base64,$base64Pdf',
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
        }),
      );

      final duration = DateTime.now().difference(startTime);
      debugPrint('⏱️ API call completed in ${duration.inMilliseconds}ms');

      if (response.statusCode != 200) {
        throw Exception(
          'API request failed with status ${response.statusCode}: ${response.body}',
        );
      }

      // Parse response
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract content from OpenRouter response
      final choices = jsonResponse['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('No choices in API response');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;

      if (content == null || content.isEmpty) {
        throw Exception('No content in API response');
      }

      debugPrint('📥 Received response from PDF: $content');

      // Parse JSON from response
      return _parseExtractedData(content);
    } catch (e) {
      debugPrint('❌ API call with PDF failed: $e');
      return _createErrorResult('API call with PDF failed: ${e.toString()}');
    }
  }

  /// Parse extracted JSON data from LLM response
  Map<String, dynamic> _parseExtractedData(String content) {
    try {
      // Try to find JSON in the response (sometimes LLMs add extra text)
      final jsonMatch = RegExp(r'\{[^{}]*\}').firstMatch(content);

      if (jsonMatch == null) {
        throw Exception('No JSON found in response');
      }

      final jsonStr = jsonMatch.group(0)!;
      final extractedData = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Determine document type and extract fields
      String? documentNumber;
      DateTime? documentDate;
      double confidence = 0.0;

      // Check for invoice fields
      if (extractedData.containsKey('invoice_number')) {
        documentNumber = extractedData['invoice_number']?.toString();
        final dateStr = extractedData['invoice_date']?.toString();
        if (dateStr != null) {
          documentDate = _parseDate(dateStr);
        }
      }
      // Check for delivery fields
      else if (extractedData.containsKey('delivery_number')) {
        documentNumber = extractedData['delivery_number']?.toString();
        final dateStr = extractedData['delivery_date']?.toString();
        if (dateStr != null) {
          documentDate = _parseDate(dateStr);
        }
      }

      // Calculate confidence
      if (documentNumber != null && documentDate != null) {
        confidence = 0.95; // High confidence - LLM extracted both fields
      } else if (documentNumber != null || documentDate != null) {
        confidence = 0.7; // Medium confidence - one field found
      } else {
        confidence = 0.3; // Low confidence - no fields found
      }

      debugPrint('📊 Extraction results:');
      debugPrint('   Number: $documentNumber');
      debugPrint('   Date: $documentDate');
      debugPrint('   Confidence: ${(confidence * 100).toInt()}%');

      // Return in invoice format (compatible with existing code)
      return {
        'success': true,
        'invoiceNumber': documentNumber,
        'invoiceDate': documentDate,
        'deliveryNumber': documentNumber, // Also include for delivery orders
        'deliveryDate': documentDate,
        'confidence': confidence,
        'rawText': content,
        'message': 'Gemini Flash extraction completed successfully',
        'extractionMethod': 'gemini_flash',
      };
    } catch (e) {
      debugPrint('❌ Failed to parse extracted data: $e');
      return _createErrorResult(
        'Failed to parse extracted data: ${e.toString()}',
      );
    }
  }

  /// Parse date string to DateTime (supports DD/MM/YYYY format)
  DateTime? _parseDate(String dateStr) {
    try {
      // Remove extra spaces and normalize separators
      final normalized = dateStr.trim().replaceAll(RegExp(r'[\/\-\.]'), '/');

      final parts = normalized.split('/');
      if (parts.length != 3) return null;

      int day, month, year;

      // Try DD/MM/YYYY format (most common for invoices)
      day = int.parse(parts[0]);
      month = int.parse(parts[1]);
      year = int.parse(parts[2]);

      // Handle 2-digit years
      if (year < 100) {
        year += (year < 50) ? 2000 : 1900;
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
      'deliveryNumber': null,
      'deliveryDate': null,
      'confidence': 0.0,
      'rawText': '',
      'message': error,
      'extractionMethod': 'gemini_flash',
    };
  }

  /// Check if service is available
  bool get isAvailable => _isInitialized;

  /// Get current model name
  String get modelName => _model;
}
