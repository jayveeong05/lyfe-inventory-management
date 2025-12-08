import 'dart:io';
import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class ImageCropperScreen extends StatefulWidget {
  final String imagePath;

  const ImageCropperScreen({Key? key, required this.imagePath})
    : super(key: key);

  @override
  State<ImageCropperScreen> createState() => _ImageCropperScreenState();
}

class _ImageCropperScreenState extends State<ImageCropperScreen> {
  final _cropController = CropController();
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();
      setState(() {
        _imageData = bytes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading image: $e')));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Image'),
        actions: [
          if (!_isLoading && !_isCropping)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                setState(() {
                  _isCropping = true;
                });
                _cropController.crop();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Crop(
                  image: _imageData!,
                  controller: _cropController,
                  onCropped: (image) {
                    // image is Uint8List
                    Navigator.pop(context, image);
                  },
                  aspectRatio: null, // Free crop
                  // initialSize: 0.5,
                  // withCircleUi: false,
                  baseColor: Colors.black,
                  maskColor: Colors.black.withOpacity(0.5),
                  progressIndicator: const CircularProgressIndicator(),
                  radius: 20,
                  cornerDotBuilder: (size, edgeAlignment) =>
                      const DotControl(color: Colors.white),
                  interactive: true,
                  // fixArea: true,
                ),
                if (_isCropping)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
