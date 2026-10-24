import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/api_response.dart';
import '../models/pick_list_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_feedback.dart';

/// Ranked pick list for one event. The Do Not Pick list is the one Alliance Selection
/// uses: the server keeps those teams out of the ranking and returns them separately.
class PickListScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const PickListScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<PickListScreen> createState() => _PickListScreenState();
}

class _PickListScreenState extends State<PickListScreen> with SingleTickerProviderStateMixin {
  static const Color _dnpRed = Color(0xFFEF4444);

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  int _pendingSaves = 0;
  Timer? _syncTimer;

  List<EventModel> _events = [];
  String? _selectedEventKey;
  List<TeamModel> _allTeams = [];
  String _selectedMetric = 'weighted';

  List<int> _ranking = [];
  List<int> _dnp = [];
  Map<String, String> _notes = {};
  int _syncedAt = 0;
  Map<int, String> _pickedLabels = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeData();
    _startSyncTimer();
  }

  @override
  void didUpdateWidget(covariant PickListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _startSyncTimer();
      _refresh();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (!widget.isVisible) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && widget.apiService.isOnline && !_isLoading && _pendingSaves == 0 && widget.isVisible) {
        _refresh();
      }
    });
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    try {
      final currentEventKey = await widget.apiService.fetchCurrentEventKey();
      _events = List.from(await widget.apiService.fetchEvents());
      if (currentEventKey != null && currentEventKey.isNotEmpty) {
        _selectedEventKey = currentEventKey;
      } else if (_events.isNotEmpty) {
        _selectedEventKey = _events.first.eventKey;
      }
      if (_selectedEventKey != null && !_events.any((e) => e.eventKey == _selectedEventKey)) {
        _events.insert(0, EventModel(eventKey: _selectedEventKey!, name: 'Configured Event (${_selectedEventKey!.toUpperCase()})'));
      }
      if (_selectedEventKey != null) await _loadEvent(_selectedEventKey!);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadEvent(String eventKey) async {
    _syncedAt = 0;
    _allTeams = await widget.apiService.fetchTeams(eventKey);
    await _refresh(force: true);
  }

  Future<void> _refresh({bool force = false}) async {
    final eventKey = _selectedEventKey;
    if (eventKey == null) return;
    final results = await Future.wait([
      widget.apiService.getPickList(eventKey),
      widget.apiService.getAllianceSelection(eventKey),
    ]);
    if (!mounted || eventKey != _selectedEventKey) return;
    // Don't let a poll overwrite edits that are still on their way to the server.
    if (!force && _pendingSaves > 0) return;

    final board = results[0] as PickListBoard?;
    final selection = results[1] as Map<String, dynamic>?;
    setState(() {
      if (board != null && (force || board.updatedAt > _syncedAt)) _applyBoard(board);
      if (selection != null) _pickedLabels = _parsePickedLabels(selection['selectionJson']?.toString() ?? '{}');
    });
  }

  void _applyBoard(PickListBoard board) {
    _ranking = List.of(board.ranking);
    _dnp = List.of(board.dnp);
    _notes = Map.of(board.notes);
    if (board.updatedAt > _syncedAt) _syncedAt = board.updatedAt;
  }

  Map<int, String> _parsePickedLabels(String rawJson) {
    final labels = <int, String>{};
    const slots = {'captain': 'Captain', 'firstPick': 'First Pick', 'secondPick': 'Second Pick', 'backup': 'Backup'};
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map) return labels;
      for (int i = 1; i <= 8; i++) {
        final alliance = parsed['alliance$i'];
        if (alliance is! Map) continue;
        slots.forEach((slot, label) {
          final team = (alliance[slot] as num?)?.toInt();
          if (team != null) labels[team] = 'A$i $label';
        });
      }
    } catch (_) {}
    return labels;
  }

  // ── Saving ──────────────────────────────────────────────

  Future<void> _runSave(Future<ApiResponse<PickListBoard>> Function() save, {String? successMessage}) async {
    _pendingSaves++;
    final response = await save();
    _pendingSaves--;
    if (!mounted) return;
    if (response.success) {
      // Take the server's copy only when no newer edit is still in flight.
      if (_pendingSaves == 0 && response.data != null) setState(() => _applyBoard(response.data!));
      if (successMessage != null) ObsidianFeedback.showSuccess(context, message: successMessage);
    } else {
      ObsidianFeedback.showError(
        context,
        title: 'Pick List Not Saved',
        message: response.message?.isNotEmpty == true ? response.message! : 'Failed to save pick list.',
        statusCode: response.statusCode,
        isOffline: response.isOffline,
      );
      if (_pendingSaves == 0) _refresh(force: true);
    }
  }

  void _saveRanking() {
    final eventKey = _selectedEventKey;
    if (eventKey == null) return;
    final snapshot = List<int>.of(_ranking);
    _runSave(() => widget.apiService.savePickListRanking(eventKey, snapshot));
  }

  void _setDoNotPick(int teamNumber, bool dnp) {
    final eventKey = _selectedEventKey;
    if (eventKey == null) return;
    setState(() {
      if (dnp) {
        _ranking.remove(teamNumber);
        if (!_dnp.contains(teamNumber)) _dnp.add(teamNumber);
      } else {
        _dnp.remove(teamNumber);
      }
    });
    _runSave(
      () => widget.apiService.setDoNotPick(eventKey, teamNumber, dnp),
      successMessage: dnp ? '$teamNumber added to Do Not Pick' : '$teamNumber removed from Do Not Pick',
    );
  }

  // ── Editing ─────────────────────────────────────────────

  void _addToRanking(int teamNumber) {
    if (_ranking.contains(teamNumber) || _dnp.contains(teamNumber)) return;
    setState(() => _ranking.add(teamNumber));
    _saveRanking();
  }

  void _removeFromRanking(int teamNumber) {
    setState(() => _ranking.remove(teamNumber));
    _saveRanking();
  }

  void _moveTeam(int from, int to) {
    if (from < 0 || from >= _ranking.length) return;
    final target = to.clamp(0, _ranking.length - 1);
    if (from == target) return;
    setState(() {
      final team = _ranking.removeAt(from);
      _ranking.insert(target, team);
    });
    _saveRanking();
  }

  void _addAllByScore() {
    final toAdd = _unrankedTeams.map((t) => t.teamNumber).toList();
    if (toAdd.isEmpty) {
      ObsidianFeedback.showWarning(context, message: 'Every team is already ranked or on Do Not Pick.');
      return;
    }
    setState(() => _ranking.addAll(toAdd));
    _saveRanking();
    ObsidianFeedback.showSuccess(context, message: 'Added ${toAdd.length} teams by score.');
  }

  Future<void> _confirmClear() async {
    if (_ranking.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: const Text('Clear ranking?', style: TextStyle(color: Colors.white)),
        content: const Text('This removes every team from the ranking. Your Do Not Pick list is not changed.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _ranking.clear());
      _saveRanking();
    }
  }

  // ── Data ────────────────────────────────────────────────

  bool get _isFtc => widget.apiService.currentProgram.toUpperCase() == 'FTC';
  bool get _useEpa => !_isFtc && (widget.apiService.currentSettings?.useStatboticsEpa ?? false);
  bool get _useOpr => widget.apiService.currentSettings?.useTbaOpr ?? false;
  bool get _useExp => !_isFtc && (widget.apiService.currentSettings?.useMatch13Exp ?? false);

  TeamModel? _findTeam(int teamNumber) {
    for (final t in _allTeams) {
      if (t.teamNumber == teamNumber) return t;
    }
    return null;
  }

  double? _metricValue(TeamModel? team) {
    if (team == null) return null;
    switch (_selectedMetric) {
      case 'scouted':
        return team.averagePoints;
      case 'epa':
        return team.epa;
      case 'exp':
        return team.exp;
      case 'opr':
        return team.opr;
      default:
        return team.calculatedWeighted;
    }
  }

  /// Event teams that are neither ranked nor on Do Not Pick, best score first.
  List<TeamModel> get _unrankedTeams {
    final excluded = {..._ranking, ..._dnp};
    final list = _allTeams.where((t) => !excluded.contains(t.teamNumber)).toList();
    list.sort((a, b) {
      final va = _metricValue(a);
      final vb = _metricValue(b);
      if (va == null && vb == null) return a.teamNumber.compareTo(b.teamNumber);
      if (va == null) return 1;
      if (vb == null) return -1;
      final cmp = vb.compareTo(va);
      return cmp != 0 ? cmp : a.teamNumber.compareTo(b.teamNumber);
    });
    return list;
  }

  String _teamName(int teamNumber) {
    final team = _findTeam(teamNumber);
    if (team == null) return 'Not at this event';
    return team.nickname ?? team.name ?? '';
  }

  // ── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = widget.isBarsVisible ? 100.0 : 20.0;
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildHeader(context),
        TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: 'Ranking (${_ranking.length})'),
            Tab(text: 'Unranked (${_unrankedTeams.length})'),
            Tab(text: 'Do Not Pick (${_dnp.length})'),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRankingTab(bottomPad),
                    _buildUnrankedTab(bottomPad),
                    _buildDnpTab(bottomPad),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final metricItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'weighted', child: Text('Weighted')),
      const DropdownMenuItem(value: 'scouted', child: Text('Scouted')),
      if (_useEpa) const DropdownMenuItem(value: 'epa', child: Text('EPA')),
      if (_useExp) const DropdownMenuItem(value: 'exp', child: Text('EXP')),
      if (_useOpr) DropdownMenuItem(value: 'opr', child: Text(_isFtc ? 'FTC Scout OPR' : 'OPR')),
    ];
    final effectiveMetric = metricItems.any((i) => i.value == _selectedMetric) ? _selectedMetric : 'weighted';

    final uniqueEvents = <String, EventModel>{};
    for (final e in _events) {
      if (e.eventKey.isNotEmpty) uniqueEvents[e.eventKey] = e;
    }
    final eventList = uniqueEvents.values.toList();
    final effectiveEvent = eventList.any((e) => e.eventKey == _selectedEventKey) ? _selectedEventKey : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ObsidianGlassCard(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('nav.pick_list', 'Pick List'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('subtitle.pick_list', 'Ranked Picks & Do Not Pick'),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_pendingSaves > 0)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent, size: 20),
                    tooltip: 'Sync',
                    onPressed: () => _refresh(force: true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _dropdownBox(
                    DropdownButton<String>(
                      value: effectiveEvent,
                      isExpanded: true,
                      hint: const Text('Select event', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      dropdownColor: ObsidianUITheme.surface,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      items: eventList
                          .map((e) => DropdownMenuItem<String>(
                                value: e.eventKey,
                                child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) async {
                        if (val == null || val == _selectedEventKey) return;
                        setState(() {
                          _selectedEventKey = val;
                          _isLoading = true;
                        });
                        await _loadEvent(val);
                        if (mounted) setState(() => _isLoading = false);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _dropdownBox(
                    DropdownButton<String>(
                      value: effectiveMetric,
                      isExpanded: true,
                      dropdownColor: ObsidianUITheme.surface,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      items: metricItems,
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedMetric = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownBox(Widget child) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ),
    );
  }

  Widget _buildRankingTab(double bottomPad) {
    final available = _ranking.where((n) => !_pickedLabels.containsKey(n)).toList();
    final nextTeam = available.isNotEmpty ? available.first : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _ranking.isEmpty ? 'Private to your team' : '${available.length} of ${_ranking.length} still available',
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _ranking.isEmpty ? null : _confirmClear,
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Clear', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ranking.isEmpty
              ? _emptyState('No teams ranked yet. Add teams from the Unranked tab.')
              : ReorderableListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
                  buildDefaultDragHandles: false,
                  itemCount: _ranking.length,
                  onReorderItem: _moveTeam,
                  itemBuilder: (context, index) {
                    final teamNumber = _ranking[index];
                    return _buildRankedRow(
                      key: ValueKey('ranked_$teamNumber'),
                      index: index,
                      teamNumber: teamNumber,
                      isNext: teamNumber == nextTeam,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRankedRow({required Key key, required int index, required int teamNumber, required bool isNext}) {
    final pickedLabel = _pickedLabels[teamNumber];
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: const BorderSide(color: Colors.cyanAccent, width: 4),
          top: BorderSide(color: isNext ? ObsidianUITheme.successGreen : Colors.transparent),
          right: BorderSide(color: isNext ? ObsidianUITheme.successGreen : Colors.transparent),
          bottom: BorderSide(color: isNext ? ObsidianUITheme.successGreen : Colors.transparent),
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Icon(Icons.drag_indicator_rounded, color: Colors.white38, size: 20),
            ),
          ),
          SizedBox(
            width: 26,
            child: Text('${index + 1}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: _teamInfo(teamNumber, struck: pickedLabel != null)),
          if (pickedLabel != null) _statusChip(pickedLabel, Colors.white24, Colors.white70),
          if (isNext) _statusChip('Next', ObsidianUITheme.successGreen, Colors.black),
          _scoreChip(teamNumber),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
            color: ObsidianUITheme.surface,
            onSelected: (action) {
              switch (action) {
                case 'top':
                  _moveTeam(index, 0);
                  break;
                case 'up':
                  _moveTeam(index, index - 1);
                  break;
                case 'down':
                  _moveTeam(index, index + 1);
                  break;
                case 'remove':
                  _removeFromRanking(teamNumber);
                  break;
                case 'dnp':
                  _setDoNotPick(teamNumber, true);
                  break;
              }
            },
            itemBuilder: (context) => [
              if (index > 0) _menuItem('top', Icons.vertical_align_top_rounded, 'Move to top'),
              if (index > 0) _menuItem('up', Icons.keyboard_arrow_up_rounded, 'Move up'),
              if (index < _ranking.length - 1) _menuItem('down', Icons.keyboard_arrow_down_rounded, 'Move down'),
              _menuItem('remove', Icons.remove_circle_outline_rounded, 'Remove from ranking'),
              _menuItem('dnp', Icons.block_rounded, 'Add to Do Not Pick', color: _dnpRed),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color color = Colors.white}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildUnrankedTab(double bottomPad) {
    final query = _searchController.text.trim().toLowerCase();
    final unranked = _unrankedTeams;
    final shown = query.isEmpty
        ? unranked
        : unranked.where((t) {
            return t.teamNumber.toString().contains(query) ||
                (t.nickname ?? '').toLowerCase().contains(query) ||
                (t.name ?? '').toLowerCase().contains(query);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: context.tr('alliance_selection.placeholder_search_team_or_name', 'Search team # or name...'),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                      filled: true,
                      fillColor: Colors.black45,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: unranked.isEmpty ? null : _addAllByScore,
                icon: const Icon(Icons.playlist_add_rounded, size: 16),
                label: const Text('Add all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? _emptyState(_allTeams.isEmpty
                  ? 'No teams found for this event.'
                  : query.isNotEmpty
                      ? 'No matching teams.'
                      : 'Every team is ranked or on Do Not Pick.')
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final teamNumber = shown[index].teamNumber;
                    final pickedLabel = _pickedLabels[teamNumber];
                    return _plainRow(
                      borderColor: Colors.white24,
                      children: [
                        Expanded(child: _teamInfo(teamNumber, struck: pickedLabel != null)),
                        if (pickedLabel != null) _statusChip(pickedLabel, Colors.white24, Colors.white70),
                        _scoreChip(teamNumber),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent, size: 22),
                          tooltip: 'Add to end of ranking',
                          onPressed: () => _addToRanking(teamNumber),
                        ),
                        IconButton(
                          icon: const Icon(Icons.block_rounded, color: _dnpRed, size: 20),
                          tooltip: 'Add to Do Not Pick',
                          onPressed: () => _setDoNotPick(teamNumber, true),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDnpTab(double bottomPad) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            'Shared with the Do Not Pick list on Alliance Selection. These teams are kept out of the ranking.',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _dnp.isEmpty
              ? _emptyState('No teams on Do Not Pick.')
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
                  itemCount: _dnp.length,
                  itemBuilder: (context, index) {
                    final teamNumber = _dnp[index];
                    return _plainRow(
                      borderColor: _dnpRed,
                      children: [
                        Expanded(child: _teamInfo(teamNumber)),
                        _statusChip('DNP', _dnpRed, Colors.white),
                        IconButton(
                          icon: const Icon(Icons.undo_rounded, color: Colors.white70, size: 20),
                          tooltip: 'Remove from Do Not Pick',
                          onPressed: () => _setDoNotPick(teamNumber, false),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _plainRow({required Color borderColor, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Row(children: children),
    );
  }

  Widget _teamInfo(int teamNumber, {bool struck = false}) {
    final note = _notes[teamNumber.toString()];
    final decoration = struck ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$teamNumber',
                style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 14, decoration: decoration),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _teamName(teamNumber),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: struck ? Colors.white38 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: decoration,
                  ),
                ),
              ),
            ],
          ),
          if (note != null && note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color background, Color foreground) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _scoreChip(int teamNumber) {
    final value = _metricValue(_findTeam(teamNumber));
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(999)),
      child: Text(
        value == null ? '–' : value.toStringAsFixed(1),
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
