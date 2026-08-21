import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/models/validation_models.dart';
import 'package:obsidianscout_app/screens/data_validation_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';

class _MockValidationApiService extends ApiService {
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
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<ValidationSummaryModel?> fetchValidationData({
    String? eventKey,
    double threshold = 15.0,
    bool forcePrescout = false,
  }) async {
    return ValidationSummaryModel(
      eventKey: '2026test',
      totalMatches: 2,
      fullyScoutedMatches: 1,
      incompleteMatches: 1,
      unscoutedMatches: 0,
      matchesWithAnomalies: 1,
      teamsAnalyzed: 2,
      teamsWithAnomalies: 1,
      useStatboticsEpa: true,
      useTbaOpr: true,
      threshold: threshold,
      matches: [
        MatchValidationModel(
          matchKey: '2026test_qm1',
          eventKey: '2026test',
          compLevel: 'qm',
          matchNumber: 1,
          label: 'QM 1',
          redAlliance: AllianceValidationModel(
            allianceColor: 'red',
            teams: [254, 1678, 1323],
            scoutedTeams: [254, 1678, 1323],
            missingTeams: [],
            isFullyScouted: true,
            actualScore: 120.0,
            scoutedScoreSum: 145.0,
            scoreDiff: 25.0,
            isAnomaly: true,
            teamBreakdowns: [
              TeamMatchEntryBreakdownModel(teamNumber: 254, teamKey: 'frc254', scoutedScore: 50.0, entryId: 'e1', scouterName: 'Alice'),
              TeamMatchEntryBreakdownModel(teamNumber: 1678, teamKey: 'frc1678', scoutedScore: 55.0, entryId: 'e2', scouterName: 'Bob'),
              TeamMatchEntryBreakdownModel(teamNumber: 1323, teamKey: 'frc1323', scoutedScore: 40.0, entryId: 'e3', scouterName: 'Charlie'),
            ],
          ),
          blueAlliance: AllianceValidationModel(
            allianceColor: 'blue',
            teams: [971, 973, 581],
            scoutedTeams: [971, 973, 581],
            missingTeams: [],
            isFullyScouted: true,
            actualScore: 100.0,
            scoutedScoreSum: 102.0,
            scoreDiff: 2.0,
            isAnomaly: false,
          ),
          isFullyScouted: true,
          hasAnomaly: true,
        ),
        MatchValidationModel(
          matchKey: '2026test_qm2',
          eventKey: '2026test',
          compLevel: 'qm',
          matchNumber: 2,
          label: 'QM 2',
          redAlliance: AllianceValidationModel(
            allianceColor: 'red',
            teams: [118, 148, 4414],
            scoutedTeams: [118],
            missingTeams: [148, 4414],
            isFullyScouted: false,
            actualScore: 90.0,
            scoutedScoreSum: 30.0,
            scoreDiff: -60.0,
            isAnomaly: false,
          ),
          blueAlliance: AllianceValidationModel(
            allianceColor: 'blue',
            teams: [2056, 1114, 2767],
            scoutedTeams: [2056, 1114, 2767],
            missingTeams: [],
            isFullyScouted: true,
            actualScore: 110.0,
            scoutedScoreSum: 108.0,
            scoreDiff: -2.0,
            isAnomaly: false,
          ),
          isFullyScouted: false,
          hasAnomaly: false,
        ),
      ],
      teams: [
        TeamValidationModel(
          teamNumber: 254,
          teamKey: 'frc254',
          nickname: 'The Cheesy Poofs',
          scoutedMatchCount: 1,
          averageScoutedScore: 50.0,
          epa: 32.0,
          opr: 33.5,
          epaDiff: 18.0,
          oprDiff: 16.5,
          isAnomaly: true,
          anomalyReason: 'Scouted avg (50.0) deviates from Statbotics EPA (32.0) by +18.0',
        ),
        TeamValidationModel(
          teamNumber: 1678,
          teamKey: 'frc1678',
          nickname: 'Citrus Circuits',
          scoutedMatchCount: 1,
          averageScoutedScore: 55.0,
          epa: 54.0,
          opr: 53.0,
          epaDiff: 1.0,
          oprDiff: 2.0,
          isAnomaly: false,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Validation Models serialization', () {
    test('ValidationSummaryModel fromJson and toJson roundtrip', () {
      final json = {
        'eventKey': '2026test',
        'totalMatches': 10,
        'fullyScoutedMatches': 8,
        'incompleteMatches': 2,
        'unscoutedMatches': 0,
        'matchesWithAnomalies': 3,
        'teamsAnalyzed': 24,
        'teamsWithAnomalies': 4,
        'useStatboticsEpa': true,
        'useTbaOpr': true,
        'threshold': 15.0,
        'matches': [
          {
            'matchKey': '2026test_qm1',
            'eventKey': '2026test',
            'compLevel': 'qm',
            'matchNumber': 1,
            'label': 'QM 1',
            'redAlliance': {
              'allianceColor': 'red',
              'teams': [254, 1678, 1323],
              'scoutedTeams': [254],
              'missingTeams': [1678, 1323],
              'isFullyScouted': false,
              'actualScore': 100.0,
              'scoutedScoreSum': 35.0,
              'scoreDiff': -65.0,
              'isAnomaly': false,
              'teamBreakdowns': [
                {
                  'teamNumber': 254,
                  'teamKey': 'frc254',
                  'scoutedScore': 35.0,
                  'entryId': 'e_254',
                  'scouterName': 'Alex',
                  'hasDiscrepancy': false,
                }
              ]
            },
            'blueAlliance': {
              'allianceColor': 'blue',
              'teams': [971, 973, 581],
              'scoutedTeams': [],
              'missingTeams': [971, 973, 581],
              'isFullyScouted': false,
              'scoutedScoreSum': 0.0,
              'isAnomaly': false,
              'teamBreakdowns': []
            },
            'isFullyScouted': false,
            'hasAnomaly': false,
          }
        ],
        'teams': [
          {
            'teamNumber': 254,
            'teamKey': 'frc254',
            'nickname': 'The Cheesy Poofs',
            'scoutedMatchCount': 2,
            'averageScoutedScore': 38.5,
            'epa': 40.0,
            'opr': 39.0,
            'epaDiff': -1.5,
            'oprDiff': -0.5,
            'isAnomaly': false,
          }
        ]
      };

      final model = ValidationSummaryModel.fromJson(json);
      expect(model.eventKey, '2026test');
      expect(model.totalMatches, 10);
      expect(model.matches.length, 1);
      expect(model.matches.first.label, 'QM 1');
      expect(model.matches.first.redAlliance.teams, [254, 1678, 1323]);
      expect(model.matches.first.redAlliance.teamBreakdowns.first.scouterName, 'Alex');
      expect(model.teams.first.nickname, 'The Cheesy Poofs');

      final serialized = model.toJson();
      expect(serialized['eventKey'], '2026test');
      expect(serialized['totalMatches'], 10);
    });
  });

  group('DataValidationScreen Widget tests', () {
    testWidgets('Renders KPI metrics, match list, tabs, and inspection modal', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = _MockValidationApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataValidationScreen(
              apiService: mockApi,
              isVisible: true,
              isBarsVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check KPI metrics
      expect(find.text('TOTAL MATCHES'), findsOneWidget);
      expect(find.text('FULLY SCOUTED'), findsOneWidget);
      expect(find.text('INCOMPLETE'), findsOneWidget);
      expect(find.text('MATCH ANOMALIES'), findsOneWidget);
      expect(find.text('TEAM ALERTS'), findsOneWidget);

      // Check Match records
      expect(find.text('QM 1'), findsOneWidget);
      expect(find.text('QM 2'), findsOneWidget);
      expect(find.text('Score Anomaly'), findsOneWidget);
      expect(find.text('Inspect Breakdown'), findsNWidgets(2));

      // Tap Inspect Breakdown on QM 1
      await tester.tap(find.text('Inspect Breakdown').first);
      await tester.pumpAndSettle();

      // Check Inspection Modal contents
      expect(find.text('QM 1 Validation Breakdown'), findsOneWidget);
      expect(find.text('RED ALLIANCE'), findsOneWidget);
      expect(find.text('BLUE ALLIANCE'), findsOneWidget);
      expect(find.text('Team 254'), findsOneWidget);
      expect(find.text('Scouter: Alice'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Switch to Team EPA / OPR tab
      final teamTab = find.textContaining('Team EPA / OPR');
      expect(teamTab, findsOneWidget);
      await tester.tap(teamTab);
      await tester.pumpAndSettle();

      // Check team cards
      expect(find.text('The Cheesy Poofs'), findsOneWidget);
      expect(find.text('Citrus Circuits'), findsOneWidget);
      expect(find.textContaining('Scouted avg (50.0) deviates from Statbotics EPA'), findsOneWidget);
    });
  });
}
