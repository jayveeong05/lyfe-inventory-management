import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Utility functions for image processing and conversion for OCR
class ImageUtils {
  /// Convert bytes to base64 string
  static String convertToBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }

  /// Compress image to reduce size for API transmission
  /// Target: Keep image under maxSizeKB while maintaining readability
  static Future<Uint8List> compressImage(
    Uint8List bytes, {
    int maxSizeKB = 500,
    int quality = 85,
  }) async {
    try {
      // If already small enough, return as-is
      if (bytes.length <= maxSizeKB * 1024) {
        debugPrint('✅ Image already under size limit (${bytes.length} bytes)');
        return bytes;
      }

      debugPrint('🗜️ Compressing image from ${bytes.length} bytes...');

      // Decode image
      img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize if too large (keep aspect ratio)
      const int maxDimension = 2048;
      if (image.width > maxDimension || image.height > maxDimension) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: maxDimension);
        } else {
          image = img.copyResize(image, height: maxDimension);
        }
      }

      // Encode as JPEG with quality setting
      List<int> compressedBytes = img.encodeJpg(image, quality: quality);

      // If still too large, reduce quality
      int currentQuality = quality;
      while (compressedBytes.length > maxSizeKB * 1024 && currentQuality > 50) {
        currentQuality -= 10;
        compressedBytes = img.encodeJpg(image, quality: currentQuality);
      }

      debugPrint(
        '✅ Image compressed to ${compressedBytes.length} bytes (quality: $currentQuality)',
      );

      return Uint8List.fromList(compressedBytes);
    } catch (e) {
      debugPrint('⚠️ Image compression failed: $e. Returning original.');
      return bytes;
    }
  }

  /// Detect if PDF appears to be scanned (image-based) vs digital
  /// Uses heuristic: very short extracted text suggests scanned PDF
  static bool isPdfScanned(String extractedText, {int minTextLength = 50}) {
    final cleanText = extractedText.trim();

    // If extracted text is too short, likely scanned
    if (cleanText.length < minTextLength) {
      debugPrint(
        '🔍 PDF appears to be scanned (text length: ${cleanText.length})',
      );
      return true;
    }

    // If text has reasonable length, likely digital
    debugPrint(
      '🔍 PDF appears to be digital (text length: ${cleanText.length})',
    );
    return false;
  }

  /// Convert image bytes to data URL for API
  static String toDataUrl(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    final base64String = convertToBase64(bytes);
    return 'data:$mimeType;base64,$base64String';
  }

  /// Get file extension from bytes by detecting image format
  static String? detectImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // Check magic numbers
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    } else if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    } else if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'pdf';
    }

    return null;
  }
}
