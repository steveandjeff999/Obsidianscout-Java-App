import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obsidianscout_app/data/local_store.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/services/account_manager_service.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/net/link_quality.dart';
import 'package:obsidianscout_app/services/net/net_client.dart' as net;
import 'package:obsidianscout_app/services/net/server_file_cache.dart';
import 'package:obsidianscout_app/widgets/cached_server_image.dart';
import 'package:obsidianscout_app/widgets/obsidian_user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends http.BaseClient {
  final http.StreamedResponse Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> requests = [];

  _FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return handler(request);
  }
}

http.StreamedResponse _reply(int status, List<int> body,
        {String type = 'application/json', Map<String, String> headers = const {}}) =>
    http.StreamedResponse(Stream.value(body), status, headers: {'content-type': type, ...headers});

// A 1x1 transparent PNG.
final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, net.EtagRecord> stored;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinkQuality.instance.resetForTesting();
    ServerFileCache.instance.resetForTesting();
    final client = net.NetClient.instance;
    client.resetForTesting();
    stored = {};
    client.readEtag = (url) async => stored[url];
    client.writeEtag = (url, record) async => stored[url] = record;
    client.removeEtag = (url) async => stored.remove(url);
  });

  group('ETag revalidation', () {
    test('a 304 gives back the stored body, not an empty reply', () async {
      final fake = _FakeClient((req) => req.headers['If-None-Match'] == '"a"'
          ? _reply(304, const [])
          : _reply(200, utf8.encode('{"x":1}'), headers: {'etag': '"a"'}));
      net.NetClient.instance.client = fake;
      final url = Uri.parse('http://s/api/matches');

      await net.get(url);
      final second = await net.get(url);

      expect(second.statusCode, 200);
      expect(second.body, '{"x":1}');
      expect(stored[url.toString()]?.body, '{"x":1}');
    });

    test('no-store responses are never kept', () async {
      net.NetClient.instance.client = _FakeClient((_) =>
          _reply(200, utf8.encode('{}'), headers: {'etag': '"a"', 'cache-control': 'no-store, private'}));

      await net.get(Uri.parse('http://s/api/public/data'));

      expect(stored, isEmpty);
    });

    test('a copy goes when the server starts forbidding storage', () async {
      final url = Uri.parse('http://s/api/public/data');
      stored[url.toString()] = (etag: '"old"', body: '{}');
      net.NetClient.instance.client = _FakeClient((_) =>
          _reply(200, utf8.encode('{"new":1}'), headers: {'etag': '"b"', 'cache-control': 'no-store'}));

      await net.get(url);

      expect(stored, isEmpty);
    });

    test('a body that outgrows the limit drops its old, stale copy', () async {
      final url = Uri.parse('http://s/api/big');
      stored[url.toString()] = (etag: '"old"', body: '{}');
      final big = jsonEncode('x' * (net.NetClient.maxEtagBodyChars + 1));
      net.NetClient.instance.client =
          _FakeClient((_) => _reply(200, utf8.encode(big), headers: {'etag': '"b"'}));

      final res = await net.get(url);

      expect(res.body, big);
      expect(stored, isEmpty);
    });

    test('live cluster figures and since= polls add no rows', () async {
      net.NetClient.instance.client =
          _FakeClient((_) => _reply(200, utf8.encode('{}'), headers: {'etag': '"a"'}));

      await net.get(Uri.parse('http://s/api/admin/cluster/analytics/overview'));
      await net.get(Uri.parse('http://s/api/slack/notifications?since=2026-11-01T00:00:00Z'));

      expect(stored, isEmpty);
    });
  });

  group('storage limits', () {
    test('the newest entries are the ones that stay', () {
      final drop = LocalStore.keysOverLimit(
        [('new', 10), ('mid', 10), ('old', 10)],
        maxEntries: 2,
        maxTotalChars: 100,
      );
      expect(drop, ['old']);
    });

    test('the total size limit applies too, and a huge entry does not push out smaller ones', () {
      final drop = LocalStore.keysOverLimit(
        [('a', 60), ('huge', 500), ('b', 30), ('c', 30)],
        maxEntries: 10,
        maxTotalChars: 100,
      );
      expect(drop, ['huge', 'c']);
    });
  });

  group('ServerFileCache', () {
    const url = 'http://server/api/event-info/files/1';

    setUp(() {
      ServerFileCache.instance
        ..serverUrl = (() => 'http://server')
        ..headers = (() => {'Cookie': 'session'});
    });

    test('the file itself is kept, and shows with the server unreachable', () async {
      net.NetClient.instance.client =
          _FakeClient((_) => _reply(200, _png, type: 'image/png', headers: {'etag': '"a"'}));

      expect(await ServerFileCache.instance.refresh(url), _png);

      ServerFileCache.instance.isOnline = () => false;
      expect(await ServerFileCache.instance.stored(url), _png);
      expect(await ServerFileCache.instance.refresh(url), isNull);
    });

    test('a server answering 304 keeps the stored file', () async {
      final cache = ServerFileCache.instance;
      net.NetClient.instance.client =
          _FakeClient((_) => _reply(200, _png, type: 'image/png', headers: {'etag': '"a"'}));
      await cache.refresh(url);

      cache.resetForTesting();
      cache.serverUrl = () => 'http://server';
      final fake = _FakeClient((req) {
        expect(req.headers['If-None-Match'], '"a"');
        return _reply(304, const []);
      });
      net.NetClient.instance.client = fake;

      expect(await cache.refresh(url), isNull);
      expect(fake.requests, hasLength(1));
      expect(await cache.stored(url), _png);
    });

    test('a file is checked once a run, however many widgets show it', () async {
      final fake = _FakeClient((_) => _reply(200, _png, type: 'image/png'));
      net.NetClient.instance.client = fake;

      await Future.wait([ServerFileCache.instance.refresh(url), ServerFileCache.instance.refresh(url)]);
      await ServerFileCache.instance.refresh(url);

      expect(fake.requests, hasLength(1));
    });

    test('a ?v= file is never downloaded twice', () async {
      const versioned = 'http://server/api/avatar/1?v=7';
      final cache = ServerFileCache.instance;
      final fake = _FakeClient((_) => _reply(200, _png, type: 'image/png'));
      net.NetClient.instance.client = fake;
      await cache.refresh(versioned);

      cache.resetForTesting();
      await cache.refresh(versioned);

      expect(fake.requests, hasLength(1));
    });

    test('the session goes only to our own server', () async {
      final fake = _FakeClient((_) => _reply(200, _png, type: 'image/png'));
      net.NetClient.instance.client = fake;

      await ServerFileCache.instance.refresh(url);
      await ServerFileCache.instance.refresh('https://elsewhere.example/a.png');

      expect(fake.requests.first.headers['Cookie'], 'session');
      expect(fake.requests.last.headers['Cookie'], isNull);
    });

    test('a failed download stores nothing', () async {
      net.NetClient.instance.client = _FakeClient((_) => _reply(500, utf8.encode('oops')));

      await ServerFileCache.instance.refresh(url);

      expect(await ServerFileCache.instance.stored(url), isNull);
    });
  });

  test('a scouting refresh finishes, so nothing waiting on it hangs', () async {
    final fake = _FakeClient((req) => req.url.path == '/api/sync/entries'
        ? _reply(500, utf8.encode('{}'))
        : _reply(200, utf8.encode('[]')));
    final api = ApiService();
    net.NetClient.instance.client = fake;

    await api.fetchScoutingEntries(forceRefresh: true).timeout(const Duration(seconds: 5));

    expect(fake.requests.map((r) => r.url.path), contains('/api/sync/entries'));
  });

  group('Clear Cache then Recache All', () {
    late _FakeClient fake;
    late ApiService api;

    int callsTo(String path) => fake.requests.where((r) => r.url.path == path).length;

    setUp(() {
      LocalStore.debugForcePrefsBackend = true;
      fake = _FakeClient((req) => req.url.path == '/api/sync/entries'
          ? _reply(200, utf8.encode('{"cursor":"c","entries":[],"deleted":[],"total":0}'))
          : _reply(200, utf8.encode('[]'), headers: {'etag': '"${req.url.path}"'}));
      api = ApiService();
      net.NetClient.instance.client = fake;
      api.setSessionCookieForTesting('session=1');
      api.setCachedUserForTesting(
          UserModel(id: '1', username: 'root', teamNumber: 1234, role: 'SUPERADMIN'));
    });

    test('everything comes back, not just a stray entry or two', () async {
      await api.syncAllServerDataInBackground();
      await api.clearAllCache();
      expect(await api.getCacheSummary(), isEmpty);

      await api.recacheAll();

      final summary = await api.getCacheSummary();
      expect(summary.keys.where((k) => !k.startsWith('cache_etag:')).length, greaterThan(3), reason: '$summary');
    });

    test('recache after an earlier sync still fetches: a finished sync must not block the next', () async {
      await api.syncAllServerDataInBackground();
      final before = callsTo('/api/settings');

      await api.recacheAll();

      expect(callsTo('/api/settings'), greaterThan(before));
    });

    test('two requests for a sync share one', () async {
      await Future.wait([api.syncAllServerDataInBackground(), api.syncAllServerDataInBackground()]);

      expect(callsTo('/api/settings'), 1);
    });

    test('recache during a sync waits, then does a full one of its own', () async {
      final running = api.syncAllServerDataInBackground();
      final recache = api.recacheAll();
      await Future.wait([running, recache]);

      expect(callsTo('/api/settings'), 2);
    });

    test('clearing lets a file be fetched again in the same run', () async {
      const url = 'http://server/api/event-info/files/9';
      final files = ServerFileCache.instance..serverUrl = (() => 'http://server');
      net.NetClient.instance.client = _FakeClient((_) => _reply(200, _png, type: 'image/png'));
      await files.refresh(url);

      await api.clearAllCache();
      expect(await files.stored(url), isNull);

      expect(await files.refresh(url), _png);
    });
  });

  group('ObsidianUserAvatar with a server link', () {
    const link = '/api/users/1/avatar?v=abc';

    setUp(() {
      ServerFileCache.instance
        ..serverUrl = (() => 'http://server')
        ..headers = (() => {'Cookie': 'session'});
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('loads through the cache with the session', (tester) async {
      final fake = _FakeClient((_) => _reply(200, _png, type: 'image/png'));
      net.NetClient.instance.client = fake;

      await tester.pumpWidget(const MaterialApp(
        home: ObsidianUserAvatar(profilePicture: link, username: 'root', serverUrl: 'http://server'),
      ));
      await settle(tester);

      expect(fake.requests.single.url.toString(), 'http://server$link');
      expect(fake.requests.single.headers['Cookie'], 'session');
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('falls back to initials when the picture cannot be loaded', (tester) async {
      net.NetClient.instance.client = _FakeClient((_) => _reply(404, utf8.encode('{}')));

      await tester.pumpWidget(const MaterialApp(
        home: ObsidianUserAvatar(profilePicture: link, username: 'root', serverUrl: 'http://server'),
      ));
      await settle(tester);

      expect(find.text('RO'), findsOneWidget);
    });

    test('a link can now be kept with a saved account, which an image never could', () {
      expect(SavedAccount.storablePicture(link), link);
      expect(SavedAccount.storablePicture('data:image/png;base64,AAAA'), isNull);
    });
  });

  testWidgets('CachedServerImage falls back when there is nothing to show', (tester) async {
    ServerFileCache.instance.isOnline = () => false;

    await tester.pumpWidget(MaterialApp(
      home: CachedServerImage(
        url: 'http://server/none.png',
        errorBuilder: (_) => const Text('fallback'),
      ),
    ));
    for (var i = 0; i < 5 && find.text('fallback').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('fallback'), findsOneWidget);
  });
}
