import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/l10n/app_localizations.dart';
import 'package:obsidianscout_app/main.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';

class _MockBackNavApiService extends ApiService {
  bool _mockLoggedIn = true;

  @override
  bool get isLoggedIn => _mockLoggedIn;

  void setMockLoggedIn(bool val) {
    _mockLoggedIn = val;
  }

  @override
  bool hasPageAccess(String pageId) => true;

  @override
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Test Config',
        fields: [],
      );

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async => [];

  @override
  Future<List<MatchModel>> fetchMatches(String? eventKey) async => [];
}

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations() : super(const Locale('en'));

  @override
  String translate(String key, [Map<String, String>? args]) {
    final map = {
      'nav.dashboard': 'Dashboard',
      'subtitle.dashboard': 'Event Overview & Realtime Analytics',
      'app.press_back_again_to_exit': 'Press back again to exit',
      'login.connect_login': 'Connect / Login',
      'login.username': 'Username',
      'login.password': 'Password',
    };
    return map[key] ?? key;
  }
}

class _TestAppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async => _TestAppLocalizations();

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

void main() {
  Widget createTestApp(Widget home) {
    return MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('he'),
        Locale('tr'),
      ],
      home: home,
    );
  }

  testWidgets('MainShell back button navigates through history to Dashboard', (WidgetTester tester) async {
    final mockApi = _MockBackNavApiService();
    await tester.pumpWidget(createTestApp(MainShell(apiService: mockApi)));
    await tester.pumpAndSettle();

    // Verify initially on Dashboard
    expect(find.text('Dashboard'), findsWidgets);

    // Tap on navigation item to switch to Match Scout (index 1)
    final matchScoutIcon = find.byIcon(Icons.sports_score_rounded);
    if (matchScoutIcon.evaluate().isNotEmpty) {
      await tester.tap(matchScoutIcon.first);
      await tester.pumpAndSettle();
    }

    // Trigger system back button (simulate Android back button)
    final dynamic widgetsBinding = tester.binding;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    // Back button should have popped history and returned to Dashboard
    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('MainShell back button on Dashboard shows press back again to exit', (WidgetTester tester) async {
    final mockApi = _MockBackNavApiService();
    await tester.pumpWidget(createTestApp(MainShell(apiService: mockApi)));
    await tester.pumpAndSettle();

    // Trigger system back button on Dashboard
    final dynamic widgetsBinding = tester.binding;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    // SnackBar message should be displayed
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('LoginScreen back button shows press back again to exit', (WidgetTester tester) async {
    final mockApi = _MockBackNavApiService();
    mockApi.setMockLoggedIn(false);

    await tester.pumpWidget(createTestApp(LoginScreen(apiService: mockApi, onLoginSuccess: () {})));
    await tester.pumpAndSettle();

    // Trigger system back button on LoginScreen
    final dynamic widgetsBinding = tester.binding;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    // SnackBar message should be displayed
    expect(find.text('Press back again to exit'), findsOneWidget);
  });
}
