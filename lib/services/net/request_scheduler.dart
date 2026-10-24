import 'dart:async';

import 'link_quality.dart';

/// Lower runs first. Writes and sign-in are [critical]; bulk downloads are [low].
enum RequestPriority { critical, high, normal, low }

/// Runs requests by priority. On a slow link, bulk downloads go one at a time and never hold up uploads,
/// assignments or the match schedule. Same rules as the site's request-scheduler.js.
class RequestScheduler {
  RequestScheduler._();

  static final RequestScheduler instance = RequestScheduler._();

  static const int normalConcurrency = 6;

  /// On a slow link: two requests in flight, at most one of them below [RequestPriority.high].
  static const int lowBandwidthConcurrency = 2;
  static const int lowBandwidthBulkSlots = 1;

  static const List<String> _highPaths = [
    '/api/assignments',
    '/api/settings',
    '/api/matches',
    '/api/teams',
    '/api/sync/entries',
    '/api/match-checklist',
    '/api/battery-tracker',
  ];
  static const List<String> _lowPaths = [
    '/api/analytics',
    '/api/custom-analytics',
    '/api/matches/predict',
    '/api/field-images',
    '/assets/',
    '/api/events',
    '/api/summary',
    '/api/stats',
    '/api/validation',
    '/api/admin/',
    '/api/chat',
    '/api/banners',
  ];

  /// Default priority for a request. Predictions live under /api/matches but are bulk, so LOW is checked first.
  static RequestPriority priorityFor(String method, String path) {
    if (method.toUpperCase() != 'GET' || path.startsWith('/api/auth')) return RequestPriority.critical;
    if (_lowPaths.any(path.startsWith)) return RequestPriority.low;
    if (_highPaths.any(path.startsWith)) return RequestPriority.high;
    return RequestPriority.normal;
  }

  final List<_Job> _queue = [];
  int _active = 0;
  int _activeBulk = 0;
  int _seq = 0;

  int get active => _active;
  int get waiting => _queue.length;

  Future<T> schedule<T>(RequestPriority priority, Future<T> Function() task) {
    final completer = Completer<T>();
    _queue.add(_Job(priority, _seq++, () async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }));
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_queue.isNotEmpty) {
      final low = LinkQuality.instance.isLowBandwidth;
      final limit = low ? lowBandwidthConcurrency : normalConcurrency;
      if (_active >= limit) return;

      var best = 0;
      for (var i = 1; i < _queue.length; i++) {
        final a = _queue[i], b = _queue[best];
        if (a.priority.index < b.priority.index || (a.priority == b.priority && a.seq < b.seq)) best = i;
      }
      final job = _queue[best];
      final bulk = job.priority.index >= RequestPriority.normal.index;
      // The best waiting job is bulk and the bulk slot is taken: nothing more important is waiting either.
      if (low && bulk && _activeBulk >= lowBandwidthBulkSlots) return;

      _queue.removeAt(best);
      _active++;
      if (bulk) _activeBulk++;
      job.run().whenComplete(() {
        _active--;
        if (bulk) _activeBulk--;
        _pump();
      });
    }
  }
}

class _Job {
  final RequestPriority priority;
  final int seq;
  final Future<void> Function() run;

  _Job(this.priority, this.seq, this.run);
}
