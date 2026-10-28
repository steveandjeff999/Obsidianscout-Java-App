import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'home_widget_service.dart';

/// Silent pushes that arrive while the app is in the background or closed. Runs in its own isolate.
@pragma('vm:entry-point')
Future<void> obsidianFcmBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] == 'widget_refresh') {
    await HomeWidgetService.handleRefreshPush();
  }
}

class FcmHelper {
  static String? currentFcmToken;
  static bool _isFirebaseInitialized = false;

  static bool get _isApple =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  /// APNs registration finishes a moment after permission is granted; poll briefly instead of failing getToken().
  static Future<bool> _waitForApnsToken() async {
    for (var i = 0; i < 20; i++) {
      if (await FirebaseMessaging.instance.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  static Future<void> initializeDynamicFcm(ApiService apiService, Function(String groupName) onNavigateToChat) async {
    // FCM is supported on Android, iOS, macOS, and Web.
    // Windows and Linux desktop use WebSocket notification service.
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }

    try {
      final config = await apiService.fetchFcmPublicConfig();
      if (config == null || config['enabled'] != true) {
        return;
      }

      var apiKey = config['apiKey'] as String? ?? '';
      var appId = config['appId'] as String? ?? '';
      final messagingSenderId = config['messagingSenderId'] as String? ?? '';
      final projectId = config['projectId'] as String? ?? '';

      // iOS and macOS need the Firebase project's iOS app (and its API key); the Android app ID is rejected there.
      if (_isApple) {
        final appleAppId = config['appleAppId'] as String? ?? '';
        if (appleAppId.isEmpty) {
          debugPrint('[FCM] No iOS / macOS app configured on the server; push notifications are off on this device.');
          return;
        }
        appId = appleAppId;
        apiKey = (config['appleApiKey'] as String? ?? '').ifEmpty(apiKey);
      }

      if (apiKey.isEmpty || projectId.isEmpty) {
        return;
      }

      if (!_isFirebaseInitialized) {
        try {
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: apiKey,
              appId: appId.ifEmpty('1:100000000000:android:default'),
              messagingSenderId: messagingSenderId.ifEmpty('100000000000'),
              projectId: projectId,
            ),
          );
          _isFirebaseInitialized = true;
        } catch (e) {
          if (e.toString().contains('duplicate-app') || e.toString().contains('already exists')) {
            _isFirebaseInitialized = true;
          }
        }
      }

      if (!_isFirebaseInitialized) return;

      // Silent "widgets are out of date" pushes: fetch now in the foreground, hand to the widgets otherwise.
      FirebaseMessaging.onBackgroundMessage(obsidianFcmBackgroundHandler);
      FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'widget_refresh') HomeWidgetService.instance.requestRefresh();
      });

      // Configure foreground notifications
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Request notification permissions
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Fetch and register FCM token. On iOS / macOS getToken() throws until APNs has handed over its token.
      if (_isApple && !await _waitForApnsToken()) {
        debugPrint('[FCM] No APNs token; check the Push Notifications capability and the APNs key in Firebase.');
        await setupNotificationListeners(onNavigateToChat);
        return;
      }
      currentFcmToken = await FirebaseMessaging.instance.getToken();
      if (currentFcmToken != null && currentFcmToken!.isNotEmpty) {
        final platformStr = kIsWeb ? 'web' : defaultTargetPlatform.name;
        await apiService.registerFcmToken(currentFcmToken!, platformStr);
      }

      // Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        currentFcmToken = newToken;
        final platformStr = kIsWeb ? 'web' : defaultTargetPlatform.name;
        apiService.registerFcmToken(newToken, platformStr);
      });

      // Set up notification tap listeners immediately
      await setupNotificationListeners(onNavigateToChat);
    } catch (e) {
      debugPrint('[FCM] Dynamic bootstrap failed: $e');
    }
  }

  static Future<void> setupNotificationListeners(Function(String groupName) onNavigateToChat) async {
    if (!_isFirebaseInitialized) return;
    try {
      // Handle background notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final groupName = message.data['groupName'] as String? ?? 'general';
        debugPrint('[FCM] Notification tapped in background: group=$groupName');
        onNavigateToChat(groupName);
      });

      // Handle terminated app launch from notification
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final groupName = initialMessage.data['groupName'] as String? ?? 'general';
        debugPrint('[FCM] Terminated app launched from notification: group=$groupName');
        onNavigateToChat(groupName);
      }
    } catch (e) {
      debugPrint('[FCM] Listener setup failed: $e');
    }
  }

  static Future<void> unregisterOnLogout(ApiService apiService) async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }

    try {
      if (currentFcmToken != null && currentFcmToken!.isNotEmpty) {
        await apiService.unregisterFcmToken(currentFcmToken!);
        currentFcmToken = null;
      }
      if (_isFirebaseInitialized) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await apiService.unregisterFcmToken(token);
          await FirebaseMessaging.instance.deleteToken();
        }
      }
    } catch (e) {
      debugPrint('[FCM] Unregister on logout failed: $e');
    }
  }
}

extension _StringExt on String {
  String ifEmpty(String fallback) => isNotEmpty ? this : fallback;
}
