import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/local_store.dart';
import 'net_client.dart' as http;

/// Keeps images on the device, so they survive a restart and show offline. `Image.network` only holds them in memory.
/// Stored like the field images: base64 in the local database, under a `cache_` key so Clear Cache removes them too.
class ServerFileCache {
  ServerFileCache._();

  static final ServerFileCache instance = ServerFileCache._();

  /// Anything bigger is shown but not kept.
  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxTotalChars = 96 * 1024 * 1024;
  static const int maxFiles = 500;
  static const int _pruneEveryWrites = 20;

  /// Sent only to [serverUrl]: an avatar can live on someone else's host, and these carry the session.
  Map<String, String> Function() headers = () => const {};
  String Function() serverUrl = () => '';
  String Function() scope = () => 'anon';
  bool Function() isOnline = () => true;

  final Set<String> _checked = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _writes = 0;

  String _key(String url) => 'cache_file:${scope()}:$url';

  @visibleForTesting
  void resetForTesting() {
    headers = () => const {};
    serverUrl = () => '';
    scope = () => 'anon';
    isOnline = () => true;
    _checked.clear();
    _inflight.clear();
    _writes = 0;
  }

  /// After the cache is cleared, every file needs fetching again this run.
  void forgetChecks() => _checked.clear();

  /// A `?v=` URL names one exact version, so a stored copy never needs checking.
  static bool _isVersioned(String url) =>
      Uri.tryParse(url)?.queryParameters.containsKey('v') ?? false;

  Future<({Uint8List bytes, String? etag})?> _read(String url) async {
    final stored = await LocalStore.instance.getJson(_key(url));
    if (stored is! Map) return null;
    try {
      return (
        bytes: base64Decode(stored['data'] as String),
        etag: stored['etag'] as String?
      );
    } catch (_) {
      return null;
    }
  }

  /// The copy on this device, or null.
  Future<Uint8List?> stored(String url) async => (await _read(url))?.bytes;

  /// Checks the server once per run. Returns bytes only when they're new; null means keep showing the stored copy.
  Future<Uint8List?> refresh(String url) {
    final key = _key(url);
    return _inflight[key] ??=
        _refresh(url, key).whenComplete(() {
      // A block, not an arrow: returning the removed future would make it wait for itself, forever.
      _inflight.remove(key);
    });
  }

  Future<Uint8List?> _refresh(String url, String key) async {
    if (!isOnline() || _checked.contains(key)) return null;
    final existing = await _read(url);
    if (existing != null && _isVersioned(url)) return null;

    final server = serverUrl();
    final requestHeaders = <String, String>{
      if (server.isNotEmpty && url.startsWith(server)) ...headers(),
      if (existing?.etag != null) 'If-None-Match': existing!.etag!,
    };
    try {
      final response = await http.get(Uri.parse(url), headers: requestHeaders);
      if (response.statusCode == 304) {
        _checked.add(key);
        return null;
      }
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      _checked.add(key);
      final bytes = response.bodyBytes;
      if (bytes.length > maxFileBytes) return bytes;
      await LocalStore.instance.setString(
          key,
          jsonEncode({
            'etag': response.headers['etag'],
            'data': base64Encode(bytes),
          }));
      if (_writes++ % _pruneEveryWrites == 0) {
        await LocalStore.instance.pruneWithPrefix('cache_file:',
            maxEntries: maxFiles, maxTotalChars: maxTotalChars);
      }
      return bytes;
    } catch (e) {
      debugPrint('[ServerFileCache] $url: $e');
      return null;
    }
  }
}
