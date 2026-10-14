import 'dart:math';
import '../data/local_store.dart';
import '../models/assignment_models.dart';
import '../models/scout_history_models.dart';

/// Persists scouting history entries on-device (SQLite via [LocalStore]).
/// All entries for match, pit, and qual scouting actions are stored here
/// regardless of how they were submitted (direct upload, QR, or offline cache).
class ScoutHistoryService {
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

  /// Load all history entries from on-device storage, newest first.
  /// Automatically purges records older than [maxRetentionDays] days (30 days).
  static Future<List<ScoutHistoryEntry>> loadAll({bool pruneExpired = true}) async {
    try {
      final raw = await LocalStore.instance.loadHistory();
      if (raw.isEmpty) return [];
      final entries = raw.map(ScoutHistoryEntry.fromJson).toList();

      if (pruneExpired) {
        final now = DateTime.now();
        const maxAge = Duration(days: maxRetentionDays);
        final validEntries = entries.where((e) => now.difference(e.timestamp) <= maxAge).toList();

        if (validEntries.length != entries.length) {
          final expiredIds = entries.where((e) => now.difference(e.timestamp) > maxAge).map((e) => e.id);
          await LocalStore.instance.deleteHistory(expiredIds);
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
      final entries = await loadAll(pruneExpired: false);
      final now = DateTime.now();
      final expiredIds = entries.where((e) => now.difference(e.timestamp) > maxAge).map((e) => e.id).toList();
      if (expiredIds.isNotEmpty) {
        await LocalStore.instance.deleteHistory(expiredIds);
      }
      return expiredIds.length;
    } catch (_) {
      return 0;
    }
  }

  /// Append a new entry and persist. Trims to [maxEntries] oldest on overflow.
  /// Automatically purges records older than [maxRetentionDays] days.
  static Future<void> addEntry(ScoutHistoryEntry entry) async {
    try {
      // Don't add if already expired
      if (entry.isExpired(maxAge: const Duration(days: maxRetentionDays))) {
        return;
      }
      // One row per entry: adding doesn't rewrite (or re-decode) the rest of the history.
      await LocalStore.instance.putHistory(entry.toJson());
      await LocalStore.instance.trimHistory(
        keep: maxEntries,
        notBefore: DateTime.now().subtract(const Duration(days: maxRetentionDays)),
      );
    } catch (_) {}
  }

  /// Update the status of a single entry by id.
  static Future<void> updateStatus(String id, String status) async {
    try {
      final entries = await loadAll();
      final idx = entries.indexWhere((e) => e.id == id);
      if (idx == -1) return;
      await LocalStore.instance.putHistory(entries[idx].copyWith(status: status).toJson());
    } catch (_) {}
  }

  /// True when two payloads are for the same event, team and match.
  static bool samePayloadTarget(Map<String, dynamic> a, Map<String, dynamic> b) {
    String norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';
    final teamA = _extractInt(a, ['targetTeamNumber', 'team_number', 'teamNumber']);
    final teamB = _extractInt(b, ['targetTeamNumber', 'team_number', 'teamNumber']);
    if (teamA != teamB) return false;
    final eventA = norm(a['eventKey'] ?? a['event_key']);
    final eventB = norm(b['eventKey'] ?? b['event_key']);
    if (eventA.isNotEmpty && eventB.isNotEmpty && eventA != eventB) return false;
    final matchA = norm(a['matchKey'] ?? a['match_key']);
    final matchB = norm(b['matchKey'] ?? b['match_key']);
    if (matchA.isNotEmpty && matchB.isNotEmpty) return matchA == matchB;
    return _extractInt(a, ['matchNumber', 'match_number']) == _extractInt(b, ['matchNumber', 'match_number']);
  }

  /// Sets [status] on not-yet-synced history rows of [type] for the same target as [payload].
  /// Called when the outbox uploads (or the server rejects) a saved submission.
  static Future<void> markMatchingStatus(String type, Map<String, dynamic> payload, String status) async {
    try {
      final entries = await loadAll(pruneExpired: false);
      for (final e in entries) {
        if (e.type != type || e.status == 'synced') continue;
        if (samePayloadTarget(e.payload, payload)) {
          await LocalStore.instance.putHistory(e.copyWith(status: status).toJson());
        }
      }
    } catch (_) {}
  }

  /// Delete a single entry by id.
  static Future<void> deleteEntry(String id) async {
    try {
      await LocalStore.instance.deleteHistory([id]);
    } catch (_) {}
  }

  /// Delete synced entries. If [account] is provided, only removes synced entries
  /// belonging to that account, preserving other accounts' local entries.
  static Future<void> clearSynced({String? account, String? accountId}) async {
    try {
      final entries = await loadAll();
      final toRemove = entries.where((e) {
        if (e.status != 'synced') return false;
        if (account != null && account.trim().isNotEmpty) {
          // If scoped to account, only remove if it matches account
          return e.matchesAccount(account, accountId);
        }
        return true;
      }).map((e) => e.id);
      await LocalStore.instance.deleteHistory(toRemove);
    } catch (_) {}
  }

  /// Wipe history entries. If [account] is provided, only deletes entries
  /// scouted by that account, preserving other users' local entries on shared devices.
  static Future<void> clearAll({String? account, String? accountId}) async {
    try {
      if (account != null && account.trim().isNotEmpty) {
        final entries = await loadAll();
        final ids = entries.where((e) => e.matchesAccount(account, accountId)).map((e) => e.id);
        await LocalStore.instance.deleteHistory(ids);
      } else {
        await LocalStore.instance.clearHistory();
      }
    } catch (_) {}
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

  // ---------------------------------------------------------------------------
  // Local Scouting & Assignment Completion Matching
  // ---------------------------------------------------------------------------

  /// Checks whether an assignment has matching scouted data locally on this device.
  static bool isAssignmentScoutedLocally(
    ScoutingAssignment a, {
    List<ScoutHistoryEntry>? history,
    List<dynamic>? cachedMatch,
    List<dynamic>? cachedPit,
    List<dynamic>? cachedQual,
  }) {
    if (a.status == 'COMPLETED') return true;

    final type = a.assignmentType.toUpperCase();
    final eventKey = a.eventKey.trim().toLowerCase();
    final matchKey = a.matchKey?.trim().toLowerCase();
    final matchNum = a.matchNumber;
    final teamNum = a.targetTeamNumber;
    final alliance = (a.allianceColor ?? a.targetAlliance)?.trim().toUpperCase();

    // 1. Check ScoutHistoryEntry records
    if (history != null && history.isNotEmpty) {
      for (final h in history) {
        final hEvent = h.eventKey.trim().toLowerCase();
        if (eventKey.isNotEmpty && hEvent.isNotEmpty && hEvent != eventKey) {
          continue;
        }

        if (type == 'MATCH' && h.type.toLowerCase() == 'match') {
          final hMatchKey = h.matchKey?.trim().toLowerCase();
          final hMatchNum = h.matchNumber;
          final hTeam = h.teamNumber;

          // With both match keys, compare keys only: qm5, a practice 5 and a playoff 5 are different matches.
          final matchMatches = (matchKey != null && matchKey.isNotEmpty && hMatchKey != null && hMatchKey.isNotEmpty)
              ? matchKey == hMatchKey
              : (matchNum != null && hMatchNum != null && matchNum == hMatchNum);
          final teamMatches = teamNum != null && hTeam == teamNum;

          if (matchMatches && teamMatches) {
            return true;
          }
        } else if (type == 'PIT' && h.type.toLowerCase() == 'pit') {
          final hTeam = h.teamNumber;
          if (teamNum != null && hTeam == teamNum) {
            return true;
          }
        } else if (type == 'QUALITATIVE' && (h.type.toLowerCase() == 'qual' || h.type.toLowerCase() == 'qualitative')) {
          final hMatchKey = h.matchKey?.trim().toLowerCase();
          final hMatchNum = h.matchNumber;
          // With both match keys, compare keys only: qm5, a practice 5 and a playoff 5 are different matches.
          final matchMatches = (matchKey != null && matchKey.isNotEmpty && hMatchKey != null && hMatchKey.isNotEmpty)
              ? matchKey == hMatchKey
              : (matchNum != null && hMatchNum != null && matchNum == hMatchNum);

          if (matchMatches) {
            if (teamNum != null && h.teamNumber == teamNum) {
              return true;
            }
            if (alliance != null) {
              final hAlliance = (h.payload['alliance'] ?? h.payload['allianceColor'] ?? h.payload['alliance_color'])?.toString().trim().toUpperCase();
              if (hAlliance == alliance) {
                return true;
              }
            }
            if (teamNum == null && alliance == null) {
              return true;
            }
          }
        }
      }
    }

    // 2. Check cached match entries list
    if (type == 'MATCH' && cachedMatch != null && cachedMatch.isNotEmpty) {
      for (final item in cachedMatch) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final eKey = (map['eventKey'] ?? map['event_key'])?.toString().trim().toLowerCase() ?? '';
        if (eventKey.isNotEmpty && eKey.isNotEmpty && eKey != eventKey) continue;

        final mKey = (map['matchKey'] ?? map['match_key'])?.toString().trim().toLowerCase();
        final mNum = _extractInt(map, ['matchNumber', 'match_number']);
        final tNum = _extractInt(map, ['targetTeamNumber', 'teamNumber', 'team_number']);

        // With both match keys, compare keys only: qm5, a practice 5 and a playoff 5 are different matches.
        final matchMatches = (matchKey != null && matchKey.isNotEmpty && mKey != null && mKey.isNotEmpty)
            ? matchKey == mKey
            : (matchNum != null && mNum != 0 && matchNum == mNum);
        final teamMatches = teamNum != null && tNum == teamNum;
        if (matchMatches && teamMatches) return true;
      }
    }

    // 3. Check cached pit entries list
    if (type == 'PIT' && cachedPit != null && cachedPit.isNotEmpty) {
      for (final item in cachedPit) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final eKey = (map['eventKey'] ?? map['event_key'])?.toString().trim().toLowerCase() ?? '';
        if (eventKey.isNotEmpty && eKey.isNotEmpty && eKey != eventKey) continue;

        final tNum = _extractInt(map, ['targetTeamNumber', 'teamNumber', 'team_number']);
        if (teamNum != null && tNum == teamNum) return true;
      }
    }

    // 4. Check cached qual entries list
    if (type == 'QUALITATIVE' && cachedQual != null && cachedQual.isNotEmpty) {
      for (final item in cachedQual) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final eKey = (map['eventKey'] ?? map['event_key'])?.toString().trim().toLowerCase() ?? '';
        if (eventKey.isNotEmpty && eKey.isNotEmpty && eKey != eventKey) continue;

        final mKey = (map['matchKey'] ?? map['match_key'])?.toString().trim().toLowerCase();
        final mNum = _extractInt(map, ['matchNumber', 'match_number']);
        final tNum = _extractInt(map, ['targetTeamNumber', 'teamNumber', 'team_number']);
        final aColor = (map['alliance'] ?? map['allianceColor'] ?? map['alliance_color'])?.toString().trim().toUpperCase();

        // With both match keys, compare keys only: qm5, a practice 5 and a playoff 5 are different matches.
        final matchMatches = (matchKey != null && matchKey.isNotEmpty && mKey != null && mKey.isNotEmpty)
            ? matchKey == mKey
            : (matchNum != null && mNum != 0 && matchNum == mNum);

        if (matchMatches) {
          if (teamNum != null && tNum == teamNum) return true;
          if (alliance != null && aColor == alliance) return true;
          if (teamNum == null && alliance == null) return true;
        }
      }
    }

    return false;
  }

  /// Merges local scouting history and cached offline submissions with assignments,
  /// updating any assignment to COMPLETED if matching local scout data is found.
  static Future<List<ScoutingAssignment>> applyLocalScoutStatus(
    List<ScoutingAssignment> assignments, {
    String? eventKey,
  }) async {
    if (assignments.isEmpty) return assignments;
    try {
      final history = await loadAll(pruneExpired: false);
      final store = LocalStore.instance;

      List<dynamic>? cachedMatch;
      final rawMatch = await store.getString('cache_scouting') ?? await store.getString('cache_prescout_scouting');
      if (rawMatch != null && rawMatch.isNotEmpty) {
        try {
          final decoded = await LocalStore.decodeJson(rawMatch);
          if (decoded is List) cachedMatch = decoded;
          if (decoded is Map && decoded['entries'] is List) cachedMatch = decoded['entries'] as List;
        } catch (_) {}
      }

      List<dynamic>? cachedPit;
      final rawPit = await store.getString('cache_pit_scouting') ?? await store.getString('cache_prescout_pit_scouting');
      if (rawPit != null && rawPit.isNotEmpty) {
        try {
          final decoded = await LocalStore.decodeJson(rawPit);
          if (decoded is List) cachedPit = decoded;
          if (decoded is Map && decoded['entries'] is List) cachedPit = decoded['entries'] as List;
        } catch (_) {}
      }

      List<dynamic>? cachedQual;
      final rawQual = await store.getString('cache_qual_scouting') ?? await store.getString('cache_prescout_qual_scouting');
      if (rawQual != null && rawQual.isNotEmpty) {
        try {
          final decoded = await LocalStore.decodeJson(rawQual);
          if (decoded is List) cachedQual = decoded;
          if (decoded is Map && decoded['entries'] is List) cachedQual = decoded['entries'] as List;
        } catch (_) {}
      }

      return assignments.map((a) {
        if (a.status == 'COMPLETED') return a;
        if (isAssignmentScoutedLocally(
          a,
          history: history,
          cachedMatch: cachedMatch,
          cachedPit: cachedPit,
          cachedQual: cachedQual,
        )) {
          return a.copyWith(status: 'COMPLETED');
        }
        return a;
      }).toList();
    } catch (_) {
      return assignments;
    }
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
