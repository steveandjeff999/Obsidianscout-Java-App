/// Computes `/api/analytics` and `/api/custom-analytics/dataset` on the device from stored entries, so analytics keep
/// working offline or on a slow link. A port of AnalyticsService, RecencyWeighting and
/// AnalyticsReportService.generateDataset on the server (and of the site's local-analytics.js); keep them in step.
/// `test/local_analytics_test.dart` checks it against the server's own output.
library;

import 'dart:math' as math;

// ── Value readers (kotlinx JsonPrimitive semantics) ─────────────────────────

bool _isPrimitive(Object? v) => v == null || v is String || v is num || v is bool;

/// JsonPrimitive.content. Integral doubles print like the server's JSON (5.0 stays "5.0" only if sent as 5.0).
String _content(Object? v) {
  if (v == null) return 'null';
  return v.toString();
}

final RegExp _number = RegExp(r'^[+-]?(\d+\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?|Infinity)$');

/// Kotlin/JVM String.toDoubleOrNull(): surrounding whitespace ignored, empty is null.
double? _toDoubleOrNull(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text == 'NaN') return double.nan;
  if (!_number.hasMatch(text)) return null;
  if (text.endsWith('Infinity')) return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  return double.tryParse(text);
}

double? _readNumber(Object? v, bool present) {
  if (!present || !_isPrimitive(v)) return null;
  if (v is num) return v.toDouble();
  return _toDoubleOrNull(_content(v));
}

bool? _readBoolean(Object? v, bool present) {
  if (!present || !_isPrimitive(v)) return null;
  final c = _content(v).toLowerCase();
  return c == 'true' ? true : (c == 'false' ? false : null);
}

String? _readLabel(Object? v, bool present) {
  if (!present || !_isPrimitive(v)) return null;
  return _content(v);
}

/// Config labels may arrive translated (`{en: "Auto"}`); the server works with the plain string.
String labelText(Object? label) {
  if (label is Map) {
    final en = label['en'];
    if (en is String) return en;
    return label.values.whereType<String>().firstOrNull ?? '';
  }
  return label?.toString() ?? '';
}

String _ifBlank(String text, String fallback) => text.trim().isEmpty ? fallback : text;

List<Map<String, dynamic>> _fields(Map<String, dynamic> config) =>
    ((config['fields'] as List?) ?? const []).whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList();

List<Map<String, dynamic>> _options(Map<String, dynamic> field) =>
    ((field['options'] as List?) ?? const []).whereType<Map>().map((o) => Map<String, dynamic>.from(o)).toList();

String _type(Map<String, dynamic> field) => (field['type'] ?? '').toString().toLowerCase();

double? _pointsPer(Map<String, dynamic> field) => (field['pointsPer'] as num?)?.toDouble();

Map<String, dynamic> _data(Map<String, dynamic> entry) =>
    entry['data'] is Map ? Map<String, dynamic>.from(entry['data'] as Map) : const {};

// ── Scoring ─────────────────────────────────────────────────────────────────

double fieldScore(Map<String, dynamic> field, Map<String, dynamic> data) {
  final id = field['id']?.toString() ?? '';
  final present = data.containsKey(id);
  if (!present) return 0;
  final v = data[id];
  final pointsPer = _pointsPer(field);
  switch (_type(field)) {
    case 'counter':
    case 'number':
    case 'rating':
      final value = _readNumber(v, present);
      return value == null ? 0 : (pointsPer ?? 0) * value;
    case 'checkbox':
      return (_readBoolean(v, present) ?? false) ? (pointsPer ?? 0) : 0;
    case 'select':
      final label = _readLabel(v, present);
      if (label == null) return 0;
      final option = _options(field).where((o) => o['value'] == label || labelText(o['label']) == label).firstOrNull;
      return (option?['points'] as num?)?.toDouble() ?? 0;
    default:
      return 0;
  }
}

double scoreEntry(Map<String, dynamic> config, Map<String, dynamic> entry) {
  final data = _data(entry);
  return _fields(config).fold(0.0, (sum, f) => sum + fieldScore(f, data));
}

List<double> _collectNumbers(Map<String, dynamic> widget, List<Map<String, dynamic>> entries) {
  final fieldId = widget['fieldId']?.toString();
  if (fieldId == null) return const [];
  final out = <double>[];
  for (final e in entries) {
    final data = _data(e);
    final present = data.containsKey(fieldId);
    final n = _readNumber(data[fieldId], present);
    if (n != null) {
      out.add(n);
      continue;
    }
    final b = _readBoolean(data[fieldId], present);
    if (b != null) out.add(b ? 1 : 0);
  }
  return out;
}

double _sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

List<Map<String, dynamic>> _barSeries(Map<String, dynamic> config, Map<String, dynamic> widget, List<Map<String, dynamic>> entries) {
  final fieldId = widget['fieldId']?.toString();
  if (fieldId == null) return const [];
  final field = _fields(config).where((f) => f['id'] == fieldId).firstOrNull;
  final counts = <String, int>{};
  if (field != null) {
    for (final opt in _options(field)) {
      counts[_ifBlank(labelText(opt['label']), opt['value']?.toString() ?? '')] = 0;
    }
  }
  for (final e in entries) {
    final data = _data(e);
    final raw = _readLabel(data[fieldId], data.containsKey(fieldId));
    if (raw == null) continue;
    final opt = field == null ? null : _options(field).where((o) => o['value'] == raw || labelText(o['label']) == raw).firstOrNull;
    final label = opt != null ? _ifBlank(labelText(opt['label']), opt['value']?.toString() ?? '') : raw;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final hasOptions = field != null && _options(field).isNotEmpty;
  final list = counts.entries.where((e) => hasOptions || e.value > 0).toList();
  _stableSortDesc(list, (e) => e.value);
  return [for (final e in list) {'label': e.key, 'value': e.value.toDouble()}];
}

/// Stable descending sort (Dart's List.sort isn't guaranteed stable; Kotlin's sortedByDescending is).
void _stableSortDesc<T>(List<T> list, num Function(T) key) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = key(b.$2).compareTo(key(a.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

List<Map<String, dynamic>> generateDefaultWidgets(Map<String, dynamic> config) {
  final widgets = <Map<String, dynamic>>[
    {'id': 'entryCount', 'title': 'Entries Collected', 'type': 'count', 'fieldId': null},
    {'id': 'avgScore', 'title': 'Average Score', 'type': 'score_avg', 'fieldId': null},
    {'id': 'totalScore', 'title': 'Total Points', 'type': 'score_total', 'fieldId': null},
  ];
  for (final field in _fields(config)) {
    final type = _type(field);
    if (const ['section', 'header', 'label', 'spacer'].contains(type)) continue;
    final id = field['id'];
    final title = _ifBlank(labelText(field['label']), id.toString());
    if (const ['counter', 'number', 'rating'].contains(type)) {
      widgets.add({'id': 'avg_$id', 'title': 'Avg $title', 'type': 'avg', 'fieldId': id});
      if (type == 'counter' || field['pointsPer'] != null) {
        widgets.add({'id': 'sum_$id', 'title': 'Total $title', 'type': 'sum', 'fieldId': id});
      }
    } else if (type == 'checkbox') {
      widgets.add({'id': 'rate_$id', 'title': '$title Rate', 'type': 'rate', 'fieldId': id});
    } else if (type == 'select' || type == 'radio') {
      widgets.add({'id': 'bar_$id', 'title': '$title Breakdown', 'type': 'bar', 'fieldId': id});
    }
  }
  return widgets;
}

/// `/api/analytics` response body.
Map<String, dynamic> generateAnalytics(Map<String, dynamic> config, List<Map<String, dynamic>> entries) {
  final configured = ((config['analytics'] as List?) ?? const []).whereType<Map>().map((w) => Map<String, dynamic>.from(w)).toList();
  final list = configured.isNotEmpty ? configured : generateDefaultWidgets(config);
  final widgets = list.map((widget) {
    final type = (widget['type'] ?? '').toString().toLowerCase();
    Map<String, dynamic> result(double? value, [List<Map<String, dynamic>> series = const []]) =>
        {'id': widget['id'], 'title': widget['title'], 'type': type, 'value': value, 'series': series};
    List<double> values() => _collectNumbers(widget, entries);
    switch (type) {
      case 'count':
        return result(entries.length.toDouble());
      case 'avg':
        final v = values();
        return result(v.isEmpty ? 0 : _sum(v) / v.length);
      case 'sum':
        return result(_sum(values()));
      case 'min':
        final v = values();
        return result(v.isEmpty ? 0 : v.reduce(math.min));
      case 'max':
        final v = values();
        return result(v.isEmpty ? 0 : v.reduce(math.max));
      case 'rate':
      case 'pct':
      case 'percentage':
        if (entries.isEmpty) return result(0);
        final v = values();
        return result(v.isEmpty ? 0 : (_sum(v) / entries.length) * 100);
      case 'bar':
        return result(null, _barSeries(config, widget, entries));
      case 'score_total':
        return result(_sum(entries.map((e) => scoreEntry(config, e)).toList()));
      case 'score_avg':
        return result(entries.isEmpty ? 0 : _sum(entries.map((e) => scoreEntry(config, e)).toList()) / entries.length);
      default:
        return result(0);
    }
  }).toList();
  return {'generatedAt': DateTime.now().toUtc().toIso8601String(), 'widgets': widgets, 'computedOnDevice': true};
}

List<Map<String, dynamic>> mergePrescoutEntries(
  List<Map<String, dynamic>> currentEventEntries,
  List<Map<String, dynamic>> prescoutEntries,
  String currentEventKey, {
  bool forceUsePrescout = false,
}) {
  final counts = <Object?, int>{};
  for (final e in currentEventEntries) {
    if (e['eventKey'] == currentEventKey && e['isPrescout'] != true) {
      counts[e['targetTeamNumber']] = (counts[e['targetTeamNumber']] ?? 0) + 1;
    }
  }
  final byTeam = <Object?, List<Map<String, dynamic>>>{};
  for (final e in prescoutEntries) {
    if (e['isPrescout'] != true) continue;
    byTeam.putIfAbsent(e['targetTeamNumber'], () => []).add(e);
  }
  final result = [...currentEventEntries];
  byTeam.forEach((team, list) {
    if (forceUsePrescout || (counts[team] ?? 0) < 3) result.addAll(list);
  });
  return result;
}

// ── Match keys and recency weighting ────────────────────────────────────────

String normalizeCompLevel(String raw) {
  final c = raw.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  if (c.isEmpty) return '';
  if (const ['qm', 'qual', 'qualification', 'quals', 'q', 'm', 'match', 'matches'].contains(c)) return 'qm';
  if (const ['qf', 'quarterfinal', 'quarterfinals'].contains(c)) return 'qf';
  if (const ['sf', 'semifinal', 'semifinals'].contains(c)) return 'sf';
  if (const ['f', 'final', 'finals'].contains(c)) return 'f';
  if (const ['ef', 'einstein'].contains(c)) return 'ef';
  if (const ['practice', 'prac', 'pr', 'prc', 'pm'].contains(c)) return 'practice';
  if (c == 'playoff' || c == 'playoffs') return 'playoff';
  return c.length > 16 ? c.substring(0, 16) : c;
}

int compLevelRank(String compLevel) =>
    const {'practice': 0, 'qm': 1, 'qf': 2, 'sf': 3, 'f': 4, 'ef': 5, 'playoff': 6}[normalizeCompLevel(compLevel)] ?? 7;

typedef MatchIdentity = ({String eventKey, String compLevel, int setNumber, int matchNumber});

String _toMatchKey(MatchIdentity id) => id.compLevel == 'qm' || id.compLevel == 'practice'
    ? '${id.eventKey}_${id.compLevel}${id.matchNumber}'
    : '${id.eventKey}_${id.compLevel}${id.setNumber}m${id.matchNumber}';

MatchIdentity? parseTbaMatchKey(String key) {
  final cut = key.lastIndexOf('_');
  final eventKey = cut >= 0 ? key.substring(0, cut).toLowerCase() : '';
  if (eventKey.trim().isEmpty) return null;
  final m = RegExp(r'^([a-z]+)(\d+)(?:m(\d+))?$', caseSensitive: false).firstMatch(key.substring(cut + 1));
  if (m == null) return null;
  final compLevel = normalizeCompLevel(m.group(1)!);
  final second = m.group(3);
  return second != null && second.isNotEmpty
      ? (eventKey: eventKey, compLevel: compLevel, setNumber: int.tryParse(m.group(2)!) ?? 1, matchNumber: int.tryParse(second) ?? 1)
      : (eventKey: eventKey, compLevel: compLevel, setNumber: 1, matchNumber: int.tryParse(m.group(2)!) ?? 1);
}

MatchIdentity? parseLegacyManualKey(String key) {
  final m = RegExp(r'^(.+)_([a-z]+)_s(\d+)_m(\d+)$', caseSensitive: false).firstMatch(key.trim());
  if (m == null) return null;
  final setNumber = math.max(int.tryParse(m.group(3)!) ?? 1, 1);
  var compLevel = normalizeCompLevel(m.group(2)!);
  if (compLevel == 'playoff') {
    compLevel = setNumber == 1 ? 'qf' : (setNumber == 2 ? 'sf' : (setNumber == 3 ? 'f' : 'playoff'));
  }
  return (eventKey: m.group(1)!.toLowerCase(), compLevel: compLevel, setNumber: setNumber, matchNumber: math.max(int.tryParse(m.group(4)!) ?? 1, 1));
}

String _matchId(Map<String, dynamic> e, int index) {
  final event = (e['eventKey'] ?? '').toString().toLowerCase();
  final key = e['matchKey']?.toString().trim().toLowerCase() ?? '';
  if (key.isNotEmpty) {
    final legacy = parseLegacyManualKey(key);
    return '$event|${legacy != null ? _toMatchKey(legacy) : key}';
  }
  if (e['matchNumber'] != null) return '$event|#${e['matchNumber']}';
  final id = e['id']?.toString() ?? '';
  return 'entry|${id.isNotEmpty ? id : index}';
}

Map<String, dynamic> _normalizeRecency(Map<String, dynamic>? raw) {
  final s = raw ?? const {};
  double num0(Object? v, double d) => v is num && v.isFinite ? v.toDouble() : d;
  return {
    'enabled': s['enabled'] == true,
    'mode': s['mode'] == 'lastN' ? 'lastN' : 'exponential',
    'halfLifeMatches': num0(s['halfLifeMatches'], 4).clamp(1, 20).toDouble(),
    'windowSize': num0(s['windowSize'], 6).truncate().clamp(1, 30),
    'minMatches': num0(s['minMatches'], 4).truncate().clamp(1, 15),
    'prescoutWeight': num0(s['prescoutWeight'], 0.5).clamp(0, 1).toDouble(),
  };
}

List<double> recencyWeights(List<Map<String, dynamic>> entries, Map<String, dynamic>? rawSettings) {
  final settings = _normalizeRecency(rawSettings);
  final eventMatches = <String>{};
  for (var i = 0; i < entries.length; i++) {
    if (entries[i]['isPrescout'] != true) eventMatches.add(_matchId(entries[i], i));
  }
  if (!(settings['enabled'] as bool && eventMatches.length >= (settings['minMatches'] as int))) {
    return List<double>.filled(entries.length, 1);
  }
  final createdAt = entries.map((e) => DateTime.tryParse(e['createdAt']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0).toList();
  final firstSeen = <String, int>{};
  for (var i = 0; i < entries.length; i++) {
    final k = (entries[i]['eventKey'] ?? '').toString().toLowerCase();
    firstSeen[k] = math.min(firstSeen[k] ?? createdAt[i], createdAt[i]);
  }
  final ids = [for (var i = 0; i < entries.length; i++) _matchId(entries[i], i)];
  final groups = <String, List<int>>{};
  for (var i = 0; i < ids.length; i++) {
    groups.putIfAbsent(ids[i], () => []).add(i);
  }
  final orders = groups.entries.map((g) {
    final e = entries[g.value.first];
    final key = e['matchKey']?.toString();
    final identity = key != null && key.trim().isNotEmpty ? (parseLegacyManualKey(key) ?? parseTbaMatchKey(key)) : null;
    final hasNumber = e['matchNumber'] != null;
    return (
      id: g.key,
      prescoutLast: e['isPrescout'] == true ? 0 : 1,
      eventFirstSeen: firstSeen[(e['eventKey'] ?? '').toString().toLowerCase()] ?? 0,
      compRank: identity != null ? compLevelRank(identity.compLevel) : (hasNumber ? 1 : -1),
      setNumber: identity?.setNumber ?? 1,
      matchNumber: identity?.matchNumber ?? (hasNumber ? (e['matchNumber'] as num).toInt() : 0),
      createdAt: g.value.map((i) => createdAt[i]).reduce(math.min),
      seq: groups.keys.toList().indexOf(g.key),
    );
  }).toList();
  orders.sort((a, b) {
    for (final c in [
      a.prescoutLast.compareTo(b.prescoutLast),
      a.eventFirstSeen.compareTo(b.eventFirstSeen),
      a.compRank.compareTo(b.compRank),
      a.setNumber.compareTo(b.setNumber),
      a.matchNumber.compareTo(b.matchNumber),
      a.createdAt.compareTo(b.createdAt),
      a.seq.compareTo(b.seq),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  });
  final newestFirst = orders.reversed.toList();
  final ageById = {for (var age = 0; age < newestFirst.length; age++) newestFirst[age].id: age};
  return [
    for (var i = 0; i < entries.length; i++)
      () {
        final age = ageById[ids[i]]!;
        final base = settings['mode'] == 'lastN'
            ? (age < (settings['windowSize'] as int) ? 1.0 : 0.0)
            : math.pow(0.5, age / (settings['halfLifeMatches'] as double)).toDouble();
        return entries[i]['isPrescout'] == true ? base * (settings['prescoutWeight'] as double) : base;
      }(),
  ];
}

// ── Custom-analytics dataset ────────────────────────────────────────────────

String _mapFieldType(Object? raw) {
  final t = (raw ?? '').toString().toLowerCase();
  if (const ['counter', 'number', 'rating', 'timer', 'slider'].contains(t)) return 'number';
  if (const ['checkbox', 'toggle', 'switch'].contains(t)) return 'boolean';
  return 'string';
}

double _scoreSection(Map<String, dynamic> config, Map<String, dynamic> entry, List<String> subs) {
  final data = _data(entry);
  return _fields(config).where((f) {
    final phase = f['phase']?.toString();
    final key = (phase != null && phase.trim().isNotEmpty ? phase : f['id'].toString()).toLowerCase();
    return subs.any((s) => key.contains(s.toLowerCase()));
  }).fold(0.0, (sum, f) => sum + fieldScore(f, data));
}

Map<String, dynamic> _meta(String id, String label, String type, String source,
        [String section = 'General', double? pointsPer, List<String> options = const []]) =>
    {'id': id, 'label': label, 'type': type, 'source': source, 'section': section, 'pointsPer': pointsPer, 'options': options};

/// `/api/custom-analytics/dataset` body. Entry lists are the resolved (one per match+team) lists the server would use.
Map<String, dynamic> buildDataset({
  required Map<String, dynamic> matchConfig,
  required Map<String, dynamic> pitConfig,
  required Map<String, dynamic> qualConfig,
  required List<Map<String, dynamic>> matchEntries,
  required List<Map<String, dynamic>> pitEntries,
  required List<Map<String, dynamic>> qualEntries,
  required List<Map<String, dynamic>> teams,
  String? eventKeyFilter,
  String program = 'FRC',
}) {
  final filter = eventKeyFilter != null && eventKeyFilter.isNotEmpty;
  List<Map<String, dynamic>> byEvent(List<Map<String, dynamic>> l) => filter ? l.where((e) => e['eventKey'] == eventKeyFilter).toList() : l;
  final matches = byEvent(matchEntries), pits = byEvent(pitEntries), quals = byEvent(qualEntries);

  final seen = <Object?>{};
  final teamsList = <Map<String, dynamic>>[];
  for (final t in teams) {
    if (filter && t['eventKey'] != eventKeyFilter) continue;
    if (!seen.add(t['teamNumber'])) continue;
    teamsList.add({
      'teamNumber': t['teamNumber'],
      'name': t['name'],
      'nickname': t['nickname'],
      'city': t['city'],
      'state': t['state'],
      'opr': t['opr'],
      'epa': t['epa'],
      'exp': t['exp'],
    });
  }

  final fields = <Map<String, dynamic>>[
    _meta('teamNumber', 'Team Number', 'number', 'system', 'Identification'),
    _meta('matchNumber', 'Match Number', 'number', 'system', 'Identification'),
    _meta('matchKey', 'Match Key', 'string', 'system', 'Identification'),
    _meta('eventKey', 'Event Key', 'string', 'system', 'Identification'),
    _meta('isPrescout', 'Is Prescout', 'boolean', 'system', 'Identification'),
    _meta('createdAt', 'Recorded At', 'string', 'system', 'Metadata'),
  ];
  List<String> optionLabels(Map<String, dynamic> f) => _options(f).map((o) => labelText(o['label'])).toList();
  for (final f in _fields(matchConfig)) {
    final phase = f['phase']?.toString() ?? 'Match Scouting';
    final pp = _pointsPer(f);
    fields.add(_meta('match_${f['id']}', '$phase: ${labelText(f['label'])}', _mapFieldType(f['type']), 'match', phase, pp, optionLabels(f)));
    if (pp != null && pp != 0) {
      fields.add(_meta('calc_pts_${f['id']}', '$phase: ${labelText(f['label'])} Points', 'number', 'calculated', 'Scoring Elements ($phase)', pp));
    }
  }
  final isFtc = program.toUpperCase() == 'FTC';
  fields.add(_meta('calc_total_score', 'Total Score', 'number', 'calculated', 'Overall Scores'));
  fields.add(_meta('calc_auto_score', 'Auto Score', 'number', 'calculated', 'Phase Scores'));
  fields.add(_meta('calc_teleop_score', 'Teleop Score', 'number', 'calculated', 'Phase Scores'));
  fields.add(_meta('calc_endgame_score', 'Endgame Score', 'number', 'calculated', 'Phase Scores'));
  if (!isFtc) {
    fields.add(_meta('statbotics_epa', 'EPA', 'number', 'calculated', 'Statistics'));
    fields.add(_meta('match13_exp', 'EXP', 'number', 'calculated', 'Statistics'));
  }
  fields.add(_meta('tba_opr', isFtc ? 'FTC Scout OPR' : 'OPR', 'number', 'calculated', 'Statistics'));
  for (final f in _fields(pitConfig)) {
    final phase = f['phase']?.toString() ?? 'Pit Scouting';
    fields.add(_meta('pit_${f['id']}', 'Pit: ${labelText(f['label'])}', _mapFieldType(f['type']), 'pit', 'Pit: $phase', null, optionLabels(f)));
  }
  for (final f in _fields(qualConfig)) {
    final phase = f['phase']?.toString() ?? 'Qualitative';
    fields.add(_meta('qual_${f['id']}', 'Qual: ${labelText(f['label'])}', _mapFieldType(f['type']), 'qual', 'Qual: $phase', _pointsPer(f), optionLabels(f)));
  }

  Map<Object?, Object?> teamMap(String key) => {for (final t in teamsList) t['teamNumber']: t[key]};
  final opr = teamMap('opr'), epa = teamMap('epa'), exp = teamMap('exp');
  final configFields = _fields(matchConfig);

  final flatMatches = matches.map((e) {
    final t = e['targetTeamNumber'] ?? 0;
    final out = <String, dynamic>{
      'id': e['id'],
      'teamNumber': t,
      'matchNumber': e['matchNumber'] ?? 0,
      'matchKey': e['matchKey'] ?? '',
      'eventKey': e['eventKey'] ?? '',
      'isPrescout': e['isPrescout'] == true,
      'createdAt': e['createdAt'],
      'calc_total_score': scoreEntry(matchConfig, e),
      'calc_auto_score': _scoreSection(matchConfig, e, const ['auto']),
      'calc_teleop_score': _scoreSection(matchConfig, e, const ['teleop']),
      'calc_endgame_score': _scoreSection(matchConfig, e, const ['endgame', 'climb']),
      'statbotics_epa': epa[t] ?? 0.0,
      'match13_exp': exp[t] ?? 0.0,
      'tba_opr': opr[t] ?? 0.0,
      'hasDiscrepancy': e['hasDiscrepancy'] == true,
    };
    _data(e).forEach((k, v) {
      out['match_$k'] = v;
      final field = configFields.where((f) => f['id'] == k).firstOrNull;
      final pp = field == null ? null : _pointsPer(field);
      if (pp != null) {
        final c = _isPrimitive(v) ? _content(v) : null;
        final n = c == null ? null : (v is num ? v.toDouble() : _toDoubleOrNull(c));
        out['calc_pts_$k'] = n != null ? n * pp : (c == 'true' ? pp : 0.0);
      }
    });
    return out;
  }).toList();
  final flatPits = pits.map((e) {
    final out = <String, dynamic>{
      'id': e['id'],
      'teamNumber': e['targetTeamNumber'] ?? 0,
      'eventKey': e['eventKey'] ?? '',
      'isPrescout': e['isPrescout'] == true,
      'createdAt': e['createdAt'],
    };
    _data(e).forEach((k, v) => out['pit_$k'] = v);
    return out;
  }).toList();
  final flatQuals = quals.map((e) {
    final out = <String, dynamic>{
      'id': e['id'],
      'teamNumber': e['targetTeamNumber'] ?? 0,
      'matchNumber': e['matchNumber'] ?? 0,
      'matchKey': e['matchKey'] ?? '',
      'eventKey': e['eventKey'] ?? '',
      'isPrescout': e['isPrescout'] == true,
      'createdAt': e['createdAt'],
    };
    _data(e).forEach((k, v) => out['qual_$k'] = v);
    return out;
  }).toList();

  final uniqueTeams = {...flatMatches.map((m) => m['teamNumber']), ...teamsList.map((t) => t['teamNumber'])};
  return {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'eventKey': filter ? eventKeyFilter : null,
    'fields': fields,
    'matchEntries': flatMatches,
    'pitEntries': flatPits,
    'qualEntries': flatQuals,
    'teams': teamsList,
    'totalMatches': flatMatches.length,
    'totalTeams': uniqueTeams.length,
    'computedOnDevice': true,
  };
}
