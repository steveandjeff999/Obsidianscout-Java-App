import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/l10n/app_localizations.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/match_checklist_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/config_collab/config_sync_engine.dart';
import 'package:obsidianscout_app/services/match_checklist_sync.dart';

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

  group('Checklist lists', () {
    test('older templates read as the Pre-Match and On the Field lists, every match', () {
      final lists = checklistListsOf({
        'sections': {
          'pre': {'title': 'Before'},
        },
        'fields': [],
      });
      expect(lists.map((l) => l.id), ['pre', 'field']);
      expect(lists.first.title, 'Before');
      expect(lists.every((l) => l.frequency == 'match'), isTrue);
    });

    test('lists keep their order, frequency and interval; converting an older template keeps its titles', () {
      final doc = <String, dynamic>{
        'sections': {
          'field': {'title': 'Queue'},
        },
      };
      final lists = ensureChecklistLists(doc);
      expect(lists.keys, containsAll(['pre', 'field']));
      expect((lists['field'] as Map)['title'], 'Queue');
      lists['x'] = {'title': 'Swerve', 'order': -1, 'frequency': 'every_n', 'every': 3};
      lists['y'] = {'title': 'Pit', 'order': 9, 'frequency': 'daily'};
      lists['z'] = {'title': 'Weigh-in', 'order': 10, 'frequency': 'bogus', 'every': 500};
      final read = checklistListsOf(doc);
      expect(read.map((l) => l.id), ['x', 'pre', 'field', 'y', 'z']);
      expect(read.first.frequency, 'every_n');
      expect(read.first.every, 3);
      expect(read.firstWhere((l) => l.id == 'y').frequency, 'daily');
      expect(read.last.frequency, 'match', reason: 'unknown frequencies fall back to every match');
      expect(read.last.every, 99, reason: 'interval is clamped');
    });

    test('day records are keyed by the local date', () {
      expect(MatchChecklistSync.todayKey(DateTime(2026, 3, 7)), 'day_2026-03-07');
      expect(MatchChecklistSync.roomIdFor('2026casj', 'event'), '2026casj|event');
      expect(MatchChecklistSync.roomIdFor('', MatchChecklistSync.templateKey), 'template');
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

    test('renaming one list while someone changes another list\'s frequency merges', () {
      var tpl = ConfigSyncEngine.keyed({
        'lists': {
          'a': {'title': 'A', 'order': 0, 'frequency': 'match', 'every': 2},
          'b': {'title': 'B', 'order': 1, 'frequency': 'match', 'every': 2},
        },
      }, newKey);
      final t1 = ConfigSyncEngine.cloneMap(tpl.doc);
      (t1['lists'] as Map)['a'] = {...(t1['lists'] as Map)['a'] as Map<String, dynamic>, 'title': 'Pre-match'};
      final t2 = ConfigSyncEngine.cloneMap(tpl.doc);
      (t2['lists'] as Map)['b'] = {...(t2['lists'] as Map)['b'] as Map<String, dynamic>, 'frequency': 'daily'};
      tpl = ConfigSyncEngine.applyOps(
        ConfigSyncEngine.applyOps(tpl, ConfigSyncEngine.diff(tpl, t1, newKey).ops),
        ConfigSyncEngine.diff(tpl, t2, newKey).ops,
      );
      final lists = checklistListsOf(tpl.doc);
      expect(lists.first.title, 'Pre-match');
      expect(lists.last.frequency, 'daily');
    });
  });

  group('Offline edits', () {
    test('are kept as drafts and come back after a restart, still waiting to be saved', () async {
      SharedPreferences.setMockInitialValues({});
      // Not signed in: no live connection can be made, like being offline.
      final api = ApiService()..setCachedUserForTesting(user(role: 'SCOUT', tools: true));
      final sync = MatchChecklistSync.of(api);
      final room = await sync.acquire('2026casj', '2026casj_qm1');
      sync.edit(room, (doc) => doc['checked'] = {'battery': {'by': 'driver', 'at': 1}});
      await sync.persistDraft(room);
      expect(sync.pendingOfflineCount, 1);

      // Leaving the screen keeps the room open until the edit is saved.
      sync.release(room);
      expect(sync.rooms.map((r) => r.id), contains('2026casj|2026casj_qm1'));
      sync.dispose();

      // "Restart": a fresh service picks the draft up again.
      final api2 = ApiService()..setCachedUserForTesting(user(role: 'SCOUT', tools: true));
      final sync2 = MatchChecklistSync.of(api2);
      await sync2.resumeDrafts();
      final restored = sync2.rooms.single;
      expect(restored.id, '2026casj|2026casj_qm1');
      expect((restored.session.lastView.doc['checked'] as Map).keys, ['battery']);
      expect(restored.pendingOffline, isTrue);
      sync2.dispose();
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

  testWidgets('building lists offline: starter items, a daily list, priorities and the offline banner', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    api.setCachedUserForTesting(user(role: 'SCOUT', tools: true));
    api.setCachedSettingsForTesting(AppSettingsModel.fromJson({'eventKey': '2026test', 'year': 2026}));
    final sync = MatchChecklistSync.of(api);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: MatchChecklistScreen(apiService: api, isBarsVisible: false),
    ));
    // Loading touches real storage / HTTP (which fails in tests), so let real time pass.
    for (var i = 0; i < 50 && find.text('Load starter items').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    // An empty template opens in Edit mode, with nothing waiting to be saved.
    expect(find.text('Load starter items'), findsOneWidget);
    expect(find.byKey(const ValueKey('checklist-offline-banner')), findsNothing);

    await tester.tap(find.text('Load starter items'));
    await settle();
    expect(find.widgetWithText(TextField, 'Fresh battery installed and strapped down'), findsOneWidget);
    expect(find.textContaining('pneumatics'), findsNothing);
    // Edits that can't reach the server are flagged.
    expect(find.byKey(const ValueKey('checklist-offline-banner')), findsOneWidget);
    expect(find.textContaining("can't be saved until you're back online"), findsOneWidget);

    // Add a list, make it daily and give it two items.
    await tester.tap(find.text('Add list'));
    await settle();
    final titles = find.widgetWithText(TextField, 'List name');
    await tester.enterText(titles.last, 'Pit check');
    await settle();
    await tester.tap(find.text('Every match').last);
    await settle();
    await tester.tap(find.text('Once a day').last);
    await settle();
    final addFields = find.widgetWithText(TextField, 'Add an item...');
    await tester.enterText(addFields.last, 'Sweep the pit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    await tester.enterText(find.widgetWithText(TextField, 'Add an item...').last, 'Charge spare batteries');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(find.widgetWithText(TextField, 'Sweep the pit'), findsOneWidget);

    // Bump the second item to Critical.
    final priorityDropdowns = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>);
    // Order in the daily list: [frequency, item1 priority, item2 priority, add-row priority].
    await tester.tap(priorityDropdowns.at(priorityDropdowns.evaluate().length - 2));
    await settle();
    await tester.tap(find.text('Critical').last);
    await settle();

    await tester.tap(find.text('Fill Out'));
    await settle();
    // The daily list can be filled without a match; its critical item comes first.
    expect(find.textContaining('Once a day'), findsWidgets);
    final charge = tester.getTopLeft(find.text('Charge spare batteries')).dy;
    final sweep = tester.getTopLeft(find.text('Sweep the pit')).dy;
    expect(charge < sweep, isTrue, reason: 'critical before normal');
    // Per-match lists wait for a match.
    expect(find.text('Pick a match to fill this list.'), findsWidgets);

    // Check an item in the daily list while offline: still kept, still flagged.
    await tester.tap(find.text('Sweep the pit'));
    await settle();
    final day = sync.rooms.firstWhere((r) => r.matchKey.startsWith('day_'));
    expect((day.session.lastView.doc['checked'] as Map).length, 1);
    expect(find.byKey(const ValueKey('checklist-offline-banner')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
