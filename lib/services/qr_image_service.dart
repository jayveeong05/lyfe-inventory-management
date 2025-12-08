import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:zxing_lib/zxing.dart';
import 'package:zxing_lib/common.dart';
import 'package:image/image.dart' as img;
import '../screens/image_cropper_screen.dart';

/// Service for decoding QR codes from image files
///
/// Uses zxing_lib pure Dart implementation for cross-platform compatibility
/// Supports all image formats that the image package can decode
class QRImageService {
  /// Pick and decode QR code from an image file
  ///
  /// Returns the decoded QR code string, or null if no QR code found or user cancelled
  static Future<String?> pickAndDecodeQRImage(BuildContext context) async {
    try {
      // Show file picker for image files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
        allowMultiple: false,
        dialogTitle: 'Select QR Code Image',
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // Crop the image using our custom widget screen
        final Uint8List? croppedBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropperScreen(imagePath: filePath),
          ),
        );

        if (croppedBytes != null) {
          return await decodeQRFromImageBytes(croppedBytes);
        }

        return null; // User cancelled cropping
      }

      return null; // User cancelled
    } catch (e) {
      debugPrint('Error picking QR image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  /// Decode QR code from image file path
  ///
  /// Returns the decoded QR code string, or null if no QR code found
  static Future<String?> decodeQRFromImageFile(String filePath) async {
    try {
      // Read image file
      final File imageFile = File(filePath);
      final Uint8List imageBytes = await imageFile.readAsBytes();

      return await decodeQRFromImageBytes(imageBytes);
    } catch (e) {
      debugPrint('Error reading image file: $e');
      return null;
    }
  }

  /// Decode QR code from image bytes
  ///
  /// Returns the decoded QR code string, or null if no QR code found
  static Future<String?> decodeQRFromImageBytes(Uint8List imageBytes) async {
    try {
      // Decode image using image package
      final img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('Failed to decode image');
        return null;
      }

      // Convert image to luminance pixels
      final Uint8List pixels = _imageToLuminancePixels(image);

      // Create luminance source for zxing
      final LuminanceSource source = RGBLuminanceSource.orig(
        image.width,
        image.height,
        pixels,
      );

      // Create binary bitmap
      final BinaryBitmap bitmap = BinaryBitmap(HybridBinarizer(source));

      // Create multi-format reader (includes QR code)
      final MultiFormatReader reader = MultiFormatReader();

      try {
        // Try to decode with hints for better QR detection
        final Result result = reader.decode(
          bitmap,
          const DecodeHint(tryHarder: true, alsoInverted: true),
        );
        return result.text;
      } on NotFoundException {
        debugPrint('No QR code found in image');
        return null;
      } on FormatsException {
        debugPrint('Invalid QR code format');
        return null;
      }
    } catch (e) {
      debugPrint('Error decoding QR from image: $e');
      return null;
    }
  }

  /// Convert image to luminance pixels for zxing
  static Uint8List _imageToLuminancePixels(img.Image image) {
    final Uint8List pixels = Uint8List(image.width * image.height);
    int index = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final img.Pixel pixel = image.getPixel(x, y);

        // Convert to luminance using the same formula as zxing
        final int r = pixel.r.toInt() & 0xff;
        final int g = pixel.g.toInt() & 0xff;
        final int b = pixel.b.toInt() & 0xff;

        // Calculate green-favouring average cheaply (same as zxing example)
        final int luminance = ((r + (g << 1) + b) ~/ 4);
        pixels[index++] = luminance;
      }
    }

    return pixels;
  }

  /// Check if the given file extension is supported for QR decoding
  static bool isSupportedImageFormat(String extension) {
    final supportedFormats = ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'];
    return supportedFormats.contains(extension.toLowerCase());
  }

  /// Get supported image formats as a user-friendly string
  static String get supportedFormatsString {
    return 'JPG, JPEG, PNG, BMP, GIF, WebP';
  }

  /// Show a dialog with QR decoding result
  static void showQRResult(
    BuildContext context,
    String? qrData, {
    VoidCallback? onUseCode,
    VoidCallback? onTryAgain,
  }) {
    if (qrData != null) {
      // Success dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('QR Code Found'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Successfully decoded QR code:'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SelectableText(
                  qrData,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onTryAgain?.call();
              },
              child: const Text('Try Another'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onUseCode?.call();
              },
              child: const Text('Use This Code'),
            ),
          ],
        ),
      );
    } else {
      // Error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.orange),
              SizedBox(width: 8),
              Text('No QR Code Found'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Could not find a QR code in the selected image.'),
              SizedBox(height: 12),
              Text('Tips for better results:'),
              SizedBox(height: 8),
              Text('• Ensure the QR code is clearly visible'),
              Text('• Use good lighting and focus'),
              Text('• Try a higher resolution image'),
              Text('• Make sure the entire QR code is in frame'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                onTryAgain?.call();
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }
  }
}
