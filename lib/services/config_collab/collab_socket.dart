import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'collab_socket_web.dart' if (dart.library.io) 'collab_socket_io.dart' as platform;

/// The bit of a WebSocket the live-editing session needs; swapped for a fake in tests.
abstract class CollabSocket {
  Stream<dynamic> get stream;
  void send(String text);
  Future<void> close();
}

typedef CollabSocketFactory = CollabSocket Function(Uri uri, Map<String, String> headers);

/// Opens a real WebSocket. Headers (the session cookie) are sent on mobile and desktop; in a browser
/// the page's own cookies are used instead.
CollabSocket connectCollabSocket(Uri uri, Map<String, String> headers) =>
    _ChannelSocket(platform.connectChannel(uri, headers));

class _ChannelSocket implements CollabSocket {
  final WebSocketChannel _channel;

  _ChannelSocket(this._channel) {
    // Connection errors surface on the stream; don't let the ready future report them a second time.
    _channel.ready.catchError((_) {});
  }

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close();
    } catch (_) {}
  }
}
