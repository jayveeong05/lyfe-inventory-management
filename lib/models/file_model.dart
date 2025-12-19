import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for file documents in Firestore
class FileModel {
  final String fileId;
  final String orderNumber;
  final String
  fileType; // 'invoice', 'delivery_order', or 'signed_delivery_order'
  final String filePath;
  final String storageUrl;
  final DateTime uploadDate;
  final String uploadedBy;
  final int fileSize;
  final String originalFilename;
  final int version;
  final bool isActive; // true for latest version only

  const FileModel({
    required this.fileId,
    required this.orderNumber,
    required this.fileType,
    required this.filePath,
    required this.storageUrl,
    required this.uploadDate,
    required this.uploadedBy,
    required this.fileSize,
    required this.originalFilename,
    required this.version,
    required this.isActive,
  });

  /// Create FileModel from Firestore document
  factory FileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return FileModel(
      fileId: doc.id,
      orderNumber: data['order_number'] ?? '',
      fileType: data['file_type'] ?? '',
      filePath: data['file_path'] ?? '',
      storageUrl: data['storage_url'] ?? '',
      uploadDate: _parseDateTime(data['upload_date']),
      uploadedBy: data['uploaded_by'] ?? '',
      fileSize: data['file_size'] ?? 0,
      originalFilename: data['original_filename'] ?? '',
      version: data['version'] ?? 1,
      isActive: data['is_active'] ?? false,
    );
  }

  /// Convert FileModel to Firestore document data
  Map<String, dynamic> toFirestore() {
    return {
      'order_number': orderNumber,
      'file_type': fileType,
      'file_path': filePath,
      'storage_url': storageUrl,
      'upload_date': Timestamp.fromDate(uploadDate),
      'uploaded_by': uploadedBy,
      'file_size': fileSize,
      'original_filename': originalFilename,
      'version': version,
      'is_active': isActive,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  /// Create a copy with updated fields
  FileModel copyWith({
    String? fileId,
    String? orderNumber,
    String? fileType,
    String? filePath,
    String? storageUrl,
    DateTime? uploadDate,
    String? uploadedBy,
    int? fileSize,
    String? originalFilename,
    int? version,
    bool? isActive,
  }) {
    return FileModel(
      fileId: fileId ?? this.fileId,
      orderNumber: orderNumber ?? this.orderNumber,
      fileType: fileType ?? this.fileType,
      filePath: filePath ?? this.filePath,
      storageUrl: storageUrl ?? this.storageUrl,
      uploadDate: uploadDate ?? this.uploadDate,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      fileSize: fileSize ?? this.fileSize,
      originalFilename: originalFilename ?? this.originalFilename,
      version: version ?? this.version,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Helper method to parse DateTime from Firestore
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();

    if (value is Timestamp) {
      return value.toDate();
    } else if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }

    return DateTime.now();
  }

  /// Check if this is an invoice file
  bool get isInvoice => fileType == 'invoice';

  /// Check if this is a delivery order file
  bool get isDeliveryOrder => fileType == 'delivery_order';

  /// Get formatted file size
  String get formattedFileSize {
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  /// Get display name for file type
  String get fileTypeDisplayName {
    switch (fileType) {
      case 'invoice':
        return 'Invoice';
      case 'delivery_order':
        return 'Delivery Order';
      default:
        return 'Unknown';
    }
  }

  @override
  String toString() {
    return 'FileModel(fileId: $fileId, orderNumber: $orderNumber, fileType: $fileType, version: $version, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FileModel &&
        other.fileId == fileId &&
        other.orderNumber == orderNumber &&
        other.fileType == fileType &&
        other.version == version;
  }

  @override
  int get hashCode {
    return fileId.hashCode ^
        orderNumber.hashCode ^
        fileType.hashCode ^
        version.hashCode;
  }
}

/// Enum for file types
enum FileType {
  invoice('invoice'),
  deliveryOrder('delivery_order'),
  signedDeliveryOrder('signed_delivery_order');

  const FileType(this.value);
  final String value;

  static FileType fromString(String value) {
    switch (value) {
      case 'invoice':
        return FileType.invoice;
      case 'delivery_order':
        return FileType.deliveryOrder;
      case 'signed_delivery_order':
        return FileType.signedDeliveryOrder;
      default:
        throw ArgumentError('Unknown file type: $value');
    }
  }
}

/// Constants for file collection
class FileConstants {
  static const String collectionName = 'files';

  // Field names
  static const String fieldOrderNumber = 'order_number';
  static const String fieldFileType = 'file_type';
  static const String fieldFilePath = 'file_path';
  static const String fieldStorageUrl = 'storage_url';
  static const String fieldUploadDate = 'upload_date';
  static const String fieldUploadedBy = 'uploaded_by';
  static const String fieldFileSize = 'file_size';
  static const String fieldOriginalFilename = 'original_filename';
  static const String fieldVersion = 'version';
  static const String fieldIsActive = 'is_active';
  static const String fieldCreatedAt = 'created_at';
  static const String fieldUpdatedAt = 'updated_at';

  // File type values
  static const String fileTypeInvoice = 'invoice';
  static const String fileTypeDeliveryOrder = 'delivery_order';
  static const String fileTypeSignedDeliveryOrder = 'signed_delivery_order';

  // Storage paths
  static const String storagePathInvoices = 'files/invoices';
  static const String storagePathDeliveryOrders = 'files/delivery_orders';

  // File constraints
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> allowedExtensions = [
    '.pdf',
    '.jpg',
    '.jpeg',
    '.png',
  ];

  // Query limits
  static const int defaultQueryLimit = 50;
  static const int maxQueryLimit = 100;
}
