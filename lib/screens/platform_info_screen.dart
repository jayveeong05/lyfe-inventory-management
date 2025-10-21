import 'package:flutter/material.dart';
import '../utils/platform_features.dart';

/// Debug screen to show platform capabilities and feature detection
class PlatformInfoScreen extends StatelessWidget {
  const PlatformInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Information'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Information',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Platform', PlatformFeatures.platformName),
                    _buildInfoRow('Type', PlatformFeatures.isDesktop ? 'Desktop' : 'Mobile'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Feature Support Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Feature Support',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureRow('QR Code Scanning', PlatformFeatures.supportsQRScanning),
                    _buildFeatureRow('Image OCR', PlatformFeatures.supportsImageOCR),
                    _buildFeatureRow('PDF OCR', PlatformFeatures.supportsPDFOCR),
                    _buildFeatureRow('Camera Access', PlatformFeatures.supportsCameraAccess),
                    _buildFeatureRow('File Picker', PlatformFeatures.hasFullFilePickerSupport),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Capabilities Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capabilities',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCapabilityRow('QR Scanning', PlatformFeatures.qrCapabilities),
                    _buildCapabilityRow('OCR Processing', PlatformFeatures.ocrCapabilities),
                    _buildCapabilityRow('File Input', PlatformFeatures.recommendedFileInput),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Test Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: PlatformFeatures.supportsQRScanning 
                        ? () => _showFeatureDialog(context, 'QR Scanning', 'Available') 
                        : () => _showFeatureDialog(context, 'QR Scanning', 'Not Available'),
                    icon: Icon(
                      PlatformFeatures.supportsQRScanning 
                          ? Icons.qr_code_scanner 
                          : Icons.block,
                    ),
                    label: const Text('Test QR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PlatformFeatures.supportsQRScanning 
                          ? Colors.green 
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: PlatformFeatures.supportsImageOCR 
                        ? () => _showFeatureDialog(context, 'Image OCR', 'Available') 
                        : () => _showFeatureDialog(context, 'Image OCR', 'Not Available'),
                    icon: Icon(
                      PlatformFeatures.supportsImageOCR 
                          ? Icons.image_search 
                          : Icons.block,
                    ),
                    label: const Text('Test OCR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PlatformFeatures.supportsImageOCR 
                          ? Colors.blue 
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }
  
  Widget _buildFeatureRow(String feature, bool supported) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            color: supported ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(feature)),
          Text(
            supported ? 'Supported' : 'Not Supported',
            style: TextStyle(
              color: supported ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCapabilityRow(String feature, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            feature,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showFeatureDialog(BuildContext context, String feature, String status) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$feature Test'),
        content: Text('Status: $status\n\nThis is a test of the platform detection system.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
