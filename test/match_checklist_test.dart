import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/match_checklist_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/config_collab/config_sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UserModel user({required String role, bool tools = false}) =>
      UserModel(id: 'u1', username: 'driver', teamNumber: 254, role: role, nonScoutingToolsEnabled: tools);

  group('Non-Scouting Tools preference', () {
    test('defaults to off and round-trips through JSON', () {
      expect(UserModel.fromJson({'id': '1', 'username': 'a', 'teamNumber': 1}).nonScoutingToolsEnabled, isFalse);
      final on = UserModel.fromJson(user(role: 'SCOUT', tools: true).toJson());
      expect(on.nonScoutingToolsEnabled, isTrue);
    });

    test('Match Checklist is shown only when the user turned the tools on, whatever their role', () {
      final api = ApiService();
      for (final role in ['SCOUT', 'ANALYTICS', 'ADMIN', 'SUPERADMIN']) {
        api.setCachedUserForTesting(user(role: role));
        expect(api.hasPageAccess('match-checklist'), isFalse, reason: '$role with tools off');
        api.setCachedUserForTesting(user(role: role, tools: true));
        expect(api.hasPageAccess('match-checklist'), isTrue, reason: '$role with tools on');
      }
    });

    test('live checklist socket URL targets the template or one match', () {
      final api = ApiService();
      final template = api.matchChecklistCollabUri();
      expect(template.path, '/api/match-checklist/collab');
      expect(template.queryParameters, {'template': '1'});
      expect(template.scheme, anyOf('ws', 'wss'));
      final match = api.matchChecklistCollabUri(eventKey: '2026casj', matchKey: '2026casj_qm1');
      expect(match.queryParameters, {'eventKey': '2026casj', 'matchKey': '2026casj_qm1'});
    });
  });

  group('Live checklist merging', () {
    var n = 0;
    String newKey() => 'k${n++}';

    test('two people checking different items at once both keep their checks', () {
      var server = ConfigSyncEngine.keyed({'checked': <String, dynamic>{}, 'notes': ''}, newKey);
      final a = ConfigSyncEngine.cloneMap(server.doc)..['checked'] = {'item1': {'by': 'alex', 'at': 1}};
      final b = ConfigSyncEngine.cloneMap(server.doc)..['checked'] = {'item2': {'by': 'sam', 'at': 2}};
      final opsA = ConfigSyncEngine.diff(server, a, newKey).ops;
      final opsB = ConfigSyncEngine.diff(server, b, newKey).ops;
      server = ConfigSyncEngine.applyOps(ConfigSyncEngine.applyOps(server, opsA), opsB);
      expect((server.doc['checked'] as Map).keys, containsAll(['item1', 'item2']));
    });

    test('editing different properties of one item at once merges', () {
      var tpl = ConfigSyncEngine.keyed({
        'fields': [
          {'id': 'x', 'section': 'pre', 'text': 'Bumpers', 'priority': 'normal'},
        ],
      }, newKey);
      final t1 = ConfigSyncEngine.cloneMap(tpl.doc);
      (t1['fields'] as List)[0] = {...(t1['fields'] as List)[0] as Map<String, dynamic>, 'text': 'Bumpers on'};
      final t2 = ConfigSyncEngine.cloneMap(tpl.doc);
      (t2['fields'] as List)[0] = {...(t2['fields'] as List)[0] as Map<String, dynamic>, 'priority': 'critical'};
      final o1 = ConfigSyncEngine.diff(tpl, t1, newKey).ops;
      final o2 = ConfigSyncEngine.diff(tpl, t2, newKey).ops;
      tpl = ConfigSyncEngine.applyOps(ConfigSyncEngine.applyOps(tpl, o1), o2);
      final field = (tpl.doc['fields'] as List).single as Map;
      expect(field['text'], 'Bumpers on');
      expect(field['priority'], 'critical');
    });
  });

  testWidgets('screen explains how to turn the tools on when they are off', (tester) async {
    final api = ApiService();
    api.setCachedUserForTesting(user(role: 'SCOUT'));
    var openedSettings = false;
    await tester.pumpWidget(MaterialApp(
      home: MatchChecklistScreen(apiService: api, isBarsVisible: false, onOpenSettings: () => openedSettings = true),
    ));
    expect(find.text('Non-scouting tools are turned off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(openedSettings, isTrue);
  });

  testWidgets('building the lists offline: starter items, priorities and the fill-out view', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    api.setCachedUserForTesting(user(role: 'SCOUT', tools: true));
    await tester.pumpWidget(MaterialApp(home: MatchChecklistScreen(apiService: api, isBarsVisible: false)));
    // Loading touches real storage / HTTP (which fails in tests), so let real time pass.
    for (var i = 0; i < 50 && find.text('Load starter items').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    // An empty template opens in Edit mode.
    expect(find.text('Load starter items'), findsOneWidget);
    await tester.tap(find.text('Load starter items'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Fresh battery installed and strapped down'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Correct autonomous routine selected'), findsOneWidget);
    // Removed starter items stay removed.
    expect(find.textContaining('pneumatics'), findsNothing);

    // Add a low-priority item, then check it is listed after the critical ones when filling out.
    await tester.enterText(find.widgetWithText(TextField, 'Add an item...').first, 'Wave to the crowd');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Wave to the crowd'), findsOneWidget);

    await tester.tap(find.text('Fill Out'));
    await tester.pump();
    final battery = tester.getTopLeft(find.text('Fresh battery installed and strapped down')).dy;
    final wave = tester.getTopLeft(find.text('Wave to the crowd')).dy;
    final mechanical = tester.getTopLeft(find.text('All bolts, chains and belts checked')).dy;
    expect(battery < mechanical, isTrue, reason: 'critical before high');
    expect(mechanical < wave, isTrue, reason: 'high before normal');
    expect(find.text('CRITICAL'), findsWidgets);
    // No match picked yet, so nothing can be checked.
    expect(find.text('Pick a match to start checking items off.'), findsOneWidget);
  });
}
