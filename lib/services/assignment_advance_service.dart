import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment_models.dart';
import '../models/team_match_models.dart';

/// The assignment the scout should do next, and how many already-played ones were passed over.
class NextAssignment {
  final ScoutingAssignment? assignment;
  final int skippedPast;
  final int remaining;

  const NextAssignment({this.assignment, this.skippedPast = 0, this.remaining = 0});
}

/// Picks a scout's next unfinished assignment after they save an entry, so the scouting form
/// can jump straight to it. The form's selectors stay editable; this only pre-fills them.
class AssignmentAdvanceService {
  static const String _prefKey = 'obsidianscout_auto_advance_assignments';

  /// Assignments whose match started more than this long ago count as already played.
  static const Duration playedGrace = Duration(minutes: 10);

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  /// Not yet completed, skipped or missed.
  static bool isOpen(ScoutingAssignment a) => !_isDone(a);

  static bool _isDone(ScoutingAssignment a) =>
      a.status == 'COMPLETED' || a.status == 'SKIPPED' || a.status == 'MISSED';

  /// Event order: practice, then qualifications, then playoffs (same ranking as the server's
  /// MatchCanonical.compLevelRank). Unknown levels sort after playoffs.
  static const Map<String, int> _levelRank = {
    'practice': 0, 'prac': 0, 'pr': 0, 'prc': 0, 'p': 0,
    'qm': 1, 'q': 1, 'qual': 1, 'quals': 1, 'qualification': 1,
    'qf': 2, 'quarterfinal': 2, 'quarterfinals': 2,
    'sf': 3, 'semifinal': 3, 'semifinals': 3,
    'f': 4, 'final': 4, 'finals': 4,
    'ef': 5, 'einstein': 5,
    'playoff': 6, 'playoffs': 6,
  };

  static final RegExp _keySuffix = RegExp(r'^([a-z]+?)(\d+)(?:m(\d+))?$');

  /// Sortable (level, set, match) from a match key like `2026abc_qm12` or `2026abc_sf2m1`,
  /// falling back to the separate comp level / match number fields.
  static List<int> orderKey({String? matchKey, String? compLevel, int? matchNumber}) {
    String? level = compLevel;
    var set = 0;
    var match = matchNumber ?? 0;
    final suffix = (matchKey ?? '').trim().toLowerCase().split('_').last;
    final m = _keySuffix.firstMatch(suffix);
    if (m != null) {
      level = (level == null || level.isEmpty) ? m.group(1) : level;
      if (m.group(3) != null) {
        set = int.tryParse(m.group(2)!) ?? 0;
        match = matchNumber ?? int.tryParse(m.group(3)!) ?? 0;
      } else {
        match = matchNumber ?? int.tryParse(m.group(2)!) ?? 0;
      }
    }
    return [_levelRank[(level ?? 'qm').toLowerCase()] ?? 7, set, match];
  }

  static int _compare(List<int> x, List<int> y) {
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }

  static List<int> _orderOf(ScoutingAssignment a) =>
      orderKey(matchKey: a.matchKey, compLevel: a.compLevel, matchNumber: a.matchNumber);

  /// Played = the match started more than [playedGrace] ago. Only used to pass over stale
  /// assignments when an unplayed one is still ahead.
  static bool _isPlayed(ScoutingAssignment a, DateTime now) {
    final t = a.effectiveScheduledTime;
    if (t == null || t <= 0) return false;
    // Server times are epoch seconds; tolerate milliseconds too.
    final ms = t < 100000000000 ? t * 1000 : t;
    return DateTime.fromMillisecondsSinceEpoch(ms).isBefore(now.subtract(playedGrace));
  }

  /// Next unfinished assignment of [type] (`MATCH`, `PIT` or `QUALITATIVE`) after the
  /// selection just scouted, in event order (practice, quals, playoffs). Keying off the scouted
  /// match, not "first unfinished", means a skipped or swapped match doesn't send the scout
  /// backwards. "No more assignments" (a null [NextAssignment.assignment]) only ever means none
  /// are left. With [noWrap], nothing is returned when no assignment comes after the selection
  /// (instead of falling back to an earlier open one). Returns null when the scout has no
  /// assignments of this type at all.
  static NextAssignment? next(
    List<ScoutingAssignment> assignments, {
    required String type,
    List<MatchModel> matches = const [],
    String? afterMatchKey,
    int? afterMatchNumber,
    int? afterTeam,
    Set<String> justCompletedIds = const {},
    DateTime? now,
    bool noWrap = false,
  }) {
    final ofType = assignments.where((a) => a.assignmentType.toUpperCase() == type).toList();
    if (ofType.isEmpty) return null;
    final open = ofType.where((a) => !_isDone(a) && !justCompletedIds.contains(a.id)).toList();
    if (open.isEmpty) return const NextAssignment();

    if (type == 'PIT') {
      open.sort((x, y) => (x.targetTeamNumber ?? 0).compareTo(y.targetTeamNumber ?? 0));
      final after = afterTeam == null ? null : open.where((a) => (a.targetTeamNumber ?? 0) > afterTeam).firstOrNull;
      if (after == null && afterTeam != null && noWrap) return NextAssignment(remaining: open.length);
      return NextAssignment(assignment: after ?? open.first, remaining: open.length);
    }

    open.sort((x, y) => _compare(_orderOf(x), _orderOf(y)));

    var candidates = open;
    if (afterMatchKey != null || afterMatchNumber != null) {
      final known = afterMatchKey == null
          ? null
          : matches.where((m) => m.matchKey.toLowerCase() == afterMatchKey.toLowerCase()).firstOrNull;
      final from = known != null
          ? orderKey(matchKey: known.matchKey, compLevel: known.compLevel, matchNumber: known.matchNumber)
          : orderKey(matchKey: afterMatchKey, matchNumber: afterMatchNumber);
      final ahead = open.where((a) => _compare(_orderOf(a), from) >= 0).toList();
      if (ahead.isNotEmpty) {
        candidates = ahead;
      } else if (noWrap) {
        // Nothing after the selection; [remaining] counts the earlier ones still open.
        return NextAssignment(remaining: open.length);
      }
    }

    final clock = now ?? DateTime.now();
    final firstUnplayed = candidates.indexWhere((a) => !_isPlayed(a, clock));
    if (firstUnplayed >= 0) {
      return NextAssignment(assignment: candidates[firstUnplayed], skippedPast: firstUnplayed, remaining: open.length);
    }
    // Everything ahead is already played (old event, catching up from video): still go in order.
    return NextAssignment(assignment: candidates.first, remaining: open.length);
  }

  /// Short label like "QM 14 · Team 254 · Red".
  static String describe(ScoutingAssignment a) {
    final parts = <String>[];
    if (a.assignmentType.toUpperCase() != 'PIT') {
      final name = a.formattedMatchName;
      if (name.isNotEmpty) parts.add(name);
    }
    if (a.targetTeamNumber != null) parts.add('Team ${a.targetTeamNumber}');
    final color = a.allianceColor ?? a.targetAlliance;
    if (color != null && color.isNotEmpty) {
      parts.add('${color[0].toUpperCase()}${color.substring(1).toLowerCase()}');
    }
    return parts.join(' · ');
  }
}
