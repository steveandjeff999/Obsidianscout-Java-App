import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) =>
    IOWebSocketChannel.connect(uri, headers: headers, connectTimeout: const Duration(seconds: 6));
