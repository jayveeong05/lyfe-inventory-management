import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.html) 'file_saver_web.dart';

/// Abstract class for platform-specific file saving
abstract class FileSaver {
  /// Save a file with the given name and content.
  /// Returns the path where the file was saved (on mobile/desktop) or null (on web).
  Future<String?> saveFile(String fileName, String content);

  /// Factory constructor to return the correct platform implementation
  factory FileSaver() => getFileSaver();
}
