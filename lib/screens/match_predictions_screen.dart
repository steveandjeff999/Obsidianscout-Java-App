import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/match_pick_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/match_prediction_card.dart';
import '../widgets/obsidian_glass_card.dart';

/// Match predictions game: pick a winner for every match at the current event (Predict tab) and see the
/// team's scouts ranked by accuracy for one event or a whole season (Leaderboard tab). Same data as the
/// website's match-predictions.html and prediction-leaderboard.html.
class MatchPredictionsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const MatchPredictionsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<MatchPredictionsScreen> createState() => _MatchPredictionsScreenState();
}

enum _ShowFilter { open, needs, done, all }

class _MatchPredictionsScreenState extends State<MatchPredictionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // Predict tab
  bool _loading = true;
  bool _turnedOff = false;
  String _eventKey = '';
  List<MatchModel> _matches = [];
  Map<String, MatchPickStatus> _picks = {};
  final Set<String> _busy = {};
  _ShowFilter _filter = _ShowFilter.open;
  String _teamQuery = '';

  // Leaderboard tab
  bool _boardLoading = false;
  bool _boardLoaded = false;
  String _scope = 'event';
  String? _boardEventKey;
  int _boardYear = DateTime.now().year;
  PickLeaderboardOptions _options = const PickLeaderboardOptions();
  PickLeaderboard? _board;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_boardLoaded && !_boardLoading && !_tabs.indexIsChanging) _loadLeaderboard(initial: true);
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant MatchPredictionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _load();
      if (_boardLoaded) _loadLeaderboard();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = widget.apiService;
    final eventKey = api.currentSettings?.eventKey ?? '';
    if (!api.matchPredictionsEnabled) {
      setState(() {
        _turnedOff = true;
        _loading = false;
      });
      return;
    }
    await api.flushPendingMatchPicks();
    final results = await Future.wait([
      eventKey.isEmpty ? Future.value(<MatchModel>[]) : api.fetchMatches(eventKey),
      eventKey.isEmpty ? Future.value(<String, MatchPickStatus>{}) : api.fetchMatchPicks(eventKey),
    ]);
    if (!mounted) return;
    final picks = results[1] as Map<String, MatchPickStatus>?;
    setState(() {
      _eventKey = eventKey;
      _turnedOff = picks == null;
      _matches = List<MatchModel>.from(results[0] as List<MatchModel>)..sort(MatchModel.compareMatches);
      _picks = picks ?? {};
      _loading = false;
    });
  }

  MatchPickStatus _statusOf(String matchKey) => _picks[matchKey] ?? MatchPickStatus(matchKey: matchKey);

  Future<void> _pick(MatchModel match, String winner) async {
    final before = _statusOf(match.matchKey);
    setState(() {
      _busy.add(match.matchKey);
      _picks[match.matchKey] = before.withPick(winner);
    });
    final next = await saveMatchPickWithFeedback(context, widget.apiService, _eventKey, before, winner);
    if (!mounted) return;
    setState(() {
      _busy.remove(match.matchKey);
      _picks[match.matchKey] = next;
    });
  }

  bool _passesFilter(MatchModel m) {
    final s = _statusOf(m.matchKey);
    final done = s.locked || s.result != null;
    switch (_filter) {
      case _ShowFilter.needs:
        if (done || s.predictedWinner != null) return false;
        break;
      case _ShowFilter.done:
        if (!done) return false;
        break;
      case _ShowFilter.all:
        break;
      case _ShowFilter.open:
        if (done) return false;
    }
    final q = _teamQuery.trim().replaceFirst(RegExp(r'^(frc|ftc)', caseSensitive: false), '');
    if (q.isNotEmpty) {
      final teams = [...m.redTeams, ...m.blueTeams]
          .map((k) => k.replaceFirst(RegExp(r'^(frc|ftc)', caseSensitive: false), ''));
      if (!teams.any((t) => t.startsWith(q))) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------ leaderboard

  Future<void> _loadLeaderboard({bool initial = false}) async {
    if (_boardLoading) return;
    final api = widget.apiService;
    setState(() => _boardLoading = true);
    PickLeaderboard? board;
    try {
      if (initial) {
        final options = await api.fetchPickLeaderboardOptions();
        final current = (api.currentSettings?.eventKey ?? '').toLowerCase();
        final year = api.currentSettings?.year ?? DateTime.now().year;
        final events = List<PickLeaderboardEvent>.from(options.events);
        if (current.isNotEmpty && !events.any((e) => e.eventKey.toLowerCase() == current)) {
          events.insert(0, PickLeaderboardEvent(eventKey: current, year: year));
        }
        final years = {...options.years, year}.toList()..sort((a, b) => b.compareTo(a));
        _options = PickLeaderboardOptions(years: years, events: events);
        _boardEventKey = current.isNotEmpty
            ? (events.firstWhere((e) => e.eventKey.toLowerCase() == current, orElse: () => events.first).eventKey)
            : (events.isNotEmpty ? events.first.eventKey : null);
        _boardYear = year;
      }
      board = _scope == 'event'
          ? (_boardEventKey == null ? null : await api.fetchPickLeaderboard(eventKey: _boardEventKey))
          : await api.fetchPickLeaderboard(year: _boardYear);
    } finally {
      if (mounted) {
        setState(() {
          _board = board;
          _boardLoading = false;
          _boardLoaded = true;
        });
      }
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
    }
    if (_turnedOff) return _buildTurnedOff(context);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: ObsidianUITheme.primaryAccent,
          unselectedLabelColor: muted,
          indicatorColor: ObsidianUITheme.primaryAccent,
          tabs: [
            Tab(icon: const Icon(Icons.flag_rounded, size: 18), text: context.tr('predictions.tab_predict', 'Predict')),
            Tab(
              icon: const Icon(Icons.emoji_events_rounded, size: 18),
              text: context.tr('predictions.tab_leaderboard', 'Leaderboard'),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildPredictTab(context, primary, muted),
              _buildLeaderboardTab(context, primary, muted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTurnedOff(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('predictions.off_title', 'Match predictions are off'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('predictions.off_notice', 'A team admin can turn them on in Admin Settings, under Permissions.'),
                style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpi(BuildContext context, String title, String value, String sub) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: muted)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ObsidianUITheme.getPrimaryTextColor(context))),
          Text(sub, maxLines: 2, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }

  Widget _buildPredictTab(BuildContext context, Color primary, Color muted) {
    final statuses = _matches.map((m) => _statusOf(m.matchKey)).toList();
    final picked = statuses.where((s) => s.predictedWinner != null).length;
    final needs = statuses.where((s) => !s.locked && s.result == null && s.predictedWinner == null).length;
    final scored = statuses.where((s) => s.correct != null).toList();
    final correct = scored.where((s) => s.correct == true).length;
    final accuracy = scored.isEmpty ? '-' : '${(correct * 1000 / scored.length).round() / 10}%';
    final shown = _matches.where(_passesFilter).toList();

    return RefreshIndicator(
      color: ObsidianUITheme.primaryAccent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4, bottom: widget.isBarsVisible ? 120 : 20),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('predictions.page_notice',
                      'Pick who you think will win each match. You can change a pick until the result comes in, then it counts toward the leaderboard.'),
                  style: TextStyle(fontSize: 13, color: muted, height: 1.35),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _kpi(context, context.tr('predictions.kpi_picks', 'Picks Made'), '$picked',
                        context.tr('predictions.kpi_picks_sub', 'of {n} matches').replaceAll('{n}', '${_matches.length}')),
                    _kpi(context, context.tr('predictions.kpi_needs', 'Still To Pick'), '$needs',
                        context.tr('predictions.kpi_needs_sub', 'open matches without a pick')),
                    _kpi(
                        context,
                        context.tr('predictions.kpi_accuracy', 'Accuracy'),
                        accuracy,
                        context
                            .tr('predictions.kpi_accuracy_sub', '{c} right of {s} scored')
                            .replaceAll('{c}', '$correct')
                            .replaceAll('{s}', '${scored.length}')),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _ShowFilter.values)
                      ChoiceChip(
                        label: Text(_filterLabel(context, f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: context.tr('predictions.team_search_placeholder', 'Team number'),
                  ),
                  onChanged: (v) => setState(() => _teamQuery = v),
                ),
              ],
            ),
          ),
          if (_eventKey.isEmpty)
            _notice(context, context.tr('predictions.no_event_notice', 'Set the current event in Admin Settings to start predicting.'))
          else if (shown.isEmpty)
            _notice(
              context,
              _matches.isEmpty
                  ? context.tr('predictions.no_matches', "No matches for this event yet. They'll show up once the schedule syncs.")
                  : context.tr('predictions.nothing_here', 'No matches fit these filters.'),
            )
          else
            for (final m in shown) _buildMatchRow(context, m, primary, muted),
        ],
      ),
    );
  }

  String _filterLabel(BuildContext context, _ShowFilter f) {
    switch (f) {
      case _ShowFilter.open:
        return context.tr('predictions.show_open', 'Matches without a result');
      case _ShowFilter.needs:
        return context.tr('predictions.show_needs', 'Still need my pick');
      case _ShowFilter.done:
        return context.tr('predictions.show_done', 'Finished matches');
      case _ShowFilter.all:
        return context.tr('predictions.show_all', 'All matches');
    }
  }

  Widget _notice(BuildContext context, String text) => ObsidianGlassCard(
        child: Text(text, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
      );

  Widget _buildMatchRow(BuildContext context, MatchModel m, Color primary, Color muted) {
    final status = _statusOf(m.matchKey);
    final ourTeam = widget.apiService.currentUser?.teamNumber;
    final isOurs = ourTeam != null && ourTeam > 0 && m.hasTeam(ourTeam);
    final start = m.predictedStart?.toLocal();
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(m.label.isNotEmpty ? m.label : m.displayLabel,
                  style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
              if (isOurs) ...[
                const SizedBox(width: 6),
                Icon(Icons.star_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
              ],
              if (start != null) ...[
                const SizedBox(width: 8),
                Text(MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(start)),
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
              const SizedBox(width: 8),
              Expanded(child: Align(alignment: Alignment.centerRight, child: MatchPickStatusLine(status: status))),
            ],
          ),
          const SizedBox(height: 8),
          MatchPickButtons(
            match: m,
            status: status,
            busy: _busy.contains(m.matchKey),
            compact: true,
            onPick: (w) => _pick(m, w),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab(BuildContext context, Color primary, Color muted) {
    final board = _board;
    final me = widget.apiService.currentUser?.id;
    return RefreshIndicator(
      color: ObsidianUITheme.primaryAccent,
      onRefresh: () => _loadLeaderboard(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4, bottom: widget.isBarsVisible ? 120 : 20),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('leaderboard.notice',
                      "Scouts ranked by how often they picked the winning alliance. Ties and matches without a result don't count."),
                  style: TextStyle(fontSize: 13, color: muted, height: 1.35),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'event', label: Text(context.tr('leaderboard.scope_event', 'One event'))),
                    ButtonSegment(value: 'year', label: Text(context.tr('leaderboard.scope_year', 'Whole season'))),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) {
                    setState(() => _scope = s.first);
                    _loadLeaderboard();
                  },
                ),
                const SizedBox(height: 10),
                if (_scope == 'event')
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _options.events.any((e) => e.eventKey == _boardEventKey) ? _boardEventKey : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    decoration: InputDecoration(labelText: context.tr('leaderboard.event', 'Event'), isDense: true),
                    hint: Text(context.tr('leaderboard.no_events', 'No events with predictions')),
                    items: [
                      for (final e in _options.events)
                        DropdownMenuItem(value: e.eventKey, child: Text(e.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setState(() => _boardEventKey = v);
                      _loadLeaderboard();
                    },
                  )
                else
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _options.years.contains(_boardYear) ? _boardYear : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    decoration: InputDecoration(labelText: context.tr('leaderboard.season', 'Season'), isDense: true),
                    items: [for (final y in _options.years) DropdownMenuItem(value: y, child: Text('$y'))],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _boardYear = v);
                      _loadLeaderboard();
                    },
                  ),
              ],
            ),
          ),
          if (_boardLoading && board == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)),
            )
          else if (board == null || board.rows.isEmpty)
            _notice(context, context.tr('leaderboard.empty', 'No predictions for this selection yet.'))
          else
            for (final row in board.rows) _buildBoardRow(context, row, row.userId == me, primary, muted),
        ],
      ),
    );
  }

  Widget _buildBoardRow(BuildContext context, PickLeaderboardRow row, bool isMe, Color primary, Color muted) {
    final rankColors = {
      1: const Color(0xFFF5C542),
      2: const Color(0xFFC9CED6),
      3: const Color(0xFFD9955B),
    };
    final rankBg = rankColors[row.rank] ?? ObsidianUITheme.getBorderColor(context);
    final accent = ObsidianUITheme.primaryAccent;
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
            child: Text(
              row.rank?.toString() ?? '-',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: rankColors.containsKey(row.rank) ? const Color(0xFF2B2F36) : primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(row.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: isMe ? FontWeight.w800 : FontWeight.w600, color: primary)),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(context.tr('leaderboard.you', 'You'), style: TextStyle(fontSize: 10.5, color: accent)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (row.accuracyPct ?? 0) / 100,
                    minHeight: 5,
                    backgroundColor: ObsidianUITheme.getBorderColor(context),
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    '${row.correct}/${row.scored} ${context.tr('leaderboard.col_correct', 'Correct').toLowerCase()}',
                    if (row.pending > 0) '${row.pending} ${context.tr('leaderboard.col_pending', 'Pending').toLowerCase()}',
                    if (row.ties > 0) '${row.ties} ${context.tr('leaderboard.col_ties', 'Ties').toLowerCase()}',
                    '${context.tr('leaderboard.col_best_streak', 'Best Streak').toLowerCase()} ${row.bestStreak}',
                    if (_scope == 'year') '${row.events} ${context.tr('leaderboard.col_events', 'Events').toLowerCase()}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                row.accuracyPct == null ? '-' : '${row.accuracyPct}%',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primary),
              ),
              if (row.currentStreak >= 3)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 14, color: Color(0xFFF97316)),
                    Text('${row.currentStreak}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF97316))),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
