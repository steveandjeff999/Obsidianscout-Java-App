import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/match_data_screen.dart';
import 'package:obsidianscout_app/screens/pit_data_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/widgets/edit_scouting_entry_modal.dart';

class _RecordingApiService extends ApiService {
  Map<String, dynamic>? savedData;
  String settingsEventKey = '2026test';
  List<dynamic> matchEntries = const [];
  List<dynamic> pitEntries = const [];

  @override
  bool get isOnline => true;

  @override
  Future<ApiResponse<void>> updateScoutingEntry(String id, Map<String, dynamic> data, {String type = 'match'}) async {
    savedData = data;
    return const ApiResponse.success(null);
  }

  @override
  Future<AppSettingsModel?> fetchSettings() async => AppSettingsModel(year: 2026, eventKey: settingsEventKey, eventCode: 'test');

  @override
  Future<AppSettingsModel?> getCachedSettings() async => fetchSettings();

  @override
  Future<List<EventModel>> fetchEvents({int? year}) async => [EventModel(eventKey: '2026test', name: 'Test Regional', year: 2026)];

  @override
  Future<List<EventModel>> getCachedEvents({int? year}) async => fetchEvents(year: year);

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async =>
      [TeamModel(eventKey: '2026test', teamKey: 'frc1234', teamNumber: 1234, nickname: 'Obsidian Bots')];

  @override
  Future<List<TeamModel>> getCachedTeams(String? eventKey) async => fetchTeams(eventKey);

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(version: 1, title: 'Match', fields: [
        ScoutingFieldModel(id: 'auto_notes', label: 'Auto Notes', type: 'counter'),
      ]);

  @override
  Future<ScoutingConfigModel?> getCachedMatchConfig() async => fetchMatchConfig();

  @override
  Future<ScoutingConfigModel?> fetchPitConfig() async => ScoutingConfigModel(version: 1, title: 'Pit', fields: [
        ScoutingFieldModel(id: 'robot_weight', label: 'Robot Weight', type: 'number'),
      ]);

  @override
  Future<ScoutingConfigModel?> getCachedPitConfig() async => fetchPitConfig();

  @override
  Future<List<dynamic>> fetchScoutingEntries({bool forceRefresh = false}) async => matchEntries;

  @override
  Future<List<dynamic>> getCachedScoutingEntries() async => matchEntries;

  @override
  Future<List<dynamic>> fetchPitScoutingEntries({bool forceRefresh = false}) async => pitEntries;

  @override
  Future<List<dynamic>> getCachedPitScoutingEntries() async => pitEntries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingApiService api;

  setUp(() {
    api = _RecordingApiService();
    api.setCachedUserForTesting(UserModel(id: '1', username: 'tester', teamNumber: 1234, role: 'ADMIN'));
  });

  group('extraFields', () {
    test('keeps each stored value\'s type and leaves out what it can\'t edit', () {
      final fields = EditScoutingEntryModal.extraFields({
        'known': 1,
        'eventKey': '2026test',
        'timestamp': 123,
        'startPos': 2,
        'onField': true,
        'scoutName': 'sam',
        'autoPath': {'points': [1, 2]},
        'tags': ['a', 'b'],
        'photo': 'data:image/png;base64,AAAA',
        'missing': null,
      }, {'known'});

      expect({for (final f in fields) f.id: f.type}, {'startPos': 'number', 'onField': 'boolean', 'scoutName': 'notes'});
    });
  });

  testWidgets('saving without changes sends every stored value back unchanged', (tester) async {
    final stored = <String, dynamic>{
      'auto_notes': 3,
      'startPos': 2,
      'onField': true,
      'autoPath': {'points': [1, 2]},
      'tags': ['a', 'b'],
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EditScoutingEntryModal(
          apiService: api,
          id: 'abc',
          type: 'match',
          title: 'Edit',
          targetTeamNumber: 1234,
          matchNumber: 1,
          matchKey: '2026test_qm1',
          eventKey: '2026test',
          initialData: stored,
          fields: [
            ScoutingFieldModel(id: 'auto_notes', label: 'Auto Notes', type: 'counter'),
            ScoutingFieldModel(id: 'endgame', label: 'Endgame', type: 'select', options: [ScoutingOptionModel(label: 'Park', value: 'Park')]),
          ],
          onSaved: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.save_rounded));
    await tester.pump();

    expect(api.savedData, {
      ...stored,
      'targetTeamNumber': 1234,
      'eventKey': '2026test',
      'matchKey': '2026test_qm1',
      'matchNumber': 1,
    });
    expect(api.savedData!.containsKey('endgame'), isFalse);
  });

  Future<void> saveFromDetailSheet(WidgetTester tester, Widget screen, String entryLabel) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text(entryLabel).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save_rounded));
    await tester.pump();
  }

  testWidgets('a prescout match entry keeps its real event key', (tester) async {
    api.settingsEventKey = '';
    api.matchEntries = [
      <String, dynamic>{
        'id': '101',
        'targetTeamNumber': 1234,
        'eventKey': '2026real',
        'isPrescout': true,
        'matchNumber': 1,
        'matchKey': '2026real_qm1',
        'data': <String, dynamic>{'auto_notes': 4},
      },
    ];

    await saveFromDetailSheet(tester, MatchDataScreen(apiService: api), 'Team 1234');

    expect(api.savedData?['eventKey'], '2026real');
  });

  testWidgets('a prescout pit entry keeps its real event key', (tester) async {
    api.pitEntries = [
      <String, dynamic>{
        'id': '201',
        'targetTeamNumber': 1234,
        'eventKey': '2026real',
        'isPrescout': true,
        'data': <String, dynamic>{'robot_weight': 115},
      },
    ];

    await saveFromDetailSheet(tester, PitDataScreen(apiService: api), 'Team 1234');

    expect(api.savedData?['eventKey'], '2026real');
  });
}
