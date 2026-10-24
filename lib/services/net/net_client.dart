/// Drop-in for `package:http`'s top-level functions, tuned for slow event connections:
///
/// * requests run through [RequestScheduler], so uploads and the schedule never wait behind bulk downloads;
/// * a request fails only when it stops making progress (no headers within the connect window, or no new bytes
///   for the idle window), so a large download on a 10 kbps link finishes instead of restarting forever;
/// * GETs send `If-None-Match` with the stored ETag and turn a `304 Not Modified` back into the stored body;
/// * JSON bodies of 1 KB or more are gzipped (the server decodes `Content-Encoding: gzip`).
///
/// Import it `as http` in place of `package:http/http.dart`; everything else in that package is re-exported.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'link_quality.dart';
import 'request_scheduler.dart';

export 'package:http/http.dart' hide get, post, put, patch, delete, head, read, readBytes;

/// A stored response body and its ETag.
typedef EtagRecord = ({String etag, String body});

class NetClient {
  NetClient._();

  static final NetClient instance = NetClient._();

  /// JSON bodies at least this large are gzipped before upload.
  static const int gzipMinBytes = 1024;

  /// Bodies larger than this aren't kept for ETag revalidation (the delta sync handles the big lists).
  static const int maxEtagBodyChars = 512 * 1024;

  static const Duration lowBandwidthMinWait = Duration(seconds: 30);
  static const Duration minBodyIdle = Duration(seconds: 15);
  static const Duration maxRequest = Duration(minutes: 10);

  http.Client _client = http.Client();
  bool _gzipDisabled = false;

  /// How long to wait for response headers on a normal link (the user's request timeout setting).
  Duration Function() connectTimeout = () => const Duration(seconds: 6);

  /// Storage for ETag revalidation; unset means no revalidation.
  Future<EtagRecord?> Function(String url)? readEtag;
  Future<void> Function(String url, EtagRecord record)? writeEtag;

  @visibleForTesting
  set client(http.Client value) => _client = value;

  @visibleForTesting
  void resetForTesting() {
    _client = http.Client();
    _gzipDisabled = false;
    readEtag = null;
    writeEtag = null;
    connectTimeout = () => const Duration(seconds: 6);
  }

  static bool _isJson(Map<String, String> headers) {
    final type = _header(headers, 'content-type') ?? '';
    return type.contains('json');
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  /// Same body rules as `package:http`: strings are encoded (UTF-8 by default), maps are form-encoded.
  static List<int> _encodeBody(Object body, Encoding? encoding, Map<String, String> headers) {
    final enc = encoding ?? utf8;
    if (body is String) {
      if (_header(headers, 'content-type') == null) headers['content-type'] = 'text/plain; charset=${enc.name}';
      return enc.encode(body);
    }
    if (body is List<int>) return body;
    if (body is Map) {
      if (_header(headers, 'content-type') == null) {
        headers['content-type'] = 'application/x-www-form-urlencoded; charset=${enc.name}';
      }
      final pairs = body.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key.toString(), encoding: enc)}=${Uri.encodeQueryComponent(e.value.toString(), encoding: enc)}');
      return enc.encode(pairs.join('&'));
    }
    throw ArgumentError('Invalid request body "$body".');
  }

  static bool _looksTextual(http.Response res) {
    final type = res.headers['content-type'] ?? '';
    return type.contains('json') || type.startsWith('text/');
  }

  Future<http.Response> send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    RequestPriority? priority,
  }) async {
    final hdrs = <String, String>{...?headers};
    final prio = priority ?? RequestScheduler.priorityFor(method, url.path);

    EtagRecord? stored;
    if (method == 'GET' && readEtag != null && _header(hdrs, 'if-none-match') == null && !url.path.startsWith('/api/sync/')) {
      try {
        stored = await readEtag!(url.toString());
      } catch (_) {}
      if (stored != null) hdrs['If-None-Match'] = stored.etag;
    }

    List<int>? plain;
    List<int>? bytes;
    var gzipped = false;
    if (body != null) {
      plain = _encodeBody(body, encoding, hdrs);
      bytes = plain;
      if (!_gzipDisabled && plain.length >= gzipMinBytes && _isJson(hdrs)) {
        final packed = GZipEncoder().encode(plain);
        if (packed.length < plain.length) {
          bytes = packed;
          gzipped = true;
          hdrs['Content-Encoding'] = 'gzip';
        }
      }
    }

    var res = await RequestScheduler.instance.schedule(prio, () => _transfer(method, url, hdrs, bytes));

    // A proxy that can't pass compressed bodies through: resend as plain JSON and stop compressing.
    if (gzipped &&
        (res.statusCode == 415 ||
            (res.statusCode == 400 && RegExp('json|parse|unexpected|malformed|illegal', caseSensitive: false).hasMatch(res.body)))) {
      _gzipDisabled = true;
      hdrs.remove('Content-Encoding');
      res = await RequestScheduler.instance.schedule(prio, () => _transfer(method, url, hdrs, plain));
    }

    if (method == 'GET') {
      if (res.statusCode == 304 && stored != null) {
        return http.Response(stored.body, 200,
            headers: {...res.headers, 'content-type': 'application/json; charset=utf-8', 'x-obsidian-revalidated': '1'},
            request: res.request);
      }
      final etag = res.headers['etag'];
      if (res.statusCode == 200 && etag != null && writeEtag != null && _looksTextual(res) && !url.path.startsWith('/api/sync/')) {
        final text = res.body;
        if (text.length <= maxEtagBodyChars) {
          try {
            await writeEtag!(url.toString(), (etag: etag, body: text));
          } catch (_) {}
        }
      }
    }
    return res;
  }

  Future<http.Response> _transfer(String method, Uri url, Map<String, String> headers, List<int>? body) async {
    final request = http.Request(method, url)..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;

    final low = LinkQuality.instance.isLowBandwidth;
    final configured = connectTimeout();
    final connect = low ? _max(configured, lowBandwidthMinWait) : configured;
    final bodyIdle = _max(connect, low ? lowBandwidthMinWait : minBodyIdle);

    final watch = Stopwatch()..start();
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(connect);
    } on TimeoutException {
      LinkQuality.instance.recordStall(watch.elapsedMilliseconds);
      rethrow;
    }
    final ttfb = watch.elapsedMilliseconds;
    final data = await _readWithIdle(streamed.stream, bodyIdle, maxRequest - watch.elapsed, watch);
    final encoding = streamed.headers['content-encoding'] ?? '';
    LinkQuality.instance.recordTransfer(
      decodedBytes: data.length,
      gzipped: encoding.contains('gzip') || encoding.contains('deflate') || data.length > 4096,
      ttfbMs: ttfb,
      downloadMs: watch.elapsedMilliseconds - ttfb,
    );
    return http.Response.bytes(
      data,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  static Duration _max(Duration a, Duration b) => a > b ? a : b;

  /// Collects the body, failing only if no bytes arrive for [idle] (or the whole request passes [remaining]).
  Future<Uint8List> _readWithIdle(Stream<List<int>> stream, Duration idle, Duration remaining, Stopwatch watch) {
    final completer = Completer<Uint8List>();
    final builder = BytesBuilder(copy: false);
    Timer? idleTimer;
    late StreamSubscription<List<int>> sub;
    final cap = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (completer.isCompleted) return;
      idleTimer?.cancel();
      sub.cancel();
      LinkQuality.instance.recordStall(watch.elapsedMilliseconds);
      completer.completeError(TimeoutException('Request took too long', maxRequest));
    });
    void arm() {
      idleTimer?.cancel();
      idleTimer = Timer(idle, () {
        if (completer.isCompleted) return;
        cap.cancel();
        sub.cancel();
        LinkQuality.instance.recordStall(math.max(idle.inMilliseconds, watch.elapsedMilliseconds));
        completer.completeError(TimeoutException('No data received', idle));
      });
    }

    arm();
    sub = stream.listen(
      (chunk) {
        builder.add(chunk);
        arm();
      },
      onError: (Object e, StackTrace st) {
        idleTimer?.cancel();
        cap.cancel();
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: () {
        idleTimer?.cancel();
        cap.cancel();
        if (!completer.isCompleted) completer.complete(builder.takeBytes());
      },
      cancelOnError: true,
    );
    return completer.future;
  }
}

Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
    NetClient.instance.send('GET', url, headers: headers);

Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
    NetClient.instance.send('HEAD', url, headers: headers);

Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    NetClient.instance.send('POST', url, headers: headers, body: body, encoding: encoding);

Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    NetClient.instance.send('PUT', url, headers: headers, body: body, encoding: encoding);

Future<http.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    NetClient.instance.send('PATCH', url, headers: headers, body: body, encoding: encoding);

Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    NetClient.instance.send('DELETE', url, headers: headers, body: body, encoding: encoding);
