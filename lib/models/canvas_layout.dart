/// Canvas scouting forms: the layout model shared by the scout form and the config editor.
///
/// A match config may carry an optional `layout` next to its `fields` (designed on the website or in the app):
///
/// ```json
/// "layout": {
///   "mode": "canvas",             // "classic" (the normal list form) or "canvas"
///   "width": 1280, "height": 720, // design size in canvas units; the canvas scales to fit the screen
///   "showUnplaced": true,         // list fields that aren't on the canvas below it
///   "allowClassicToggle": true,   // scouts may switch to the classic list on their own device
///   "pages": [{ "id": "p1", "name": "Auto", "phase": "auto",
///               "background": { "color": "#1b1a17", "image": "/api/blobs/<uuid>", "fit": "contain" },
///               "elements": [{ "id": "e1", "type": "button", "x": 40, "y": 60, "w": 160, "h": 90, ... }] }]
/// }
/// ```
///
/// This mirrors the website's `js/components/canvas-form.js`; keep the two in step. Layouts stay plain maps so keys
/// this version doesn't know about survive a round trip. The fields remain the source of truth for what gets
/// collected; the layout only says where widgets and tap buttons sit.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'config_models.dart';

const int kCanvasDefaultWidth = 1280;
const int kCanvasDefaultHeight = 720;

const List<String> kCanvasElementTypes = ['button', 'field', 'text', 'image', 'shape', 'value'];
const List<String> kCanvasPhases = ['auto', 'teleop', 'endgame', 'postmatch'];

/// Field types a canvas button can drive.
const Set<String> kCanvasButtonFieldTypes = {'counter', 'number', 'rating', 'checkbox', 'select', 'text', 'textarea'};
const Set<String> _numericTypes = {'counter', 'number', 'rating'};

final RegExp _imageSrc = RegExp(
    r'^(/api/blobs/[0-9a-f-]{36}|data:image/(png|jpeg|webp|gif);base64,[A-Za-z0-9+/=]+)$');
final RegExp _hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');
final math.Random _rng = math.Random();

class CanvasSizePreset {
  final String label;
  final int width;
  final int height;
  const CanvasSizePreset(this.label, this.width, this.height);
}

const List<CanvasSizePreset> kCanvasSizePresets = [
  CanvasSizePreset('Landscape 16:9 (1280 x 720)', 1280, 720),
  CanvasSizePreset('Tablet 4:3 (1024 x 768)', 1024, 768),
  CanvasSizePreset('Phone portrait (720 x 1280)', 720, 1280),
  CanvasSizePreset('Tall scroll (1280 x 1600)', 1280, 1600),
];

String canvasUid(String prefix) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return '${prefix}_${List.generate(7, (_) => chars[_rng.nextInt(chars.length)]).join()}';
}

double canvasNum(dynamic v, double dflt, double lo, double hi) {
  final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  if (n == null || !n.isFinite) return dflt;
  return math.min(hi, math.max(lo, n));
}

bool _isMap(dynamic v) => v is Map;

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// A `/api/blobs/<uuid>` URL or a small embedded image; anything else is dropped.
String canvasSafeSrc(dynamic src) => src is String && _imageSrc.hasMatch(src) ? src : '';

/// `#rgb` / `#rrggbb` only.
String? canvasSafeHex(dynamic c) {
  if (c is! String) return null;
  final s = c.trim();
  return _hex.hasMatch(s) ? s : null;
}

/// A colour from a hex string, or [fallback] when it isn't one.
Color canvasColor(dynamic hex, Color fallback, {double opacity = 1.0}) {
  final s = canvasSafeHex(hex);
  if (s == null) return fallback.withValues(alpha: fallback.a * opacity);
  var h = s.substring(1);
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final n = int.parse(h, radix: 16);
  return Color(0xFF000000 | n).withValues(alpha: opacity.clamp(0.0, 1.0));
}

String canvasHexOf(Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  return '#${[ch(c.r), ch(c.g), ch(c.b)].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
}

Map<String, dynamic> normalizeCanvasElement(Map<String, dynamic> raw, int w, int h) {
  final el = Map<String, dynamic>.from(raw);
  el['id'] = raw['id'] is String && (raw['id'] as String).isNotEmpty ? raw['id'] : canvasUid('el');
  el['type'] = kCanvasElementTypes.contains(raw['type']) ? raw['type'] : 'shape';
  final ew = canvasNum(raw['w'], 160, 8, w.toDouble()).round();
  final eh = canvasNum(raw['h'], 80, 8, h.toDouble()).round();
  el['w'] = ew;
  el['h'] = eh;
  el['x'] = canvasNum(raw['x'], 0, -ew + 8.0, w - 8.0).round();
  el['y'] = canvasNum(raw['y'], 0, -eh + 8.0, h - 8.0).round();
  el['style'] = _asMap(raw['style']);
  return el;
}

Map<String, dynamic> normalizeCanvasPage(Map<String, dynamic> raw, int index, int w, int h) {
  final page = Map<String, dynamic>.from(raw);
  page['id'] = raw['id'] is String && (raw['id'] as String).isNotEmpty ? raw['id'] : canvasUid('page');
  page['name'] = raw['name'] is String && (raw['name'] as String).trim().isNotEmpty ? raw['name'] : 'Page ${index + 1}';
  page['phase'] = kCanvasPhases.contains(raw['phase']) ? raw['phase'] : '';
  page['background'] = _asMap(raw['background']);
  page['elements'] = [
    for (final e in (raw['elements'] is List ? raw['elements'] as List : const []))
      if (_isMap(e)) normalizeCanvasElement(_asMap(e), w, h),
  ];
  return page;
}

/// A layout with every value in range. Unknown keys are kept so newer layouts survive a round trip.
Map<String, dynamic> normalizeCanvasLayout(dynamic raw) {
  final l = _asMap(raw);
  final width = canvasNum(l['width'], kCanvasDefaultWidth.toDouble(), 200, 4000).round();
  final height = canvasNum(l['height'], kCanvasDefaultHeight.toDouble(), 200, 6000).round();
  final rawPages = l['pages'] is List ? l['pages'] as List : const [];
  final pages = <Map<String, dynamic>>[];
  for (final p in rawPages) {
    if (_isMap(p)) pages.add(normalizeCanvasPage(_asMap(p), pages.length, width, height));
  }
  return {
    ...l,
    'mode': l['mode'] == 'canvas' ? 'canvas' : 'classic',
    'width': width,
    'height': height,
    'showUnplaced': l['showUnplaced'] != false,
    'allowClassicToggle': l['allowClassicToggle'] != false,
    'pages': pages,
  };
}

/// True when [layout] asks scouts to see a canvas and has something to show.
bool canvasIsActive(Map<String, dynamic>? layout) {
  if (layout == null) return false;
  final l = normalizeCanvasLayout(layout);
  return l['mode'] == 'canvas' && (l['pages'] as List).isNotEmpty;
}

List<Map<String, dynamic>> canvasPages(Map<String, dynamic> layout) =>
    (layout['pages'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();

List<Map<String, dynamic>> canvasElements(Map<String, dynamic> page) =>
    (page['elements'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();

/// Deep copy through JSON-shaped values, so edits never touch the original.
Map<String, dynamic> canvasClone(Map<String, dynamic> m) => _cloneValue(m) as Map<String, dynamic>;

dynamic _cloneValue(dynamic v) {
  if (v is Map) return {for (final e in v.entries) e.key.toString(): _cloneValue(e.value)};
  if (v is List) return [for (final e in v) _cloneValue(e)];
  return v;
}

/// Actions a button can take on a field of this type; the first is the default.
List<String> canvasActionsFor(String? fieldType) {
  final type = (fieldType ?? '').toLowerCase();
  if (_numericTypes.contains(type)) return const ['increment', 'decrement', 'set'];
  if (type == 'checkbox') return const ['toggle', 'set'];
  if (type == 'select') return const ['set', 'cycle'];
  if (type == 'text' || type == 'textarea') return const ['set'];
  return const [];
}

const Map<String, String> kCanvasActionLabels = {
  'increment': 'Add to it (+)',
  'decrement': 'Take away from it (-)',
  'set': 'Set it to one answer',
  'toggle': 'Tick / untick it',
  'cycle': 'Go to the next answer',
};

String canvasActionOf(Map<String, dynamic> el, ScoutingFieldModel? field) {
  final allowed = canvasActionsFor(field?.type);
  final a = el['action'];
  return allowed.contains(a) ? a as String : (allowed.isEmpty ? '' : allowed.first);
}

String canvasFieldLabel(ScoutingFieldModel? field) => field == null ? '' : (field.label.isNotEmpty ? field.label : field.id);

String canvasDefaultButtonLabel(Map<String, dynamic> el, ScoutingFieldModel? field) {
  if (field == null) return 'Button';
  final action = canvasActionOf(el, field);
  final name = canvasFieldLabel(field);
  final amount = el['amount'] ?? field.step ?? 1;
  switch (action) {
    case 'increment':
      return '+$amount $name';
    case 'decrement':
      return '-$amount $name';
    case 'toggle':
    case 'cycle':
      return name;
    case 'set':
      if (field.type == 'select') {
        final opt = field.options.where((o) => o.value == '${el['value']}').firstOrNull;
        return opt != null ? (opt.label.isNotEmpty ? opt.label : opt.value) : name;
      }
      if (field.type == 'checkbox') return '$name: ${'${el['value']}' == 'false' ? 'No' : 'Yes'}';
      return '$name = ${el['value'] ?? ''}';
  }
  return name;
}

/// The label a button shows: its own text (an empty string means no label) or one made from its action.
String canvasButtonLabel(Map<String, dynamic> el, ScoutingFieldModel? field) {
  final label = el['label'];
  if (label is String) return label;
  return canvasDefaultButtonLabel(el, field);
}

bool _truthy(dynamic v) => v == true || v == 1 || v == 'true';

/// The new value for [field] after a tap on button [el], or null when the tap does nothing.
/// [current] is the field's current value in the form.
({dynamic value})? canvasApplyAction(Map<String, dynamic> el, ScoutingFieldModel? field, dynamic current) {
  if (field == null) return null;
  final type = field.type.toLowerCase();
  final action = canvasActionOf(el, field);
  if (action.isEmpty) return null;

  if (type == 'checkbox') {
    return (value: action == 'toggle' ? !_truthy(current) : '${el['value']}' != 'false');
  }
  if (_numericTypes.contains(type)) {
    final floor = (field.min ?? (type == 'rating' ? 1 : 0)).toDouble();
    final ceil = field.max?.toDouble() ?? double.infinity;
    final cur = current is num ? current.toDouble() : (double.tryParse('${current ?? ''}') ?? 0);
    final rawAmount = el['amount'] is num ? (el['amount'] as num).toDouble() : double.tryParse('${el['amount'] ?? ''}');
    final amount = (rawAmount != null && rawAmount != 0 ? rawAmount : (field.step ?? 1).toDouble()).abs();
    double next;
    if (action == 'increment') {
      next = cur + amount;
    } else if (action == 'decrement') {
      next = cur - amount;
    } else {
      next = el['value'] is num ? (el['value'] as num).toDouble() : (double.tryParse('${el['value'] ?? ''}') ?? 0);
    }
    final clamped = math.min(ceil, math.max(floor, next));
    return (value: clamped == clamped.roundToDouble() ? clamped.toInt() : clamped);
  }
  if (type == 'select') {
    final options = field.options;
    if (options.isEmpty) return null;
    if (action == 'cycle') {
      final idx = options.indexWhere((o) => o.value == '${current ?? ''}');
      return (value: options[(idx + 1) % options.length].value);
    }
    final want = '${el['value']}';
    if (!options.any((o) => o.value == want)) return null;
    return (value: want);
  }
  return (value: el['value'] == null ? '' : '${el['value']}');
}

/// What a value element or button badge shows for a field.
String canvasDisplayValue(ScoutingFieldModel field, dynamic v) {
  if (v == null || v == '') return field.type == 'counter' ? '0' : '-';
  if (field.type == 'checkbox') return _truthy(v) ? 'Yes' : 'No';
  if (field.type == 'select') {
    final opt = field.options.where((o) => o.value == '$v').firstOrNull;
    return opt != null ? (opt.label.isNotEmpty ? opt.label : opt.value) : '$v';
  }
  if (v is double && v == v.roundToDouble()) return v.toInt().toString();
  return '$v';
}

/// Whether a button shows as "on" (a set/toggle button whose answer is the current one).
bool canvasButtonIsOn(Map<String, dynamic> el, ScoutingFieldModel? field, dynamic v) {
  if (field == null) return false;
  final action = canvasActionOf(el, field);
  if (field.type == 'checkbox') {
    return action == 'toggle' ? _truthy(v) : (_truthy(v) == ('${el['value']}' != 'false'));
  }
  if (action == 'set') return '${v ?? ''}' == '${el['value'] ?? ''}';
  return false;
}

/// The phase a field belongs to: its own phase, else its id prefix, else teleop (same rule as the scout pages).
String canvasPhaseOf(ScoutingFieldModel f) {
  final p = (f.phase ?? '').toLowerCase().trim();
  final s = p.isNotEmpty ? p : f.id.toLowerCase();
  if (s.startsWith('post')) return 'postmatch';
  for (final ph in const ['auto', 'teleop', 'endgame']) {
    if (s.startsWith(ph)) return ph;
  }
  return 'teleop';
}

bool _isLayoutOnlyType(String type) {
  final t = type.toLowerCase();
  return t == 'section' || t == 'header' || t == 'divider';
}

/// Fields that can sit on a canvas as a widget.
List<ScoutingFieldModel> canvasPlaceableFields(List<ScoutingFieldModel> fields) =>
    fields.where((f) => f.id.isNotEmpty && !_isLayoutOnlyType(f.type)).toList();

/// Pages built from the form's fields, one per match phase, with every field's widget placed in columns.
/// Returns the new layout (the size may grow taller to fit).
Map<String, dynamic> canvasGenerateFromFields(Map<String, dynamic> layout, List<ScoutingFieldModel> fields) {
  final l = normalizeCanvasLayout(layout);
  const heights = {'counter': 120, 'select': 110, 'rating': 110, 'checkbox': 70, 'timer': 150, 'textarea': 180, 'notes': 180, 'image': 280, 'photo': 280, 'image_upload': 280};
  const names = {'auto': 'Auto', 'teleop': 'Teleop', 'endgame': 'Endgame', 'postmatch': 'Post match'};
  final w = l['width'] as int;
  var height = l['height'] as int;
  final cols = w >= 1000 ? 3 : (w >= 640 ? 2 : 1);
  const gap = 20;
  final colW = ((w - gap * (cols + 1)) / cols).floor();
  var maxBottom = 0;
  final pages = <Map<String, dynamic>>[];
  for (final phase in kCanvasPhases) {
    final list = canvasPlaceableFields(fields).where((f) => canvasPhaseOf(f) == phase).toList();
    if (list.isEmpty) continue;
    final colY = List<int>.filled(cols, gap);
    final elements = <Map<String, dynamic>>[];
    for (final f in list) {
      var c = 0;
      for (var i = 1; i < cols; i++) {
        if (colY[i] < colY[c]) c = i;
      }
      final hh = heights[f.type.toLowerCase()] ?? 110;
      elements.add({'id': canvasUid('el'), 'type': 'field', 'fieldId': f.id, 'x': gap + c * (colW + gap), 'y': colY[c], 'w': colW, 'h': hh, 'style': <String, dynamic>{}});
      colY[c] += hh + gap;
      maxBottom = math.max(maxBottom, colY[c]);
    }
    pages.add({'id': canvasUid('page'), 'name': names[phase], 'phase': phase, 'background': <String, dynamic>{}, 'elements': elements});
  }
  if (pages.isEmpty) {
    pages.add({'id': canvasUid('page'), 'name': 'Page 1', 'phase': '', 'background': <String, dynamic>{}, 'elements': <Map<String, dynamic>>[]});
  }
  if (maxBottom > height) height = math.min(6000, (maxBottom / 10).ceil() * 10);
  return normalizeCanvasLayout({...l, 'height': height, 'pages': pages});
}

/// Ids of fields placed as a widget anywhere in the layout (each field can be placed once).
Set<String> canvasPlacedFieldIds(Map<String, dynamic> layout) => {
      for (final p in canvasPages(layout))
        for (final e in canvasElements(p))
          if (e['type'] == 'field' && e['fieldId'] is String) e['fieldId'] as String,
    };

/// Index of the page that holds [fieldId] (as a widget, else as a button target), or -1.
int canvasPageOfField(Map<String, dynamic> layout, String fieldId) {
  final pages = canvasPages(layout);
  for (var i = 0; i < pages.length; i++) {
    if (canvasElements(pages[i]).any((e) => e['type'] == 'field' && e['fieldId'] == fieldId)) return i;
  }
  for (var i = 0; i < pages.length; i++) {
    if (canvasElements(pages[i]).any((e) => e['fieldId'] == fieldId)) return i;
  }
  return -1;
}
