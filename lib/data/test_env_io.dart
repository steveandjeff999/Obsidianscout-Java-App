import 'dart:io' show Platform;

/// True under `flutter test`, where platform plugins (path_provider) aren't available.
bool get isFlutterTestEnvironment => Platform.environment.containsKey('FLUTTER_TEST');
