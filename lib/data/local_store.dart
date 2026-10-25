import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';
import 'test_env_stub.dart' if (dart.library.io) 'test_env_io.dart';

/// A submission waiting in the outbox.
class OutboxItem {
  final String id;
  final String kind;
  final String? eventKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final String? historyId;

  const OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.eventKey,
    this.attempts = 0,
    this.lastError,
    this.historyId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'eventKey': eventKey,
        'payload': payload,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'attempts': attempts,
        'lastError': lastError,
        'historyId': historyId,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'].toString(),
        kind: json['kind'].toString(),
        eventKey: json['eventKey']?.toString(),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num?)?.toInt() ?? 0),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['lastError']?.toString(),
        historyId: json['historyId']?.toString(),
      );
}

/// On-device storage for everything too large for SharedPreferences: cached API responses,
/// checklist/collab documents, drafts, scout history and the upload outbox.
///
/// On Android, iOS, Windows, macOS and Linux this is a SQLite database (drift) that runs on
/// a background isolate and only loads what is asked for. SharedPreferences, by contrast,
/// keeps every stored value in memory for the life of the app.
///
/// On web, or if the database can't be opened (for example in widget tests), it falls back
/// to SharedPreferences with the same keys, so behaviour is unchanged there.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  /// Set before first use to skip SQLite (tests, diagnostics).
  static bool debugForcePrefsBackend = false;

  /// Values longer than this are JSON-decoded on a background isolate.
  static const int offThreadDecodeThreshold = 64 * 1024;

  static const String _historyPrefsKey = 'obsidianscout:scout_history';
  static const String _outboxPrefsKey = 'obsidianscout:outbox';
  static const String _migratedFlag = 'local_db_migrated_v1';
  static const String _cleanedFlag = 'local_db_prefs_cleaned_v1';

  /// Number of submissions waiting to upload. Drives the "saved on this device only" banner.
  final ValueNotifier<int> outboxCount = ValueNotifier<int>(0);

  LocalDb? _db;
  Future<void>? _ready;

  bool get usingDatabase => _db != null;

  /// SharedPreferences keys whose values now live in the database.
  static bool isMovedPrefsKey(String key) =>
      key.startsWith('cache_') ||
      key.startsWith('checklist_drafts_') ||
      key.startsWith('battery_drafts_') ||
      key.startsWith('scouting_draft_') ||
      key == 'obsidianscout:scanned_qr_entries';

  Future<void> ensureReady() => _ready ??= _open();

  Future<void> _open() async {
    if (!kIsWeb && !debugForcePrefsBackend && !isFlutterTestEnvironment) {
      LocalDb? db;
      try {
        db = LocalDb.open();
        await db.customSelect('SELECT 1').get().timeout(const Duration(seconds: 10));
        _db = db;
        await _migrateFromPrefs();
      } catch (e) {
        debugPrint('[LocalStore] SQLite unavailable, using SharedPreferences: $e');
        _db = null;
        try {
          await db?.close();
        } catch (_) {}
      }
    }
    await _refreshOutboxCount();
  }

  /// First launch on the new version copies the large prefs entries into SQLite. The prefs
  /// copies are deleted only on the following launch, so a crash mid-migration loses nothing.
  Future<void> _migrateFromPrefs() async {
    final db = _db!;
    final prefs = await SharedPreferences.getInstance();
    final movedKeys = prefs.getKeys().where((k) => isMovedPrefsKey(k) || k == _historyPrefsKey).toList();

    if (prefs.getInt(_migratedFlag) == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction(() async {
        for (final key in movedKeys) {
          if (key == _historyPrefsKey) continue;
          final value = prefs.get(key);
          if (value is! String) continue;
          await db.into(db.kvEntries).insertOnConflictUpdate(
                KvEntriesCompanion.insert(key: key, value: value, updatedAt: now),
              );
        }
        final rawHistory = prefs.getString(_historyPrefsKey);
        if (rawHistory != null && rawHistory.isNotEmpty) {
          try {
            final list = jsonDecode(rawHistory);
            if (list is List) {
              for (final item in list.whereType<Map>()) {
                final map = Map<String, dynamic>.from(item);
                final id = map['id']?.toString();
                if (id == null) continue;
                await db.into(db.scoutHistoryRows).insertOnConflictUpdate(
                      ScoutHistoryRowsCompanion.insert(
                        id: id,
                        createdAt: _timestampOf(map),
                        json: jsonEncode(map),
                      ),
                    );
              }
            }
          } catch (_) {}
        }
      });
      await prefs.setInt(_migratedFlag, now);
      debugPrint('[LocalStore] Moved ${movedKeys.length} entries from SharedPreferences to SQLite.');
    } else if (prefs.getBool(_cleanedFlag) != true) {
      for (final key in movedKeys) {
        await prefs.remove(key);
      }
      await prefs.setBool(_cleanedFlag, true);
    }
  }

  static int _timestampOf(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    if (raw is num) return raw.toInt();
    return DateTime.tryParse(raw?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
  }

  // ── Key/value ─────────────────────────────────────────────────────────────

  Future<String?> getString(String key) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    final row = await (db.select(db.kvEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setString(String key, String value) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await db.into(db.kvEntries).insertOnConflictUpdate(
          KvEntriesCompanion.insert(key: key, value: value, updatedAt: DateTime.now().millisecondsSinceEpoch),
        );
  }

  Future<void> remove(String key) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await (db.delete(db.kvEntries)..where((t) => t.key.equals(key))).go();
  }

  /// Keys starting with [prefix], with the stored value's length in characters.
  Future<Map<String, int>> sizesWithPrefix(String prefix) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      return {
        for (final k in prefs.getKeys().where((k) => k.startsWith(prefix)))
          k: (prefs.get(k) is String) ? (prefs.getString(k)!.length) : 0,
      };
    }
    final rows = await db.customSelect(
      'SELECT key, length(value) AS size FROM kv_entries WHERE key LIKE ? ESCAPE \'\\\'',
      variables: [Variable.withString('${_escapeLike(prefix)}%')],
      readsFrom: {db.kvEntries},
    ).get();
    return {for (final r in rows) r.read<String>('key'): r.read<int>('size')};
  }

  Future<void> removeWithPrefix(String prefix) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
        await prefs.remove(k);
      }
      return;
    }
    await db.customStatement(
      'DELETE FROM kv_entries WHERE key LIKE ? ESCAPE \'\\\'',
      ['${_escapeLike(prefix)}%'],
    );
  }

  static String _escapeLike(String s) => s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');

  /// Decodes JSON, moving large documents to a background isolate so the UI doesn't stutter.
  static Future<dynamic> decodeJson(String raw) {
    if (raw.length < offThreadDecodeThreshold) return Future.value(jsonDecode(raw));
    return compute(_decode, raw);
  }

  static dynamic _decode(String raw) => jsonDecode(raw);

  /// Reads and decodes a stored JSON value; null when missing or malformed.
  Future<dynamic> getJson(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return await decodeJson(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Scout history ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> loadHistory() async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyPrefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = await decodeJson(raw);
      return decoded is List ? decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : [];
    }
    final rows = await (db.select(db.scoutHistoryRows)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    if (rows.isEmpty) return [];
    // Decode the whole set in one background pass when it's large (photos make payloads big).
    final joined = '[${rows.map((r) => r.json).join(',')}]';
    final decoded = await decodeJson(joined);
    return (decoded as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Inserts or replaces one history record.
  Future<void> putHistory(Map<String, dynamic> entry) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final all = await loadHistory();
      all.removeWhere((e) => e['id'] == entry['id']);
      all.insert(0, entry);
      await _writeHistoryPrefs(all);
      return;
    }
    await db.into(db.scoutHistoryRows).insertOnConflictUpdate(
          ScoutHistoryRowsCompanion.insert(
            id: entry['id'].toString(),
            createdAt: _timestampOf(entry),
            json: jsonEncode(entry),
          ),
        );
  }

  /// Replaces every history record with [entries].
  Future<void> replaceHistory(List<Map<String, dynamic>> entries) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      await _writeHistoryPrefs(entries);
      return;
    }
    await db.transaction(() async {
      await db.delete(db.scoutHistoryRows).go();
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.scoutHistoryRows, [
          for (final e in entries)
            ScoutHistoryRowsCompanion.insert(id: e['id'].toString(), createdAt: _timestampOf(e), json: jsonEncode(e)),
        ]);
      });
    });
  }

  Future<void> deleteHistory(Iterable<String> ids) async {
    await ensureReady();
    final db = _db;
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    if (db == null) {
      final all = await loadHistory();
      all.removeWhere((e) => idSet.contains(e['id']?.toString()));
      await _writeHistoryPrefs(all);
      return;
    }
    await (db.delete(db.scoutHistoryRows)..where((t) => t.id.isIn(idSet))).go();
  }

  /// Keeps the newest [keep] records and drops any created before [notBefore].
  Future<void> trimHistory({required int keep, DateTime? notBefore}) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final all = await loadHistory();
      all.sort((a, b) => _timestampOf(b).compareTo(_timestampOf(a)));
      final cutoff = notBefore?.millisecondsSinceEpoch;
      final kept = all.where((e) => cutoff == null || _timestampOf(e) >= cutoff).take(keep).toList();
      if (kept.length != all.length) await _writeHistoryPrefs(kept);
      return;
    }
    if (notBefore != null) {
      await (db.delete(db.scoutHistoryRows)..where((t) => t.createdAt.isSmallerThanValue(notBefore.millisecondsSinceEpoch))).go();
    }
    await db.customStatement(
      'DELETE FROM scout_history_rows WHERE id NOT IN '
      '(SELECT id FROM scout_history_rows ORDER BY created_at DESC LIMIT ?)',
      [keep],
    );
  }

  Future<void> clearHistory() async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyPrefsKey);
      return;
    }
    await db.delete(db.scoutHistoryRows).go();
  }

  Future<void> _writeHistoryPrefs(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyPrefsKey, jsonEncode(entries));
  }

  // ── Outbox ────────────────────────────────────────────────────────────────

  Future<void> enqueue(OutboxItem item) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final all = await _readOutboxPrefs();
      all.add(item);
      await _writeOutboxPrefs(all);
    } else {
      await db.into(db.outboxItems).insertOnConflictUpdate(
            OutboxItemsCompanion.insert(
              id: item.id,
              kind: item.kind,
              eventKey: Value(item.eventKey),
              payload: jsonEncode(item.payload),
              createdAt: item.createdAt.millisecondsSinceEpoch,
              attempts: Value(item.attempts),
              lastError: Value(item.lastError),
              historyId: Value(item.historyId),
            ),
          );
    }
    await _refreshOutboxCount();
  }

  /// Oldest first, which is the order they are uploaded in.
  Future<List<OutboxItem>> outbox() async {
    await ensureReady();
    final db = _db;
    if (db == null) return _readOutboxPrefs();
    final rows = await (db.select(db.outboxItems)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    return rows
        .map((r) => OutboxItem(
              id: r.id,
              kind: r.kind,
              eventKey: r.eventKey,
              payload: Map<String, dynamic>.from(jsonDecode(r.payload) as Map),
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
              attempts: r.attempts,
              lastError: r.lastError,
              historyId: r.historyId,
            ))
        .toList();
  }

  Future<void> removeFromOutbox(String id) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final all = await _readOutboxPrefs();
      all.removeWhere((i) => i.id == id);
      await _writeOutboxPrefs(all);
    } else {
      await (db.delete(db.outboxItems)..where((t) => t.id.equals(id))).go();
    }
    await _refreshOutboxCount();
  }

  Future<void> recordOutboxFailure(String id, String error) async {
    await ensureReady();
    final db = _db;
    if (db == null) {
      final all = await _readOutboxPrefs();
      final idx = all.indexWhere((i) => i.id == id);
      if (idx >= 0) {
        final old = all[idx];
        all[idx] = OutboxItem(
          id: old.id,
          kind: old.kind,
          eventKey: old.eventKey,
          payload: old.payload,
          createdAt: old.createdAt,
          attempts: old.attempts + 1,
          lastError: error,
          historyId: old.historyId,
        );
        await _writeOutboxPrefs(all);
      }
      return;
    }
    await db.customStatement(
      'UPDATE outbox_items SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<List<OutboxItem>> _readOutboxPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_outboxPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().map((m) => OutboxItem.fromJson(Map<String, dynamic>.from(m))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeOutboxPrefs(List<OutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_outboxPrefsKey);
    } else {
      await prefs.setString(_outboxPrefsKey, jsonEncode(items.map((i) => i.toJson()).toList()));
    }
  }

  Future<void> _refreshOutboxCount() async {
    try {
      // Only scouting entries count; queued assignment status changes aren't "entries".
      final db = _db;
      if (db == null) {
        outboxCount.value = (await _readOutboxPrefs()).where((i) => i.kind != 'assignment_status').length;
      } else {
        final count = db.outboxItems.id.count();
        final row = await (db.selectOnly(db.outboxItems)
              ..addColumns([count])
              ..where(db.outboxItems.kind.equals('assignment_status').not()))
            .getSingle();
        outboxCount.value = row.read(count) ?? 0;
      }
    } catch (_) {}
  }

  /// Test hook: use [db] (e.g. an in-memory database) and run the prefs migration against it.
  @visibleForTesting
  Future<void> useDatabaseForTesting(LocalDb db) async {
    await resetForTesting();
    _db = db;
    _ready = () async {
      await _migrateFromPrefs();
      await _refreshOutboxCount();
    }();
    await _ready;
  }

  /// Test hook: forget the opened backend so the next call re-initialises.
  @visibleForTesting
  Future<void> resetForTesting() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _ready = null;
    outboxCount.value = 0;
  }
}
