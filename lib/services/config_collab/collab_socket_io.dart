import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A phone moving between arena Wi-Fi and cellular, or waking from sleep, can be left holding a socket whose other end is
/// gone, and nothing reports it for many minutes. Pinging makes dart:io close the socket when a pong doesn't come back
/// within [_pingInterval], which ends the stream and lets the caller reconnect.
const Duration _pingInterval = Duration(seconds: 20);

WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) => IOWebSocketChannel.connect(
      uri,
      headers: headers,
      connectTimeout: const Duration(seconds: 6),
      pingInterval: _pingInterval,
    );
