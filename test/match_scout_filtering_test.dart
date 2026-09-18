import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/match_scout_screen.dart';
import 'package:obsidianscout_app/screens/qual_scout_screen.dart';

class _MockScoutApiService extends ApiService {
  @override
  bool get isOnline => true;

  @override
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<String?> getCachedEventKey() async => '2026test';

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Match Test Config',
        fields: [
          ScoutingFieldModel(id: 'auto_cones', label: 'Auto Cones', type: 'counter', phase: 'auto'),
          ScoutingFieldModel(id: 'teleop_cubes', label: 'Teleop Cubes', type: 'counter', phase: 'teleop'),
        ],
      );

  @override
  Future<ScoutingConfigModel?> getCachedMatchConfig() async => fetchMatchConfig();

  @override
  Future<ScoutingConfigModel?> fetchQualConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Qual Test Config',
        fields: [
          ScoutingFieldModel(id: 'driver_skill', label: 'Driver Skill', type: 'rating'),
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
        TeamModel(eventKey: '2026test', teamKey: 'frc5419', teamNumber: 5419, nickname: 'Berkelium'),
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
        MatchModel(
          eventKey: '2026test',
          matchKey: '2026test_qm2',
          matchNumber: 2,
          compLevel: 'qm',
          label: 'Quals 2',
          redTeams: ['frc5419', 'frc118', 'frc254'],
          blueTeams: ['frc1678', 'frc148', 'frc2056'],
        ),
        MatchModel(
          eventKey: '2026test',
          matchKey: '2026test_qm3',
          matchNumber: 3,
          compLevel: 'qm',
          label: 'Quals 3',
          redTeams: ['frc971', 'frc5419', 'frc148'],
          blueTeams: ['frc118', 'frc1678', 'frc2056'],
        ),
      ];

  @override
  Future<List<MatchModel>> getCachedMatches(String? eventKey) async => fetchMatches(eventKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MatchModel Team Extraction & Search', () {
    test('hasTeam detects team from red and blue alliances with various key prefixes', () {
      final match = MatchModel(
        eventKey: '2026test',
        matchKey: '2026test_qm1',
        compLevel: 'qm',
        label: 'Quals 1',
        redTeams: ['frc254', 'ftc971/1', '1678'],
        blueTeams: ['frc118', 'frc148', 'frc2056'],
      );

      expect(match.hasTeam(254), isTrue);
      expect(match.hasTeam(971), isTrue);
      expect(match.hasTeam(1678), isTrue);
      expect(match.hasTeam(118), isTrue);
      expect(match.hasTeam(148), isTrue);
      expect(match.hasTeam(2056), isTrue);
      expect(match.hasTeam(5419), isFalse);
    });

    test('getTeamNumbers parses all numbers from red and blue teams', () {
      final match = MatchModel(
        eventKey: '2026test',
        matchKey: '2026test_qm1',
        compLevel: 'qm',
        label: 'Quals 1',
        redTeams: ['frc254', 'frc1678'],
        blueTeams: ['frc118', 'frc148'],
      );

      final nums = match.getTeamNumbers();
      expect(nums, containsAll([254, 1678, 118, 148]));
      expect(nums.length, 4);
    });
  });

  group('MatchScoutScreen Bidirectional Filtering', () {
    testWidgets('Selecting a team limits match dropdown to matches containing that team', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: MatchScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();

      final team971 = find.text('971 - Spartan Robotics').last;
      await tester.tap(team971);
      await tester.pumpAndSettle();

      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();

      expect(find.text('Quals 1'), findsWidgets);
      expect(find.text('Quals 3'), findsWidgets);
      expect(find.text('Quals 2'), findsNothing);
    });

    testWidgets('Selecting a match limits team dropdown to teams playing in that match', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: MatchScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();

      final quals1 = find.text('Quals 1').last;
      await tester.tap(quals1);
      await tester.pumpAndSettle();

      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();

      expect(find.text('254 - Cheesy Poofs'), findsWidgets);
      expect(find.text('1678 - Citrus Circuits'), findsWidgets);
      expect(find.text('971 - Spartan Robotics'), findsWidgets);
      expect(find.text('5419 - Berkelium'), findsNothing);
    });

    testWidgets('Clear button resets selection and restores options', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: MatchScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('971 - Spartan Robotics').last);
      await tester.pumpAndSettle();

      final clearTeamBtn = find.byTooltip('Clear Team').first;
      expect(clearTeamBtn, findsOneWidget);
      await tester.tap(clearTeamBtn);
      await tester.pumpAndSettle();

      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();

      expect(find.text('Quals 1'), findsWidgets);
      expect(find.text('Quals 2'), findsWidgets);
      expect(find.text('Quals 3'), findsWidgets);
    });

    testWidgets('When both match and team are selected, team dropdown fully populates and changing team clears match', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: MatchScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select Team 254
      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('254 - Cheesy Poofs').last);
      await tester.pumpAndSettle();

      // 2. Select Quals 1 (now both are selected)
      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // 3. Open Team dropdown again -> verify it is FULLY POPULATED with all teams (including 5419 which is not in Quals 1)
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();
      expect(find.text('5419 - Berkelium'), findsWidgets);

      // 4. Select Team 5419 -> verify match is cleared and match dropdown now shows 5419's matches (Quals 2 and Quals 3, NOT Quals 1)
      await tester.tap(find.text('5419 - Berkelium').last);
      await tester.pumpAndSettle();

      await tester.tap(matchFinder);
      await tester.pumpAndSettle();

      expect(find.text('Quals 2'), findsWidgets);
      expect(find.text('Quals 3'), findsWidgets);
      expect(find.text('Quals 1'), findsNothing);
    });

    testWidgets('When both match and team are selected, match dropdown fully populates and changing match clears team', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: MatchScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select Match Quals 1
      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quals 1').last);
      await tester.pumpAndSettle();

      // 2. Select Team 254 (now both are selected)
      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('254 - Cheesy Poofs').last);
      await tester.pumpAndSettle();

      // 3. Open Match dropdown again -> verify it is FULLY POPULATED with all matches (Quals 1, Quals 2, Quals 3)
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();
      expect(find.text('Quals 1'), findsWidgets);
      expect(find.text('Quals 2'), findsWidgets);
      expect(find.text('Quals 3'), findsWidgets);

      // 4. Select Quals 3 -> verify team is cleared and team dropdown shows Quals 3's teams (971, 5419, 148, 118, 1678, 2056; NOT 254)
      await tester.tap(find.text('Quals 3').last);
      await tester.pumpAndSettle();

      await tester.tap(teamFinder);
      await tester.pumpAndSettle();

      expect(find.text('5419 - Berkelium'), findsWidgets);
      expect(find.text('971 - Spartan Robotics'), findsWidgets);
      expect(find.text('254 - Cheesy Poofs'), findsNothing);
    });
  });

  group('QualScoutScreen Single Team Bidirectional Filtering', () {
    testWidgets('Selecting team limits match dropdown in QualScoutScreen single team mode', (tester) async {
      final mockApi = _MockScoutApiService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: QualScoutScreen(apiService: mockApi),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final teamFinder = find.byType(DropdownButtonFormField<TeamModel>).first;
      await tester.tap(teamFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5419 - Berkelium').last);
      await tester.pumpAndSettle();

      final matchFinder = find.byType(DropdownButtonFormField<MatchModel>).first;
      await tester.tap(matchFinder);
      await tester.pumpAndSettle();

      expect(find.text('Quals 2'), findsWidgets);
      expect(find.text('Quals 3'), findsWidgets);
      expect(find.text('Quals 1'), findsNothing);
    });
  });
}
