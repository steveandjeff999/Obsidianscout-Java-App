import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/config_models.dart';
import '../../models/graph_models.dart';
import '../../models/team_match_models.dart';
import '../../theme/obsidian_ui_theme.dart';
import 'fullscreen_graph_modal.dart';

class TeamStrategyCard extends StatefulWidget {
  final int teamNumber;
  final String alliance; // 'blue' | 'red'
  final int stationNumber; // 1, 2, 3
  final TeamModel? team;
  final List<dynamic> matchEntries;
  final List<dynamic> pitEntries;
  final List<dynamic> qualEntries;
  final ScoutingConfigModel? matchConfig;
  final ScoutingConfigModel? pitConfig;
  final ScoutingConfigModel? qualConfig;
  final List<MatchModel> allMatches;
  final StatsHistoryModel? statsHistory;
  final bool useStatboticsEpa;
  final bool useMatch13Exp;
  final bool useTbaOpr;
  final bool isFtc;

  const TeamStrategyCard({
    super.key,
    required this.teamNumber,
    required this.alliance,
    required this.stationNumber,
    required this.team,
    required this.matchEntries,
    required this.pitEntries,
    required this.qualEntries,
    required this.matchConfig,
    required this.pitConfig,
    required this.qualConfig,
    required this.allMatches,
    required this.statsHistory,
    required this.useStatboticsEpa,
    required this.useMatch13Exp,
    required this.useTbaOpr,
    this.isFtc = false,
  });

  @override
  State<TeamStrategyCard> createState() => _TeamStrategyCardState();
}

class _TeamStrategyCardState extends State<TeamStrategyCard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _activeDatasource = 'scouted'; // 'scouted' | 'statbotics' | 'match13'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _scoreEntry(ScoutingConfigModel? config, Map<String, dynamic>? data) {
    if (config == null || data == null) return 0.0;
    double score = 0.0;

    for (final field in config.fields) {
      final val = data[field.id];
      if (val == null) continue;

      final type = field.type.toLowerCase();
      final pointsPer = field.pointsPer ?? 0.0;

      if (type == 'counter' || type == 'number' || type == 'rating') {
        final numVal = double.tryParse(val.toString());
        if (numVal != null) {
          score += pointsPer * numVal;
        }
      } else if (type == 'checkbox') {
        if (val == true || val == 'true' || val == 1) {
          score += pointsPer;
        }
      } else if (type == 'select' || type == 'radio') {
        for (final opt in field.options) {
          if (opt.value == val.toString() || opt.label == val.toString()) {
            score += opt.points;
          }
        }
      }
    }
    return score;
  }

  GraphDataSeries _getGraphData(String datasource) {
    final teamNum = widget.teamNumber;

    if (datasource == 'statbotics') {
      final epaHistory = widget.statsHistory?.epaHistory ?? [];
      final List<Map<String, dynamic>> teamItems = [];

      for (final item in epaHistory) {
        if (item is Map) {
          final rawTeam = item['teamNumber'] ?? item['team_number'] ?? item['team'];
          final itemTeam = rawTeam is num
              ? rawTeam.toInt()
              : (int.tryParse(rawTeam?.toString().replaceAll(RegExp(r'\D'), '') ?? '') ?? 0);
          if (itemTeam == teamNum) {
            final matchKey = (item['matchKey'] ?? item['match_key'] ?? '').toString();
            final epaVal = (item['epa'] ?? item['epaValue'] ?? item['total_points'] ?? item['total_epa'] ?? 0.0) as num;
            final label = _formatMatchKey(matchKey);
            teamItems.add({'label': label, 'val': epaVal.toDouble(), 'weight': _getMatchWeight(label)});
          }
        }
      }

      teamItems.sort((a, b) => (a['weight'] as int).compareTo(b['weight'] as int));

      return GraphDataSeries(
        labels: teamItems.map((e) => e['label'] as String).toList(),
        values: teamItems.map((e) => (e['val'] as num).toDouble()).toList(),
        title: 'Statbotics EPA',
        unit: 'EPA',
        color: const Color(0xFF10B981),
      );
    }

    if (datasource == 'match13') {
      final match13History = widget.statsHistory?.match13History ?? [];
      final List<Map<String, dynamic>> teamItems = [];

      for (final item in match13History) {
        final teamData = extractTeamExpData(item, teamNum);
        if (teamData != null) {
          final expVal = getTeamExpMetricValue(teamData, 'total');
          final matchKey = (item is Map ? item['matchKey'] ?? item['match_key'] ?? '' : '').toString();
          final label = _formatMatchKey(matchKey);
          teamItems.add({'label': label, 'val': expVal, 'weight': _getMatchWeight(label)});
        }
      }

      teamItems.sort((a, b) => (a['weight'] as int).compareTo(b['weight'] as int));

      return GraphDataSeries(
        labels: teamItems.map((e) => e['label'] as String).toList(),
        values: teamItems.map((e) => (e['val'] as num).toDouble()).toList(),
        title: 'Match 13 EXP',
        unit: 'EXP',
        color: const Color(0xFFF59E0B),
      );
    }

    // Default: Scouted Points
    final sorted = List<dynamic>.from(widget.matchEntries)
      ..sort((a, b) {
        final numA = (a is Map ? a['matchNumber'] : a.matchNumber) ?? 0;
        final numB = (b is Map ? b['matchNumber'] : b.matchNumber) ?? 0;
        return (numA as num).compareTo(numB as num);
      });

    final labels = <String>[];
    final values = <double>[];

    for (int i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final matchNum = e is Map ? e['matchNumber'] : e.matchNumber;
      final matchKey = e is Map ? e['matchKey'] : e.matchKey;
      final data = (e is Map ? e['data'] : e.data) as Map<String, dynamic>?;

      if (matchNum != null) {
        labels.add('QM $matchNum');
      } else if (matchKey != null) {
        labels.add(_formatMatchKey(matchKey.toString()));
      } else {
        labels.add('#${i + 1}');
      }
      values.add(_scoreEntry(widget.matchConfig, data));
    }

    return GraphDataSeries(
      labels: labels,
      values: values,
      title: 'Scouted Points',
      unit: 'pts',
      color: const Color(0xFF6366F1),
    );
  }

  String _formatMatchKey(String raw) {
    if (raw.isEmpty) return 'Match';
    final parts = raw.split('_');
    final comp = parts.length > 1 ? parts.last.toLowerCase() : raw.toLowerCase();
    if (comp.startsWith('qm')) return 'QM ${comp.replaceAll('qm', '')}';
    if (comp.startsWith('qf')) return comp.toUpperCase();
    if (comp.startsWith('sf')) return comp.toUpperCase();
    if (comp.startsWith('f')) return 'Final ${comp.replaceAll('f', '')}';
    return comp.toUpperCase();
  }

  int _getMatchWeight(String label) {
    final upper = label.toUpperCase();
    int base = 100000;
    if (upper.startsWith('P ') || upper.startsWith('PR')) {
      base = 10000;
    } else if (upper.startsWith('QM')) {
      base = 20000;
    } else if (upper.startsWith('QF')) {
      base = 40000;
    } else if (upper.startsWith('SF')) {
      base = 50000;
    } else if (upper.startsWith('FINAL') || upper.startsWith('F ')) {
      base = 60000;
    }

    final match = RegExp(r'\d+').firstMatch(label);
    if (match != null) {
      return base + (int.tryParse(match.group(0)!) ?? 0);
    }
    return base;
  }

  void _openFullscreenGraph() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => FullscreenGraphModal(
        teamNumber: widget.teamNumber,
        team: widget.team,
        initialDatasource: _activeDatasource,
        enableStatbotics: !widget.isFtc && widget.useStatboticsEpa,
        enableMatch13: !widget.isFtc && widget.useMatch13Exp,
        dataProvider: _getGraphData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final isBlue = widget.alliance.toLowerCase() == 'blue';
    final accentBorder = isBlue ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final pillBg = isBlue ? const Color(0x333B82F6) : const Color(0x33EF4444);
    final pillText = isBlue ? const Color(0xFF60A5FA) : const Color(0xFFF87171);

    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    final teamNick = widget.team?.nickname ?? widget.team?.name ?? '';
    final stationLabel = '${widget.alliance.toUpperCase()[0]}${widget.stationNumber}';

    // Calculate dynamic average score
    String calculatedAvg = '-';
    if (widget.matchEntries.isNotEmpty) {
      double sum = 0;
      for (final e in widget.matchEntries) {
        final data = (e is Map ? e['data'] : e.data) as Map<String, dynamic>?;
        sum += _scoreEntry(widget.matchConfig, data);
      }
      calculatedAvg = (sum / widget.matchEntries.length).toStringAsFixed(1);
    } else if (widget.team?.averagePoints != null) {
      calculatedAvg = widget.team!.averagePoints!.toStringAsFixed(1);
    }

    final epaStr = widget.team?.epa != null ? widget.team!.epa!.toStringAsFixed(1) : '-';
    final expStr = (widget.team?.exp ?? widget.team?.match13Exp) != null
        ? (widget.team?.exp ?? widget.team?.match13Exp)!.toStringAsFixed(1)
        : '-';
    final oprStr = widget.team?.opr != null ? widget.team!.opr!.toStringAsFixed(1) : '-';

    final teamMatches = widget.allMatches.where((m) {
      final all = [...m.redTeams, ...m.blueTeams];
      return all.any((k) => k.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '') == widget.teamNumber.toString());
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4.0, color: accentBorder),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // Header: Team #, Nickname, Station Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '#${widget.teamNumber}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryTextColor,
                      ),
                    ),
                    if (teamNick.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          teamNick,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: secondaryTextColor,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accentBorder.withValues(alpha: 0.5)),
                ),
                child: Text(
                  stationLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: pillText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Summary Metrics Grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildStatPill('Scouted Avg', calculatedAvg, const Color(0xFF10B981), isDark),
              if (!widget.isFtc && widget.useStatboticsEpa)
                _buildStatPill('Statbotics EPA', epaStr, ObsidianUITheme.primaryAccent, isDark),
              if (!widget.isFtc && widget.useMatch13Exp)
                _buildStatPill('Match 13 EXP', expStr, const Color(0xFFF59E0B), isDark),
              if (widget.useTbaOpr)
                _buildStatPill(widget.isFtc ? 'FTC OPR' : 'TBA OPR', oprStr, const Color(0xFF8B5CF6), isDark),
              _buildStatPill('Matches', '${teamMatches.length}', primaryTextColor, isDark),
            ],
          ),

          const SizedBox(height: 12),

          // Tab Bar
          TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: ObsidianUITheme.primaryAccent,
            unselectedLabelColor: secondaryTextColor,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            indicatorColor: ObsidianUITheme.primaryAccent,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'History'),
              Tab(text: 'Graph'),
            ],
          ),

          const SizedBox(height: 8),

          // Tab Content Area
          SizedBox(
            height: 220,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Overview & Pit Specs + Notes
                _buildOverviewTab(primaryTextColor, secondaryTextColor, isDark),

                // Tab 2: Match History
                _buildHistoryTab(teamMatches, primaryTextColor, secondaryTextColor),

                // Tab 3: Performance Graph
                _buildGraphTab(primaryTextColor, secondaryTextColor, isDark),
              ],
            ),
          ),
        ],
      ),
    ),
  ],
),
),
);
  }

  Widget _buildStatPill(String label, String value, Color valColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: valColor),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(Color primaryTextColor, Color secondaryTextColor, bool isDark) {
    final pitEntries = widget.pitEntries;
    final pitConfig = widget.pitConfig;

    final notes = <Map<String, String>>[];

    // Extract Pit Specs
    final specs = <Map<String, String>>[];
    for (final e in pitEntries) {
      final data = (e is Map ? e['data'] : e.data) as Map<String, dynamic>?;
      if (data != null && pitConfig?.fields != null) {
        for (final f in pitConfig!.fields) {
          final val = data[f.id];
          if (val != null && val.toString().isNotEmpty) {
            if (f.type == 'text' || f.type == 'textarea') {
              notes.add({
                'type': 'Pit',
                'label': f.label,
                'text': val.toString(),
                'date': (e is Map ? e['createdAt'] : e.createdAt)?.toString() ?? '',
              });
            } else {
              String displayVal = val.toString();
              if (f.type == 'checkbox') {
                displayVal = (val == true || val == 'true' || val == 1) ? 'Yes' : 'No';
              }
              specs.add({'label': f.label, 'val': displayVal});
            }
          }
        }
      }
    }

    // Extract qualitative notes from match entries
    for (final e in widget.matchEntries) {
      final data = (e is Map ? e['data'] : e.data) as Map<String, dynamic>?;
      final matchNum = e is Map ? e['matchNumber'] : e.matchNumber;
      if (data != null && widget.matchConfig?.fields != null) {
        for (final f in widget.matchConfig!.fields) {
          final val = data[f.id];
          if (val != null && val.toString().isNotEmpty && (f.type == 'text' || f.type == 'textarea')) {
            notes.add({
              'type': matchNum != null ? 'Match $matchNum' : 'Match',
              'label': f.label,
              'text': val.toString(),
              'date': (e is Map ? e['createdAt'] : e.createdAt)?.toString() ?? '',
            });
          }
        }
      }
    }

    // Extract qualitative notes from qual entries
    for (final e in widget.qualEntries) {
      final data = (e is Map ? e['data'] : e.data) as Map<String, dynamic>?;
      final matchNum = e is Map ? e['matchNumber'] : e.matchNumber;
      if (data != null && widget.qualConfig?.fields != null) {
        for (final f in widget.qualConfig!.fields) {
          final val = data[f.id];
          if (val != null && val.toString().isNotEmpty && (f.type == 'text' || f.type == 'textarea')) {
            notes.add({
              'type': matchNum != null ? 'Qual $matchNum' : 'Qual',
              'label': f.label,
              'text': val.toString(),
              'date': (e is Map ? e['createdAt'] : e.createdAt)?.toString() ?? '',
            });
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.only(top: 6),
      children: [
        // Pit Specs Grid
        if (specs.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: specs.map((s) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['label']!.toUpperCase(), style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                    Text(s['val']!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primaryTextColor)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Scouter Notes
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No qualitative comments recorded.',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: secondaryTextColor),
              ),
            ),
          )
        else
          ...notes.map((n) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: ObsidianUITheme.primaryAccent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(n['type']!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                      Text(n['date']!.split('T').first, style: TextStyle(fontSize: 9.5, color: secondaryTextColor)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${n['label']}: ${n['text']}',
                    style: TextStyle(fontSize: 11.5, color: primaryTextColor),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHistoryTab(List<MatchModel> matches, Color primaryTextColor, Color secondaryTextColor) {
    if (matches.isEmpty) {
      return Center(
        child: Text('No match schedule data.', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: secondaryTextColor)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: matches.length,
      itemBuilder: (ctx, idx) {
        final m = matches[idx];
        final matchLabel = m.label.isNotEmpty ? m.label : (m.matchNumber != null ? 'Q${m.matchNumber}' : m.matchKey);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  matchLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ),

              // Red Teams
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: m.redTeams.map((key) {
                    final numStr = key.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '');
                    final isSelf = numStr == widget.teamNumber.toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0x33EF4444),
                        borderRadius: BorderRadius.circular(4),
                        border: isSelf ? Border.all(color: const Color(0xFFEF4444), width: 1.5) : null,
                      ),
                      child: Text(
                        numStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isSelf ? FontWeight.w900 : FontWeight.w600,
                          color: const Color(0xFFF87171),
                          decoration: isSelf ? TextDecoration.underline : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(width: 6),

              // Blue Teams
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: m.blueTeams.map((key) {
                    final numStr = key.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '');
                    final isSelf = numStr == widget.teamNumber.toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0x333B82F6),
                        borderRadius: BorderRadius.circular(4),
                        border: isSelf ? Border.all(color: const Color(0xFF3B82F6), width: 1.5) : null,
                      ),
                      child: Text(
                        numStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isSelf ? FontWeight.w900 : FontWeight.w600,
                          color: const Color(0xFF60A5FA),
                          decoration: isSelf ? TextDecoration.underline : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGraphTab(Color primaryTextColor, Color secondaryTextColor, bool isDark) {
    final series = _getGraphData(_activeDatasource);

    return Column(
      children: [
        // Datasource Switch & Fullscreen Enlarge Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInlineSourceBtn('scouted', 'Scouted'),
                      if (!widget.isFtc && widget.useStatboticsEpa)
                        _buildInlineSourceBtn('statbotics', 'Statbotics'),
                      if (!widget.isFtc && widget.useMatch13Exp)
                        _buildInlineSourceBtn('match13', 'Match 13'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _openFullscreenGraph,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fullscreen_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 2),
                    Text(
                      'Fullscreen',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ObsidianUITheme.primaryAccent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // Preview Line Chart (clickable to enlarge)
        Expanded(
          child: InkWell(
            onTap: _openFullscreenGraph,
            child: series.values.isEmpty
                ? Center(
                    child: Text(
                      'No ${series.title} recorded.',
                      style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: secondaryTextColor),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (val) => FlLine(
                          color: isDark ? Colors.white10 : Colors.black12,
                          strokeWidth: 1,
                        ),
                        getDrawingVerticalLine: (val) => FlLine(
                          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: const FlTitlesData(
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(
                            series.values.length,
                            (i) => FlSpot(i.toDouble(), series.values[i]),
                          ),
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: series.color,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 3.5,
                                color: series.color,
                                strokeWidth: 1.5,
                                strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineSourceBtn(String key, String label) {
    final isActive = _activeDatasource == key;
    return InkWell(
      onTap: () => setState(() => _activeDatasource = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? ObsidianUITheme.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
