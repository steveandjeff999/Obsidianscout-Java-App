/// Battery rotation for the drive team's Battery Tracker and Match Checklist.
///
/// The server only stores what people enter: the batteries (inventory doc) and, per event, the skips / pins /
/// batteries actually used (plan doc). The match-by-match schedule is worked out here from those docs plus
/// our match list. Same rules as the website's static/js/services/battery-rotation.js; both are checked
/// against test/fixtures/battery-rotation-cases.json.
///
/// Inventory doc: {batteries: {id: {name, type: "match"|"pit", order, retired, notes, createdAt}}}
/// Plan doc:      {matches: {matchKey: {skipped: {id: {by, at}}, pinned, used}}, startAt, autoMarkUsed}
///
/// Each match gets the battery recorded as `used` (history never changes), else its pinned battery (unless
/// skipped), else the next battery in the rotation after the previous match's battery that isn't skipped
/// for it. The rotation carries on from whichever battery the match got.
library;

class Battery {
  final String id;
  final String name;
  final String type; // "match" | "pit"
  final num order;
  final bool retired;
  final String notes;
  final num createdAt;

  const Battery({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    required this.retired,
    required this.notes,
    required this.createdAt,
  });

  bool get isPit => type == 'pit';

  /// Name shown to people (falls back to the id for unnamed batteries).
  String get displayName => name.trim().isEmpty ? id : name.trim();
}

/// The battery a match needs.
class BatterySlot {
  final String? batteryId;
  final String source; // "used" | "pinned" | "auto" | "none"
  final List<String> skipped;

  const BatterySlot(this.batteryId, this.source, this.skipped);
}

class BatteryRotation {
  BatteryRotation._();

  static Map<String, dynamic>? _map(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static final _chunk = RegExp(r'\d+|\D+');
  static final _digits = RegExp(r'^\d');

  /// "B2" before "B10"; otherwise plain code-unit order, the same as the website.
  static int naturalCompare(String a, String b) {
    final ca = _chunk.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
    final cb = _chunk.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
    final n = ca.length < cb.length ? ca.length : cb.length;
    for (var i = 0; i < n; i++) {
      final x = ca[i], y = cb[i];
      if (_digits.hasMatch(x) && _digits.hasMatch(y)) {
        final d = num.parse(x).compareTo(num.parse(y));
        if (d != 0) return d;
      } else if (x != y) {
        return x.compareTo(y) < 0 ? -1 : 1;
      }
    }
    return ca.length - cb.length;
  }

  static String normalizeCompLevel(String level) {
    final compact = level.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return switch (compact) {
      'p' || 'pr' || 'pm' || 'prac' || 'prc' || 'practice' || 'practicematch' => 'practice',
      'q' || 'qm' || 'qual' || 'quals' || 'qualification' || 'qualificationmatch' || 'm' || 'match' || 'matches' => 'qm',
      'qf' || 'quarterfinal' || 'quarterfinals' => 'qf',
      'sf' || 'semifinal' || 'semifinals' => 'sf',
      'f' || 'final' || 'finals' => 'f',
      'ef' || 'einstein' || 'eighthfinal' || 'eighthfinals' => 'ef',
      'po' || 'playoff' || 'playoffs' || 'playoffmatch' => 'playoff',
      _ => compact,
    };
  }

  static final _legacyKeyRe = RegExp(r'_([a-z]+)_s(\d+)_m(\d+)$', caseSensitive: false);
  static final _tbaSuffixRe = RegExp(r'^([a-z]+)(\d+)(?:m(\d+))?$', caseSensitive: false);
  static final _customMatchRe = RegExp(
    r'^(practice|prac|pr|pm|p|qualification|quals|qual|qm|q|quarterfinals|quarterfinal|qf|semifinals|semifinal|sf|finals|final|f|einstein|ef|playoffs|playoff|po)(?:\s+match)?(?:[\s#:-]+(\d+)(?:[\s/-]+(\d+))?)?$',
    caseSensitive: false,
  );

  static ({String compLevel, int setNumber, int matchNumber}) _parseMatchKey(String matchKey) {
    final key = matchKey.trim();
    if (key.isEmpty) return (compLevel: '', setNumber: 1, matchNumber: 0);

    final legacy = _legacyKeyRe.firstMatch(key);
    if (legacy != null) {
      return (
        compLevel: normalizeCompLevel(legacy.group(1)!),
        setNumber: int.tryParse(legacy.group(2)!) ?? 1,
        matchNumber: int.tryParse(legacy.group(3)!) ?? 0,
      );
    }

    if (key.toLowerCase().startsWith('custom_')) {
      final customText = key.substring(7).replaceAll('_', ' ').trim();
      final customMatch = _customMatchRe.firstMatch(customText);
      if (customMatch != null) {
        final compLevel = normalizeCompLevel(customMatch.group(1)!);
        final hasSetAndMatch = customMatch.group(3) != null;
        return (
          compLevel: compLevel,
          setNumber: hasSetAndMatch ? (int.tryParse(customMatch.group(2)!) ?? 1) : 1,
          matchNumber: hasSetAndMatch
              ? (int.tryParse(customMatch.group(3)!) ?? 0)
              : (int.tryParse(customMatch.group(2) ?? '') ?? 0),
        );
      }
      return (compLevel: '', setNumber: 1, matchNumber: 0);
    }

    final suffix = key.contains('_') ? key.substring(key.lastIndexOf('_') + 1) : key;
    final tba = _tbaSuffixRe.firstMatch(suffix);
    if (tba != null) {
      final compLevel = normalizeCompLevel(tba.group(1)!);
      final hasSetAndMatch = tba.group(3) != null;
      return (
        compLevel: compLevel,
        setNumber: hasSetAndMatch ? (int.tryParse(tba.group(2)!) ?? 1) : 1,
        matchNumber: hasSetAndMatch ? (int.tryParse(tba.group(3)!) ?? 0) : (int.tryParse(tba.group(2)!) ?? 0),
      );
    }

    return (compLevel: '', setNumber: 1, matchNumber: 0);
  }

  static int _levelRank(String level, [String matchKey = '']) {
    final parsed = _parseMatchKey(matchKey);
    var norm = normalizeCompLevel(level);
    if (norm.isEmpty ||
        (norm == 'playoff' && parsed.compLevel.isNotEmpty && parsed.compLevel != 'playoff') ||
        (norm == 'qm' && parsed.compLevel.isNotEmpty && parsed.compLevel != 'qm')) {
      norm = parsed.compLevel.isNotEmpty ? parsed.compLevel : norm;
    }
    return switch (norm) {
      'practice' => 0,
      'qm' => 1,
      'qf' => 2,
      'sf' => 3,
      'f' => 4,
      'ef' => 5,
      'playoff' => 6,
      _ => 7,
    };
  }

  /// Playoff set number from a match key (`..._sf2m1`, `..._sf_s2_m1`); 1 otherwise.
  static int setNumberOf(String matchKey) => _parseMatchKey(matchKey).setNumber;

  /// Match number from a match key (`..._sf2m1` -> 1, `..._qm10` -> 10); 0 otherwise.
  static int matchNumberOf(String matchKey) => _parseMatchKey(matchKey).matchNumber;

  /// Practice, then qualifications, then playoffs (QF, SF, F); by set and match number within each, then key.
  /// Same order as the website's ObsidianMatchUtils.compareMatches, so both pick the same battery per match.
  static int compareMatchOrder(String levelA, int? numberA, String keyA, String levelB, int? numberB, String keyB) {
    final byLevel = _levelRank(levelA, keyA) - _levelRank(levelB, keyB);
    if (byLevel != 0) return byLevel;
    final bySet = setNumberOf(keyA) - setNumberOf(keyB);
    if (bySet != 0) return bySet;
    final numA = (numberA != null && numberA > 0) ? numberA : matchNumberOf(keyA);
    final numB = (numberB != null && numberB > 0) ? numberB : matchNumberOf(keyB);
    final byNumber = numA - numB;
    if (byNumber != 0) return byNumber;
    return keyA.compareTo(keyB);
  }

  /// Every battery in the inventory, sorted by `order` then name.
  static List<Battery> batteriesOf(Map<String, dynamic>? inventory) {
    final map = _map(inventory?['batteries']) ?? const <String, dynamic>{};
    final list = <Battery>[];
    map.forEach((id, raw) {
      final b = _map(raw);
      if (b == null) return;
      list.add(Battery(
        id: id,
        name: b['name'] is String ? b['name'] as String : '',
        type: b['type'] == 'pit' ? 'pit' : 'match',
        order: b['order'] is num && (b['order'] as num).isFinite ? b['order'] as num : 0,
        retired: b['retired'] == true,
        notes: b['notes'] is String ? b['notes'] as String : '',
        createdAt: b['createdAt'] is num ? b['createdAt'] as num : 0,
      ));
    });
    list.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      final byName = naturalCompare(a.name, b.name);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  /// The batteries that take turns in matches.
  static List<Battery> rotationOf(Map<String, dynamic>? inventory) =>
      batteriesOf(inventory).where((b) => !b.isPit && !b.retired).toList();

  static Map<String, dynamic> _entry(Map<String, dynamic>? plan, String matchKey) =>
      _map(_map(plan?['matches'])?[matchKey]) ?? const <String, dynamic>{};

  static List<String> _skipped(Map<String, dynamic> entry) => _map(entry['skipped'])?.keys.toList() ?? const [];

  /// The battery for each of [matchKeys] (our matches, already in play order).
  static Map<String, BatterySlot> computeSchedule(
    Map<String, dynamic>? inventory,
    Map<String, dynamic>? plan,
    List<String> matchKeys,
  ) {
    final all = {for (final b in batteriesOf(inventory)) b.id: b};
    final rotation = rotationOf(inventory);
    final index = {for (var i = 0; i < rotation.length; i++) rotation[i].id: i};
    var pointer = index[plan?['startAt']] ?? 0;
    final result = <String, BatterySlot>{};

    for (final matchKey in matchKeys) {
      final entry = _entry(plan, matchKey);
      final skipped = _skipped(entry);
      final skip = skipped.toSet();
      String? batteryId;
      var source = 'none';
      final used = entry['used'];
      final pinned = entry['pinned'];

      if (used is String && all.containsKey(used)) {
        batteryId = used;
        source = 'used';
      } else if (pinned is String && all.containsKey(pinned) && !all[pinned]!.retired && !skip.contains(pinned)) {
        batteryId = pinned;
        source = 'pinned';
      } else {
        for (var step = 0; step < rotation.length; step++) {
          final candidate = rotation[(pointer + step) % rotation.length];
          if (!skip.contains(candidate.id)) {
            batteryId = candidate.id;
            source = 'auto';
            break;
          }
        }
      }

      if (batteryId != null && index.containsKey(batteryId)) pointer = (index[batteryId]! + 1) % rotation.length;
      result[matchKey] = BatterySlot(batteryId, source, skipped);
    }
    return result;
  }

  // ── Plan edits (mutate the doc in place) ───────────────────────────────────

  static Map<String, dynamic> _ensureEntry(Map<String, dynamic> plan, String matchKey) {
    final matches = _map(plan['matches']) ?? <String, dynamic>{};
    plan['matches'] = matches;
    final entry = _map(matches[matchKey]) ?? <String, dynamic>{};
    matches[matchKey] = entry;
    return entry;
  }

  static void _tidy(Map<String, dynamic> plan, String matchKey) {
    final matches = _map(plan['matches']);
    final e = _map(matches?[matchKey]);
    if (matches == null || e == null) return;
    final skipped = _map(e['skipped']);
    if (skipped != null && skipped.isEmpty) e.remove('skipped');
    if (e.isEmpty) matches.remove(matchKey);
  }

  /// Skips [batteryId] for one match; the next battery in the rotation takes its place.
  static void skip(Map<String, dynamic> plan, String matchKey, String batteryId, String by) {
    final e = _ensureEntry(plan, matchKey);
    final skipped = _map(e['skipped']) ?? <String, dynamic>{};
    skipped[batteryId] = {'by': by, 'at': DateTime.now().millisecondsSinceEpoch};
    e['skipped'] = skipped;
    if (e['pinned'] == batteryId) e.remove('pinned');
    if (e['used'] == batteryId) e.remove('used');
  }

  /// Clears every skip for a match.
  static void clearSkips(Map<String, dynamic> plan, String matchKey) {
    _ensureEntry(plan, matchKey).remove('skipped');
    _tidy(plan, matchKey);
  }

  /// Pins a battery to a match (null/empty un-pins).
  static void pin(Map<String, dynamic> plan, String matchKey, String? batteryId) {
    final e = _ensureEntry(plan, matchKey);
    if (batteryId != null && batteryId.isNotEmpty) {
      e['pinned'] = batteryId;
      _map(e['skipped'])?.remove(batteryId);
    } else {
      e.remove('pinned');
    }
    _tidy(plan, matchKey);
  }

  /// Records which battery ran in a match, freezing it (null/empty un-freezes).
  static void markUsed(Map<String, dynamic> plan, String matchKey, String? batteryId) {
    final e = _ensureEntry(plan, matchKey);
    if (batteryId != null && batteryId.isNotEmpty) {
      e['used'] = batteryId;
    } else {
      e.remove('used');
    }
    _tidy(plan, matchKey);
  }

  static String usedOf(Map<String, dynamic>? plan, String matchKey) {
    final used = _entry(plan, matchKey)['used'];
    return used is String ? used : '';
  }

  static String pinnedOf(Map<String, dynamic>? plan, String matchKey) {
    final pinned = _entry(plan, matchKey)['pinned'];
    return pinned is String ? pinned : '';
  }

  /// Matches each battery has run at this event (from `used`), in match order.
  static Map<String, List<String>> usageByBattery(Map<String, dynamic>? plan, List<String> matchKeys) {
    final out = <String, List<String>>{};
    for (final k in matchKeys) {
      final id = usedOf(plan, k);
      if (id.isNotEmpty) out.putIfAbsent(id, () => []).add(k);
    }
    return out;
  }

  /// Whether matches finished on the checklist record their battery automatically (default on).
  static bool autoMarkUsed(Map<String, dynamic>? plan) => plan?['autoMarkUsed'] != false;
}
