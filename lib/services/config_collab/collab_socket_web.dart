import 'package:web_socket_channel/web_socket_channel.dart';

// Browsers don't allow custom WebSocket headers; the page's cookies authenticate the socket.
WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) => WebSocketChannel.connect(uri);
