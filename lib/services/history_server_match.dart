/// Decides whether a local scout history record is already on the server, whichever way it got there (this
/// device, another device, a scanned QR). Same rules as the website's cache manager.
library;

import '../models/scout_history_models.dart';

/// Server list ('match', 'pit' or 'qual') that holds records of this history type.
String serverKindFor(String historyType) {
  if (historyType.contains('pit')) return 'pit';
  if (historyType.contains('qual')) return 'qual';
  return 'match';
}

/// "2026mitry_qm12" and "qm12" name the same match; a bare number is a match number, not a key.
String normalizeMatchKey(Object? key) {
  if (key == null) return '';
  final s = key.toString().trim().toLowerCase();
  final i = s.lastIndexOf('_');
  final k = i >= 0 ? s.substring(i + 1) : s;
  return RegExp(r'^\d+$').hasMatch(k) ? '' : k;
}

int matchNumberOf(Object? key, Object? number) {
  final n = number is num ? number.toInt() : int.tryParse(number?.toString() ?? '');
  if (n != null && n > 0) return n;
  final raw = key?.toString().trim() ?? '';
  if (RegExp(r'^\d+$').hasMatch(raw)) return int.parse(raw);
  final m = RegExp(r'^qm(\d+)$').firstMatch(normalizeMatchKey(key));
  return m != null ? int.parse(m.group(1)!) : 0;
}

bool sameMatch(Object? aKey, Object? aNum, Object? bKey, Object? bNum) {
  final ak = normalizeMatchKey(aKey);
  final bk = normalizeMatchKey(bKey);
  if (ak.isNotEmpty && bk.isNotEmpty) return ak == bk;
  final an = matchNumberOf(aKey, aNum);
  final bn = matchNumberOf(bKey, bNum);
  if (an > 0 && bn > 0) return an == bn;
  // Only when the local record names no match at all is team + event enough.
  return ak.isEmpty && an == 0;
}

Object? _field(Map record, List<String> keys) {
  final data = record['data'] is Map ? record['data'] as Map : const {};
  for (final k in keys) {
    final v = record[k];
    if (v != null && v.toString().isNotEmpty) return v;
    final d = data[k];
    if (d != null && d.toString().isNotEmpty) return d;
  }
  return null;
}

int _teamOf(ScoutHistoryEntry local) {
  if (local.teamNumber > 0) return local.teamNumber;
  final raw = local.payload['targetTeamNumber'] ?? local.payload['teamNumber'] ?? local.payload['team_number'];
  return raw is num ? raw.toInt() : (int.tryParse(raw?.toString() ?? '') ?? 0);
}

/// True when [serverRecords] (a list from /api/scouting, /api/pit-scouting or /api/qual-scouting with
/// includePrescout=true) holds this record.
bool isHistoryEntryOnServer(ScoutHistoryEntry local, List<dynamic> serverRecords) {
  final team = _teamOf(local);
  if (team == 0) return false;
  final prescout = local.type.startsWith('prescout');
  final isPit = serverKindFor(local.type) == 'pit';
  final localEvent = local.eventKey.toLowerCase();

  return serverRecords.any((raw) {
    if (raw is! Map) return false;
    final isPrescout = raw['isPrescout'];
    if (isPrescout is bool && isPrescout != prescout) return false;

    final serverTeam = _field(raw, ['targetTeamNumber', 'teamNumber', 'team_number']);
    final serverTeamNum = serverTeam is num ? serverTeam.toInt() : int.tryParse(serverTeam?.toString() ?? '');
    if (serverTeamNum != team) return false;

    final serverEvent = (_field(raw, ['eventKey', 'event_key']) ?? '').toString().toLowerCase();
    if (serverEvent.isNotEmpty && localEvent.isNotEmpty && serverEvent != localEvent) return false;

    if (isPit) return true;
    return sameMatch(local.matchKey, local.matchNumber,
        _field(raw, ['matchKey', 'match_key']), _field(raw, ['matchNumber', 'match_number']));
  });
}
