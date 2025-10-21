import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform-specific feature detection for cross-platform compatibility
///
/// This class provides a centralized way to check which features are available
/// on the current platform, enabling graceful degradation on unsupported platforms.
class PlatformFeatures {
  /// Check if QR code scanning is supported on current platform
  ///
  /// Supported on: Android, iOS, macOS, Web
  /// Not supported on: Windows, Linux
  static bool get supportsQRScanning {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Check if QR code image upload/decoding is supported on current platform
  ///
  /// Uses zxing_lib pure Dart implementation - works on all platforms
  /// Supported on: All platforms (Android, iOS, Windows, macOS, Linux, Web)
  static bool get supportsQRImageUpload => true;

  /// Check if ANY QR code functionality is supported on current platform
  ///
  /// Returns true if either camera scanning OR image upload is supported
  /// This should be used for enabling/disabling QR features in the UI
  static bool get supportsAnyQRFeature =>
      supportsQRScanning || supportsQRImageUpload;

  /// Check if image-based OCR is supported on current platform
  ///
  /// Uses Google ML Kit which only supports mobile platforms
  /// Supported on: Android, iOS
  /// Not supported on: Windows, macOS, Linux, Web
  static bool get supportsImageOCR {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if PDF text extraction is supported on current platform
  ///
  /// Uses Syncfusion Flutter PDF which supports all platforms
  /// Supported on: All platforms
  static bool get supportsPDFOCR => true;

  /// Check if camera access is available on current platform
  ///
  /// Supported on: Android, iOS, macOS, Web
  /// Not supported on: Windows, Linux (no camera API)
  static bool get supportsCameraAccess {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Check if the current platform is a desktop platform
  ///
  /// Desktop platforms: Windows, macOS, Linux
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Check if the current platform is a mobile platform
  ///
  /// Mobile platforms: Android, iOS
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Get a user-friendly platform name
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get OCR capabilities description for current platform
  static String get ocrCapabilities {
    if (supportsImageOCR && supportsPDFOCR) {
      return 'PDF and Image OCR supported';
    } else if (supportsPDFOCR) {
      return 'PDF OCR supported (Image OCR not available on $platformName)';
    } else {
      return 'OCR not supported on $platformName';
    }
  }

  /// Get QR scanning capabilities description for current platform
  static String get qrCapabilities {
    if (supportsQRScanning && supportsQRImageUpload) {
      return 'QR code scanning + image upload supported';
    } else if (supportsQRImageUpload) {
      return 'QR code image upload supported (camera scanning not available)';
    } else {
      return 'QR code scanning not available on $platformName';
    }
  }

  /// Check if file picker has full functionality on current platform
  ///
  /// File picker works on all platforms but with varying capabilities
  static bool get hasFullFilePickerSupport {
    // File picker works everywhere but desktop has more features
    return true;
  }

  /// Get recommended file input method for current platform
  static String get recommendedFileInput {
    if (isMobile) {
      return 'Camera, Gallery, or File Browser';
    } else {
      return 'File Browser';
    }
  }
}
