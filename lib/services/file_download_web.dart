// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'file_download_helper.dart';

Future<FileDownloadResult> downloadOrSaveFileImpl({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) async {
  try {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);

    return FileDownloadResult(
      success: true,
      isWebDownload: true,
      message: 'Downloaded $filename to your browser downloads.',
    );
  } catch (e) {
    return FileDownloadResult(
      success: false,
      isWebDownload: true,
      message: 'Web download failed: $e',
    );
  }
}
