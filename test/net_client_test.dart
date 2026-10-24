import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obsidianscout_app/services/net/link_quality.dart';
import 'package:obsidianscout_app/services/net/net_client.dart' as net;
import 'package:obsidianscout_app/services/net/request_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A client whose responses are produced by [handler]; the body can be streamed in timed chunks.
class _FakeClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request, List<int> body) handler;
  final List<http.BaseRequest> requests = [];

  _FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = await request.finalize().toBytes();
    return handler(request, body);
  }
}

http.StreamedResponse _json(int status, String body, {Map<String, String> headers = const {}}) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinkQuality.instance.resetForTesting();
    net.NetClient.instance.resetForTesting();
  });

  test('large JSON uploads are gzipped and small ones are not', () async {
    final seen = <String, List<int>>{};
    final client = _FakeClient((req, body) async {
      seen[req.url.path] = body;
      expect(req.headers['Content-Encoding'], req.url.path == '/big' ? 'gzip' : isNull);
      return _json(200, '{}');
    });
    net.NetClient.instance.client = client;
    final headers = {'Content-Type': 'application/json'};
    final big = jsonEncode({'data': List.generate(200, (i) => {'field_$i': i})});
    await net.post(Uri.parse('http://s/big'), headers: headers, body: big);
    await net.post(Uri.parse('http://s/small'), headers: headers, body: '{"a":1}');
    expect(utf8.decode(gzip.decode(seen['/big']!)), big);
    expect(utf8.decode(seen['/small']!), '{"a":1}');
  });

  test('a server that rejects gzip gets the plain body and no more gzip', () async {
    var calls = 0;
    final client = _FakeClient((req, body) async {
      calls++;
      if (req.headers['Content-Encoding'] == 'gzip') return _json(400, '{"error":"Malformed JSON"}');
      return _json(200, '{"ok":true}');
    });
    net.NetClient.instance.client = client;
    final big = jsonEncode({'x': 'y' * 2000});
    final res = await net.post(Uri.parse('http://s/p'), headers: {'Content-Type': 'application/json'}, body: big);
    expect(res.statusCode, 200);
    expect(calls, 2);
    await net.post(Uri.parse('http://s/p'), headers: {'Content-Type': 'application/json'}, body: big);
    expect(calls, 3, reason: 'sent plain straight away the second time');
  });

  test('GETs revalidate with the stored ETag and a 304 returns the stored body', () async {
    final store = <String, net.EtagRecord>{};
    net.NetClient.instance
      ..readEtag = ((url) async => store[url])
      ..writeEtag = ((url, record) async => store[url] = record);
    final client = _FakeClient((req, body) async {
      if (req.headers['If-None-Match'] == '"v1"') return http.StreamedResponse(const Stream.empty(), 304);
      return _json(200, '{"teams":[1,2,3]}', headers: {'etag': '"v1"'});
    });
    net.NetClient.instance.client = client;

    final first = await net.get(Uri.parse('http://s/api/teams'));
    expect(first.body, '{"teams":[1,2,3]}');
    final second = await net.get(Uri.parse('http://s/api/teams'));
    expect(second.statusCode, 200);
    expect(second.body, '{"teams":[1,2,3]}');
    expect(client.requests.last.headers['If-None-Match'], '"v1"');
  });

  test('a slow download that keeps moving finishes; one that stalls fails', () async {
    net.NetClient.instance.connectTimeout = () => const Duration(milliseconds: 200);
    LinkQuality.instance.resetForTesting();
    await LinkQuality.instance.setMode(LowBandwidthMode.off);

    Stream<List<int>> trickle(int chunks, Duration gap) async* {
      for (var i = 0; i < chunks; i++) {
        await Future<void>.delayed(gap);
        yield utf8.encode('x');
      }
    }

    // 30 chunks 100 ms apart = 3 s total, far beyond the 200 ms window, but never 15 s without a byte.
    net.NetClient.instance.client = _FakeClient((req, body) async => http.StreamedResponse(trickle(30, const Duration(milliseconds: 100)), 200));
    final ok = await net.get(Uri.parse('http://s/slow'));
    expect(ok.body.length, 30);

    net.NetClient.instance.client = _FakeClient((req, body) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return _json(200, '{}');
    });
    await expectLater(net.get(Uri.parse('http://s/dead')), throwsA(isA<TimeoutException>()));
  });

  test('on a slow link bulk requests run one at a time and never block uploads', () async {
    await LinkQuality.instance.setMode(LowBandwidthMode.on);
    final sched = RequestScheduler.instance;
    final order = <String>[];
    final gate = Completer<void>();
    final bulk1 = sched.schedule<void>(RequestPriority.low, () async {
      order.add('bulk1:start');
      await gate.future;
      order.add('bulk1:end');
    });
    final bulk2 = sched.schedule<void>(RequestPriority.low, () async => order.add("bulk2"));
    final upload = sched.schedule<void>(RequestPriority.critical, () async => order.add("upload"));
    await upload;
    expect(order, ['bulk1:start', 'upload']);
    gate.complete();
    await Future.wait([bulk1, bulk2]);
    expect(order, ['bulk1:start', 'upload', 'bulk1:end', 'bulk2']);
  });

  test('priorities: writes first, predictions are bulk, schedule is high', () {
    expect(RequestScheduler.priorityFor('POST', '/api/scouting'), RequestPriority.critical);
    expect(RequestScheduler.priorityFor('GET', '/api/matches/predict-all'), RequestPriority.low);
    expect(RequestScheduler.priorityFor('GET', '/api/matches'), RequestPriority.high);
    expect(RequestScheduler.priorityFor('GET', '/api/sync/entries'), RequestPriority.high);
  });

  test('link estimate turns slow mode on and off with hysteresis', () {
    void sample(double kbps) =>
        LinkQuality.instance.recordTransfer(decodedBytes: (kbps * 4000 / 8).round(), gzipped: false, ttfbMs: 100, downloadMs: 4000);
    for (var i = 0; i < 8; i++) {
      sample(10);
    }
    expect(LinkQuality.instance.isLowBandwidth, isTrue);
    for (var i = 0; i < 3; i++) {
      sample(70);
    }
    expect(LinkQuality.instance.isLowBandwidth, isTrue, reason: 'between the thresholds, so it stays on');
    for (var i = 0; i < 10; i++) {
      sample(500);
    }
    expect(LinkQuality.instance.isLowBandwidth, isFalse);
  });
}
