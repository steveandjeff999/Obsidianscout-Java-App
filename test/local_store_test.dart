import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/data/local_db.dart';
import 'package:obsidianscout_app/data/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = LocalStore.instance;

  // Each test opens its own in-memory database on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<void> openFresh([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    await store.useDatabaseForTesting(LocalDb(NativeDatabase.memory()));
  }

  tearDown(() => store.resetForTesting());

  group('SQLite backend', () {
    test('moves large prefs entries into the database, then clears them on the next launch', () async {
      final history = [
        {'id': 'h1', 'type': 'match', 'timestamp': DateTime(2026, 10, 1).toIso8601String(), 'status': 'pending', 'payload': {}},
      ];
      await openFresh({
        'cache_scouting': '[{"targetTeamNumber":254}]',
        'checklist_drafts_v1_1_FRC_u': '{"room":{}}',
        'obsidianscout:scout_history': jsonEncode(history),
        'obsidianscout_theme_mode': 'dark',
      });

      expect(await store.getString('cache_scouting'), '[{"targetTeamNumber":254}]');
      expect(await store.getString('checklist_drafts_v1_1_FRC_u'), '{"room":{}}');
      expect((await store.loadHistory()).single['id'], 'h1');

      // First launch keeps the prefs copies so a crash mid-migration loses nothing.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_scouting'), isNotNull);

      // Second launch (same prefs, new database handle) removes them; settings stay in prefs.
      await store.useDatabaseForTesting(LocalDb(NativeDatabase.memory()));
      expect(prefs.getString('cache_scouting'), isNull);
      expect(prefs.getString('obsidianscout:scout_history'), isNull);
      expect(prefs.getString('obsidianscout_theme_mode'), 'dark');
    });

    test('key/value round trip, prefix sizes and prefix removal', () async {
      await openFresh();
      await store.setString('cache_a', 'xx');
      await store.setString('cache_b', 'yyyy');
      await store.setString('other', 'z');
      expect(await store.sizesWithPrefix('cache_'), {'cache_a': 2, 'cache_b': 4});
      await store.removeWithPrefix('cache_');
      expect(await store.getString('cache_a'), isNull);
      expect(await store.getString('other'), 'z');
    });

    test('history keeps the newest entries when trimmed', () async {
      await openFresh();
      for (var i = 0; i < 5; i++) {
        await store.putHistory({'id': 'e$i', 'timestamp': DateTime(2026, 10, 1, 12, i).toIso8601String()});
      }
      await store.trimHistory(keep: 3);
      final ids = (await store.loadHistory()).map((e) => e['id']).toList();
      expect(ids, ['e4', 'e3', 'e2']);
    });

    test('outbox count ignores queued assignment status changes', () async {
      await openFresh();
      await store.enqueue(OutboxItem(id: '1', kind: 'match', payload: {'data': {}}, createdAt: DateTime(2026, 10, 1)));
      await store.enqueue(OutboxItem(id: '2', kind: 'assignment_status', payload: {'id': 'a', 'status': 'COMPLETED'}, createdAt: DateTime(2026, 10, 2)));
      expect(store.outboxCount.value, 1);
      expect((await store.outbox()).map((i) => i.id), ['1', '2']);

      await store.recordOutboxFailure('1', 'timeout');
      expect((await store.outbox()).first.attempts, 1);

      await store.removeFromOutbox('1');
      expect(store.outboxCount.value, 0);
    });
  });

  test('large JSON decodes off the UI thread and still returns the same value', () async {
    final big = jsonEncode(List.generate(5000, (i) => {'i': i, 'pad': 'x' * 20}));
    expect(big.length, greaterThan(LocalStore.offThreadDecodeThreshold));
    final decoded = await LocalStore.decodeJson(big) as List;
    expect(decoded.length, 5000);
    expect(decoded.last['i'], 4999);
  });
}
