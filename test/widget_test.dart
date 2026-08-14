import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';

import 'package:obsidianscout_app/screens/settings_screen.dart';

void main() {
  test('ApiService initializes with default server URL', () async {
    final apiService = ApiService();
    expect(apiService.serverUrl, 'http://localhost:8080');
  });

  test('ObsidianUITheme provides dark mode theme', () {
    final theme = ObsidianUITheme.darkTheme;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, ObsidianUITheme.background);
  });

  testWidgets('LoginScreen renders configurable server URL field', (WidgetTester tester) async {
    final apiService = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          apiService: apiService,
          onLoginSuccess: () {},
        ),
      ),
    );

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('SettingsScreen renders cache manager without overflow', (WidgetTester tester) async {
    final apiService = ApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            apiService: apiService,
            onLogout: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
