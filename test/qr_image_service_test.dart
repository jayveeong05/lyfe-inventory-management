import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import '../lib/services/qr_image_service.dart';

void main() {
  group('QRImageService', () {
    test('should detect supported image formats', () {
      expect(QRImageService.isSupportedImageFormat('jpg'), true);
      expect(QRImageService.isSupportedImageFormat('jpeg'), true);
      expect(QRImageService.isSupportedImageFormat('png'), true);
      expect(QRImageService.isSupportedImageFormat('bmp'), true);
      expect(QRImageService.isSupportedImageFormat('gif'), true);
      expect(QRImageService.isSupportedImageFormat('webp'), true);
      expect(QRImageService.isSupportedImageFormat('JPG'), true); // case insensitive
      expect(QRImageService.isSupportedImageFormat('txt'), false);
      expect(QRImageService.isSupportedImageFormat('pdf'), false);
    });

    test('should return supported formats string', () {
      final formats = QRImageService.supportedFormatsString;
      expect(formats, contains('JPG'));
      expect(formats, contains('PNG'));
      expect(formats, contains('WebP'));
    });

    test('should handle null image bytes gracefully', () async {
      // Create empty image bytes
      final Uint8List emptyBytes = Uint8List(0);
      
      final result = await QRImageService.decodeQRFromImageBytes(emptyBytes);
      expect(result, isNull);
    });

    test('should handle invalid image data gracefully', () async {
      // Create invalid image bytes
      final Uint8List invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      
      final result = await QRImageService.decodeQRFromImageBytes(invalidBytes);
      expect(result, isNull);
    });

    test('should create simple test image without QR code', () async {
      // Create a simple solid color image
      final img.Image testImage = img.Image(width: 100, height: 100);
      img.fill(testImage, color: img.ColorRgb8(255, 255, 255)); // White image
      
      final Uint8List imageBytes = Uint8List.fromList(img.encodePng(testImage));
      
      final result = await QRImageService.decodeQRFromImageBytes(imageBytes);
      expect(result, isNull); // Should not find QR code in solid white image
    });
  });
}
