import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/battery_rotation.dart';
import '../services/battery_tracker_sync.dart';
import '../services/config_collab/config_collab_session.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/battery_match_banner.dart';
import '../widgets/obsidian_glass_app_bar.dart';
import '../widgets/obsidian_glass_card.dart';

/// The drive team's batteries and which one runs in each of our matches (Settings > Non-Scouting Tools).
///
/// Two live documents, edited through [BatteryTrackerSync] (which keeps offline edits and saves them later):
///   inventory  {batteries: {id: {name, type: "match"|"pit", order, retired, notes, createdAt}}}
///   event plan {matches: {matchKey: {skipped, pinned, used}}, startAt, autoMarkUsed}
/// The schedule is computed by [BatteryRotation]. Mirrors static/js/battery-tracker.js on the website; the
/// Match Checklist shows the same battery for each match.
class BatteryTrackerScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenChecklist;

  const BatteryTrackerScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onOpenSettings,
    this.onOpenChecklist,
  });

  @override
  State<BatteryTrackerScreen> createState() => _BatteryTrackerScreenState();
}

class _BatteryTrackerScreenState extends State<BatteryTrackerScreen> {
  bool _loading = true;
  List<EventModel> _events = [];
  String _eventKey = '';
  List<MatchModel> _matches = []; // our matches, in play order

  late final BatteryTrackerSync _sync = BatteryTrackerSync.of(widget.apiService);
  BatteryRoom? _inv;
  BatteryRoom? _plan;
  int _planGeneration = 0;

  // Text fields that must survive live updates, per battery id.
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _notesControllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final TextEditingController _addController = TextEditingController();
  String _addType = 'match';
  final _random = Random();

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
    for (final c in [..._nameControllers.values, ..._notesControllers.values]) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _addController.dispose();
    super.dispose();
  }

  void _releaseAll() {
    _sync.release(_inv);
    _sync.release(_plan);
    _inv = null;
    _plan = null;
  }

  void _onPermissionsChanged() {
    if (!mounted) return;
    final enabled = _api.nonScoutingToolsEnabled;
    if (enabled && _inv == null) {
      unawaited(_init());
    } else if (!enabled && _inv != null) {
      _releaseAll();
    }
    setState(() {});
  }

  void _onSyncChanged() {
    if (!mounted) return;
    _syncControllers();
    setState(() {});
  }

  void _onOfflineSaved() {
    if (mounted) _snack(context.tr('checklist.offline_saved', 'All offline changes saved'));
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    final inv = await _sync.acquire('');
    if (!mounted) {
      _sync.release(inv);
      return;
    }
    _inv = inv;
    _syncControllers();
    await _loadEvents();
    unawaited(_sync.resumeDrafts());
    if (mounted) setState(() => _loading = false);
  }

  // ── Documents ──────────────────────────────────────────────────────────────

  Map<String, dynamic> get _inventory => _inv?.doc ?? const <String, dynamic>{};

  Map<String, dynamic> get _planDoc => _plan != null && _plan!.eventKey == _eventKey ? _plan!.doc : const <String, dynamic>{};

  List<Battery> get _batteries => BatteryRotation.batteriesOf(_inventory);

  String _nameOf(String id) => _batteries.where((b) => b.id == id).map((b) => b.displayName).firstOrNull ?? id;

  Map<String, BatterySlot> get _schedule =>
      BatteryRotation.computeSchedule(_inventory, _planDoc, _matches.map((m) => m.matchKey).toList());

  void _editInventory(void Function(Map<String, dynamic> batteries, Map<String, dynamic> doc) mutate) {
    _sync.edit(_inv, (doc) {
      final batteries = doc['batteries'] is Map ? Map<String, dynamic>.from(doc['batteries'] as Map) : <String, dynamic>{};
      batteries.updateAll((_, v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
      doc['batteries'] = batteries;
      mutate(batteries, doc);
    });
  }

  void _editPlan(void Function(Map<String, dynamic> doc) mutate) => _sync.edit(_plan, mutate);

  /// Renumbers `order` to the current display order so neighbours can be swapped.
  void _normalizeOrder(Map<String, dynamic> batteries, Map<String, dynamic> doc) {
    final sorted = BatteryRotation.batteriesOf(doc);
    for (var i = 0; i < sorted.length; i++) {
      (batteries[sorted[i].id] as Map<String, dynamic>)['order'] = i;
    }
  }

  String _newId() => List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_random.nextInt(36)]).join();

  void _addBatteries(List<(String, String)> entries) {
    _editInventory((batteries, doc) {
      _normalizeOrder(batteries, doc);
      var order = batteries.length;
      for (final (name, type) in entries) {
        batteries[_newId()] = <String, dynamic>{
          'name': name,
          'type': type,
          'order': order++,
          'retired': false,
          'notes': '',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
      }
    });
  }

  void _move(Battery b, List<Battery> group, int delta) {
    final i = group.indexWhere((x) => x.id == b.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= group.length) return;
    final other = group[j].id;
    _editInventory((batteries, doc) {
      _normalizeOrder(batteries, doc);
      final mine = batteries[b.id] as Map<String, dynamic>?;
      final theirs = batteries[other] as Map<String, dynamic>?;
      if (mine == null || theirs == null) return;
      final o = theirs['order'];
      theirs['order'] = mine['order'];
      mine['order'] = o;
    });
  }

  // Keeps text fields in step with live edits without disturbing the one being typed in.
  void _syncControllers() {
    final live = <String>{};
    for (final b in _batteries) {
      live.add(b.id);
      final name = _nameControllers.putIfAbsent(b.id, () => TextEditingController(text: b.name));
      final notes = _notesControllers.putIfAbsent(b.id, () => TextEditingController(text: b.notes));
      final focus = _focusNodes.putIfAbsent('name-${b.id}', () => _newFocus(b.id));
      final notesFocus = _focusNodes.putIfAbsent('notes-${b.id}', () => _newFocus(b.id));
      if (name.text != b.name && !focus.hasFocus) _setText(name, b.name);
      if (notes.text != b.notes && !notesFocus.hasFocus) _setText(notes, b.notes);
    }
    for (final id in _nameControllers.keys.where((id) => !live.contains(id)).toList()) {
      final disposables = [_nameControllers.remove(id), _notesControllers.remove(id)];
      final focus = [_focusNodes.remove('name-$id'), _focusNodes.remove('notes-$id')];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in disposables) {
          c?.dispose();
        }
        for (final f in focus) {
          f?.dispose();
        }
      });
    }
  }

  FocusNode _newFocus(String batteryId) {
    final node = FocusNode();
    node.addListener(() => _inv?.session.setFocus(node.hasFocus ? batteryId : null));
    return node;
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

  static int? _teamNumberOf(String teamKey) => int.tryParse(RegExp(r'\d+').firstMatch(teamKey)?.group(0) ?? '');

  int get _ourTeam => _api.currentUser?.teamNumber ?? 0;

  String? _allianceOf(MatchModel m) {
    if (m.redTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'red';
    if (m.blueTeams.any((k) => _teamNumberOf(k) == _ourTeam)) return 'blue';
    return null;
  }

  Future<void> _selectEvent(String eventKey) async {
    final generation = ++_planGeneration;
    setState(() {
      _eventKey = eventKey;
      _matches = [];
    });
    final previous = _plan;
    _plan = null;
    _sync.release(previous);
    if (eventKey.isEmpty) return;
    final results = await Future.wait<Object?>([
      _api.fetchMatches(eventKey).catchError((_) => <MatchModel>[]),
      _sync.acquire(eventKey),
    ]);
    final room = results[1] as BatteryRoom;
    if (!mounted || generation != _planGeneration) {
      _sync.release(room);
      return;
    }
    final ours = (results[0] as List<MatchModel>).where((m) => _allianceOf(m) != null).toList()
      ..sort((a, b) => BatteryRotation.compareMatchOrder(a.compLevel, a.matchNumber, a.matchKey, b.compLevel, b.matchNumber, b.matchKey));
    final seen = <String>{};
    setState(() {
      _plan = room;
      _matches = ours.where((m) => seen.add(m.matchKey)).toList();
    });
  }

  String _matchLabel(MatchModel m) => m.label.isNotEmpty ? m.label : m.shortLabel;

  // ── UI ─────────────────────────────────────────────────────────────────────

  void _snack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: ObsidianUITheme.primaryAccent,
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
              title: context.tr('nav.battery_tracker', 'Battery Tracker'),
              subtitle: context.tr('subtitle.battery_tracker', 'Batteries and which one runs each match'),
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
                    _buildEventCard(),
                    _buildInventoryCard(),
                    _buildRotationCard(),
                  ],
                ),
    );
  }

  Widget _buildOfflineBanner() {
    if (_sync.pendingOfflineCount == 0) return const SizedBox.shrink();
    return Container(
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
              context.tr('battery.offline.banner',
                  "You're offline. Battery changes can't be saved until you're back online. They're kept on this device and will save automatically when you reconnect."),
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
                context.tr('battery.disabled.notice', 'Turn on "Non-Scouting Tools" in Personal Settings to use the Battery Tracker.'),
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

  Widget _buildStatusBar(BatteryRoom? room) {
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
      margin: const EdgeInsets.only(top: 8),
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
          Expanded(child: Text(text, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12))),
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

  Widget _buildEventCard() {
    final keys = <String>{if (_eventKey.isNotEmpty) _eventKey, ..._events.map((e) => e.eventKey.toLowerCase())};
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('battery.subtitle',
                'Add your batteries and get the battery to run in each of our matches. Pit batteries stay out of the rotation. Shared live with your team.'),
            style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
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
          ),
          if (widget.onOpenChecklist != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onOpenChecklist,
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: Text(context.tr('battery.open_checklist', 'Open Match Checklist')),
              ),
            ),
        ],
      ),
    );
  }

  // ── Inventory ──────────────────────────────────────────────────────────────

  Widget _buildInventoryCard() {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final all = _batteries;
    final usage = BatteryRotation.usageByBattery(_planDoc, _matches.map((m) => m.matchKey).toList());
    final groups = [
      ('match', context.tr('battery.group.match', 'Match batteries (in rotation)'), all.where((b) => !b.retired && !b.isPit).toList()),
      ('pit', context.tr('battery.group.pit', 'Pit batteries (never in a match)'), all.where((b) => !b.retired && b.isPit).toList()),
      ('retired', context.tr('battery.group.retired', 'Retired'), all.where((b) => b.retired).toList()),
    ];
    Widget empty(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text, style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
        );

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('battery.inventory.title', 'Batteries'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primary)),
          const SizedBox(height: 4),
          Text(
            context.tr('battery.inventory.notice', 'Match batteries take turns in the order shown. Pit batteries are for the pit and never go in a match.'),
            style: TextStyle(color: secondary, fontSize: 12),
          ),
          _buildStatusBar(_inv),
          if (all.isEmpty) ...[
            empty(context.tr('battery.inventory.empty', 'No batteries yet. Add them below, or start with six numbered batteries.')),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _addBatteries([for (var n = 1; n <= 6; n++) ('B$n', 'match')]),
                child: Text(context.tr('battery.inventory.quick_add', 'Add B1–B6')),
              ),
            ),
          ] else
            for (final (id, title, list) in groups)
              if (list.isNotEmpty || id != 'retired') ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text('${title.toUpperCase()} · ${list.length}',
                      style: TextStyle(color: secondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
                if (list.isEmpty)
                  empty(id == 'match'
                      ? context.tr('battery.group.match_empty', "No match batteries. Set a battery's type to Match to put it in the rotation.")
                      : context.tr('battery.group.pit_empty', 'No pit batteries.'))
                else
                  for (final b in list) _buildBatteryRow(b, list, id == 'retired', usage[b.id] ?? const []),
              ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addController,
                  maxLength: 40,
                  decoration: InputDecoration(
                    hintText: context.tr('battery.add.placeholder', 'Battery name, e.g. B7'),
                    counterText: '',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitAdd(),
                ),
              ),
              const SizedBox(width: 8),
              _typeDropdown(_addType, (v) => setState(() => _addType = v)),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submitAdd, child: Text(context.tr('battery.add.button', '+ Add'))),
            ],
          ),
        ],
      ),
    );
  }

  void _submitAdd() {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    _addBatteries([(name, _addType)]);
    _addController.clear();
  }

  Widget _typeDropdown(String value, ValueChanged<String> onChanged) => DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(value: 'match', child: Text(context.tr('battery.type.match', 'Match'))),
          DropdownMenuItem(value: 'pit', child: Text(context.tr('battery.type.pit', 'Pit'))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );

  Widget _buildBatteryRow(Battery b, List<Battery> group, bool retired, List<String> used) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final index = group.indexWhere((x) => x.id == b.id);
    final last = used.isEmpty ? null : _matches.where((m) => m.matchKey == used.last).firstOrNull;
    final editors = (_inv?.editors ?? const <CollabEditor>[]).where((e) => e.focus == b.id && e.sid != _inv?.session.sid).toList();
    return Opacity(
      opacity: retired ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: editors.isNotEmpty ? ObsidianUITheme.warningOrange : ObsidianUITheme.getBorderColor(context),
            width: editors.isNotEmpty ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!retired)
              Column(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('battery.action.move_up', 'Move up'),
                    onPressed: index > 0 ? () => _move(b, group, -1) : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('battery.action.move_down', 'Move down'),
                    onPressed: index < group.length - 1 ? () => _move(b, group, 1) : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (editors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        editors.map((e) => e.username).join(', '),
                        style: const TextStyle(color: ObsidianUITheme.warningOrange, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameControllers[b.id],
                          focusNode: _focusNodes['name-${b.id}'],
                          maxLength: 40,
                          decoration: InputDecoration(
                            hintText: context.tr('battery.name_placeholder', 'Name'),
                            counterText: '',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) => _editInventory((batteries, _) => (batteries[b.id] as Map<String, dynamic>?)?['name'] = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _typeDropdown(
                        b.type,
                        (v) => _editInventory((batteries, _) => (batteries[b.id] as Map<String, dynamic>?)?['type'] = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesControllers[b.id],
                    focusNode: _focusNodes['notes-${b.id}'],
                    maxLength: 200,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: context.tr('battery.notes_placeholder', 'Notes (age, condition, voltage…)'),
                      counterText: '',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => _editInventory((batteries, _) => (batteries[b.id] as Map<String, dynamic>?)?['notes'] = v),
                  ),
                  if (used.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        batteryText(context, 'battery.stats.used', 'Ran {count}× at this event · last {match}',
                            {'count': '${used.length}', 'match': last == null ? used.last : _matchLabel(last)}),
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (action) => _onBatteryAction(b, action),
              itemBuilder: (ctx) => [
                if (retired) ...[
                  PopupMenuItem(value: 'restore', child: Text(ctx.tr('battery.action.restore', 'Restore'))),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(ctx.tr('battery.action.delete', 'Delete'), style: const TextStyle(color: ObsidianUITheme.errorRed)),
                  ),
                ] else
                  PopupMenuItem(value: 'retire', child: Text(ctx.tr('battery.action.retire', 'Retire'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onBatteryAction(Battery b, String action) async {
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(b.displayName),
          content: Text(batteryText(ctx, 'battery.delete_confirm',
              'Delete battery "{name}"? Matches it ran in will lose that record. Retire it instead to keep its history.', {'name': b.displayName})),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('checklist.cancel', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('battery.action.delete', 'Delete'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _editInventory((batteries, _) {
      final entry = batteries[b.id] as Map<String, dynamic>?;
      if (entry == null) return;
      switch (action) {
        case 'retire':
          entry['retired'] = true;
        case 'restore':
          entry['retired'] = false;
        case 'delete':
          batteries.remove(b.id);
      }
    });
  }

  // ── Rotation ───────────────────────────────────────────────────────────────

  Widget _buildRotationCard() {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    Widget note(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text, style: TextStyle(color: secondary, fontStyle: FontStyle.italic)),
        );

    final rotation = BatteryRotation.rotationOf(_inventory);
    final children = <Widget>[];
    if (_eventKey.isEmpty) {
      children.add(note(context.tr('battery.rotation.needs_event', 'Pick an event to see which battery runs in each match.')));
    } else if (_plan == null) {
      children.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
    } else {
      children
        ..add(_buildStatusBar(_plan))
        ..add(_buildRotationSettings(rotation));
      if (_matches.isEmpty) {
        children.add(note(context.tr('battery.rotation.no_matches', 'No matches for our team at this event yet. They show up here once the schedule is out.')));
      } else if (rotation.isEmpty) {
        children.add(note(context.tr('battery.rotation.no_batteries', 'Add a match battery to build the rotation.')));
      } else {
        final slots = _schedule;
        final nextKey = _matches.where((m) => slots[m.matchKey]?.source != 'used').firstOrNull?.matchKey;
        for (final m in _matches) {
          children.add(_buildMatchRow(m, slots[m.matchKey]!, m.matchKey == nextKey));
        }
      }
    }

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('battery.rotation.title', 'Match rotation'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primary)),
          const SizedBox(height: 4),
          Text(
            context.tr('battery.rotation.notice', 'Skip a battery to give the match the next one; later matches keep rotating from there.'),
            style: TextStyle(color: secondary, fontSize: 12),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRotationSettings(List<Battery> rotation) {
    final plan = _planDoc;
    final startAt = plan['startAt'] is String && rotation.any((b) => b.id == plan['startAt']) ? plan['startAt'] as String : '';
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('start-at-$startAt-${rotation.length}'),
            isExpanded: true,
            initialValue: startAt,
            decoration: InputDecoration(
              labelText: context.tr('battery.settings.start_at', 'First battery at this event'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(context.tr('battery.settings.start_first', 'First in the list'))),
              for (final b in rotation) DropdownMenuItem(value: b.id, child: Text(b.displayName)),
            ],
            onChanged: (v) => _editPlan((doc) {
              if (v == null || v.isEmpty) {
                doc.remove('startAt');
              } else {
                doc['startAt'] = v;
              }
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: BatteryRotation.autoMarkUsed(plan),
            activeTrackColor: ObsidianUITheme.primaryAccent,
            title: Text(
              context.tr('battery.settings.auto_mark', "Mark a match's battery as used when its checklist is finished"),
              style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
            ),
            onChanged: (on) => _editPlan((doc) {
              if (on) {
                doc.remove('autoMarkUsed');
              } else {
                doc['autoMarkUsed'] = false;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchRow(MatchModel m, BatterySlot slot, bool isNext) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final alliance = _allianceOf(m);
    final pinned = BatteryRotation.pinnedOf(_planDoc, m.matchKey);
    final usable = _batteries.where((b) => !b.retired).toList();
    return Opacity(
      opacity: slot.source == 'used' ? 0.7 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isNext ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context),
            width: isNext ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_matchLabel(m), style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                if (alliance != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    context.tr('checklist.alliance_short_$alliance', alliance == 'red' ? 'Red' : 'Blue').toUpperCase(),
                    style: TextStyle(
                      color: alliance == 'red' ? Colors.redAccent : Colors.lightBlueAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const Spacer(),
                if (slot.source != 'used')
                  PopupMenuButton<String>(
                    tooltip: context.tr('battery.action.pin', 'Pin a battery'),
                    icon: Icon(pinned.isEmpty ? Icons.push_pin_outlined : Icons.push_pin_rounded, size: 20),
                    onSelected: (id) => _editPlan((doc) => BatteryRotation.pin(doc, m.matchKey, id)),
                    itemBuilder: (ctx) => [
                      CheckedPopupMenuItem(value: '', checked: pinned.isEmpty, child: Text(ctx.tr('battery.pin.auto', 'Auto'))),
                      for (final b in usable)
                        CheckedPopupMenuItem(
                          value: b.id,
                          checked: pinned == b.id,
                          child: Text(batteryText(ctx, 'battery.pin.option', 'Pin {name}', {'name': b.displayName})),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            BatteryMatchBanner(
              slot: slot,
              nameOf: _nameOf,
              onSkip: () => _editPlan((doc) => BatteryRotation.skip(doc, m.matchKey, slot.batteryId!, _api.currentUser?.username ?? '')),
              onUnskip: () => _editPlan((doc) => BatteryRotation.clearSkips(doc, m.matchKey)),
              onMarkUsed: () => _editPlan((doc) => BatteryRotation.markUsed(doc, m.matchKey, slot.batteryId)),
              onUnmarkUsed: () => _editPlan((doc) => BatteryRotation.markUsed(doc, m.matchKey, null)),
            ),
          ],
        ),
      ),
    );
  }
}
