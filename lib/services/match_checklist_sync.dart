import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'config_collab/config_collab_session.dart';
import 'config_collab/config_sync_engine.dart';

/// One live Match Checklist document: the team template, or the completion record of a match, a day
/// (`day_YYYY-MM-DD`) or the whole event (`event`).
class ChecklistRoom {
  final String id;
  final String eventKey;
  final String matchKey;
  late final ConfigCollabSession session;
  late final Future<void> ready;
  int uses = 0;
  DateTime lastRestTry = DateTime.fromMillisecondsSinceEpoch(0);
  CollabStatus status = CollabStatus.connecting;
  List<CollabEditor> editors = const [];

  ChecklistRoom(this.id, this.eventKey, this.matchKey);

  bool get isTemplate => matchKey == MatchChecklistSync.templateKey;

  /// Edits made here that the server doesn't have yet, while it can't be reached.
  bool get pendingOffline => session.hasUnsavedChanges && !session.isLive;
}

/// Keeps Match Checklist documents in sync for the whole app, so edits made offline are saved once the
/// server is reachable again even after leaving the screen or restarting the app.
///
/// Unsaved edits are stored as drafts (the server-confirmed document plus the local one) in
/// SharedPreferences. Rooms with unsaved edits stay open in the background until the server has them;
/// when the live connection can't be made but the network is up, they are saved over plain HTTP.
/// Mirrors the room/draft logic in static/js/match-checklist.js on the website.
class MatchChecklistSync extends ChangeNotifier {
  static const templateKey = '__template__';
  static const eventScopeKey = 'event';
  static const _tick = Duration(seconds: 1);
  static const _restRetry = Duration(seconds: 20);

  static final Map<ApiService, MatchChecklistSync> _instances = {};

  /// The sync for [api]'s account (one per ApiService).
  static MatchChecklistSync of(ApiService api) => _instances.putIfAbsent(api, () => MatchChecklistSync._(api));

  final ApiService api;
  final Map<String, ChecklistRoom> _rooms = {};
  Timer? _ticker;
  bool _hadPendingOffline = false;

  /// Bumped when every edit made while offline has reached the server.
  final ValueNotifier<int> offlineChangesSaved = ValueNotifier<int>(0);

  MatchChecklistSync._(this.api);

  static String roomIdFor(String eventKey, String matchKey) => matchKey == templateKey ? 'template' : '$eventKey|$matchKey';

  static String todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'day_${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Iterable<ChecklistRoom> get rooms => _rooms.values;

  int get pendingOfflineCount => _rooms.values.where((r) => r.pendingOffline).length;

  // ── Drafts ─────────────────────────────────────────────────────────────────

  String? get _draftsKey {
    final user = api.currentUser;
    if (user == null) return null;
    return 'checklist_drafts_v1_${user.teamNumber}_${user.program}_${user.id.isNotEmpty ? user.id : user.username}';
  }

  Future<Map<String, dynamic>> _readDrafts() async {
    final key = _draftsKey;
    if (key == null) return {};
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(key) ?? '{}');
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeDrafts(Map<String, dynamic> drafts) async {
    final key = _draftsKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(drafts));
    }
  }

  // Draft writes are serialized so a slow write can't overwrite a newer one.
  Future<void> _draftQueue = Future.value();

  /// Stores (or clears) a room's unsaved edits on this device.
  Future<void> persistDraft(ChecklistRoom room) {
    _draftQueue = _draftQueue.then((_) async {
      final drafts = await _readDrafts();
      final session = room.session;
      if (session.hasUnsavedChanges) {
        drafts[room.id] = {
          'eventKey': room.eventKey,
          'matchKey': room.matchKey,
          'base': session.confirmedDoc,
          'local': session.lastView.doc,
          'at': DateTime.now().millisecondsSinceEpoch,
        };
      } else if (drafts.containsKey(room.id)) {
        drafts.remove(room.id);
      } else {
        return;
      }
      await _writeDrafts(drafts);
    }).catchError((_) {});
    return _draftQueue;
  }

  /// Opens any drafts left from earlier so they save as soon as the server is reachable.
  Future<void> resumeDrafts() async {
    final drafts = await _readDrafts();
    for (final entry in drafts.entries) {
      if (_rooms.containsKey(entry.key) || entry.value is! Map) continue;
      final draft = entry.value as Map;
      final room = await acquire(draft['eventKey']?.toString() ?? '', draft['matchKey']?.toString() ?? templateKey);
      release(room);
    }
    _ensureTicker();
  }

  // ── Rooms ──────────────────────────────────────────────────────────────────

  /// Opens (or reuses) a live document, replaying any draft left on this device.
  Future<ChecklistRoom> acquire(String eventKey, String matchKey) async {
    final id = roomIdFor(eventKey, matchKey);
    final existing = _rooms[id];
    if (existing != null) {
      existing.uses++;
      await existing.ready;
      return existing;
    }
    final room = ChecklistRoom(id, eventKey, matchKey)..uses = 1;
    _rooms[id] = room;
    final isTemplate = matchKey == templateKey;
    room.session = ConfigCollabSession(
      url: api.isLoggedIn
          ? (isTemplate ? api.matchChecklistCollabUri() : api.matchChecklistCollabUri(eventKey: eventKey, matchKey: matchKey))
          : null,
      headers: () => api.webSocketHeaders,
      onView: (view, source, user) {
        unawaited(persistDraft(room));
        notifyListeners();
      },
      onStatus: (status) {
        room.status = status;
        notifyListeners();
      },
      onPresence: (editors) {
        room.editors = editors;
        notifyListeners();
      },
    );
    room.ready = () async {
      final draft = (await _readDrafts())[id];
      if (draft is Map) {
        // Unsaved edits from earlier: replay them; they merge into the server's copy on connect.
        room.session.load(_asMap(draft['base']));
        room.session.commit(_asMap(draft['local']));
      } else {
        final doc = isTemplate ? await api.fetchMatchChecklistTemplate() : await api.fetchMatchChecklist(eventKey, matchKey);
        room.session.load(doc ?? <String, dynamic>{});
      }
      room.session.connect();
      room.status = room.session.status;
    }();
    await room.ready;
    _ensureTicker();
    notifyListeners();
    return room;
  }

  /// Stops showing a room; it stays open in the background until its unsaved edits reach the server.
  void release(ChecklistRoom? room) {
    if (room == null) return;
    room.uses = room.uses > 0 ? room.uses - 1 : 0;
    _closeIfIdle(room);
  }

  void _closeIfIdle(ChecklistRoom room) {
    if (room.uses > 0 || room.session.hasUnsavedChanges) return;
    room.session.close();
    _rooms.remove(room.id);
  }

  /// Applies a change to a live document and shares it (or keeps it as a draft while offline).
  void edit(ChecklistRoom? room, void Function(Map<String, dynamic> doc) mutate) {
    if (room == null) return;
    final next = ConfigSyncEngine.cloneMap(room.session.lastView.doc);
    mutate(next);
    room.session.commit(next);
    unawaited(persistDraft(room));
    _checkOfflineState();
    notifyListeners();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(_tick, (_) => tick());
  }

  /// Housekeeping: keeps drafts current, saves over HTTP when the live connection is down but the
  /// network is up, and closes background rooms once everything in them is saved.
  @visibleForTesting
  Future<void> tick() async {
    final now = DateTime.now();
    for (final room in _rooms.values.toList()) {
      await persistDraft(room);
      final s = room.session;
      if (s.hasUnsavedChanges && !s.isLive && api.isOnline && now.difference(room.lastRestTry) > _restRetry) {
        room.lastRestTry = now;
        unawaited(_saveViaRest(room));
      }
      _closeIfIdle(room);
    }
    _checkOfflineState();
    notifyListeners();
    if (_rooms.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _saveViaRest(ChecklistRoom room) async {
    try {
      await room.session.saveViaRest<bool>(
        () => room.isTemplate ? api.fetchMatchChecklistTemplate() : api.fetchMatchChecklist(room.eventKey, room.matchKey),
        (doc) => room.isTemplate ? api.saveMatchChecklistTemplate(doc) : api.saveMatchChecklist(room.eventKey, room.matchKey, doc),
        saved: (ok) => ok,
      );
      await persistDraft(room);
      _checkOfflineState();
      notifyListeners();
    } catch (_) {
      // Still unreachable; retried later.
    }
  }

  void _checkOfflineState() {
    if (pendingOfflineCount > 0) {
      _hadPendingOffline = true;
    } else if (_hadPendingOffline && !_rooms.values.any((r) => r.session.hasUnsavedChanges)) {
      _hadPendingOffline = false;
      offlineChangesSaved.value++;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    for (final room in _rooms.values) {
      room.session.close();
    }
    _rooms.clear();
    _instances.removeWhere((_, sync) => identical(sync, this));
    super.dispose();
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return ConfigSyncEngine.cloneMap(v);
    if (v is Map) return ConfigSyncEngine.cloneMap(Map<String, dynamic>.from(v));
    return <String, dynamic>{};
  }
}
