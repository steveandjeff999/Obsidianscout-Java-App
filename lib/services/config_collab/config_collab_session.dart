import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'collab_socket.dart';
import 'config_sync_engine.dart';

enum CollabStatus { connecting, live, readonly, reconnecting, offline }

/// Someone with the same config open.
class CollabEditor {
  final String sid;
  final String username;
  final int teamNumber;
  final bool canEdit;
  final String? focus;

  const CollabEditor({required this.sid, required this.username, required this.teamNumber, required this.canEdit, this.focus});

  factory CollabEditor.fromJson(Map<String, dynamic> json) => CollabEditor(
        sid: json['sid']?.toString() ?? '',
        username: json['username']?.toString() ?? '?',
        teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
        canEdit: json['canEdit'] != false,
        focus: json['focus'] as String?,
      );
}

/// Result of "save version" (a revision checkpoint) while live.
class CollabCommitResult {
  final bool hasFieldChanges;
  final List<String> changedFields;
  final int entryCount;

  const CollabCommitResult({this.hasFieldChanges = false, this.changedFields = const [], this.entryCount = 0});
}

class _Batch {
  final int seq;
  final List<dynamic> ops;

  _Batch(this.seq, this.ops);
}

/// Keeps a config editor in sync with everyone else editing the same config.
///
/// Local edits apply immediately and are sent in batches; edits from others arrive as ops and are shown
/// through [onView]. While the socket is down, edits keep buffering locally and are merged in when it
/// reconnects. If the server can't be reached, [saveViaRest] merges with the latest saved config and
/// saves it the way the editor always has. Mirrors ConfigCollabSession in static/js/services/config-collab.js.
class ConfigCollabSession {
  static const protocol = 1;
  static const _flushDelay = Duration(milliseconds: 60);
  static const _pingEvery = Duration(seconds: 20);
  static const _silenceLimit = Duration(seconds: 45);
  static const _connectTimeout = Duration(seconds: 6);
  static const _maxBatch = 400;

  final Uri? url;
  final Map<String, String> Function() headers;
  final Map<String, dynamic>? Function(Map<String, dynamic> field) projectField;
  final Map<String, dynamic> Function(Map<String, dynamic> doc) projectRest;
  final void Function(KeyedDoc view, String source, String? user)? onView;
  final void Function(CollabStatus status)? onStatus;
  final void Function(List<CollabEditor> editors)? onPresence;
  final void Function(String level, String message)? onNotice;
  final CollabSocketFactory socketFactory;

  final String sid = _randomId(16);
  int _keyCounter = 0;
  int _seqCounter = 0;

  CollabStatus status = CollabStatus.offline;
  bool canEdit = true;
  String? _epoch;
  int _version = 0;
  late KeyedDoc _confirmed;
  late KeyedDoc _local;
  final List<_Batch> _inflight = [];
  final List<dynamic> _unsent = [];
  late KeyedDoc lastView;
  List<CollabEditor> editors = const [];

  CollabSocket? _socket;
  StreamSubscription? _subscription;
  bool _closed = false;
  int _retry = 0;
  DateTime _lastMessageAt = DateTime.now();
  String? _focusKey;
  Timer? _flushTimer;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _connectTimer;
  final Map<String, Completer<CollabCommitResult>> _pendingCommits = {};

  ConfigCollabSession({
    required this.url,
    Map<String, String> Function()? headers,
    Map<String, dynamic>? Function(Map<String, dynamic> field)? projectField,
    Map<String, dynamic> Function(Map<String, dynamic> doc)? projectRest,
    this.onView,
    this.onStatus,
    this.onPresence,
    this.onNotice,
    CollabSocketFactory? socketFactory,
  })  : headers = headers ?? (() => const {}),
        projectField = projectField ?? ((f) => f),
        projectRest = projectRest ?? ((d) => Map<String, dynamic>.of(d)..remove(ConfigSyncEngine.fieldsKey)),
        socketFactory = socketFactory ?? connectCollabSocket {
    _confirmed = ConfigSyncEngine.keyed({}, _newKey);
    _local = _confirmed;
    lastView = project(_local);
  }

  String _newKey() => '$sid.${(_keyCounter++).toRadixString(36)}';

  bool get isLive => status == CollabStatus.live || status == CollabStatus.readonly;
  bool get hasUnsavedChanges => _inflight.isNotEmpty || _unsent.isNotEmpty;
  Map<String, dynamic> get localDoc => _local.doc;

  /// The config as this editor shows it, with the key of each shown field.
  KeyedDoc project(KeyedDoc state) {
    final fields = <dynamic>[];
    final keys = <String>[];
    final all = state.fields;
    for (var i = 0; i < all.length; i++) {
      final f = all[i];
      if (f is! Map) continue;
      final p = projectField(ConfigSyncEngine.cloneMap(Map<String, dynamic>.from(f)));
      if (p != null) {
        fields.add(p);
        keys.add(state.keys[i]);
      }
    }
    final rest = projectRest(ConfigSyncEngine.cloneMap(state.doc))..remove(ConfigSyncEngine.fieldsKey);
    return KeyedDoc({...rest, ConfigSyncEngine.fieldsKey: fields}, keys);
  }

  /// Starts from a config loaded the old way (REST/cache); returns the view to show.
  KeyedDoc load(Map<String, dynamic> doc) {
    _confirmed = ConfigSyncEngine.keyed(doc, _newKey);
    _local = _confirmed;
    _inflight.clear();
    _unsent.clear();
    _epoch = null;
    lastView = project(_local);
    return lastView;
  }

  /// Records an edit: [next] is the editor's whole config, [base] the view it was derived from
  /// (defaults to the last view). Returns [next] keyed.
  KeyedDoc commit(Map<String, dynamic> next, [KeyedDoc? base]) {
    final from = base ?? lastView;
    final target = ConfigSyncEngine.ensureFields(ConfigSyncEngine.cloneMap(next));
    final result = ConfigSyncEngine.diff(from, target, _newKey);
    if (result.ops.isNotEmpty) {
      if (!canEdit && isLive) {
        onNotice?.call('warning', 'You can view this config but not edit it.');
        _emitView('reject');
        return KeyedDoc(target, result.keys);
      }
      _local = ConfigSyncEngine.applyOps(_local, result.ops);
      _unsent.addAll(result.ops);
      _scheduleFlush();
    }
    final view = project(_local);
    lastView = view;
    if (!ConfigSyncEngine.deepEqual(view.doc, target)) onView?.call(view, 'normalize', null);
    return KeyedDoc(target, result.keys);
  }

  void setFocus(String? key) {
    if (key == _focusKey) return;
    _focusKey = key;
    _send({'type': 'focus', 'key': key});
  }

  /// "Save version": checkpoints the live config (revision history + migration check).
  Future<CollabCommitResult> saveVersion() {
    if (!isLive) return Future.error(StateError('Not connected'));
    _flush();
    final req = _randomId(10);
    final completer = Completer<CollabCommitResult>();
    _pendingCommits[req] = completer;
    _send({'type': 'commit', 'req': req});
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      _pendingCommits.remove(req);
      throw TimeoutException('Timed out waiting for the server');
    });
  }

  /// Fallback save while live editing is down: merges unsaved edits into the latest saved config
  /// ([fetchCurrent]) and stores it with [put]. Pending edits are only cleared if [saved] says it worked.
  Future<T> saveViaRest<T>(
    Future<Map<String, dynamic>?> Function() fetchCurrent,
    Future<T> Function(Map<String, dynamic> doc) put, {
    bool Function(T result)? saved,
  }) async {
    final theirs = ConfigSyncEngine.ensureFields(await fetchCurrent() ?? <String, dynamic>{});
    final inflightOps = [for (final b in _inflight) ...b.ops];
    final base = ConfigSyncEngine.applyOps(_confirmed, inflightOps);
    final merged = ConfigSyncEngine.rebase(base, theirs, [...inflightOps, ..._unsent], _newKey);
    final result = await put(ConfigSyncEngine.cloneMap(merged.doc));
    if (saved == null || saved(result)) {
      _confirmed = merged;
      _local = merged;
      _inflight.clear();
      _unsent.clear();
      _epoch = null;
      _emitView('rebase');
    }
    return result;
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  void connect() {
    if (_socket != null || _closed || url == null) return;
    _reconnectTimer?.cancel();
    // Once retries have failed the editor stays "offline" until a connection actually succeeds.
    if (status != CollabStatus.offline || _retry == 0) {
      _setStatus(_epoch != null ? CollabStatus.reconnecting : CollabStatus.connecting);
    }
    final uri = url!.replace(queryParameters: {...url!.queryParameters, 'sid': sid});
    final CollabSocket socket;
    try {
      socket = socketFactory(uri, headers());
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _socket = socket;
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      if (identical(_socket, socket) && !isLive) _drop(socket);
    });
    _subscription = socket.stream.listen(
      (data) {
        if (!identical(_socket, socket)) return;
        _lastMessageAt = DateTime.now();
        try {
          final msg = jsonDecode(data.toString());
          if (msg is Map<String, dynamic>) _handle(msg);
        } catch (_) {}
      },
      onError: (_) => _drop(socket),
      onDone: () => _drop(socket),
      cancelOnError: true,
    );
  }

  /// Reconnects right away (e.g. when the device comes back online).
  void reconnectNow() {
    if (_closed || _socket != null) return;
    _reconnectTimer?.cancel();
    connect();
  }

  void close() {
    _closed = true;
    _reconnectTimer?.cancel();
    _flushTimer?.cancel();
    _pingTimer?.cancel();
    _connectTimer?.cancel();
    _subscription?.cancel();
    final socket = _socket;
    _socket = null;
    socket?.close();
    _failCommits('Closed');
  }

  void _drop(CollabSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _subscription?.cancel();
    _connectTimer?.cancel();
    _pingTimer?.cancel();
    socket.close();
    if (_closed) return;
    _failCommits('Connection lost');
    _scheduleReconnect();
  }

  void _failCommits(String reason) {
    for (final c in _pendingCommits.values) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _pendingCommits.clear();
  }

  void _scheduleReconnect() {
    _retry += 1;
    // After a couple of failed attempts, the editor works offline (Save falls back to REST).
    _setStatus(_retry >= 2 || _epoch == null ? CollabStatus.offline : CollabStatus.reconnecting);
    final base = min(30000, 1000 * pow(2, min(_retry - 1, 5)).toInt());
    final jitter = 0.75 + Random().nextDouble() * 0.5;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: (base * jitter).round()), connect);
  }

  void _setStatus(CollabStatus s) {
    if (status == s) return;
    status = s;
    onStatus?.call(s);
  }

  bool _send(Map<String, dynamic> msg) {
    final socket = _socket;
    if (socket == null || !isLive) return false;
    try {
      socket.send(jsonEncode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive == true) return;
    _flushTimer = Timer(_flushDelay, _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    if (_unsent.isEmpty || !isLive || !canEdit) return;
    while (_unsent.isNotEmpty) {
      final n = min(_maxBatch, _unsent.length);
      final batch = _Batch(++_seqCounter, _unsent.sublist(0, n));
      _unsent.removeRange(0, n);
      _inflight.add(batch);
      _send({'type': 'ops', 'seq': batch.seq, 'ops': batch.ops});
    }
  }

  void _emitView(String source, [String? user]) {
    lastView = project(_local);
    onView?.call(lastView, source, user);
  }

  KeyedDoc _replayPending() => ConfigSyncEngine.applyOps(_confirmed, [for (final b in _inflight) ...b.ops, ..._unsent]);

  void _handle(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'init':
        _onInit(msg);
        break;
      case 'ops':
        _onOps(msg);
        break;
      case 'ack':
        final seq = (msg['seq'] as num?)?.toInt() ?? 0;
        _inflight.removeWhere((b) => b.seq <= seq);
        break;
      case 'reject':
        final seq = (msg['seq'] as num?)?.toInt();
        _inflight.removeWhere((b) => b.seq == seq);
        _local = _replayPending();
        _emitView('reject');
        onNotice?.call('error', msg['reason']?.toString() ?? 'A change was not accepted');
        break;
      case 'presence':
        editors = _parseEditors(msg['editors']);
        onPresence?.call(editors);
        break;
      case 'committed':
        final completer = _pendingCommits.remove(msg['req']);
        if (completer == null || completer.isCompleted) break;
        if (msg['ok'] == true) {
          completer.complete(CollabCommitResult(
            hasFieldChanges: msg['hasFieldChanges'] == true,
            changedFields: (msg['changedFields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
            entryCount: (msg['entryCount'] as num?)?.toInt() ?? 0,
          ));
        } else {
          completer.completeError(StateError(msg['error']?.toString() ?? 'Save failed'));
        }
        break;
      case 'notice':
        onNotice?.call(msg['level']?.toString() ?? 'info', msg['message']?.toString() ?? '');
        break;
      case 'error':
        onNotice?.call('error', msg['message']?.toString() ?? 'Live editing error');
        break;
    }
  }

  List<CollabEditor> _parseEditors(dynamic raw) =>
      raw is List ? [for (final e in raw) if (e is Map) CollabEditor.fromJson(Map<String, dynamic>.from(e))] : const [];

  void _onInit(Map<String, dynamic> msg) {
    if (msg['proto'] != protocol) {
      onNotice?.call('warning', 'Live editing needs an app update; changes are saved with the Save button.');
      close();
      _setStatus(CollabStatus.offline);
      return;
    }
    _connectTimer?.cancel();
    final serverDoc = ConfigSyncEngine.ensureFields(Map<String, dynamic>.from(msg['doc'] as Map? ?? const {}));
    var serverKeys = (msg['keys'] as List?)?.map((k) => k.toString()).toList() ?? <String>[];
    if (serverKeys.length != ConfigSyncEngine.fieldsOf(serverDoc).length) {
      serverKeys = [for (final _ in ConfigSyncEngine.fieldsOf(serverDoc)) _newKey()];
    }
    final server = KeyedDoc(serverDoc, serverKeys);

    if (msg['epoch'] == _epoch) {
      // Same room as before the drop: resend only what the server hasn't applied.
      final ackSeq = (msg['ackSeq'] as num?)?.toInt() ?? 0;
      _inflight.removeWhere((b) => b.seq <= ackSeq);
    } else {
      // A new room (first connect, or the server restarted it): merge our unsaved edits into its state.
      final inflightOps = [for (final b in _inflight) ...b.ops];
      final base = ConfigSyncEngine.applyOps(_confirmed, inflightOps);
      final pending = [...inflightOps, ..._unsent];
      final mapped = ConfigSyncEngine.diff(base, serverDoc, _newKey).keys;
      final keyMap = <String, String>{for (var j = 0; j < mapped.length; j++) mapped[j]: serverKeys[j]};
      String? tr(dynamic k) => k is String ? (keyMap[k] ?? k) : k as String?;
      final translated = pending.map((op) {
        final o = Map<String, dynamic>.from(ConfigSyncEngine.clone(op) as Map);
        if (o.containsKey('key')) o['key'] = tr(o['key']);
        if (o.containsKey('after')) o['after'] = tr(o['after']);
        final path = o['path'];
        if (path is List && path.length > 1 && path[0] == ConfigSyncEngine.fieldsKey) {
          o['path'] = [path[0], tr(path[1]), ...path.skip(2)];
        }
        return o;
      }).toList();
      _inflight.clear();
      _unsent
        ..clear()
        ..addAll(translated);
    }
    _epoch = msg['epoch']?.toString();
    _version = (msg['version'] as num?)?.toInt() ?? 0;
    _confirmed = server;
    canEdit = msg['canEdit'] != false;
    _retry = 0;
    editors = _parseEditors(msg['editors']);
    if (!canEdit) {
      _inflight.clear();
      _unsent.clear();
    }
    _local = _replayPending();
    _setStatus(canEdit ? CollabStatus.live : CollabStatus.readonly);
    _emitView('rebase');
    onPresence?.call(editors);

    for (final b in _inflight) {
      _send({'type': 'ops', 'seq': b.seq, 'ops': b.ops});
    }
    _flush();
    if (_focusKey != null) _send({'type': 'focus', 'key': _focusKey});
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      final socket = _socket;
      if (socket != null && DateTime.now().difference(_lastMessageAt) > _silenceLimit) {
        _drop(socket);
        return;
      }
      _send({'type': 'ping'});
    });
  }

  void _onOps(Map<String, dynamic> msg) {
    final version = (msg['version'] as num?)?.toInt() ?? -1;
    if (version != _version + 1) {
      // Missed something: reconnect and resync from the server's state.
      final socket = _socket;
      if (socket != null) _drop(socket);
      return;
    }
    _version = version;
    final ops = (msg['ops'] as List?) ?? const [];
    _confirmed = ConfigSyncEngine.applyOps(_confirmed, ops);
    if (msg['sid'] == sid && _inflight.isNotEmpty && _inflight.first.seq == (msg['seq'] as num?)?.toInt()) {
      _inflight.removeAt(0);
      return; // already showing it
    }
    _local = _replayPending();
    final before = lastView;
    lastView = project(_local);
    if (!ConfigSyncEngine.deepEqual(before.doc, lastView.doc) || before.keys.join(',') != lastView.keys.join(',')) {
      onView?.call(lastView, msg['sid'] == 'server' ? 'server' : 'remote', msg['user']?.toString());
    }
  }

  static String _randomId(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return String.fromCharCodes(List.generate(length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }
}
