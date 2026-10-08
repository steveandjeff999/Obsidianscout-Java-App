import 'dart:convert';

/// Operation engine for live config editing.
///
/// The same rules are implemented by the server (ConfigSyncEngine.kt) and the website
/// (static/js/services/config-collab.js); test/fixtures/config-collab-vectors.json checks that all three agree.
///
/// A document is a config JSON object whose `fields` entries are addressed by per-room keys, so edits to
/// different fields — or different properties of one field — made at the same time merge instead of
/// overwriting each other.
///
/// Ops:
///   {"op":"set","path":[...],"value":V}      top-level path, or ["fields", key, ...props]
///   {"op":"unset","path":[...]}
///   {"op":"insert","key":K,"after":K|null,"value":V}
///   {"op":"delete","key":K}
///   {"op":"move","key":K,"after":K|null}
/// Ops that reference a key that no longer exists are no-ops; `after` pointing at a missing key means "at the end".
class KeyedDoc {
  final Map<String, dynamic> doc;
  final List<String> keys;

  const KeyedDoc(this.doc, this.keys);

  List<dynamic> get fields => ConfigSyncEngine.fieldsOf(doc);
}

class DiffResult {
  final List<Map<String, dynamic>> ops;
  final List<String> keys;

  const DiffResult(this.ops, this.keys);
}

typedef KeyFactory = String Function();

class ConfigSyncEngine {
  static const fieldsKey = 'fields';

  ConfigSyncEngine._();

  static List<dynamic> fieldsOf(Map<String, dynamic>? doc) {
    final f = doc?[fieldsKey];
    return f is List ? f : const [];
  }

  static Map<String, dynamic> ensureFields(Map<String, dynamic> doc) {
    if (doc[fieldsKey] is List) return doc;
    return {...doc, fieldsKey: <dynamic>[]};
  }

  static KeyedDoc keyed(Map<String, dynamic> doc, KeyFactory newKey) {
    final d = ensureFields(cloneMap(doc));
    return KeyedDoc(d, [for (final _ in fieldsOf(d)) newKey()]);
  }

  // ── Applying ───────────────────────────────────────────────────────────────

  static KeyedDoc applyOps(KeyedDoc state, Iterable<dynamic> ops) {
    var s = state;
    for (final op in ops) {
      s = applyOp(s, op);
    }
    return s;
  }

  static KeyedDoc applyOp(KeyedDoc state, dynamic op) {
    if (op is! Map) return state;
    final keys = state.keys;
    final fields = state.fields;
    switch (op['op']) {
      case 'set':
      case 'unset':
        final unset = op['op'] == 'unset';
        final rawPath = op['path'];
        final path = rawPath is List ? rawPath.whereType<String>().toList() : <String>[];
        if (path.isEmpty) return state;
        final value = clone(op['value']);
        if (path[0] != fieldsKey) {
          return KeyedDoc(unset ? _unsetIn(state.doc, path) : _setIn(state.doc, path, value), keys);
        }
        if (path.length < 2) return state;
        final idx = keys.indexOf(path[1]);
        if (idx < 0) return state;
        final next = List<dynamic>.of(fields);
        if (path.length == 2) {
          if (unset) return state;
          next[idx] = value;
        } else {
          final field = next[idx];
          if (field is! Map) return state;
          final rest = path.sublist(2);
          final f = Map<String, dynamic>.from(field);
          next[idx] = unset ? _unsetIn(f, rest) : _setIn(f, rest, value);
        }
        return KeyedDoc(_withFields(state.doc, next), keys);
      case 'insert':
        final key = op['key'];
        if (key is! String || keys.contains(key)) return state;
        final after = op['after'];
        final pos = _positionAfter(keys, after is String ? after : null);
        final nk = List<String>.of(keys)..insert(pos, key);
        final nf = List<dynamic>.of(fields)..insert(pos, clone(op['value']));
        return KeyedDoc(_withFields(state.doc, nf), nk);
      case 'delete':
        final idx = keys.indexOf(op['key'] is String ? op['key'] as String : '');
        if (idx < 0) return state;
        final nk = List<String>.of(keys)..removeAt(idx);
        final nf = List<dynamic>.of(fields)..removeAt(idx);
        return KeyedDoc(_withFields(state.doc, nf), nk);
      case 'move':
        final key = op['key'];
        final rawAfter = op['after'];
        final after = rawAfter is String ? rawAfter : null;
        final idx = key is String ? keys.indexOf(key) : -1;
        if (idx < 0 || after == key) return state;
        final nk = List<String>.of(keys)..removeAt(idx);
        final nf = List<dynamic>.of(fields);
        final value = nf.removeAt(idx);
        final pos = _positionAfter(nk, after);
        nk.insert(pos, key as String);
        nf.insert(pos, value);
        return KeyedDoc(_withFields(state.doc, nf), nk);
      default:
        return state;
    }
  }

  static int _positionAfter(List<String> keys, String? after) {
    if (after == null) return 0;
    final idx = keys.indexOf(after);
    return idx >= 0 ? idx + 1 : keys.length;
  }

  static Map<String, dynamic> _setIn(Map<String, dynamic> obj, List<String> path, dynamic value) {
    final out = Map<String, dynamic>.of(obj);
    final head = path[0];
    if (path.length == 1) {
      out[head] = value;
      return out;
    }
    final child = obj[head] is Map ? Map<String, dynamic>.from(obj[head] as Map) : <String, dynamic>{};
    out[head] = _setIn(child, path.sublist(1), value);
    return out;
  }

  static Map<String, dynamic> _unsetIn(Map<String, dynamic> obj, List<String> path) {
    final head = path[0];
    if (path.length == 1) {
      if (!obj.containsKey(head)) return obj;
      return Map<String, dynamic>.of(obj)..remove(head);
    }
    final child = obj[head];
    if (child is! Map) return obj;
    return Map<String, dynamic>.of(obj)..[head] = _unsetIn(Map<String, dynamic>.from(child), path.sublist(1));
  }

  static Map<String, dynamic> _withFields(Map<String, dynamic> doc, List<dynamic> fields) =>
      Map<String, dynamic>.of(doc)..[fieldsKey] = fields;

  // ── Diffing ────────────────────────────────────────────────────────────────

  /// Ops that turn [base] into [target], plus the keys of [target]'s fields (base keys where a field was
  /// matched, fresh keys from [newKey] for added fields).
  static DiffResult diff(KeyedDoc base, Map<String, dynamic> target, KeyFactory newKey) {
    final baseFields = base.fields;
    final newFields = fieldsOf(target);
    final match = matchFields(baseFields, newFields);

    final newKeys = <String>[];
    final inserted = <bool>[];
    for (var j = 0; j < newFields.length; j++) {
      if (match[j] >= 0) {
        newKeys.add(base.keys[match[j]]);
        inserted.add(false);
      } else {
        newKeys.add(newKey());
        inserted.add(true);
      }
    }

    // Order: deletes, then inserts and moves, then property changes.
    final ops = <Map<String, dynamic>>[];
    final usedBase = List<bool>.filled(baseFields.length, false);
    for (final i in match) {
      if (i >= 0) usedBase[i] = true;
    }
    for (var i = 0; i < baseFields.length; i++) {
      if (!usedBase[i]) ops.add({'op': 'delete', 'key': base.keys[i]});
    }

    // Keep the longest run of matched fields that is already in order; move the rest.
    final matchedNewIdx = [for (var j = 0; j < newFields.length; j++) if (match[j] >= 0) j];
    final stable = _longestIncreasing([for (final j in matchedNewIdx) match[j]]).map((k) => matchedNewIdx[k]).toSet();
    for (var j = 0; j < newFields.length; j++) {
      final after = j == 0 ? null : newKeys[j - 1];
      if (inserted[j]) {
        ops.add({'op': 'insert', 'key': newKeys[j], 'after': after, 'value': clone(newFields[j])});
      } else if (!stable.contains(j)) {
        ops.add({'op': 'move', 'key': newKeys[j], 'after': after});
      }
    }

    final topKeys = <String>[...base.doc.keys];
    for (final k in target.keys) {
      if (!base.doc.containsKey(k)) topKeys.add(k);
    }
    for (final k in topKeys) {
      if (k == fieldsKey) continue;
      _diffValue([k], base.doc.containsKey(k), base.doc[k], target.containsKey(k), target[k], ops);
    }
    for (var j = 0; j < newFields.length; j++) {
      if (match[j] >= 0) _diffValue([fieldsKey, newKeys[j]], true, baseFields[match[j]], true, newFields[j], ops);
    }
    return DiffResult(ops, newKeys);
  }

  static void _diffValue(List<String> path, bool hasA, dynamic a, bool hasB, dynamic b, List<Map<String, dynamic>> out) {
    if (!hasB) {
      if (hasA) out.add({'op': 'unset', 'path': path});
    } else if (!hasA) {
      out.add({'op': 'set', 'path': path, 'value': clone(b)});
    } else if (deepEqual(a, b)) {
      // unchanged
    } else if (a is Map && b is Map) {
      final keys = <String>[...a.keys.cast<String>()];
      for (final k in b.keys.cast<String>()) {
        if (!a.containsKey(k)) keys.add(k);
      }
      for (final k in keys) {
        _diffValue([...path, k], a.containsKey(k), a[k], b.containsKey(k), b[k], out);
      }
    } else {
      out.add({'op': 'set', 'path': path, 'value': clone(b)});
    }
  }

  /// For each target field, the index of the base field it corresponds to, or -1 if it was added.
  static List<int> matchFields(List<dynamic> base, List<dynamic> target) {
    final match = List<int>.filled(target.length, -1);
    final used = List<bool>.filled(base.length, false);

    // 1. Unchanged fields.
    final byContent = <String, List<int>>{};
    for (var i = 0; i < base.length; i++) {
      byContent.putIfAbsent(canonical(base[i]), () => []).add(i);
    }
    for (var j = 0; j < target.length; j++) {
      final queue = byContent[canonical(target[j])];
      while (queue != null && queue.isNotEmpty) {
        final i = queue.removeAt(0);
        if (!used[i]) {
          match[j] = i;
          used[i] = true;
          break;
        }
      }
    }
    // 2. Same field id.
    for (var j = 0; j < target.length; j++) {
      if (match[j] >= 0) continue;
      final id = _fieldId(target[j]);
      if (id == null) continue;
      for (var i = 0; i < base.length; i++) {
        if (!used[i] && _fieldId(base[i]) == id) {
          match[j] = i;
          used[i] = true;
          break;
        }
      }
    }
    // 3. Same position (an edit that also changed the id).
    for (var j = 0; j < target.length; j++) {
      if (match[j] >= 0 || j >= base.length || used[j]) continue;
      if (base[j] is Map && target[j] is Map) {
        match[j] = j;
        used[j] = true;
      }
    }
    return match;
  }

  static String? _fieldId(dynamic f) {
    if (f is! Map) return null;
    final id = f['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Indices (into [seq]) of one longest strictly increasing subsequence.
  static List<int> _longestIncreasing(List<int> seq) {
    if (seq.isEmpty) return const [];
    final tails = <int>[];
    final prev = List<int>.filled(seq.length, -1);
    for (var i = 0; i < seq.length; i++) {
      var lo = 0;
      var hi = tails.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (seq[tails[mid]] < seq[i]) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0) prev[i] = tails[lo - 1];
      if (lo == tails.length) {
        tails.add(i);
      } else {
        tails[lo] = i;
      }
    }
    final out = <int>[];
    var k = tails.last;
    while (k >= 0) {
      out.add(k);
      k = prev[k];
    }
    return out.reversed.toList();
  }

  // ── Merging ────────────────────────────────────────────────────────────────

  /// Plays [ops] (written against [base]) onto [theirs], a plain config that also descends from [base].
  /// The result stays in [base]'s key space; on a conflicting property [ops] win.
  static KeyedDoc rebase(KeyedDoc base, Map<String, dynamic> theirs, List<dynamic> ops, KeyFactory newKey) {
    final t = ensureFields(cloneMap(theirs));
    return applyOps(KeyedDoc(t, diff(base, t, newKey).keys), ops);
  }

  // ── JSON helpers ───────────────────────────────────────────────────────────

  static dynamic clone(dynamic v) {
    if (v is Map) return {for (final e in v.entries) e.key.toString(): clone(e.value)};
    if (v is List) return [for (final x in v) clone(x)];
    return v;
  }

  static Map<String, dynamic> cloneMap(Map<String, dynamic> v) => clone(v) as Map<String, dynamic>;

  static bool deepEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !deepEqual(a[k], b[k])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Order-independent text for content matching.
  static String canonical(dynamic v) {
    if (v is List) return '[${v.map(canonical).join(',')}]';
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(v[k])}').join(',')}}';
    }
    if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    return jsonEncode(v);
  }
}
