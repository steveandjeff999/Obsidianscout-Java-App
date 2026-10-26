import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Keep idle connections this long, so the next request (health check every 45 s, sync every few minutes) reuses
/// one instead of paying a fresh TCP + TLS handshake: 2-3 round trips, i.e. seconds on a congested event network.
const Duration connectionIdleTimeout = Duration(minutes: 2);

/// The platform's own HTTP stack where it does better on bad networks than `dart:io`:
///
/// * Android, Cronet: HTTP/2 and HTTP/3 (QUIC, so one lost packet doesn't stall every request on the connection, and
///   the connection survives a Wi-Fi/cellular switch), Brotli, and stale-DNS fallback when a lookup times out.
/// * iOS/macOS, NSURLSession: HTTP/2 and HTTP/3, Brotli.
///
/// Cookies stay the app's business (ApiService sends and parses the session cookie itself), so neither stack keeps a
/// cookie jar or an HTTP cache of its own (NetClient does ETag revalidation). Anywhere else, or if the native stack
/// can't start (Cronet needs Google Play services), it's `dart:io` with a longer idle timeout.
http.Client createPlatformClient() {
  try {
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(
        cacheMode: CacheMode.disabled,
        enableBrotli: true,
        enableHttp2: true,
        enableQuic: true,
        enableStaleDns: true,
        useStaleOnNameNotResolved: true,
        userAgent: 'ObsidianScout-App',
      );
      return CronetClient.fromCronetEngine(engine, closeEngine: true);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final config = URLSessionConfiguration.ephemeralSessionConfiguration()
        ..cache = null
        ..requestCachePolicy = NSURLRequestCachePolicy.NSURLRequestReloadIgnoringLocalCacheData
        ..httpShouldSetCookies = false
        ..httpCookieAcceptPolicy = NSHTTPCookieAcceptPolicy.NSHTTPCookieAcceptPolicyNever;
      return CupertinoClient.fromSessionConfiguration(config);
    }
  } catch (e) {
    debugPrint('[NetClient] Native HTTP stack unavailable, using dart:io: $e');
  }
  return ioClient();
}

http.Client ioClient() => IOClient(HttpClient()..idleTimeout = connectionIdleTimeout);
