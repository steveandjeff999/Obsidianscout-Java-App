import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class NotificationWebSocketService {
  final ApiService apiService;
  final Function(String groupName, String title, String body, String sender) onNotificationReceived;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isDisposed = false;

  NotificationWebSocketService({
    required this.apiService,
    required this.onNotificationReceived,
  });

  void connect() {
    if (_isDisposed || !apiService.isLoggedIn) return;

    try {
      final serverUrl = apiService.serverUrl;
      final uri = Uri.parse(serverUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final portSuffix = uri.hasPort ? ':${uri.port}' : '';
      final wsUrl = '$scheme://${uri.host}$portSuffix/api/ws/notifications';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _subscription = _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (err) {
          debugPrint('[WS-Notification] Connection error: $err');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WS-Notification] Connection closed.');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WS-Notification] Failed to connect: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic rawData) {
    try {
      final String text = rawData.toString();
      final Map<String, dynamic> data = jsonDecode(text);
      if (data['type'] == 'chat_notification') {
        final groupName = data['groupName'] as String? ?? 'general';
        final title = data['title'] as String? ?? 'New Chat Message';
        final body = data['body'] as String? ?? '';
        final sender = data['sender'] as String? ?? 'Team Member';
        onNotificationReceived(groupName, title, body, sender);
      }
    } catch (e) {
      debugPrint('[WS-Notification] Error handling frame: $e');
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || !apiService.isLoggedIn) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      connect();
    });
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
