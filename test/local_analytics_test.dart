import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/entry_sync.dart';
import 'package:obsidianscout_app/services/local_analytics.dart';

/// Replays the server's own analytics output (written by LocalAnalyticsVectorsTest on the server and copied to
/// test/fixtures/local-analytics-cases.json) against the on-device port, plus the delta-merge rules.
void main() {
  final cases = jsonDecode(File('test/fixtures/local-analytics-cases.json').readAsStringSync()) as Map<String, dynamic>;
  final config = Map<String, dynamic>.from(cases['config'] as Map);
  final customConfig = Map<String, dynamic>.from(cases['customConfig'] as Map);
  final entries = (cases['entries'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final expected = cases['expected'] as Map<String, dynamic>;
  final team1678 = entries.where((e) => e['targetTeamNumber'] == 1678).toList();

  void close(num a, num b) => expect((a - b).abs() < 1e-9, isTrue, reason: '$a != $b');

  /// Server JSON writes every number as a double (3.0); compare widgets numerically.
  void sameWidgets(List<dynamic> actual, List<dynamic> wanted) {
    expect(actual.length, wanted.length);
    for (var i = 0; i < actual.length; i++) {
      final a = actual[i] as Map, w = wanted[i] as Map;
      expect(a['id'], w['id']);
      expect(a['title'], w['title']);
      expect(a['type'], w['type']);
      if (w['value'] == null) {
        expect(a['value'], isNull);
      } else {
        close(a['value'] as num, w['value'] as num);
      }
      final as = a['series'] as List, ws = w['series'] as List;
      expect(as.length, ws.length, reason: '${w['id']} series');
      for (var j = 0; j < as.length; j++) {
        expect(as[j]['label'], ws[j]['label']);
        close(as[j]['value'] as num, ws[j]['value'] as num);
      }
    }
  }

  test('entry scores match the server', () {
    final scores = expected['scores'] as Map<String, dynamic>;
    for (final e in entries) {
      close(scoreEntry(config, e), scores[e['id']] as num);
    }
  });

  test('default widgets match the server', () {
    sameWidgets(generateAnalytics(config, entries)['widgets'] as List, expected['defaultWidgets'] as List);
  });

  test('configured widgets match the server', () {
    sameWidgets(generateAnalytics(customConfig, team1678)['widgets'] as List, expected['customWidgets'] as List);
    sameWidgets(generateAnalytics(customConfig, const [])['widgets'] as List, expected['emptyWidgets'] as List);
  });

  test('prescout merge matches the server', () {
    final merged = mergePrescoutEntries(
      entries.where((e) => e['isPrescout'] != true).toList(),
      entries.where((e) => e['isPrescout'] == true).toList(),
      '2026test',
    );
    expect(merged.map((e) => e['id']).toList(), expected['mergedIds']);
  });

  test('recency weights match the server', () {
    for (final c in expected['recency'] as List) {
      final weights = recencyWeights(team1678, Map<String, dynamic>.from(c['settings'] as Map));
      final want = (c['weights'] as List).cast<num>();
      expect(weights.length, want.length, reason: c['name'] as String);
      for (var i = 0; i < weights.length; i++) {
        close(weights[i], want[i]);
      }
    }
  });

  test('dataset flattens entries like the server', () {
    final ds = buildDataset(
      matchConfig: config,
      pitConfig: const {'fields': []},
      qualConfig: const {'fields': []},
      matchEntries: entries.take(2).toList(),
      pitEntries: const [],
      qualEntries: const [],
      teams: const [
        {'eventKey': '2026test', 'teamNumber': 1678, 'opr': 50.0}
      ],
    );
    final first = (ds['matchEntries'] as List).first as Map;
    expect(first['match_auto_coral'], 3);
    expect(first['calc_pts_auto_coral'], 9.0);
    expect(first['calc_pts_leave'], 2.0);
    expect(first['tba_opr'], 50.0);
    expect(ds['totalTeams'], 1);
  });

  group('delta sync', () {
    test('compact rows decode to the server records', () {
      final packed = expected['packed'] as Map<String, dynamic>;
      final cols = (packed['cols'] as List).cast<String>();
      final decoded = unpackCompact(cols, packed['keys'] as List, packed['rows'] as List);
      for (var i = 0; i < entries.length; i++) {
        final want = {...entries[i]};
        for (final c in cols) {
          want.putIfAbsent(c, () => null);
        }
        expect(decoded[i], want);
      }
    });

    test('a delta updates, adds and removes; a count mismatch asks for a full sync', () {
      final current = [
        {'id': 'a', 'createdAt': '2026-01-01T00:00:00Z', 'data': {'x': 1}},
        {'id': 'b', 'createdAt': '2026-01-02T00:00:00Z', 'data': {'x': 2}},
      ];
      final merged = mergeDelta(current, {
        'full': false,
        'total': 2,
        'deleted': ['a'],
        'entries': [
          {'id': 'b', 'createdAt': '2026-01-02T00:00:00Z', 'data': {'x': 3}},
          {'id': 'c', 'createdAt': '2026-01-03T00:00:00Z', 'data': {'x': 4}},
        ],
      });
      expect(merged.consistent, isTrue);
      expect(merged.entries.map((e) => e['id']), ['c', 'b'], reason: 'newest first');
      expect(merged.entries.last['data'], {'x': 3});

      expect(mergeDelta(current, {'full': false, 'total': 5, 'deleted': [], 'entries': []}).consistent, isFalse);
      final full = mergeDelta(current, {'full': true, 'total': 1, 'deleted': [], 'entries': [{'id': 'z', 'createdAt': ''}]});
      expect(full.entries.map((e) => e['id']), ['z'], reason: 'a full response replaces everything');
    });

    test('lists are de-duplicated per match and team, own team first', () {
      final list = [
        {'id': 'x', 'matchKey': 'm1', 'targetTeamNumber': 1, 'ownerTeamNumber': 9999},
        {'id': 'y', 'matchKey': 'm1', 'targetTeamNumber': 1, 'ownerTeamNumber': 254},
        {'id': 'z', 'matchKey': 'm2', 'targetTeamNumber': 1, 'ownerTeamNumber': 9999},
      ];
      expect(resolveEntries(list, 'match', 254).map((e) => e['id']), ['y', 'z']);
      expect(resolveEntries(list, 'pit', 254).map((e) => e['id']), ['y'], reason: 'pit groups by event and team: one group, own team wins');
    });
  });
}
