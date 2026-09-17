import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/models/scout_history_models.dart';
import 'package:obsidianscout_app/services/scout_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScoutHistoryEntry Model', () {
    test('serialization roundtrip works', () {
      final entry = ScoutHistoryEntry(
        id: 'test-123',
        type: 'match',
        action: 'direct_upload',
        timestamp: DateTime(2026, 8, 22, 10, 30),
        teamNumber: 254,
        eventKey: '2026casj',
        matchKey: 'qm12',
        matchNumber: 12,
        compLevel: 'qm',
        status: 'synced',
        payload: {'auto_notes': 5, 'teleop_speaker': 10},
      );

      final json = entry.toJson();
      final deserialized = ScoutHistoryEntry.fromJson(json);

      expect(deserialized.id, equals('test-123'));
      expect(deserialized.type, equals('match'));
      expect(deserialized.action, equals('direct_upload'));
      expect(deserialized.teamNumber, equals(254));
      expect(deserialized.eventKey, equals('2026casj'));
      expect(deserialized.matchKey, equals('qm12'));
      expect(deserialized.matchNumber, equals(12));
      expect(deserialized.status, equals('synced'));
      expect(deserialized.payload['auto_notes'], equals(5));
      expect(deserialized.displayLabel, equals('Team 254 • qm12'));
    });
  });

  group('ScoutHistoryService', () {
    test('addEntry, loadAll, updateStatus, deleteEntry, clearSynced, clearAll', () async {
      // 1. Initial should be empty
      var list = await ScoutHistoryService.loadAll();
      expect(list, isEmpty);

      // 2. Add entry
      final entry1 = ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'direct_upload',
        status: 'synced',
        payload: {
          'targetTeamNumber': 254,
          'matchKey': 'qm1',
          'eventKey': '2026casj',
          'teleop_score': 15,
        },
      );
      await ScoutHistoryService.addEntry(entry1);

      list = await ScoutHistoryService.loadAll();
      expect(list.length, equals(1));
      expect(list.first.teamNumber, equals(254));
      expect(list.first.status, equals('synced'));

      // 3. Add second entry (pending)
      final entry2 = ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'qr_generated',
        status: 'pending',
        payload: {
          'targetTeamNumber': 1678,
          'eventKey': '2026casj',
          'drivetrain': 'Swerve',
        },
      );
      await ScoutHistoryService.addEntry(entry2);

      list = await ScoutHistoryService.loadAll();
      expect(list.length, equals(2));

      // 4. Update status of entry2 to synced
      await ScoutHistoryService.updateStatus(entry2.id, 'synced');
      list = await ScoutHistoryService.loadAll();
      final updatedEntry2 = list.firstWhere((e) => e.id == entry2.id);
      expect(updatedEntry2.status, equals('synced'));

      // 5. Delete entry1
      await ScoutHistoryService.deleteEntry(entry1.id);
      list = await ScoutHistoryService.loadAll();
      expect(list.length, equals(1));
      expect(list.first.id, equals(entry2.id));

      // 6. Clear synced (should remove entry2 since it is synced)
      await ScoutHistoryService.clearSynced();
      list = await ScoutHistoryService.loadAll();
      expect(list, isEmpty);

      // 7. Add another and clearAll
      await ScoutHistoryService.addEntry(entry1);
      await ScoutHistoryService.clearAll();
      list = await ScoutHistoryService.loadAll();
      expect(list, isEmpty);

      // 8. Test Prescout and QR scanned actions
      final prescoutEntry = ScoutHistoryService.buildEntry(
        type: 'prescout-match',
        action: 'offline_cached',
        status: 'pending',
        payload: {
          'targetTeamNumber': 971,
          'matchNumber': 5,
          'eventKey': '2026casj',
          'auto_points': 20,
        },
      );
      await ScoutHistoryService.addEntry(prescoutEntry);

      final qrScannedEntry = ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'qr_scanned',
        status: 'synced',
        payload: {
          'targetTeamNumber': 973,
          'matchKey': 'qm15',
          'eventKey': '2026casj',
        },
      );
      await ScoutHistoryService.addEntry(qrScannedEntry);

      list = await ScoutHistoryService.loadAll();
      expect(list.length, equals(2));
      expect(list.any((e) => e.type == 'prescout-match' && e.action == 'offline_cached'), isTrue);
      expect(list.any((e) => e.action == 'qr_scanned' && e.status == 'synced'), isTrue);
    });

    test('30-day retention auto-purges entries older than 30 days', () async {
      final now = DateTime.now();

      // 1. Fresh entry (5 days old)
      final freshEntry = ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'direct_upload',
        status: 'synced',
        timestamp: now.subtract(const Duration(days: 5)),
        payload: {'targetTeamNumber': 254},
      );
      await ScoutHistoryService.addEntry(freshEntry);

      // 2. Expired entry (35 days old)
      final expiredEntry = ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'direct_upload',
        status: 'synced',
        timestamp: now.subtract(const Duration(days: 35)),
        payload: {'targetTeamNumber': 1678},
      );
      // Manually add expired entry to storage bypassing addEntry check to test loadAll prune
      final all = await ScoutHistoryService.loadAll(pruneExpired: false);
      all.insert(0, expiredEntry);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('obsidianscout:scout_history',
          jsonEncode(all.map((e) => e.toJson()).toList()));

      expect(expiredEntry.isExpired(), isTrue);
      expect(freshEntry.isExpired(), isFalse);

      // 3. Loading with pruneExpired: true should prune the 35-day-old entry
      final loaded = await ScoutHistoryService.loadAll();
      expect(loaded.length, equals(1));
      expect(loaded.first.teamNumber, equals(254));

      // 4. Verify SharedPreferences was updated
      final reloaded = await ScoutHistoryService.loadAll(pruneExpired: false);
      expect(reloaded.length, equals(1));
      expect(reloaded.first.teamNumber, equals(254));
    });

    test('account isolation: only shows entries for logged-in account, else hides them', () async {
      // 1. Add entry for userA
      final entryA = ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'direct_upload',
        status: 'synced',
        scoutedBy: 'ScoutAlice',
        payload: {'targetTeamNumber': 254},
      );
      await ScoutHistoryService.addEntry(entryA);

      // 2. Add entry for userB
      final entryB = ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'direct_upload',
        status: 'synced',
        scoutedBy: 'ScoutBob',
        payload: {'targetTeamNumber': 1678},
      );
      await ScoutHistoryService.addEntry(entryB);

      // 3. UserAlice logs in: should only see userA's entry
      final aliceView = await ScoutHistoryService.loadForAccount('ScoutAlice');
      expect(aliceView.length, equals(1));
      expect(aliceView.first.teamNumber, equals(254));
      expect(aliceView.first.scoutedBy, equals('ScoutAlice'));

      // Case-insensitivity check
      final aliceLower = await ScoutHistoryService.loadForAccount('scoutalice');
      expect(aliceLower.length, equals(1));

      // 4. UserBob logs in: should only see userB's entry
      final bobView = await ScoutHistoryService.loadForAccount('ScoutBob');
      expect(bobView.length, equals(1));
      expect(bobView.first.teamNumber, equals(1678));

      // 5. Logged out / unknown account: hides all entries
      final loggedOutView = await ScoutHistoryService.loadForAccount(null);
      expect(loggedOutView, isEmpty);

      final emptyAccountView = await ScoutHistoryService.loadForAccount('');
      expect(emptyAccountView, isEmpty);

      final strangerView = await ScoutHistoryService.loadForAccount('Stranger');
      expect(strangerView, isEmpty);

      // 6. Scoped clearAll: userA clears their history, userB history remains intact
      await ScoutHistoryService.clearAll(account: 'ScoutAlice');
      final aliceAfterClear = await ScoutHistoryService.loadForAccount('ScoutAlice');
      expect(aliceAfterClear, isEmpty);

      final bobAfterClear = await ScoutHistoryService.loadForAccount('ScoutBob');
      expect(bobAfterClear.length, equals(1));
      expect(bobAfterClear.first.teamNumber, equals(1678));
    });
  });
}
