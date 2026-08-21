import 'dart:io';
import 'file_download_helper.dart';

Future<FileDownloadResult> downloadOrSaveFileImpl({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) async {
  try {
    Directory? targetDir;

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final downloads = Directory('$userProfile\\Downloads');
        if (downloads.existsSync()) {
          targetDir = downloads;
        } else {
          final docs = Directory('$userProfile\\Documents');
          if (docs.existsSync()) targetDir = docs;
        }
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final downloads = Directory('$home/Downloads');
        if (downloads.existsSync()) {
          targetDir = downloads;
        } else {
          final docs = Directory('$home/Documents');
          if (docs.existsSync()) targetDir = docs;
        }
      }
    }

    targetDir ??= Directory.systemTemp;

    String finalPath = '${targetDir.path}${Platform.pathSeparator}$filename';
    File file = File(finalPath);
    if (file.existsSync()) {
      final dotIndex = filename.lastIndexOf('.');
      final base = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
      final ext = dotIndex != -1 ? filename.substring(dotIndex) : '';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      finalPath = '${targetDir.path}${Platform.pathSeparator}${base}_$timestamp$ext';
      file = File(finalPath);
    }

    await file.writeAsString(content);

    return FileDownloadResult(
      success: true,
      savedPath: file.path,
      message: 'Saved $filename to ${targetDir.path}',
    );
  } catch (e) {
    return FileDownloadResult(
      success: false,
      message: 'Failed to save file: $e',
    );
  }
}
