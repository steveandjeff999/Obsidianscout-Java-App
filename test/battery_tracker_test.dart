import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/l10n/app_localizations.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/battery_tracker_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/battery_rotation.dart';
import 'package:obsidianscout_app/services/battery_tracker_sync.dart';
import 'package:obsidianscout_app/widgets/battery_match_banner.dart';

// Same cases as the website's src/test/js/battery-rotation.test.mjs (copied from
// Site/.../src/test/resources/battery-rotation-cases.json).
final _cases = (jsonDecode(File('test/fixtures/battery-rotation-cases.json').readAsStringSync()) as Map<String, dynamic>)['cases'] as List;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UserModel user({bool tools = true}) =>
      UserModel(id: 'u1', username: 'driver', teamNumber: 254, role: 'SCOUT', nonScoutingToolsEnabled: tools);

  group('Rotation (shared cases)', () {
    for (final c in _cases.cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final schedule = BatteryRotation.computeSchedule(
          Map<String, dynamic>.from(c['inventory'] as Map),
          Map<String, dynamic>.from(c['plan'] as Map),
          (c['matches'] as List).cast<String>(),
        );
        final actual = schedule.map((k, v) => MapEntry(k, [v.batteryId, v.source]));
        expect(actual, (c['expected'] as Map).map((k, v) => MapEntry(k, v)));
      });
    }
  });

  group('Plan edits', () {
    final inventory = {
      'batteries': {
        'b1': {'name': 'B1', 'order': 0},
        'b2': {'name': 'B2', 'order': 1},
        'b3': {'name': 'B3', 'order': 2},
      },
    };
    List<String?> ids(Map<String, dynamic> plan, List<String> keys) {
      final s = BatteryRotation.computeSchedule(inventory, plan, keys);
      return keys.map((k) => s[k]!.batteryId).toList();
    }

    test('skip pulls the next battery; clearing skips restores the rotation', () {
      final plan = <String, dynamic>{};
      BatteryRotation.skip(plan, 'q1', 'b1', 'alex');
      expect(ids(plan, ['q1', 'q2']), ['b2', 'b3']);
      expect(((plan['matches'] as Map)['q1'] as Map)['skipped'], contains('b1'));
      BatteryRotation.clearSkips(plan, 'q1');
      expect(ids(plan, ['q1', 'q2']), ['b1', 'b2']);
      expect(plan['matches'], isEmpty);
    });

    test('pin, mark used and usage', () {
      final plan = <String, dynamic>{};
      BatteryRotation.pin(plan, 'q1', 'b3');
      expect(ids(plan, ['q1', 'q2']), ['b3', 'b1']);
      BatteryRotation.markUsed(plan, 'q1', 'b3');
      expect(BatteryRotation.usedOf(plan, 'q1'), 'b3');
      expect(BatteryRotation.usageByBattery(plan, ['q1', 'q2']), {'b3': ['q1']});
      BatteryRotation.skip(plan, 'q1', 'b3', 'alex');
      expect(BatteryRotation.usedOf(plan, 'q1'), '');
      expect(BatteryRotation.pinnedOf(plan, 'q1'), '');
      expect(BatteryRotation.autoMarkUsed(plan), isTrue);
      expect(BatteryRotation.autoMarkUsed({'autoMarkUsed': false}), isFalse);
    });

    test('match order matches the website: practice, quals, then playoffs by set', () {
      final keys = ['e_sf2m1', 'e_qm10', 'e_sf1m1', 'e_qm2', 'e_pr1', 'e_f1m1'];
      final level = {'e_sf2m1': 'sf', 'e_qm10': 'qm', 'e_sf1m1': 'sf', 'e_qm2': 'qm', 'e_pr1': 'pr', 'e_f1m1': 'f'};
      final number = {'e_sf2m1': 1, 'e_qm10': 10, 'e_sf1m1': 1, 'e_qm2': 2, 'e_pr1': 1, 'e_f1m1': 1};
      keys.sort((a, b) => BatteryRotation.compareMatchOrder(level[a]!, number[a], a, level[b]!, number[b], b));
      expect(keys, ['e_pr1', 'e_qm2', 'e_qm10', 'e_f1m1', 'e_sf1m1', 'e_sf2m1']);
    });
  });

  test('Battery Tracker is shown only with Non-Scouting Tools on', () {
    final api = ApiService();
    api.setCachedUserForTesting(user(tools: false));
    expect(api.hasPageAccess('battery-tracker'), isFalse);
    api.setCachedUserForTesting(user());
    expect(api.hasPageAccess('battery-tracker'), isTrue);
  });

  test('offline battery edits are kept as drafts and come back after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService()..setCachedUserForTesting(user());
    final sync = BatteryTrackerSync.of(api);
    final room = await sync.acquire('2026casj');
    sync.edit(room, (doc) => BatteryRotation.skip(doc, '2026casj_qm1', 'b1', 'driver'));
    await sync.persistDraft(room);
    expect(sync.pendingOfflineCount, 1);
    sync.release(room);
    expect(sync.rooms.map((r) => r.id), contains('event|2026casj'));
    sync.dispose();

    final api2 = ApiService()..setCachedUserForTesting(user());
    final sync2 = BatteryTrackerSync.of(api2);
    await sync2.resumeDrafts();
    final restored = sync2.rooms.single;
    expect(restored.eventKey, '2026casj');
    expect(((restored.doc['matches'] as Map)['2026casj_qm1'] as Map)['skipped'], contains('b1'));
    expect(restored.pendingOffline, isTrue);
    sync2.dispose();
  });

  testWidgets('screen explains how to turn the tools on when they are off', (tester) async {
    final api = ApiService()..setCachedUserForTesting(user(tools: false));
    var openedSettings = false;
    await tester.pumpWidget(MaterialApp(
      home: BatteryTrackerScreen(apiService: api, isBarsVisible: false, onOpenSettings: () => openedSettings = true),
    ));
    expect(find.text('Non-scouting tools are turned off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(openedSettings, isTrue);
  });

  testWidgets('adding batteries offline: quick add, pit type and retire', (tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final api = ApiService()..setCachedUserForTesting(user());
    api.setCachedSettingsForTesting(AppSettingsModel.fromJson({'eventKey': '2026test', 'year': 2026}));
    final sync = BatteryTrackerSync.of(api);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: BatteryTrackerScreen(apiService: api, isBarsVisible: false),
    ));
    for (var i = 0; i < 50 && find.text('Add B1–B6').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('Add B1–B6'), findsOneWidget);

    await tester.tap(find.text('Add B1–B6'));
    await settle();
    for (var n = 1; n <= 6; n++) {
      expect(find.widgetWithText(TextField, 'B$n'), findsOneWidget);
    }
    expect(find.textContaining("Battery changes can't be saved"), findsOneWidget);

    // Add a pit battery by name.
    await tester.enterText(find.widgetWithText(TextField, 'Battery name, e.g. B7'), 'Spare');
    await tester.tap(find.text('Match').last);
    await settle();
    await tester.tap(find.text('Pit').last);
    await settle();
    await tester.tap(find.text('+ Add'));
    await settle();
    final inventory = sync.rooms.firstWhere((r) => r.isInventory).doc;
    final batteries = BatteryRotation.batteriesOf(inventory);
    expect(batteries.map((b) => b.displayName), ['B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'Spare']);
    expect(batteries.last.isPit, isTrue);
    expect(BatteryRotation.rotationOf(inventory).map((b) => b.displayName), ['B1', 'B2', 'B3', 'B4', 'B5', 'B6']);
    expect(find.textContaining('PIT BATTERIES (NEVER IN A MATCH) · 1'), findsOneWidget);
    sync.dispose();
  });

  testWidgets('match banner offers skip and mark used, and hides skip once used', (tester) async {
    final actions = <String>[];
    // No translations loaded: the banner falls back to English.
    Widget banner(BatterySlot slot) => MaterialApp(
          home: Scaffold(
            body: BatteryMatchBanner(
              slot: slot,
              nameOf: (id) => id.toUpperCase(),
              onSkip: () => actions.add('skip'),
              onUnskip: () => actions.add('unskip'),
              onMarkUsed: () => actions.add('use'),
              onUnmarkUsed: () => actions.add('unuse'),
            ),
          ),
        );
    await tester.pumpWidget(banner(const BatterySlot('b3', 'auto', ['b1'])));
    await tester.pumpAndSettle();
    expect(find.text('Battery: B3'), findsOneWidget);
    expect(find.text('Skipped: B1'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.tap(find.text('Undo skips'));
    await tester.tap(find.text('Mark used'));
    expect(actions, ['skip', 'unskip', 'use']);

    await tester.pumpWidget(banner(const BatterySlot('b3', 'used', [])));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.text('Not used'));
    expect(actions.last, 'unuse');
  });
}
