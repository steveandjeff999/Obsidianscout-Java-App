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
  static const int maxRetentionDays = 30;

  /// Optional hook to resolve currently active account username across the app
  static String? Function()? currentAccountProvider;
  static String? Function()? currentAccountIdProvider;

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
  /// Automatically purges records older than [maxRetentionDays] days (30 days).
  static Future<List<ScoutHistoryEntry>> loadAll({bool pruneExpired = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> list = jsonDecode(raw);
      final entries = list
          .map((e) => ScoutHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      if (pruneExpired) {
        final now = DateTime.now();
        const maxAge = Duration(days: maxRetentionDays);
        final validEntries = entries.where((e) => now.difference(e.timestamp) <= maxAge).toList();

        if (validEntries.length != entries.length) {
          await _persist(prefs, validEntries);
        }
        validEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return validEntries;
      }

      // Newest first
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// Load history entries scoped strictly to [account].
  /// If [account] is null or empty (i.e. logged out), returns an empty list
  /// ensuring unauthorized accounts cannot view other users' local history.
  static Future<List<ScoutHistoryEntry>> loadForAccount(
    String? account, {
    String? accountId,
    bool pruneExpired = true,
  }) async {
    if (account == null || account.trim().isEmpty) {
      return [];
    }
    final allEntries = await loadAll(pruneExpired: pruneExpired);
    return allEntries.where((e) => e.matchesAccount(account, accountId)).toList();
  }

  /// Proactively purges all entries older than [maxAge] (defaults to 30 days).
  /// Returns the number of entries deleted.
  static Future<int> purgeExpiredEntries({
    Duration maxAge = const Duration(days: maxRetentionDays),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return 0;
      final List<dynamic> list = jsonDecode(raw);
      final entries = list
          .map((e) => ScoutHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      final now = DateTime.now();
      final validEntries = entries.where((e) => now.difference(e.timestamp) <= maxAge).toList();
      final purgedCount = entries.length - validEntries.length;

      if (purgedCount > 0) {
        await _persist(prefs, validEntries);
      }
      return purgedCount;
    } catch (_) {
      return 0;
    }
  }

  /// Append a new entry and persist. Trims to [maxEntries] oldest on overflow.
  /// Automatically purges records older than [maxRetentionDays] days.
  static Future<void> addEntry(ScoutHistoryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadAll(pruneExpired: true);

      // Don't add if already expired
      if (entry.isExpired(maxAge: const Duration(days: maxRetentionDays))) {
        return;
      }

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

  /// Delete synced entries. If [account] is provided, only removes synced entries
  /// belonging to that account, preserving other accounts' local entries.
  static Future<void> clearSynced({String? account, String? accountId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await loadAll();
      final filtered = entries.where((e) {
        if (e.status != 'synced') return true;
        if (account != null && account.trim().isNotEmpty) {
          // If scoped to account, only remove if it matches account
          return !e.matchesAccount(account, accountId);
        }
        return false;
      }).toList();
      await _persist(prefs, filtered);
    } catch (_) {}
  }

  /// Wipe history entries. If [account] is provided, only deletes entries
  /// scouted by that account, preserving other users' local entries on shared devices.
  static Future<void> clearAll({String? account, String? accountId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (account != null && account.trim().isNotEmpty) {
        final entries = await loadAll();
        final kept = entries.where((e) => !e.matchesAccount(account, accountId)).toList();
        await _persist(prefs, kept);
      } else {
        await prefs.remove(_storageKey);
      }
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
    String? scoutedBy,
    String? scoutedById,
    DateTime? timestamp,
  }) {
    final teamNumber = _extractInt(payload, ['targetTeamNumber', 'team_number', 'teamNumber']);
    final eventKey = payload['eventKey']?.toString() ??
        payload['event_key']?.toString() ?? '';
    final matchKey = payload['matchKey']?.toString() ??
        payload['match_key']?.toString();
    final matchNumber = _extractInt(payload, ['matchNumber', 'match_number']);
    final compLevel = payload['compLevel']?.toString() ??
        payload['comp_level']?.toString();

    final resolvedScoutedBy = scoutedBy ??
        currentAccountProvider?.call() ??
        payload['scoutedBy']?.toString() ??
        payload['scoutName']?.toString() ??
        payload['scout_name']?.toString() ??
        payload['username']?.toString();

    final resolvedScoutedById = scoutedById ??
        currentAccountIdProvider?.call() ??
        payload['scoutedById']?.toString() ??
        payload['userId']?.toString();

    return ScoutHistoryEntry(
      id: generateId(),
      type: type,
      action: action,
      timestamp: timestamp ?? DateTime.now(),
      teamNumber: teamNumber,
      eventKey: eventKey,
      matchKey: matchKey,
      matchNumber: matchNumber,
      compLevel: compLevel,
      status: status,
      payload: payload,
      scoutedBy: resolvedScoutedBy,
      scoutedById: resolvedScoutedById,
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
