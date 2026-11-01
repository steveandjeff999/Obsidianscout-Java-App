import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'api_service.dart';
import 'net/link_quality.dart';
import 'net/net_client.dart';

/// What the server said changed: topic names, plus the event for shared event data (see NotificationWebSocketManager
/// on the server). [everything] means changes may have been missed, because the socket was down.
class LiveDataChange {
  const LiveDataChange(this.topics, {this.eventKey, this.everything = false});

  const LiveDataChange.everything()
      : topics = const {},
        eventKey = null,
        everything = true;

  final Set<String> topics;
  final String? eventKey;
  final bool everything;
}

/// Keeps a screen current: when data under [liveTopics] changes on the server, [liveReload] runs in the background.
///
/// A burst of changes is one reload: the screen waits for them to settle ([liveSettle], at most [liveMaxGather]), then a
/// random time up to [liveSpread], because a score sync reaches every screen at an event at once. Reloads also stay
/// [liveMinInterval] apart (four times that on a slow link) however fast changes arrive. One that comes due while the
/// screen can't be seen (the app is in the background or minimised, or another screen or dialog covers it) or the device
/// is offline waits, and the screen keeps showing what it has. A visible window without focus still updates, so a pit
/// display keeps up. Catching up after a reconnect waits a random time up to
/// [liveCatchUpSpread]: a server restart reconnects everyone at once, and they shouldn't all refetch at that moment.
/// [liveReload] should leave the screen alone until it has new data: a loader with a spinner or an error state checks
/// [isLiveRefreshing] and keeps the current data instead.
mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  /// Changes arriving together are one reload.
  static const Duration _gatherWait = Duration(milliseconds: 300);

  ApiService get liveApi;
  Set<String> get liveTopics;
  Future<void> liveReload();

  bool get liveVisible => true;

  /// The event on screen; null or 'all' means any event's changes matter here.
  String? get liveEventKey => liveApi.currentSettings?.eventKey;
  Duration get liveMinInterval => const Duration(seconds: 5);
  Duration get liveCatchUpSpread => const Duration(seconds: 20);
  Duration get liveSettle => const Duration(seconds: 5);
  Duration get liveMaxGather => const Duration(seconds: 15);
  Duration get liveSpread => const Duration(seconds: 10);

  bool get isLiveRefreshing => _reloading;

  StreamSubscription<LiveDataChange>? _changes;
  StreamSubscription<bool>? _online;
  Timer? _timer;
  Timer? _catchUpTimer;
  Timer? _settleTimer;
  Timer? _gatherLimitTimer;
  Timer? _spreadTimer;
  AppLifecycleListener? _lifecycle;
  bool _reloading = false;
  bool _dirty = false;
  bool _routeOnTop = true;
  DateTime? _lastReload;

  bool get _onTop {
    final appState = WidgetsBinding.instance.lifecycleState;
    final appVisible = appState == null || appState == AppLifecycleState.resumed || appState == AppLifecycleState.inactive;
    return liveVisible && _routeOnTop && appVisible;
  }

  @override
  void initState() {
    super.initState();
    _changes = liveApi.onDataChanged.listen(_onChange);
    _online = liveApi.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) _catchUp();
    });
    _lifecycle = AppLifecycleListener(onShow: _schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the route here is what brings this back when the screen above it closes.
    _routeOnTop = ModalRoute.of(context)?.isCurrent ?? true;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _catchUpTimer?.cancel();
    _settleTimer?.cancel();
    _gatherLimitTimer?.cancel();
    _spreadTimer?.cancel();
    _lifecycle?.dispose();
    _changes?.cancel();
    _online?.cancel();
    super.dispose();
  }

  void _onChange(LiveDataChange change) {
    if (change.everything) {
      _catchUp();
      return;
    }
    if (!change.topics.any(liveTopics.contains)) return;
    final changedEvent = change.eventKey;
    final shownEvent = liveEventKey;
    if (changedEvent != null && shownEvent != null && shownEvent.isNotEmpty && shownEvent != 'all' &&
        shownEvent.toLowerCase() != changedEvent.toLowerCase()) {
      return;
    }
    _markDirty();
  }

  void _catchUp() {
    _catchUpTimer ??= Timer(liveCatchUpSpread * Random().nextDouble(), () {
      _catchUpTimer = null;
      _dirty = true;
      _schedule();
    });
  }

  void _markDirty() {
    _dirty = true;
    if (_spreadTimer != null) return;
    _gatherLimitTimer ??= Timer(liveMaxGather, _endGathering);
    _settleTimer?.cancel();
    _settleTimer = Timer(liveSettle, _endGathering);
  }

  void _endGathering() {
    _settleTimer?.cancel();
    _gatherLimitTimer?.cancel();
    _settleTimer = null;
    _gatherLimitTimer = null;
    _spreadTimer = Timer(liveSpread * Random().nextDouble(), () {
      _spreadTimer = null;
      _schedule();
    });
  }

  void _schedule() {
    if (_timer != null || _reloading || !_dirty) return;
    if (_settleTimer != null || _spreadTimer != null) return;
    final interval = LinkQuality.instance.isLowBandwidth ? liveMinInterval * 4 : liveMinInterval;
    final last = _lastReload;
    final wait = last == null ? Duration.zero : last.add(interval).difference(DateTime.now());
    _timer = Timer(wait < _gatherWait ? _gatherWait : wait, _run);
  }

  Future<void> _run() async {
    _timer = null;
    // didUpdateWidget, didChangeDependencies and the lifecycle and online listeners pick these back up.
    if (!mounted || !_onTop || !liveApi.isOnline) return;
    _dirty = false;
    _reloading = true;
    _lastReload = DateTime.now();
    NetClient.liveRefreshes++;
    try {
      await liveReload();
    } catch (e) {
      debugPrint('[LiveRefresh] Reload failed: $e');
    } finally {
      NetClient.liveRefreshes--;
      _reloading = false;
      if (mounted) _schedule();
    }
  }
}
