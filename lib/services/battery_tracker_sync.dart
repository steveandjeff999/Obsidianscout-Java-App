import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'config_collab/config_collab_session.dart';
import 'config_collab/config_sync_engine.dart';

/// One live Battery Tracker document: the team's battery inventory ([eventKey] empty) or one event's
/// rotation plan (skips, pins and the batteries actually used).
class BatteryRoom {
  final String id;
  final String eventKey;
  late final ConfigCollabSession session;
  late final Future<void> ready;
  int uses = 0;
  DateTime lastRestTry = DateTime.fromMillisecondsSinceEpoch(0);
  CollabStatus status = CollabStatus.connecting;
  List<CollabEditor> editors = const [];

  BatteryRoom(this.id, this.eventKey);

  bool get isInventory => eventKey.isEmpty;

  Map<String, dynamic> get doc => session.lastView.doc;

  /// Edits made here that the server doesn't have yet, while it can't be reached.
  bool get pendingOffline => session.hasUnsavedChanges && !session.isLive;
}

/// Keeps Battery Tracker documents in sync for the whole app, the same way [MatchChecklistSync] does for
/// checklists: unsaved edits are kept as drafts in SharedPreferences and saved once the server is reachable
/// (live, or over plain HTTP when only that works). Used by the Battery Tracker and Match Checklist screens.
/// Mirrors static/js/services/collab-rooms.js on the website.
class BatteryTrackerSync extends ChangeNotifier {
  static const _tick = Duration(seconds: 1);
  static const _restRetry = Duration(seconds: 20);

  static final Map<ApiService, BatteryTrackerSync> _instances = {};

  /// The sync for [api]'s account (one per ApiService).
  static BatteryTrackerSync of(ApiService api) => _instances.putIfAbsent(api, () => BatteryTrackerSync._(api));

  final ApiService api;
  final Map<String, BatteryRoom> _rooms = {};
  Timer? _ticker;
  bool _hadPendingOffline = false;

  /// Bumped when every edit made while offline has reached the server.
  final ValueNotifier<int> offlineChangesSaved = ValueNotifier<int>(0);

  BatteryTrackerSync._(this.api);

  static String roomIdFor(String eventKey) => eventKey.isEmpty ? 'inventory' : 'event|$eventKey';

  Iterable<BatteryRoom> get rooms => _rooms.values;

  int get pendingOfflineCount => _rooms.values.where((r) => r.pendingOffline).length;

  // ── Drafts ─────────────────────────────────────────────────────────────────

  String? get _draftsKey {
    final user = api.currentUser;
    if (user == null) return null;
    return 'battery_drafts_v1_${user.teamNumber}_${user.program}_${user.id.isNotEmpty ? user.id : user.username}';
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
  Future<void> persistDraft(BatteryRoom room) {
    _draftQueue = _draftQueue.then((_) async {
      final drafts = await _readDrafts();
      final session = room.session;
      if (session.hasUnsavedChanges) {
        drafts[room.id] = {
          'eventKey': room.eventKey,
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
      final room = await acquire(draft['eventKey']?.toString() ?? '');
      release(room);
    }
    _ensureTicker();
  }

  // ── Rooms ──────────────────────────────────────────────────────────────────

  /// Opens (or reuses) the inventory (empty [eventKey]) or an event's plan, replaying any local draft.
  Future<BatteryRoom> acquire(String eventKey) async {
    final id = roomIdFor(eventKey);
    final existing = _rooms[id];
    if (existing != null) {
      existing.uses++;
      await existing.ready;
      return existing;
    }
    final room = BatteryRoom(id, eventKey)..uses = 1;
    _rooms[id] = room;
    room.session = ConfigCollabSession(
      url: api.isLoggedIn ? api.batteryTrackerCollabUri(eventKey: eventKey) : null,
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
        final doc = eventKey.isEmpty ? await api.fetchBatteryInventory() : await api.fetchBatteryPlan(eventKey);
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
  void release(BatteryRoom? room) {
    if (room == null) return;
    room.uses = room.uses > 0 ? room.uses - 1 : 0;
    _closeIfIdle(room);
  }

  void _closeIfIdle(BatteryRoom room) {
    if (room.uses > 0 || room.session.hasUnsavedChanges) return;
    room.session.close();
    _rooms.remove(room.id);
    if (_rooms.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Applies a change to a live document and shares it (or keeps it as a draft while offline).
  void edit(BatteryRoom? room, void Function(Map<String, dynamic> doc) mutate) {
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

  Future<void> _saveViaRest(BatteryRoom room) async {
    try {
      await room.session.saveViaRest<bool>(
        () => room.isInventory ? api.fetchBatteryInventory() : api.fetchBatteryPlan(room.eventKey),
        (doc) => room.isInventory ? api.saveBatteryInventory(doc) : api.saveBatteryPlan(room.eventKey, doc),
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
