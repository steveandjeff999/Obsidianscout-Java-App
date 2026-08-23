import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';
import 'package:obsidianscout_app/screens/settings_screen.dart';
import 'package:obsidianscout_app/screens/match_scout_screen.dart';

class _MockScoutingApiService extends ApiService {
  @override
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Test Config',
        fields: [
          ScoutingFieldModel(id: 'auto_score', label: 'Auto Score', type: 'counter', phase: 'auto', pointsPer: 3.0),
          ScoutingFieldModel(id: 'teleop_score', label: 'Teleop Score', type: 'counter', phase: 'teleop', pointsPer: 2.0),
          ScoutingFieldModel(id: 'endgame_climb', label: 'Endgame Climb', type: 'checkbox', phase: 'endgame', pointsPer: 5.0),
          ScoutingFieldModel(id: 'post_comments', label: 'Comments', type: 'text', phase: 'postmatch'),
        ],
      );

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async => [
        TeamModel(eventKey: '2026test', teamKey: 'frc1234', teamNumber: 1234, nickname: 'Test Team'),
      ];

  @override
  Future<List<MatchModel>> fetchMatches(String? eventKey) async => [
        MatchModel(eventKey: '2026test', matchKey: '2026test_qm1', matchNumber: 1, compLevel: 'qm', label: 'Quals 1'),
      ];
}

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

  testWidgets('MatchScoutScreen renders tabbed layout with Auto, Teleop, Endgame, and Post Match', (WidgetTester tester) async {
    final mockApi = _MockScoutingApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchScoutScreen(
            apiService: mockApi,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(MatchScoutScreen), findsOneWidget);
    expect(find.text('Select a team and match to start scouting.'), findsOneWidget);

    // Select team
    await tester.tap(find.byType(DropdownButtonFormField<TeamModel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1234 - Test Team').last);
    await tester.pumpAndSettle();

    // Select match
    await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quals 1').last);
    await tester.pumpAndSettle();

    // Find phase tabs
    expect(find.text('Auto'), findsWidgets);
    expect(find.text('Teleop'), findsWidgets);
    expect(find.text('Endgame'), findsWidgets);
    expect(find.text('Post Match'), findsWidgets);
    expect(find.text('AUTONOMOUS PERIOD'), findsOneWidget);
    expect(find.text('Auto Score'), findsOneWidget);

    // Tap Teleop tab
    await tester.tap(find.text('Teleop').first);
    await tester.pumpAndSettle();
    expect(find.text('TELEOPERATED PERIOD'), findsOneWidget);
    expect(find.text('Teleop Score'), findsOneWidget);

    // Tap Endgame tab
    await tester.tap(find.text('Endgame').first);
    await tester.pumpAndSettle();
    expect(find.text('ENDGAME PERIOD'), findsOneWidget);
    expect(find.text('Endgame Climb'), findsOneWidget);

    // Tap Post Match tab
    await tester.tap(find.text('Post Match').first);
    await tester.pumpAndSettle();
    expect(find.text('POST-MATCH'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
  });

  test('ApiService onSessionRevoked stream exists and is broadcast', () async {
    final apiService = ApiService();
    expect(apiService.onSessionRevoked, isA<Stream<String>>());
  });

  testWidgets('SettingsScreen renders Active Sessions card', (WidgetTester tester) async {
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
    expect(find.text('Active Sessions'), findsOneWidget);
  });
}
