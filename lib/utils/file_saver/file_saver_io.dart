import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'file_saver.dart';

class FileSaverIO implements FileSaver {
  @override
  Future<String?> saveFile(String fileName, String content) async {
    try {
      final directory = await _getExportDirectory();
      final file = File('${directory.path}/$fileName');

      // Write with explicit UTF-8 encoding
      // Note: We need to handle the content encoding manually or pass bytes if we want to be more generic,
      // but the requirement was string content for CSV.
      await file.writeAsString(content);

      debugPrint('✅ File saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('❌ Error saving file: $e');
      return null;
    }
  }

  Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isAndroid) {
        // Approach 1: Try public Downloads directory directly
        try {
          final publicDownloads = Directory('/storage/emulated/0/Download');
          // Simple write check
          final testFile = File('${publicDownloads.path}/.test_write_access');
          await testFile.writeAsString('test');
          await testFile.delete();
          return publicDownloads;
        } catch (e) {
          debugPrint('❌ Public Downloads not directly accessible: $e');
        }

        // Approach 2: Request permission
        final permission = await Permission.storage.request();
        if (permission.isGranted) {
          return Directory('/storage/emulated/0/Download');
        }

        // Fallback
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final appDir = Directory('${directory.path}/InventoryReports');
          if (!await appDir.exists()) await appDir.create(recursive: true);
          return appDir;
        }
      } else if (Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
    }
    return await getApplicationDocumentsDirectory();
  }
}

FileSaver getFileSaver() => FileSaverIO();
