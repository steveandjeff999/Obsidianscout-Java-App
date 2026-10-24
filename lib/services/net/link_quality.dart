import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app should behave on this connection. `auto` measures; `on`/`off` are the user's override.
enum LowBandwidthMode { auto, on, off }

/// Snapshot of the link estimate, for the settings screen.
class LinkStats {
  final int? kbps;
  final int? rttMs;
  final int samples;
  final LowBandwidthMode mode;
  final bool low;

  const LinkStats({this.kbps, this.rttMs, this.samples = 0, this.mode = LowBandwidthMode.auto, this.low = false});
}

/// Estimates link speed from finished requests and decides when the app should act as if it's on a slow link
/// (5-50 kbps event Wi-Fi, a crowded hotspot). Same thresholds as the site's net-quality.js.
class LinkQuality {
  LinkQuality._();

  static final LinkQuality instance = LinkQuality._();

  static const String keyMode = 'obsidianscout_low_bandwidth_mode';

  /// Enter low-bandwidth behaviour below this speed or above this round trip...
  static const double enterKbps = 48;
  static const double enterRttMs = 2500;

  /// ...and leave it only once the link is clearly better, so it doesn't flap.
  static const double exitKbps = 96;
  static const double exitRttMs = 1200;

  /// Transfers smaller or quicker than this say more about latency than throughput.
  static const int minSampleBytes = 4096;
  static const int minSampleMs = 250;
  static const double alpha = 0.35;

  /// gzip'd JSON is usually 4-8x smaller on the wire than the decoded body we get to measure.
  static const double assumedGzipRatio = 4;

  double? _kbps;
  double? _rttMs;
  bool _autoLow = false;
  int _samples = 0;
  LowBandwidthMode _mode = LowBandwidthMode.auto;

  /// True when bulk downloads should be skipped or queued and local data preferred.
  final ValueNotifier<bool> lowBandwidth = ValueNotifier<bool>(false);

  /// Bumped on every new estimate, for screens that show the numbers.
  final ValueNotifier<int> statsVersion = ValueNotifier<int>(0);

  LowBandwidthMode get mode => _mode;
  bool get isLowBandwidth => lowBandwidth.value;

  LinkStats get stats => LinkStats(
        kbps: _kbps?.round(),
        rttMs: _rttMs?.round(),
        samples: _samples,
        mode: _mode,
        low: isLowBandwidth,
      );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _parseMode(prefs.getString(keyMode));
    } catch (_) {}
    _publish();
  }

  Future<void> setMode(LowBandwidthMode mode) async {
    _mode = mode;
    _publish();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyMode, mode.name);
    } catch (_) {}
  }

  static LowBandwidthMode _parseMode(String? raw) =>
      LowBandwidthMode.values.firstWhere((m) => m.name == raw, orElse: () => LowBandwidthMode.auto);

  double _ewma(double? prev, double value) => prev == null ? value : prev + alpha * (value - prev);

  void _publish() {
    final low = switch (_mode) {
      LowBandwidthMode.on => true,
      LowBandwidthMode.off => false,
      LowBandwidthMode.auto => _autoLow,
    };
    if (lowBandwidth.value != low) lowBandwidth.value = low;
    statsVersion.value++;
  }

  void _reevaluate() {
    if (_autoLow) {
      final speedOk = _kbps == null || _kbps! >= exitKbps;
      final rttOk = _rttMs == null || _rttMs! <= exitRttMs;
      if (speedOk && rttOk) _autoLow = false;
    } else {
      final slow = _kbps != null && _kbps! < enterKbps;
      final laggy = _rttMs != null && _rttMs! > enterRttMs;
      if (slow || laggy) _autoLow = true;
    }
    _publish();
  }

  /// One finished request: decoded body size, whether it was compressed, time to headers and time reading the body.
  void recordTransfer({required int decodedBytes, required bool gzipped, required int ttfbMs, required int downloadMs}) {
    final wireBytes = gzipped ? decodedBytes / assumedGzipRatio : decodedBytes.toDouble();
    if (ttfbMs > 0) _rttMs = _ewma(_rttMs, ttfbMs.toDouble());
    if (wireBytes >= minSampleBytes && downloadMs >= minSampleMs) {
      _kbps = _ewma(_kbps, wireBytes * 8 / downloadMs); // bits per ms == kbit/s
    }
    _samples++;
    _reevaluate();
  }

  /// A request that stopped making progress counts as a very slow sample.
  void recordStall(int waitedMs) {
    _rttMs = _ewma(_rttMs, (waitedMs > enterRttMs ? waitedMs : enterRttMs + 1).toDouble());
    _samples++;
    _reevaluate();
  }

  @visibleForTesting
  void resetForTesting() {
    _kbps = null;
    _rttMs = null;
    _autoLow = false;
    _samples = 0;
    _mode = LowBandwidthMode.auto;
    _publish();
  }
}
