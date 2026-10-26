import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obsidianscout_app/data/local_db.dart';
import 'package:obsidianscout_app/data/local_store.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/net/link_quality.dart';
import 'package:obsidianscout_app/services/net/net_client.dart' as net;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers each request with [handler] and records it.
class _FakeServer extends http.BaseClient {
  final http.Response Function(http.BaseRequest request) handler;
  final List<String> requests = [];

  _FakeServer(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    requests.add('${request.method} ${request.url.path}');
    final res = handler(request);
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

Map<String, dynamic> _entry(String id, int team, String match, {bool conflict = false, Map<String, dynamic>? data}) => {
      'id': id,
      'eventKey': '2026test',
      'matchKey': '2026test_$match',
      'targetTeamNumber': team,
      'hasDiscrepancy': conflict,
      'data': data ?? {'score': 1},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final store = LocalStore.instance;
  late ApiService api;
  late _FakeServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.useDatabaseForTesting(LocalDb(NativeDatabase.memory()));
    LinkQuality.instance.resetForTesting();
    net.NetClient.instance.resetForTesting();
    api = ApiService()..setSessionCookieForTesting('session=abc');
    server = _FakeServer((req) => req.method == 'PUT'
        ? http.Response(jsonEncode({..._entry('a', 254, 'qm1', conflict: true), 'data': {'score': 3}}), 200)
        : http.Response('', 204));
    net.NetClient.instance.client = server;

    // Two scouts disagree on 254 in qm1; 1678 in qm2 has its own unresolved conflict.
    await store.setString('cache_scouting', jsonEncode([
      _entry('a', 254, 'qm1', conflict: true),
      _entry('b', 254, 'qm1', conflict: true),
      _entry('c', 1678, 'qm2', conflict: true),
      _entry('d', 1678, 'qm2', conflict: true),
    ]));
  });

  tearDown(() => store.resetForTesting());

  test('merging a conflict updates the stored list in place instead of downloading it again', () async {
    expect((await api.updateScoutingEntry('a', {'score': 3})).success, isTrue);
    expect((await api.deleteScoutingEntry('b')).success, isTrue);

    final entries = (await api.getCachedScoutingEntries()).cast<Map>();
    expect(entries.map((e) => e['id']), ['a', 'c', 'd']);
    expect(entries.first['data'], {'score': 3});
    expect(entries.first['hasDiscrepancy'], isFalse, reason: 'its conflict is resolved');
    expect(entries.where((e) => e['id'] != 'a').map((e) => e['hasDiscrepancy']), [true, true],
        reason: 'the other conflict is still open');

    // Fresh, so the page redraws from it: only the two writes went to the server.
    expect(api.isCacheFresh('cache_scouting'), isTrue);
    expect(await api.fetchScoutingEntries(), hasLength(3));
    expect(server.requests, ['PUT /api/scouting/a', 'DELETE /api/scouting/b']);

    // Survives a restart (the disk copy was updated too).
    final reloaded = jsonDecode((await store.getString('cache_scouting'))!) as List;
    expect(reloaded.map((e) => (e as Map)['id']), ['a', 'c', 'd']);
  });

  test('pit entries are grouped by event and team', () async {
    await store.setString('cache_pit_scouting', jsonEncode([
      {'id': 'p1', 'eventKey': '2026test', 'targetTeamNumber': 254, 'hasDiscrepancy': true},
      {'id': 'p2', 'eventKey': '2026test', 'targetTeamNumber': 254, 'hasDiscrepancy': true},
    ]));
    await api.deleteScoutingEntry('pit-p2', type: 'pit');

    final pit = (await api.getCachedPitScoutingEntries()).cast<Map>();
    expect(pit.single['id'], 'p1');
    expect(pit.single['hasDiscrepancy'], isFalse);
  });
}
