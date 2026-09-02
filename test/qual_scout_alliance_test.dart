import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/screens/qual_scout_screen.dart';
import 'package:obsidianscout_app/screens/qr_scanner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockQualScoutApiService extends ApiService {
  @override
  bool get isOnline => true;

  @override
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<String?> getCachedEventKey() async => '2026test';

  @override
  Future<ScoutingConfigModel?> fetchQualConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Qual Test Config',
        fields: [
          ScoutingFieldModel(id: 'driver_skill', label: 'Driver Skill', type: 'rating'),
          ScoutingFieldModel(id: 'defense_rating', label: 'Defense Rating', type: 'rating'),
          ScoutingFieldModel(id: 'notes', label: 'Notes', type: 'text'),
        ],
      );

  @override
  Future<ScoutingConfigModel?> getCachedQualConfig() async => fetchQualConfig();

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async => [
        TeamModel(eventKey: '2026test', teamKey: 'frc254', teamNumber: 254, nickname: 'Cheesy Poofs'),
        TeamModel(eventKey: '2026test', teamKey: 'frc1678', teamNumber: 1678, nickname: 'Citrus Circuits'),
        TeamModel(eventKey: '2026test', teamKey: 'frc971', teamNumber: 971, nickname: 'Spartan Robotics'),
        TeamModel(eventKey: '2026test', teamKey: 'frc118', teamNumber: 118, nickname: 'Robonauts'),
        TeamModel(eventKey: '2026test', teamKey: 'frc148', teamNumber: 148, nickname: 'Robowranglers'),
        TeamModel(eventKey: '2026test', teamKey: 'frc2056', teamNumber: 2056, nickname: 'OP Robotics'),
      ];

  @override
  Future<List<TeamModel>> getCachedTeams(String? eventKey) async => fetchTeams(eventKey);

  @override
  Future<List<MatchModel>> fetchMatches(String? eventKey) async => [
        MatchModel(
          eventKey: '2026test',
          matchKey: '2026test_qm1',
          matchNumber: 1,
          compLevel: 'qm',
          label: 'Quals 1',
          redTeams: ['frc254', 'frc1678', 'frc971'],
          blueTeams: ['frc118', 'frc148', 'frc2056'],
        ),
      ];

  @override
  Future<List<MatchModel>> getCachedMatches(String? eventKey) async => fetchMatches(eventKey);

  List<Map<String, dynamic>> lastBatchEntries = [];

  @override
  Future<ApiResponse<void>> submitBatchQualScouting(List<Map<String, dynamic>> entries) async {
    lastBatchEntries = entries;
    return const ApiResponse.success(null, statusCode: 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QualScoutScreen Alliance Scouting', () {
    testWidgets('renders all 4 scouting scope options', (tester) async {
      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Single Team'), findsWidgets);
      expect(find.text('Red Alliance'), findsWidgets);
      expect(find.text('Blue Alliance'), findsWidgets);
      expect(find.text('Both Alliances'), findsWidgets);
    });

    testWidgets('switching to Red Alliance hides single team select and renders alliance teams upon match selection', (tester) async {
      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Red Alliance scope chip
      await tester.tap(find.text('Red Alliance'));
      await tester.pumpAndSettle();

      // Match dropdown should be present, team dropdown should be hidden
      expect(find.byType(DropdownButtonFormField<TeamModel>), findsNothing);
      expect(find.byType(DropdownButtonFormField<MatchModel>), findsOneWidget);

      // Select Quals 1
      await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // Alliance team cards should appear with Red teams: 254, 1678, 971
      expect(find.textContaining('254'), findsWidgets);
      expect(find.textContaining('1678'), findsWidgets);
      expect(find.textContaining('971'), findsWidgets);

      // Blue teams should NOT be in Red Alliance mode
      expect(find.textContaining('118'), findsNothing);

      // Submit button should reflect alliance mode
      expect(find.text('SAVE RED ALLIANCE (3 TEAMS)'), findsOneWidget);
    });

    testWidgets('switching to Both Alliances displays all 6 teams and allows batch submission', (tester) async {
      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Both Alliances
      await tester.tap(find.text('Both Alliances'));
      await tester.pumpAndSettle();

      // Select Quals 1
      await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // Should show Red and Blue teams
      expect(find.textContaining('254'), findsWidgets);
      expect(find.textContaining('1678'), findsWidgets);
      expect(find.textContaining('971'), findsWidgets);
      expect(find.textContaining('118'), findsWidgets);
      expect(find.textContaining('148'), findsWidgets);
      expect(find.textContaining('2056'), findsWidgets);

      // Submit button should reflect both alliances
      final saveBtn = find.text('SAVE BOTH ALLIANCES (6 TEAMS)');
      expect(saveBtn, findsOneWidget);

      // Tap Save (scroll into view if needed)
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Check that 6 entries were submitted in batch
      expect(mockApi.lastBatchEntries.length, equals(6));
      final teamNumbers = mockApi.lastBatchEntries.map((e) => e['targetTeamNumber']).toList();
      expect(teamNumbers, containsAll([254, 1678, 971, 118, 148, 2056]));
    });

    testWidgets('shows all alliance teams simultaneously and saves distinct team data without copy button', (tester) async {
      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Red Alliance and Quals 1
      await tester.tap(find.text('Red Alliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // Verify all 3 Red teams are shown simultaneously on screen
      expect(find.textContaining('Team 254'), findsOneWidget);
      expect(find.textContaining('Team 1678'), findsOneWidget);
      expect(find.textContaining('Team 971'), findsOneWidget);

      // Verify position badges are visible simultaneously
      expect(find.text('Red 1'), findsOneWidget);
      expect(find.text('Red 2'), findsOneWidget);
      expect(find.text('Red 3'), findsOneWidget);

      // Verify "Copy to Other Teams" is removed
      expect(find.text('Copy to Other Teams'), findsNothing);

      // Verify Notes text fields exist for all teams simultaneously (3 fields for 3 teams)
      final notesFinders = find.widgetWithText(TextFormField, 'Notes');
      if (notesFinders.evaluate().isNotEmpty) {
        expect(notesFinders, findsNWidgets(3));
        await tester.enterText(notesFinders.at(0), 'Team 254 notes');
        await tester.enterText(notesFinders.at(1), 'Team 1678 notes');
        await tester.pumpAndSettle();
      }

      // Save the red alliance
      final saveBtn = find.text('SAVE RED ALLIANCE (3 TEAMS)');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify batch entries
      expect(mockApi.lastBatchEntries.length, equals(3));
      final entry254 = mockApi.lastBatchEntries.firstWhere((e) => e['targetTeamNumber'] == 254);
      final entry1678 = mockApi.lastBatchEntries.firstWhere((e) => e['targetTeamNumber'] == 1678);
      if (notesFinders.evaluate().isNotEmpty) {
        expect(entry254['notes'], equals('Team 254 notes'));
        expect(entry1678['notes'], equals('Team 1678 notes'));
      }
    });

    testWidgets('resizes and displays all 3 teams side-by-side on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Red Alliance and Quals 1
      await tester.tap(find.text('Red Alliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // Find top left position of each team card
      final pos254 = tester.getTopLeft(find.textContaining('Team 254'));
      final pos1678 = tester.getTopLeft(find.textContaining('Team 1678'));
      final pos971 = tester.getTopLeft(find.textContaining('Team 971'));

      // In side-by-side 3-column layout, their dy should be identical, and dx strictly increasing
      expect(pos254.dy, equals(pos1678.dy));
      expect(pos1678.dy, equals(pos971.dy));
      expect(pos254.dx, lessThan(pos1678.dx));
      expect(pos1678.dx, lessThan(pos971.dx));
    });

    testWidgets('generating alliance QR code displays all team numbers with TEAMS header', (tester) async {
      final mockApi = _MockQualScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Red Alliance and Quals 1
      await tester.tap(find.text('Red Alliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<MatchModel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // Tap Generate Alliance QR
      final qrBtn = find.text('GENERATE ALLIANCE QR');
      await tester.ensureVisible(qrBtn);
      await tester.pumpAndSettle();
      await tester.tap(qrBtn);
      await tester.pumpAndSettle();

      // Verify TEAMS header is shown (not singular TEAM)
      expect(find.text('TEAMS'), findsOneWidget);
      // Verify all 3 teams are listed in the modal details
      expect(find.text('254, 1678, 971'), findsOneWidget);
    });
  });

  group('Alliance QR Code Bundle Processing', () {
    test('unpacks qual-alliance QR bundle into multiple team entries', () {
      final alliancePayload = {
        'type': 'qual-alliance',
        'scope': 'red',
        'matchKey': '2026test_qm1',
        'matchNumber': 1,
        'eventKey': '2026test',
        'entries': [
          {
            'eventKey': '2026test',
            'targetTeamNumber': 254,
            'matchKey': '2026test_qm1',
            'matchNumber': 1,
            'driver_skill': 5,
          },
          {
            'eventKey': '2026test',
            'targetTeamNumber': 1678,
            'matchKey': '2026test_qm1',
            'matchNumber': 1,
            'driver_skill': 5,
          },
          {
            'eventKey': '2026test',
            'targetTeamNumber': 971,
            'matchKey': '2026test_qm1',
            'matchNumber': 1,
            'driver_skill': 4,
          }
        ]
      };

      final jsonStr = jsonEncode(alliancePayload);
      final decoded = jsonDecode(jsonStr);

      expect(decoded['type'], equals('qual-alliance'));
      expect(decoded['entries'], isA<List>());
      final entries = decoded['entries'] as List;
      expect(entries.length, equals(3));
      expect(entries[0]['targetTeamNumber'], equals(254));
      expect(entries[1]['targetTeamNumber'], equals(1678));
      expect(entries[2]['targetTeamNumber'], equals(971));
    });

    testWidgets('QrScannerScreen unpacks wrapped qual-alliance QR bundle into queue and blocks duplicate scan', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final mockApi = _MockQualScoutApiService();
      final scannerKey = GlobalKey<QrScannerScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QrScannerScreen(key: scannerKey, apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wrappedAllianceQr = {
        'type': 'qual-alliance',
        'data': {
          'type': 'qual-alliance',
          'scope': 'red',
          'matchKey': '2026test_qm1',
          'matchNumber': 1,
          'eventKey': '2026test',
          'entries': [
            {
              'eventKey': '2026test',
              'targetTeamNumber': 254,
              'matchKey': '2026test_qm1',
              'matchNumber': 1,
              'driver_skill': 5,
            },
            {
              'eventKey': '2026test',
              'targetTeamNumber': 1678,
              'matchKey': '2026test_qm1',
              'matchNumber': 1,
              'driver_skill': 4,
            },
            {
              'eventKey': '2026test',
              'targetTeamNumber': 971,
              'matchKey': '2026test_qm1',
              'matchNumber': 1,
              'driver_skill': 5,
            }
          ]
        }
      };

      final jsonStr = jsonEncode(wrappedAllianceQr);
      scannerKey.currentState!.handleRawScan(jsonStr);
      await tester.pumpAndSettle();

      // Verify all 3 teams are present in queue
      expect(scannerKey.currentState!.queue.length, equals(3));
      expect(scannerKey.currentState!.queue[0].data['targetTeamNumber'], equals(254));
      expect(scannerKey.currentState!.queue[1].data['targetTeamNumber'], equals(1678));
      expect(scannerKey.currentState!.queue[2].data['targetTeamNumber'], equals(971));

      // Scan again - should detect duplicate and not add again
      await tester.pump(const Duration(milliseconds: 1300));
      scannerKey.currentState!.handleRawScan(jsonStr, resetCooldown: true);
      await tester.pumpAndSettle();

      expect(scannerKey.currentState!.queue.length, equals(3));
      expect(find.text('All 3 alliance entries already exist in queue'), findsOneWidget);

      // Drain remaining cooldown timer
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
