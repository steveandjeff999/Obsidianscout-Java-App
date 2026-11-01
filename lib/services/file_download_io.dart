import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'file_download_helper.dart';

const MethodChannel _channel = MethodChannel('obsidianscout/downloads');

Future<FileDownloadResult> downloadOrSaveFileImpl({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) {
  return downloadOrSaveBytesImpl(filename: filename, bytes: utf8.encode(content), mimeType: mimeType);
}

Future<FileDownloadResult> downloadOrSaveBytesImpl({
  required String filename,
  required List<int> bytes,
  String mimeType = 'image/png',
}) async {
  try {
    final safeName = _safeFilename(filename);

    if (Platform.isAndroid) {
      final saved = await _saveToAndroidDownloads(safeName, bytes, mimeType);
      if (saved != null) {
        return FileDownloadResult(success: true, savedPath: saved, message: 'Saved to $saved');
      }
    }

    final targetDir = await _targetDirectory();

    String finalPath = '${targetDir.path}${Platform.pathSeparator}$safeName';
    File file = File(finalPath);
    if (file.existsSync()) {
      final dotIndex = safeName.lastIndexOf('.');
      final base = dotIndex != -1 ? safeName.substring(0, dotIndex) : safeName;
      final ext = dotIndex != -1 ? safeName.substring(dotIndex) : '';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      finalPath = '${targetDir.path}${Platform.pathSeparator}${base}_$timestamp$ext';
      file = File(finalPath);
    }

    await file.writeAsBytes(bytes);

    return FileDownloadResult(
      success: true,
      savedPath: Platform.isIOS ? 'the Files app (ObsidianScout folder)' : file.path,
      message: Platform.isIOS ? 'Saved $safeName to the Files app (ObsidianScout folder)' : 'Saved $safeName to ${targetDir.path}',
    );
  } catch (e) {
    return FileDownloadResult(
      success: false,
      message: 'Failed to save file: $e',
    );
  }
}

/// Names can come from the server or an uploader, so drop anything that isn't valid in a file name.
String _safeFilename(String filename) {
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return safe.isEmpty ? 'download' : safe;
}

/// Saves to the shared Downloads folder, which only native code can write to on Android.
/// Returns where the file went, or null when the app has to keep it in its own folder.
Future<String?> _saveToAndroidDownloads(String filename, List<int> bytes, String mimeType) async {
  Future<String?> save() => _channel.invokeMethod<String>('saveToDownloads', {
        'filename': filename,
        'mimeType': mimeType,
        'bytes': Uint8List.fromList(bytes),
      });

  try {
    return await save();
  } on PlatformException catch (e) {
    if (e.code != 'needs_permission') return null;
  } catch (_) {
    return null;
  }

  // Android 9 and older only.
  if (!(await Permission.storage.request()).isGranted) return null;
  try {
    return await save();
  } catch (_) {
    return null;
  }
}

Future<Directory> _targetDirectory() async {
  Directory? targetDir;

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // Asks the OS rather than assuming ~/Downloads, which can be moved (e.g. into OneDrive on Windows).
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null && downloads.existsSync()) {
        // The macOS sandbox hands back a link inside the app's container; follow it to the real folder.
        targetDir = Platform.isMacOS ? Directory(await downloads.resolveSymbolicLinks()) : downloads;
      }
    } catch (_) {}
    targetDir ??= await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    // Shown in the Files app under ObsidianScout (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace).
    targetDir = await getApplicationDocumentsDirectory();
  } else if (Platform.isAndroid) {
    try {
      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (extDirs != null && extDirs.isNotEmpty) {
        targetDir = extDirs.first;
      }
    } catch (_) {}
    targetDir ??= await getExternalStorageDirectory();
    targetDir ??= await getApplicationDocumentsDirectory();
  }

  return targetDir ?? Directory.systemTemp;
}
