import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/file_model.dart';

/// Service class for managing the files collection in Firestore
class FilesCollectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get reference to files collection
  CollectionReference get _filesCollection =>
      _firestore.collection(FileConstants.collectionName);

  /// Create a new file record
  Future<String> createFileRecord(FileModel fileModel) async {
    try {
      final docRef = await _filesCollection.add(fileModel.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create file record: ${e.toString()}');
    }
  }

  /// Get file by ID
  Future<FileModel?> getFileById(String fileId) async {
    try {
      final doc = await _filesCollection.doc(fileId).get();
      if (doc.exists) {
        return FileModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get file by ID: ${e.toString()}');
    }
  }

  /// Get active file for order and file type
  Future<FileModel?> getActiveFile(String orderNumber, String fileType) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .where(FileConstants.fieldFileType, isEqualTo: fileType)
          .where(FileConstants.fieldIsActive, isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return FileModel.fromFirestore(query.docs.first);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get active file: ${e.toString()}');
    }
  }

  /// Get all files for an order (with version history)
  Future<List<FileModel>> getFilesForOrder(String orderNumber) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .orderBy(FileConstants.fieldFileType)
          .orderBy(FileConstants.fieldVersion, descending: true)
          .get();

      return query.docs.map((doc) => FileModel.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get files for order: ${e.toString()}');
    }
  }

  /// Get file history for specific order and file type
  Future<List<FileModel>> getFileHistory(
    String orderNumber,
    String fileType,
  ) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .where(FileConstants.fieldFileType, isEqualTo: fileType)
          .orderBy(FileConstants.fieldVersion, descending: true)
          .get();

      return query.docs.map((doc) => FileModel.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get file history: ${e.toString()}');
    }
  }

  /// Get next version number for order and file type
  Future<int> getNextVersionNumber(String orderNumber, String fileType) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .where(FileConstants.fieldFileType, isEqualTo: fileType)
          .orderBy(FileConstants.fieldVersion, descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final latestFile = FileModel.fromFirestore(query.docs.first);
        return latestFile.version + 1;
      }
      return 1; // First version
    } catch (e) {
      throw Exception('Failed to get next version number: ${e.toString()}');
    }
  }

  /// Update file record
  Future<void> updateFileRecord(
    String fileId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final updateData = Map<String, dynamic>.from(updates);
      updateData[FileConstants.fieldUpdatedAt] = FieldValue.serverTimestamp();

      await _filesCollection.doc(fileId).update(updateData);
    } catch (e) {
      throw Exception('Failed to update file record: ${e.toString()}');
    }
  }

  /// Deactivate previous versions when uploading new version
  Future<void> deactivatePreviousVersions(
    String orderNumber,
    String fileType,
    String excludeFileId,
  ) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .where(FileConstants.fieldFileType, isEqualTo: fileType)
          .where(FileConstants.fieldIsActive, isEqualTo: true)
          .get();

      final batch = _firestore.batch();

      for (final doc in query.docs) {
        if (doc.id != excludeFileId) {
          batch.update(doc.reference, {
            FileConstants.fieldIsActive: false,
            FileConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
          });
        }
      }

      if (query.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      throw Exception(
        'Failed to deactivate previous versions: ${e.toString()}',
      );
    }
  }

  /// Delete file record
  Future<void> deleteFileRecord(String fileId) async {
    try {
      await _filesCollection.doc(fileId).delete();
    } catch (e) {
      throw Exception('Failed to delete file record: ${e.toString()}');
    }
  }

  /// Get files by upload date range
  Future<List<FileModel>> getFilesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final query = await _filesCollection
          .where(
            FileConstants.fieldUploadDate,
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where(
            FileConstants.fieldUploadDate,
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          )
          .orderBy(FileConstants.fieldUploadDate, descending: true)
          .get();

      return query.docs.map((doc) => FileModel.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get files by date range: ${e.toString()}');
    }
  }

  /// Get files by user
  Future<List<FileModel>> getFilesByUser(String userId) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldUploadedBy, isEqualTo: userId)
          .orderBy(FileConstants.fieldUploadDate, descending: true)
          .get();

      return query.docs.map((doc) => FileModel.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get files by user: ${e.toString()}');
    }
  }

  /// Check if order has both required files (invoice and delivery order)
  Future<Map<String, bool>> checkOrderFileStatus(String orderNumber) async {
    try {
      final invoiceFile = await getActiveFile(
        orderNumber,
        FileConstants.fileTypeInvoice,
      );
      final deliveryFile = await getActiveFile(
        orderNumber,
        FileConstants.fileTypeDeliveryOrder,
      );

      return {
        'has_invoice': invoiceFile != null,
        'has_delivery_order': deliveryFile != null,
        'is_complete': invoiceFile != null && deliveryFile != null,
      };
    } catch (e) {
      throw Exception('Failed to check order file status: ${e.toString()}');
    }
  }

  /// Get file statistics
  Future<Map<String, int>> getFileStatistics() async {
    try {
      final allFiles = await _filesCollection.get();
      final activeFiles = await _filesCollection
          .where(FileConstants.fieldIsActive, isEqualTo: true)
          .get();

      int invoiceCount = 0;
      int deliveryOrderCount = 0;

      for (final doc in activeFiles.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final fileType = data[FileConstants.fieldFileType] as String?;
        if (fileType == FileConstants.fileTypeInvoice) {
          invoiceCount++;
        } else if (fileType == FileConstants.fileTypeDeliveryOrder) {
          deliveryOrderCount++;
        }
      }

      return {
        'total_files': allFiles.docs.length,
        'active_files': activeFiles.docs.length,
        'invoice_files': invoiceCount,
        'delivery_order_files': deliveryOrderCount,
      };
    } catch (e) {
      throw Exception('Failed to get file statistics: ${e.toString()}');
    }
  }

  /// Stream active files for real-time updates
  Stream<List<FileModel>> streamActiveFilesForOrder(String orderNumber) {
    return _filesCollection
        .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
        .where(FileConstants.fieldIsActive, isEqualTo: true)
        .orderBy(FileConstants.fieldFileType)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => FileModel.fromFirestore(doc)).toList(),
        );
  }

  /// Stream file history for real-time updates
  Stream<List<FileModel>> streamFileHistory(
    String orderNumber,
    String fileType,
  ) {
    return _filesCollection
        .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
        .where(FileConstants.fieldFileType, isEqualTo: fileType)
        .orderBy(FileConstants.fieldVersion, descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => FileModel.fromFirestore(doc)).toList(),
        );
  }
}
