import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/all_data_screen.dart';
import 'package:obsidianscout_app/screens/match_data_screen.dart';
import 'package:obsidianscout_app/screens/pit_data_screen.dart';
import 'package:obsidianscout_app/screens/qual_data_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/widgets/conflict_resolution_modal.dart';

class _MockDataApiService extends ApiService {
  @override
  Future<AppSettingsModel?> fetchSettings() async => AppSettingsModel(
        year: 2026,
        eventKey: '2026test',
        eventCode: 'test',
      );

  @override
  Future<List<EventModel>> fetchEvents({int? year}) async => [
        EventModel(
          eventKey: '2026test',
          name: 'Test Regional',
          year: 2026,
        ),
      ];

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async => [
        TeamModel(eventKey: '2026test', teamKey: 'frc1234', teamNumber: 1234, nickname: 'Obsidian Bots'),
        TeamModel(eventKey: '2026test', teamKey: 'frc5678', teamNumber: 5678, nickname: 'Robo Knights'),
      ];

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Match Config',
        fields: [
          ScoutingFieldModel(id: 'auto_notes', label: 'Auto Notes', type: 'counter', phase: 'auto', pointsPer: 3.0),
          ScoutingFieldModel(id: 'teleop_cycles', label: 'Teleop Cycles', type: 'counter', phase: 'teleop', pointsPer: 2.0),
          ScoutingFieldModel(id: 'endgame_climb', label: 'Endgame Climb', type: 'checkbox', phase: 'endgame', pointsPer: 5.0),
        ],
      );

  @override
  Future<ScoutingConfigModel?> fetchPitConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Pit Config',
        fields: [
          ScoutingFieldModel(id: 'drivetrain', label: 'Drivetrain', type: 'select', options: [
            ScoutingOptionModel(label: 'Swerve', value: 'swerve'),
            ScoutingOptionModel(label: 'Tank', value: 'tank'),
          ]),
          ScoutingFieldModel(id: 'robot_weight', label: 'Robot Weight', type: 'number'),
        ],
      );

  @override
  Future<ScoutingConfigModel?> fetchQualConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Qual Config',
        fields: [
          ScoutingFieldModel(id: 'driver_skill', label: 'Driver Skill', type: 'rating', min: 1, max: 5),
          ScoutingFieldModel(id: 'defense_impact', label: 'Defense Impact', type: 'slider', min: 1, max: 10),
        ],
      );

  @override
  Future<List<dynamic>> fetchScoutingEntries() async => [
        {
          'id': '101',
          'targetTeamNumber': 1234,
          'eventKey': '2026test',
          'matchNumber': 1,
          'matchKey': '2026test_qm1',
          'createdAt': '2026-03-01T12:00:00Z',
          'scoutUsername': 'lead_scout',
          'hasDiscrepancy': false,
          'data': {'auto_notes': 4, 'teleop_cycles': 8, 'endgame_climb': true},
        },
      ];

  @override
  Future<List<dynamic>> fetchPitScoutingEntries() async => [
        {
          'id': '201',
          'targetTeamNumber': 1234,
          'eventKey': '2026test',
          'createdAt': '2026-03-01T10:00:00Z',
          'scoutUsername': 'pit_scout',
          'data': {'drivetrain': 'Swerve', 'robot_weight': 115},
        },
      ];

  @override
  Future<List<dynamic>> fetchQualScoutingEntries() async => [
        {
          'id': '301',
          'targetTeamNumber': 1234,
          'eventKey': '2026test',
          'matchNumber': 1,
          'createdAt': '2026-03-01T12:15:00Z',
          'scoutUsername': 'strategy_lead',
          'data': {'driver_skill': 4.5, 'defense_impact': 8},
        },
      ];

  @override
  Future<ApiResponse<void>> deleteScoutingEntry(String id, {String type = 'match'}) async {
    return const ApiResponse.success(null);
  }

  @override
  Future<ApiResponse<void>> updateScoutingEntry(String id, Map<String, dynamic> data, {String type = 'match'}) async {
    return const ApiResponse.success(null);
  }

  @override
  Future<void> clearScoutingCaches() async {
    // No-op in tests — no SharedPreferences needed
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Data Screens Page Access and Permissions Tests', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService();
    });

    test('Analytics and Admin roles can access all 4 data screens by default', () {
      apiService.setCachedUserForTesting(
        UserModel(id: '1', username: 'scout_lead', teamNumber: 1234, role: 'ANALYTICS'),
      );

      expect(apiService.hasPageAccess('all-data'), isTrue);
      expect(apiService.hasPageAccess('match-data'), isTrue);
      expect(apiService.hasPageAccess('pit-data'), isTrue);
      expect(apiService.hasPageAccess('qual-data'), isTrue);
    });

    test('SuperAdmin has unconditional access to all 4 data screens', () {
      apiService.setCachedUserForTesting(
        UserModel(id: '1', username: 'root', teamNumber: 1234, role: 'SUPERADMIN'),
      );

      expect(apiService.hasPageAccess('all-data'), isTrue);
      expect(apiService.hasPageAccess('match-data'), isTrue);
      expect(apiService.hasPageAccess('pit-data'), isTrue);
      expect(apiService.hasPageAccess('qual-data'), isTrue);
    });
  });

  group('Data Screens Widget Rendering Tests', () {
    late _MockDataApiService mockApi;

    setUp(() {
      mockApi = _MockDataApiService();
      mockApi.setCachedUserForTesting(
        UserModel(id: '1', username: 'tester', teamNumber: 1234, role: 'ADMIN'),
      );
    });

    testWidgets('AllDataScreen renders header, metrics, entries, and filters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllDataScreen(apiService: mockApi),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('All Scouting Data'), findsOneWidget);
      expect(find.text('Total Entries'), findsOneWidget);
      expect(find.text('Pit Entries'), findsOneWidget);
      expect(find.text('Match Entries'), findsOneWidget);
      expect(find.text('Qualitative'), findsOneWidget);
      expect(find.text('Filters & Search'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Team 1234'), findsWidgets);
    });

    testWidgets('MatchDataScreen renders header, metrics, records, and match filters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MatchDataScreen(apiService: mockApi),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Match Scouting Data'), findsOneWidget);
      expect(find.text('Match Entries'), findsOneWidget);
      expect(find.text('Teams Scouted'), findsOneWidget);
      expect(find.text('Conflicts'), findsOneWidget);
      expect(find.text('Filter Match Records'), findsOneWidget);
      expect(find.text('Conflicts Only'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Team 1234'), findsOneWidget);
    });

    testWidgets('PitDataScreen renders header, coverage metrics, and team cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PitDataScreen(apiService: mockApi),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Pit Scouting Data'), findsOneWidget);
      expect(find.text('Teams Scouted'), findsOneWidget);
      expect(find.text('Coverage'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('Filters & Quick Field View'), findsOneWidget);
      expect(find.text('Needs Pit Scouting'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Team 1234'), findsOneWidget);
      expect(find.text('COMPLETE'), findsOneWidget);
      expect(find.text('MISSING'), findsOneWidget);
    });

    testWidgets('QualDataScreen renders header, metrics, tabs, and team rankings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualDataScreen(apiService: mockApi),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Qualitative Data Center'), findsOneWidget);
      expect(find.text('Qual Entries'), findsOneWidget);
      expect(find.text('Teams Ranked'), findsOneWidget);
      expect(find.text('Ranking & Performance Config'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Team Rankings'), findsOneWidget);
      expect(find.text('Entry List'), findsOneWidget);
      expect(find.text('Team 1234'), findsWidgets);
    });

    testWidgets('ConflictResolutionModal renders comparisons and interactive actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool resolvedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ConflictResolutionModal.show(
                    context: context,
                    apiService: mockApi,
                    title: 'Match 1 - Team 1234 Conflict',
                    subtitle: '2 scouters submitted conflicting data',
                    type: 'match',
                    fields: [
                      ScoutingFieldModel(id: 'autoNotes', label: 'Auto Notes', type: 'number'),
                      ScoutingFieldModel(id: 'teleopNotes', label: 'Teleop Notes', type: 'number'),
                    ],
                    conflictingEntries: [
                      {
                        'id': 'entry-1',
                        'scoutUsername': 'scouter_alice',
                        'createdAt': '2026-03-01T12:00:00.000Z',
                        'data': {'autoNotes': 4, 'teleopNotes': 8},
                      },
                      {
                        'id': 'entry-2',
                        'scoutUsername': 'scouter_bob',
                        'createdAt': '2026-03-01T12:02:00.000Z',
                        'data': {'autoNotes': 2, 'teleopNotes': 8},
                      },
                    ],
                    onResolved: () {
                      resolvedCalled = true;
                    },
                  );
                },
                child: const Text('Open Resolver'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Resolver'));
      await tester.pumpAndSettle();

      expect(find.text('Match 1 - Team 1234 Conflict'), findsOneWidget);
      expect(find.text('Merge / Avg'), findsOneWidget);
      expect(find.text('#1: scouter_alice'), findsOneWidget);
      expect(find.text('#2: scouter_bob'), findsOneWidget);
      expect(find.text('DIFF'), findsWidgets);
      expect(find.text('Keep This'), findsWidgets);

      // Tap Merge / Avg
      await tester.tap(find.text('Merge / Avg'));
      await tester.pumpAndSettle();

      expect(resolvedCalled, isTrue);
    });
  });
}

