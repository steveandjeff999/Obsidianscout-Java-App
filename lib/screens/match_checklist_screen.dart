import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/config_collab/config_collab_session.dart';
import '../services/config_collab/config_sync_engine.dart';
import '../services/match_checklist_sync.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_app_bar.dart';
import '../widgets/obsidian_glass_card.dart';

/// Drive-team checklists (Settings > Non-Scouting Tools).
///
/// The team builds any number of lists; each has a frequency: every match, every N of our matches, once a
/// day, or once per event. Lists due every match / every N matches are filled out per match; daily lists in
/// a per-day record (`day_YYYY-MM-DD`) and per-event lists in one record (`event`). Everything is edited live
/// through [MatchChecklistSync], which also keeps offline edits and saves them once the server is reachable.
/// Mirrors static/js/match-checklist.js on the website; both read and write the same documents:
///
///   Template:   {lists: {listId: {title, order, frequency, every}}, fields: [{id, section: listId, text, priority}]}
///               (older templates have no `lists`, just the fixed lists "pre" and "field" titled by `sections`)
///   Completion: {checked: {itemId: {by, at}}, notes, fields: []}
class MatchChecklistScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onOpenSettings;

  const MatchChecklistScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onOpenSettings,
  });

  @override
  State<MatchChecklistScreen> createState() => _MatchChecklistScreenState();
}

const _frequencies = ['match', 'every_n', 'daily', 'event'];
const _legacyLists = ['pre', 'field'];
const _priorities = ['critical', 'high', 'normal', 'low'];
const _defaultPriority = 'normal';
const _customMatchValue = '__custom__';

/// Starter items: translation key suffix and priority. Text is stored in the language of whoever adds it.
const _starterItems = {
  'pre': [
    ('battery', 'critical'),
    ('voltage', 'critical'),
    ('bumpers', 'critical'),
    ('radio', 'critical'),
    ('mechanical', 'high'),
    ('controllers_charged', 'high'),
  ],
  'field': [
    ('start_position', 'critical'),
    ('auto_selected', 'critical'),
    ('ds_connected', 'critical'),
    ('preload', 'high'),
    ('controllers_mapped', 'high'),
  ],
};

const _starterFallback = {
  'battery': 'Fresh battery installed and strapped down',
  'voltage': 'Battery voltage checked (12.5V+)',
  'bumpers': 'Bumpers on and showing the correct alliance color',
  'radio': 'Radio powered and secured',
  'mechanical': 'All bolts, chains and belts checked',
  'controllers_charged': 'Controllers and driver station laptop charged',
  'start_position': 'Robot placed in the correct starting position',
  'auto_selected': 'Correct autonomous routine selected',
  'ds_connected': 'Driver station connected to the field (all green)',
  'preload': 'Game piece preloaded',
  'controllers_mapped': 'Controllers plugged in and mapped to the right ports',
};

class _ChecklistItem {
  final String id;
  final String text;
  final String priority;
  final int index; // position in the template's `fields` array
  final String key; // live-sync key of that field

  const _ChecklistItem(this.id, this.text, this.priority, this.index, this.key);

  bool get fillable => id.isNotEmpty && text.trim().isNotEmpty;
}

class _ChecklistList {
  final String id;
  final String title;
  final int order;
  final String frequency;
  final int every;
  final List<_ChecklistItem> items;

  const _ChecklistList(this.id, this.title, this.order, this.frequency, this.every, this.items);

  List<_ChecklistItem> get fillable => items.where((i) => i.fillable).toList();

  /// Which completion record this list is filled out in.
  String get scope => switch (frequency) {
        'daily' => 'day',
        'event' => 'event',
        _ => 'match',
      };
}

/// Lists defined by a template doc (without items), in display order.
List<({String id, String title, int order, String frequency, int every})> checklistListsOf(Map<String, dynamic> doc) {
  final lists = doc['lists'];
  if (lists is Map) {
    final out = <({String id, String title, int order, String frequency, int every})>[];
    lists.forEach((id, l) {
      if (l is! Map) return;
      final freq = l['frequency']?.toString();
      final every = (l['every'] is num) ? (l['every'] as num).toInt() : int.tryParse(l['every']?.toString() ?? '') ?? 2;
      out.add((
        id: id.toString(),
        title: l['title']?.toString() ?? '',
        order: (l['order'] is num) ? (l['order'] as num).toInt() : 0,
        frequency: _frequencies.contains(freq) ? freq! : 'match',
        every: every.clamp(2, 99),
      ));
    });
    out.sort((a, b) => a.order != b.order ? a.order - b.order : a.id.compareTo(b.id));
    return out;
  }
  // Older template: the fixed Pre-Match / On the Field lists.
  final sections = doc['sections'] is Map ? doc['sections'] as Map : const {};
  return [
    for (var i = 0; i < _legacyLists.length; i++)
      (
        id: _legacyLists[i],
        title: (sections[_legacyLists[i]] is Map ? (sections[_legacyLists[i]] as Map)['title']?.toString() : null) ?? '',
        order: i,
        frequency: 'match',
        every: 2,
      ),
  ];
}

/// Converts an older template to the `lists` form before its lists are changed; returns `lists`.
Map<String, dynamic> ensureChecklistLists(Map<String, dynamic> doc) {
  final existing = doc['lists'];
  if (existing is Map) {
    final lists = existing.map((k, v) => MapEntry(k.toString(), v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
    doc['lists'] = lists;
    return lists;
  }
  final lists = <String, dynamic>{
    for (final l in checklistListsOf(doc))
      l.id: <String, dynamic>{'title': l.title, 'order': l.order, 'frequency': l.frequency, 'every': l.every},
  };
  doc['lists'] = lists;
  return lists;
}

class _MatchChecklistScreenState extends State<MatchChecklistScreen> {
  bool _editMode = false;
  bool _loading = true;

  // Event / match selection
  List<EventModel> _events = [];
  String _eventKey = '';
  List<MatchModel> _matches = [];
  String _matchKey = '';
  bool _onlyOurs = true;
  final Map<String, Map<String, dynamic>> _completions = {};
  final Map<String, String> _customMatchNames = {};

  // Live documents
  late final MatchChecklistSync _sync = MatchChecklistSync.of(widget.apiService);
  ChecklistRoom? _tpl;
  final Map<String, ChecklistRoom?> _fillRooms = {'match': null, 'day': null, 'event': null};
  int _fillSyncGeneration = 0;

  // Text fields that must survive live updates
  final Map<String, TextEditingController> _itemControllers = {};
  final Map<String, FocusNode> _itemFocus = {};
  final Map<String, TextEditingController> _listTitleControllers = {};
  final Map<String, TextEditingController> _everyControllers = {};
  final Map<String, TextEditingController> _addControllers = {};
  final Map<String, String> _addPriority = {};
  final Set<String> _focusedListFields = {};
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _notesFocus = FocusNode();
  String? _focusedItemKey;

  ApiService get _api => widget.apiService;

  @override
  void initState() {
    super.initState();
    _api.permissionsNotifier.addListener(_onPermissionsChanged);
    _sync.addListener(_onSyncChanged);
    _sync.offlineChangesSaved.addListener(_onOfflineSaved);
    if (_api.nonScoutingToolsEnabled) unawaited(_init());
  }

  @override
  void dispose() {
    _api.permissionsNotifier.removeListener(_onPermissionsChanged);
    _sync.removeListener(_onSyncChanged);
    _sync.offlineChangesSaved.removeListener(_onOfflineSaved);
    _releaseAll();
    for (final c in [
      ..._itemControllers.values,
      ..._listTitleControllers.values,
      ..._everyControllers.values,
      ..._addControllers.values,
    ]) {
      c.dispose();
    }
    for (final f in _itemFocus.values) {
      f.dispose();
    }
    _notesController.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _releaseAll() {
    _sync.release(_tpl);
    _tpl = null;
    for (final scope in _fillRooms.keys.toList()) {
      _sync.release(_fillRooms[scope]);
      _fillRooms[scope] = null;
    }
  }

  void _onPermissionsChanged() {
    if (!mounted) return;
    final enabled = _api.nonScoutingToolsEnabled;
    if (enabled && _tpl == null) {
      unawaited(_init());
    } else if (!enabled && _tpl != null) {
      _releaseAll();
    }
    setState(() {});
  }

  void _onSyncChanged() {
    if (!mounted) return;
    _syncControllers();
    final match = _fillRooms['match'];
    if (match != null && _matchKey.isNotEmpty) _completions[_matchKey] = Map<String, dynamic>.from(match.session.lastView.doc);
    // A teammate may have added a daily / per-event list, or removed the last one.
    if (!_editMode && _eventKey.isNotEmpty && _tpl != null) {
      final lists = _lists();
      final needDay = lists.any((l) => l.scope == 'day');
      final needEvent = lists.any((l) => l.scope == 'event');
      if (needDay != (_fillRooms['day'] != null) || needEvent != (_fillRooms['event'] != null)) unawaited(_syncFillRooms());
    }
    setState(() {});
  }

  void _onOfflineSaved() {
    if (mounted) _snack(context.tr('checklist.offline_saved', 'All offline changes saved'));
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    _tpl = await _sync.acquire('', MatchChecklistSync.templateKey);
    _syncControllers();
    await _loadEvents();
    unawaited(_sync.resumeDrafts());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _editMode = !_lists().any((l) => l.fillable.isNotEmpty);
    });
  }

  /// Opens the match/day/event records the Fill Out view needs and lets go of the others.
  Future<void> _syncFillRooms() async {
    final generation = ++_fillSyncGeneration;
    final lists = _lists();
    final eventKey = _eventKey;
    final wanted = <String, String?>{
      'match': eventKey.isNotEmpty && _matchKey.isNotEmpty ? _matchKey : null,
      'day': eventKey.isNotEmpty && lists.any((l) => l.scope == 'day') ? MatchChecklistSync.todayKey() : null,
      'event': eventKey.isNotEmpty && lists.any((l) => l.scope == 'event') ? MatchChecklistSync.eventScopeKey : null,
    };
    for (final scope in wanted.keys) {
      final current = _fillRooms[scope];
      final wantedKey = wanted[scope];
      final wantedId = wantedKey == null ? null : MatchChecklistSync.roomIdFor(eventKey, wantedKey);
      if (current?.id == wantedId) continue;
      _fillRooms[scope] = null;
      _sync.release(current);
      if (wantedKey == null) continue;
      final room = await _sync.acquire(eventKey, wantedKey);
      // The selection may have changed while this opened.
      if (!mounted || generation != _fillSyncGeneration || _fillRooms[scope] != null) {
        _sync.release(room);
        continue;
      }
      _fillRooms[scope] = room;
      if (scope == 'match') _completions[_matchKey] = Map<String, dynamic>.from(room.session.lastView.doc);
    }
    _syncNotes(force: true);
    if (mounted) setState(() {});
  }

  // ── Documents ──────────────────────────────────────────────────────────────

  List<_ChecklistList> _lists() {
    final view = _tpl?.session.lastView;
    final doc = view?.doc ?? const <String, dynamic>{};
    final fields = ConfigSyncEngine.fieldsOf(doc);
    return checklistListsOf(doc).map((l) {
      final items = <_ChecklistItem>[];
      for (var i = 0; i < fields.length; i++) {
        final f = fields[i];
        if (f is! Map || (f['section']?.toString() ?? 'pre') != l.id) continue;
        final priority = f['priority']?.toString();
        items.add(_ChecklistItem(
          f['id']?.toString() ?? '',
          f['text']?.toString() ?? '',
          _priorities.contains(priority) ? priority! : _defaultPriority,
          i,
          i < (view?.keys.length ?? 0) ? view!.keys[i] : 'i$i',
        ));
      }
      return _ChecklistList(l.id, l.title, l.order, l.frequency, l.every, items);
    }).toList();
  }

  String _listTitle(_ChecklistList l) {
    final title = l.title.trim();
    if (l.id == 'pre' && (title.isEmpty || title == 'Pre-Match')) return context.tr('checklist.section.pre', 'Pre-Match');
    if (l.id == 'field' && (title.isEmpty || title == 'On the Field')) return context.tr('checklist.section.field', 'On the Field');
    return title.isEmpty ? context.tr('checklist.list_untitled', 'Untitled list') : title;
  }

  String _frequencyLabel(_ChecklistList l) => switch (l.frequency) {
        'every_n' => context.tr('checklist.freq.every_n', {'n': '${l.every}'}),
        'daily' => context.tr('checklist.freq.daily', 'Once a day'),
        'event' => context.tr('checklist.freq.event', 'Once per event'),
        _ => context.tr('checklist.freq.match', 'Every match'),
      };

  String _frequencyOptionLabel(String f) => switch (f) {
        'every_n' => context.tr('checklist.freq.every_n_option', 'Every few matches'),
        'daily' => context.tr('checklist.freq.daily', 'Once a day'),
        'event' => context.tr('checklist.freq.event', 'Once per event'),
        _ => context.tr('checklist.freq.match', 'Every match'),
      };

  static Map<String, dynamic> _checkedOf(Map<String, dynamic>? completion) {
    final c = completion?['checked'];
    return c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{};
  }

  Map<String, dynamic> _checkedIn(String scope) => _checkedOf(_fillRooms[scope]?.session.lastView.doc);

  // "Every N matches": due on our 1st, (N+1)th, ... match of the event. Matches outside our schedule
  // (custom / practice) always count as due.
  List<MatchModel> get _ourMatches => _matches.where((m) => _allianceOf(m) != null).toList();

  bool _isDue(_ChecklistList l, String matchKey) {
    if (l.frequency != 'every_n') return true;
    final idx = _ourMatches.indexWhere((m) => m.matchKey == matchKey);
    return idx < 0 || idx % l.every == 0;
  }

  MatchModel? _nextDue(_ChecklistList l, String matchKey) {
    final ours = _ourMatches;
    final idx = ours.indexWhere((m) => m.matchKey == matchKey);
    for (var i = idx + 1; i < ours.length; i++) {
      if (i % l.every == 0) return ours[i];
    }
    return null;
  }

  /// A match is done when every item of its per-match lists that are due for it is checked.
  bool _isMatchComplete(String matchKey, Map<String, dynamic>? completion) {
    if (completion == null) return false;
    final ids = _lists()
        .where((l) => l.scope == 'match' && _isDue(l, matchKey))
        .expand((l) => l.fillable)
        .map((i) => i.id)
        .toList();
    if (ids.isEmpty) return false;
    final checked = _checkedOf(completion);
    return ids.every(checked.containsKey);
  }

  // Keeps text fields in step with live edits without disturbing the one being typed in.
  void _syncControllers() {
    final lists = _lists();
    final liveKeys = <String>{};
    for (final l in lists) {
      final shownTitle = l.title.trim().isNotEmpty ? l.title : (_legacyLists.contains(l.id) ? _listTitle(l) : '');
      final title = _listTitleControllers.putIfAbsent(l.id, () => TextEditingController(text: shownTitle));
      if (title.text != shownTitle && !_focusedListFields.contains('title-${l.id}')) _setText(title, shownTitle);
      final every = _everyControllers.putIfAbsent(l.id, () => TextEditingController(text: '${l.every}'));
      if (every.text != '${l.every}' && !_focusedListFields.contains('every-${l.id}')) _setText(every, '${l.every}');
      _addControllers.putIfAbsent(l.id, () => TextEditingController());
      _addPriority.putIfAbsent(l.id, () => _defaultPriority);
      for (final item in l.items) {
        liveKeys.add(item.key);
        final controller = _itemControllers.putIfAbsent(item.key, () => TextEditingController(text: item.text));
        final focus = _itemFocus.putIfAbsent(item.key, () => _newItemFocus(item.key));
        if (controller.text != item.text && !focus.hasFocus) _setText(controller, item.text);
      }
    }
    for (final key in _itemControllers.keys.toList()) {
      if (liveKeys.contains(key)) continue;
      final controller = _itemControllers.remove(key);
      final focus = _itemFocus.remove(key);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller?.dispose();
        focus?.dispose();
      });
    }
    _syncNotes();
  }

  FocusNode _newItemFocus(String key) {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) {
        _focusedItemKey = key;
        _tpl?.session.setFocus(key);
      } else if (_focusedItemKey == key) {
        _focusedItemKey = null;
        // If focus moved to another item, that item reports in before this runs.
        scheduleMicrotask(() {
          if (_focusedItemKey == null) _tpl?.session.setFocus(null);
        });
      }
    });
    return node;
  }

  void _syncNotes({bool force = false}) {
    final notes = _fillRooms['match']?.session.lastView.doc['notes']?.toString() ?? '';
    if (_notesController.text != notes && (force || !_notesFocus.hasFocus)) _setText(_notesController, notes);
  }

  static void _setText(TextEditingController controller, String text) {
    final sel = controller.selection;
    controller.value = TextEditingValue(
      text: text,
      selection: sel.isValid
          ? TextSelection(baseOffset: min(sel.baseOffset, text.length), extentOffset: min(sel.extentOffset, text.length))
          : TextSelection.collapsed(offset: text.length),
    );
  }

  // ── Events & matches ───────────────────────────────────────────────────────

  Future<void> _loadEvents() async {
    final settings = await _api.fetchSettings() ?? _api.currentSettings;
    final year = settings?.year ?? DateTime.now().year;
    var eventKey = (settings?.eventKey ?? '').toLowerCase();
    List<EventModel> events = [];
    try {
      events = await _api.fetchEvents(year: year);
    } catch (_) {}
    final unique = <String, EventModel>{};
    for (final e in events) {
      if (e.eventKey.isNotEmpty) unique[e.eventKey.toLowerCase()] = e;
    }
    if (eventKey.isEmpty && unique.isNotEmpty) eventKey = unique.keys.first;
    if (!mounted) return;
    setState(() => _events = unique.values.toList());
    await _selectEvent(eventKey);
  }

  Future<void> _selectEvent(String eventKey) async {
    setState(() {
      _eventKey = eventKey;
      _matches = [];
      _matchKey = '';
      _completions.clear();
      _customMatchNames.clear();
    });
    if (eventKey.isEmpty) {
      await _syncFillRooms();
      return;
    }
    final results = await Future.wait([
      _api.fetchMatches(eventKey).catchError((_) => <MatchModel>[]),
      _api.fetchMatchChecklistsForEvent(eventKey),
    ]);
    if (!mounted || _eventKey != eventKey) return;
    final matches = (results[0] as List<MatchModel>).toList()..sort(_compareMatches);
    final completions = results[1] as Map<String, Map<String, dynamic>>;
    setState(() {
      _matches = matches;
      _completions.addAll(completions);
      for (final key in completions.keys.where((k) => k.startsWith('custom_'))) {
        _customMatchNames[key] = key.substring('custom_'.length).replaceAll('_', ' ');
      }
    });
    // Default to our next match without a finished checklist.
    final next = _visibleMatches.where((m) => !_isMatchComplete(m.matchKey, _completions[m.matchKey])).firstOrNull;
    await _selectMatch(_onlyOurs ? (next?.matchKey ?? '') : '');
  }

  Future<void> _selectMatch(String matchKey) async {
    if (matchKey == _customMatchValue) {
      final name = await _askCustomMatchName();
      if (name == null) {
        setState(() {});
        return;
      }
      final slug = name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
      if (slug.isEmpty) {
        setState(() {});
        return;
      }
      matchKey = 'custom_${slug.substring(0, min(50, slug.length))}';
      _customMatchNames[matchKey] = name;
    }
    setState(() => _matchKey = matchKey);
    await _syncFillRooms();
  }

  Future<String?> _askCustomMatchName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('checklist.custom_match_title', 'Custom / practice match')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(hintText: ctx.tr('checklist.custom_match_hint', 'e.g. Practice 3')),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(ctx.tr('checklist.add', 'Add')),
          ),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  static int _levelRank(String level) {
    final l = level.toLowerCase();
    if (['p', 'pr', 'pm', 'practice'].contains(l)) return 0;
    if (['q', 'qm', 'qual', 'qualification'].contains(l)) return 1;
    return 2;
  }

  static int _compareMatches(MatchModel a, MatchModel b) {
    final byLevel = _levelRank(a.compLevel) - _levelRank(b.compLevel);
    if (byLevel != 0) return byLevel;
    return (a.matchNumber ?? 0) - (b.matchNumber ?? 0);
  }

  static int? _teamNumberOf(String teamKey) => int.tryParse(RegExp(r'\d+').firstMatch(teamKey)?.group(0) ?? '');

  int get _ourTeam => _api.currentUser?.teamNumber ?? 0;

  String? _allianceOf(MatchModel? m) {
    if (m == null) return null;
    if (m.redTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'red';
    if (m.blueTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'blue';
    return null;
  }

  List<MatchModel> get _visibleMatches => _onlyOurs ? _ourMatches : _matches;

  String _matchLabel(MatchModel m) => m.label.isNotEmpty ? m.label : m.shortLabel;

  // ── UI ─────────────────────────────────────────────────────────────────────

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? ObsidianUITheme.errorRed : ObsidianUITheme.primaryAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _api.nonScoutingToolsEnabled;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isBarsVisible
          ? ObsidianGlassAppBar(
              title: context.tr('nav.match_checklist', 'Match Checklist'),
              subtitle: context.tr('subtitle.match_checklist', 'Pre-Match & On-Field Checks'),
              isOnline: _api.isOnline,
            )
          : null,
      body: !enabled
          ? _buildDisabled()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _buildOfflineBanner(),
                    _buildModeSwitcher(),
                    if (_editMode) ..._buildEditMode() else ..._buildFillMode(),
                  ],
                ),
    );
  }

  Widget _buildOfflineBanner() {
    final count = _sync.pendingOfflineCount;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('checklist-offline-banner'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ObsidianUITheme.warningOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ObsidianUITheme.warningOrange.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: ObsidianUITheme.warningOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('checklist.offline_banner', {'count': '$count'}),
              style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabled() {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return ListView(
      children: [
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('checklist.disabled_title', 'Non-scouting tools are turned off'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
              const SizedBox(height: 8),
              Text(
                context.tr('checklist.disabled_body', 'Turn on Non-Scouting Tools in Settings to use the Match Checklist.'),
                style: TextStyle(color: secondary),
              ),
              if (widget.onOpenSettings != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: Text(context.tr('checklist.open_settings', 'Open settings')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: Text(context.tr('checklist.tab_fill', 'Fill Out')),
          ),
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text(context.tr('checklist.tab_edit', 'Edit Checklists')),
          ),
        ],
        selected: {_editMode},
        onSelectionChanged: (s) {
          setState(() => _editMode = s.first);
          if (!_editMode) unawaited(_syncFillRooms());
        },
      ),
    );
  }

  Widget _buildStatusBar(ChecklistRoom? room) {
    final status = room?.status ?? CollabStatus.connecting;
    final (Color dot, String text) = switch (status) {
      CollabStatus.live => (Colors.greenAccent.shade400, context.tr('checklist.status.live', 'Live — changes save automatically')),
      CollabStatus.readonly => (Colors.greenAccent.shade400, context.tr('checklist.status.readonly', 'Live — view only')),
      CollabStatus.connecting => (Colors.orangeAccent, context.tr('checklist.status.connecting', 'Connecting to live editing…')),
      CollabStatus.reconnecting => (Colors.orangeAccent, context.tr('checklist.status.reconnecting', 'Reconnecting… your changes are kept')),
      CollabStatus.offline => (ObsidianUITheme.errorRed, context.tr('checklist.status.offline', 'Offline — your changes are kept on this device')),
    };
    final mySid = room?.session.sid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
          ),
          for (final editor in (room?.editors ?? const <CollabEditor>[]).take(6))
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: editor.sid == mySid ? '${editor.username} (${context.tr('checklist.you', 'you')})' : editor.username,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: editor.sid == mySid ? 0.45 : 1),
                  child: Text(
                    editor.username.length >= 2 ? editor.username.substring(0, 2).toUpperCase() : editor.username.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Fill out ───────────────────────────────────────────────────────────────

  List<Widget> _buildFillMode() {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final lists = _lists().where((l) => l.fillable.isNotEmpty).toList();
    final matchRoom = _fillRooms['match'];

    return [
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEventPicker(),
            const SizedBox(height: 12),
            _buildMatchPicker(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _onlyOurs,
              title: Text(context.tr('checklist.only_our_matches', 'Only our matches'), style: TextStyle(color: primary, fontSize: 14)),
              activeTrackColor: ObsidianUITheme.primaryAccent,
              onChanged: (v) => setState(() => _onlyOurs = v),
            ),
            if (matchRoom != null) ...[
              const SizedBox(height: 4),
              _buildStatusBar(matchRoom),
            ],
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_matchTitle(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 4),
            Text(_statusText(lists), style: TextStyle(fontSize: 12, color: secondary)),
          ],
        ),
      ),
      if (lists.isEmpty)
        ObsidianGlassCard(
          child: Text(
            context.tr('checklist.empty_template', 'No checklist items yet. Use Edit Checklists to create your lists.'),
            style: TextStyle(color: secondary, fontStyle: FontStyle.italic),
          ),
        )
      else
        for (final l in lists) _buildFillList(l),
      ObsidianGlassCard(
        child: TextField(
          controller: _notesController,
          focusNode: _notesFocus,
          enabled: matchRoom != null,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: context.tr('checklist.notes', 'Match notes'),
            hintText: context.tr('checklist.notes_hint', 'Anything the drive team should remember about this match...'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => _sync.edit(matchRoom, (doc) => doc['notes'] = value),
        ),
      ),
    ];
  }

  String _matchTitle() {
    if (_matchKey.isEmpty) return context.tr('checklist.select_match', 'Select a match');
    final match = _matches.where((m) => m.matchKey == _matchKey).firstOrNull;
    if (match == null) return _customMatchNames[_matchKey] ?? _matchKey;
    final alliance = _allianceOf(match);
    if (alliance == null) return _matchLabel(match);
    return '${_matchLabel(match)} · ${context.tr('checklist.alliance_$alliance', alliance == 'red' ? 'Red alliance' : 'Blue alliance')}';
  }

  String _statusText(List<_ChecklistList> lists) {
    if (_eventKey.isEmpty) return context.tr('checklist.select_event_first', 'Select an event first');
    final shown = lists.where((l) => l.scope != 'match' || (_matchKey.isNotEmpty && _isDue(l, _matchKey))).toList();
    if (_matchKey.isEmpty && shown.isEmpty) return context.tr('checklist.pick_match_hint', 'Pick a match to start checking items off.');
    var done = 0, total = 0, criticalLeft = 0;
    for (final l in shown) {
      final checked = _checkedIn(l.scope);
      for (final item in l.fillable) {
        total++;
        if (checked.containsKey(item.id)) {
          done++;
        } else if (item.priority == 'critical') {
          criticalLeft++;
        }
      }
    }
    final parts = <String>[
      total > 0 && done == total
          ? context.tr('checklist.all_done', 'All checks complete ✓')
          : context.tr('checklist.done_count', {'done': '$done', 'total': '$total'}),
    ];
    if (criticalLeft > 0) parts.add(context.tr('checklist.critical_left', {'count': '$criticalLeft'}));
    if (_matchKey.isEmpty) parts.add(context.tr('checklist.pick_match_hint', 'Pick a match to start checking items off.'));
    return parts.join(' · ');
  }

  Widget _buildEventPicker() {
    final keys = <String>{if (_eventKey.isNotEmpty) _eventKey, ..._events.map((e) => e.eventKey.toLowerCase())};
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _eventKey.isEmpty ? null : _eventKey,
      decoration: InputDecoration(labelText: context.tr('checklist.event', 'Event'), border: const OutlineInputBorder()),
      items: [
        for (final key in keys)
          DropdownMenuItem(
            value: key,
            child: Text(
              _events.where((e) => e.eventKey.toLowerCase() == key).map((e) => '${e.name} ($key)').firstOrNull ?? key,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != _eventKey) _selectEvent(v);
      },
    );
  }

  Widget _buildMatchPicker() {
    final visible = _visibleMatches;
    final seen = <String>{};
    final unique = visible.where((m) => seen.add(m.matchKey)).toList();
    final customKeys = _customMatchNames.keys.where((k) => !seen.contains(k)).toList();
    String doneMark(String key) => _isMatchComplete(key, _completions[key]) ? '✓ ' : '';
    final hint = _eventKey.isEmpty
        ? context.tr('checklist.select_event_first', 'Select an event first')
        : unique.isEmpty && customKeys.isEmpty
            ? (_onlyOurs && _matches.isNotEmpty
                ? context.tr('checklist.no_our_matches', 'No matches for our team yet')
                : context.tr('checklist.no_matches', 'No matches found'))
            : context.tr('checklist.select_match', 'Select a match');
    final values = {...unique.map((m) => m.matchKey), ...customKeys};
    return DropdownButtonFormField<String>(
      key: ValueKey('match-picker-$_eventKey-$_onlyOurs-${values.length}-$_matchKey'),
      isExpanded: true,
      initialValue: values.contains(_matchKey) ? _matchKey : null,
      hint: Text(hint),
      decoration: InputDecoration(labelText: context.tr('checklist.match', 'Match'), border: const OutlineInputBorder()),
      items: [
        for (final m in unique)
          DropdownMenuItem(
            value: m.matchKey,
            child: Text(
              '${doneMark(m.matchKey)}${_matchLabel(m)}${_allianceOf(m) == null ? '' : ' (${context.tr('checklist.alliance_short_${_allianceOf(m)}', _allianceOf(m) == 'red' ? 'Red' : 'Blue')})'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final key in customKeys)
          DropdownMenuItem(value: key, child: Text('${doneMark(key)}${_customMatchNames[key]}', overflow: TextOverflow.ellipsis)),
        if (_eventKey.isNotEmpty)
          DropdownMenuItem(value: _customMatchValue, child: Text(context.tr('checklist.custom_match', '+ Custom / practice match...'))),
      ],
      onChanged: (v) {
        if (v != null && v != _matchKey) _selectMatch(v);
      },
    );
  }

  Widget _listHeader(_ChecklistList l, {Widget? trailing}) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final scopeNote = switch (l.frequency) {
      'daily' => ' · ${context.tr('checklist.today', {'date': MaterialLocalizations.of(context).formatShortDate(DateTime.now())})}',
      'event' => ' · ${context.tr('checklist.whole_event', 'Shared for the whole event')}',
      _ => '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(_listTitle(l), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primary))),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 2),
        Text('${_frequencyLabel(l)}$scopeNote', style: TextStyle(fontSize: 12, color: secondary)),
      ],
    );
  }

  Widget _buildFillList(_ChecklistList l) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    Widget note(String text, {double opacity = 1}) => Opacity(
          opacity: opacity,
          child: ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _listHeader(l),
                const SizedBox(height: 8),
                Text(text, style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        );

    if (_eventKey.isEmpty) return note(context.tr('checklist.needs_event', 'Pick an event to fill this list.'));
    if (l.scope == 'match' && _matchKey.isEmpty) return note(context.tr('checklist.needs_match', 'Pick a match to fill this list.'));
    if (l.scope == 'match' && !_isDue(l, _matchKey)) {
      final next = _nextDue(l, _matchKey);
      return note(
        next == null
            ? context.tr('checklist.not_due_again', 'Not due again at this event.')
            : context.tr('checklist.not_due', {'match': _matchLabel(next)}),
        opacity: 0.6,
      );
    }

    final room = _fillRooms[l.scope];
    final checked = _checkedIn(l.scope);
    // Sorted by priority; within a priority, the order set in Edit Checklists.
    final items = l.fillable
      ..sort((a, b) {
        final byPriority = _priorities.indexOf(a.priority) - _priorities.indexOf(b.priority);
        return byPriority != 0 ? byPriority : a.index - b.index;
      });
    final done = items.where((i) => checked.containsKey(i.id)).length;
    final total = items.length;
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _listHeader(
            l,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$done/$total', style: TextStyle(color: secondary, fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: context.tr('checklist.reset_list', 'Reset'),
                  onPressed: room != null && done > 0 ? () => _confirmResetList(l, room) : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: total > 0 && done == total ? ObsidianUITheme.successGreen : ObsidianUITheme.primaryAccent,
              backgroundColor: ObsidianUITheme.getBorderColor(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items) _buildCheckRow(item, checked[item.id], room),
        ],
      ),
    );
  }

  Widget _buildCheckRow(_ChecklistItem item, dynamic check, ChecklistRoom? room) {
    final isChecked = check != null;
    final by = check is Map ? check['by']?.toString() : null;
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    return Opacity(
      opacity: isChecked ? 0.7 : 1,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: isChecked,
        activeColor: ObsidianUITheme.primaryAccent,
        onChanged: room != null ? (v) => _toggle(room, item.id, v ?? false) : null,
        title: Text(
          item.text.trim(),
          style: TextStyle(color: primary, decoration: isChecked ? TextDecoration.lineThrough : null),
        ),
        subtitle: by == null ? null : Text(by, style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
        secondary: _priorityChip(item.priority),
      ),
    );
  }

  Widget _priorityChip(String priority) {
    final color = switch (priority) {
      'critical' => ObsidianUITheme.errorRed,
      'high' => ObsidianUITheme.warningOrange,
      'normal' => ObsidianUITheme.primaryAccent,
      _ => ObsidianUITheme.getSecondaryTextColor(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        _priorityLabel(priority).toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
      ),
    );
  }

  String _priorityLabel(String priority) => context.tr('checklist.priority.$priority', switch (priority) {
        'critical' => 'Critical',
        'high' => 'High',
        'low' => 'Low',
        _ => 'Normal',
      });

  void _toggle(ChecklistRoom room, String itemId, bool checked) {
    final mark = {'by': _api.currentUser?.username ?? '', 'at': DateTime.now().millisecondsSinceEpoch};
    _sync.edit(room, (doc) {
      final c = doc['checked'] is Map ? Map<String, dynamic>.from(doc['checked'] as Map) : <String, dynamic>{};
      if (checked) {
        c.putIfAbsent(itemId, () => mark);
      } else {
        c.remove(itemId);
      }
      doc['checked'] = c;
    });
  }

  Future<void> _confirmResetList(_ChecklistList l, ChecklistRoom room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_listTitle(l)),
        content: Text(ctx.tr('checklist.reset_list_confirm', {'name': _listTitle(l)})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('checklist.reset_list', 'Reset'))),
        ],
      ),
    );
    if (ok != true) return;
    final ids = l.items.map((i) => i.id).toSet();
    _sync.edit(room, (doc) {
      final c = doc['checked'] is Map ? Map<String, dynamic>.from(doc['checked'] as Map) : <String, dynamic>{};
      c.removeWhere((k, _) => ids.contains(k));
      doc['checked'] = c;
    });
  }

  // ── Edit template ──────────────────────────────────────────────────────────

  List<Widget> _buildEditMode() {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final lists = _lists();
    return [
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('checklist.edit_help',
                  'Your whole team edits these lists together, live. Changes apply to every match, and checks already made on renamed items are kept.'),
              style: TextStyle(color: secondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _buildStatusBar(_tpl),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadStarterItems,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text(context.tr('checklist.load_starter', 'Load starter items')),
                ),
                FilledButton.icon(
                  onPressed: _addList,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: Text(context.tr('checklist.add_list', '+ Add list').replaceFirst(RegExp(r'^\+\s*'), '')),
                ),
              ],
            ),
          ],
        ),
      ),
      if (lists.isEmpty)
        ObsidianGlassCard(
          child: Text(context.tr('checklist.no_lists', 'No lists yet. Use "Add list" to create one.'),
              style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
        ),
      for (var i = 0; i < lists.length; i++) _buildEditList(lists[i], i, lists.length),
    ];
  }

  Widget _trackFocus(String id, Widget child) => Focus(
        onFocusChange: (has) => has ? _focusedListFields.add(id) : _focusedListFields.remove(id),
        child: child,
      );

  Widget _buildEditList(_ChecklistList l, int position, int count) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return ObsidianGlassCard(
      key: ValueKey('checklist-edit-list-${l.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _trackFocus(
            'title-${l.id}',
            TextField(
              controller: _listTitleControllers[l.id],
              maxLength: 60,
              decoration: InputDecoration(
                labelText: context.tr('checklist.list_name', 'List name'),
                hintText: context.tr('checklist.list_untitled', 'Untitled list'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (value) => _sync.edit(_tpl, (doc) {
                final lists = ensureChecklistLists(doc);
                (lists[l.id] as Map<String, dynamic>)['title'] = value;
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('freq-${l.id}-${l.frequency}'),
                  initialValue: l.frequency,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('checklist.frequency', 'How often'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [for (final f in _frequencies) DropdownMenuItem(value: f, child: Text(_frequencyOptionLabel(f)))],
                  onChanged: (f) {
                    if (f == null || f == l.frequency) return;
                    _sync.edit(_tpl, (doc) {
                      final list = ensureChecklistLists(doc)[l.id] as Map<String, dynamic>;
                      list['frequency'] = f;
                      if (f == 'every_n' && ((list['every'] as num?) ?? 0) < 2) list['every'] = 2;
                    });
                  },
                ),
              ),
              if (l.frequency == 'every_n') ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _trackFocus(
                    'every-${l.id}',
                    TextField(
                      controller: _everyControllers[l.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                      decoration: InputDecoration(
                        labelText: context.tr('checklist.every_label', 'Every how many of our matches'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n == null || n < 2) return;
                        _sync.edit(_tpl, (doc) => (ensureChecklistLists(doc)[l.id] as Map<String, dynamic>)['every'] = n.clamp(2, 99));
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: context.tr('checklist.move_list_up', 'Move list up'),
                onPressed: position == 0 ? null : () => _moveList(l.id, -1),
                icon: const Icon(Icons.keyboard_double_arrow_up_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.tr('checklist.move_list_down', 'Move list down'),
                onPressed: position == count - 1 ? null : () => _moveList(l.id, 1),
                icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 20),
              ),
              TextButton.icon(
                onPressed: () => _deleteList(l),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: ObsidianUITheme.errorRed),
                label: Text(context.tr('checklist.delete_list', 'Delete list'), style: TextStyle(color: ObsidianUITheme.errorRed)),
              ),
            ],
          ),
          const Divider(),
          if (l.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(context.tr('checklist.no_items', 'No items yet.'), style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
            ),
          for (var i = 0; i < l.items.length; i++) _buildEditRow(l, i),
          const SizedBox(height: 8),
          _buildAddRow(l.id),
        ],
      ),
    );
  }

  Widget _buildEditRow(_ChecklistList l, int position) {
    final item = l.items[position];
    final others = (_tpl?.editors ?? const <CollabEditor>[]).where((e) => e.focus == item.key && e.sid != _tpl?.session.sid).toList();
    final controller = _itemControllers[item.key] ??= TextEditingController(text: item.text);
    final focus = _itemFocus[item.key] ??= _newItemFocus(item.key);
    return Container(
      key: ValueKey('checklist-edit-${item.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: others.isEmpty ? EdgeInsets.zero : const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: others.isEmpty ? Colors.transparent : Colors.orangeAccent.withValues(alpha: 0.8), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                others.map((e) => context.tr('checklist.is_editing', {'name': e.username})).join(' · '),
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          TextField(
            controller: controller,
            focusNode: focus,
            maxLength: 200,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              counterText: '',
              hintText: context.tr('checklist.item_hint', 'Checklist item'),
            ),
            onChanged: (value) => _sync.edit(_tpl, (doc) => _fieldAt(doc, item.index)?['text'] = value),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _priorityDropdown(item.priority, (p) => _sync.edit(_tpl, (doc) => _fieldAt(doc, item.index)?['priority'] = p))),
              IconButton(
                tooltip: context.tr('checklist.move_up', 'Move up'),
                onPressed: position == 0 ? null : () => _moveItem(l, position, -1),
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.tr('checklist.move_down', 'Move down'),
                onPressed: position == l.items.length - 1 ? null : () => _moveItem(l, position, 1),
                icon: const Icon(Icons.arrow_downward_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.tr('checklist.remove', 'Remove'),
                onPressed: () => _sync.edit(_tpl, (doc) => _fields(doc).removeAt(item.index)),
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: ObsidianUITheme.errorRed),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow(String listId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _addControllers[listId],
          maxLength: 200,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
            hintText: context.tr('checklist.add_item_hint', 'Add an item...'),
          ),
          onSubmitted: (_) => _addItem(listId),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _priorityDropdown(_addPriority[listId] ?? _defaultPriority, (p) => setState(() => _addPriority[listId] = p))),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _addItem(listId),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.tr('checklist.add', 'Add')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _priorityDropdown(String value, void Function(String) onChanged) {
    return DropdownButtonFormField<String>(
      key: ValueKey('priority-$value'),
      initialValue: value,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: context.tr('checklist.priority', 'Priority'),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [for (final p in _priorities) DropdownMenuItem(value: p, child: Text(_priorityLabel(p)))],
      onChanged: (p) {
        if (p != null && p != value) onChanged(p);
      },
    );
  }

  static List<dynamic> _fields(Map<String, dynamic> doc) {
    final f = doc[ConfigSyncEngine.fieldsKey];
    if (f is List) return f;
    final list = <dynamic>[];
    doc[ConfigSyncEngine.fieldsKey] = list;
    return list;
  }

  static Map<String, dynamic>? _fieldAt(Map<String, dynamic> doc, int index) {
    final fields = _fields(doc);
    if (index < 0 || index >= fields.length || fields[index] is! Map) return null;
    final field = Map<String, dynamic>.from(fields[index] as Map);
    fields[index] = field;
    return field;
  }

  /// Swaps an item with its neighbour in the same list (all lists share one ordered array).
  void _moveItem(_ChecklistList l, int position, int delta) {
    final a = l.items[position].index;
    final b = l.items[position + delta].index;
    _sync.edit(_tpl, (doc) {
      final fields = _fields(doc);
      final tmp = fields[a];
      fields[a] = fields[b];
      fields[b] = tmp;
    });
  }

  /// Renumbers list order 0..n-1 in display order so lists can be swapped; returns `lists`.
  static Map<String, dynamic> _normalizedLists(Map<String, dynamic> doc) {
    final lists = ensureChecklistLists(doc);
    final ordered = checklistListsOf(doc);
    for (var i = 0; i < ordered.length; i++) {
      (lists[ordered[i].id] as Map<String, dynamic>)['order'] = i;
    }
    return lists;
  }

  void _moveList(String id, int delta) {
    _sync.edit(_tpl, (doc) {
      final lists = _normalizedLists(doc);
      final ordered = checklistListsOf(doc);
      final pos = ordered.indexWhere((l) => l.id == id);
      final other = pos + delta;
      if (pos < 0 || other < 0 || other >= ordered.length) return;
      final a = lists[id] as Map<String, dynamic>;
      final b = lists[ordered[other].id] as Map<String, dynamic>;
      final tmp = a['order'];
      a['order'] = b['order'];
      b['order'] = tmp;
    });
  }

  Future<void> _deleteList(_ChecklistList l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('checklist.delete_list', 'Delete list')),
        content: Text(ctx.tr('checklist.delete_list_confirm', {'name': _listTitle(l)})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('checklist.delete_list', 'Delete list'))),
        ],
      ),
    );
    if (ok != true) return;
    _sync.edit(_tpl, (doc) {
      ensureChecklistLists(doc).remove(l.id);
      _fields(doc).removeWhere((f) => f is Map && (f['section']?.toString() ?? 'pre') == l.id);
    });
  }

  void _addList() {
    final id = _newId();
    _sync.edit(_tpl, (doc) {
      final lists = _normalizedLists(doc);
      lists[id] = <String, dynamic>{'title': '', 'order': lists.length, 'frequency': 'match', 'every': 2};
    });
  }

  String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _addItem(String listId) {
    final controller = _addControllers[listId];
    if (controller == null) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final priority = _addPriority[listId] ?? _defaultPriority;
    controller.clear();
    _sync.edit(_tpl, (doc) => _fields(doc).add({'id': _newId(), 'section': listId, 'text': text, 'priority': priority}));
  }

  Future<void> _loadStarterItems() async {
    final lists = _lists();
    if (lists.any((l) => l.items.isNotEmpty)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('checklist.load_starter', 'Load starter items')),
          content: Text(ctx.tr('checklist.starter_confirm', 'Add the starter items to your lists? Existing items are kept.')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('checklist.add', 'Add'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final texts = {
      for (final entry in _starterItems.entries)
        entry.key: [for (final (key, priority) in entry.value) (context.tr('checklist.starter.$key', _starterFallback[key]!), priority)],
    };
    _sync.edit(_tpl, (doc) {
      final listsMap = _normalizedLists(doc);
      final fields = _fields(doc);
      for (final entry in texts.entries) {
        listsMap.putIfAbsent(entry.key, () => <String, dynamic>{'title': '', 'order': listsMap.length, 'frequency': 'match', 'every': 2});
        final existing = fields
            .whereType<Map>()
            .where((f) => f['section'] == entry.key)
            .map((f) => (f['text']?.toString() ?? '').trim().toLowerCase())
            .toSet();
        for (final (text, priority) in entry.value) {
          if (existing.contains(text.toLowerCase())) continue;
          fields.add({'id': _newId(), 'section': entry.key, 'text': text, 'priority': priority});
        }
      }
    });
  }
}
