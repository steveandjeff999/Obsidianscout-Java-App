import 'net/server_file_cache.dart';

/// Photos the server has moved out of entry JSON into its blob store arrive as `/api/blobs/<uuid>`.
/// Older entries (and photos captured offline, before upload) are still `data:image/...;base64,` strings.
final RegExp _blobPhotoPath = RegExp(
    r'^/api/blobs/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

bool isBlobPhotoPath(Object? value) => value is String && _blobPhotoPath.hasMatch(value);

/// True for any scouting value that is a photo, in either form.
bool isPhotoValue(Object? value) =>
    value is String && (value.startsWith('data:image/') || _blobPhotoPath.hasMatch(value));

/// Absolute URL for a blob photo path on the current server, or null when no server is selected.
String? resolveBlobPhotoUrl(String path) {
  final base = ServerFileCache.instance.serverUrl().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return null;
  return '$base$path';
}
