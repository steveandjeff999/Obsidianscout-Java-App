import 'file_download_io.dart'
    if (dart.library.html) 'file_download_web.dart' as platform_downloader;

class FileDownloadResult {
  final bool success;
  final String? savedPath;
  final String? message;
  final bool isWebDownload;

  const FileDownloadResult({
    required this.success,
    this.savedPath,
    this.message,
    this.isWebDownload = false,
  });
}

Future<FileDownloadResult> downloadOrSaveFile({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) async {
  return platform_downloader.downloadOrSaveFileImpl(
    filename: filename,
    content: content,
    mimeType: mimeType,
  );
}

Future<FileDownloadResult> downloadOrSaveBytes({
  required String filename,
  required List<int> bytes,
  String mimeType = 'image/png',
}) async {
  return platform_downloader.downloadOrSaveBytesImpl(
    filename: filename,
    bytes: bytes,
    mimeType: mimeType,
  );
}
