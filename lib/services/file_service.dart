import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/file_model.dart';
import '../services/files_collection_service.dart';
import '../services/auth_service.dart';

/// Upload file result model
class FileUploadResult {
  final bool success;
  final String? fileId;
  final String? downloadUrl;
  final String? error;
  final FileModel? fileModel;

  const FileUploadResult({
    required this.success,
    this.fileId,
    this.downloadUrl,
    this.error,
    this.fileModel,
  });

  factory FileUploadResult.success({
    required String fileId,
    required String downloadUrl,
    required FileModel fileModel,
  }) {
    return FileUploadResult(
      success: true,
      fileId: fileId,
      downloadUrl: downloadUrl,
      fileModel: fileModel,
    );
  }

  factory FileUploadResult.error(String error) {
    return FileUploadResult(success: false, error: error);
  }
}

/// Service for handling file uploads, validation, and management
class FileService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FilesCollectionService _filesCollectionService =
      FilesCollectionService();
  final AuthService _authService;

  FileService({required AuthService authService}) : _authService = authService;

  /// Validate file before upload
  Future<Map<String, dynamic>> validateFile(File file, String fileType) async {
    try {
      // Check if file exists
      if (!await file.exists()) {
        return {'valid': false, 'error': 'File does not exist'};
      }

      // Check file extension
      final fileName = file.path.toLowerCase();
      if (!FileConstants.allowedExtensions.any(
        (ext) => fileName.endsWith(ext),
      )) {
        return {
          'valid': false,
          'error':
              'Only PDF files are allowed. Allowed extensions: ${FileConstants.allowedExtensions.join(', ')}',
        };
      }

      // Check file size
      final fileSize = await file.length();
      if (fileSize > FileConstants.maxFileSizeBytes) {
        final maxSizeMB = (FileConstants.maxFileSizeBytes / (1024 * 1024))
            .toStringAsFixed(1);
        final currentSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        return {
          'valid': false,
          'error':
              'File size (${currentSizeMB}MB) exceeds maximum allowed size of ${maxSizeMB}MB',
        };
      }

      // Validate file format based on file header
      final bytes = await file.readAsBytes();

      // Determine expected file type
      bool isValidFormat = false;

      if (fileName.endsWith('.pdf')) {
        // PDF validation - check file header (%PDF)
        if (bytes.length >= 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46) {
          isValidFormat = true;
        }
      } else if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
        // JPEG validation - check file header (0xFFD8FF)
        if (bytes.length >= 3 &&
            bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF) {
          isValidFormat = true;
        }
      } else if (fileName.endsWith('.png')) {
        // PNG validation - check file header (0x89504E47)
        if (bytes.length >= 4 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47) {
          isValidFormat = true;
        }
      }

      if (!isValidFormat) {
        return {
          'valid': false,
          'error': 'Invalid file format or corrupted file',
        };
      }

      // Validate file type
      if (![
        'invoice',
        'delivery_order',
        'signed_delivery_order',
      ].contains(fileType)) {
        return {
          'valid': false,
          'error':
              'Invalid file type. Must be "invoice", "delivery_order", or "signed_delivery_order"',
        };
      }

      return {
        'valid': true,
        'file_size': fileSize,
        'file_name': file.path.split('/').last,
      };
    } catch (e) {
      return {
        'valid': false,
        'error': 'File validation failed: ${e.toString()}',
      };
    }
  }

  /// Validate file from bytes (for web compatibility)
  Future<Map<String, dynamic>> validateFileFromBytes(
    Uint8List bytes,
    String fileName,
    String fileType,
  ) async {
    try {
      // Check file extension
      final lowerFileName = fileName.toLowerCase();
      if (!FileConstants.allowedExtensions.any(
        (ext) => lowerFileName.endsWith(ext),
      )) {
        return {
          'valid': false,
          'error':
              'Only PDF files are allowed. Allowed extensions: ${FileConstants.allowedExtensions.join(', ')}',
        };
      }

      // Check file size
      final fileSize = bytes.length;
      if (fileSize > FileConstants.maxFileSizeBytes) {
        final maxSizeMB = (FileConstants.maxFileSizeBytes / (1024 * 1024))
            .toStringAsFixed(1);
        final currentSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        return {
          'valid': false,
          'error':
              'File size (${currentSizeMB}MB) exceeds maximum allowed size of ${maxSizeMB}MB',
        };
      }

      // Validate file format based on file header

      // Determine expected file type
      bool isValidFormat = false;

      if (lowerFileName.endsWith('.pdf')) {
        // PDF validation - check file header (%PDF)
        if (bytes.length >= 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46) {
          isValidFormat = true;
        }
      } else if (lowerFileName.endsWith('.jpg') ||
          lowerFileName.endsWith('.jpeg')) {
        // JPEG validation - check file header (0xFFD8FF)
        if (bytes.length >= 3 &&
            bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF) {
          isValidFormat = true;
        }
      } else if (lowerFileName.endsWith('.png')) {
        // PNG validation - check file header (0x89504E47)
        if (bytes.length >= 4 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47) {
          isValidFormat = true;
        }
      }

      if (!isValidFormat) {
        return {
          'valid': false,
          'error': 'Invalid file format or corrupted file',
        };
      }

      // Validate file type
      if (![
        'invoice',
        'delivery_order',
        'signed_delivery_order',
      ].contains(fileType)) {
        return {
          'valid': false,
          'error':
              'Invalid file type. Must be "invoice", "delivery_order", or "signed_delivery_order"',
        };
      }

      return {'valid': true, 'file_size': fileSize, 'file_name': fileName};
    } catch (e) {
      return {
        'valid': false,
        'error': 'File validation failed: ${e.toString()}',
      };
    }
  }

  /// Generate file path for Firebase Storage
  String _generateFilePath(
    String orderNumber,
    String fileType,
    String originalFilename,
  ) {
    final timestamp = DateTime.now();
    final dateStr = timestamp
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('T')[0];
    final timeStr = timestamp
        .toIso8601String()
        .split('T')[1]
        .replaceAll(':', '')
        .split('.')[0];

    final basePath = fileType == 'invoice'
        ? FileConstants.storagePathInvoices
        : FileConstants.storagePathDeliveryOrders;

    // Get file extension from original filename
    final extension = originalFilename.split('.').last.toLowerCase();

    String fileName;
    if (fileType == 'invoice') {
      fileName = 'invoice_${orderNumber}_${dateStr}_$timeStr.$extension';
    } else if (fileType == 'delivery_order') {
      fileName = 'delivery_${orderNumber}_${dateStr}_$timeStr.$extension';
    } else if (fileType == 'signed_delivery_order') {
      fileName =
          'signed_delivery_${orderNumber}_${dateStr}_$timeStr.$extension';
    } else {
      fileName = 'unknown_${orderNumber}_${dateStr}_$timeStr.$extension';
    }

    return '$basePath/$fileName';
  }

  /// Get MIME type based on file extension
  String _getMimeType(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  /// Upload file to Firebase Storage with retry logic and timeout
  Future<String> _uploadToStorage(
    File file,
    String filePath,
    String filename, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    Exception? lastException;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final ref = _storage.ref().child(filePath);

        // Set metadata with correct MIME type
        final metadata = SettableMetadata(
          contentType: _getMimeType(filename),
          customMetadata: {
            'uploaded_by': _authService.currentUser?.uid ?? 'unknown',
            'upload_attempt': attempt.toString(),
            'upload_timestamp': DateTime.now().toIso8601String(),
          },
        );

        // Upload file with timeout
        final uploadTask = ref.putFile(file, metadata);

        // Wait for upload to complete with timeout
        final snapshot = await uploadTask.timeout(
          timeout,
          onTimeout: () {
            // Cancel the upload task
            uploadTask.cancel();
            throw Exception(
              'Network connection timeout. Please check your internet connection and try again.',
            );
          },
        );

        // Get download URL
        final downloadUrl = await snapshot.ref.getDownloadURL();

        return downloadUrl;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());

        if (attempt < maxRetries) {
          // Wait before retry (shorter delay for faster feedback)
          await Future.delayed(Duration(seconds: 2));
        }
      }
    }

    throw lastException ??
        Exception('Upload failed after $maxRetries attempts');
  }

  /// Upload file and create database record
  Future<FileUploadResult> uploadFile({
    required File file,
    required String orderNumber,
    required String fileType,
    String? originalFilename,
  }) async {
    try {
      // Get current user
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return FileUploadResult.error('User not authenticated');
      }

      // Validate file
      final validation = await validateFile(file, fileType);
      if (!validation['valid']) {
        return FileUploadResult.error(validation['error']);
      }

      // Generate file path
      final filename = originalFilename ?? validation['file_name'];
      final filePath = _generateFilePath(orderNumber, fileType, filename);

      // Get next version number
      final nextVersion = await _filesCollectionService.getNextVersionNumber(
        orderNumber,
        fileType,
      );

      // Upload to Firebase Storage
      final downloadUrl = await _uploadToStorage(file, filePath, filename);

      // Create file model
      final fileModel = FileModel(
        fileId: '', // Will be set after Firestore creation
        orderNumber: orderNumber,
        fileType: fileType,
        filePath: filePath,
        storageUrl: downloadUrl,
        uploadDate: DateTime.now(),
        uploadedBy: currentUser.uid,
        fileSize: validation['file_size'],
        originalFilename: originalFilename ?? validation['file_name'],
        version: nextVersion,
        isActive: true,
      );

      // Create database record
      final fileId = await _filesCollectionService.createFileRecord(fileModel);

      // Deactivate previous versions
      await _filesCollectionService.deactivatePreviousVersions(
        orderNumber,
        fileType,
        fileId,
      );

      // Return updated file model with ID
      final updatedFileModel = fileModel.copyWith(fileId: fileId);

      return FileUploadResult.success(
        fileId: fileId,
        downloadUrl: downloadUrl,
        fileModel: updatedFileModel,
      );
    } catch (e) {
      return FileUploadResult.error('Upload failed: ${e.toString()}');
    }
  }

  /// Upload file from bytes (for web compatibility)
  Future<FileUploadResult> uploadFileFromBytes({
    required Uint8List bytes,
    required String orderNumber,
    required String fileType,
    required String originalFilename,
  }) async {
    try {
      // Get current user
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return FileUploadResult.error('User not authenticated');
      }

      // Validate file size
      if (bytes.length > FileConstants.maxFileSizeBytes) {
        final maxSizeMB = (FileConstants.maxFileSizeBytes / (1024 * 1024))
            .toStringAsFixed(1);
        final currentSizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        return FileUploadResult.error(
          'File size (${currentSizeMB}MB) exceeds maximum allowed size of ${maxSizeMB}MB',
        );
      }

      // Validate file format based on file header
      final validation = await validateFileFromBytes(
        bytes,
        originalFilename,
        fileType,
      );
      if (!validation['valid']) {
        return FileUploadResult.error(validation['error']);
      }

      // Validate file type
      if (![
        'invoice',
        'delivery_order',
        'signed_delivery_order',
      ].contains(fileType)) {
        return FileUploadResult.error(
          'Invalid file type. Must be "invoice", "delivery_order", or "signed_delivery_order"',
        );
      }

      // Generate file path
      final filePath = _generateFilePath(
        orderNumber,
        fileType,
        originalFilename,
      );

      // Get next version number
      final nextVersion = await _filesCollectionService.getNextVersionNumber(
        orderNumber,
        fileType,
      );

      // Upload to Firebase Storage
      final downloadUrl = await _uploadBytesToStorage(
        bytes,
        filePath,
        originalFilename,
      );

      // Create file model
      final fileModel = FileModel(
        fileId: '', // Will be set after Firestore creation
        orderNumber: orderNumber,
        fileType: fileType,
        filePath: filePath,
        storageUrl: downloadUrl,
        uploadDate: DateTime.now(),
        uploadedBy: currentUser.uid,
        fileSize: bytes.length,
        originalFilename: originalFilename,
        version: nextVersion,
        isActive: true,
      );

      // Create database record
      final fileId = await _filesCollectionService.createFileRecord(fileModel);

      // Deactivate previous versions
      await _filesCollectionService.deactivatePreviousVersions(
        orderNumber,
        fileType,
        fileId,
      );

      // Return updated file model with ID
      final updatedFileModel = fileModel.copyWith(fileId: fileId);

      return FileUploadResult.success(
        fileId: fileId,
        downloadUrl: downloadUrl,
        fileModel: updatedFileModel,
      );
    } catch (e) {
      return FileUploadResult.error('Upload failed: ${e.toString()}');
    }
  }

  /// Upload bytes to Firebase Storage with retry logic and timeout
  Future<String> _uploadBytesToStorage(
    Uint8List bytes,
    String filePath,
    String filename, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    Exception? lastException;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final ref = _storage.ref().child(filePath);

        // Set metadata with correct MIME type
        final metadata = SettableMetadata(
          contentType: _getMimeType(filename),
          customMetadata: {
            'uploaded_by': _authService.currentUser?.uid ?? 'unknown',
            'upload_attempt': attempt.toString(),
            'upload_timestamp': DateTime.now().toIso8601String(),
          },
        );

        // Upload bytes with timeout
        final uploadTask = ref.putData(bytes, metadata);

        // Wait for upload to complete with timeout
        final snapshot = await uploadTask.timeout(
          timeout,
          onTimeout: () {
            // Cancel the upload task
            uploadTask.cancel();
            throw Exception(
              'Network connection timeout. Please check your internet connection and try again.',
            );
          },
        );

        // Get download URL
        final downloadUrl = await snapshot.ref.getDownloadURL();

        return downloadUrl;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());

        if (attempt < maxRetries) {
          // Wait before retry (shorter delay for faster feedback)
          await Future.delayed(Duration(seconds: 2));
        }
      }
    }

    throw lastException ??
        Exception('Upload failed after $maxRetries attempts');
  }

  /// Delete file from both Storage and Firestore
  Future<Map<String, dynamic>> deleteFile(String fileId) async {
    try {
      // Get file record
      final fileModel = await _filesCollectionService.getFileById(fileId);
      if (fileModel == null) {
        return {'success': false, 'error': 'File not found'};
      }

      // Delete from Firebase Storage
      try {
        final ref = _storage.ref().child(fileModel.filePath);
        await ref.delete();
      } catch (e) {
        // Continue even if storage deletion fails (file might not exist)
        // In production, use a proper logging framework instead of print
        // ignore: avoid_print
        print('Warning: Failed to delete file from storage: ${e.toString()}');
      }

      // Delete from Firestore
      await _filesCollectionService.deleteFileRecord(fileId);

      return {
        'success': true,
        'message': 'File deleted successfully',
        'file_id': fileId,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to delete file: ${e.toString()}',
      };
    }
  }

  /// Get download URL for a file
  Future<String?> getDownloadUrl(String fileId) async {
    try {
      final fileModel = await _filesCollectionService.getFileById(fileId);
      return fileModel?.storageUrl;
    } catch (e) {
      return null;
    }
  }

  /// Download file as bytes
  Future<Uint8List?> downloadFileAsBytes(String fileId) async {
    try {
      final fileModel = await _filesCollectionService.getFileById(fileId);
      if (fileModel == null) return null;

      final ref = _storage.ref().child(fileModel.filePath);
      final bytes = await ref.getData();
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Check if order has required files
  Future<Map<String, bool>> checkOrderFileStatus(String orderNumber) async {
    return await _filesCollectionService.checkOrderFileStatus(orderNumber);
  }

  /// Get active files for an order
  Future<List<FileModel>> getActiveFilesForOrder(String orderNumber) async {
    final allFiles = await _filesCollectionService.getFilesForOrder(
      orderNumber,
    );
    return allFiles.where((file) => file.isActive).toList();
  }

  /// Get file history for order and type
  Future<List<FileModel>> getFileHistory(
    String orderNumber,
    String fileType,
  ) async {
    return await _filesCollectionService.getFileHistory(orderNumber, fileType);
  }

  /// Stream active files for real-time updates
  Stream<List<FileModel>> streamActiveFilesForOrder(String orderNumber) {
    return _filesCollectionService.streamActiveFilesForOrder(orderNumber);
  }

  /// Replace existing file with new version
  Future<FileUploadResult> replaceFile({
    required String orderNumber,
    required String fileType,
    required File newFile,
    String? originalFilename,
  }) async {
    // This is essentially the same as uploadFile since version management
    // is handled automatically by deactivating previous versions
    return await uploadFile(
      file: newFile,
      orderNumber: orderNumber,
      fileType: fileType,
      originalFilename: originalFilename,
    );
  }

  /// Replace existing file with new version from bytes
  Future<FileUploadResult> replaceFileFromBytes({
    required String orderNumber,
    required String fileType,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    return await uploadFileFromBytes(
      bytes: bytes,
      orderNumber: orderNumber,
      fileType: fileType,
      originalFilename: originalFilename,
    );
  }

  /// Get file statistics
  Future<Map<String, int>> getFileStatistics() async {
    return await _filesCollectionService.getFileStatistics();
  }

  /// Cleanup old file versions (keep only latest N versions)
  Future<Map<String, dynamic>> cleanupOldVersions(
    String orderNumber,
    String fileType, {
    int keepVersions = 3,
  }) async {
    try {
      final fileHistory = await _filesCollectionService.getFileHistory(
        orderNumber,
        fileType,
      );

      if (fileHistory.length <= keepVersions) {
        return {
          'success': true,
          'message': 'No cleanup needed',
          'deleted_count': 0,
        };
      }

      // Sort by version descending and keep only the latest versions
      fileHistory.sort((a, b) => b.version.compareTo(a.version));
      final filesToDelete = fileHistory.skip(keepVersions).toList();

      int deletedCount = 0;
      for (final file in filesToDelete) {
        final result = await deleteFile(file.fileId);
        if (result['success']) {
          deletedCount++;
        }
      }

      return {
        'success': true,
        'message': 'Cleanup completed',
        'deleted_count': deletedCount,
        'total_files': fileHistory.length,
        'kept_files': fileHistory.length - deletedCount,
      };
    } catch (e) {
      return {'success': false, 'error': 'Cleanup failed: ${e.toString()}'};
    }
  }

  /// Validate file exists in storage
  Future<bool> validateFileExists(String fileId) async {
    try {
      final fileModel = await _filesCollectionService.getFileById(fileId);
      if (fileModel == null) return false;

      final ref = _storage.ref().child(fileModel.filePath);
      await ref.getMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get file metadata from storage
  Future<Map<String, dynamic>?> getFileMetadata(String fileId) async {
    try {
      final fileModel = await _filesCollectionService.getFileById(fileId);
      if (fileModel == null) return null;

      final ref = _storage.ref().child(fileModel.filePath);
      final metadata = await ref.getMetadata();

      return {
        'name': metadata.name,
        'bucket': metadata.bucket,
        'full_path': metadata.fullPath,
        'size': metadata.size,
        'time_created': metadata.timeCreated?.toIso8601String(),
        'updated': metadata.updated?.toIso8601String(),
        'content_type': metadata.contentType,
        'custom_metadata': metadata.customMetadata,
      };
    } catch (e) {
      return null;
    }
  }
}
