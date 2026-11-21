import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/canvas_layout.dart';
import '../models/config_models.dart';
import '../services/net/server_file_cache.dart';
import '../services/photo_values.dart';
import '../theme/obsidian_tokens.dart';
import '../theme/obsidian_ui_theme.dart';
import 'cached_server_image.dart';
import 'dynamic_field_widget.dart';
import 'obsidian_glass_card.dart';

// ---------------------------------------------------------------------------------------------------------------
// Shared rendering (scout form and editor)
// ---------------------------------------------------------------------------------------------------------------

BoxFit _fitOf(dynamic fit) => fit == 'cover' ? BoxFit.cover : (fit == 'fill' ? BoxFit.fill : BoxFit.contain);

/// An image from a canvas layout: a `/api/blobs/` URL (kept on the device so it shows offline) or an embedded one.
class CanvasImage extends StatelessWidget {
  final String src;
  final BoxFit fit;

  const CanvasImage({super.key, required this.src, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final safe = canvasSafeSrc(src);
    if (safe.isEmpty) return const SizedBox.shrink();
    if (safe.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(safe.substring(safe.indexOf(',') + 1)), fit: fit, gaplessPlayback: true);
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    final url = resolveBlobPhotoUrl(safe);
    if (url == null) return const SizedBox.shrink();
    return CachedServerImage(url: url, fit: fit, errorBuilder: (_) => const SizedBox.shrink());
  }
}

/// Fetches every image a layout uses into the device cache, so the canvas shows them offline later.
void prefetchCanvasImages(Map<String, dynamic>? layout) {
  if (layout == null) return;
  final srcs = <String>{};
  for (final p in canvasPages(normalizeCanvasLayout(layout))) {
    final bg = p['background'];
    if (bg is Map) srcs.add(canvasSafeSrc(bg['image']));
    for (final e in canvasElements(p)) {
      if (e['type'] == 'image') srcs.add(canvasSafeSrc(e['src']));
    }
  }
  for (final s in srcs) {
    if (!isBlobPhotoPath(s)) continue;
    final url = resolveBlobPhotoUrl(s);
    if (url != null) ServerFileCache.instance.refresh(url).catchError((_) => null);
  }
}

/// Scales a design-size child to the available width (and at most [maxHeight] tall), keeping its shape.
class CanvasScaler extends StatelessWidget {
  final int designWidth;
  final int designHeight;
  final double? maxHeight;
  final double maxScale;
  final Widget child;
  final ValueChanged<double>? onScale;

  const CanvasScaler({
    super.key,
    required this.designWidth,
    required this.designHeight,
    required this.child,
    this.maxHeight,
    this.maxScale = double.infinity,
    this.onScale,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final avail = constraints.maxWidth.isFinite ? constraints.maxWidth : designWidth.toDouble();
      var scale = math.min(avail / designWidth, maxScale);
      if (maxHeight != null) scale = math.min(scale, maxHeight! / designHeight);
      onScale?.call(scale);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: designWidth * scale,
          height: designHeight * scale,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(width: designWidth.toDouble(), height: designHeight.toDouble(), child: child),
          ),
        ),
      );
    });
  }
}

/// The page's background colour and image, filling the stage.
class CanvasBackground extends StatelessWidget {
  final Map<String, dynamic> page;
  final Color fallbackColor;

  const CanvasBackground({super.key, required this.page, this.fallbackColor = Colors.transparent});

  @override
  Widget build(BuildContext context) {
    final bg = page['background'] is Map ? Map<String, dynamic>.from(page['background'] as Map) : const <String, dynamic>{};
    final src = canvasSafeSrc(bg['image']);
    return Container(
      color: canvasColor(bg['color'], fallbackColor),
      child: src.isEmpty ? null : SizedBox.expand(child: CanvasImage(src: src, fit: _fitOf(bg['fit']))),
    );
  }
}

TextAlign _alignOf(dynamic a, TextAlign dflt) =>
    a == 'left' ? TextAlign.left : (a == 'right' ? TextAlign.right : (a == 'center' ? TextAlign.center : dflt));

Alignment _boxAlignOf(TextAlign a) =>
    a == TextAlign.left ? Alignment.centerLeft : (a == TextAlign.right ? Alignment.centerRight : Alignment.center);

TextStyle _textStyle(Map<String, dynamic> s, {required double fontSize, required String color, required bool bold}) {
  final weightBold = s['bold'] == false ? false : (s['bold'] == true || bold);
  return TextStyle(
    fontSize: canvasNum(s['fontSize'], fontSize, 6, 200),
    color: canvasColor(s['color'], canvasColor(color, Colors.black)),
    fontWeight: weightBold ? FontWeight.w700 : FontWeight.w400,
    height: 1.15,
  );
}

BoxDecoration _fill(Map<String, dynamic> s,
    {required String bg, required double bgOpacity, required double radius, required double borderWidth, required String borderColor}) {
  final opacity = canvasNum(s['bgOpacity'], bgOpacity, 0, 1);
  final bw = canvasNum(s['borderWidth'], borderWidth, 0, 40);
  return BoxDecoration(
    color: opacity > 0 ? canvasColor(s['bg'], canvasColor(bg, Colors.black), opacity: opacity) : Colors.transparent,
    borderRadius: BorderRadius.circular(canvasNum(s['radius'], radius, 0, 999)),
    border: bw > 0 ? Border.all(color: canvasColor(s['borderColor'], canvasColor(borderColor, Colors.black)), width: bw) : null,
  );
}

Map<String, dynamic> _styleOf(Map<String, dynamic> el) =>
    el['style'] is Map ? Map<String, dynamic>.from(el['style'] as Map) : const <String, dynamic>{};

/// The look of a non-field element. [value] is the bound field's current value (scout form), or null in the editor.
/// [editing] shows placeholders where the scout form would show nothing.
class CanvasElementVisual extends StatelessWidget {
  final Map<String, dynamic> el;
  final ScoutingFieldModel? field;
  final dynamic value;
  final bool editing;
  final bool invalid;
  final bool pressed;

  const CanvasElementVisual({
    super.key,
    required this.el,
    this.field,
    this.value,
    this.editing = false,
    this.invalid = false,
    this.pressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = _styleOf(el);
    final broken = el['fieldId'] != null && field == null;
    switch (el['type']) {
      case 'button':
        final on = !editing && canvasButtonIsOn(el, field, value);
        final style = _textStyle(s, fontSize: 20, color: '#ffffff', bold: true);
        final align = _alignOf(s['align'], TextAlign.center);
        final label = canvasButtonLabel(el, field);
        final zone = canvasNum(s['bgOpacity'], 0.9, 0, 1) == 0;
        return AnimatedScale(
          scale: pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            decoration: _fill(s, bg: '#5b4ec7', bgOpacity: 0.9, radius: 8, borderWidth: 0, borderColor: '#ffffff').copyWith(
              border: (on || invalid || broken || (zone && editing))
                  ? Border.all(
                      color: invalid || broken ? ObsidianUITheme.errorRed : (on ? Colors.white : ObsidianUITheme.primaryAccent),
                      width: on ? 4 : 2)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: _boxAlignOf(align),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: _boxAlignOf(align),
                  child: Text(label, textAlign: align, style: style, overflow: TextOverflow.fade),
                ),
                if (el['showValue'] == true)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        editing || field == null ? '0' : canvasDisplayValue(field!, value),
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: math.max(12, style.fontSize! * 0.7)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      case 'text':
        final align = _alignOf(s['align'], TextAlign.center);
        return Container(
          decoration: _fill(s, bg: '#000000', bgOpacity: 0, radius: 0, borderWidth: 0, borderColor: '#000000'),
          alignment: _boxAlignOf(align),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(el['text'] is String ? el['text'] as String : '',
              textAlign: align, style: _textStyle(s, fontSize: 24, color: '#1b1a17', bold: false), overflow: TextOverflow.fade),
        );
      case 'image':
        final src = canvasSafeSrc(el['src']);
        return ClipRRect(
          borderRadius: BorderRadius.circular(canvasNum(s['radius'], 0, 0, 999)),
          child: src.isNotEmpty
              ? SizedBox.expand(child: CanvasImage(src: src, fit: _fitOf(el['fit'])))
              : (editing
                  ? Container(
                      color: Colors.black.withValues(alpha: 0.06),
                      alignment: Alignment.center,
                      child: const Text('No image yet', style: TextStyle(fontSize: 20, color: Colors.black54)),
                    )
                  : const SizedBox.shrink()),
        );
      case 'value':
        final align = _alignOf(s['align'], TextAlign.center);
        final shown = editing ? (field != null ? canvasFieldLabel(field) : '?') : (field == null ? '-' : canvasDisplayValue(field!, value));
        return Container(
          decoration: _fill(s, bg: '#ffffff', bgOpacity: 0.85, radius: 6, borderWidth: 0, borderColor: '#000000').copyWith(
            border: invalid || broken ? Border.all(color: ObsidianUITheme.errorRed, width: 2) : null,
          ),
          alignment: _boxAlignOf(align),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('${el['prefix'] ?? ''}$shown${el['suffix'] ?? ''}',
              textAlign: align, style: _textStyle(s, fontSize: 22, color: '#1b1a17', bold: true), overflow: TextOverflow.fade),
        );
      case 'field':
        // Only drawn here in the editor; the scout form puts the field's real widget in this box.
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: broken ? ObsidianUITheme.errorRed : ObsidianUITheme.primaryAccent, width: 2),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                field != null ? canvasFieldLabel(field) : (el['fieldId'] != null ? 'Missing field: ${el['fieldId']}' : 'Pick a field'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: broken ? ObsidianUITheme.errorRed : Colors.black87),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
              if (field != null)
                Text('${field!.type} widget', style: const TextStyle(fontSize: 16, color: Colors.black54)),
            ],
          ),
        );
      default:
        return Container(
          decoration: _fill(s, bg: '#5b4ec7', bgOpacity: 0.15, radius: 8, borderWidth: 2, borderColor: '#5b4ec7'),
        );
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Scout form
// ---------------------------------------------------------------------------------------------------------------

/// The canvas scouting form: page tabs, the scaled canvas, and the fields that aren't placed listed below.
///
/// Values live in the screen's form data; buttons and field widgets report changes through [onChanged], exactly
/// like the classic list, so saving, drafts, review, QR and points work the same either way.
class CanvasScoutForm extends StatefulWidget {
  final Map<String, dynamic> layout;
  final List<ScoutingFieldModel> fields;
  final Map<String, dynamic> values;
  final void Function(String fieldId, dynamic value) onChanged;

  /// Called with the page's phase ('' when none) whenever the page changes, for controller bindings.
  final ValueChanged<String>? onPageChanged;

  /// Field ids to mark as needing attention (e.g. a missing required answer).
  final Set<String> invalidFieldIds;

  const CanvasScoutForm({
    super.key,
    required this.layout,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.onPageChanged,
    this.invalidFieldIds = const {},
  });

  @override
  State<CanvasScoutForm> createState() => CanvasScoutFormState();
}

class CanvasScoutFormState extends State<CanvasScoutForm> {
  late Map<String, dynamic> _layout;
  int _page = 0;
  String? _pressedId;

  @override
  void initState() {
    super.initState();
    _layout = normalizeCanvasLayout(widget.layout);
    prefetchCanvasImages(_layout);
    WidgetsBinding.instance.addPostFrameCallback((_) => _announcePage());
  }

  @override
  void didUpdateWidget(covariant CanvasScoutForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layout, widget.layout)) {
      _layout = normalizeCanvasLayout(widget.layout);
      prefetchCanvasImages(_layout);
      final count = canvasPages(_layout).length;
      if (_page >= count) _page = math.max(0, count - 1);
    }
  }

  List<Map<String, dynamic>> get _pages => canvasPages(_layout);
  int get pageCount => _pages.length;
  int get currentPage => _page;
  String get currentPhase => _pages.isEmpty ? '' : (_pages[_page]['phase'] as String? ?? '');

  void _announcePage() {
    if (mounted) widget.onPageChanged?.call(currentPhase);
  }

  void showPage(int index) {
    if (_pages.isEmpty) return;
    final next = index.clamp(0, _pages.length - 1);
    if (next == _page) return;
    setState(() => _page = next);
    _announcePage();
  }

  void nextPage() => showPage(_page < _pages.length - 1 ? _page + 1 : 0);
  void previousPage() => showPage(_page > 0 ? _page - 1 : _pages.length - 1);

  /// Goes to the first page for a match phase; false when no page has it.
  bool showPhase(String phase) {
    final idx = _pages.indexWhere((p) => p['phase'] == phase);
    if (idx < 0) return false;
    showPage(idx);
    return true;
  }

  /// Goes to the page holding [fieldId]; false when the field isn't on the canvas (it is in the list below).
  bool revealField(String fieldId) {
    final idx = canvasPageOfField(_layout, fieldId);
    if (idx < 0) return false;
    showPage(idx);
    return true;
  }

  Map<String, ScoutingFieldModel> get _fieldsById => {for (final f in widget.fields) f.id: f};

  void _tap(Map<String, dynamic> el) {
    final field = _fieldsById[el['fieldId']];
    final result = canvasApplyAction(el, field, field == null ? null : widget.values[field.id]);
    if (result == null || field == null) return;
    HapticFeedback.lightImpact();
    widget.onChanged(field.id, result.value);
    final id = el['id'] as String;
    setState(() => _pressedId = id);
    Future.delayed(const Duration(milliseconds: 110), () {
      if (mounted && _pressedId == id) setState(() => _pressedId = null);
    });
  }

  Widget _fieldBox(Map<String, dynamic> el, ScoutingFieldModel field) {
    final invalid = widget.invalidFieldIds.contains(field.id);
    // A Material (not a decorated box) so the field's own ink effects, e.g. a checkbox's list tile, still show.
    return Material(
      color: ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        side: BorderSide(color: invalid ? ObsidianUITheme.errorRed : ObsidianUITheme.getBorderColor(context), width: invalid ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: DynamicFieldWidget(
          key: ValueKey('canvas-field-${field.id}'),
          field: field,
          currentValue: widget.values[field.id],
          currentPhase: currentPhase.isEmpty ? canvasPhaseOf(field) : currentPhase,
          onChanged: (v) => widget.onChanged(field.id, v),
        ),
      ),
    );
  }

  Widget _stage(Map<String, dynamic> page) {
    final byId = _fieldsById;
    final placed = <String>{};
    final children = <Widget>[Positioned.fill(child: CanvasBackground(page: page))];
    for (final el in canvasElements(page)) {
      final fid = el['fieldId'] as String?;
      final field = fid == null ? null : byId[fid];
      // A season default canvas may point at a field this team's form doesn't have: leave it out.
      if (fid != null && field == null) continue;
      Widget child;
      if (el['type'] == 'field') {
        if (field == null || placed.contains(field.id)) continue;
        placed.add(field.id);
        child = _fieldBox(el, field);
      } else if (el['type'] == 'button') {
        child = Semantics(
          button: true,
          label: canvasButtonLabel(el, field),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(el),
            child: CanvasElementVisual(
              el: el,
              field: field,
              value: field == null ? null : widget.values[field.id],
              invalid: field != null && widget.invalidFieldIds.contains(field.id),
              pressed: _pressedId == el['id'],
            ),
          ),
        );
      } else {
        child = IgnorePointer(
          child: CanvasElementVisual(
            el: el,
            field: field,
            value: field == null ? null : widget.values[field.id],
            invalid: field != null && widget.invalidFieldIds.contains(field.id),
          ),
        );
      }
      children.add(Positioned(
        left: (el['x'] as num).toDouble(),
        top: (el['y'] as num).toDouble(),
        width: (el['w'] as num).toDouble(),
        height: (el['h'] as num).toDouble(),
        child: child,
      ));
    }
    return ClipRect(child: Stack(children: children));
  }

  Widget _pageTabs() {
    final pages = _pages;
    if (pages.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < pages.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    showPage(i);
                  },
                  borderRadius: BorderRadius.circular(ObsidianTokens.radiusPill),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                    decoration: BoxDecoration(
                      color: i == _page ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.16) : ObsidianUITheme.getSurfaceColor(context),
                      borderRadius: BorderRadius.circular(ObsidianTokens.radiusPill),
                      border: Border.all(color: i == _page ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context)),
                    ),
                    child: Text(
                      pages[i]['name'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: i == _page ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pages[_page];
    final placedIds = canvasPlacedFieldIds(_layout);
    final unplaced = canvasPlaceableFields(widget.fields).where((f) => !placedIds.contains(f.id)).toList();
    final showUnplaced = _layout['showUnplaced'] != false && unplaced.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTabs(),
        ClipRRect(
          borderRadius: BorderRadius.circular(ObsidianTokens.radius),
          child: CanvasScaler(
            designWidth: _layout['width'] as int,
            designHeight: _layout['height'] as int,
            child: KeyedSubtree(key: ValueKey('canvas-page-${page['id']}'), child: _stage(page)),
          ),
        ),
        if (showUnplaced)
          ObsidianGlassCard(
            margin: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MORE FIELDS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                const SizedBox(height: 6),
                for (final f in unplaced)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: widget.invalidFieldIds.contains(f.id)
                        ? BoxDecoration(
                            border: Border.all(color: ObsidianUITheme.errorRed, width: 1.5),
                            borderRadius: BorderRadius.circular(ObsidianTokens.radius))
                        : null,
                    child: DynamicFieldWidget(
                      key: ValueKey('canvas-list-${f.id}'),
                      field: f,
                      currentValue: widget.values[f.id],
                      currentPhase: canvasPhaseOf(f),
                      onChanged: (v) => widget.onChanged(f.id, v),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
