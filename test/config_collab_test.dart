import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/config_collab/collab_socket.dart';
import 'package:obsidianscout_app/services/config_collab/config_collab_session.dart';
import 'package:obsidianscout_app/services/config_collab/config_sync_engine.dart';

/// Shared with the server and website engines (Site/Obsidianscout-Java/src/test/resources); keep in sync.
final _vectors = jsonDecode(File('test/fixtures/config-collab-vectors.json').readAsStringSync()) as Map<String, dynamic>;

KeyedDoc _keyed(dynamic json) {
  final m = json as Map<String, dynamic>;
  return KeyedDoc(Map<String, dynamic>.from(m['doc'] as Map), (m['keys'] as List).cast<String>());
}

KeyFactory _counterKeys([String prefix = 'n']) {
  var n = 0;
  return () => '$prefix${n++}';
}

Map<String, dynamic> _field(String id, [String? label]) => {'id': id, 'label': label ?? id.toUpperCase(), 'type': 'counter'};

List<String> _labels(Map<String, dynamic> doc) => [for (final f in ConfigSyncEngine.fieldsOf(doc)) (f as Map)['label'].toString()];

// ── Fake server speaking the live-editing protocol ─────────────────────────────

class _FakeSocket implements CollabSocket {
  final _FakeServer server;
  final String sid;
  final bool canEdit;
  final _controller = StreamController<dynamic>();
  bool closed = false;

  _FakeSocket(this.server, this.sid, this.canEdit);

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String text) => server.receive(this, jsonDecode(text) as Map<String, dynamic>);

  void deliver(Map<String, dynamic> msg) {
    if (!closed) _controller.add(jsonEncode(msg));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    server.clients.remove(this);
    await _controller.close();
  }
}

class _FakeServer {
  int _n = 0;
  String epoch = 'e1';
  late KeyedDoc state;
  int version = 0;
  final Map<String, int> ack = {};
  final Set<_FakeSocket> clients = {};
  bool reachable = true;
  bool readOnly = false;

  _FakeServer(Map<String, dynamic> doc) {
    state = ConfigSyncEngine.keyed(doc, () => '~${_n++}');
  }

  CollabSocket connect(Uri uri, Map<String, String> headers) {
    if (!reachable) throw const SocketException('unreachable');
    final socket = _FakeSocket(this, uri.queryParameters['sid']!, !readOnly);
    clients.add(socket);
    scheduleMicrotask(() => socket.deliver({
          'type': 'init', 'proto': 1, 'epoch': epoch, 'version': version, 'doc': state.doc, 'keys': state.keys,
          'ackSeq': ack[socket.sid] ?? 0, 'canEdit': socket.canEdit, 'sid': socket.sid, 'editors': [],
        }));
    return socket;
  }

  void receive(_FakeSocket socket, Map<String, dynamic> msg) {
    if (msg['type'] != 'ops') return;
    final seq = (msg['seq'] as num).toInt();
    if (!socket.canEdit) {
      socket.deliver({'type': 'reject', 'seq': seq, 'reason': 'read only'});
      return;
    }
    final ops = msg['ops'] as List;
    state = ConfigSyncEngine.applyOps(state, ops);
    version++;
    ack[socket.sid] = seq;
    for (final c in clients.toList()) {
      c.deliver({'type': 'ops', 'version': version, 'sid': socket.sid, 'seq': seq, 'user': socket.sid, 'ops': ops});
    }
  }

  void restart(Map<String, dynamic> doc) {
    for (final c in clients.toList()) {
      c.close();
    }
    epoch = 'e${Random().nextInt(1 << 30)}';
    _n = 1000;
    state = ConfigSyncEngine.keyed(doc, () => '~${_n++}');
    ack.clear();
  }
}

ConfigCollabSession _session(_FakeServer server, {List<String>? notices}) => ConfigCollabSession(
      url: Uri.parse('wss://test/api/config-collab/team/game'),
      socketFactory: server.connect,
      onNotice: (_, m) => notices?.add(m),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  group('engine matches the server and website', () {
    test('apply vectors', () {
      for (final c in (_vectors['apply'] as List).cast<Map<String, dynamic>>()) {
        final out = ConfigSyncEngine.applyOps(_keyed(c['state']), c['ops'] as List);
        final expect_ = _keyed(c['expect']);
        expect(ConfigSyncEngine.deepEqual(out.doc, expect_.doc), isTrue, reason: '${c['name']}: ${jsonEncode(out.doc)}');
        expect(out.keys, expect_.keys, reason: c['name'] as String);
      }
    });

    test('diff vectors', () {
      for (final c in (_vectors['diff'] as List).cast<Map<String, dynamic>>()) {
        final out = ConfigSyncEngine.diff(_keyed(c['base']), Map<String, dynamic>.from(c['target'] as Map), _counterKeys());
        expect(ConfigSyncEngine.deepEqual(out.ops, c['ops']), isTrue, reason: '${c['name']}: ${jsonEncode(out.ops)}');
        expect(out.keys, (c['keys'] as List).cast<String>(), reason: c['name'] as String);
      }
    });

    test('diff round-trips random edits', () {
      final rnd = Random(7);
      for (var it = 0; it < 300; it++) {
        final fields = [
          for (var i = 0; i < rnd.nextInt(7); i++) {'id': 'f$i', 'label': 'L${rnd.nextInt(3)}', 'type': 'counter', if (rnd.nextBool()) 'min': rnd.nextInt(3)}
        ];
        final base = ConfigSyncEngine.keyed({'title': 'T', 'fields': fields}, _counterKeys('k'));
        final next = ConfigSyncEngine.cloneMap(base.doc);
        final list = next['fields'] as List;
        for (var m = rnd.nextInt(5); m > 0; m--) {
          switch (rnd.nextInt(4)) {
            case 0:
              list.insert(rnd.nextInt(list.length + 1), _field('n${rnd.nextInt(50)}'));
            case 1:
              if (list.isNotEmpty) list.removeAt(rnd.nextInt(list.length));
            case 2:
              if (list.length > 1) list.insert(rnd.nextInt(list.length), list.removeAt(rnd.nextInt(list.length)));
            default:
              if (list.isNotEmpty) (list[rnd.nextInt(list.length)] as Map)['label'] = 'E${rnd.nextInt(9)}';
          }
        }
        final out = ConfigSyncEngine.diff(base, next, _counterKeys('x'));
        final applied = ConfigSyncEngine.applyOps(base, out.ops);
        expect(ConfigSyncEngine.deepEqual(applied.doc, next), isTrue, reason: 'iteration $it');
        expect(applied.keys, out.keys);
      }
    });
  });

  group('live session', () {
    test('two editors see each other and both edits survive', () async {
      final server = _FakeServer({'title': 'T', 'fields': [_field('a'), _field('b')]});
      final alice = _session(server)..connect();
      final bob = _session(server)..connect();
      await _settle();
      expect(alice.status, CollabStatus.live);

      final a = alice.lastView.doc;
      alice.commit({...a, 'fields': [{...(a['fields'] as List)[0] as Map<String, dynamic>, 'label': 'Alpha'}, (a['fields'] as List)[1]]});
      final b = bob.lastView.doc;
      bob.commit({...b, 'fields': [(b['fields'] as List)[0], {...(b['fields'] as List)[1] as Map<String, dynamic>, 'label': 'Bravo'}, _field('c')]});
      await _settle();

      expect(_labels(server.state.doc), ['Alpha', 'Bravo', 'C']);
      expect(_labels(alice.lastView.doc), ['Alpha', 'Bravo', 'C']);
      expect(_labels(bob.lastView.doc), ['Alpha', 'Bravo', 'C']);
      expect(alice.hasUnsavedChanges, isFalse);
      alice.close();
      bob.close();
    });

    test('unsaved edits merge into a restarted room without duplicate fields', () async {
      final server = _FakeServer({'fields': [_field('a'), _field('b')]});
      final ed = _session(server)..connect();
      await _settle();
      server.reachable = false;
      for (final c in server.clients.toList()) {
        await c.close();
      }
      await _settle();
      expect(ed.isLive, isFalse);

      final v = ed.lastView.doc;
      final fields = v['fields'] as List;
      ed.commit({...v, 'fields': [fields[0], {...fields[1] as Map<String, dynamic>, 'label': 'Bee'}, _field('c')]});

      server.restart({'fields': [_field('a'), _field('b'), _field('z')]});
      server.reachable = true;
      ed.reconnectNow();
      await _settle();
      expect(_labels(server.state.doc), ['A', 'Bee', 'C', 'Z']);
      expect(_labels(ed.lastView.doc), ['A', 'Bee', 'C', 'Z']);
      ed.close();
    });

    test('view-only editors cannot change the config', () async {
      final server = _FakeServer({'title': 'T', 'fields': []})..readOnly = true;
      final notices = <String>[];
      final ed = _session(server, notices: notices)..connect();
      await _settle();
      expect(ed.status, CollabStatus.readonly);
      ed.commit({...ed.lastView.doc, 'title': 'Nope'});
      await _settle();
      expect(server.state.doc['title'], 'T');
      expect(ed.lastView.doc['title'], 'T');
      expect(notices, isNotEmpty);
      ed.close();
    });

    test('REST fallback merges with changes saved elsewhere and keeps edits if the save failed', () async {
      final ed = ConfigCollabSession(url: null);
      final v = ed.load({'title': 'T', 'fields': [_field('a'), _field('b')]}).doc;
      final fields = v['fields'] as List;
      ed.commit({...v, 'fields': [{...fields[0] as Map<String, dynamic>, 'label': 'Alpha'}, fields[1]]});

      // Offline: the save only reached the local cache, so the edit stays pending.
      await ed.saveViaRest(() async => {'title': 'T', 'fields': [_field('a'), _field('b')]}, (doc) async => false, saved: (ok) => ok);
      expect(ed.hasUnsavedChanges, isTrue);

      Map<String, dynamic>? stored;
      await ed.saveViaRest(
        () async => {'title': 'Theirs', 'fields': [_field('a'), _field('b'), _field('c')]},
        (doc) async {
          stored = doc;
          return true;
        },
        saved: (ok) => ok,
      );
      expect(stored!['title'], 'Theirs');
      expect(_labels(stored!), ['Alpha', 'B', 'C']);
      expect(ed.hasUnsavedChanges, isFalse);
    });

    test('projection leaves unknown properties and hidden fields alone', () {
      final ed = ConfigCollabSession(
        url: null,
        projectField: (f) => f['id'] == 'hidden' ? null : {'id': f['id'], 'label': f['label']},
        projectRest: (d) => {'title': d['title'] ?? 'Default'},
      );
      final view = ed.load({'secret': 1, 'fields': [_field('a'), {'id': 'hidden', 'label': 'H'}, _field('b')]});
      expect(view.doc, {'title': 'Default', 'fields': [{'id': 'a', 'label': 'A'}, {'id': 'b', 'label': 'B'}]});
      ed.commit({'title': 'Default', 'fields': [{'id': 'b', 'label': 'B'}, {'id': 'a', 'label': 'A2'}]});
      expect(ed.localDoc['secret'], 1);
      expect([for (final f in ed.localDoc['fields'] as List) (f as Map)['id']], ['b', 'a', 'hidden']);
      final a = (ed.localDoc['fields'] as List).firstWhere((f) => (f as Map)['id'] == 'a') as Map;
      expect(a['label'], 'A2');
      expect(a['type'], 'counter');
    });
  });
}
