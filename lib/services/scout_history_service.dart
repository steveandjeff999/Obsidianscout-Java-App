import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scout_history_models.dart';

/// Persists scouting history entries on-device via SharedPreferences.
/// All entries for match, pit, and qual scouting actions are stored here
/// regardless of how they were submitted (direct upload, QR, or offline cache).
class ScoutHistoryService {
  static const String _storageKey = 'obsidianscout:scout_history';
  static const int maxEntries = 500;

  // ---------------------------------------------------------------------------
  // Unique ID generation (no external package required)
  // ---------------------------------------------------------------------------
  static final Random _rng = Random.secure();

  static String generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(0xFFFFFF);
    return '${ts.toRadixString(16)}-${rand.toRadixString(16).padLeft(6, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Core CRUD operations
  // ---------------------------------------------------------------------------

  /// Load all history entries from SharedPreferences, newest first.
  static Future<List<ScoutHistoryEntry>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> list = jsonDecode(raw);
      final entries = list
          .map((e) => ScoutHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      // Newest first
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// Append a new entry and persist. Trims to [maxEntries] oldest on overflow.
  static Future<void> addEntry(ScoutHistoryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadAll();
      current.insert(0, entry);
      final trimmed = current.length > maxEntries
          ? current.sublist(0, maxEntries)
          : current;
      await _persist(prefs, trimmed);
    } catch (_) {}
  }

  /// Update the status of a single entry by id.
  static Future<void> updateStatus(String id, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await loadAll();
      final idx = entries.indexWhere((e) => e.id == id);
      if (idx == -1) return;
      entries[idx] = entries[idx].copyWith(status: status);
      await _persist(prefs, entries);
    } catch (_) {}
  }

  /// Delete a single entry by id.
  static Future<void> deleteEntry(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await loadAll();
      entries.removeWhere((e) => e.id == id);
      await _persist(prefs, entries);
    } catch (_) {}
  }

  /// Delete all entries with status == 'synced'.
  static Future<void> clearSynced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await loadAll();
      final filtered = entries.where((e) => e.status != 'synced').toList();
      await _persist(prefs, filtered);
    } catch (_) {}
  }

  /// Wipe all history entries.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  static Future<void> _persist(
      SharedPreferences prefs, List<ScoutHistoryEntry> entries) async {
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  // ---------------------------------------------------------------------------
  // Factory helpers — build a ScoutHistoryEntry from a scout screen's data map
  // ---------------------------------------------------------------------------

  static ScoutHistoryEntry buildEntry({
    required String type,         // 'match', 'pit', 'qual'
    required String action,       // 'direct_upload', 'qr_generated', 'offline_cached'
    required String status,       // 'synced', 'pending', 'failed'
    required Map<String, dynamic> payload,
  }) {
    final teamNumber = _extractInt(payload, ['targetTeamNumber', 'team_number', 'teamNumber']);
    final eventKey = payload['eventKey']?.toString() ??
        payload['event_key']?.toString() ?? '';
    final matchKey = payload['matchKey']?.toString() ??
        payload['match_key']?.toString();
    final matchNumber = _extractInt(payload, ['matchNumber', 'match_number']);
    final compLevel = payload['compLevel']?.toString() ??
        payload['comp_level']?.toString();

    return ScoutHistoryEntry(
      id: generateId(),
      type: type,
      action: action,
      timestamp: DateTime.now(),
      teamNumber: teamNumber,
      eventKey: eventKey,
      matchKey: matchKey,
      matchNumber: matchNumber,
      compLevel: compLevel,
      status: status,
      payload: payload,
    );
  }

  static int _extractInt(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }
}
