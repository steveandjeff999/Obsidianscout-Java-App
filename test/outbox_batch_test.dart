import 'dart:convert';
import 'dart:io' show gzip;

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
  final http.Response Function(http.BaseRequest request, String body) handler;
  final List<({String path, String body})> requests = [];

  _FakeServer(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final body = request.headers['Content-Encoding'] == 'gzip' ? utf8.decode(gzip.decode(bytes)) : utf8.decode(bytes);
    requests.add((path: request.url.path, body: body));
    final res = handler(request, body);
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

http.Response _results(List<Map<String, Object?>> results) => http.Response(jsonEncode({'results': results}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final store = LocalStore.instance;
  late ApiService api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.useDatabaseForTesting(LocalDb(NativeDatabase.memory()));
    LinkQuality.instance.resetForTesting();
    net.NetClient.instance.resetForTesting();
    api = ApiService()..setSessionCookieForTesting('session=abc');
  });

  tearDown(() => store.resetForTesting());

  Future<void> queue(String id, String kind, Map<String, dynamic> payload) =>
      store.enqueue(OutboxItem(id: id, kind: kind, payload: payload, createdAt: DateTime(2026, 10, 1)));

  Map<String, dynamic> entry(int team) => {'data': {'eventKey': '2026test', 'targetTeamNumber': team}};

  test('the outbox goes up in one request, with each item\'s id as its clientId', () async {
    await queue('a', 'match', entry(1));
    await queue('b', 'pit', entry(2));
    await queue('c', 'assignment_status', {'id': 'x1', 'status': 'COMPLETED'});
    final server = _FakeServer((req, body) {
      final items = (jsonDecode(body) as Map)['items'] as List;
      return _results([for (final i in items) {'id': (i as Map)['id'], 'status': 200}]);
    });
    net.NetClient.instance.client = server;

    expect(await api.syncOutbox(), 3);

    expect(server.requests.map((r) => r.path), ['/api/sync/outbox']);
    final items = (jsonDecode(server.requests.single.body) as Map)['items'] as List;
    expect(items.map((i) => (i as Map)['kind']), ['match', 'pit', 'assignment_status']);
    expect(((items[0] as Map)['payload'] as Map)['clientId'], 'a');
    expect(((items[2] as Map)['payload'] as Map).containsKey('clientId'), isFalse);
    expect(await store.outbox(), isEmpty);
  });

  test('a retryable failure keeps that item and everything after it, in order', () async {
    await queue('a', 'match', entry(1));
    await queue('b', 'match', entry(2));
    await queue('c', 'match', entry(3));
    await queue('d', 'match', entry(4));
    net.NetClient.instance.client = _FakeServer((req, body) => _results([
          {'id': 'a', 'status': 200},
          {'id': 'b', 'status': 422, 'error': 'bad'},
          {'id': 'c', 'status': 500, 'error': 'db down'},
          {'id': 'd', 'status': 503},
        ]));

    expect(await api.syncOutbox(), 1);

    final left = await store.outbox();
    expect(left.map((i) => i.id), ['c', 'd'], reason: 'a uploaded, b refused for good');
    expect(left.first.attempts, 1);
  });

  test('a server without the batch endpoint gets one request per item', () async {
    await queue('a', 'match', entry(1));
    await queue('b', 'qual', entry(2));
    final server = _FakeServer((req, body) =>
        req.url.path == '/api/sync/outbox' ? http.Response('Not Found', 404) : http.Response('{}', 200));
    net.NetClient.instance.client = server;

    expect(await api.syncOutbox(), 2);
    expect(server.requests.map((r) => r.path), ['/api/sync/outbox', '/api/scouting', '/api/qual-scouting']);
    expect((jsonDecode(server.requests[1].body) as Map)['clientId'], 'a');

    // Remembered for the next sync: no second probe.
    await queue('c', 'pit', entry(3));
    expect(await api.syncOutbox(), 1);
    expect(server.requests.last.path, '/api/pit-scouting');
    expect(server.requests.where((r) => r.path == '/api/sync/outbox'), hasLength(1));
  });

  test('a large outbox is split so one dropped request does not cost all of it', () async {
    for (var i = 0; i < 30; i++) {
      await queue('i$i', 'match', entry(i));
    }
    final server = _FakeServer((req, body) {
      final items = (jsonDecode(body) as Map)['items'] as List;
      return _results([for (final i in items) {'id': (i as Map)['id'], 'status': 200}]);
    });
    net.NetClient.instance.client = server;

    expect(await api.syncOutbox(), 30);
    expect(server.requests, hasLength(2));
  });
}
