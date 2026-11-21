import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/canvas_layout.dart';
import '../models/config_models.dart';
import '../theme/obsidian_tokens.dart';
import '../theme/obsidian_ui_theme.dart';
import 'canvas_form_view.dart';
import 'obsidian_glass_card.dart';

/// Editor for a match form's canvas layout; the app's version of the website's Canvas Layout tab
/// (`js/components/canvas-form-editor.js`), producing the same layout JSON.
///
/// [layout] is the team's own layout (null = none, so the season default applies). Every change is reported
/// through [onChanged]; null there means "remove the team's layout and follow the season default".
class CanvasLayoutEditor extends StatefulWidget {
  final Map<String, dynamic>? layout;
  final List<ScoutingFieldModel> fields;
  final Map<String, dynamic>? seasonLayout;
  final int? seasonYear;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  /// Lets the admin pick an image and returns its `src` (an `/api/blobs/` URL, or an embedded image), or null
  /// when they cancel. Throws with a message the editor shows on failure.
  final Future<String?> Function() pickImage;
  final bool readOnly;

  const CanvasLayoutEditor({
    super.key,
    required this.layout,
    required this.fields,
    required this.onChanged,
    required this.pickImage,
    this.seasonLayout,
    this.seasonYear,
    this.readOnly = false,
  });

  @override
  State<CanvasLayoutEditor> createState() => _CanvasLayoutEditorState();
}

class _ElementDrag extends Drag {
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onDone;
  _ElementDrag(this.onUpdate, this.onDone);
  @override
  void update(DragUpdateDetails details) => onUpdate(details);
  @override
  void end(DragEndDetails details) => onDone();
  @override
  void cancel() => onDone();
}

class _CanvasLayoutEditorState extends State<CanvasLayoutEditor> {
  Map<String, dynamic> _layout = normalizeCanvasLayout(null);
  Map<String, dynamic>? _lastSent;
  int _page = 0;
  String? _selectedId;
  int _snap = 10;
  double _scale = 1;
  Timer? _commitTimer;
  // Bumped when a size or position changes from outside its text box, so the boxes show the new numbers
  // (but not while the admin is typing in them).
  int _sizeEpoch = 0;
  int _boxEpoch = 0;

  // Drag state (design units), so snapping doesn't lose small movements.
  double _dragX = 0, _dragY = 0, _dragW = 0, _dragH = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CanvasLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Our own changes come back as the same map; anything else (raw JSON edit, live edit, reload) is reloaded.
    if (!identical(widget.layout, _lastSent) && !identical(widget.layout, oldWidget.layout)) _load();
  }

  @override
  void dispose() {
    if (_commitTimer?.isActive ?? false) {
      _commitTimer!.cancel();
      _send();
    }
    super.dispose();
  }

  void _load() {
    _layout = normalizeCanvasLayout(widget.layout == null ? null : canvasClone(widget.layout!));
    final pages = canvasPages(_layout);
    if (_page >= pages.length) _page = math.max(0, pages.length - 1);
    if (_selected == null) _selectedId = null;
  }

  // ------------------------------------------------------------------ state helpers

  List<Map<String, dynamic>> get _pages => canvasPages(_layout);
  Map<String, dynamic>? get _currentPage => _pages.isEmpty ? null : _pages[_page];
  int get _w => _layout['width'] as int;
  int get _h => _layout['height'] as int;

  Map<String, dynamic>? get _selected {
    final p = _currentPage;
    if (p == null || _selectedId == null) return null;
    return canvasElements(p).where((e) => e['id'] == _selectedId).firstOrNull;
  }

  Map<String, ScoutingFieldModel> get _fieldsById => {for (final f in widget.fields) f.id: f};
  List<ScoutingFieldModel> get _placeable => canvasPlaceableFields(widget.fields);

  void _send() {
    final out = canvasClone(_layout);
    _lastSent = out;
    widget.onChanged(out);
  }

  /// Reports the layout: right away, or after a short pause while typing.
  void _commit({bool now = true}) {
    _commitTimer?.cancel();
    if (now) {
      _send();
    } else {
      _commitTimer = Timer(const Duration(milliseconds: 350), _send);
    }
  }

  void _change(VoidCallback fn, {bool now = true}) {
    if (widget.readOnly) return;
    setState(fn);
    _commit(now: now);
  }

  void _setOwnLayout(Map<String, dynamic>? layout) {
    _commitTimer?.cancel();
    setState(() {
      _layout = normalizeCanvasLayout(layout);
      _page = 0;
      _selectedId = null;
    });
    if (layout == null) {
      _lastSent = null;
      widget.onChanged(null);
    } else {
      _send();
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? ObsidianUITheme.errorRed : null,
    ));
  }

  Future<String?> _pick() async {
    try {
      return await widget.pickImage();
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
      return null;
    }
  }

  // ------------------------------------------------------------------ editing actions

  void _generate() {
    _change(() {
      _layout = canvasGenerateFromFields({..._layout, 'mode': 'canvas'}, widget.fields);
      _page = 0;
      _selectedId = null;
    });
  }

  void _setSize(int w, int h) {
    _change(() {
      _layout = normalizeCanvasLayout({..._layout, 'width': w.clamp(200, 4000), 'height': h.clamp(200, 6000)});
    });
  }

  void _addPage() {
    _change(() {
      final pages = _pages;
      pages.add({'id': canvasUid('page'), 'name': 'Page ${pages.length + 1}', 'phase': '', 'background': <String, dynamic>{}, 'elements': <Map<String, dynamic>>[]});
      _layout['pages'] = pages;
      _page = pages.length - 1;
      _selectedId = null;
    });
  }

  void _duplicatePage() {
    final p = _currentPage;
    if (p == null) return;
    _change(() {
      final copy = canvasClone(p)
        ..['id'] = canvasUid('page')
        ..['name'] = '${p['name']} copy';
      final els = canvasElements(copy);
      for (final e in els) {
        e['id'] = canvasUid('el');
      }
      // A field's widget can only be placed once, so the copy keeps buttons and pictures but not widgets.
      copy['elements'] = els.where((e) => e['type'] != 'field').toList();
      final pages = _pages..insert(_page + 1, copy);
      _layout['pages'] = pages;
      _page += 1;
      _selectedId = null;
    });
  }

  void _movePage(int delta) {
    final to = _page + delta;
    if (to < 0 || to >= _pages.length) return;
    _change(() {
      final pages = _pages;
      final p = pages.removeAt(_page);
      pages.insert(to, p);
      _layout['pages'] = pages;
      _page = to;
    });
  }

  Future<void> _deletePage() async {
    final p = _currentPage;
    if (p == null) return;
    final ok = await _confirm('Delete page "${p['name']}"?',
        'Everything on this page is removed from the canvas. Your fields and data are not affected.');
    if (!ok) return;
    _change(() {
      final pages = _pages..removeAt(_page);
      _layout['pages'] = pages;
      _page = math.max(0, math.min(_page, pages.length - 1));
      _selectedId = null;
    });
  }

  Map<String, dynamic>? _defaultButtonFor(ScoutingFieldModel? f) {
    if (f == null) return null;
    final action = canvasActionsFor(f.type).first;
    return {
      'fieldId': f.id,
      'action': action,
      'amount': f.step ?? 1,
      if (action == 'set') 'value': _defaultSetValue(f),
      'showValue': f.type == 'counter',
    };
  }

  dynamic _defaultSetValue(ScoutingFieldModel f) {
    if (f.type == 'select') return f.options.isNotEmpty ? f.options.first.value : '';
    if (f.type == 'checkbox') return 'true';
    if (f.type == 'text' || f.type == 'textarea') return '';
    return f.max ?? 1;
  }

  void _addElement(String type, {String? fieldId}) {
    final p = _currentPage;
    if (p == null) return;
    final sizes = {
      'button': [180, 100],
      'field': [380, 120],
      'image': [(_w * 0.6).round(), (_h * 0.6).round()],
      'text': [300, 60],
      'value': [200, 70],
      'shape': [300, 200],
    };
    final size = sizes[type]!;
    final w = math.min(size[0], _w), h = math.min(size[1], _h);
    final el = <String, dynamic>{
      'id': canvasUid('el'),
      'type': type,
      'w': w,
      'h': h,
      'x': ((_w - w) / 2 / 10).round() * 10,
      'y': ((_h - h) / 2 / 10).round() * 10,
      'style': <String, dynamic>{},
    };
    final placed = canvasPlacedFieldIds(_layout);
    if (type == 'button') {
      final f = _placeable.where((x) => kCanvasButtonFieldTypes.contains(x.type.toLowerCase())).firstOrNull;
      el.addAll(_defaultButtonFor(f) ?? {'showValue': false});
    } else if (type == 'field') {
      final f = fieldId != null ? _fieldsById[fieldId] : _placeable.where((x) => !placed.contains(x.id)).firstOrNull;
      if (f != null) el['fieldId'] = f.id;
    } else if (type == 'value') {
      final f = _placeable.firstOrNull;
      if (f != null) el['fieldId'] = f.id;
      el['prefix'] = '';
    } else if (type == 'text') {
      el['text'] = 'Label';
    }
    _change(() {
      final els = canvasElements(p)..add(normalizeCanvasElement(el, _w, _h));
      p['elements'] = els;
      _selectedId = el['id'] as String;
    });
    if (type == 'image') _pickElementImage();
  }

  Future<void> _pickElementImage() async {
    final id = _selectedId;
    final src = await _pick();
    if (src == null || !mounted) return;
    final el = _currentPage == null ? null : canvasElements(_currentPage!).where((e) => e['id'] == id).firstOrNull;
    if (el == null) return;
    _change(() => el['src'] = src);
  }

  Future<void> _pickBackground() async {
    final p = _currentPage;
    final src = await _pick();
    if (src == null || p == null || !mounted) return;
    _change(() => p['background'] = {...Map<String, dynamic>.from(p['background'] as Map), 'image': src});
  }

  void _deleteSelected() {
    final p = _currentPage;
    if (p == null || _selectedId == null) return;
    _change(() {
      p['elements'] = canvasElements(p).where((e) => e['id'] != _selectedId).toList();
      _selectedId = null;
    });
  }

  void _duplicateSelected() {
    final p = _currentPage, el = _selected;
    if (p == null || el == null) return;
    if (el['type'] == 'field') {
      _toast('A field can only be placed once. Add a button for it instead.');
      return;
    }
    _change(() {
      final copy = canvasClone(el)
        ..['id'] = canvasUid('el')
        ..['x'] = math.min((el['x'] as int) + 20, _w - 8)
        ..['y'] = math.min((el['y'] as int) + 20, _h - 8);
      p['elements'] = canvasElements(p)..add(copy);
      _selectedId = copy['id'] as String;
    });
  }

  void _reorderSelected(bool toFront) {
    final p = _currentPage, el = _selected;
    if (p == null || el == null) return;
    _change(() {
      final els = canvasElements(p)..removeWhere((e) => e['id'] == el['id']);
      toFront ? els.add(el) : els.insert(0, el);
      p['elements'] = els;
    });
  }

  Future<bool> _confirm(String title, String body) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    return res == true;
  }

  // ------------------------------------------------------------------ drag & resize

  Drag _startMove(Map<String, dynamic> el) {
    setState(() => _selectedId = el['id'] as String);
    _dragX = (el['x'] as num).toDouble();
    _dragY = (el['y'] as num).toDouble();
    return _ElementDrag((d) {
      if (widget.readOnly) return;
      _dragX += d.delta.dx / _scale;
      _dragY += d.delta.dy / _scale;
      final w = el['w'] as int, h = el['h'] as int;
      setState(() {
        el['x'] = _snapTo(_dragX).clamp(-w + 8, _w - 8);
        el['y'] = _snapTo(_dragY).clamp(-h + 8, _h - 8);
      });
    }, () {
      _boxEpoch++;
      _commit();
    });
  }

  Drag _startResize(Map<String, dynamic> el) {
    _dragW = (el['w'] as num).toDouble();
    _dragH = (el['h'] as num).toDouble();
    return _ElementDrag((d) {
      if (widget.readOnly) return;
      _dragW += d.delta.dx / _scale;
      _dragH += d.delta.dy / _scale;
      setState(() {
        el['w'] = _snapTo(_dragW).clamp(8, _w);
        el['h'] = _snapTo(_dragH).clamp(8, _h);
      });
    }, () {
      _boxEpoch++;
      _commit();
    });
  }

  int _snapTo(double v) => _snap <= 1 ? v.round() : ((v / _snap).round() * _snap);

  /// Starts a drag the moment a finger touches the element, so the page doesn't scroll instead.
  Widget _dragArea({required Drag Function() onStart, required Widget child}) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
          () => ImmediateMultiDragGestureRecognizer(),
          (r) => r.onStart = (_) => onStart(),
        ),
      },
      child: child,
    );
  }

  // ------------------------------------------------------------------ UI pieces

  Color get _text => ObsidianUITheme.getPrimaryTextColor(context);
  Color get _sub => ObsidianUITheme.getSecondaryTextColor(context);
  Color get _border => ObsidianUITheme.getBorderColor(context);

  Widget _stepHeader(int n, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ObsidianUITheme.primaryAccent, borderRadius: BorderRadius.circular(13)),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _text)),
                const SizedBox(height: 2),
                Text(hint, style: TextStyle(fontSize: 12, color: _sub, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 12, color: _sub, height: 1.35)),
      );

  Widget _segment<T>(List<(T, String)> options, T value, ValueChanged<T> onPick) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: v == value,
            onSelected: widget.readOnly ? null : (_) => onPick(v),
            selectedColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
            labelStyle: TextStyle(color: v == value ? ObsidianUITheme.primaryAccent : _text, fontWeight: FontWeight.w600, fontSize: 12.5),
            side: BorderSide(color: v == value ? ObsidianUITheme.primaryAccent : _border),
            backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          ),
      ],
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        labelStyle: TextStyle(color: _sub, fontSize: 12),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _border)),
        border: const OutlineInputBorder(),
      );

  Widget _textInput(String label, String value, ValueChanged<String> onChanged,
      {bool number = false, String? keyId, int maxLines = 1}) {
    return TextFormField(
      key: ValueKey('cfe-$keyId-$label-${_selectedId ?? _page}'),
      initialValue: value,
      enabled: !widget.readOnly,
      maxLines: maxLines,
      keyboardType: number ? const TextInputType.numberWithOptions(signed: true, decimal: true) : TextInputType.text,
      style: TextStyle(color: _text, fontSize: 13),
      decoration: _dec(label),
      onChanged: onChanged,
    );
  }

  Widget _dropdown<T>(String label, T? value, List<(T, String)> items, ValueChanged<T?> onChanged) {
    final has = items.any((i) => i.$1 == value);
    return DropdownButtonFormField<T>(
      key: ValueKey('cfe-dd-$label-${_selectedId ?? _page}-$value'),
      initialValue: has ? value : null,
      isExpanded: true,
      dropdownColor: ObsidianUITheme.getSurfaceColor(context),
      style: TextStyle(color: _text, fontSize: 13),
      decoration: _dec(label),
      items: [for (final (v, l) in items) DropdownMenuItem<T>(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
      onChanged: widget.readOnly ? null : onChanged,
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: value,
          activeThumbColor: ObsidianUITheme.primaryAccent,
          onChanged: widget.readOnly ? null : onChanged,
          title: Text(label, style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        if (hint != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(hint, style: TextStyle(fontSize: 12, color: _sub))),
      ],
    );
  }

  static const List<String> _swatches = [
    '#ffffff', '#f4f1ea', '#d9d4c7', '#9a968c', '#4a4740', '#1b1a17', '#000000',
    '#5b4ec7', '#3d7bd9', '#2aa6a1', '#2f9e44', '#e8b20c', '#f08c00', '#e03131', '#c2255c',
  ];

  Widget _colorInput(String label, dynamic current, String fallback, ValueChanged<String> onPick) {
    final hex = canvasSafeHex(current) ?? fallback;
    return InkWell(
      onTap: widget.readOnly ? null : () => _openColorPicker(label, hex, onPick),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: _dec(label),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: canvasColor(hex, Colors.white), borderRadius: BorderRadius.circular(5), border: Border.all(color: _border)),
            ),
            const SizedBox(width: 8),
            Text(hex, style: TextStyle(color: _text, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _openColorPicker(String label, String hex, ValueChanged<String> onPick) async {
    final controller = TextEditingController(text: hex);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _swatches)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, s),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: canvasColor(s, Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: s == hex ? ObsidianUITheme.primaryAccent : _border, width: s == hex ? 3 : 1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(controller: controller, decoration: _dec('Hex colour (#rrggbb)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = canvasSafeHex(controller.text.trim().startsWith('#') ? controller.text.trim() : '#${controller.text.trim()}');
              Navigator.pop(ctx, v);
            },
            child: const Text('Use'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked != null) onPick(picked);
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {int? divisions, String Function(double)? fmt}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${fmt != null ? fmt(value) : value.round()}', style: TextStyle(fontSize: 12, color: _sub)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: ObsidianUITheme.primaryAccent,
          onChanged: widget.readOnly ? null : onChanged,
          onChangeEnd: (_) => _commit(),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ sections

  Widget _seasonChoiceCard() {
    final year = widget.seasonYear;
    final yearText = year != null ? 'the $year' : "this season's";
    return ObsidianGlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your scouts are using $yearText default canvas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _text)),
          _hint("The site admins designed a canvas for the season. Teams that haven't made their own choice see it on the "
              "Scout page. Anything on it tied to a field your form doesn't have is left out, and those fields are listed "
              'under the canvas instead.'),
          const SizedBox(height: 4),
          SizedBox(
            height: 260,
            child: IgnorePointer(child: _preview(normalizeCanvasLayout(widget.seasonLayout))),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent, foregroundColor: Colors.white),
                onPressed: widget.readOnly ? null : () => _setOwnLayout(canvasClone(widget.seasonLayout!)),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Make my own copy to change'),
              ),
              OutlinedButton.icon(
                onPressed: widget.readOnly ? null : () => _setOwnLayout({'mode': 'classic', 'pages': <dynamic>[]}),
                icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                label: const Text('Design my own from my fields'),
              ),
              TextButton.icon(
                onPressed: widget.readOnly
                    ? null
                    : () {
                        _setOwnLayout({'mode': 'classic', 'pages': <dynamic>[]});
                        _toast('Your scouts now get the classic list instead of the default canvas.');
                      },
                icon: const Icon(Icons.view_list_rounded, size: 18),
                label: const Text('Use the classic list instead'),
              ),
            ],
          ),
          _hint('Staying on the default needs no action: if the site admins change it, your scouts get the update automatically.'),
        ],
      ),
    );
  }

  /// A read-only picture of a layout's first page.
  Widget _preview(Map<String, dynamic> layout) {
    final pages = canvasPages(layout);
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pages.first;
    final byId = _fieldsById;
    return CanvasScaler(
      designWidth: layout['width'] as int,
      designHeight: layout['height'] as int,
      maxHeight: 260,
      child: Stack(children: [
        Positioned.fill(child: CanvasBackground(page: page, fallbackColor: Colors.white)),
        for (final el in canvasElements(page))
          Positioned(
            left: (el['x'] as num).toDouble(),
            top: (el['y'] as num).toDouble(),
            width: (el['w'] as num).toDouble(),
            height: (el['h'] as num).toDouble(),
            child: CanvasElementVisual(el: el, field: byId[el['fieldId']], editing: true),
          ),
      ]),
    );
  }

  Widget _settingsSection() {
    final mode = _layout['mode'] as String;
    final preset = kCanvasSizePresets.where((p) => p.width == _w && p.height == _h).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(1, 'Choose what scouts see', 'Pick the classic list or your canvas, and the shape of the canvas.'),
        _segment<String>(const [('classic', 'Classic list'), ('canvas', 'Canvas layout')], mode, (v) {
          _change(() {
            _layout['mode'] = v;
            if (v == 'canvas' && _pages.isEmpty) {
              _layout = canvasGenerateFromFields(_layout, widget.fields);
              _page = 0;
            }
          });
        }),
        _hint(mode == 'canvas'
            ? 'On: the Scout page opens with this canvas. The classic list still works underneath, so saving and data are unchanged.'
            : 'Off: scouts get the normal list form. You can keep designing here; nothing changes for scouts until you pick Canvas layout.'),
        const SizedBox(height: 6),
        _dropdown<String>(
          'Canvas shape',
          preset == null ? 'custom' : '${preset.width}x${preset.height}',
          [
            ('custom', 'Custom size'),
            for (final p in kCanvasSizePresets) ('${p.width}x${p.height}', p.label),
          ],
          (v) {
            final p = kCanvasSizePresets.where((p) => '${p.width}x${p.height}' == v).firstOrNull;
            if (p != null) {
              _sizeEpoch++;
              _setSize(p.width, p.height);
            }
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _textInput('Width', '$_w', (v) {
                final n = int.tryParse(v);
                if (n != null && n >= 200) _setSize(n, _h);
              }, number: true, keyId: 'size-$_sizeEpoch'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textInput('Height', '$_h', (v) {
                final n = int.tryParse(v);
                if (n != null && n >= 200) _setSize(_w, n);
              }, number: true, keyId: 'size-$_sizeEpoch'),
            ),
          ],
        ),
        _hint('Choose the shape of the screens your scouts use. The canvas shrinks or grows to fit each screen but keeps '
            'this shape, so a landscape canvas looks small on a phone held upright.'),
        _switch("List fields that aren't on the canvas below it", _layout['showUnplaced'] != false,
            (v) => _change(() => _layout['showUnplaced'] = v),
            hint: "Recommended. Any field you haven't placed still appears in a short list under the canvas."),
        _switch('Let scouts switch to the classic list on their device', _layout['allowClassicToggle'] != false,
            (v) => _change(() => _layout['allowClassicToggle'] = v),
            hint: 'Adds a "Classic list" button on the Scout page, handy on small phones. It only changes their own screen.'),
      ],
    );
  }

  Widget _pagesSection() {
    final p = _currentPage;
    final bg = p == null ? const <String, dynamic>{} : Map<String, dynamic>.from(p['background'] as Map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(2, 'Pages', 'Pages are tabs scouts switch between, usually one per match phase. Pick a page to edit it.'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _pages.length; i++)
              ChoiceChip(
                label: Text(_pages[i]['name'] as String),
                selected: i == _page,
                onSelected: (_) => setState(() {
                  _page = i;
                  _selectedId = null;
                }),
                selectedColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                labelStyle: TextStyle(color: i == _page ? ObsidianUITheme.primaryAccent : _text, fontWeight: FontWeight.w600),
                backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                side: BorderSide(color: i == _page ? ObsidianUITheme.primaryAccent : _border),
              ),
            if (!widget.readOnly)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add page'),
                onPressed: _addPage,
                backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                side: BorderSide(color: _border),
              ),
          ],
        ),
        if (p != null) ...[
          const SizedBox(height: 12),
          _textInput('Page name', p['name'] as String, (v) => _change(() => p['name'] = v.trim().isEmpty ? 'Page' : v, now: false), keyId: 'page-name'),
          _hint('Shown on the tab above the canvas.'),
          _dropdown<String>(
            'Controller phase',
            p['phase'] as String? ?? '',
            const [('', 'None (no controller)'), ('auto', 'Auto'), ('teleop', 'Teleop'), ('endgame', 'Endgame'), ('postmatch', 'Post match')],
            (v) => _change(() => p['phase'] = v ?? ''),
          ),
          _hint("Only matters if scouts use a gamepad or keyboard: that phase's button mapping is used while this page is open."),
          Row(
            children: [
              Expanded(child: _colorInput('Background colour', bg['color'], '#ffffff', (v) => _change(() => p['background'] = {...bg, 'color': v}))),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdown<String>('Image fit', bg['fit'] as String? ?? 'contain',
                    const [('contain', 'Fit inside'), ('cover', 'Fill (crop)'), ('fill', 'Stretch')],
                    (v) => _change(() => p['background'] = {...bg, 'fit': v ?? 'contain'})),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: widget.readOnly ? null : _pickBackground,
                icon: const Icon(Icons.image_rounded, size: 18),
                label: Text(canvasSafeSrc(bg['image']).isNotEmpty ? 'Replace background image' : 'Background image'),
              ),
              if (canvasSafeSrc(bg['image']).isNotEmpty)
                TextButton.icon(
                  onPressed: widget.readOnly ? null : () => _change(() => p['background'] = {...bg}..remove('image')),
                  icon: const Icon(Icons.hide_image_rounded, size: 18),
                  label: const Text('Remove image'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!widget.readOnly)
            Wrap(
              spacing: 4,
              children: [
                IconButton(tooltip: 'Move page left', onPressed: _page > 0 ? () => _movePage(-1) : null, icon: const Icon(Icons.arrow_back_rounded)),
                IconButton(tooltip: 'Move page right', onPressed: _page < _pages.length - 1 ? () => _movePage(1) : null, icon: const Icon(Icons.arrow_forward_rounded)),
                IconButton(tooltip: 'Duplicate page', onPressed: _duplicatePage, icon: const Icon(Icons.copy_rounded)),
                IconButton(tooltip: 'Delete page', onPressed: _deletePage, icon: const Icon(Icons.delete_outline_rounded, color: ObsidianUITheme.errorRed)),
              ],
            ),
        ],
      ],
    );
  }

  Widget _paletteSection() {
    Widget item(String type, IconData icon, String label, String desc) {
      return SizedBox(
        width: 158,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            side: BorderSide(color: _border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ObsidianTokens.radius)),
          ),
          onPressed: widget.readOnly || _currentPage == null ? null : () => _addElement(type),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: ObsidianUITheme.primaryAccent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: _text, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(fontSize: 11, color: _sub)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(3, 'Add things to this page', 'Tap one to drop it in the middle of the page. You can move it next.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            item('button', Icons.touch_app_rounded, 'Tap button', 'Changes a field when tapped'),
            item('field', Icons.input_rounded, 'Field widget', "A field's normal control"),
            item('value', Icons.pin_rounded, 'Live value', "Shows a field's answer"),
            item('text', Icons.title_rounded, 'Text', 'A heading or note'),
            item('image', Icons.image_rounded, 'Image', 'A field map or diagram'),
            item('shape', Icons.crop_square_rounded, 'Shape', 'A coloured box or zone'),
          ],
        ),
      ],
    );
  }

  Widget _stageSection() {
    final p = _currentPage!;
    final byId = _fieldsById;
    final handle = 30 / (_scale <= 0 ? 1 : _scale);
    final children = <Widget>[
      Positioned.fill(
        child: GestureDetector(
          onTap: () => setState(() => _selectedId = null),
          child: CanvasBackground(page: p, fallbackColor: Colors.white),
        ),
      ),
      if (_snap > 1)
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _GridPainter(_snap * 4.0))),
        ),
    ];
    for (final el in canvasElements(p)) {
      final selected = el['id'] == _selectedId;
      final w = (el['w'] as num).toDouble(), h = (el['h'] as num).toDouble();
      children.add(Positioned(
        left: (el['x'] as num).toDouble(),
        top: (el['y'] as num).toDouble(),
        width: w,
        height: h,
        child: _dragArea(
          onStart: () => _startMove(el),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CanvasElementVisual(el: el, field: byId[el['fieldId']], editing: true)),
              if (selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: ObsidianUITheme.primaryAccent, width: math.max(2, 2 / _scale))),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
      if (selected && !widget.readOnly) {
        children.add(Positioned(
          left: (el['x'] as num).toDouble() + w - handle / 2,
          top: (el['y'] as num).toDouble() + h - handle / 2,
          width: handle,
          height: handle,
          child: _dragArea(
            onStart: () => _startResize(el),
            child: Container(
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent,
                borderRadius: BorderRadius.circular(handle / 4),
                border: Border.all(color: Colors.white, width: math.max(1.5, 2 / _scale)),
              ),
              child: Icon(Icons.open_in_full_rounded, color: Colors.white, size: handle * 0.6),
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(4, 'Arrange and set up', 'Drag things to move them, drag the corner handle to resize, and tap one to change its settings.'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Snap to grid', style: TextStyle(fontSize: 12, color: _sub)),
            _segment<int>(const [(1, 'Off'), (5, '5'), (10, '10'), (20, '20')], _snap, (v) => setState(() => _snap = v)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(6)),
          child: LayoutBuilder(builder: (context, c) {
            final screenH = MediaQuery.of(context).size.height;
            return CanvasScaler(
              designWidth: _w,
              designHeight: _h,
              maxHeight: math.max(260, screenH * 0.7),
              onScale: (s) => _scale = s,
              child: ClipRect(child: Stack(clipBehavior: Clip.none, children: children)),
            );
          }),
        ),
      ],
    );
  }

  Widget _inspector() {
    final el = _selected;
    if (el == null) {
      return ObsidianGlassCard(
        margin: const EdgeInsets.only(top: 12),
        child: Text('Tap something on the canvas to see and change its settings.', style: TextStyle(color: _sub, fontSize: 13)),
      );
    }
    final type = el['type'] as String;
    final style = Map<String, dynamic>.from(el['style'] as Map? ?? {});
    void setStyle(String k, dynamic v, {bool now = true}) => _change(() => el['style'] = {...style, k: v}, now: now);
    final field = _fieldsById[el['fieldId']];
    final placed = canvasPlacedFieldIds(_layout);
    const names = {'button': 'Tap button', 'field': 'Field widget', 'value': 'Live value', 'text': 'Text', 'image': 'Image', 'shape': 'Shape'};

    final rows = <Widget>[
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(names[type] ?? type, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _text)),
          ),
          if (!widget.readOnly) ...[
            IconButton(tooltip: 'Bring to front', onPressed: () => _reorderSelected(true), icon: const Icon(Icons.flip_to_front_rounded)),
            IconButton(tooltip: 'Send to back', onPressed: () => _reorderSelected(false), icon: const Icon(Icons.flip_to_back_rounded)),
            IconButton(tooltip: 'Duplicate', onPressed: _duplicateSelected, icon: const Icon(Icons.copy_rounded)),
            IconButton(tooltip: 'Remove from canvas', onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline_rounded, color: ObsidianUITheme.errorRed)),
          ],
        ],
      ),
      const SizedBox(height: 6),
    ];

    // Field binding
    if (type == 'field' || type == 'button' || type == 'value') {
      final options = type == 'button'
          ? _placeable.where((f) => kCanvasButtonFieldTypes.contains(f.type.toLowerCase())).toList()
          : (type == 'field' ? _placeable.where((f) => f.id == el['fieldId'] || !placed.contains(f.id)).toList() : _placeable);
      rows.add(_dropdown<String>('Field', el['fieldId'] as String?, [for (final f in options) (f.id, '${canvasFieldLabel(f)} (${f.type})')], (v) {
        final f = v == null ? null : _fieldsById[v];
        _change(() {
          el['fieldId'] = v;
          if (type == 'button' && f != null) {
            final d = _defaultButtonFor(f)!;
            el['action'] = d['action'];
            el['amount'] = d['amount'];
            if (d.containsKey('value')) {
              el['value'] = d['value'];
            } else {
              el.remove('value');
            }
          }
        });
      }));
      if (type == 'field') rows.add(_hint('Each field can be placed once. Its normal control appears here on the scout form.'));
      if (field == null && el['fieldId'] != null) rows.add(_hint('This field is no longer in the form. Pick another or remove this from the canvas.'));
      rows.add(const SizedBox(height: 10));
    }

    if (type == 'button' && field != null) {
      final actions = canvasActionsFor(field.type);
      final action = canvasActionOf(el, field);
      rows.add(_dropdown<String>('When tapped', action, [for (final a in actions) (a, kCanvasActionLabels[a] ?? a)], (v) {
        _change(() {
          el['action'] = v;
          if (v == 'set' && el['value'] == null) el['value'] = _defaultSetValue(field);
        });
      }));
      rows.add(const SizedBox(height: 10));
      if (action == 'increment' || action == 'decrement') {
        rows.add(_textInput('By how much', '${el['amount'] ?? field.step ?? 1}', (v) {
          final n = num.tryParse(v);
          if (n != null) _change(() => el['amount'] = n, now: false);
        }, number: true));
        rows.add(const SizedBox(height: 10));
      } else if (action == 'set') {
        if (field.type == 'select') {
          rows.add(_dropdown<String>('Answer', '${el['value'] ?? ''}', [for (final o in field.options) (o.value, o.label.isNotEmpty ? o.label : o.value)],
              (v) => _change(() => el['value'] = v)));
        } else if (field.type == 'checkbox') {
          rows.add(_dropdown<String>('Set it to', '${el['value'] ?? 'true'}', const [('true', 'Yes (ticked)'), ('false', 'No (unticked)')],
              (v) => _change(() => el['value'] = v)));
        } else {
          rows.add(_textInput('Value', '${el['value'] ?? ''}', (v) {
            final isNum = const {'counter', 'number', 'rating'}.contains(field.type.toLowerCase());
            _change(() => el['value'] = isNum ? (num.tryParse(v) ?? 0) : v, now: false);
          }, number: const {'counter', 'number', 'rating'}.contains(field.type.toLowerCase())));
        }
        rows.add(const SizedBox(height: 10));
      }
      rows.add(_textInput('Label (leave empty for an automatic one)', el['label'] is String ? el['label'] as String : '', (v) {
        _change(() => v.isEmpty ? el.remove('label') : el['label'] = v, now: false);
      }));
      rows.add(_switch('Show the current value on the button', el['showValue'] == true, (v) => _change(() => el['showValue'] = v)));
    }

    if (type == 'text') {
      rows.add(_textInput('Text', el['text'] as String? ?? '', (v) => _change(() => el['text'] = v, now: false), maxLines: 3));
      rows.add(const SizedBox(height: 10));
    }
    if (type == 'value') {
      rows.add(Row(children: [
        Expanded(child: _textInput('Before', el['prefix'] as String? ?? '', (v) => _change(() => el['prefix'] = v, now: false))),
        const SizedBox(width: 10),
        Expanded(child: _textInput('After', el['suffix'] as String? ?? '', (v) => _change(() => el['suffix'] = v, now: false))),
      ]));
      rows.add(const SizedBox(height: 10));
    }
    if (type == 'image') {
      rows.add(Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: widget.readOnly ? null : _pickElementImage,
          icon: const Icon(Icons.image_rounded, size: 18),
          label: Text(canvasSafeSrc(el['src']).isNotEmpty ? 'Replace image' : 'Choose image'),
        ),
      ]));
      rows.add(const SizedBox(height: 10));
      rows.add(_dropdown<String>('Fit', el['fit'] as String? ?? 'contain',
          const [('contain', 'Fit inside'), ('cover', 'Fill (crop)'), ('fill', 'Stretch')], (v) => _change(() => el['fit'] = v)));
      rows.add(const SizedBox(height: 10));
    }

    // Look
    final hasFill = type == 'button' || type == 'text' || type == 'value' || type == 'shape';
    final hasText = type == 'button' || type == 'text' || type == 'value';
    if (hasFill) {
      final defaults = {
        'button': ('#5b4ec7', 0.9, 8.0),
        'text': ('#000000', 0.0, 0.0),
        'value': ('#ffffff', 0.85, 6.0),
        'shape': ('#5b4ec7', 0.15, 8.0),
      }[type]!;
      rows.add(Row(children: [
        Expanded(child: _colorInput('Fill colour', style['bg'], defaults.$1, (v) => setStyle('bg', v))),
        if (hasText) ...[
          const SizedBox(width: 10),
          Expanded(child: _colorInput('Text colour', style['color'], type == 'button' ? '#ffffff' : '#1b1a17', (v) => setStyle('color', v))),
        ],
      ]));
      rows.add(const SizedBox(height: 6));
      rows.add(_slider('Fill opacity', canvasNum(style['bgOpacity'], defaults.$2, 0, 1) * 100, 0, 100, (v) {
        setState(() => el['style'] = {...style, 'bgOpacity': (v / 100 * 100).round() / 100});
      }, divisions: 20, fmt: (v) => '${v.round()}%'));
      if (type == 'button') rows.add(_hint('Set opacity to 0% for an invisible tap zone on top of a picture.'));
      rows.add(_slider('Corner radius', canvasNum(style['radius'], defaults.$3, 0, 60), 0, 60, (v) {
        setState(() => el['style'] = {...style, 'radius': v.round()});
      }, divisions: 30));
      rows.add(Row(children: [
        Expanded(
          child: _slider('Border', canvasNum(style['borderWidth'], type == 'shape' ? 2 : 0, 0, 20), 0, 20, (v) {
            setState(() => el['style'] = {...style, 'borderWidth': v.round()});
          }, divisions: 20),
        ),
        const SizedBox(width: 10),
        Expanded(child: _colorInput('Border colour', style['borderColor'], type == 'shape' ? '#5b4ec7' : '#000000', (v) => setStyle('borderColor', v))),
      ]));
    }
    if (hasText) {
      final dfltSize = {'button': 20.0, 'text': 24.0, 'value': 22.0}[type]!;
      rows.add(_slider('Text size', canvasNum(style['fontSize'], dfltSize, 6, 120), 6, 120, (v) {
        setState(() => el['style'] = {...style, 'fontSize': v.round()});
      }, divisions: 114));
      rows.add(Row(children: [
        Expanded(
          child: _segment<String>(const [('left', 'Left'), ('center', 'Centre'), ('right', 'Right')], (style['align'] as String?) ?? 'center',
              (v) => setStyle('align', v)),
        ),
        Expanded(
          child: _switch('Bold', style['bold'] == false ? false : (style['bold'] == true || type != 'text'), (v) => setStyle('bold', v)),
        ),
      ]));
    }
    if (type == 'image') {
      rows.add(_slider('Corner radius', canvasNum(style['radius'], 0, 0, 60), 0, 60, (v) {
        setState(() => el['style'] = {...style, 'radius': v.round()});
      }, divisions: 30));
    }

    // Position and size
    rows.add(const SizedBox(height: 8));
    rows.add(Text('Position and size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _text)));
    rows.add(const SizedBox(height: 8));
    Widget numBox(String k) => Expanded(
          child: _textInput(k.toUpperCase(), '${el[k]}', (v) {
            final n = int.tryParse(v);
            if (n == null) return;
            _change(() {
              final norm = normalizeCanvasElement({...el, k: n}, _w, _h);
              el['x'] = norm['x'];
              el['y'] = norm['y'];
              el['w'] = norm['w'];
              el['h'] = norm['h'];
            }, now: false);
          }, number: true, keyId: 'box-$_boxEpoch'),
        );
    rows.add(Row(children: [numBox('x'), const SizedBox(width: 6), numBox('y'), const SizedBox(width: 6), numBox('w'), const SizedBox(width: 6), numBox('h')]));
    if (!widget.readOnly) {
      void nudge(int dx, int dy) => _change(() {
            _boxEpoch++;
            final step = math.max(1, _snap);
            el['x'] = ((el['x'] as int) + dx * step).clamp(-(el['w'] as int) + 8, _w - 8);
            el['y'] = ((el['y'] as int) + dy * step).clamp(-(el['h'] as int) + 8, _h - 8);
          });
      rows.add(Wrap(children: [
        IconButton(tooltip: 'Nudge left', onPressed: () => nudge(-1, 0), icon: const Icon(Icons.keyboard_arrow_left_rounded)),
        IconButton(tooltip: 'Nudge up', onPressed: () => nudge(0, -1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
        IconButton(tooltip: 'Nudge down', onPressed: () => nudge(0, 1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
        IconButton(tooltip: 'Nudge right', onPressed: () => nudge(1, 0), icon: const Icon(Icons.keyboard_arrow_right_rounded)),
      ]));
    }

    return ObsidianGlassCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _unplacedSection() {
    final placed = canvasPlacedFieldIds(_layout);
    final unplaced = _placeable.where((f) => !placed.contains(f.id)).toList();
    if (unplaced.isEmpty) return const SizedBox.shrink();
    return ObsidianGlassCard(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fields not on the canvas (${unplaced.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _text)),
          _hint(_layout['showUnplaced'] != false
              ? 'Scouts see these in a list under the canvas.'
              : 'Hidden from scouts: the setting to list them under the canvas is off.'),
          for (final f in unplaced)
            Row(
              children: [
                Expanded(child: Text('${canvasFieldLabel(f)} (${f.type})', style: TextStyle(color: _text, fontSize: 13), overflow: TextOverflow.ellipsis)),
                if (!widget.readOnly)
                  TextButton.icon(
                    onPressed: _currentPage == null ? null : () => _addElement('field', fieldId: f.id),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Place'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.seasonLayout != null && canvasIsActive(widget.seasonLayout) ? widget.seasonLayout : null;
    if (season != null && widget.layout == null) return _seasonChoiceCard();

    final sections = <Widget>[];
    if (season != null) {
      sections.add(ObsidianGlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'The site admins have a ${widget.seasonYear ?? "season"} default canvas. Your team is using its own setting below instead.',
                style: TextStyle(fontSize: 12.5, color: _sub),
              ),
            ),
            TextButton.icon(
              onPressed: widget.readOnly
                  ? null
                  : () async {
                      final ok = await _confirm('Go back to the default canvas?',
                          "Your team's own canvas design will be removed (you can copy it from Raw JSON first).");
                      if (ok) _setOwnLayout(null);
                    },
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Use default'),
            ),
          ],
        ),
      ));
    }

    sections.add(_card(_settingsSection()));

    if (_pages.isEmpty && _layout['mode'] != 'canvas') {
      sections.add(_card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing is on a canvas yet. Start from your current fields, then move and restyle them.', style: TextStyle(color: _text, fontSize: 13)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent, foregroundColor: Colors.white),
            onPressed: widget.readOnly ? null : _generate,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Start a canvas from my fields'),
          ),
        ],
      )));
    } else {
      sections.add(_card(_pagesSection()));
      sections.add(_card(_paletteSection()));
      if (_currentPage != null) {
        sections.add(_card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_stageSection(), _inspector(), _unplacedSection()],
        )));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
  }

  Widget _card(Widget child) => ObsidianGlassCard(margin: const EdgeInsets.only(bottom: 12), child: child);
}

class _GridPainter extends CustomPainter {
  final double step;
  _GridPainter(this.step);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x145B4EC7)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.step != step;
}
