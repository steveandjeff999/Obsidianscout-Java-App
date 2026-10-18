import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'data/local_store.dart';
import 'services/api_service.dart';
import 'services/gamepad_service.dart';
import 'services/home_widget_service.dart';

export 'app.dart';
export 'shell/main_shell.dart';
export 'shell/shell_screen_registry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint('[window_manager] Init error: $e');
    }
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER_ERROR: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PLATFORM_ERROR: $error\nSTACK_TRACE:\n$stack');
    // ignore: avoid_print
    print('PLATFORM_ERROR: $error\nSTACK_TRACE:\n$stack');
    return true;
  };

  // Open the on-device database (and move old SharedPreferences caches into it) before
  // anything reads cached data.
  try {
    await LocalStore.instance.ensureReady();
  } catch (e, st) {
    debugPrint('[LocalStore] Init error: $e\n$st');
  }

  final apiService = ApiService();
  try {
    await apiService.init();
  } catch (e, st) {
    debugPrint('[ApiService] Init error: $e\n$st');
  }

  try {
    await HomeWidgetService.instance.init(apiService);
  } catch (e, st) {
    debugPrint('[HomeWidget] Init error: $e\n$st');
  }

  try {
    await GamepadService.instance.init();
    GamepadService.instance.attachApiService(apiService);
  } catch (e, st) {
    debugPrint('[GamepadService] Init error: $e\n$st');
  }

  runApp(ObsidianscoutApp(apiService: apiService));
}
