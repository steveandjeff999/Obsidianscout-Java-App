import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/live_refresh.dart';
import 'package:obsidianscout_app/services/net/net_client.dart';

class _FakeApi extends ApiService {
  bool online = true;
  final StreamController<bool> onlineChanges = StreamController<bool>.broadcast();

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get onOnlineStatusChanged => onlineChanges.stream;
}

class _Live extends StatefulWidget {
  const _Live({
    required this.api,
    required this.onReload,
    this.isVisible = true,
    this.catchUpSpread = Duration.zero,
    this.settleTime = Duration.zero,
    this.maxGather = Duration.zero,
    this.spread = Duration.zero,
  });

  final ApiService api;
  final Future<void> Function() onReload;
  final bool isVisible;
  final Duration catchUpSpread;
  final Duration settleTime;
  final Duration maxGather;
  final Duration spread;

  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> with LiveRefresh<_Live> {
  @override
  ApiService get liveApi => widget.api;

  @override
  Set<String> get liveTopics => const {'scouting'};

  @override
  Future<void> liveReload() => widget.onReload();

  @override
  bool get liveVisible => widget.isVisible;

  @override
  String? get liveEventKey => '2026cada';

  @override
  Duration get liveCatchUpSpread => widget.catchUpSpread;

  @override
  Duration get liveSettle => widget.settleTime;

  @override
  Duration get liveMaxGather => widget.maxGather;

  @override
  Duration get liveSpread => widget.spread;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApi api;
  late int reloads;

  setUp(() {
    api = _FakeApi();
    reloads = 0;
  });

  Future<void> reload() async => reloads++;

  const change = LiveDataChange({'scouting'});
  const settle = Duration(milliseconds: 350);

  testWidgets('reloads for its topics and ignores the others', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));

    api.announceDataChanged(const LiveDataChange({'chat'}));
    await tester.pump(settle);
    expect(reloads, 0);

    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('a burst of changes is spread out, and the last one still lands', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));

    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 1);

    for (var i = 0; i < 10; i++) {
      api.announceDataChanged(change);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(reloads, 1);

    await tester.pump(const Duration(seconds: 4));
    expect(reloads, 2);
  });

  testWidgets('another event is dropped, its own event and missed changes are not', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));

    api.announceDataChanged(const LiveDataChange({'scouting'}, eventKey: '2026other'));
    await tester.pump(settle);
    expect(reloads, 0);

    api.announceDataChanged(const LiveDataChange({'scouting'}, eventKey: '2026CADA'));
    await tester.pump(settle);
    expect(reloads, 1);

    api.announceDataChanged(const LiveDataChange.everything());
    await tester.pump(const Duration(seconds: 6));
    expect(reloads, 2);
  });

  testWidgets('catching up spreads out, but a real change does not wait with it', (tester) async {
    const spread = Duration(seconds: 20);
    await tester.pumpWidget(_Live(api: api, onReload: reload, catchUpSpread: spread));

    api.announceDataChanged(const LiveDataChange.everything());
    await tester.pump(settle);
    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 1);

    await tester.pump(spread + const Duration(seconds: 6));
    expect(reloads, lessThanOrEqualTo(2));
  });

  testWidgets('a hidden screen waits until it is shown', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload, isVisible: false));

    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 0);

    await tester.pumpWidget(_Live(api: api, onReload: reload));
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('a burst of changes is one reload, once they stop', (tester) async {
    await tester.pumpWidget(_Live(
      api: api,
      onReload: reload,
      settleTime: const Duration(seconds: 5),
      maxGather: const Duration(seconds: 15),
    ));

    for (var i = 0; i < 4; i++) {
      api.announceDataChanged(change);
      await tester.pump(const Duration(seconds: 2));
    }
    expect(reloads, 0);

    await tester.pump(const Duration(seconds: 4));
    expect(reloads, 1);
  });

  testWidgets('changes that never stop still reload at the gathering limit', (tester) async {
    await tester.pumpWidget(_Live(
      api: api,
      onReload: reload,
      settleTime: const Duration(seconds: 5),
      maxGather: const Duration(seconds: 15),
    ));

    for (var i = 0; i < 9; i++) {
      api.announceDataChanged(change);
      await tester.pump(const Duration(seconds: 2));
    }
    expect(reloads, greaterThanOrEqualTo(1));
  });

  testWidgets('a reload waits inside the random spread, and no longer', (tester) async {
    const spread = Duration(seconds: 10);
    await tester.pumpWidget(_Live(api: api, onReload: reload, spread: spread));

    api.announceDataChanged(change);
    await tester.pump(spread + settle);
    expect(reloads, 1);
  });

  testWidgets('a screen under another one waits, and reloads once when it is back on top', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Live(api: api, onReload: reload)));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pumpAndSettle();

    api.announceDataChanged(change);
    await tester.pump(settle);
    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 0);

    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('a visible window without focus keeps updating', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('an app that cannot be seen waits, and reloads when it can', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('offline keeps what is on screen and catches up when back online', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));
    api.online = false;

    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(reloads, 0);

    api.online = true;
    api.onlineChanges.add(true);
    await tester.pump(settle);
    expect(reloads, 1);
  });

  testWidgets('requests during a reload are marked for the load profiler, and later ones are not', (tester) async {
    int? duringReload;
    await tester.pumpWidget(_Live(
      api: api,
      onReload: () async => duringReload = NetClient.liveRefreshes,
    ));

    api.announceDataChanged(change);
    await tester.pump(settle);
    expect(duringReload, 1);
    expect(NetClient.liveRefreshes, 0);
  });

  testWidgets('a change clears the freshness of the data it covers', (tester) async {
    api.markCacheFresh('cache_scouting');
    api.markCacheFresh('cache_config');

    api.announceDataChanged(change);

    expect(api.isCacheFresh('cache_scouting'), isFalse);
    expect(api.isCacheFresh('cache_config'), isTrue);
  });

  testWidgets('no timers outlive the screen', (tester) async {
    await tester.pumpWidget(_Live(api: api, onReload: reload));
    api.announceDataChanged(change);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(settle);
    expect(reloads, 0);
  });
}
