import 'dart:html' as html;
import 'dart:convert';
import 'file_saver.dart';

class FileSaverWeb implements FileSaver {
  @override
  Future<String?> saveFile(String fileName, String content) async {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
    return 'Downloads folder'; // Web doesn't return a specific path
  }
}

FileSaver getFileSaver() => FileSaverWeb();
