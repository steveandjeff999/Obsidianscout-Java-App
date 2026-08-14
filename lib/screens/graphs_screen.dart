import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../models/graph_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';

// Reserved fields that are metadata, not graphable
const _reserved = {'eventKey', 'matchKey', 'matchNumber', 'targetTeamNumber'};

class GraphsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const GraphsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends State<GraphsScreen> {
  bool _isLoading = true;
  String? _eventKey;
  ScoutingConfigModel? _config;
  List<ScoutingEntryModel> _entries = [];
  List<TeamModel> _teams = [];

  // State - mirrors web page
  List<GraphMetric> _metrics = [];
  GraphMetric? _selectedMetric;
  Set<int> _selectedTeams = {};
  String _graphType = 'bar'; // bar, line, scatter, area
  String _dataView = 'averages'; // averages, matches
  String _sort = 'value_desc'; // value_desc, value_asc, team_asc, team_desc
  String _teamSearch = '';
  bool _graphGenerated = false;

  // Computed graph data
  List<GraphPoint> _barPoints = [];
  List<GraphSeries> _lineSeries = [];

  // Summary stats
  int _totalEntries = 0;
  int _totalTeams = 0;
  int _totalEvents = 0;
  int _totalMatches = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant GraphsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final eventKey = await widget.apiService.fetchCurrentEventKey();
    final config = await widget.apiService.fetchMatchConfig();
    final rawEntries = await widget.apiService.fetchScoutingEntries();
    final teams = await widget.apiService.fetchTeams(eventKey);

    final entries = rawEntries
        .map((e) => ScoutingEntryModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // Build metrics list from config
    final metrics = _buildMetrics(config);

    // Summary stats
    final teamSet = entries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
    final matchSet = entries.map((e) => e.matchKey).whereType<String>().toSet();
    final eventSet = entries.map((e) => e.eventKey).whereType<String>().toSet();

    setState(() {
      _eventKey = eventKey;
      _config = config;
      _entries = entries;
      _teams = teams;
      _metrics = metrics;
      _selectedMetric = metrics.isNotEmpty ? metrics.first : null;
      _totalEntries = entries.length;
      _totalTeams = teamSet.length;
      _totalMatches = matchSet.length;
      _totalEvents = eventSet.length;
      _isLoading = false;
    });
  }

  List<GraphMetric> _buildMetrics([ScoutingConfigModel? overrideConfig]) {
    final config = overrideConfig ?? _config;
    final metrics = <GraphMetric>[
      const GraphMetric(id: 'count', label: 'Entry Count', kind: 'count'),
    ];

    for (final field in config?.fields ?? []) {
      if (_reserved.contains(field.id) || field.type.toLowerCase() == 'section') continue;
      final type = field.type.toLowerCase();
      if (type == 'number' || type == 'counter' || type == 'rating') {
        metrics.add(GraphMetric(id: 'field:${field.id}', label: field.label, kind: 'numeric', fieldId: field.id));
      }
    }
    return metrics;
  }

  List<ScoutingEntryModel> _getFilteredEntries() {
    if (_selectedTeams.isEmpty) return [];
    final result = <ScoutingEntryModel>[];
    for (final teamNum in _selectedTeams) {
      final teamEntries = _entries.where((e) {
        if (e.targetTeamNumber != teamNum) return false;
        if (_eventKey != null && _eventKey!.isNotEmpty && e.eventKey != _eventKey) return false;
        return true;
      }).toList();
      result.addAll(teamEntries);
    }
    return result;
  }

  double _metricValue(ScoutingEntryModel entry, GraphMetric metric) {
    if (metric.kind == 'count') return 1.0;
    if (metric.kind == 'numeric' && metric.fieldId != null) {
      final raw = entry.data[metric.fieldId!];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? 0.0;
      return 0.0;
    }
    return 0.0;
  }

  void _generateGraph() {
    if (_selectedMetric == null || _selectedTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one team and a metric'), backgroundColor: ObsidianUITheme.warningOrange),
      );
      return;
    }

    final entries = _getFilteredEntries();
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No scouting entries found for selected teams'), backgroundColor: ObsidianUITheme.warningOrange),
      );
      return;
    }

    final metric = _selectedMetric!;

    if (_graphType == 'bar') {
      // Averages per team
      final stats = _buildTeamStats(entries, metric);
      final sorted = _sortStats(stats);
      setState(() {
        _barPoints = sorted.map((s) => GraphPoint('${s.$1}', s.$2)).toList();
        _lineSeries = [];
        _graphGenerated = true;
      });
    } else {
      // Line / scatter / area  — per-match series per team
      if (_dataView == 'averages') {
        final stats = _buildTeamStats(entries, metric);
        final sorted = _sortStats(stats);
        setState(() {
          _lineSeries = [
            GraphSeries(
              name: metric.label,
              x: sorted.map((s) => '${s.$1}').toList(),
              y: sorted.map((s) => s.$2).toList(),
            )
          ];
          _barPoints = [];
          _graphGenerated = true;
        });
      } else {
        // Per-match for each team — sort by comp level then match number
        final seriesList = <GraphSeries>[];
        for (final teamNum in _selectedTeams) {
          final teamEntries = entries
              .where((e) => e.targetTeamNumber == teamNum)
              .toList()
            ..sort((a, b) {
              final la = _matchSortKey(a.matchKey, a.matchNumber);
              final lb = _matchSortKey(b.matchKey, b.matchNumber);
              return la.compareTo(lb);
            });

          seriesList.add(GraphSeries(
            name: '$teamNum',
            x: teamEntries.asMap().entries.map((e) => _matchLabel(e.value.matchKey, e.value.matchNumber, e.key)).toList(),
            y: teamEntries.map((e) => _metricValue(e, metric)).toList(),
          ));
        }
        setState(() {
          _lineSeries = seriesList;
          _barPoints = [];
          _graphGenerated = true;
        });
      }
    }
  }

  /// Returns a human-readable match label, e.g. "QM 5", "SF 1M1", "PM 3", "F 1M2"
  /// Mirrors the web graphs.js label format.
  String _matchLabel(String? matchKey, int? matchNumber, int fallbackIndex) {
    if (matchKey != null && matchKey.contains('_')) {
      final part = matchKey.split('_').last.toLowerCase();
      // Capture leading letters as level, rest as the numeric/set portion
      // e.g. 'qm5' → level='qm', rest='5'
      //      'sf1m1' → level='sf', rest='1m1'
      //      'f1m2'  → level='f',  rest='1m2'
      final match = RegExp(r'^([a-z]+)(.+)$').firstMatch(part);
      if (match != null) {
        final levelStr = match.group(1)!;
        final rest = match.group(2)!;
        final abbrev = _levelAbbrev(levelStr);
        // Playoff matches contain 'm' separator: sf1m1 → 'SF 1M1'
        if (rest.contains('m')) {
          final mIdx = rest.indexOf('m');
          final setNum = rest.substring(0, mIdx);
          final matchNum = rest.substring(mIdx + 1);
          return '$abbrev ${setNum}M$matchNum';
        }
        return '$abbrev $rest';
      }
    }
    // Fallback: use matchNumber
    return 'QM ${matchNumber ?? fallbackIndex + 1}';
  }

  String _levelAbbrev(String level) {
    switch (level) {
      case 'qm': return 'QM';
      case 'pm': return 'PM';
      case 'sf': return 'SF';
      case 'f': return 'F';
      case 'ef': return 'EF';
      default: return level.toUpperCase();
    }
  }

  /// Returns an integer sort key that orders matches by comp level then number.
  /// PM < QM < EF < SF < F, matching competition flow.
  int _matchSortKey(String? matchKey, int? matchNumber) {
    const levelOrder = {'pm': 0, 'qm': 1, 'ef': 2, 'sf': 3, 'f': 4};
    int levelPriority = 1; // default: QM
    int numericPart = matchNumber ?? 0;

    if (matchKey != null && matchKey.contains('_')) {
      final part = matchKey.split('_').last.toLowerCase();
      final levelStr = part.replaceAll(RegExp(r'[0-9m]'), '');
      levelPriority = levelOrder[levelStr] ?? 1;
      final numStr = part.replaceAll(RegExp(r'[^0-9]'), '');
      numericPart = int.tryParse(numStr) ?? numericPart;
    }
    // Encode as a single comparable int: level * 10000 + matchNum
    return levelPriority * 10000 + numericPart;
  }

  List<(int, double)> _buildTeamStats(List<ScoutingEntryModel> entries, GraphMetric metric) {
    final map = <int, List<double>>{};
    for (final entry in entries) {
      final team = entry.targetTeamNumber;
      if (team == null) continue;
      map.putIfAbsent(team, () => []).add(_metricValue(entry, metric));
    }
    return map.entries.map((e) {
      final avg = metric.kind == 'count' ? e.value.length.toDouble() : (e.value.isEmpty ? 0.0 : e.value.reduce((a, b) => a + b) / e.value.length);
      return (e.key, avg);
    }).toList();
  }

  List<(int, double)> _sortStats(List<(int, double)> stats) {
    final copy = List<(int, double)>.from(stats);
    switch (_sort) {
      case 'team_asc': copy.sort((a, b) => a.$1.compareTo(b.$1));
      case 'team_desc': copy.sort((a, b) => b.$1.compareTo(a.$1));
      case 'value_asc': copy.sort((a, b) => a.$2.compareTo(b.$2));
      default: copy.sort((a, b) => b.$2.compareTo(a.$2));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
    }

    final filteredTeams = _teams.where((t) {
      final q = _teamSearch.toLowerCase();
      return q.isEmpty || t.displayName.toLowerCase().contains(q) || t.teamNumber.toString().contains(q);
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === Summary Stats ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('dashboard.data_summary').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statChip(context.tr('dashboard.entries'), '$_totalEntries', Icons.description_rounded),
                    _statChip(context.tr('dashboard.teams'), '$_totalTeams', Icons.group_rounded),
                    _statChip(context.tr('dashboard.matches'), '$_totalMatches', Icons.sports_esports_rounded),
                    _statChip(context.tr('dashboard.events'), '$_totalEvents', Icons.event_rounded),
                  ],
                ),
              ],
            ),
          ),

          // === Metric Selection ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('rankings.metric').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                DropdownButtonFormField<GraphMetric>(
                  isExpanded: true,
                  initialValue: _selectedMetric,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    labelText: context.tr('rankings.metric'),
                    labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                    prefixIcon: const Icon(Icons.assessment_rounded, color: ObsidianUITheme.primaryAccent),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  items: _metrics.map((m) => DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (m) => setState(() => _selectedMetric = m),
                ),
              ],
            ),
          ),

          // === Graph Type ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('graphs.title').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                _buildGraphTypeRow(),
                const SizedBox(height: 10),
                if (_graphType != 'bar') ...[
                  Text(context.tr('graphs.distribution'), style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'averages', label: Text('Averages')),
                      ButtonSegment(value: 'matches', label: Text('Per Match')),
                    ],
                    selected: {_dataView},
                    onSelectionChanged: (s) => setState(() => _dataView = s.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return ObsidianUITheme.primaryAccent;
                        return ObsidianUITheme.getSurfaceColor(context);
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(context.tr('rankings.sort'), style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _sort,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'value_desc', child: Text('Value: High → Low', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'value_asc', child: Text('Value: Low → High', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'team_asc', child: Text('Team: Ascending', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'team_desc', child: Text('Team: Descending', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'value_desc'),
                ),
              ],
            ),
          ),

          // === Team Selection ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('scout.select_team').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.warningOrange, letterSpacing: 1.0)),
                    Text(context.tr('graphs.selected_count', {'count': '${_selectedTeams.length}'}), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                // Quick actions
                Wrap(
                  spacing: 8,
                  children: [
                    _quickChip(context.tr('graphs.select_all'), Icons.select_all_rounded, () {
                      setState(() => _selectedTeams = _teams.map((t) => t.teamNumber).toSet());
                    }),
                    _quickChip(context.tr('graphs.select_top'), Icons.emoji_events_rounded, () {
                      _selectTopN(8);
                    }),
                    _quickChip(context.tr('graphs.clear_all'), Icons.clear_all_rounded, () {
                      setState(() => _selectedTeams.clear());
                    }),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setState(() => _teamSearch = v),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    hintText: context.tr('scout.search_teams'),
                    hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)),
                    prefixIcon: Icon(Icons.search_rounded, color: ObsidianUITheme.getFaintTextColor(context)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                // Team list (scrollable)
                SizedBox(
                  height: 200,
                  child: filteredTeams.isEmpty
                      ? Center(child: Text(context.tr('errors.no_teams_found'), style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context))))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          itemCount: filteredTeams.length,
                          itemBuilder: (ctx, i) {
                            final team = filteredTeams[i];
                            final selected = _selectedTeams.contains(team.teamNumber);
                            final hasScouting = _entries.any((e) => e.targetTeamNumber == team.teamNumber);
                            return CheckboxListTile(
                              dense: true,
                              value: selected,
                              activeColor: ObsidianUITheme.primaryAccent,
                              title: Text(team.displayName, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13)),
                              subtitle: Text(hasScouting ? 'Scouted' : 'Not scouted', style: TextStyle(fontSize: 11, color: hasScouting ? ObsidianUITheme.successGreen : ObsidianUITheme.getFaintTextColor(context))),
                              onChanged: (_) {
                                setState(() {
                                  if (selected) {
                                    _selectedTeams.remove(team.teamNumber);
                                  } else {
                                    _selectedTeams.add(team.teamNumber);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // === Generate Button ===
          ObsidianGlassCard(
            onTap: _generateGraph,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bar_chart_rounded, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 10),
                  Text('GENERATE GRAPHS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: ObsidianUITheme.getPrimaryTextColor(context))),
                ],
              ),
            ),
          ),

          // === Graph Output ===
          if (_graphGenerated) _buildGraphOutput(),
        ],
      ),
    );
  }

  Widget _buildGraphOutput() {
    final metric = _selectedMetric;
    if (metric == null) return const SizedBox.shrink();

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${metric.label} — ${_graphType.toUpperCase()}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.getPrimaryTextColor(context)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                onPressed: _generateGraph,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_graphType == 'bar') _buildBarChart() else _buildLineChart(),
          const SizedBox(height: 8),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    if (_barPoints.isEmpty) {
      return const Text('No data', style: TextStyle(color: Colors.white38));
    }

    final maxVal = _barPoints.map((p) => p.value).reduce(max);
    final palette = _chartPalette();

    return SizedBox(
      height: max(220.0, _barPoints.length * 32.0).clamp(0.0, 500.0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.15,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = _barPoints[groupIndex].label;
                return BarTooltipItem(
                  '$label\n',
                  TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                  children: [
                    TextSpan(
                      text: rod.toY.toStringAsFixed(rod.toY == rod.toY.truncate() ? 0 : 2),
                      style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text(
                  value == value.truncate() ? value.toInt().toString() : value.toStringAsFixed(1),
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _barPoints.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_barPoints[idx].label, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 10), overflow: TextOverflow.ellipsis),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(_barPoints.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _barPoints[i].value,
                  gradient: LinearGradient(
                    colors: [palette[i % palette.length].withValues(alpha: 0.9), ObsidianUITheme.secondaryAccent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: max(8.0, min(28.0, 280.0 / _barPoints.length)),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }

  Widget _buildLineChart() {
    if (_lineSeries.isEmpty) {
      return Text('No data', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)));
    }

    final palette = _chartPalette();
    final allY = _lineSeries.expand((s) => s.y).toList();
    if (allY.isEmpty) return Text('No data', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)));

    final maxY = allY.reduce(max) * 1.15;

    // Build a unified x-axis
    // Sort x-axis: by comp level priority (PM < QM < EF < SF < F) then match number
    const levelOrder = {'PM': 0, 'QM': 1, 'EF': 2, 'SF': 3, 'F': 4};
    int labelSortKey(String label) {
      final levelStr = label.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
      final numStr = label.replaceAll(RegExp(r'[^0-9]'), '');
      final levelPri = levelOrder[levelStr] ?? 1;
      final num = int.tryParse(numStr) ?? 0;
      return levelPri * 10000 + num;
    }
    final allX = _lineSeries.expand((s) => s.x).toSet().toList()
      ..sort((a, b) => labelSortKey(a).compareTo(labelSortKey(b)));


    final lineBarsData = _lineSeries.asMap().entries.map((entry) {
      final i = entry.key;
      final series = entry.value;
      final color = palette[i % palette.length];

      final spots = List.generate(series.x.length, (j) {
        final xIdx = allX.indexOf(series.x[j]).toDouble();
        return FlSpot(xIdx < 0 ? j.toDouble() : xIdx, series.y[j]);
      });

      return LineChartBarData(
        spots: spots,
        isCurved: _graphType == 'line' || _graphType == 'area',
        color: color,
        barWidth: 2.2,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 4,
            color: color,
            strokeWidth: 2,
            strokeColor: ObsidianUITheme.getSurfaceColor(context),
          ),
        ),
        belowBarData: _graphType == 'area'
            ? BarAreaData(show: true, color: color.withValues(alpha: 0.15))
            : BarAreaData(show: false),
      );
    }).toList();

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItems: (spots) => spots.map((s) {
                final seriesName = _lineSeries.length > s.barIndex ? _lineSeries[s.barIndex].name : '';
                return LineTooltipItem(
                  '$seriesName: ${s.y.toStringAsFixed(s.y == s.y.truncate() ? 0 : 2)}',
                  TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                );
              }).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text(
                  value == value.truncate() ? value.toInt().toString() : value.toStringAsFixed(1),
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  // Only render label at exact integer positions to avoid duplicates
                  if (value != value.roundToDouble()) return const SizedBox.shrink();
                  final idx = value.toInt();
                  if (idx < 0 || idx >= allX.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(allX[idx], style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 10)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 1),
            getDrawingVerticalLine: (_) => FlLine(color: ObsidianUITheme.getBorderColor(context).withValues(alpha: 0.5), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: lineBarsData,
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }

  Widget _buildLegend() {
    final palette = _chartPalette();
    final items = _graphType == 'bar'
        ? _barPoints.asMap().entries.map((e) => (e.value.label, palette[e.key % palette.length])).toList()
        : _lineSeries.asMap().entries.map((e) => (e.value.name, palette[e.key % palette.length])).toList();

    if (items.length <= 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: item.$2, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(item.$1, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildGraphTypeRow() {
    const types = [
      ('bar', Icons.bar_chart_rounded, 'Bar'),
      ('line', Icons.show_chart_rounded, 'Line'),
      ('scatter', Icons.scatter_plot_rounded, 'Scatter'),
      ('area', Icons.area_chart_rounded, 'Area'),
    ];
    final unselectedColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Wrap(
      spacing: 8,
      children: types.map((t) {
        final selected = _graphType == t.$1;
        return GestureDetector(
          onTap: () => setState(() {
            _graphType = t.$1;
            _graphGenerated = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: selected ? const LinearGradient(colors: [ObsidianUITheme.primaryAccent, ObsidianUITheme.secondaryAccent]) : null,
              border: Border.all(color: selected ? Colors.transparent : borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.$2, size: 16, color: selected ? Colors.white : unselectedColor),
                const SizedBox(width: 6),
                Text(t.$3, style: TextStyle(fontSize: 13, color: selected ? Colors.white : unselectedColor, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: ObsidianUITheme.primaryAccent),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
          Text(label, style: TextStyle(fontSize: 10, color: ObsidianUITheme.getSecondaryTextColor(context), letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _quickChip(String label, IconData icon, VoidCallback onTap) {
    final chipTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    return ActionChip(
      avatar: Icon(icon, size: 14, color: chipTextColor),
      label: Text(label, style: TextStyle(color: chipTextColor, fontSize: 12)),
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
      onPressed: onTap,
    );
  }

  void _selectTopN(int n) {
    if (_selectedMetric == null) return;
    final metric = _selectedMetric!;
    final eventEntries = _entries.where((e) => _eventKey == null || _eventKey!.isEmpty || e.eventKey == _eventKey).toList();
    final stats = _buildTeamStats(eventEntries, metric);
    final sorted = _sortStats(stats);
    setState(() {
      _selectedTeams = sorted.take(n).map((s) => s.$1).toSet();
    });
  }

  List<Color> _chartPalette() => const [
    ObsidianUITheme.primaryAccent,
    ObsidianUITheme.secondaryAccent,
    ObsidianUITheme.successGreen,
    ObsidianUITheme.warningOrange,
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF59E0B), // Amber
  ];
}
