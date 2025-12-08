import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'image_cropper_screen.dart';
import '../utils/platform_features.dart';
import '../services/qr_image_service.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  String? scannedData;
  bool isScanning = true;
  final ImagePicker _imagePicker = ImagePicker();

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && scannedData == null && isScanning) {
      final barcode = barcodes.first;
      if (barcode.rawValue != null) {
        setState(() {
          scannedData = barcode.rawValue;
          isScanning = false;
        });
        controller.stop();
      }
    }
  }

  Future<void> _pickImageAndScan() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null) {
        // Stop the camera scanner
        controller.stop();

        // Crop the image using our custom widget screen
        final Uint8List? croppedBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropperScreen(imagePath: image.path),
          ),
        );

        if (croppedBytes != null) {
          // Save cropped bytes to a temporary file for analysis
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/cropped_qr_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          await tempFile.writeAsBytes(croppedBytes);

          // Analyze the picked (and cropped) image for QR codes
          final BarcodeCapture? result = await controller.analyzeImage(
            tempFile.path,
          );

          if (result != null && result.barcodes.isNotEmpty) {
            final barcode = result.barcodes.first;
            if (barcode.rawValue != null) {
              setState(() {
                scannedData = barcode.rawValue;
                isScanning = false;
              });
            } else {
              _showErrorDialog('No QR code found in the selected image.');
              controller.start(); // Restart camera if no QR code found
            }
          } else {
            _showErrorDialog('No QR code found in the selected image.');
            controller.start(); // Restart camera if no QR code found
          }
        } else {
          // User cancelled cropping
          controller.start();
        }
      }
    } catch (e) {
      _showErrorDialog('Error analyzing image: ${e.toString()}');
      controller.start(); // Restart camera on error
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Upload and decode QR code from image file
  Future<void> _uploadAndDecodeQRImage() async {
    final String? qrData = await QRImageService.pickAndDecodeQRImage(context);

    if (qrData != null && mounted) {
      // QR code found - return it
      Navigator.pop(context, qrData);
    }
    // If qrData is null, the service already showed appropriate error messages
  }

  /// Build screen for unsupported platforms
  Widget _buildUnsupportedPlatformScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                'QR Code Scanning Not Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                PlatformFeatures.qrCapabilities,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).primaryColor,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Alternative Options',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Upload QR code image (see button below)\n'
                        '• Use mobile device for QR scanning\n'
                        '• Manually enter equipment codes\n'
                        '• Use barcode scanner hardware',
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // QR Image Upload Button (available on all platforms)
              if (PlatformFeatures.supportsQRImageUpload) ...[
                ElevatedButton.icon(
                  onPressed: _uploadAndDecodeQRImage,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload QR Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if QR scanning is supported on current platform
    if (!PlatformFeatures.supportsQRScanning) {
      return _buildUnsupportedPlatformScreen(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (PlatformFeatures.supportsCameraAccess)
            IconButton(
              icon: const Icon(Icons.photo_library),
              onPressed: _pickImageAndScan,
              tooltip: 'Upload QR Image (Camera)',
            ),
          if (PlatformFeatures.supportsQRImageUpload)
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _uploadAndDecodeQRImage,
              tooltip: 'Upload QR Image (File)',
            ),
          if (PlatformFeatures.isMobile)
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () async {
                await controller.toggleTorch();
              },
              tooltip: 'Toggle Flash',
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                MobileScanner(controller: controller, onDetect: _onDetect),
                // Custom overlay frame
                Container(
                  decoration: const BoxDecoration(color: Colors.transparent),
                  child: CustomPaint(
                    painter: QRScannerOverlay(),
                    child: Container(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (scannedData != null)
                    Column(
                      children: [
                        Text(
                          'Scanned Data:',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          scannedData!,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context, scannedData);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Use This Code'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  scannedData = null;
                                  isScanning = true;
                                });
                                controller.start();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Scan Again'),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        const Icon(
                          Icons.qr_code_scanner,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Position the QR code within the frame to scan',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Or tap the photo icon above to upload a QR image',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

// Custom painter for QR scanner overlay
class QRScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 250,
      height: 250,
    );

    // Draw the overlay with a transparent square in the middle
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(
          RRect.fromRectAndRadius(scanArea, const Radius.circular(12)),
        ),
      ),
      paint,
    );

    // Draw corner brackets
    final bracketPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const bracketLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      Offset(scanArea.left, scanArea.top + bracketLength),
      Offset(scanArea.left, scanArea.top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(scanArea.left, scanArea.top),
      Offset(scanArea.left + bracketLength, scanArea.top),
      bracketPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scanArea.right - bracketLength, scanArea.top),
      Offset(scanArea.right, scanArea.top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(scanArea.right, scanArea.top),
      Offset(scanArea.right, scanArea.top + bracketLength),
      bracketPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scanArea.left, scanArea.bottom - bracketLength),
      Offset(scanArea.left, scanArea.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(scanArea.left, scanArea.bottom),
      Offset(scanArea.left + bracketLength, scanArea.bottom),
      bracketPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scanArea.right - bracketLength, scanArea.bottom),
      Offset(scanArea.right, scanArea.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(scanArea.right, scanArea.bottom),
      Offset(scanArea.right, scanArea.bottom - bracketLength),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
