import 'dart:math';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_chart_interactive_wrapper.dart';

class TeamDetailsScreen extends StatefulWidget {
  final TeamModel team;
  final ApiService apiService;
  final String? eventKey;

  const TeamDetailsScreen({
    super.key,
    required this.team,
    required this.apiService,
    this.eventKey,
  });

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  ScoutingConfigModel? _matchConfig;
  ScoutingConfigModel? _pitConfig;

  List<MatchModel> _teamMatches = [];
  List<Map<String, dynamic>> _matchEntries = [];
  List<Map<String, dynamic>> _pitEntries = [];
  List<Map<String, dynamic>> _qualEntries = [];

  String _recordFilter = 'all'; // 'all', 'match', 'pit', 'qual'
  String _matchCompLevelFilter = 'all'; // 'all', 'qm', 'playoff', 'practice'

  // Computed Analytics
  double _avgTotalScore = 0.0;
  double _avgAutoScore = 0.0;
  double _avgTeleopScore = 0.0;
  double _avgEndgameScore = 0.0;
  double _maxTotalScore = 0.0;
  double _minTotalScore = 0.0;
  List<_MatchScoreSummary> _matchScoreSummaries = [];
  Map<String, _FieldMetricSummary> _fieldMetrics = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final resolvedEvent = widget.eventKey ?? await widget.apiService.fetchCurrentEventKey();

    try {
      final results = await Future.wait([
        widget.apiService.fetchMatchConfig(),
        widget.apiService.fetchPitConfig(),
        widget.apiService.fetchMatches(resolvedEvent),
        widget.apiService.fetchScoutingEntries(),
        widget.apiService.fetchPitScoutingEntries(),
        widget.apiService.fetchQualScoutingEntries(),
      ]);

      _matchConfig = results[0] as ScoutingConfigModel?;
      _pitConfig = results[1] as ScoutingConfigModel?;

      final allMatches = results[2] as List<MatchModel>;
      final teamNumStr = widget.team.teamNumber.toString();

      final rawScouting = results[3] as List<dynamic>;
      final rawPit = results[4] as List<dynamic>;
      final rawQual = results[5] as List<dynamic>;

      _matchEntries = rawScouting
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) {
            final t = e['targetTeamNumber'] ?? (e['data'] is Map ? e['data']['targetTeamNumber'] : null);
            return t == widget.team.teamNumber || t.toString() == teamNumStr;
          })
          .toList();

      _pitEntries = rawPit
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) {
            final t = e['targetTeamNumber'] ?? (e['data'] is Map ? e['data']['targetTeamNumber'] : null);
            return t == widget.team.teamNumber || t.toString() == teamNumStr;
          })
          .toList();

      _qualEntries = rawQual
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) {
            final t = e['targetTeamNumber'] ?? (e['data'] is Map ? e['data']['targetTeamNumber'] : null);
            return t == widget.team.teamNumber || t.toString() == teamNumStr;
          })
          .toList();

      // Filter matches where this team played in the official schedule
      final scheduled = allMatches.where((m) {
        final all = [...m.redTeams, ...m.blueTeams];
        return all.any((t) => t.replaceAll(RegExp(r'^(frc|ftc)'), '') == teamNumStr);
      }).toList();

      final existingKeys = scheduled.map((m) => m.matchKey).where((k) => k.isNotEmpty).toSet();
      final existingNumbers = scheduled.map((m) => m.matchNumber).where((n) => n != null).toSet();

      // Also incorporate any matches this team played from _matchEntries (e.g. practice, prescout, local playoff)
      for (final entry in _matchEntries) {
        final matchKey = entry['matchKey']?.toString() ?? '';
        final rawNum = entry['matchNumber'] ?? (entry['data'] is Map ? entry['data']['matchNumber'] : null);
        final matchNum = rawNum is num ? rawNum.toInt() : int.tryParse(rawNum?.toString() ?? '');
        final isPrescout = entry['isPrescout'] == true;

        if (matchKey.isNotEmpty && !existingKeys.contains(matchKey)) {
          scheduled.add(MatchModel.fromJson({
            'matchKey': matchKey,
            'eventKey': entry['eventKey'] ?? resolvedEvent,
            'matchNumber': matchNum,
            'compLevel': isPrescout ? 'practice' : null,
            'redTeams': [widget.team.teamKey.isNotEmpty ? widget.team.teamKey : 'frc$teamNumStr'],
            'blueTeams': <String>[],
          }));
          existingKeys.add(matchKey);
        } else if (matchNum != null && !existingNumbers.contains(matchNum) && matchKey.isEmpty) {
          final syntheticKey = '${resolvedEvent}_qm$matchNum';
          scheduled.add(MatchModel.fromJson({
            'matchKey': syntheticKey,
            'eventKey': resolvedEvent,
            'matchNumber': matchNum,
            'compLevel': isPrescout ? 'practice' : 'qm',
            'redTeams': [widget.team.teamKey.isNotEmpty ? widget.team.teamKey : 'frc$teamNumStr'],
            'blueTeams': <String>[],
          }));
          existingNumbers.add(matchNum);
        }
      }

      // Sort all matches logically: practice -> qm -> qf -> sf -> f -> playoff
      scheduled.sort((a, b) {
        final levelOrder = {'practice': 0, 'qm': 1, 'qual': 1, 'qf': 2, 'sf': 3, 'f': 4, 'playoff': 4};
        final la = levelOrder[a.compLevel.toLowerCase()] ?? 5;
        final lb = levelOrder[b.compLevel.toLowerCase()] ?? 5;
        if (la != lb) return la.compareTo(lb);
        return (a.matchNumber ?? 0).compareTo(b.matchNumber ?? 0);
      });

      _teamMatches = scheduled;
      _computeAnalytics();
    } catch (e) {
      debugPrint('Error loading team details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _computeAnalytics() {
    if (_matchEntries.isEmpty || _matchConfig == null) {
      _avgTotalScore = widget.team.averagePoints ?? 0.0;
      return;
    }

    final fields = _matchConfig!.fields;
    final summaries = <_MatchScoreSummary>[];
    final fieldSums = <String, double>{};
    final fieldCounts = <String, int>{};
    final fieldMaxs = <String, double>{};
    final fieldOptionsCount = <String, Map<String, int>>{};

    double totalScoreSum = 0;
    double autoSum = 0;
    double teleopSum = 0;
    double endgameSum = 0;
    double maxScore = 0;
    double minScore = double.infinity;

    for (var entry in _matchEntries) {
      final data = entry['data'] is Map ? Map<String, dynamic>.from(entry['data'] as Map) : entry;
      final matchNum = entry['matchNumber'] ?? data['matchNumber'];
      final matchKey = entry['matchKey']?.toString() ?? data['matchKey']?.toString() ?? 'M$matchNum';

      double matchAuto = 0;
      double matchTeleop = 0;
      double matchEndgame = 0;

      for (var f in fields) {
        final val = data[f.id];
        if (val == null) continue;

        double pts = 0.0;
        double numVal = 0.0;

        if (f.type == 'counter' || f.type == 'number' || f.type == 'slider' || f.type == 'rating') {
          numVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
          pts = numVal * (f.pointsPer ?? 0.0);
          fieldSums[f.id] = (fieldSums[f.id] ?? 0) + numVal;
          fieldCounts[f.id] = (fieldCounts[f.id] ?? 0) + 1;
          fieldMaxs[f.id] = max(fieldMaxs[f.id] ?? 0.0, numVal);
        } else if (f.type == 'checkbox' || f.type == 'toggle' || f.type == 'boolean') {
          final isTrue = val == true || val.toString().toLowerCase() == 'true';
          if (isTrue) {
            pts = f.pointsPer ?? 0.0;
            fieldSums[f.id] = (fieldSums[f.id] ?? 0) + 1;
          }
          fieldCounts[f.id] = (fieldCounts[f.id] ?? 0) + 1;
        } else if (f.type == 'select' || f.type == 'radio') {
          final strVal = val.toString();
          fieldOptionsCount.putIfAbsent(f.id, () => {})[strVal] = (fieldOptionsCount[f.id]![strVal] ?? 0) + 1;
          fieldCounts[f.id] = (fieldCounts[f.id] ?? 0) + 1;
        }

        final phase = (f.phase ?? '').toLowerCase();
        if (phase == 'auto' || phase.contains('auto')) {
          matchAuto += pts;
        } else if (phase == 'teleop' || phase.contains('tele')) {
          matchTeleop += pts;
        } else if (phase == 'endgame' || phase.contains('end')) {
          matchEndgame += pts;
        } else {
          matchTeleop += pts;
        }
      }

      final matchTotal = matchAuto + matchTeleop + matchEndgame;
      totalScoreSum += matchTotal;
      autoSum += matchAuto;
      teleopSum += matchTeleop;
      endgameSum += matchEndgame;
      if (matchTotal > maxScore) maxScore = matchTotal;
      if (matchTotal < minScore) minScore = matchTotal;

      summaries.add(_MatchScoreSummary(
        matchKey: matchKey,
        matchNumber: (matchNum is num) ? matchNum.toInt() : (int.tryParse(matchNum?.toString() ?? '0') ?? 0),
        autoPoints: matchAuto,
        teleopPoints: matchTeleop,
        endgamePoints: matchEndgame,
        totalPoints: matchTotal,
      ));
    }

    final n = _matchEntries.length;
    _avgTotalScore = n > 0 ? (totalScoreSum / n) : (widget.team.averagePoints ?? 0.0);
    _avgAutoScore = n > 0 ? (autoSum / n) : 0.0;
    _avgTeleopScore = n > 0 ? (teleopSum / n) : 0.0;
    _avgEndgameScore = n > 0 ? (endgameSum / n) : 0.0;
    _maxTotalScore = maxScore;
    _minTotalScore = minScore == double.infinity ? 0.0 : minScore;

    // Sort summaries by match number
    summaries.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    _matchScoreSummaries = summaries;

    // Build field metrics
    final metrics = <String, _FieldMetricSummary>{};
    for (var f in fields) {
      if (f.type == 'section') continue;
      final c = fieldCounts[f.id] ?? 0;
      if (c == 0) continue;

      if (f.type == 'counter' || f.type == 'number' || f.type == 'slider' || f.type == 'rating') {
        final sum = fieldSums[f.id] ?? 0.0;
        final avg = sum / c;
        final mx = fieldMaxs[f.id] ?? 0.0;
        metrics[f.id] = _FieldMetricSummary(
          field: f,
          average: avg,
          max: mx,
          total: sum,
          count: c,
        );
      } else if (f.type == 'checkbox' || f.type == 'toggle' || f.type == 'boolean') {
        final successes = fieldSums[f.id] ?? 0.0;
        final pct = (successes / c) * 100.0;
        metrics[f.id] = _FieldMetricSummary(
          field: f,
          percentage: pct,
          total: successes,
          count: c,
        );
      } else if (f.type == 'select' || f.type == 'radio') {
        final opts = fieldOptionsCount[f.id] ?? {};
        metrics[f.id] = _FieldMetricSummary(
          field: f,
          optionCounts: opts,
          count: c,
        );
      }
    }
    _fieldMetrics = metrics;
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final isDark = ObsidianUITheme.isDark(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, primaryTextColor, secondaryTextColor),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(14.0),
                  color: ObsidianUITheme.primaryAccent,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: secondaryTextColor,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                tabs: [
                  Tab(icon: const Icon(Icons.analytics_rounded, size: 18), text: context.tr('team_details.analytics', 'Analytics')),
                  Tab(icon: const Icon(Icons.calendar_month_rounded, size: 18), text: context.tr('team_details.matches', 'Matches')),
                  Tab(icon: const Icon(Icons.build_circle_rounded, size: 18), text: context.tr('team_details.pit_profile', 'Pit Profile')),
                  Tab(icon: const Icon(Icons.receipt_long_rounded, size: 18), text: context.tr('team_details.records', 'Records')),
                ],
              ),
            ),

            const SizedBox(height: 8.0),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAnalyticsTab(context),
                        _buildMatchesTab(context),
                        _buildPitTab(context),
                        _buildRecordsTab(context),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Color primaryColor, Color secondaryColor) {
    final team = widget.team;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 16.0, 4.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: primaryColor,
            onPressed: () => Navigator.of(context).pop(),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [ObsidianUITheme.primaryAccent, ObsidianUITheme.secondaryAccent],
              ),
            ),
            child: Center(
              child: Text(
                '${team.teamNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  team.nickname ?? team.name ?? 'Team ${team.teamNumber}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [team.city, team.state, team.country].where((s) => s != null && s.isNotEmpty).cast<String>().join(', ').ifEmpty('Event: ${widget.eventKey ?? "Current"}'),
                  style: TextStyle(fontSize: 12, color: secondaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: ObsidianUITheme.primaryAccent),
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tab 1: Analytics
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildAnalyticsTab(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Stats Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(child: _statCard(context.tr('team_details.epa', 'EPA'), widget.team.epa?.toStringAsFixed(1) ?? '--', Colors.amber, Icons.electric_bolt_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _statCard(context.tr('team_details.opr', 'OPR'), widget.team.opr?.toStringAsFixed(1) ?? '--', ObsidianUITheme.primaryAccent, Icons.leaderboard_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _statCard(context.tr('team_details.avg_points', 'AVG PTS'), _avgTotalScore > 0 ? _avgTotalScore.toStringAsFixed(1) : '--', ObsidianUITheme.secondaryAccent, Icons.stars_rounded)),
              ],
            ),
          ),

          // Detailed Scoring Breakdown Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pie_chart_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('team_details.scoring_breakdown', 'Scoring Breakdown by Phase'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _phasePill(context.tr('team_details.auto_avg', 'Auto Avg'), _avgAutoScore, Colors.blueAccent)),
                    const SizedBox(width: 8),
                    Expanded(child: _phasePill(context.tr('team_details.teleop_avg', 'Teleop Avg'), _avgTeleopScore, Colors.deepPurpleAccent)),
                    const SizedBox(width: 8),
                    Expanded(child: _phasePill(context.tr('team_details.endgame_avg', 'Endgame Avg'), _avgEndgameScore, Colors.tealAccent)),
                  ],
                ),
                const SizedBox(height: 14),
                // Score range row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${context.tr("team_details.max_score", "Max Match Score")}: ${_maxTotalScore.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    Text('${context.tr("team_details.min_score", "Min")}: ${_minTotalScore.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    Text('${context.tr("team_details.scouted_matches", "Scouted Matches")}: ${_matchEntries.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                  ],
                ),
              ],
            ),
          ),

          // Match-by-Match Score Trend Progression Chart
          if (_matchScoreSummaries.isNotEmpty)
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.show_chart_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('team_details.match_scoring_trend', 'Match-by-Match Scoring Trend'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                        ],
                      ),
                      Text(
                        '${_matchScoreSummaries.length} ${context.tr("team_details.matches", "matches")}',
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildMatchProgressionChart(context),
                  const SizedBox(height: 12),
                  // Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _legendItem(context.tr('team_details.auto_avg', 'Auto'), Colors.blueAccent),
                      const SizedBox(width: 16),
                      _legendItem(context.tr('team_details.teleop_avg', 'Teleop'), Colors.deepPurpleAccent),
                      const SizedBox(width: 16),
                      _legendItem(context.tr('team_details.endgame_avg', 'Endgame'), Colors.tealAccent),
                    ],
                  ),
                ],
              ),
            ),

          // Field Metrics Breakdown (Game Config Driven)
          if (_fieldMetrics.isNotEmpty)
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('team_details.game_metrics', 'Game Metrics Analysis'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._fieldMetrics.values.map((metric) => _buildMetricRow(context, metric)),
                ],
              ),
            ),

          // Qualitative Notes & Comments
          if (_qualEntries.isNotEmpty)
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.rate_review_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${context.tr("team_details.qualitative_notes", "Qualitative Scout Notes")} (${_qualEntries.length})',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._qualEntries.map((e) {
                    final data = e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : e;
                    final matchNum = e['matchNumber'] ?? data['matchNumber'] ?? '?';
                    final scouter = _getScouterUsername(e);
                    final notes = data['notes'] ?? data['comments'] ?? data['driver_skill'] ?? data.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.isDark(context) ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Match $matchNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: ObsidianUITheme.primaryAccent)),
                                Text('By $scouter', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(notes.toString(), style: TextStyle(fontSize: 13, color: primaryTextColor)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) {
    return ObsidianGlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _phasePill(String label, double val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 2),
          Text(val.toStringAsFixed(1), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMatchProgressionChart(BuildContext context) {
    if (_matchScoreSummaries.isEmpty) return const SizedBox.shrink();

    final maxVal = _matchScoreSummaries.map((m) => m.totalPoints).fold(0.0, max);
    const maxBarHeight = 90.0;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    void showMatchDetailsModal(_MatchScoreSummary item) {
      ObsidianChartHaptics.impact();
      showModalBottomSheet(
        context: context,
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final autoPct = item.totalPoints > 0 ? (item.autoPoints / item.totalPoints) * 100 : 0.0;
          final teleopPct = item.totalPoints > 0 ? (item.teleopPoints / item.totalPoints) * 100 : 0.0;
          final endgamePct = item.totalPoints > 0 ? (item.endgamePoints / item.totalPoints) * 100 : 0.0;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Match ${item.matchNumber} Breakdown',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: ObsidianUITheme.primaryAccent,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${item.totalPoints.toStringAsFixed(0)} pts',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildPhaseScoreBar('Auto Phase', item.autoPoints, autoPct, Colors.blueAccent),
                  const SizedBox(height: 10),
                  _buildPhaseScoreBar('Teleop Phase', item.teleopPoints, teleopPct, Colors.deepPurpleAccent),
                  const SizedBox(height: 10),
                  _buildPhaseScoreBar('Endgame Phase', item.endgamePoints, endgamePct, Colors.tealAccent),
                ],
              ),
            ),
          );
        },
      );
    }

    return ScrollConfiguration(
      behavior: const ObsidianChartScrollBehavior(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _matchScoreSummaries.map((item) {
              final autoHeight = maxVal > 0 ? (item.autoPoints / maxVal) * maxBarHeight : 0.0;
              final teleopHeight = maxVal > 0 ? (item.teleopPoints / maxVal) * maxBarHeight : 0.0;
              final endgameHeight = maxVal > 0 ? (item.endgamePoints / maxVal) * maxBarHeight : 0.0;
              final totalHeight = autoHeight + teleopHeight + endgameHeight;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showMatchDetailsModal(item),
                  child: Tooltip(
                    message: 'Match ${item.matchNumber}: ${item.totalPoints.toStringAsFixed(0)} pts\nAuto: ${item.autoPoints.toStringAsFixed(0)} • Teleop: ${item.teleopPoints.toStringAsFixed(0)} • Endgame: ${item.endgamePoints.toStringAsFixed(0)}\n(Tap for breakdown)',
                    child: Container(
                      width: _matchScoreSummaries.length <= 4
                          ? (MediaQuery.of(context).size.width - 90) / _matchScoreSummaries.length
                          : 54.0,
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.totalPoints.toStringAsFixed(0),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 30,
                            height: maxBarHeight,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 30,
                              height: totalHeight.clamp(2.0, maxBarHeight),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white12, width: 0.8),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (endgameHeight > 0) Container(height: endgameHeight, color: Colors.tealAccent),
                                  if (teleopHeight > 0) Container(height: teleopHeight, color: Colors.deepPurpleAccent),
                                  if (autoHeight > 0) Container(height: autoHeight, color: Colors.blueAccent),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'M${item.matchNumber}',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: secondaryTextColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseScoreBar(String label, double points, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                ],
              ),
              Text(
                '${points.toStringAsFixed(1)} pts (${pct.toStringAsFixed(0)}%)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, _FieldMetricSummary metric) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (metric.percentage != null) {
      final pct = metric.percentage!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(metric.field.label, style: TextStyle(fontSize: 13, color: primaryTextColor)),
                Text('${pct.toStringAsFixed(0)}% (${metric.total.toInt()}/${metric.count})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black12,
                valueColor: const AlwaysStoppedAnimation<Color>(ObsidianUITheme.primaryAccent),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }

    if (metric.average != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.field.label, style: TextStyle(fontSize: 13, color: primaryTextColor)),
                  Text('Max: ${metric.max?.toStringAsFixed(1)} | Total: ${metric.total.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Avg: ${metric.average!.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
              ),
            ),
          ],
        ),
      );
    }

    if (metric.optionCounts != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(metric.field.label, style: TextStyle(fontSize: 13, color: primaryTextColor)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: metric.optionCounts!.entries.map((opt) {
                return Chip(
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text('${opt.key}: ${opt.value}', style: const TextStyle(fontSize: 10)),
                  backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tab 2: Matches
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildMatchesTab(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final teamNumStr = widget.team.teamNumber.toString();

    final qualCount = _teamMatches.where((m) => m.compLevel.toLowerCase() == 'qm' || m.compLevel.toLowerCase() == 'qual').length;
    final playoffCount = _teamMatches.where((m) => ['playoff', 'qf', 'sf', 'f'].contains(m.compLevel.toLowerCase())).length;
    final practiceCount = _teamMatches.where((m) => m.compLevel.toLowerCase() == 'practice').length;

    final filteredMatches = _teamMatches.where((m) {
      if (_matchCompLevelFilter == 'all') return true;
      final lvl = m.compLevel.toLowerCase();
      if (_matchCompLevelFilter == 'qm') return lvl == 'qm' || lvl == 'qual';
      if (_matchCompLevelFilter == 'playoff') return ['playoff', 'qf', 'sf', 'f'].contains(lvl);
      if (_matchCompLevelFilter == 'practice') return lvl == 'practice';
      return true;
    }).toList();

    return Column(
      children: [
        // Comp Level Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: Row(
            children: [
              for (final opt in [
                ('all', '${context.tr("team_details.all_matches", "All")} (${_teamMatches.length})'),
                ('qm', '${context.tr("team_details.qualification", "Qual")} ($qualCount)'),
                ('playoff', '${context.tr("team_details.playoffs", "Playoffs")} ($playoffCount)'),
                ('practice', '${context.tr("team_details.practice", "Practice")} ($practiceCount)'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(opt.$2),
                    selected: _matchCompLevelFilter == opt.$1,
                    selectedColor: ObsidianUITheme.primaryAccent,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _matchCompLevelFilter == opt.$1 ? Colors.white : secondaryTextColor,
                      fontWeight: _matchCompLevelFilter == opt.$1 ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _matchCompLevelFilter = opt.$1),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: filteredMatches.isEmpty
              ? Center(
                  child: Text(
                    context.tr('team_details.no_matches', 'No matches found for this filter.'),
                    style: TextStyle(color: secondaryTextColor),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  itemCount: filteredMatches.length,
                  itemBuilder: (context, i) {
                    final m = filteredMatches[i];
                    final isRed = m.redTeams.any((t) => t.replaceAll(RegExp(r'^(frc|ftc)'), '') == teamNumStr);
                    final scouted = _matchEntries.firstWhere(
                      (e) {
                        final mn = e['matchNumber'] ?? (e['data'] is Map ? e['data']['matchNumber'] : null);
                        return mn == m.matchNumber || e['matchKey'] == m.matchKey;
                      },
                      orElse: () => <String, dynamic>{},
                    );

                    final lvl = m.compLevel.toLowerCase();
                    Color levelColor = ObsidianUITheme.primaryAccent;
                    String levelText = 'QUAL';
                    if (lvl == 'practice') {
                      levelColor = Colors.teal;
                      levelText = 'PRACTICE';
                    } else if (lvl == 'qf' || lvl == 'sf' || lvl == 'f' || lvl == 'playoff') {
                      levelColor = Colors.orangeAccent;
                      levelText = lvl.toUpperCase();
                    }

                    return ObsidianGlassCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: levelColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: levelColor.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      levelText,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: levelColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    m.displayLabel,
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isRed ? Colors.red : Colors.blue).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: (isRed ? Colors.red : Colors.blue).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  isRed ? context.tr('team_details.red_alliance', 'RED ALLIANCE') : context.tr('team_details.blue_alliance', 'BLUE ALLIANCE'),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isRed ? Colors.redAccent : Colors.lightBlueAccent),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Alliances
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('team_details.red_alliance', 'Red Alliance'), style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      children: m.redTeams.map((t) {
                                        final isSelf = t.replaceAll(RegExp(r'^(frc|ftc)'), '') == teamNumStr;
                                        return _teamBadge(t, Colors.red, isSelf);
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('team_details.blue_alliance', 'Blue Alliance'), style: const TextStyle(fontSize: 10, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      children: m.blueTeams.map((t) {
                                        final isSelf = t.replaceAll(RegExp(r'^(frc|ftc)'), '') == teamNumStr;
                                        return _teamBadge(t, Colors.blue, isSelf);
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (scouted.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: ObsidianUITheme.successGreen, size: 14),
                                    const SizedBox(width: 4),
                                    Text('Scouted by ${_getScouterUsername(scouted)}', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _teamBadge(String teamCode, Color color, bool isSelf) {
    final numStr = teamCode.replaceAll(RegExp(r'^(frc|ftc)'), '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSelf ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelf ? color : color.withValues(alpha: 0.2),
          width: isSelf ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        numStr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelf ? FontWeight.bold : FontWeight.normal,
          color: isSelf ? Colors.white : color,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tab 3: Pit Profile
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPitTab(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (_pitEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_circle_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(context.tr('team_details.no_pit', 'No pit scouting profile available for this team.'), style: TextStyle(color: secondaryTextColor)),
          ],
        ),
      );
    }

    final latestPit = _pitEntries.first;
    final data = latestPit['data'] is Map ? Map<String, dynamic>.from(latestPit['data'] as Map) : latestPit;
    final fields = _pitConfig?.fields ?? [];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ObsidianGlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('team_details.pit_profile', 'Pit Scouting Profile'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    Text('By ${_getScouterUsername(latestPit)}', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                  ],
                ),
                const SizedBox(height: 16),
                if (fields.isEmpty)
                  ...data.entries.where((e) => !['targetTeamNumber', 'eventKey', 'id'].contains(e.key)).map((e) {
                    return _pitFieldRow(e.key, e.value?.toString() ?? '--', primaryTextColor, secondaryTextColor);
                  })
                else
                  ...fields.where((f) {
                    final t = f.type.toLowerCase();
                    return t != 'section' && t != 'header' && t != 'divider';
                  }).map((f) {
                    final val = data[f.id];
                    return _pitFieldRow(f.label, val != null ? val.toString() : '--', primaryTextColor, secondaryTextColor);
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pitFieldRow(String label, String value, Color primary, Color secondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(fontSize: 13, color: secondary)),
          ),
          Expanded(
            child: Text(
              value == 'true' ? 'Yes' : (value == 'false' ? 'No' : value),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tab 4: Scouting Records
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildRecordsTab(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    final allRecords = <_ScoutingRecordItem>[];

    for (var e in _matchEntries) {
      allRecords.add(_ScoutingRecordItem(type: 'Match', entry: e, date: DateTime.tryParse(e['createdAt']?.toString() ?? '')));
    }
    for (var e in _pitEntries) {
      allRecords.add(_ScoutingRecordItem(type: 'Pit', entry: e, date: DateTime.tryParse(e['createdAt']?.toString() ?? '')));
    }
    for (var e in _qualEntries) {
      allRecords.add(_ScoutingRecordItem(type: 'Qualitative', entry: e, date: DateTime.tryParse(e['createdAt']?.toString() ?? '')));
    }

    // Filter
    final filtered = allRecords.where((r) {
      if (_recordFilter == 'match') return r.type == 'Match';
      if (_recordFilter == 'pit') return r.type == 'Pit';
      if (_recordFilter == 'qual') return r.type == 'Qualitative';
      return true;
    }).toList();

    filtered.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

    return Column(
      children: [
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: Row(
            children: [
              for (final opt in [
                ('all', context.tr('all_data.all_records', 'All')),
                ('match', context.tr('all-data.match_scouting', 'Match')),
                ('pit', context.tr('all-data.pit_scouting', 'Pit')),
                ('qual', context.tr('all-data.qualitative_scouting', 'Qualitative')),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(opt.$2),
                    selected: _recordFilter == opt.$1,
                    selectedColor: ObsidianUITheme.primaryAccent,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _recordFilter == opt.$1 ? Colors.white : secondaryTextColor,
                      fontWeight: _recordFilter == opt.$1 ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _recordFilter = opt.$1),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(context.tr('team_details.no_records', 'No scouting records found for this team.'), style: TextStyle(color: secondaryTextColor)))
              : ListView.builder(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final entry = item.entry;
                    final data = entry['data'] is Map ? Map<String, dynamic>.from(entry['data'] as Map) : entry;
                    final matchNum = entry['matchNumber'] ?? data['matchNumber'];

                    return ObsidianGlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(top: 8),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _recordTypeColor(item.type).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(item.type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _recordTypeColor(item.type))),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              matchNum != null ? 'Match $matchNum' : item.type,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Scouted by ${_getScouterUsername(entry)} • ${entry["createdAt"] ?? ""}',
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                        children: [
                          ...data.entries.where((e) => !['targetTeamNumber', 'eventKey', 'id', 'matchNumber', 'matchKey'].contains(e.key)).map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(e.key, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                                  Text(e.value?.toString() ?? '--', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getScouterUsername(Map<String, dynamic> entry) {
    if (entry.isEmpty) return 'Scout';
    final data = entry['data'] is Map ? Map<String, dynamic>.from(entry['data'] as Map) : entry;
    final u = entry['username'] ??
        entry['submittedByUsername'] ??
        entry['scouter'] ??
        entry['scouterUsername'] ??
        entry['user'] ??
        data['username'] ??
        data['scouter'] ??
        data['scout_name'] ??
        data['scoutName'] ??
        data['submittedBy'] ??
        data['scouter_name'];

    if (u != null && u.toString().trim().isNotEmpty && u.toString().trim() != 'null') {
      return u.toString().trim();
    }

    final teamNum = entry['ownerTeamNumber'] ?? entry['teamNumber'] ?? data['ownerTeamNumber'];
    if (teamNum != null && teamNum.toString().trim().isNotEmpty && teamNum.toString().trim() != 'null') {
      return 'Team ${teamNum.toString().trim()}';
    }
    return 'Scout';
  }

  Color _recordTypeColor(String type) {
    switch (type) {
      case 'Match':
        return Colors.blueAccent;
      case 'Pit':
        return Colors.amber;
      case 'Qualitative':
        return ObsidianUITheme.secondaryAccent;
      default:
        return ObsidianUITheme.primaryAccent;
    }
  }
}

class _MatchScoreSummary {
  final String matchKey;
  final int matchNumber;
  final double autoPoints;
  final double teleopPoints;
  final double endgamePoints;
  final double totalPoints;

  _MatchScoreSummary({
    required this.matchKey,
    required this.matchNumber,
    required this.autoPoints,
    required this.teleopPoints,
    required this.endgamePoints,
    required this.totalPoints,
  });
}

class _FieldMetricSummary {
  final ScoutingFieldModel field;
  final double? average;
  final double? max;
  final double? percentage;
  final double total;
  final int count;
  final Map<String, int>? optionCounts;

  _FieldMetricSummary({
    required this.field,
    this.average,
    this.max,
    this.percentage,
    this.total = 0.0,
    this.count = 0,
    this.optionCounts,
  });
}

class _ScoutingRecordItem {
  final String type;
  final Map<String, dynamic> entry;
  final DateTime? date;

  _ScoutingRecordItem({
    required this.type,
    required this.entry,
    this.date,
  });
}

extension _StringExt on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
