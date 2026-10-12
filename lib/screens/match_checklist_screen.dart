import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/config_collab/config_collab_session.dart';
import '../services/config_collab/config_sync_engine.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_app_bar.dart';
import '../widgets/obsidian_glass_card.dart';

/// Drive-team pre-match and on-the-field checklists (Settings > Non-Scouting Tools).
///
/// The team edits one checklist template; every match gets its own filled-out copy. Both are edited live
/// through the same sync as the config editor, so teammates' edits and checks merge as they happen.
/// Mirrors static/js/match-checklist.js on the website; the documents are shared between the two:
///
///   Template:   {sections: {pre: {title}, field: {title}}, fields: [{id, section, text, priority}]}
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

const _sectionIds = ['pre', 'field'];
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

class _ChecklistSection {
  final String id;
  final String? customTitle;
  final List<_ChecklistItem> items;

  const _ChecklistSection(this.id, this.customTitle, this.items);

  List<_ChecklistItem> get fillable => items.where((i) => i.fillable).toList();
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

  // Live sessions
  ConfigCollabSession? _tpl;
  ConfigCollabSession? _match;
  CollabStatus _tplStatus = CollabStatus.offline;
  CollabStatus _matchStatus = CollabStatus.offline;
  List<CollabEditor> _tplEditors = const [];
  List<CollabEditor> _matchEditors = const [];

  // Text fields that must survive live updates
  final Map<String, TextEditingController> _itemControllers = {};
  final Map<String, FocusNode> _itemFocus = {};
  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _addControllers = {};
  final Map<String, String> _addPriority = {};
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _notesFocus = FocusNode();
  String? _focusedItemKey;

  ApiService get _api => widget.apiService;

  @override
  void initState() {
    super.initState();
    for (final id in _sectionIds) {
      _titleControllers[id] = TextEditingController();
      _addControllers[id] = TextEditingController();
      _addPriority[id] = _defaultPriority;
    }
    _api.permissionsNotifier.addListener(_onPermissionsChanged);
    if (_api.nonScoutingToolsEnabled) unawaited(_init());
  }

  @override
  void dispose() {
    _api.permissionsNotifier.removeListener(_onPermissionsChanged);
    _tpl?.close();
    _match?.close();
    for (final c in [..._itemControllers.values, ..._titleControllers.values, ..._addControllers.values]) {
      c.dispose();
    }
    for (final f in _itemFocus.values) {
      f.dispose();
    }
    _notesController.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _onPermissionsChanged() {
    if (!mounted) return;
    final enabled = _api.nonScoutingToolsEnabled;
    if (enabled && _tpl == null) {
      unawaited(_init());
    } else if (!enabled && _tpl != null) {
      _tpl?.close();
      _match?.close();
      _tpl = null;
      _match = null;
    }
    setState(() {});
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    await _openTemplate();
    await _loadEvents();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _editMode = !_sections().any((s) => s.fillable.isNotEmpty);
    });
  }

  // ── Live sessions ──────────────────────────────────────────────────────────

  ConfigCollabSession _newSession({
    required Uri url,
    required bool Function(ConfigCollabSession s) isCurrent,
    required void Function() onChange,
    required void Function(CollabStatus status) onStatus,
    required void Function(List<CollabEditor> editors) onPresence,
  }) {
    late final ConfigCollabSession session;
    session = ConfigCollabSession(
      url: _api.isLoggedIn ? url : null,
      headers: () => _api.webSocketHeaders,
      onView: (view, source, user) {
        if (mounted && isCurrent(session)) onChange();
      },
      onStatus: (status) {
        if (mounted && isCurrent(session)) setState(() => onStatus(status));
      },
      onPresence: (editors) {
        if (mounted && isCurrent(session)) setState(() => onPresence(editors));
      },
      onNotice: (level, message) {
        if (!mounted || !isCurrent(session) || message.isEmpty) return;
        _snack(message, error: level == 'error');
      },
    );
    return session;
  }

  Future<void> _openTemplate() async {
    final session = _newSession(
      url: _api.matchChecklistCollabUri(),
      isCurrent: (s) => identical(_tpl, s),
      onChange: () {
        _syncTemplateControllers();
        setState(() {});
      },
      onStatus: (s) => _tplStatus = s,
      onPresence: (e) => _tplEditors = e,
    );
    _tpl = session;
    _tplStatus = CollabStatus.connecting;
    final doc = await _api.fetchMatchChecklistTemplate();
    if (!identical(_tpl, session)) return;
    session.load(doc ?? <String, dynamic>{});
    _syncTemplateControllers();
    session.connect();
  }

  Future<void> _openMatch(String eventKey, String matchKey) async {
    _match?.close();
    _match = null;
    _matchEditors = const [];
    if (eventKey.isEmpty || matchKey.isEmpty) {
      _notesController.text = '';
      return;
    }
    final session = _newSession(
      url: _api.matchChecklistCollabUri(eventKey: eventKey, matchKey: matchKey),
      isCurrent: (s) => identical(_match, s),
      onChange: () {
        _completions[matchKey] = Map<String, dynamic>.from(_match!.lastView.doc);
        _syncNotes();
        setState(() {});
      },
      onStatus: (s) => _matchStatus = s,
      onPresence: (e) => _matchEditors = e,
    );
    _match = session;
    _matchStatus = CollabStatus.connecting;
    final doc = await _api.fetchMatchChecklist(eventKey, matchKey);
    if (!identical(_match, session)) return;
    session.load(doc ?? <String, dynamic>{});
    _completions[matchKey] = Map<String, dynamic>.from(session.lastView.doc);
    _syncNotes(force: true);
    session.connect();
    if (mounted) setState(() {});
  }

  /// Applies a change to a live document and shares it.
  void _edit(ConfigCollabSession? session, void Function(Map<String, dynamic> doc) mutate) {
    if (session == null) return;
    final next = ConfigSyncEngine.cloneMap(session.lastView.doc);
    mutate(next);
    session.commit(next);
    if (identical(session, _match) && _matchKey.isNotEmpty) {
      _completions[_matchKey] = Map<String, dynamic>.from(session.lastView.doc);
    }
    if (identical(session, _tpl)) _syncTemplateControllers();
    setState(() {});
  }

  Future<void> _saveOffline(ConfigCollabSession? session) async {
    if (session == null) return;
    final isTemplate = identical(session, _tpl);
    final eventKey = _eventKey;
    final matchKey = _matchKey;
    try {
      final ok = await session.saveViaRest<bool>(
        () => isTemplate ? _api.fetchMatchChecklistTemplate() : _api.fetchMatchChecklist(eventKey, matchKey),
        (doc) => isTemplate ? _api.saveMatchChecklistTemplate(doc) : _api.saveMatchChecklist(eventKey, matchKey, doc),
        saved: (ok) => ok,
      );
      if (!mounted) return;
      _snack(ok ? context.tr('checklist.saved', 'Changes saved') : context.tr('checklist.save_failed', 'Could not save yet'), error: !ok);
    } catch (_) {
      if (mounted) _snack(context.tr('checklist.save_failed', 'Could not save yet'), error: true);
    }
    if (mounted) setState(() {});
  }

  // ── Documents ──────────────────────────────────────────────────────────────

  List<_ChecklistSection> _sections() {
    final view = _tpl?.lastView;
    final doc = view?.doc ?? const <String, dynamic>{};
    final fields = ConfigSyncEngine.fieldsOf(doc);
    final sectionsMeta = doc['sections'] is Map ? doc['sections'] as Map : const {};
    return _sectionIds.map((sectionId) {
      final items = <_ChecklistItem>[];
      for (var i = 0; i < fields.length; i++) {
        final f = fields[i];
        if (f is! Map || (f['section']?.toString() ?? 'pre') != sectionId) continue;
        final priority = f['priority']?.toString();
        items.add(_ChecklistItem(
          f['id']?.toString() ?? '',
          f['text']?.toString() ?? '',
          _priorities.contains(priority) ? priority! : _defaultPriority,
          i,
          i < (view?.keys.length ?? 0) ? view!.keys[i] : 'i$i',
        ));
      }
      final meta = sectionsMeta[sectionId];
      final title = meta is Map ? meta['title']?.toString() : null;
      return _ChecklistSection(sectionId, (title == null || title.trim().isEmpty) ? null : title, items);
    }).toList();
  }

  String _sectionTitle(_ChecklistSection s) =>
      s.customTitle ?? context.tr('checklist.section.${s.id}', s.id == 'pre' ? 'Pre-Match' : 'On the Field');

  Map<String, dynamic> _checkedOf(Map<String, dynamic>? completion) {
    final c = completion?['checked'];
    return c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{};
  }

  Map<String, dynamic> get _currentChecked => _checkedOf(_match?.lastView.doc);

  bool _isComplete(Map<String, dynamic>? completion) {
    final ids = _sections().expand((s) => s.fillable).map((i) => i.id).toList();
    if (ids.isEmpty || completion == null) return false;
    final checked = _checkedOf(completion);
    return ids.every(checked.containsKey);
  }

  // Keeps text fields in step with live edits without disturbing the one being typed in.
  void _syncTemplateControllers() {
    final sections = _sections();
    final liveKeys = <String>{};
    for (final s in sections) {
      final title = _titleControllers[s.id]!;
      final shownTitle = s.customTitle ?? '';
      if (title.text != shownTitle && !_titleHasFocus(s.id)) _setText(title, shownTitle);
      for (final item in s.items) {
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
  }

  final Set<String> _focusedTitles = {};
  bool _titleHasFocus(String sectionId) => _focusedTitles.contains(sectionId);

  FocusNode _newItemFocus(String key) {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) {
        _focusedItemKey = key;
        _tpl?.setFocus(key);
      } else if (_focusedItemKey == key) {
        _focusedItemKey = null;
        // If focus moved to another item, that item reports in before this runs.
        scheduleMicrotask(() {
          if (_focusedItemKey == null) _tpl?.setFocus(null);
        });
      }
    });
    return node;
  }

  void _syncNotes({bool force = false}) {
    final notes = _match?.lastView.doc['notes']?.toString() ?? '';
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
      _completions.clear();
      _customMatchNames.clear();
    });
    if (eventKey.isEmpty) {
      await _selectMatch('');
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
    final next = _visibleMatches.where((m) => !_isComplete(_completions[m.matchKey])).firstOrNull;
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
    await _openMatch(_eventKey, matchKey);
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

  String? _allianceOf(MatchModel m) {
    if (m.redTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'red';
    if (m.blueTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'blue';
    return null;
  }

  List<MatchModel> get _visibleMatches => _onlyOurs ? _matches.where((m) => _allianceOf(m) != null).toList() : _matches;

  String _matchLabel(MatchModel m) => m.label.isNotEmpty ? m.label : m.shortLabel;

  // ── UI ─────────────────────────────────────────────────────────────────────

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
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
                    _buildModeSwitcher(),
                    if (_editMode) ..._buildEditMode() else ..._buildFillMode(),
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
        onSelectionChanged: (s) => setState(() => _editMode = s.first),
      ),
    );
  }

  Widget _buildStatusBar(CollabStatus status, List<CollabEditor> editors, ConfigCollabSession? session) {
    final (Color dot, String text) = switch (status) {
      CollabStatus.live => (Colors.greenAccent.shade400, context.tr('checklist.status.live', 'Live — changes save automatically')),
      CollabStatus.readonly => (Colors.greenAccent.shade400, context.tr('checklist.status.readonly', 'Live — view only')),
      CollabStatus.connecting => (Colors.orangeAccent, context.tr('checklist.status.connecting', 'Connecting to live editing…')),
      CollabStatus.reconnecting => (Colors.orangeAccent, context.tr('checklist.status.reconnecting', 'Reconnecting… your changes are kept')),
      CollabStatus.offline => (ObsidianUITheme.errorRed, context.tr('checklist.status.offline', 'Offline — your changes are kept on this device')),
    };
    final mySid = session?.sid;
    final showOfflineSave = session != null && !session.isLive && session.hasUnsavedChanges;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
              for (final editor in editors.take(6))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: editor.sid == mySid
                        ? '${editor.username} (${context.tr('checklist.you', 'you')})'
                        : editor.username,
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
        ),
        if (showOfflineSave) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _saveOffline(session),
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: Text(context.tr('checklist.save_offline', 'Save offline changes')),
          ),
        ],
      ],
    );
  }

  // ── Fill out ───────────────────────────────────────────────────────────────

  List<Widget> _buildFillMode() {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final sections = _sections();
    final hasItems = sections.any((s) => s.fillable.isNotEmpty);
    final checked = _currentChecked;
    final hasMatch = _matchKey.isNotEmpty && _match != null;

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
            if (hasMatch) ...[
              const SizedBox(height: 4),
              _buildStatusBar(_matchStatus, _matchEditors, _match),
            ],
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_matchTitle(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                  const SizedBox(height: 4),
                  Text(_statusText(sections, checked), style: TextStyle(fontSize: 12, color: secondary)),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('checklist.reset', 'Reset this match'),
              onPressed: hasMatch ? _confirmReset : null,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ),
      ),
      if (!hasItems)
        ObsidianGlassCard(
          child: Text(
            context.tr('checklist.empty_template', 'No checklist items yet. Use Edit Checklists to create your pre-match and on-the-field lists.'),
            style: TextStyle(color: secondary, fontStyle: FontStyle.italic),
          ),
        )
      else
        for (final s in sections) _buildFillSection(s, checked, hasMatch),
      ObsidianGlassCard(
        child: TextField(
          controller: _notesController,
          focusNode: _notesFocus,
          enabled: hasMatch,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: context.tr('checklist.notes', 'Match notes'),
            hintText: context.tr('checklist.notes_hint', 'Anything the drive team should remember about this match...'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => _edit(_match, (doc) => doc['notes'] = value),
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

  String _statusText(List<_ChecklistSection> sections, Map<String, dynamic> checked) {
    if (_matchKey.isEmpty) return context.tr('checklist.pick_match_hint', 'Pick a match to start checking items off.');
    final items = sections.expand((s) => s.fillable).toList();
    final done = items.where((i) => checked.containsKey(i.id)).length;
    final parts = <String>[
      items.isNotEmpty && done == items.length
          ? context.tr('checklist.all_done', 'All checks complete ✓')
          : context.tr('checklist.done_count', {'done': '$done', 'total': '${items.length}'}),
    ];
    final criticalLeft = items.where((i) => i.priority == 'critical' && !checked.containsKey(i.id)).length;
    if (criticalLeft > 0) parts.add(context.tr('checklist.critical_left', {'count': '$criticalLeft'}));
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
    final customKeys = _customMatchNames.keys.where((k) => !visible.any((m) => m.matchKey == k)).toList();
    String doneMark(String key) => _isComplete(_completions[key]) ? '✓ ' : '';
    final hint = _eventKey.isEmpty
        ? context.tr('checklist.select_event_first', 'Select an event first')
        : visible.isEmpty && customKeys.isEmpty
            ? (_onlyOurs && _matches.isNotEmpty
                ? context.tr('checklist.no_our_matches', 'No matches for our team yet')
                : context.tr('checklist.no_matches', 'No matches found'))
            : context.tr('checklist.select_match', 'Select a match');
    final values = {...visible.map((m) => m.matchKey), ...customKeys};
    return DropdownButtonFormField<String>(
      key: ValueKey('match-picker-$_eventKey-$_onlyOurs-${values.length}'),
      isExpanded: true,
      initialValue: values.contains(_matchKey) ? _matchKey : null,
      hint: Text(hint),
      decoration: InputDecoration(labelText: context.tr('checklist.match', 'Match'), border: const OutlineInputBorder()),
      items: [
        for (final m in visible)
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

  Widget _buildFillSection(_ChecklistSection section, Map<String, dynamic> checked, bool hasMatch) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    // Sorted by priority; within a priority, the order set in Edit Checklists.
    final items = section.fillable
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
          Row(
            children: [
              Expanded(child: Text(_sectionTitle(section), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primary))),
              Text('$done/$total', style: TextStyle(color: secondary, fontWeight: FontWeight.w600)),
            ],
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
          if (items.isEmpty)
            Text(context.tr('checklist.empty_section', 'No items in this list.'), style: TextStyle(color: secondary, fontStyle: FontStyle.italic))
          else
            for (final item in items) _buildCheckRow(item, checked[item.id], hasMatch),
        ],
      ),
    );
  }

  Widget _buildCheckRow(_ChecklistItem item, dynamic check, bool hasMatch) {
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
        onChanged: hasMatch ? (v) => _toggle(item.id, v ?? false) : null,
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

  void _toggle(String itemId, bool checked) {
    final mark = {'by': _api.currentUser?.username ?? '', 'at': DateTime.now().millisecondsSinceEpoch};
    _edit(_match, (doc) {
      final c = doc['checked'] is Map ? Map<String, dynamic>.from(doc['checked'] as Map) : <String, dynamic>{};
      if (checked) {
        c.putIfAbsent(itemId, () => mark);
      } else {
        c.remove(itemId);
      }
      doc['checked'] = c;
    });
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('checklist.reset', 'Reset this match')),
        content: Text(ctx.tr('checklist.reset_confirm', 'Uncheck every item for this match?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('checklist.reset_button', 'Reset'))),
        ],
      ),
    );
    if (ok == true) _edit(_match, (doc) => doc['checked'] = <String, dynamic>{});
  }

  // ── Edit template ──────────────────────────────────────────────────────────

  List<Widget> _buildEditMode() {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
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
            _buildStatusBar(_tplStatus, _tplEditors, _tpl),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadStarterItems,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(context.tr('checklist.load_starter', 'Load starter items')),
            ),
          ],
        ),
      ),
      for (final s in _sections()) _buildEditSection(s),
    ];
  }

  Widget _buildEditSection(_ChecklistSection section) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            onFocusChange: (has) => has ? _focusedTitles.add(section.id) : _focusedTitles.remove(section.id),
            child: TextField(
              controller: _titleControllers[section.id],
              maxLength: 60,
              decoration: InputDecoration(
                labelText: context.tr('checklist.list_name', 'List name'),
                hintText: context.tr('checklist.section.${section.id}', section.id == 'pre' ? 'Pre-Match' : 'On the Field'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (value) => _edit(_tpl, (doc) {
                final sections = doc['sections'] is Map ? Map<String, dynamic>.from(doc['sections'] as Map) : <String, dynamic>{};
                final meta = sections[section.id] is Map ? Map<String, dynamic>.from(sections[section.id] as Map) : <String, dynamic>{};
                meta['title'] = value;
                sections[section.id] = meta;
                doc['sections'] = sections;
              }),
            ),
          ),
          const SizedBox(height: 12),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(context.tr('checklist.no_items', 'No items yet.'), style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
            ),
          for (var i = 0; i < section.items.length; i++) _buildEditRow(section, i),
          const SizedBox(height: 8),
          _buildAddRow(section.id),
        ],
      ),
    );
  }

  Widget _buildEditRow(_ChecklistSection section, int position) {
    final item = section.items[position];
    final others = _tplEditors.where((e) => e.focus == item.key && e.sid != _tpl?.sid).toList();
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
            onChanged: (value) => _edit(_tpl, (doc) => _fieldAt(doc, item.index)?['text'] = value),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _priorityDropdown(item.priority, (p) => _edit(_tpl, (doc) => _fieldAt(doc, item.index)?['priority'] = p))),
              IconButton(
                tooltip: context.tr('checklist.move_up', 'Move up'),
                onPressed: position == 0 ? null : () => _move(section, position, -1),
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.tr('checklist.move_down', 'Move down'),
                onPressed: position == section.items.length - 1 ? null : () => _move(section, position, 1),
                icon: const Icon(Icons.arrow_downward_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.tr('checklist.remove', 'Remove'),
                onPressed: () => _edit(_tpl, (doc) => _fields(doc).removeAt(item.index)),
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: ObsidianUITheme.errorRed),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow(String sectionId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _addControllers[sectionId],
          maxLength: 200,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
            hintText: context.tr('checklist.add_item_hint', 'Add an item...'),
          ),
          onSubmitted: (_) => _addItem(sectionId),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _priorityDropdown(_addPriority[sectionId]!, (p) => setState(() => _addPriority[sectionId] = p))),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _addItem(sectionId),
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

  /// Swaps an item with its neighbour in the same list (both lists share one ordered array).
  void _move(_ChecklistSection section, int position, int delta) {
    final a = section.items[position].index;
    final b = section.items[position + delta].index;
    _edit(_tpl, (doc) {
      final fields = _fields(doc);
      final tmp = fields[a];
      fields[a] = fields[b];
      fields[b] = tmp;
    });
  }

  String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _addItem(String sectionId) {
    final controller = _addControllers[sectionId]!;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final priority = _addPriority[sectionId]!;
    controller.clear();
    _edit(_tpl, (doc) => _fields(doc).add({'id': _newId(), 'section': sectionId, 'text': text, 'priority': priority}));
  }

  Future<void> _loadStarterItems() async {
    final sections = _sections();
    if (sections.any((s) => s.items.isNotEmpty)) {
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
    _edit(_tpl, (doc) {
      final fields = _fields(doc);
      for (final s in sections) {
        final existing = s.items.map((i) => i.text.trim().toLowerCase()).toSet();
        for (final (key, priority) in _starterItems[s.id] ?? const <(String, String)>[]) {
          final text = context.tr('checklist.starter.$key', _starterFallback[key]!);
          if (existing.contains(text.toLowerCase())) continue;
          fields.add({'id': _newId(), 'section': s.id, 'text': text, 'priority': priority});
        }
      }
    });
  }
}
