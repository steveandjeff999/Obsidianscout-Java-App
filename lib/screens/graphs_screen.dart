import 'dart:async';
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
import '../widgets/obsidian_chart_interactive_wrapper.dart';

// Reserved fields that are metadata, not graphable
const _reserved = {'eventKey', 'matchKey', 'matchNumber', 'targetTeamNumber'};

int _parseTeamNumber(String name) {
  final trimmed = name.trim();
  // If it's explicitly a match label (e.g. "M1", "M12", "Match 5", "Match 1 (event)"), it is NOT a team
  if (RegExp(r'^M\d+(\s*\(.*\))?$', caseSensitive: false).hasMatch(trimmed) ||
      RegExp(r'^Match\s*\d+(\s*\(.*\))?$', caseSensitive: false).hasMatch(trimmed)) {
    return 0;
  }

  // If starts with "Team " (e.g. "Team 254")
  if (RegExp(r'^team\s*\d+', caseSensitive: false).hasMatch(trimmed)) {
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

class GraphTypeInfo {
  final String id;
  final String label;
  final IconData icon;
  final String group; // "basic" or "distribution"

  const GraphTypeInfo(this.id, this.label, this.icon, {this.group = 'basic'});
}

const List<GraphTypeInfo> kGraphTypes = [
  GraphTypeInfo('bar', 'Bar', Icons.bar_chart_rounded),
  GraphTypeInfo('line', 'Line', Icons.show_chart_rounded),
  GraphTypeInfo('scatter', 'Scatter', Icons.scatter_plot_rounded),
  GraphTypeInfo('area', 'Area', Icons.area_chart_rounded),
  GraphTypeInfo('box', 'Box', Icons.candlestick_chart_rounded, group: 'distribution'),
  GraphTypeInfo('violin', 'Violin', Icons.graphic_eq_rounded, group: 'distribution'),
  GraphTypeInfo('histogram', 'Histogram', Icons.analytics_rounded, group: 'distribution'),
];

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
  AppSettingsModel? _settings;
  String? _eventKey;
  List<EventModel> _events = [];
  ScoutingConfigModel? _config;
  List<ScoutingEntryModel> _entries = [];
  List<TeamModel> _teams = [];
  Map<int, TeamModel> _teamMap = {};

  // State - mirrors web page
  List<GraphMetric> _metrics = [];
  GraphMetric? _selectedMetric;
  Set<int> _selectedTeams = {};
  Set<String> _selectedGraphTypes = {'bar'};
  String _datasource = 'scouted'; // scouted, epa, opr, all
  String _dataView = 'averages'; // averages, matches
  String _sort = 'value_desc'; // value_desc, value_asc, team_asc, team_desc
  bool _forcePrescout = false;
  String _teamSearch = '';
  bool _graphGenerated = false;

  // Interactive Graph Controls
  bool _showDataLabels = false;
  bool _showBenchmark = false;
  final Set<String> _hiddenSeries = {};
  int? _hoveredSeriesIndex;

  // Summary stats
  int _totalEntries = 0;
  int _totalTeams = 0;
  int _totalEvents = 0;
  int _totalMatches = 0;

  final ScrollController _scrollController = ScrollController();

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Hydration
    final cachedSettings = await widget.apiService.getCachedSettings();
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    final cachedConfig = await widget.apiService.getCachedMatchConfig();
    final cachedEntriesRaw = await widget.apiService.getCachedScoutingEntries();
    final cachedEvents = await widget.apiService.getCachedEvents(year: cachedSettings?.year);
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);

    if (mounted && (cachedEntriesRaw.isNotEmpty || cachedTeams.isNotEmpty || cachedConfig != null)) {
      final entries = cachedEntriesRaw
          .map((e) => ScoutingEntryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final metrics = _buildMetrics(cachedConfig);
      final teamSet = entries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
      final matchSet = entries.map((e) => e.matchKey).whereType<String>().toSet();
      final eventSet = entries.map((e) => e.eventKey).whereType<String>().toSet();
      final teamMap = <int, TeamModel>{};
      for (final t in cachedTeams) {
        teamMap[t.teamNumber] = t;
      }

      setState(() {
        _settings = cachedSettings;
        _events = cachedEvents;
        _eventKey = (cachedEventKey != null && cachedEventKey.isNotEmpty) ? cachedEventKey : (cachedSettings?.eventKey ?? '');
        _config = cachedConfig;
        _entries = entries;
        _teams = cachedTeams;
        _teamMap = teamMap;
        _metrics = metrics;
        if (_selectedMetric == null && metrics.isNotEmpty) _selectedMetric = metrics.first;
        if (_selectedTeams.isEmpty) {
          if (cachedTeams.isNotEmpty) {
            _selectedTeams = cachedTeams.map((t) => t.teamNumber).toSet();
          } else if (teamSet.isNotEmpty) {
            _selectedTeams = teamSet;
          }
        }
        _totalEntries = entries.length;
        _totalTeams = teamSet.length;
        _totalMatches = matchSet.length;
        _totalEvents = eventSet.length;
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation
    try {
      final results = await Future.wait([
        widget.apiService.fetchSettings(),
        widget.apiService.fetchCurrentEventKey(),
        widget.apiService.fetchMatchConfig(),
        widget.apiService.fetchScoutingEntries(),
      ]);

      final settings = results[0] as AppSettingsModel?;
      final eventKey = results[1] as String?;
      final config = results[2] as ScoutingConfigModel?;
      final rawEntries = results[3] as List<dynamic>;

      final eventsAndTeams = await Future.wait([
        widget.apiService.fetchEvents(year: settings?.year),
        widget.apiService.fetchTeams(eventKey),
      ]);

      final events = eventsAndTeams[0] as List<EventModel>;
      final teams = eventsAndTeams[1] as List<TeamModel>;

      final entries = rawEntries
          .map((e) => ScoutingEntryModel.fromJson(e as Map<String, dynamic>))
          .toList();

      // Build metrics list from config matching web graphs.js
      final metrics = _buildMetrics(config);

      // Summary stats
      final teamSet = entries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
      final matchSet = entries.map((e) => e.matchKey).whereType<String>().toSet();
      final eventSet = entries.map((e) => e.eventKey).whereType<String>().toSet();

      final teamMap = <int, TeamModel>{};
      for (final t in teams) {
        teamMap[t.teamNumber] = t;
      }

      if (!mounted) return;

      setState(() {
        _settings = settings;
        _events = events;
        _eventKey = (eventKey != null && eventKey.isNotEmpty) ? eventKey : (settings?.eventKey ?? '');
        _config = config;
        _entries = entries;
        _teams = teams;
        _teamMap = teamMap;
        _metrics = metrics;
        if (_selectedMetric == null || !metrics.any((m) => m.id == _selectedMetric?.id)) {
          _selectedMetric = metrics.isNotEmpty ? metrics.first : null;
        }
        if (_selectedTeams.isEmpty) {
          if (teams.isNotEmpty) {
            _selectedTeams = teams.map((t) => t.teamNumber).toSet();
          } else if (teamSet.isNotEmpty) {
            _selectedTeams = teamSet;
          }
        }
        _totalEntries = entries.length;
        _totalTeams = teamSet.length;
        _totalMatches = matchSet.length;
        _totalEvents = eventSet.length;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _onEventChanged(String? newEventKey) async {
    final effectiveKey = newEventKey ?? '';
    setState(() {
      _eventKey = effectiveKey;
      _isLoading = true;
    });

    final teams = await widget.apiService.fetchTeams(effectiveKey.isNotEmpty ? effectiveKey : null);
    final teamMap = <int, TeamModel>{};
    for (final t in teams) {
      teamMap[t.teamNumber] = t;
    }

    if (!mounted) return;

    setState(() {
      _teams = teams;
      _teamMap = teamMap;
      // Retain selected teams that exist in the new event (if event is filtered)
      if (effectiveKey.isNotEmpty && teams.isNotEmpty) {
        final validNums = teams.map((t) => t.teamNumber).toSet();
        _selectedTeams = _selectedTeams.intersection(validNums);
      }
      _isLoading = false;
    });
  }

  List<GraphMetric> _buildMetrics([ScoutingConfigModel? overrideConfig]) {
    final config = overrideConfig ?? _config;
    final metrics = <GraphMetric>[
      const GraphMetric(id: 'score_total', label: 'Total points', kind: 'score', scope: 'total'),
      const GraphMetric(id: 'score_auto', label: 'Auto points', kind: 'score', scope: 'auto'),
      const GraphMetric(id: 'score_teleop', label: 'Teleop points', kind: 'score', scope: 'teleop'),
      const GraphMetric(id: 'score_endgame', label: 'Endgame points', kind: 'score', scope: 'endgame'),
      const GraphMetric(id: 'count', label: 'Entry count', kind: 'count'),
    ];

    for (final field in config?.fields ?? []) {
      if (_reserved.contains(field.id) || field.type.toLowerCase() == 'section') continue;
      final type = field.type.toLowerCase();
      final label = field.label.isNotEmpty ? field.label : field.id;

      if (type == 'number' || type == 'counter' || type == 'rating' || type == 'slider') {
        metrics.add(GraphMetric(
          id: 'field:${field.id}',
          label: label,
          kind: 'numeric',
          fieldId: field.id,
          field: field,
        ));
      } else if (type == 'select' || type == 'checkbox' || type == 'toggle' || type == 'radio' || type == 'boolean') {
        metrics.add(GraphMetric(
          id: 'category:${field.id}',
          label: label,
          kind: 'category',
          fieldId: field.id,
          field: field,
        ));
      }
    }
    return metrics;
  }

  double _fieldPoints(ScoutingFieldModel field, dynamic value) {
    if (value == null) return 0.0;
    final type = field.type.toLowerCase();
    final pointsPer = field.pointsPer ?? 0.0;

    if (type == 'counter' || type == 'number' || type == 'rating' || type == 'slider') {
      double numVal = 0.0;
      if (value is num) {
        numVal = value.toDouble();
      } else if (value is String) {
        numVal = double.tryParse(value) ?? 0.0;
      }
      return numVal * pointsPer;
    }

    if (type == 'checkbox' || type == 'toggle' || type == 'boolean') {
      bool enabled = false;
      if (value is bool) {
        enabled = value;
      } else if (value is String) {
        enabled = value.toLowerCase() == 'true';
      }
      return enabled ? pointsPer : 0.0;
    }

    if (type == 'select' || type == 'radio') {
      final label = value.toString();
      final opt = field.options.firstWhere(
        (o) => o.value == label || o.label == label,
        orElse: () => ScoutingOptionModel(label: '', value: '', points: 0.0),
      );
      return opt.points;
    }

    return 0.0;
  }

  double _entryScore(ScoutingConfigModel? config, ScoutingEntryModel entry, [String? scope]) {
    if (config == null || config.fields.isEmpty) return 0.0;
    double total = 0.0;
    for (final field in config.fields) {
      if (_reserved.contains(field.id) || field.type.toLowerCase() == 'section') continue;
      if (scope != null && scope != 'total') {
        final phase = field.phase?.toLowerCase() ?? '';
        if (phase != scope.toLowerCase()) continue;
      }
      total += _fieldPoints(field, entry.data[field.id]);
    }
    return total;
  }

  double? _metricValue(ScoutingEntryModel entry, GraphMetric metric) {
    if (metric.kind == 'count') return 1.0;
    if (metric.kind == 'score') return _entryScore(_config, entry, metric.scope);
    if (metric.kind == 'numeric' && metric.fieldId != null) {
      final raw = entry.data[metric.fieldId!];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }
    return null;
  }

  List<ScoutingEntryModel> _getFilteredEntriesForTeams() {
    final selectedTeams = _selectedTeams.toList();
    final result = <ScoutingEntryModel>[];

    for (final teamNum in selectedTeams) {
      final currentEventEntries = _entries.where((entry) {
        if (entry.targetTeamNumber != teamNum) return false;
        if (entry.isPrescout) return false;
        if (_eventKey == null || _eventKey!.isEmpty) return true;
        final entryKey = entry.eventKey?.trim().toLowerCase() ?? '';
        final targetKey = _eventKey!.trim().toLowerCase();
        return entryKey == targetKey ||
            entryKey.replaceAll(RegExp(r'^[0-9]+'), '') == targetKey.replaceAll(RegExp(r'^[0-9]+'), '');
      }).toList();

      final prescoutEntries = _entries.where((entry) =>
          entry.targetTeamNumber == teamNum &&
          entry.isPrescout).toList();

      if (_forcePrescout || currentEventEntries.length < 3) {
        result.addAll(currentEventEntries);
        result.addAll(prescoutEntries);
      } else {
        result.addAll(currentEventEntries);
      }

      // Fallback: if no entries matched for this event, grab all entries for this team
      if (result.where((e) => e.targetTeamNumber == teamNum).isEmpty) {
        final anyEntries = _entries.where((entry) => entry.targetTeamNumber == teamNum).toList();
        result.addAll(anyEntries);
      }
    }
    return result;
  }

  List<ScoutingEntryModel> _getFilteredEntriesForEvent() {
    if (_eventKey == null || _eventKey!.isEmpty) return _entries;
    final teamNums = _entries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
    final result = <ScoutingEntryModel>[];

    for (final teamNum in teamNums) {
      final currentEventEntries = _entries.where((entry) {
        if (entry.targetTeamNumber != teamNum) return false;
        if (entry.isPrescout) return false;
        final entryKey = entry.eventKey?.trim().toLowerCase() ?? '';
        final targetKey = _eventKey!.trim().toLowerCase();
        return entryKey == targetKey ||
            entryKey.replaceAll(RegExp(r'^[0-9]+'), '') == targetKey.replaceAll(RegExp(r'^[0-9]+'), '');
      }).toList();

      final prescoutEntries = _entries.where((entry) =>
          entry.targetTeamNumber == teamNum &&
          entry.isPrescout).toList();

      if (_forcePrescout || currentEventEntries.length < 3) {
        result.addAll(currentEventEntries);
        result.addAll(prescoutEntries);
      } else {
        result.addAll(currentEventEntries);
      }

      if (result.where((e) => e.targetTeamNumber == teamNum).isEmpty) {
        final anyEntries = _entries.where((entry) => entry.targetTeamNumber == teamNum).toList();
        result.addAll(anyEntries);
      }
    }
    return result;
  }

  List<(int, double)> _buildTeamStats(List<ScoutingEntryModel> entries, GraphMetric metric) {
    final map = <int, List<double>>{};
    for (final entry in entries) {
      final team = entry.targetTeamNumber;
      if (team == null) continue;
      final val = _metricValue(entry, metric);
      if (val == null) continue;
      map.putIfAbsent(team, () => []).add(val);
    }
    return map.entries.map((e) {
      final avg = metric.kind == 'count'
          ? e.value.length.toDouble()
          : (e.value.isEmpty ? 0.0 : e.value.reduce((a, b) => a + b) / e.value.length);
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

  List<GraphPoint> _buildCategoryCounts(List<ScoutingEntryModel> entries, GraphMetric metric) {
    if (metric.fieldId == null) return [];
    final counts = <String, int>{};
    for (final entry in entries) {
      final raw = entry.data[metric.fieldId!];
      if (raw == null) continue;
      final label = raw.toString();
      if (label.isEmpty) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => GraphPoint(e.key, e.value.toDouble())).toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  List<GraphSeries> _buildTeamSeries(List<ScoutingEntryModel> entries, GraphMetric metric) {
    if (_dataView == 'averages') {
      final stats = _sortStats(_buildTeamStats(entries, metric));
      return [
        GraphSeries(
          name: metric.label,
          x: stats.map((item) => 'Team ${item.$1}').toList(),
          y: stats.map((item) => item.$2).toList(),
        )
      ];
    }

    final groups = <int, List<ScoutingEntryModel>>{};
    for (final entry in entries) {
      final team = entry.targetTeamNumber;
      if (team == null) continue;
      groups.putIfAbsent(team, () => []).add(entry);
    }

    final seriesList = <GraphSeries>[];
    groups.forEach((teamNum, teamEntries) {
      final validEntries = teamEntries
          .where((e) => _metricValue(e, metric) != null)
          .toList()
        ..sort((a, b) {
          if (a.matchPlayedTime != null && b.matchPlayedTime != null) {
            return a.matchPlayedTime!.compareTo(b.matchPlayedTime!);
          }
          final aEvent = a.eventKey ?? '';
          final bEvent = b.eventKey ?? '';
          if (aEvent != bEvent) return aEvent.compareTo(bEvent);
          return _matchSortKey(a.matchKey, a.matchNumber).compareTo(_matchSortKey(b.matchKey, b.matchNumber));
        });

      seriesList.add(GraphSeries(
        name: 'Team $teamNum',
        x: validEntries.asMap().entries.map((e) {
          final entry = e.value;
          final matchLabel = _matchLabel(entry.matchKey, entry.matchNumber, e.key);
          final eventLabel = entry.isPrescout ? (entry.eventKey ?? 'Prescout') : '';
          return eventLabel.isNotEmpty ? '$matchLabel ($eventLabel)' : matchLabel;
        }).toList(),
        y: validEntries.map((e) => _metricValue(e, metric) ?? 0.0).toList(),
      ));
    });

    return seriesList;
  }

  String _matchLabel(String? matchKey, int? matchNumber, int fallbackIndex) {
    if (matchKey != null && matchKey.contains('_')) {
      final part = matchKey.split('_').last.toLowerCase();
      final match = RegExp(r'^([a-z]+)(.+)$').firstMatch(part);
      if (match != null) {
        final levelStr = match.group(1)!;
        final rest = match.group(2)!;
        final abbrev = _levelAbbrev(levelStr);
        if (rest.contains('m')) {
          final mIdx = rest.indexOf('m');
          final setNum = rest.substring(0, mIdx);
          final matchNum = rest.substring(mIdx + 1);
          return '$abbrev ${setNum}M$matchNum';
        }
        return '$abbrev $rest';
      }
    }
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

  int _matchSortKey(String? matchKey, int? matchNumber) {
    const levelOrder = {'pm': 0, 'qm': 1, 'ef': 2, 'sf': 3, 'f': 4};
    int levelPriority = 1;
    int numericPart = matchNumber ?? 0;

    if (matchKey != null && matchKey.contains('_')) {
      final part = matchKey.split('_').last.toLowerCase();
      final levelStr = part.replaceAll(RegExp(r'[0-9m]'), '');
      levelPriority = levelOrder[levelStr] ?? 1;
      final numStr = part.replaceAll(RegExp(r'[^0-9]'), '');
      numericPart = int.tryParse(numStr) ?? numericPart;
    }
    return levelPriority * 10000 + numericPart;
  }

  List<DistributionStats> _buildDistributionStats(List<ScoutingEntryModel> entries, GraphMetric metric) {
    final valuesByTeam = <int, List<double>>{};
    for (final entry in entries) {
      final team = entry.targetTeamNumber;
      if (team == null) continue;
      final val = _metricValue(entry, metric);
      if (val == null) continue;
      valuesByTeam.putIfAbsent(team, () => []).add(val);
    }

    if (valuesByTeam.isEmpty) return [];

    // Always compute individual distribution stats per team
    final stats = valuesByTeam.entries.map((e) {
      return DistributionStats.fromValues('Team ${e.key}', e.value);
    }).toList();

    // Sort teams based on active sort setting
    if (_sort == 'team_asc') {
      stats.sort((a, b) => _extractTeamNum(a.name).compareTo(_extractTeamNum(b.name)));
    } else if (_sort == 'team_desc') {
      stats.sort((a, b) => _extractTeamNum(b.name).compareTo(_extractTeamNum(a.name)));
    } else if (_sort == 'value_asc') {
      stats.sort((a, b) => a.median.compareTo(b.median));
    } else {
      // value_desc default
      stats.sort((a, b) => b.median.compareTo(a.median));
    }

    return stats;
  }

  int _extractTeamNum(String name) {
    final numVal = _parseTeamNumber(name);
    if (numVal > 0) {
      if (_teamMap.containsKey(numVal) || _selectedTeams.contains(numVal)) {
        return numVal;
      }
      if (_teams.isEmpty) return numVal;
    }
    return 0;
  }

  String _resolveTeamLabel({required String seriesName, required String xLabel}) {
    if (seriesName.toLowerCase().startsWith('team ') || RegExp(r'^team\s*\d+', caseSensitive: false).hasMatch(seriesName)) {
      return seriesName;
    }
    if (xLabel.toLowerCase().startsWith('team ') || RegExp(r'^team\s*\d+', caseSensitive: false).hasMatch(xLabel)) {
      return xLabel;
    }
    final sNum = _extractTeamNum(seriesName);
    if (sNum > 0) return 'Team $sNum';
    final xNum = _extractTeamNum(xLabel);
    if (xNum > 0) return 'Team $xNum';
    return seriesName.isNotEmpty ? seriesName : xLabel;
  }

  List<HistogramBin> _buildHistogramBins(List<ScoutingEntryModel> entries, GraphMetric metric) {
    final values = entries.map((e) => _metricValue(e, metric)).whereType<double>().toList();
    if (values.isEmpty) return [];

    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);

    if (minVal == maxVal) {
      return [
        HistogramBin(
          rangeLabel: minVal.toStringAsFixed(1),
          start: minVal,
          end: maxVal,
          count: values.length,
        )
      ];
    }

    const binCount = 6;
    final binWidth = (maxVal - minVal) / binCount;
    final bins = List.generate(binCount, (i) {
      final start = minVal + i * binWidth;
      final end = start + binWidth;
      final count = values.where((v) => i == binCount - 1 ? (v >= start && v <= end) : (v >= start && v < end)).length;
      final label = '${start.toStringAsFixed(1)}-${end.toStringAsFixed(1)}';
      return HistogramBin(rangeLabel: label, start: start, end: end, count: count);
    });

    return bins;
  }

  void _generateGraphs() {
    if (_selectedTeams.isEmpty) {
      if (_teams.isNotEmpty) {
        _selectedTeams = _teams.map((t) => t.teamNumber).toSet();
      } else if (_entries.isNotEmpty) {
        _selectedTeams = _entries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
      }
    }

    if (_selectedGraphTypes.isEmpty) {
      _selectedGraphTypes = {'bar'};
    }

    if (_datasource == 'scouted' && _selectedMetric == null && _metrics.isNotEmpty) {
      _selectedMetric = _metrics.first;
    }

    if (_selectedTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No teams available to generate graphs'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    setState(() {
      _graphGenerated = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generated ${_selectedGraphTypes.length} graph(s) for ${_selectedTeams.length} teams'),
        backgroundColor: ObsidianUITheme.primaryAccent,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _selectTopN(int n) {
    final metric = _selectedMetric;
    if (metric == null) return;
    final filteredEntries = _getFilteredEntriesForEvent();
    final teamStats = _buildTeamStats(filteredEntries, metric);
    final topTeams = teamStats
        .sortDescending((a, b) => a.$2.compareTo(b.$2))
        .take(n)
        .map((item) => item.$1)
        .toSet();
    setState(() => _selectedTeams = topTeams);
  }

  void _addEventTeams() {
    final filteredEntries = _getFilteredEntriesForEvent();
    final teams = filteredEntries.map((e) => e.targetTeamNumber).whereType<int>().toSet();
    setState(() => _selectedTeams.addAll(teams));
  }

  String _getDatasourceLabel(String ds) {
    switch (ds) {
      case 'epa': return 'Statbotics EPA';
      case 'opr': return 'TBA OPR';
      case 'all': return 'All Three';
      default: return 'Scouted Data';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
    }

    final filteredTeams = _teams.where((t) {
      final q = _teamSearch.toLowerCase().trim();
      return q.isEmpty || t.displayName.toLowerCase().contains(q) || t.teamNumber.toString().contains(q);
    }).toList();

    final hasStatbotics = _settings?.useStatboticsEpa == true;
    final hasTbaOpr = _settings?.useTbaOpr == true;
    final showDatasource = hasStatbotics || hasTbaOpr;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === Summary Stats ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('dashboard.data_summary').toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0)),
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

          // === Team Selection Panel ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('graphs.team_selection').toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.warningOrange, letterSpacing: 1.0)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _selectedTeams.isNotEmpty ? '${_selectedTeams.length} selected' : 'No teams selected',
                        style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Event filter
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _eventKey ?? '',
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    labelText: context.tr('graphs.event_filter'),
                    labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                    prefixIcon: const Icon(Icons.event_rounded, color: ObsidianUITheme.primaryAccent),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All events', overflow: TextOverflow.ellipsis)),
                    ..._events.map((e) => DropdownMenuItem(
                      value: e.eventKey,
                      child: Text('${e.name} (${e.year})', overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (k) => _onEventChanged(k),
                ),
                const SizedBox(height: 10),

                // Quick Action Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _quickChip(context.tr('graphs.select_all'), Icons.select_all_rounded, () {
                      setState(() => _selectedTeams = _teams.map((t) => t.teamNumber).toSet());
                    }),
                    _quickChip(context.tr('graphs.select_top'), Icons.emoji_events_rounded, () {
                      _selectTopN(8);
                    }),
                    _quickChip('Add event', Icons.playlist_add_rounded, _addEventTeams),
                    _quickChip(context.tr('graphs.clear_all'), Icons.clear_all_rounded, () {
                      setState(() => _selectedTeams.clear());
                    }),
                  ],
                ),
                const SizedBox(height: 10),

                // Selected team removable pills
                if (_selectedTeams.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (_selectedTeams.toList()..sort()).map((teamNum) {
                      return Chip(
                        label: Text('Team $teamNum', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                        side: const BorderSide(color: ObsidianUITheme.primaryAccent),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                        onDeleted: () {
                          setState(() => _selectedTeams.remove(teamNum));
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Search Box
                TextField(
                  onChanged: (v) => setState(() => _teamSearch = v),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    hintText: context.tr('graphs.placeholder_type_team_number'),
                    hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)),
                    prefixIcon: Icon(Icons.search_rounded, color: ObsidianUITheme.getFaintTextColor(context)),
                    suffixIcon: _teamSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _teamSearch = ''),
                          )
                        : null,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),

                // Team list
                SizedBox(
                  height: 200,
                  child: filteredTeams.isEmpty
                      ? Center(child: Text(context.tr('graphs.no_teams_found'), style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context))))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          itemCount: filteredTeams.length,
                          itemBuilder: (ctx, i) {
                            final team = filteredTeams[i];
                            final selected = _selectedTeams.contains(team.teamNumber);
                            final hasScouting = _entries.any((e) =>
                                e.targetTeamNumber == team.teamNumber &&
                                (_eventKey == null || _eventKey!.isEmpty || e.eventKey == _eventKey));
                            final nickname = team.nickname ?? team.name ?? '';

                            return CheckboxListTile(
                              dense: true,
                              value: selected,
                              activeColor: ObsidianUITheme.primaryAccent,
                              title: Text(
                                nickname.isNotEmpty ? 'Team ${team.teamNumber} - $nickname' : 'Team ${team.teamNumber}',
                                style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                              ),
                              subtitle: Text(
                                hasScouting ? 'Scouted' : 'Not scouted',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hasScouting ? ObsidianUITheme.successGreen : ObsidianUITheme.getFaintTextColor(context),
                                ),
                              ),
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
                const SizedBox(height: 6),
                Text(
                  '${_selectedTeams.length} teams selected from ${_teams.length} available',
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 11),
                ),
              ],
            ),
          ),

          // === Graph Options Panel ===
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('graphs.graph_options').toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.secondaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_selectedGraphTypes.length} selected',
                        style: const TextStyle(color: ObsidianUITheme.secondaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Datasource (Statbotics / TBA OPR / All)
                if (showDatasource) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _datasource,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('predictor.data_source'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: const Icon(Icons.storage_rounded, color: ObsidianUITheme.secondaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: [
                      if (hasStatbotics && hasTbaOpr)
                        const DropdownMenuItem(value: 'all', child: Text('All Three (Scouted, EPA, OPR)', overflow: TextOverflow.ellipsis)),
                      const DropdownMenuItem(value: 'scouted', child: Text('Scouted Data', overflow: TextOverflow.ellipsis)),
                      if (hasStatbotics)
                        const DropdownMenuItem(value: 'epa', child: Text('Statbotics EPA', overflow: TextOverflow.ellipsis)),
                      if (hasTbaOpr)
                        const DropdownMenuItem(value: 'opr', child: Text('TBA OPR', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _datasource = v ?? 'scouted'),
                  ),
                  const SizedBox(height: 12),
                ],

                // Metric dropdown (only for scouted data)
                if (_datasource == 'scouted') ...[
                  DropdownButtonFormField<GraphMetric>(
                    isExpanded: true,
                    value: _metrics.contains(_selectedMetric) ? _selectedMetric : (_metrics.isNotEmpty ? _metrics.first : null),
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('graphs.metric'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: const Icon(Icons.assessment_rounded, color: ObsidianUITheme.primaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _metrics.map((m) => DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (m) => setState(() => _selectedMetric = m),
                  ),
                  const SizedBox(height: 12),

                  // Data view segmented button
                  Text(context.tr('graphs.data_view'), style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'averages', label: Text(context.tr('graphs.team_averages'))),
                      ButtonSegment(value: 'matches', label: Text(context.tr('graphs.match_by_match'))),
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
                  const SizedBox(height: 12),
                ],

                // Sort teams dropdown
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _sort,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    labelText: context.tr('graphs.sort_teams'),
                    labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                    prefixIcon: const Icon(Icons.sort_rounded, color: ObsidianUITheme.secondaryAccent),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'value_desc', child: Text('Value: High → Low', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'value_asc', child: Text('Value: Low → High', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'team_asc', child: Text('Team #: Low → High', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'team_desc', child: Text('Team #: High → Low', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'value_desc'),
                ),
                const SizedBox(height: 12),

                // Force use prescout checkbox
                if (_datasource == 'scouted') ...[
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('graphs.force_use_prescout_data'),
                        style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13)),
                    value: _forcePrescout,
                    activeColor: ObsidianUITheme.primaryAccent,
                    onChanged: (val) => setState(() => _forcePrescout = val ?? false),
                  ),
                  const SizedBox(height: 8),
                ],

                // Graph Types multi-select
                Text('GRAPH TYPES', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kGraphTypes.map((type) {
                    final selected = _selectedGraphTypes.contains(type.id);
                    return FilterChip(
                      selected: selected,
                      avatar: Icon(type.icon, size: 16, color: selected ? Colors.white : ObsidianUITheme.getSecondaryTextColor(context)),
                      label: Text(type.label, style: TextStyle(color: selected ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                      selectedColor: ObsidianUITheme.primaryAccent,
                      checkmarkColor: Colors.white,
                      side: BorderSide(color: selected ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context)),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedGraphTypes.add(type.id);
                          } else {
                            _selectedGraphTypes.remove(type.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),

                // Quick Select All / Clear graph types
                Row(
                  children: [
                    _quickChip(context.tr('graphs.select_all'), Icons.done_all_rounded, () {
                      setState(() => _selectedGraphTypes = kGraphTypes.map((g) => g.id).toSet());
                    }),
                    const SizedBox(width: 8),
                    _quickChip(context.tr('graphs.clear_types'), Icons.clear_rounded, () {
                      setState(() => _selectedGraphTypes.clear());
                    }),
                  ],
                ),
              ],
            ),
          ),

          // === Generate Button ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _generateGraphs,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [ObsidianUITheme.primaryAccent, Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          context.tr('graphs.generate').toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.0,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // === Graphs Output ===
          if (_graphGenerated) _buildGraphsOutput(),
        ],
      ),
    );
  }

  Widget _buildGraphsOutput() {
    final filteredEntries = _getFilteredEntriesForTeams();
    final hasDiscrepancy = filteredEntries.any((e) => e.hasDiscrepancy);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Discrepancy Warning Banner if present
        if (hasDiscrepancy) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFFEAB308)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEAB308), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Discrepancy Warning: Some data contains conflicting inputs from partner teams. Review or resolve in Alliance Scouting Data.',
                    style: TextStyle(color: Color(0xFFCA8A04), fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Render a card for each selected graph type
        ..._selectedGraphTypes.map((graphType) => _buildSingleGraphCard(graphType)),
      ],
    );
  }

  Widget _buildSingleGraphCard(String graphType) {
    final metric = _selectedMetric;
    final isScouted = _datasource == 'scouted';
    final title = isScouted
        ? '${metric?.label ?? "Metric"} — ${graphType.toUpperCase()}'
        : '${_getDatasourceLabel(_datasource)} — ${graphType.toUpperCase()}';

    // 1. Check Non-scouted distributions
    if (!isScouted && (graphType == 'box' || graphType == 'violin' || graphType == 'histogram')) {
      return ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.getPrimaryTextColor(context))),
            const SizedBox(height: 12),
            _buildNotice('Distribution graphs are only supported for Scouted Data.'),
          ],
        ),
      );
    }

    // 2. Check Category metric rules
    if (isScouted && metric?.kind == 'category' && graphType != 'bar') {
      return ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.getPrimaryTextColor(context))),
            const SizedBox(height: 12),
            _buildNotice('This metric only supports bar charts.'),
          ],
        ),
      );
    }

    // 3. Render Non-scouted Graphs
    if (!isScouted) {
      return ObsidianGlassCard(
        child: _renderNonScoutedGraph(graphType, title: title),
      );
    }

    // 4. Render Scouted Graphs
    final entries = _getFilteredEntriesForTeams();

    return ObsidianGlassCard(
      child: metric != null ? _renderScoutedGraph(graphType, metric, entries, title: title) : _buildNotice('Select a metric to view graph.'),
    );
  }

  Widget _renderNonScoutedGraph(String graphType, {String title = ''}) {
    final selectedNums = _selectedTeams.toList();
    final data = selectedNums.map((teamNum) {
      final team = _teamMap[teamNum];
      return (
        num: teamNum,
        label: 'Team $teamNum',
        epa: team?.epa ?? 0.0,
        opr: team?.opr ?? 0.0,
        scouted: team?.averagePoints ?? 0.0,
      );
    }).toList();

    // Sort based on _sort
    data.sort((a, b) {
      if (_sort == 'team_asc') return a.num.compareTo(b.num);
      if (_sort == 'team_desc') return b.num.compareTo(a.num);
      final valA = _datasource == 'epa' ? a.epa : (_datasource == 'opr' ? a.opr : a.scouted);
      final valB = _datasource == 'epa' ? b.epa : (_datasource == 'opr' ? b.opr : b.scouted);
      if (_sort == 'value_asc') return valA.compareTo(valB);
      return valB.compareTo(a.scouted);
    });

    if (graphType == 'bar') {
      if (_datasource == 'all') {
        // Grouped multi-bar for Scouted, EPA, OPR
        final seriesList = <GraphSeries>[
          GraphSeries(name: 'Scouted Average', x: data.map((d) => d.label).toList(), y: data.map((d) => d.scouted).toList()),
          if (_settings?.useStatboticsEpa == true)
            GraphSeries(name: 'Statbotics EPA', x: data.map((d) => d.label).toList(), y: data.map((d) => d.epa).toList()),
          if (_settings?.useTbaOpr == true)
            GraphSeries(name: 'TBA OPR', x: data.map((d) => d.label).toList(), y: data.map((d) => d.opr).toList()),
        ];
        return _buildGroupedBarChart(seriesList, title: title);
      } else {
        final valExtractor = _datasource == 'epa' ? (d) => d.epa : (d) => d.opr;
        final points = data.map((d) => GraphPoint(d.label, valExtractor(d))).toList();
        return _buildHorizontalBarChart(points, title: title);
      }
    }

    if (graphType == 'line' || graphType == 'scatter' || graphType == 'area') {
      final labels = data.map((d) => d.label).toList();
      final seriesList = <GraphSeries>[];

      if (_datasource == 'scouted' || _datasource == 'all') {
        seriesList.add(GraphSeries(name: 'Scouted Average', x: labels, y: data.map((d) => d.scouted).toList()));
      }
      if ((_datasource == 'epa' || _datasource == 'all') && _settings?.useStatboticsEpa == true) {
        seriesList.add(GraphSeries(name: 'Statbotics EPA', x: labels, y: data.map((d) => d.epa).toList()));
      }
      if ((_datasource == 'opr' || _datasource == 'all') && _settings?.useTbaOpr == true) {
        seriesList.add(GraphSeries(name: 'TBA OPR', x: labels, y: data.map((d) => d.opr).toList()));
      }

      return _buildLineOrScatterChart(seriesList, mode: graphType, title: title);
    }

    return _buildNotice('Unsupported graph format.');
  }

  Widget _renderScoutedGraph(String graphType, GraphMetric metric, List<ScoutingEntryModel> entries, {String title = ''}) {
    if (metric.kind == 'category') {
      final counts = _buildCategoryCounts(entries, metric);
      return _buildHorizontalBarChart(counts, title: title);
    }

    if (graphType == 'bar') {
      if (_dataView == 'matches') {
        final seriesList = _buildTeamSeries(entries, metric);
        return _buildGroupedBarChart(seriesList, title: title);
      }
      final stats = _sortStats(_buildTeamStats(entries, metric));
      final points = stats.map((s) => GraphPoint('Team ${s.$1}', s.$2)).toList();
      return _buildHorizontalBarChart(points, title: title);
    }

    if (graphType == 'line' || graphType == 'scatter' || graphType == 'area') {
      final seriesList = _buildTeamSeries(entries, metric);
      return _buildLineOrScatterChart(seriesList, mode: graphType, title: title);
    }

    if (graphType == 'box' || graphType == 'violin') {
      final traces = _buildDistributionStats(entries, metric);
      return _buildDistributionCards(traces, isViolin: graphType == 'violin', title: title);
    }

    if (graphType == 'histogram') {
      final bins = _buildHistogramBins(entries, metric);
      return _buildHistogramChart(bins, title: title, entries: entries, metric: metric);
    }

    return _buildNotice('Unsupported graph format.');
  }

  Future<void> _showTeamInspectFromLabel(String label, double val) async {
    final teamNum = _extractTeamNum(label);
    if (teamNum <= 0) return;

    final teamModel = _teamMap[teamNum];
    final entries = _getFilteredEntriesForTeams();
    final teamEntries = entries.where((e) => e.targetTeamNumber == teamNum).toList();

    double? minVal;
    double? maxVal;
    double? avgVal;
    if (_selectedMetric != null && teamEntries.isNotEmpty) {
      final vals = teamEntries
          .map((e) => _metricValue(e, _selectedMetric!))
          .whereType<double>()
          .toList();
      if (vals.isNotEmpty) {
        minVal = vals.reduce(min);
        maxVal = vals.reduce(max);
        avgVal = vals.reduce((a, b) => a + b) / vals.length;
      }
    }

    int? rank;
    int? totalRankCount;
    if (_selectedTeams.isNotEmpty) {
      totalRankCount = _selectedTeams.length;
      final allStats = _buildTeamStats(entries, _selectedMetric ?? _metrics.first);
      allStats.sort((a, b) => b.$2.compareTo(a.$2));
      final idx = allStats.indexWhere((s) => s.$1 == teamNum);
      if (idx >= 0) rank = idx + 1;
    }

    final filteredTeam = await ObsidianTeamQuickInspect.show(
      context: context,
      teamNumber: teamNum,
      teamName: teamModel?.name ?? teamModel?.nickname ?? 'Team $teamNum',
      metricLabel: _selectedMetric?.label ?? 'Value',
      metricValue: val,
      apiService: widget.apiService,
      rank: rank,
      totalRankCount: totalRankCount,
      matchCount: teamEntries.length,
      teamMin: minVal,
      teamMax: maxVal,
      teamAverage: avgVal ?? val,
      showFilterButton: true,
    );

    if (filteredTeam != null && filteredTeam > 0 && mounted) {
      setState(() {
        _selectedTeams = {filteredTeam};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filtered to Team $filteredTeam only'),
          backgroundColor: ObsidianUITheme.primaryAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showHistogramBinInspect(HistogramBin bin, List<ScoutingEntryModel> entries, GraphMetric metric) {
    ObsidianChartHaptics.impact();

    final matchingEntries = entries.where((e) {
      final val = _metricValue(e, metric);
      if (val == null) return false;
      return val >= bin.start && val <= bin.end;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
                      'Bin Range: ${bin.rangeLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ObsidianUITheme.primaryAccent,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${matchingEntries.length} ${matchingEntries.length == 1 ? "entry" : "entries"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ObsidianUITheme.getSecondaryTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (matchingEntries.isEmpty)
                  Text(
                    'No entries found in this range.',
                    style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: matchingEntries.length,
                      itemBuilder: (ctx, i) {
                        final e = matchingEntries[i];
                        final val = _metricValue(e, metric) ?? 0.0;
                        final tNum = e.targetTeamNumber ?? 0;
                        final mLabel = _matchLabel(e.matchKey, e.matchNumber, i);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Team $tNum',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: ObsidianUITheme.primaryAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    mLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: ObsidianUITheme.getSecondaryTextColor(context),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                val.toStringAsFixed(val == val.truncate() ? 0 : 2),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: ObsidianUITheme.getPrimaryTextColor(context),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalBarChart(List<GraphPoint> points, {String title = ''}) {
    if (points.isEmpty) return _buildNotice('No data yet.');

    final maxVal = points.map((p) => p.value).fold(0.0, max);
    final avgVal = points.isNotEmpty
        ? points.map((p) => p.value).reduce((a, b) => a + b) / points.length
        : 0.0;
    final palette = _chartPalette();

    final minContentWidth = max(points.length * 52.0 + 40.0, 300.0);

    Widget buildChartWidget(BuildContext ctx, {bool isFullscreen = false}) {
      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal > 0 ? maxVal * 1.18 : 10.0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= points.length) return null;
                final label = points[groupIndex].label;
                return BarTooltipItem(
                  '$label\n',
                  TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                  children: [
                    TextSpan(
                      text: rod.toY.toStringAsFixed(rod.toY == rod.toY.truncate() ? 0 : 2),
                      style: TextStyle(
                        color: ObsidianUITheme.getPrimaryTextColor(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const TextSpan(
                      text: '\n(Tap to Inspect)',
                      style: TextStyle(
                        color: ObsidianUITheme.primaryAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                final groupIdx = response!.spot!.touchedBarGroupIndex;
                if (groupIdx >= 0 && groupIdx < points.length) {
                  _showTeamInspectFromLabel(points[groupIdx].label, points[groupIdx].value);
                }
              }
            },
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (_showBenchmark && avgVal > 0)
                HorizontalLine(
                  y: avgVal,
                  color: ObsidianUITheme.primaryAccent,
                  strokeWidth: 1.8,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 6, bottom: 4),
                    style: const TextStyle(
                      color: ObsidianUITheme.primaryAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    labelResolver: (_) => 'Avg: ${avgVal.toStringAsFixed(1)}',
                  ),
                ),
            ],
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
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[idx].label,
                      style: TextStyle(
                        color: ObsidianUITheme.getSecondaryTextColor(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(points.length, (i) {
            return BarChartGroupData(
              x: i,
              showingTooltipIndicators: _showDataLabels ? [0] : [],
              barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  gradient: LinearGradient(
                    colors: [
                      palette[i % palette.length].withValues(alpha: 0.9),
                      ObsidianUITheme.secondaryAccent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: max(8.0, min(28.0, 280.0 / points.length)),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      );
    }

    return ObsidianChartInteractiveWrapper(
      title: title.isNotEmpty ? title : '${_selectedMetric?.label ?? "Chart"} — BAR',
      subtitle: '${points.length} teams • Tap any bar for quick inspection',
      minContentWidth: minContentWidth,
      chartHeight: max(220.0, min(360.0, points.length * 16.0 + 120.0)),
      showDataLabels: _showDataLabels,
      onToggleDataLabels: (v) => setState(() => _showDataLabels = v),
      showBenchmark: _showBenchmark,
      onToggleBenchmark: (v) => setState(() => _showBenchmark = v),
      benchmarkValue: avgVal,
      benchmarkLabel: 'Avg: ${avgVal.toStringAsFixed(1)}',
      onRefresh: _generateGraphs,
      chart: buildChartWidget(context),
      fullscreenChartBuilder: (ctx) => buildChartWidget(ctx, isFullscreen: true),
    );
  }

  Widget _buildGroupedBarChart(List<GraphSeries> seriesList, {String title = ''}) {
    if (seriesList.isEmpty) return _buildNotice('No data yet.');

    final allX = seriesList.expand((s) => s.x).toSet().toList();
    if (allX.isEmpty) return _buildNotice('No data yet.');

    final visibleSeries = seriesList
        .where((s) => !_hiddenSeries.contains(s.name))
        .toList();

    final allY = visibleSeries.expand((s) => s.y).toList();
    final maxY = allY.isNotEmpty ? allY.reduce(max) * 1.18 : 10.0;
    final avgY = allY.isNotEmpty ? allY.reduce((a, b) => a + b) / allY.length : 0.0;
    final palette = _chartPalette();

    final legendSeries = seriesList.asMap().entries.map((entry) {
      final s = entry.value;
      final isVisible = !_hiddenSeries.contains(s.name);
      final isDimmed = _hoveredSeriesIndex != null && _hoveredSeriesIndex != entry.key;
      return ChartLegendSeries(
        name: s.name,
        color: palette[entry.key % palette.length],
        isVisible: isVisible,
        isDimmed: isDimmed,
      );
    }).toList();

    final minContentWidth = max(allX.length * (max(1, visibleSeries.length) * 32.0 + 36.0), 300.0);

    Widget buildChartWidget(BuildContext ctx, {bool isFullscreen = false}) {
      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final sName = visibleSeries.length > rodIndex ? visibleSeries[rodIndex].name : '';
                return BarTooltipItem(
                  '$sName: ${rod.toY.toStringAsFixed(rod.toY == rod.toY.truncate() ? 0 : 2)}\n(Tap to Inspect)',
                  TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                final spot = response!.spot!;
                final groupIdx = spot.touchedBarGroupIndex;
                final rodIdx = spot.touchedRodDataIndex;
                if (groupIdx >= 0 && groupIdx < allX.length) {
                  final xLabel = allX[groupIdx];
                  final sName = (rodIdx >= 0 && rodIdx < visibleSeries.length) ? visibleSeries[rodIdx].name : '';
                  final teamLabel = _resolveTeamLabel(seriesName: sName, xLabel: xLabel);
                  final val = spot.touchedRodData.toY;
                  _showTeamInspectFromLabel(teamLabel, val);
                }
              }
            },
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (_showBenchmark && avgY > 0)
                HorizontalLine(
                  y: avgY,
                  color: ObsidianUITheme.primaryAccent,
                  strokeWidth: 1.8,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 6, bottom: 4),
                    style: const TextStyle(
                      color: ObsidianUITheme.primaryAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    labelResolver: (_) => 'Avg: ${avgY.toStringAsFixed(1)}',
                  ),
                ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (val, _) => Text(
                  val == val.truncate() ? val.toInt().toString() : val.toStringAsFixed(1),
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= allX.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      allX[idx],
                      style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(allX.length, (xIdx) {
            final xLabel = allX[xIdx];
            return BarChartGroupData(
              x: xIdx,
              barRods: visibleSeries.asMap().entries.map((entry) {
                final sIdx = entry.key;
                final s = entry.value;
                final pos = s.x.indexOf(xLabel);
                final val = pos >= 0 && pos < s.y.length ? s.y[pos] : 0.0;
                final color = palette[sIdx % palette.length];
                final isDimmed = _hoveredSeriesIndex != null && _hoveredSeriesIndex != sIdx;

                return BarChartRodData(
                  toY: val,
                  color: isDimmed ? color.withValues(alpha: 0.25) : color,
                  width: max(4.0, min(24.0, 36.0 / max(1, visibleSeries.length))),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                );
              }).toList(),
            );
          }),
        ),
      );
    }

    return ObsidianChartInteractiveWrapper(
      title: title.isNotEmpty ? title : '${_selectedMetric?.label ?? "Grouped"} — GROUPED BAR',
      subtitle: '${allX.length} groups • Click legend items to toggle series',
      minContentWidth: minContentWidth,
      chartHeight: 300.0,
      legendSeries: legendSeries,
      onToggleSeries: (idx) {
        final sName = seriesList[idx].name;
        setState(() {
          if (_hiddenSeries.contains(sName)) {
            _hiddenSeries.remove(sName);
          } else {
            // Keep at least one visible
            if (_hiddenSeries.length < seriesList.length - 1) {
              _hiddenSeries.add(sName);
            }
          }
        });
      },
      onHoverSeries: (idx) => setState(() => _hoveredSeriesIndex = idx),
      showBenchmark: _showBenchmark,
      onToggleBenchmark: (v) => setState(() => _showBenchmark = v),
      benchmarkValue: avgY,
      benchmarkLabel: 'Avg: ${avgY.toStringAsFixed(1)}',
      onRefresh: _generateGraphs,
      chart: buildChartWidget(context),
      fullscreenChartBuilder: (ctx) => buildChartWidget(ctx, isFullscreen: true),
    );
  }

  Widget _buildLineOrScatterChart(List<GraphSeries> seriesList, {required String mode, String title = ''}) {
    if (seriesList.isEmpty) return _buildNotice('No data yet.');

    final palette = _chartPalette();

    // Unify x-axis and preserve order
    const levelOrder = {'PM': 0, 'QM': 1, 'EF': 2, 'SF': 3, 'F': 4};
    int labelSortKey(String label) {
      final clean = label.toUpperCase();
      int pri = 1;
      for (final entry in levelOrder.entries) {
        if (clean.contains(entry.key)) {
          pri = entry.value;
          break;
        }
      }
      final numStr = label.replaceAll(RegExp(r'[^0-9]'), '');
      final num = int.tryParse(numStr) ?? 0;
      return pri * 10000 + num;
    }

    final allX = seriesList.expand((s) => s.x).toSet().toList();
    if (mode == 'matches' || _dataView == 'matches') {
      allX.sort((a, b) => labelSortKey(a).compareTo(labelSortKey(b)));
    }

    final visibleSeries = seriesList
        .where((s) => !_hiddenSeries.contains(s.name))
        .toList();

    final allY = visibleSeries.expand((s) => s.y).toList();
    if (allY.isEmpty && seriesList.isNotEmpty) {
      // If all hidden, fall back to showing all
      visibleSeries.addAll(seriesList);
    }
    final safeY = visibleSeries.expand((s) => s.y).toList();
    final maxY = safeY.isNotEmpty ? (safeY.reduce(max) * 1.18).clamp(1.0, double.infinity) : 10.0;
    final avgY = safeY.isNotEmpty ? safeY.reduce((a, b) => a + b) / safeY.length : 0.0;

    final isScatter = mode == 'scatter';
    final isArea = mode == 'area';

    final legendSeries = seriesList.asMap().entries.map((entry) {
      final s = entry.value;
      final isVisible = !_hiddenSeries.contains(s.name);
      final isDimmed = _hoveredSeriesIndex != null && _hoveredSeriesIndex != entry.key;
      return ChartLegendSeries(
        name: s.name,
        color: palette[entry.key % palette.length],
        isVisible: isVisible,
        isDimmed: isDimmed,
      );
    }).toList();

    final minContentWidth = max(allX.length * 44.0 + 40.0, 300.0);

    Widget buildChartWidget(BuildContext ctx, {bool isFullscreen = false}) {
      final lineBarsData = visibleSeries.asMap().entries.map((entry) {
        final i = entry.key;
        final series = entry.value;
        final color = palette[i % palette.length];
        final isDimmed = _hoveredSeriesIndex != null && _hoveredSeriesIndex != i;

        final spots = List.generate(series.x.length, (j) {
          final xIdx = allX.indexOf(series.x[j]).toDouble();
          return FlSpot(xIdx < 0 ? j.toDouble() : xIdx, series.y[j]);
        });

        return LineChartBarData(
          spots: spots,
          isCurved: !isScatter,
          color: isScatter ? Colors.transparent : (isDimmed ? color.withValues(alpha: 0.25) : color),
          barWidth: isScatter ? 0.0 : (isDimmed ? 1.5 : 2.5),
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
              radius: isScatter ? 6.0 : 4.5,
              color: isDimmed ? color.withValues(alpha: 0.3) : color,
              strokeWidth: 2,
              strokeColor: ObsidianUITheme.getSurfaceColor(context),
            ),
          ),
          belowBarData: isArea
              ? BarAreaData(
                  show: true,
                  color: color.withValues(alpha: isDimmed ? 0.05 : 0.20),
                )
              : BarAreaData(show: false),
        );
      }).toList();

      return LineChart(
        LineChartData(
          maxY: maxY,
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItems: (spots) => spots.map((s) {
                final seriesName = visibleSeries.length > s.barIndex ? visibleSeries[s.barIndex].name : '';
                return LineTooltipItem(
                  '$seriesName: ${s.y.toStringAsFixed(s.y == s.y.truncate() ? 0 : 2)}',
                  TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                );
              }).toList(),
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
                final touched = response.lineBarSpots!.first;
                final sName = visibleSeries.length > touched.barIndex ? visibleSeries[touched.barIndex].name : '';
                final xIdx = touched.x.toInt();
                final xLabel = (xIdx >= 0 && xIdx < allX.length) ? allX[xIdx] : '';
                final teamLabel = _resolveTeamLabel(seriesName: sName, xLabel: xLabel);
                _showTeamInspectFromLabel(teamLabel, touched.y);
              }
            },
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (_showBenchmark && avgY > 0)
                HorizontalLine(
                  y: avgY,
                  color: ObsidianUITheme.primaryAccent,
                  strokeWidth: 1.8,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 6, bottom: 4),
                    style: const TextStyle(
                      color: ObsidianUITheme.primaryAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    labelResolver: (_) => 'Avg: ${avgY.toStringAsFixed(1)}',
                  ),
                ),
            ],
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
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) return const SizedBox.shrink();
                  final idx = value.toInt();
                  if (idx < 0 || idx >= allX.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      allX[idx],
                      style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 1),
            getDrawingVerticalLine: (_) => FlLine(
                color: ObsidianUITheme.getBorderColor(context).withValues(alpha: 0.5),
                strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: lineBarsData,
        ),
      );
    }

    return ObsidianChartInteractiveWrapper(
      title: title.isNotEmpty ? title : '${_selectedMetric?.label ?? "Chart"} — ${mode.toUpperCase()}',
      subtitle: '${allX.length} points • Scrub to inspect or click legend to toggle',
      minContentWidth: minContentWidth,
      chartHeight: 300.0,
      legendSeries: legendSeries,
      onToggleSeries: (idx) {
        final sName = seriesList[idx].name;
        setState(() {
          if (_hiddenSeries.contains(sName)) {
            _hiddenSeries.remove(sName);
          } else {
            if (_hiddenSeries.length < seriesList.length - 1) {
              _hiddenSeries.add(sName);
            }
          }
        });
      },
      onHoverSeries: (idx) => setState(() => _hoveredSeriesIndex = idx),
      showBenchmark: _showBenchmark,
      onToggleBenchmark: (v) => setState(() => _showBenchmark = v),
      benchmarkValue: avgY,
      benchmarkLabel: 'Avg: ${avgY.toStringAsFixed(1)}',
      onRefresh: _generateGraphs,
      chart: buildChartWidget(context),
      fullscreenChartBuilder: (ctx) => buildChartWidget(ctx, isFullscreen: true),
    );
  }

  Widget _buildDistributionCards(List<DistributionStats> statsList, {required bool isViolin, String title = ''}) {
    if (statsList.isEmpty) return _buildNotice('No data yet.');
    final palette = _chartPalette();

    final legendSeries = statsList.asMap().entries.map((entry) {
      return ChartLegendSeries(
        name: entry.value.name,
        color: palette[entry.key % palette.length],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObsidianChartInteractiveWrapper(
          title: title.isNotEmpty ? title : '${_selectedMetric?.label ?? "Distribution"} — ${isViolin ? "VIOLIN" : "BOX PLOT"}',
          subtitle: '${statsList.length} teams • Tap or hover column for quantile breakdown',
          chartHeight: 280.0,
          legendSeries: legendSeries,
          onRefresh: _generateGraphs,
          chart: ObsidianDistributionChart(
            statsList: statsList,
            isViolin: isViolin,
            palette: palette,
            apiService: widget.apiService,
          ),
        ),
        const SizedBox(height: 16),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${isViolin ? "Violin" : "Box Plot"} Statistical Breakdown (${statsList.length} ${statsList.length == 1 ? "group" : "groups"})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ObsidianUITheme.getSecondaryTextColor(context),
                letterSpacing: 0.5,
              ),
            ),
            children: statsList.map((stats) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ObsidianUITheme.getSurfaceColor(context),
                  border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(stats.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: ObsidianUITheme.primaryAccent)),
                        Text('${stats.count} matches', style: TextStyle(fontSize: 10, color: ObsidianUITheme.getTertiaryTextColor(context))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _miniStat('Min', stats.min),
                        _miniStat('Q1 (25%)', stats.q1),
                        _miniStat('Median', stats.median, isHighlight: true),
                        _miniStat('Q3 (75%)', stats.q3),
                        _miniStat('Max', stats.max),
                        _miniStat('Mean', stats.mean),
                      ],
                    ),
                    if (stats.outliers.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Outliers: ${stats.outliers.map((o) => o.toStringAsFixed(1)).join(", ")}',
                        style: const TextStyle(color: ObsidianUITheme.warningOrange, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, double val, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(val.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal, color: isHighlight ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context))),
        Text(label, style: TextStyle(fontSize: 9, color: ObsidianUITheme.getSecondaryTextColor(context))),
      ],
    );
  }

  Widget _buildHistogramChart(List<HistogramBin> bins, {String title = '', List<ScoutingEntryModel>? entries, GraphMetric? metric}) {
    if (bins.isEmpty) return _buildNotice('No data yet.');

    final maxCount = bins.map((b) => b.count).fold(0, max).toDouble();

    Widget buildChart(BuildContext ctx) {
      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxCount > 0 ? maxCount * 1.2 : 5.0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ObsidianUITheme.getSurfaceColor(context),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final bin = bins[groupIndex];
                return BarTooltipItem(
                  'Range: ${bin.rangeLabel}\nCount: ${bin.count}\n(Tap to view entries)',
                  TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                final idx = response!.spot!.touchedBarGroupIndex;
                if (idx >= 0 && idx < bins.length && entries != null && metric != null) {
                  _showHistogramBinInspect(bins[idx], entries, metric);
                }
              }
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= bins.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(bins[idx].rangeLabel, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 9)),
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
          barGroups: List.generate(bins.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: bins[i].count.toDouble(),
                  color: ObsidianUITheme.primaryAccent,
                  width: max(12.0, 180.0 / bins.length),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      );
    }

    return ObsidianChartInteractiveWrapper(
      title: title.isNotEmpty ? title : '${_selectedMetric?.label ?? "Distribution"} — HISTOGRAM',
      subtitle: '${bins.length} bins • Tap any bin to view matching matches',
      chartHeight: 250.0,
      onRefresh: _generateGraphs,
      chart: buildChart(context),
      fullscreenChartBuilder: (ctx) => buildChart(ctx),
    );
  }

  Widget _buildNotice(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 13, fontStyle: FontStyle.italic)),
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

extension _IterableExt<T> on Iterable<T> {
  List<T> sortDescending(int Function(T a, T b) compare) {
    final list = toList();
    list.sort((a, b) => compare(b, a));
    return list;
  }
}

/// Interactive graphical chart for Box Plots and Violin Plots
class ObsidianDistributionChart extends StatefulWidget {
  final List<DistributionStats> statsList;
  final bool isViolin;
  final List<Color> palette;
  final double canvasHeight;
  final ApiService? apiService;

  const ObsidianDistributionChart({
    super.key,
    required this.statsList,
    required this.isViolin,
    required this.palette,
    this.canvasHeight = 260.0,
    this.apiService,
  });

  @override
  State<ObsidianDistributionChart> createState() => _ObsidianDistributionChartState();
}

class _ObsidianDistributionChartState extends State<ObsidianDistributionChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.statsList.isEmpty) return const SizedBox.shrink();

    final allMin = widget.statsList.map((s) => s.min).reduce(min);
    final allMax = widget.statsList.map((s) => s.max).reduce(max);
    final range = (allMax - allMin).abs();
    final pad = range > 0 ? range * 0.12 : 5.0;
    final minY = allMin >= 0 && allMin - pad < 0 ? 0.0 : allMin - pad;
    final maxY = allMax + pad;

    final count = widget.statsList.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : widget.canvasHeight;
        final chartWidth = count <= 4 ? availableWidth : max(availableWidth, count * 85.0 + 50.0);

        return Stack(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: chartWidth,
                height: availableHeight,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (event) {
                    _handleTouch(event.localPosition, chartWidth);
                  },
                  onExit: (_) {
                    scheduleMicrotask(() {
                      if (mounted && _selectedIndex != null) {
                        setState(() => _selectedIndex = null);
                      }
                    });
                  },
                  child: GestureDetector(
                    onTapDown: (details) {
                      ObsidianChartHaptics.lightTouch();
                      _handleTouch(details.localPosition, chartWidth);
                    },
                    onTap: () {
                      if (_selectedIndex != null && _selectedIndex! >= 0 && _selectedIndex! < count && widget.apiService != null) {
                        final stats = widget.statsList[_selectedIndex!];
                        final teamNum = _parseTeamNumber(stats.name);
                        if (teamNum > 0) {
                          ObsidianTeamQuickInspect.show(
                            context: context,
                            teamNumber: teamNum,
                            teamName: stats.name,
                            metricLabel: 'Median Score',
                            metricValue: stats.median,
                            apiService: widget.apiService!,
                            matchCount: stats.count,
                            teamMin: stats.min,
                            teamMax: stats.max,
                            teamAverage: stats.mean,
                          );
                        }
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      _handleTouch(details.localPosition, chartWidth);
                    },
                    child: CustomPaint(
                      size: Size(chartWidth, availableHeight),
                      painter: _DistributionPainter(
                        statsList: widget.statsList,
                        isViolin: widget.isViolin,
                        palette: widget.palette,
                        minY: minY,
                        maxY: maxY,
                        selectedIndex: _selectedIndex,
                        textColor: ObsidianUITheme.getPrimaryTextColor(context),
                        secondaryTextColor: ObsidianUITheme.getSecondaryTextColor(context),
                        tertiaryTextColor: ObsidianUITheme.getTertiaryTextColor(context),
                        gridColor: ObsidianUITheme.getBorderColor(context),
                        surfaceColor: ObsidianUITheme.getSurfaceColor(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Floating Tooltip Card over top if column is selected
            if (_selectedIndex != null && _selectedIndex! >= 0 && _selectedIndex! < count)
              Positioned(
                top: 0,
                left: 8,
                right: 8,
                child: _buildTooltipCard(widget.statsList[_selectedIndex!], _selectedIndex!),
              ),
          ],
        );
      },
    );
  }

  void _handleTouch(Offset localPos, double totalWidth) {
    const leftMargin = 46.0;
    const rightMargin = 16.0;
    final chartContentWidth = totalWidth - leftMargin - rightMargin;
    final colWidth = chartContentWidth / widget.statsList.length;

    if (localPos.dx < leftMargin || localPos.dx > totalWidth - rightMargin) {
      if (_selectedIndex != null) {
        scheduleMicrotask(() {
          if (mounted) setState(() => _selectedIndex = null);
        });
      }
      return;
    }

    final index = ((localPos.dx - leftMargin) / colWidth).floor();
    if (index >= 0 && index < widget.statsList.length) {
      if (_selectedIndex != index) {
        scheduleMicrotask(() {
          if (mounted) setState(() => _selectedIndex = index);
        });
      }
    }
  }

  Widget _buildTooltipCard(DistributionStats stats, int index) {
    final color = widget.palette[index % widget.palette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(stats.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ObsidianUITheme.getPrimaryTextColor(context))),
              const SizedBox(width: 6),
              Text('(${stats.count} matches)', style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
            ],
          ),
          Row(
            children: [
              _tooltipStat('Med', stats.median.toStringAsFixed(1), isBold: true),
              const SizedBox(width: 8),
              _tooltipStat('Q1-Q3', '${stats.q1.toStringAsFixed(1)} - ${stats.q3.toStringAsFixed(1)}'),
              const SizedBox(width: 8),
              _tooltipStat('Min-Max', '${stats.min.toStringAsFixed(1)} - ${stats.max.toStringAsFixed(1)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tooltipStat(String label, String val, {bool isBold = false}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context)),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: val,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionPainter extends CustomPainter {
  final List<DistributionStats> statsList;
  final bool isViolin;
  final List<Color> palette;
  final double minY;
  final double maxY;
  final int? selectedIndex;
  final Color textColor;
  final Color secondaryTextColor;
  final Color tertiaryTextColor;
  final Color gridColor;
  final Color surfaceColor;

  _DistributionPainter({
    required this.statsList,
    required this.isViolin,
    required this.palette,
    required this.minY,
    required this.maxY,
    this.selectedIndex,
    required this.textColor,
    required this.secondaryTextColor,
    required this.tertiaryTextColor,
    required this.gridColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 46.0;
    const rightMargin = 16.0;
    const topMargin = 16.0;
    const bottomMargin = 36.0;

    final chartWidth = size.width - leftMargin - rightMargin;
    final chartHeight = size.height - topMargin - bottomMargin;
    final yRange = (maxY - minY) == 0 ? 1.0 : (maxY - minY);

    double toY(double val) {
      final normalized = (val - minY) / yRange;
      return topMargin + (1.0 - normalized.clamp(0.0, 1.0)) * chartHeight;
    }

    // 1. Draw horizontal grid lines & Y-axis labels
    const gridDivisions = 5;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= gridDivisions; i++) {
      final gridVal = minY + (i / gridDivisions) * yRange;
      final yPos = toY(gridVal);

      // Grid line
      canvas.drawLine(Offset(leftMargin, yPos), Offset(size.width - rightMargin, yPos), gridPaint);

      // Y-axis Label
      final labelText = gridVal == gridVal.truncate() ? gridVal.toInt().toString() : gridVal.toStringAsFixed(1);
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(color: tertiaryTextColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(leftMargin - textPainter.width - 6, yPos - textPainter.height / 2));
    }

    if (statsList.isEmpty) return;

    final colWidth = chartWidth / statsList.length;

    // 2. Draw each team distribution (Box or Violin)
    for (int i = 0; i < statsList.length; i++) {
      final stats = statsList[i];
      final color = palette[i % palette.length];
      final isSelected = selectedIndex == i;
      final centerX = leftMargin + (i + 0.5) * colWidth;
      final maxColWidth = min(54.0, colWidth * 0.65);

      // Highlight background if selected
      if (isSelected) {
        final colRect = Rect.fromLTWH(leftMargin + i * colWidth, topMargin, colWidth, chartHeight);
        final selectPaint = Paint()..color = color.withValues(alpha: 0.08);
        canvas.drawRRect(RRect.fromRectAndRadius(colRect, const Radius.circular(6)), selectPaint);
      }

      if (isViolin) {
        _paintViolin(canvas, stats, centerX, maxColWidth, toY, color, isSelected);
      } else {
        _paintBoxPlot(canvas, stats, centerX, maxColWidth, toY, color, isSelected);
      }

      // X-axis Team Label (Draws 'Team 254' or 'Team XXX')
      final xText = stats.name;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: xText,
          style: TextStyle(
            color: isSelected ? color : secondaryTextColor,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      labelPainter.paint(
        canvas,
        Offset(centerX - labelPainter.width / 2, size.height - bottomMargin + 8),
      );
    }
  }

  void _paintBoxPlot(
    Canvas canvas,
    DistributionStats stats,
    double centerX,
    double colWidth,
    double Function(double) toY,
    Color color,
    bool isSelected,
  ) {
    final yMin = toY(stats.min);
    final yQ1 = toY(stats.q1);
    final yMedian = toY(stats.median);
    final yQ3 = toY(stats.q3);
    final yMax = toY(stats.max);
    final yMean = toY(stats.mean);

    final whiskerPaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 2.0 : 1.5;

    final capWidth = colWidth * 0.4;

    // 1. Whiskers & Caps (Q3 -> Max, Q1 -> Min)
    // Upper whisker (from top of box yQ3 to yMax)
    canvas.drawLine(Offset(centerX, yQ3), Offset(centerX, yMax), whiskerPaint);
    canvas.drawLine(Offset(centerX - capWidth / 2, yMax), Offset(centerX + capWidth / 2, yMax), whiskerPaint);

    // Lower whisker (from bottom of box yQ1 to yMin)
    canvas.drawLine(Offset(centerX, yQ1), Offset(centerX, yMin), whiskerPaint);
    canvas.drawLine(Offset(centerX - capWidth / 2, yMin), Offset(centerX + capWidth / 2, yMin), whiskerPaint);

    // 2. IQR Box (from Q1 to Q3)
    final boxTop = min(yQ1, yQ3);
    final boxBottom = max(yQ1, yQ3);
    final boxRect = Rect.fromLTRB(
      centerX - colWidth / 2,
      boxTop,
      centerX + colWidth / 2,
      max(boxTop + 2.0, boxBottom),
    );

    final boxFillPaint = Paint()
      ..color = color.withValues(alpha: isSelected ? 0.42 : 0.28)
      ..style = PaintingStyle.fill;
    final boxBorderPaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 2.4 : 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(4)), boxFillPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(4)), boxBorderPaint);

    // 3. Median Line
    final medianPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4;
    canvas.drawLine(
      Offset(centerX - colWidth / 2, yMedian),
      Offset(centerX + colWidth / 2, yMedian),
      medianPaint,
    );

    // 4. Mean Indicator (dashed horizontal or center diamond)
    final meanPaint = Paint()
      ..color = ObsidianUITheme.warningOrange
      ..style = PaintingStyle.fill;
    const diamondSize = 4.0;
    final meanPath = Path()
      ..moveTo(centerX, yMean - diamondSize)
      ..lineTo(centerX + diamondSize, yMean)
      ..lineTo(centerX, yMean + diamondSize)
      ..lineTo(centerX - diamondSize, yMean)
      ..close();
    canvas.drawPath(meanPath, meanPaint);

    // 5. Outliers
    final outlierPaint = Paint()
      ..color = ObsidianUITheme.warningOrange
      ..style = PaintingStyle.fill;
    final outlierBorderPaint = Paint()
      ..color = surfaceColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final out in stats.outliers) {
      final outY = toY(out);
      canvas.drawCircle(Offset(centerX, outY), 3.5, outlierPaint);
      canvas.drawCircle(Offset(centerX, outY), 3.5, outlierBorderPaint);
    }
  }

  void _paintViolin(
    Canvas canvas,
    DistributionStats stats,
    double centerX,
    double colWidth,
    double Function(double) toY,
    Color color,
    bool isSelected,
  ) {
    if (stats.rawValues.isEmpty) return;

    final values = stats.rawValues;
    final n = values.length;
    final minVal = stats.min;
    final maxVal = stats.max;

    // 1. Kernel Density Estimation (Gaussian Kernel)
    // Silverman's rule of thumb bandwidth
    final mean = stats.mean;
    final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / max(1, n - 1);
    final sd = sqrt(variance);
    final h = max(0.5, 1.06 * (sd > 0 ? sd : 1.0) * pow(n, -0.2));

    double kernel(double u) => exp(-0.5 * u * u) / sqrt(2 * pi);
    double kde(double y) {
      double sum = 0.0;
      for (final v in values) {
        sum += kernel((y - v) / h);
      }
      return sum / (n * h);
    }

    const steps = 36;
    final yStep = (maxVal - minVal) / steps;
    final densities = <double>[];
    double maxD = 0.0;

    for (int step = 0; step <= steps; step++) {
      final yVal = minVal + step * yStep;
      final d = kde(yVal);
      densities.add(d);
      if (d > maxD) maxD = d;
    }

    if (maxD == 0) maxD = 1.0;
    final halfWidth = colWidth * 0.5;

    // 2. Build Symmetrical Violin Path
    final rightPoints = <Offset>[];
    final leftPoints = <Offset>[];

    for (int step = 0; step <= steps; step++) {
      final yVal = minVal + step * yStep;
      final canvasY = toY(yVal);
      final d = densities[step];
      final dx = (d / maxD) * halfWidth;

      rightPoints.add(Offset(centerX + dx, canvasY));
      leftPoints.add(Offset(centerX - dx, canvasY));
    }

    final violinPath = Path();
    if (rightPoints.isNotEmpty) {
      violinPath.moveTo(centerX, rightPoints.first.dy);
      for (final p in rightPoints) {
        violinPath.lineTo(p.dx, p.dy);
      }
      violinPath.lineTo(centerX, rightPoints.last.dy);
      for (final p in leftPoints.reversed) {
        violinPath.lineTo(p.dx, p.dy);
      }
      violinPath.close();
    }

    // Fill Violin Body
    final violinFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isSelected ? 0.48 : 0.32),
          color.withValues(alpha: isSelected ? 0.24 : 0.14),
        ],
      ).createShader(Rect.fromLTWH(centerX - halfWidth, toY(maxVal), halfWidth * 2, (toY(minVal) - toY(maxVal)).abs()))
      ..style = PaintingStyle.fill;

    final violinBorderPaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(violinPath, violinFillPaint);
    canvas.drawPath(violinPath, violinBorderPaint);

    // 3. Inner Whisker Spine (Min to Max)
    final spinePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(centerX, toY(stats.min)), Offset(centerX, toY(stats.max)), spinePaint);

    // 4. Inner Quartile Box (Q1 to Q3)
    final q1Y = toY(stats.q1);
    final q3Y = toY(stats.q3);
    final innerBoxRect = Rect.fromLTRB(
      centerX - 3.5,
      min(q1Y, q3Y),
      centerX + 3.5,
      max(q1Y, q3Y),
    );
    final innerBoxPaint = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.fill;
    final innerBoxStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(RRect.fromRectAndRadius(innerBoxRect, const Radius.circular(2)), innerBoxPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(innerBoxRect, const Radius.circular(2)), innerBoxStroke);

    // 5. Median Center Dot
    final medianY = toY(stats.median);
    canvas.drawCircle(Offset(centerX, medianY), 3.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(centerX, medianY), 3.5, Paint()..color = surfaceColor..style = PaintingStyle.stroke..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(covariant _DistributionPainter oldDelegate) {
    return oldDelegate.statsList != statsList ||
        oldDelegate.isViolin != isViolin ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY;
  }
}


