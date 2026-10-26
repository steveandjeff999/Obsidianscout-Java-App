import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/graph_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Two or three teams side by side, metric by metric. Same data as the website's compare.html, plus a
/// Match 13 xP mode (when the team has Match 13 on) from the server's source=match13 comparison.
class CompareScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const CompareScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  bool _loading = true;
  bool _comparing = false;
  List<EventModel> _events = [];
  String _eventKey = '';
  List<TeamModel> _teams = [];
  final List<int?> _picked = [null, null, null];
  Map<String, dynamic>? _result;
  String? _error;

  /// 'scouted' compares scouting averages (server); 'exp' compares Match 13 xP for the selected event.
  String _source = 'scouted';
  final Map<String, List<dynamic>> _match13ByEvent = {};

  bool get _match13Available =>
      widget.apiService.currentProgram != 'FTC' && (widget.apiService.currentSettings?.useMatch13Exp ?? false);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = widget.apiService;
    final events = await api.fetchEvents();
    if (!mounted) return;
    _events = events;
    _eventKey = api.currentSettings?.eventKey ?? '';
    await _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _loading = true);
    final teams = await widget.apiService.fetchTeams(_eventKey.isEmpty ? null : _eventKey);
    if (!mounted) return;
    final numbers = teams.map((t) => t.teamNumber).toSet();
    setState(() {
      _teams = List<TeamModel>.from(teams)..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
      for (var i = 0; i < _picked.length; i++) {
        if (_picked[i] != null && !numbers.contains(_picked[i])) _picked[i] = null;
      }
      _loading = false;
    });
    _compare();
  }

  List<int> get _selected => _picked.whereType<int>().toSet().toList();

  Future<void> _compare() async {
    final teams = _selected;
    if (teams.length < 2) {
      setState(() => _result = null);
      return;
    }
    setState(() {
      _comparing = true;
      _error = null;
    });
    if (_source == 'exp') {
      await _compareExp(teams);
      return;
    }
    final res = await widget.apiService.requestJson('GET', '/api/analytics/compare', query: {
      'teams': teams.join(','),
      if (_eventKey.isNotEmpty) 'eventKey': _eventKey,
    });
    if (!mounted) return;
    setState(() {
      _comparing = false;
      _result = res.success ? jsonMap(res.data) : null;
      _error = res.success ? null : (res.message ?? 'Request failed');
    });
  }

  Future<void> _compareExp(List<int> teams) async {
    if (_eventKey.isEmpty) {
      setState(() {
        _comparing = false;
        _result = null;
      });
      return;
    }
    final res = await widget.apiService.requestJson('GET', '/api/analytics/compare', query: {
      'teams': teams.join(','),
      'eventKey': _eventKey,
      'source': 'match13',
    });
    if (!mounted) return;
    // Servers that predate source=match13 answer with scouting averages; work it out here instead.
    if (res.success && jsonMap(res.data)['source'] == 'match13') {
      setState(() {
        _comparing = false;
        _result = jsonMap(res.data);
      });
      return;
    }
    // Offline or an older server: build the same numbers from the event's Match 13 history.
    var history = _match13ByEvent[_eventKey];
    if (history == null) {
      final stats = await widget.apiService.fetchStatsHistory(_eventKey);
      history = stats?.match13History ?? const [];
      if (history.isNotEmpty) _match13ByEvent[_eventKey] = history;
    }
    if (!mounted) return;
    setState(() {
      _comparing = false;
      _result = _buildExpResult(teams, history!);
    });
  }

  /// Offline copy of the server's Match13Compare: turns Match 13 history into the compare endpoint's shape: current, starting and peak xP, the change over
  /// the event, and the latest auto / teleop / endgame split for each team.
  Map<String, dynamic> _buildExpResult(List<int> teams, List<dynamic> history) {
    final teamData = <String, dynamic>{};
    var anyData = false;
    for (final n in teams) {
      final played = <({int weight, dynamic data})>[];
      for (final match in history) {
        final data = extractTeamExpData(match, n);
        if (data == null) continue;
        final key = match is Map ? (match['key'] ?? match['matchKey'] ?? match['match_key'] ?? '').toString() : '';
        played.add((weight: getMatchSortWeightFromLabel(formatMatchKeyToLabel(key)), data: data));
      }
      played.sort((a, b) => a.weight.compareTo(b.weight));
      final team = _teams.where((t) => t.teamNumber == n).firstOrNull;
      final metrics = <String, double>{'matches_scouted': played.length.toDouble()};
      if (played.isNotEmpty) {
        anyData = true;
        final latest = played.last.data;
        final current = getTeamExpMetricValue(latest, 'score_total');
        // xP going into the first match; the post-match value when the history has no pre-match number.
        final pre = jsonDouble(jsonMap(played.first.data)['xpPre']);
        final start = pre ?? getTeamExpMetricValue(played.first.data, 'score_total');
        metrics['xp_current'] = current;
        metrics['xp_start'] = start;
        metrics['xp_change'] = current - start;
        metrics['xp_peak'] = played.map((m) => getTeamExpMetricValue(m.data, 'score_total')).reduce((a, b) => a > b ? a : b);
        metrics['xp_auto'] = getTeamExpMetricValue(latest, 'score_auto');
        metrics['xp_teleop'] = getTeamExpMetricValue(latest, 'score_teleop');
        metrics['xp_endgame'] = getTeamExpMetricValue(latest, 'score_endgame');
      }
      teamData['$n'] = {
        'nickname': team?.nickname ?? team?.name,
        'matchesScouted': played.length,
        'exp': metrics['xp_current'] ?? team?.match13Exp ?? team?.exp,
        'metrics': metrics,
      };
    }

    Map<String, dynamic> def(String id, String title, String phase, [String unit = 'xP']) =>
        {'id': id, 'title': title, 'phase': phase, 'type': 'number', 'unit': unit};
    return {
      'teams': teamData,
      'metricDefinitions': !anyData
          ? []
          : [
              def('xp_current', context.tr('compare.exp_current', 'Current xP'), 'overview'),
              def('xp_start', context.tr('compare.exp_start', 'Starting xP'), 'overview'),
              def('xp_change', context.tr('compare.exp_change', 'xP Change This Event'), 'overview'),
              def('xp_peak', context.tr('compare.exp_peak', 'Peak xP'), 'overview'),
              def('matches_scouted', context.tr('compare.exp_matches', 'Matches With xP'), 'overview', 'matches'),
              def('xp_auto', context.tr('compare.exp_auto', 'Auto xP'), 'auto'),
              def('xp_teleop', context.tr('compare.exp_teleop', 'Teleop xP'), 'teleop'),
              def('xp_endgame', context.tr('compare.exp_endgame', 'Endgame xP'), 'endgame'),
            ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return PortedPageList(
      onRefresh: _loadTeams,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('compare.title', 'Team Comparison'),
          subtitle: context.tr('compare.notice', 'Compare 2 or 3 teams side-by-side using scouting metrics.'),
          child: Column(
            children: [
              if (_match13Available) ...[
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'scouted',
                        icon: const Icon(Icons.fact_check_rounded, size: 18),
                        label: Text(context.tr('compare.source_scouted', 'Scouted')),
                      ),
                      ButtonSegment(
                        value: 'exp',
                        icon: const Icon(Icons.insights_rounded, size: 18),
                        label: Text(context.tr('compare.source_match13', 'Match 13 xP')),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (sel) {
                      setState(() => _source = sel.first);
                      _compare();
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _eventKey,
                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                decoration: InputDecoration(labelText: context.tr('nav.events', 'Event'), isDense: true),
                items: [
                  DropdownMenuItem(value: '', child: Text(context.tr('compare.select_event', 'All Events (Prescout)'))),
                  for (final e in _events)
                    DropdownMenuItem(
                      value: e.eventKey,
                      child: Text('${e.year ?? ''} ${e.name.isNotEmpty ? e.name : (e.eventCode ?? e.eventKey)}'.trim(),
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (_eventKey.isNotEmpty && !_events.any((e) => e.eventKey == _eventKey))
                    DropdownMenuItem(value: _eventKey, child: Text(_eventKey)),
                ],
                onChanged: (v) {
                  _eventKey = v ?? '';
                  _loadTeams();
                },
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < 3; i++) ...[
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _picked[i],
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  decoration: InputDecoration(
                    labelText: i == 2
                        ? context.tr('compare.team_3', 'Team 3 (Optional)')
                        : context.tr('compare.team_${i + 1}', 'Team ${i + 1}'),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(i == 2
                          ? context.tr('compare.none_compare_2', 'None (Compare 2)')
                          : context.tr('compare.select_team_${i + 1}', 'Select Team ${i + 1}...')),
                    ),
                    for (final t in _teams)
                      DropdownMenuItem<int?>(
                        value: t.teamNumber,
                        child: Text('${t.teamNumber} - ${t.nickname ?? t.name ?? ''}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _picked[i] = v);
                    _compare();
                  },
                ),
                if (i < 2) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (_loading || _comparing)
          const PortedLoading()
        else if (_error != null)
          PortedError(message: _error!, onRetry: _compare)
        else if (_source == 'exp' && _eventKey.isEmpty)
          PortedNotice(context.tr('compare.exp_needs_event', 'Pick an event to compare Match 13 xP.'))
        else if (_result == null)
          PortedNotice(context.tr('compare.select_at_least_two', 'Select at least two teams above to view a side-by-side comparison.'))
        else
          ..._buildResults(context, _result!),
      ],
    );
  }

  List<Widget> _buildResults(BuildContext context, Map<String, dynamic> result) {
    final teams = _selected;
    final data = jsonMap(result['teams']);
    final defs = jsonMaps(result['metricDefinitions']);
    final settings = widget.apiService.currentSettings;
    final isFtc = widget.apiService.currentProgram == 'FTC';
    final showEpa = !isFtc && (settings?.useStatboticsEpa ?? false);
    final showExp = !isFtc && (settings?.useMatch13Exp ?? false);
    final showOpr = settings?.useTbaOpr ?? false;
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);

    final hero = ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          for (final n in teams)
            Expanded(
              child: Builder(builder: (context) {
                final t = jsonMap(data['$n']);
                final team = _teams.where((x) => x.teamNumber == n).firstOrNull;
                final badges = <Widget>[
                  if (showEpa && t['epa'] != null) PortedBadge('EPA ${fmtNum(t['epa'], digits: 1)}', color: const Color(0xFF38BDF8)),
                  if (showExp && t['exp'] != null) PortedBadge('EXP ${fmtNum(t['exp'], digits: 1)}', color: const Color(0xFF10B981)),
                  if (showOpr && t['opr'] != null) PortedBadge('OPR ${fmtNum(t['opr'], digits: 1)}', color: const Color(0xFFC084FC)),
                ];
                return Column(
                  children: [
                    Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ObsidianUITheme.primaryAccent)),
                    Text(jsonStr(t['nickname'], team?.nickname ?? team?.name ?? 'Team $n'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: primary)),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: badges),
                    ],
                    if (t['matchesScouted'] != null) ...[
                      const SizedBox(height: 6),
                      Text(_source == 'exp' ? '${t['matchesScouted']} matches with xP' : '${t['matchesScouted']} matches', style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ],
                );
              }),
            ),
        ],
      ),
    );

    if (defs.isEmpty) {
      return [
        hero,
        PortedNotice(_source == 'exp'
            ? context.tr('compare.exp_no_data', 'No Match 13 match data for these teams at this event.')
            : context.tr('compare.no_data', 'No scouting data available for these teams at this event.')),
      ];
    }

    const known = ['overview', 'auto', 'teleop', 'endgame', 'custom'];
    final groups = <(String, bool Function(Map<String, dynamic>))>[
      (context.tr('compare.overview', 'Performance Overview'), (m) => m['phase'] == 'overview'),
      (context.tr('compare.avg_auto', 'Autonomous Phase'), (m) => m['phase'] == 'auto'),
      (context.tr('compare.avg_teleop', 'Teleoperated Phase'), (m) => m['phase'] == 'teleop'),
      (context.tr('compare.avg_endgame', 'Endgame Phase'), (m) => m['phase'] == 'endgame'),
      (context.tr('compare.breakdown', 'Additional Elements'), (m) => !known.contains(m['phase'])),
      (context.tr('nav.custom_analytics', 'Custom Analytics'), (m) => m['phase'] == 'custom'),
    ];

    dynamic customWidget(Map<String, dynamic> t, String id) =>
        jsonMaps(t['widgets']).where((w) => w['id'] == id.replaceFirst(RegExp(r'^custom_'), '')).firstOrNull;

    return [
      hero,
      for (final g in groups)
        if (defs.any(g.$2))
          PortedSection(
            title: g.$1,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                for (final m in defs.where(g.$2))
                  Builder(builder: (context) {
                    final id = jsonStr(m['id']);
                    final isCustom = m['phase'] == 'custom';
                    final values = teams.map((n) {
                      final t = data['$n'];
                      if (t is! Map) return null;
                      final tm = jsonMap(t);
                      if (isCustom) return jsonDouble(jsonMap(customWidget(tm, id))['value']);
                      return jsonDouble(jsonMap(tm['metrics'])[id]);
                    }).toList();
                    final valid = values.whereType<double>().toList();
                    final best = valid.length > 1 ? valid.reduce((a, b) => a > b ? a : b) : null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: jsonStr(m['title']), style: TextStyle(fontWeight: FontWeight.w600, color: primary)),
                              if (jsonStr(m['unit']).isNotEmpty)
                                TextSpan(text: ' (${m['unit']})', style: TextStyle(fontSize: 11, color: muted)),
                            ]), style: const TextStyle(fontSize: 13)),
                          ),
                          for (var i = 0; i < teams.length; i++)
                            Expanded(
                              flex: 2,
                              child: _valueCell(context, m, data['${teams[i]}'], values[i], best, isCustom, id, customWidget),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
    ];
  }

  Widget _valueCell(BuildContext context, Map<String, dynamic> m, dynamic teamData, double? value, double? best, bool isCustom,
      String id, dynamic Function(Map<String, dynamic>, String) customWidget) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    if (m['type'] == 'bar') {
      final t = jsonMap(teamData);
      final series = isCustom ? jsonMaps(jsonMap(customWidget(t, id))['series']) : jsonMaps(jsonMap(t['metricSeries'])[id]);
      if (series.isEmpty) return Text('--', textAlign: TextAlign.right, style: TextStyle(color: muted));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final s in series)
            Text('${s['label']}: ${fmtNum(s['value'])}', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: primary)),
        ],
      );
    }
    if (value == null) return Text('--', textAlign: TextAlign.right, style: TextStyle(color: muted));
    final text = m['type'] == 'percentage' ? '${value.toStringAsFixed(1)}%' : fmtNum(value);
    final isBest = best != null && value == best && best > 0 && m['id'] != 'matches_scouted';
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 13,
        fontWeight: isBest ? FontWeight.w800 : FontWeight.w500,
        color: isBest ? ObsidianUITheme.successGreen : primary,
      ),
    );
  }
}
