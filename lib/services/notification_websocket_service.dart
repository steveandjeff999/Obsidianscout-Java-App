import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/slack_models.dart';
import 'api_service.dart';
import 'config_collab/collab_socket_web.dart' if (dart.library.io) 'config_collab/collab_socket_io.dart' as platform;

class NotificationWebSocketService {
  final ApiService apiService;
  final Function(String groupName, String title, String body, String sender) onNotificationReceived;
  final void Function(SlackBanner banner)? onSlackNotification;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  StreamSubscription? _onlineSubscription;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  int _reconnectDelaySeconds = 10;
  /// Newest Slack banner seen, so a reconnect can ask the server for what it missed.
  DateTime? _lastSlackAt;

  NotificationWebSocketService({
    required this.apiService,
    required this.onNotificationReceived,
    this.onSlackNotification,
  }) {
    _onlineSubscription = apiService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline && !_isDisposed && apiService.isLoggedIn && _channel == null) {
        _reconnectDelaySeconds = 10;
        connect();
      }
    });
  }

  void connect() {
    if (_isDisposed || !apiService.isLoggedIn || !apiService.isOnline) return;

    try {
      final serverUrl = apiService.serverUrl;
      final uri = Uri.parse(serverUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final portSuffix = uri.hasPort ? ':${uri.port}' : '';
      final wsUrl = '$scheme://${uri.host}$portSuffix/api/ws/notifications';

      // On mobile and desktop the session cookie has to be sent as a header, or the server closes the socket.
      _channel = platform.connectChannel(Uri.parse(wsUrl), apiService.webSocketHeaders);
      _channel!.ready.then((_) => _catchUpSlack()).catchError((err) {
        // Suppress unhandled future error in VM; error is handled by stream subscription onError
      });

      _subscription = _channel!.stream.listen(
        (data) {
          _reconnectDelaySeconds = 10;
          _handleMessage(data);
        },
        onError: (err) {
          _cleanChannel();
          _scheduleReconnect();
        },
        onDone: () {
          _cleanChannel();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _cleanChannel();
      _scheduleReconnect();
    }
  }

  void _cleanChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
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
      } else if (data['type'] == 'slack_notification') {
        _deliverSlack(SlackBanner.fromJson(data));
      }
    } catch (e) {
      debugPrint('[WS-Notification] Error handling frame: $e');
    }
  }

  void _deliverSlack(SlackBanner banner) {
    final at = banner.createdAt;
    if (at != null && (_lastSlackAt == null || at.isAfter(_lastSlackAt!))) _lastSlackAt = at;
    onSlackNotification?.call(banner);
  }

  Future<void> _catchUpSlack() async {
    if (onSlackNotification == null || _isDisposed) return;
    final since = _lastSlackAt ?? DateTime.now().subtract(const Duration(minutes: 5));
    final missed = await apiService.fetchMissedSlackNotifications(since);
    if (_isDisposed) return;
    for (final json in missed) {
      _deliverSlack(SlackBanner.fromJson(json));
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || !apiService.isLoggedIn || !apiService.isOnline) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      if (!_isDisposed && apiService.isLoggedIn && apiService.isOnline) {
        connect();
      }
    });
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(10, 120);
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _onlineSubscription?.cancel();
    _cleanChannel();
  }
}
