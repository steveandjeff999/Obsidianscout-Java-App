/// Pure helpers for the delta sync of scouting entries (`GET /api/sync/entries`, see EntrySync.kt on the server):
/// decoding the compact wire form, merging a delta into the stored list, and the server's one-entry-per-match rule.
library;

/// Expands the compact form (`cols` / `keys` / `rows`) back into entry maps.
/// Each row is `[meta values in cols order..., [data values in keys order], [indexes of real nulls]?]`.
List<Map<String, dynamic>> unpackCompact(List<dynamic> cols, List<dynamic> keys, List<dynamic> rows) {
  final colNames = cols.map((c) => c.toString()).toList();
  final keyNames = keys.map((k) => k.toString()).toList();
  return rows.map((rowRaw) {
    final row = rowRaw as List<dynamic>;
    final out = <String, dynamic>{};
    for (var i = 0; i < colNames.length; i++) {
      out[colNames[i]] = i < row.length ? row[i] : null;
    }
    final values = row.length > colNames.length && row[colNames.length] is List ? row[colNames.length] as List : const [];
    final nulls = row.length > colNames.length + 1 && row[colNames.length + 1] is List
        ? (row[colNames.length + 1] as List).map((e) => (e as num).toInt()).toSet()
        : const <int>{};
    final data = <String, dynamic>{};
    for (var i = 0; i < keyNames.length; i++) {
      final v = i < values.length ? values[i] : null;
      if (v != null) {
        data[keyNames[i]] = v;
      } else if (nulls.contains(i)) {
        data[keyNames[i]] = null;
      }
    }
    out['data'] = data;
    return out;
  }).toList();
}

/// Entries carried by a sync response, whichever form it used.
List<Map<String, dynamic>> changedEntries(Map<String, dynamic> response) {
  final entries = response['entries'];
  if (entries is List) return entries.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  return unpackCompact(
    (response['cols'] as List?) ?? const [],
    (response['keys'] as List?) ?? const [],
    (response['rows'] as List?) ?? const [],
  );
}

int _ts(dynamic value) => DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;

/// Newest first, like the server's `ORDER BY created_at DESC`.
List<Map<String, dynamic>> newestFirst(Iterable<Map<String, dynamic>> entries) {
  final list = entries.toList();
  final keyed = [for (var i = 0; i < list.length; i++) (i, _ts(list[i]['createdAt']))];
  keyed.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return [for (final k in keyed) list[k.$1]];
}

class DeltaMerge {
  /// The merged list, newest first.
  final List<Map<String, dynamic>> entries;

  /// False when the merged count differs from the server's `total`: a change was missed and a full sync is needed.
  final bool consistent;
  final int changed;
  final int deleted;

  const DeltaMerge(this.entries, {required this.consistent, required this.changed, required this.deleted});
}

/// Applies one sync response to the stored list.
DeltaMerge mergeDelta(List<dynamic> current, Map<String, dynamic> response) {
  final full = response['full'] == true;
  final byId = <String, Map<String, dynamic>>{};
  if (!full) {
    for (final e in current) {
      if (e is Map && e['id'] != null) byId[e['id'].toString()] = Map<String, dynamic>.from(e);
    }
  }
  final deleted = ((response['deleted'] as List?) ?? const []).map((e) => e.toString()).toList();
  for (final id in deleted) {
    byId.remove(id);
  }
  final changed = changedEntries(response);
  for (final e in changed) {
    final id = e['id']?.toString();
    if (id != null) byId[id] = e;
  }
  final total = response['total'];
  final consistent = full || total is! num || byId.length == total.toInt();
  return DeltaMerge(newestFirst(byId.values), consistent: consistent, changed: changed.length, deleted: deleted.length);
}

/// Same rule as the server's resolveEntriesList: one entry per match+team (event+team for pit), own team's first.
List<Map<String, dynamic>> resolveEntries(List<dynamic> list, String kind, int? ownTeam) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final raw in list) {
    if (raw is! Map) continue;
    final e = Map<String, dynamic>.from(raw);
    final team = e['targetTeamNumber'] ?? 0;
    final key = kind == 'pit' ? '${e['eventKey'] ?? ''}|$team' : '${e['matchKey'] ?? ''}|$team';
    groups.putIfAbsent(key, () => []).add(e);
  }
  return groups.values.map((g) {
    if (g.length <= 1) return g.first;
    return g.firstWhere((e) => e['ownerTeamNumber'] == ownTeam, orElse: () => g.first);
  }).toList();
}
