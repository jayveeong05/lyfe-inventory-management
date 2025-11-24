import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/file_model.dart';
import '../services/auth_service.dart';
import '../services/files_collection_service.dart';

/// Service class for managing file history and version control
class FileHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final FilesCollectionService _filesCollectionService = FilesCollectionService();

  /// Get reference to files collection
  CollectionReference get _filesCollection =>
      _firestore.collection(FileConstants.collectionName);

  /// Get all file versions for a specific order number
  /// Returns all versions (active and inactive) sorted by version descending
  Future<List<FileModel>> getOrderFileHistory(String orderNumber) async {
    try {
      final query = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: orderNumber)
          .orderBy(FileConstants.fieldVersion, descending: true)
          .get();

      return query.docs.map((doc) => FileModel.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get order file history: ${e.toString()}');
    }
  }

  /// Get file history for specific order and file type
  /// Returns all versions of a specific file type for an order
  Future<List<FileModel>> getOrderFileHistoryByType(
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
      throw Exception('Failed to get file history by type: ${e.toString()}');
    }
  }

  /// Get all orders that have uploaded files
  /// Returns a list of unique order numbers with file counts
  Future<List<Map<String, dynamic>>> getOrdersWithFiles() async {
    try {
      final query = await _filesCollection
          .orderBy(FileConstants.fieldUploadDate, descending: true)
          .get();

      // Group files by order number and count file types
      final Map<String, Map<String, dynamic>> orderMap = {};

      for (final doc in query.docs) {
        final file = FileModel.fromFirestore(doc);
        
        if (!orderMap.containsKey(file.orderNumber)) {
          orderMap[file.orderNumber] = {
            'orderNumber': file.orderNumber,
            'totalFiles': 0,
            'invoiceCount': 0,
            'deliveryCount': 0,
            'signedDeliveryCount': 0,
            'lastUploadDate': file.uploadDate,
          };
        }

        final orderData = orderMap[file.orderNumber]!;
        orderData['totalFiles'] = (orderData['totalFiles'] as int) + 1;

        // Count by file type
        switch (file.fileType) {
          case FileConstants.fileTypeInvoice:
            orderData['invoiceCount'] = (orderData['invoiceCount'] as int) + 1;
            break;
          case FileConstants.fileTypeDeliveryOrder:
            orderData['deliveryCount'] = (orderData['deliveryCount'] as int) + 1;
            break;
          case FileConstants.fileTypeSignedDeliveryOrder:
            orderData['signedDeliveryCount'] = (orderData['signedDeliveryCount'] as int) + 1;
            break;
        }

        // Update last upload date if this file is newer
        if (file.uploadDate.isAfter(orderData['lastUploadDate'] as DateTime)) {
          orderData['lastUploadDate'] = file.uploadDate;
        }
      }

      // Convert to list and sort by last upload date
      final ordersList = orderMap.values.toList();
      ordersList.sort((a, b) => 
        (b['lastUploadDate'] as DateTime).compareTo(a['lastUploadDate'] as DateTime));

      return ordersList;
    } catch (e) {
      throw Exception('Failed to get orders with files: ${e.toString()}');
    }
  }

  /// Restore a previous file version (make it active)
  /// This deactivates the current active version and activates the specified version
  Future<bool> restoreFileVersion(String fileId) async {
    try {
      // Check admin access
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the file to restore
      final fileDoc = await _filesCollection.doc(fileId).get();
      if (!fileDoc.exists) {
        throw Exception('File not found');
      }

      final fileToRestore = FileModel.fromFirestore(fileDoc);

      // Use batch operation for consistency
      final batch = _firestore.batch();

      // Deactivate all current active versions of this file type for this order
      final activeFilesQuery = await _filesCollection
          .where(FileConstants.fieldOrderNumber, isEqualTo: fileToRestore.orderNumber)
          .where(FileConstants.fieldFileType, isEqualTo: fileToRestore.fileType)
          .where(FileConstants.fieldIsActive, isEqualTo: true)
          .get();

      for (final doc in activeFilesQuery.docs) {
        batch.update(doc.reference, {
          FileConstants.fieldIsActive: false,
          FileConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
        });
      }

      // Activate the selected version
      batch.update(fileDoc.reference, {
        FileConstants.fieldIsActive: true,
        FileConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return true;
    } catch (e) {
      throw Exception('Failed to restore file version: ${e.toString()}');
    }
  }

  /// Search orders by order number (partial match)
  Future<List<Map<String, dynamic>>> searchOrdersWithFiles(String searchQuery) async {
    try {
      final allOrders = await getOrdersWithFiles();
      
      if (searchQuery.isEmpty) {
        return allOrders;
      }

      // Filter orders that contain the search query
      return allOrders.where((order) {
        final orderNumber = order['orderNumber'] as String;
        return orderNumber.toLowerCase().contains(searchQuery.toLowerCase());
      }).toList();
    } catch (e) {
      throw Exception('Failed to search orders: ${e.toString()}');
    }
  }
}
