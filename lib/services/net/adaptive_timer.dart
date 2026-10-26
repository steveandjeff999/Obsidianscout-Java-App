import 'dart:async';

import 'link_quality.dart';

/// [Timer.periodic] for screens that poll the server.
///
/// On a slow link each wait is [slowFactor] times longer (checked every tick, so it follows the link as it changes):
/// every poll costs a round trip and a request slot even when nothing changed, and on a 2 s-latency link a 4 s poll
/// leaves the uploads behind it little room. A tick whose callback returns a Future waits for it before the next
/// wait starts, so slow polls never pile up behind each other.
class AdaptiveTimer implements Timer {
  AdaptiveTimer(this.interval, this.onTick, {this.slowFactor = 4}) {
    _schedule();
  }

  final Duration interval;
  final FutureOr<void> Function(Timer timer) onTick;
  final int slowFactor;

  Timer? _timer;
  int _tick = 0;
  bool _cancelled = false;

  /// The wait before the next tick on the current link.
  Duration get currentInterval => LinkQuality.instance.isLowBandwidth ? interval * slowFactor : interval;

  void _schedule() {
    _timer = Timer(currentInterval, () async {
      if (_cancelled) return;
      _tick++;
      try {
        await onTick(this);
      } catch (_) {
        // A failed poll just waits for the next tick, as with Timer.periodic.
      }
      if (!_cancelled) _schedule();
    });
  }

  @override
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _tick;
}
