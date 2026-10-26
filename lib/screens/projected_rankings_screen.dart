import 'dart:math';
import 'package:flutter/material.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Simulates the remaining qualification matches to estimate where each team finishes.
/// Same data as the website's projected-rankings.html.
class ProjectedRankingsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ProjectedRankingsScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<ProjectedRankingsScreen> createState() => _ProjectedRankingsScreenState();
}

class _ProjectedRankingsScreenState extends State<ProjectedRankingsScreen> {
  static const _simOptions = [1000, 2000, 5000, 10000];

  bool _loading = true;
  List<EventModel> _events = [];
  String _eventKey = '';
  int _simulations = 2000;
  Map<String, dynamic>? _data;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final events = await widget.apiService.fetchEvents();
    if (!mounted) return;
    _events = events;
    _eventKey = widget.apiService.currentSettings?.eventKey ?? '';
    if (_eventKey.isEmpty && events.isNotEmpty) _eventKey = events.first.eventKey;
    await _load();
  }

  /// [fresh] draws a new set of simulations (the website's Re-run); other loads use the stable default seed.
  Future<void> _load({bool fresh = false}) async {
    if (_eventKey.isEmpty) {
      setState(() {
        _loading = false;
        _data = null;
      });
      return;
    }
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.apiService.requestJson('GET', '/api/matches/projected-rankings', query: {
      'eventKey': _eventKey,
      'simulations': '$_simulations',
      if (fresh) 'seed': '${Random().nextInt(2147483647)}',
    }, cacheKey: 'cache_projected_rankings_$_eventKey');
    if (!mounted || id != _requestId) return;
    setState(() {
      _loading = false;
      _data = res.success ? jsonMap(res.data) : null;
      _error = res.success ? null : (res.message ?? 'Request failed');
    });
  }

  String _summary(BuildContext context, Map<String, dynamic> d) {
    final parts = <String>[];
    final total = jsonInt(d['qualMatchesTotal']) ?? 0;
    final played = jsonInt(d['qualMatchesPlayed']) ?? 0;
    final official = d['rpSource'] == 'official';
    if (jsonBool(d['qualsComplete']) && total > 0) {
      parts.add(context.trArgs('projected.complete',
          'Qualifications are complete ({n} matches). These are the final standings, not a projection', {'n': '$total'}));
      parts.add(official
          ? context.trArgs('projected.rp_official', 'ranking points from official results')
          : context.trArgs('projected.rp_estimated_final',
              'ranking points estimated from wins (bonus RP not included), so check official rankings for exact order'));
    } else if (total > 0) {
      parts.add(context.trArgs('projected.played', '{played} of {total} qualification matches played',
          {'played': '$played', 'total': '$total'}));
      final sims = jsonInt(d['simulations']) ?? 0;
      if (sims > 0 && played < total) parts.add(context.trArgs('projected.sims', '{n} simulations', {'n': '$sims'}));
      final rp = fmtNum(d['winRp']);
      parts.add(official
          ? context.trArgs('projected.rp_official_win', 'ranking points from official results ({rp} RP per win)', {'rp': rp})
          : context.trArgs('projected.rp_estimated', 'ranking points estimated from wins ({rp} RP per win, bonus RP not included)',
              {'rp': rp}));
      parts.add(context.trArgs('projected.strength', 'team strength from {metrics}',
          {'metrics': jsonList(d['strengthMetrics']).join(' + ')}));
      parts.add(context.trArgs('projected.rerun_note', 'Re-run draws a new set of simulations, so small changes between runs are normal'));
    }
    if (jsonStr(d['note']).isNotEmpty) parts.add(jsonStr(d['note']));
    return parts.isEmpty
        ? context.trArgs('projected.notice', 'Simulates the remaining qualification matches to estimate where each team will finish.')
        : '${parts.join(' · ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final complete = d != null && jsonBool(d['qualsComplete']);
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.trArgs('projected.title', 'Projected Final Rankings'),
          subtitle: d == null
              ? context.trArgs('projected.notice', 'Simulates the remaining qualification matches to estimate where each team will finish.')
              : _summary(context, d),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _eventKey.isEmpty ? null : _eventKey,
                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                decoration: InputDecoration(labelText: context.trArgs('projected.tip.event', 'Event'), isDense: true),
                items: [
                  for (final e in _events)
                    DropdownMenuItem(value: e.eventKey, child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis)),
                  if (_eventKey.isNotEmpty && !_events.any((e) => e.eventKey == _eventKey))
                    DropdownMenuItem(value: _eventKey, child: Text(_eventKey)),
                ],
                onChanged: (v) {
                  _eventKey = v ?? '';
                  _load();
                },
              ),
              if (!complete) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _simulations,
                        dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                        decoration: InputDecoration(
                            labelText: context.trArgs('projected.tip.sims', 'Number of simulated seasons'), isDense: true),
                        items: [
                          for (final n in _simOptions)
                            DropdownMenuItem(
                              value: n,
                              child: Text(context.trArgs('projected.runs_$n', '${MaterialLocalizations.of(context).formatDecimal(n)} runs')),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _simulations = v;
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _load(fresh: true),
                      icon: const Icon(Icons.casino_rounded, size: 18),
                      label: Text(context.trArgs('projected.rerun', 'Re-run')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_loading)
          const PortedLoading()
        else if (_eventKey.isEmpty)
          PortedNotice(context.trArgs('projected.no_event', 'No event selected'))
        else if (_error != null)
          PortedError(
            message: context.trArgs('projected.failed_project', 'Failed to project rankings: {error}', {'error': _error!}),
            onRetry: _load,
          )
        else if (d == null || jsonList(d['teams']).isEmpty)
          PortedNotice(jsonStr(d?['note']).isNotEmpty
              ? jsonStr(d?['note'])
              : context.trArgs('projected.no_matches', 'No qualification matches to project.'))
        else
          ..._rows(context, d),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, Map<String, dynamic> d) {
    final complete = jsonBool(d['qualsComplete']);
    final slots = jsonInt(d['captainSlots']) ?? 8;
    final myTeam = widget.apiService.currentUser?.teamNumber;
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    // A simulation can't prove certainty, so only show 100% / 0% once qualifications are over.
    String pct(dynamic p) {
      final v = jsonDouble(p) ?? 0;
      if (complete) return '${(v * 100).round()}%';
      if (v >= 0.995) return '>99%';
      if (v < 0.005) return '<1%';
      return '${(v * 100).round()}%';
    }

    final teams = jsonMaps(d['teams']);
    return [
      for (var i = 0; i < teams.length; i++)
        Builder(builder: (context) {
          final t = teams[i];
          final projected = i + 1;
          final current = jsonInt(t['currentRank']);
          final delta = current == null ? 0 : current - projected;
          final best = jsonInt(t['bestLikelyRank']);
          final worst = jsonInt(t['worstLikelyRank']);
          final range = best == worst ? '$best' : '$best–$worst';
          final played = jsonInt(t['matchesPlayed']) ?? 0;
          final record = played > 0 ? '${t['wins']}-${t['losses']}-${t['ties']}' : '–';
          final isMine = myTeam != null && myTeam > 0 && jsonInt(t['teamNumber']) == myTeam;
          final top = jsonDouble(t['probTopSeeds']) ?? 0;
          return ObsidianGlassCard(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isMine ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.25) : ObsidianUITheme.getBorderColor(context),
                        shape: BoxShape.circle,
                      ),
                      child: Text('$projected', style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t['teamNumber']}  ${jsonStr(t['nickname'])}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
                          Text(
                            [
                              '${context.trArgs('projected.col.now', 'Now')} ${current ?? '–'}',
                              '${context.trArgs('projected.col.record', 'Record')} $record',
                              '${context.trArgs('projected.col.left', 'Left')} ${t['matchesRemaining'] ?? 0}',
                            ].join(' · '),
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (delta != 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(delta > 0 ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                            color: delta > 0 ? ObsidianUITheme.successGreen : ObsidianUITheme.errorRed),
                        Text('${delta.abs()}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: delta > 0 ? ObsidianUITheme.successGreen : ObsidianUITheme.errorRed)),
                      ]),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _mini(context, context.trArgs('projected.col.rs_now', 'RS Now'),
                        t['currentRankingScore'] == null ? '–' : (jsonDouble(t['currentRankingScore']) ?? 0).toStringAsFixed(2)),
                    _mini(context, context.trArgs('projected.col.rs_final', 'RS Final'),
                        (jsonDouble(t['expectedRankingScore']) ?? 0).toStringAsFixed(2)),
                    _mini(context, context.trArgs('projected.col.range', 'Likely Range'), range),
                    _mini(context, '#1', pct(t['probFirst'])),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(context.trArgs('projected.col.top', 'Top {n}', {'n': '$slots'}), style: TextStyle(fontSize: 11.5, color: muted)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: top.clamp(0, 1).toDouble(),
                          minHeight: 6,
                          backgroundColor: ObsidianUITheme.getBorderColor(context),
                          color: ObsidianUITheme.primaryAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(pct(top), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
                  ],
                ),
              ],
            ),
          );
        }),
    ];
  }

  Widget _mini(BuildContext context, String label, String value) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
          TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context))),
        ]),
        style: const TextStyle(fontSize: 12),
      );
}
