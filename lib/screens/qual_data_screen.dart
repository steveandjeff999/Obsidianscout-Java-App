import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/conflict_resolution_modal.dart';

class QualScoutingRecord {
  final String id;
  final int targetTeamNumber;
  final String eventKey;
  final bool isPrescout;
  final int? matchNumber;
  final String? matchKey;
  final String? createdAt;
  final Map<String, dynamic> data;
  final String? scoutUsername;

  QualScoutingRecord({
    required this.id,
    required this.targetTeamNumber,
    required this.eventKey,
    this.isPrescout = false,
    this.matchNumber,
    this.matchKey,
    this.createdAt,
    required this.data,
    this.scoutUsername,
  });

  DateTime? get createdDateTime {
    if (createdAt == null || createdAt!.isEmpty) return null;
    return DateTime.tryParse(createdAt!);
  }
}

class QualRankedTeam {
  final int rank;
  final int teamNumber;
  final String nickname;
  final double score;
  final int entryCount;
  final List<int> matches;
  final String trend; // 'improving', 'declining', 'steady'
  final String? lastUpdated;
  final List<QualScoutingRecord> entries;

  QualRankedTeam({
    required this.rank,
    required this.teamNumber,
    required this.nickname,
    required this.score,
    required this.entryCount,
    required this.matches,
    required this.trend,
    this.lastUpdated,
    required this.entries,
  });
}

class QualDataScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const QualDataScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<QualDataScreen> createState() => _QualDataScreenState();
}

class _QualDataScreenState extends State<QualDataScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;

  List<QualScoutingRecord> _rawEntries = [];
  List<EventModel> _events = [];
  Map<int, TeamModel> _teamsByNumber = {};
  ScoutingConfigModel? _qualConfig;
  List<ScoutingFieldModel> _metricFields = [];

  // Filter & Metric Analysis State
  String _selectedEventKey = 'all';
  String _teamQuery = '';
  String _selectedMetric = '__composite__'; // '__composite__' or fieldId
  String _aggregateMode = 'avg'; // 'avg', 'median', 'latest', 'max', 'min'
  int _minEntries = 1;
  String _entrySort = 'createdAt-desc';
  bool _conflictsOnly = false;
  late TabController _tabController;
  QualRankedTeam? _selectedRankedTeam;
  QualScoutingRecord? _selectedEntry;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant QualDataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await widget.apiService.fetchSettings();
      final currentYear = settings?.year ?? DateTime.now().year;

      final results = await Future.wait([
        widget.apiService.fetchQualConfig(),
        widget.apiService.fetchQualScoutingEntries(),
        widget.apiService.fetchEvents(year: currentYear),
        widget.apiService.fetchTeams(settings?.eventKey ?? ''),
      ]);

      final qualCfg = results[0] as ScoutingConfigModel?;
      final qualRaw = results[1] as List<dynamic>;
      final events = results[2] as List<EventModel>;
      final teams = results[3] as List<TeamModel>;

      final Map<int, TeamModel> teamMap = {};
      for (final t in teams) {
        teamMap[t.teamNumber] = t;
      }

      final List<QualScoutingRecord> parsed = [];
      for (final e in qualRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          parsed.add(QualScoutingRecord(
            id: e['id']?.toString() ?? '',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            matchNumber: (e['matchNumber'] as num?)?.toInt(),
            matchKey: e['matchKey']?.toString(),
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      // Filter numeric / rating fields from qual config for metric ranking
      final metricCandidates = <ScoutingFieldModel>[];
      if (qualCfg != null) {
        for (final f in qualCfg.fields) {
          if (['number', 'counter', 'slider', 'range', 'rating'].contains(f.type.toLowerCase())) {
            metricCandidates.add(f);
          }
        }
      }

      if (mounted) {
        setState(() {
          _qualConfig = qualCfg;
          _metricFields = metricCandidates;
          _rawEntries = parsed;
          _events = events;
          _teamsByNumber = teamMap;
          if (_selectedEventKey == 'all' && settings?.eventKey != null && settings!.eventKey.isNotEmpty) {
            _selectedEventKey = settings.eventKey;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  double _extractMetricValue(Map<String, dynamic> data, String metricId) {
    if (metricId == '__composite__') {
      if (_metricFields.isEmpty) return 0.0;
      double total = 0.0;
      int count = 0;
      for (final f in _metricFields) {
        final raw = data[f.id];
        if (raw is num) {
          total += raw.toDouble();
          count++;
        }
      }
      return count > 0 ? (total / count) : 0.0;
    }

    final raw = data[metricId];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  List<QualRankedTeam> get _computedRankings {
    final query = _teamQuery.trim().toLowerCase();

    // Filter raw entries by event
    final filtered = _rawEntries.where((e) {
      if (_selectedEventKey != 'all' && _selectedEventKey.isNotEmpty) {
        if (e.eventKey != _selectedEventKey) return false;
      }
      return true;
    }).toList();

    // Group by teamNumber
    final Map<int, List<QualScoutingRecord>> byTeam = {};
    for (final e in filtered) {
      byTeam.putIfAbsent(e.targetTeamNumber, () => []).add(e);
    }

    final List<QualRankedTeam> list = [];

    byTeam.forEach((teamNum, entries) {
      if (entries.length < _minEntries) return;

      final teamObj = _teamsByNumber[teamNum];
      final nickname = teamObj?.nickname ?? 'Team $teamNum';

      if (query.isNotEmpty) {
        final numStr = teamNum.toString();
        final name = nickname.toLowerCase();
        if (!numStr.contains(query) && !name.contains(query)) {
          return;
        }
      }

      // Sort entries chronologically to compute trend
      entries.sort((a, b) {
        final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return da.compareTo(db);
      });

      final values = entries.map((e) => _extractMetricValue(e.data, _selectedMetric)).toList();
      double score = 0.0;

      if (values.isNotEmpty) {
        switch (_aggregateMode) {
          case 'latest':
            score = values.last;
            break;
          case 'median':
            final sorted = List<double>.from(values)..sort();
            final mid = sorted.length ~/ 2;
            score = sorted.length.isOdd ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2);
            break;
          case 'max':
            score = values.reduce(max);
            break;
          case 'min':
            score = values.reduce(min);
            break;
          case 'avg':
          default:
            score = values.reduce((a, b) => a + b) / values.length;
            break;
        }
      }

      // Trend calculation
      String trend = 'steady';
      if (values.length >= 2) {
        final firstHalf = values.sublist(0, values.length ~/ 2);
        final secondHalf = values.sublist(values.length ~/ 2);
        final avg1 = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
        final avg2 = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
        if (avg2 - avg1 > 0.3) {
          trend = 'improving';
        } else if (avg1 - avg2 > 0.3) {
          trend = 'declining';
        }
      }

      final matches = entries.map((e) => e.matchNumber ?? 0).where((m) => m > 0).toSet().toList()..sort();
      final lastDate = entries.isNotEmpty ? entries.last.createdAt : null;

      list.add(QualRankedTeam(
        rank: 0,
        teamNumber: teamNum,
        nickname: nickname,
        score: score,
        entryCount: entries.length,
        matches: matches,
        trend: trend,
        lastUpdated: lastDate,
        entries: entries,
      ));
    });

    // Sort by score descending
    list.sort((a, b) => b.score.compareTo(a.score));

    // Assign 1-indexed ranks
    final ranked = <QualRankedTeam>[];
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      ranked.add(QualRankedTeam(
        rank: i + 1,
        teamNumber: item.teamNumber,
        nickname: item.nickname,
        score: item.score,
        entryCount: item.entryCount,
        matches: item.matches,
        trend: item.trend,
        lastUpdated: item.lastUpdated,
        entries: item.entries,
      ));
    }

    return ranked;
  }

  List<QualScoutingRecord> _getConflictingRecordsFor(QualScoutingRecord record) {
    return _rawEntries.where((e) {
      if (e.targetTeamNumber != record.targetTeamNumber) return false;
      if (e.eventKey != record.eventKey) return false;
      if (e.matchNumber != record.matchNumber) return false;
      return true;
    }).toList();
  }

  void _openConflictResolver(QualScoutingRecord record) {
    final conflicts = _getConflictingRecordsFor(record);
    if (conflicts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No conflicting qualitative submissions found.')),
      );
      return;
    }

    final rawEntries = conflicts.map((c) => {
      'id': c.id,
      'scoutUsername': c.scoutUsername ?? 'Scouter',
      'createdAt': c.createdAt,
      'data': c.data,
      'targetTeamNumber': c.targetTeamNumber,
      'eventKey': c.eventKey,
      'matchKey': c.matchKey,
      'matchNumber': c.matchNumber,
    }).toList();

    ConflictResolutionModal.show(
      context: context,
      apiService: widget.apiService,
      title: 'Qual Conflict: Team ${record.targetTeamNumber}${record.matchNumber != null ? ' (M${record.matchNumber})' : ''}',
      subtitle: '${conflicts.length} scouter qualitative ratings submitted. Compare side-by-side.',
      type: 'qual',
      fields: _qualConfig?.fields ?? [],
      conflictingEntries: rawEntries,
      onResolved: _loadData,
    );
  }

  List<QualScoutingRecord> get _filteredEntryList {
    final query = _teamQuery.trim().toLowerCase();

    final list = _rawEntries.where((e) {
      if (_selectedEventKey != 'all' && _selectedEventKey.isNotEmpty) {
        if (e.eventKey != _selectedEventKey) return false;
      }
      if (_conflictsOnly) {
        final conflicts = _getConflictingRecordsFor(e);
        if (conflicts.length <= 1) return false;
      }
      if (query.isNotEmpty) {
        final numStr = e.targetTeamNumber.toString();
        final teamObj = _teamsByNumber[e.targetTeamNumber];
        final name = teamObj?.nickname?.toLowerCase() ?? '';
        if (!numStr.contains(query) && !name.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    list.sort((a, b) {
      switch (_entrySort) {
        case 'createdAt-asc':
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return da.compareTo(db);
        case 'metric-desc':
          final va = _extractMetricValue(a.data, _selectedMetric);
          final vb = _extractMetricValue(b.data, _selectedMetric);
          return vb.compareTo(va);
        case 'metric-asc':
          final va = _extractMetricValue(a.data, _selectedMetric);
          final vb = _extractMetricValue(b.data, _selectedMetric);
          return va.compareTo(vb);
        case 'team-asc':
          return a.targetTeamNumber.compareTo(b.targetTeamNumber);
        case 'match-asc':
          final ma = a.matchNumber ?? 0;
          final mb = b.matchNumber ?? 0;
          return ma.compareTo(mb);
        case 'createdAt-desc':
        default:
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
      }
    });

    return list;
  }

  void _resetFilters() {
    setState(() {
      _teamQuery = '';
      _selectedMetric = '__composite__';
      _aggregateMode = 'avg';
      _minEntries = 1;
      _conflictsOnly = false;
      _entrySort = 'createdAt-desc';
      _selectedRankedTeam = null;
      _selectedEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Failed to load qualitative scouting data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: secondaryTextColor, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final rankings = _computedRankings;
    final entries = _filteredEntryList;
    final totalEntries = _rawEntries.length;
    final teamsRanked = rankings.length;

    String metricName = 'Composite Score';
    if (_selectedMetric != '__composite__') {
      final f = _metricFields.where((f) => f.id == _selectedMetric).firstOrNull;
      metricName = f?.label ?? _selectedMetric;
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 24.0),
        children: [
          // Header Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rate_review_rounded, color: Colors.lightGreenAccent, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Qualitative Data Center',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Analyze driver skill, defense impact, and team performance ratings across matches.',
                  style: TextStyle(color: secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 18),
                // Metric cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Qual Entries', totalEntries.toString(), Colors.lightGreenAccent, isDark)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildMetricTile('Teams Ranked', teamsRanked.toString(), Colors.cyanAccent, isDark)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildMetricTile('Metric', metricName, Colors.amberAccent, isDark),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _buildMetricTile('Qual Entries', totalEntries.toString(), Colors.lightGreenAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Teams Ranked', teamsRanked.toString(), Colors.cyanAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Metric', metricName, Colors.amberAccent, isDark)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Filters Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Ranking & Performance Config',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                    ),
                    const Spacer(),
                    FilterChip(
                      selected: _conflictsOnly,
                      showCheckmark: true,
                      checkmarkColor: Colors.black87,
                      label: const Text('Conflicts Only'),
                      avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amberAccent),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _conflictsOnly ? Colors.black87 : Colors.amberAccent,
                      ),
                      selectedColor: Colors.amberAccent,
                      backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                      side: BorderSide(color: Colors.amberAccent.withOpacity(0.4)),
                      onSelected: (val) => setState(() => _conflictsOnly = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Event selector
                DropdownButtonFormField<String>(
                  value: _events.any((e) => e.eventKey == _selectedEventKey) ? _selectedEventKey : 'all',
                  decoration: InputDecoration(
                    labelText: 'Event',
                    prefixIcon: const Icon(Icons.event_rounded, size: 20),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Events')),
                    ..._events.map((e) => DropdownMenuItem(
                          value: e.eventKey,
                          child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedEventKey = val);
                  },
                ),
                const SizedBox(height: 10),
                // Team search & Rank by metric
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search Team # or name',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) => setState(() => _teamQuery = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: (_selectedMetric == '__composite__' || _metricFields.any((f) => f.id == _selectedMetric))
                            ? _selectedMetric
                            : '__composite__',
                        decoration: InputDecoration(
                          labelText: 'Rank Metric',
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: '__composite__', child: Text('Composite Score')),
                          ..._metricFields.map((f) => DropdownMenuItem(
                                value: f.id,
                                child: Text(f.label.isNotEmpty ? f.label : f.id, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedMetric = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Aggregation mode & Min Entries
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _aggregateMode,
                        decoration: InputDecoration(
                          labelText: 'Aggregation',
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'avg', child: Text('Average')),
                          DropdownMenuItem(value: 'median', child: Text('Median')),
                          DropdownMenuItem(value: 'latest', child: Text('Latest')),
                          DropdownMenuItem(value: 'max', child: Text('Max')),
                          DropdownMenuItem(value: 'min', child: Text('Min')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _aggregateMode = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: _minEntries,
                        decoration: InputDecoration(
                          labelText: 'Min Entries',
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1+')),
                          DropdownMenuItem(value: 2, child: Text('2+')),
                          DropdownMenuItem(value: 3, child: Text('3+')),
                          DropdownMenuItem(value: 5, child: Text('5+')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _minEntries = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Reset button
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset Config'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.lightGreenAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${rankings.length} ranked',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.lightGreenAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Tabs: Team Rankings vs Entry List
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x601E293B) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.lightGreenAccent.withOpacity(0.2),
                border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.6)),
              ),
              labelColor: Colors.lightGreenAccent,
              unselectedLabelColor: secondaryTextColor,
              tabs: const [
                Tab(icon: Icon(Icons.leaderboard_rounded, size: 18), text: 'Team Rankings'),
                Tab(icon: Icon(Icons.list_alt_rounded, size: 18), text: 'Entry List'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Tab Content
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index == 0) {
                // Team Rankings View
                if (rankings.isEmpty) {
                  return ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text('No teams meet the ranking criteria.', style: TextStyle(color: secondaryTextColor)),
                      ),
                    ),
                  );
                }

                return Column(
                  children: rankings.map((team) {
                    final isSelected = _selectedRankedTeam?.teamNumber == team.teamNumber;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedRankedTeam = isSelected ? null : team;
                          });
                          _showTeamDrillDownBottomSheet(context, team);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x731E293B) : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.lightGreenAccent
                                  : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Rank badge
                              Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: team.rank <= 3
                                      ? Colors.amberAccent.withOpacity(0.2)
                                      : (isDark ? Colors.white10 : Colors.black12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: team.rank <= 3 ? Colors.amberAccent : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  '#${team.rank}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: team.rank <= 3 ? Colors.amberAccent : primaryTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Team ${team.teamNumber}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    Text(
                                      '${team.nickname} • ${team.entryCount} entries',
                                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              // Trend
                              _buildTrendIcon(team.trend),
                              const SizedBox(width: 10),
                              // Score Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.lightGreenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.4)),
                                ),
                                child: Text(
                                  team.score.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.lightGreenAccent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white38),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              } else {
                // Entry List View
                if (entries.isEmpty) {
                  return ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text('No qualitative entries match filters.', style: TextStyle(color: secondaryTextColor)),
                      ),
                    ),
                  );
                }

                return Column(
                  children: entries.map((entry) {
                    final isSelected = _selectedEntry?.id == entry.id;
                    final teamObj = _teamsByNumber[entry.targetTeamNumber];
                    final metricVal = _extractMetricValue(entry.data, _selectedMetric);
                    final conflicts = _getConflictingRecordsFor(entry);
                    final hasConflict = conflicts.length > 1;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedEntry = isSelected ? null : entry;
                          });
                          _showQualEntryDetailBottomSheet(context, entry);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x731E293B) : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: hasConflict
                                  ? Colors.amberAccent.withOpacity(0.7)
                                  : (isSelected
                                      ? Colors.lightGreenAccent
                                      : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08))),
                              width: hasConflict || isSelected ? 1.8 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.lightGreenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  entry.matchNumber != null ? 'M${entry.matchNumber}' : 'QUAL',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.lightGreenAccent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Team ${entry.targetTeamNumber}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    Text(
                                      teamObj?.nickname ?? 'Event: ${entry.eventKey}',
                                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (hasConflict) ...[
                                InkWell(
                                  onTap: () => _openConflictResolver(entry),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amberAccent),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amberAccent),
                                        SizedBox(width: 4),
                                        Text(
                                          'Resolve',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amberAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Score: ${metricVal.toStringAsFixed(1)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white38),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIcon(String trend) {
    switch (trend) {
      case 'improving':
        return const Tooltip(
          message: 'Performance improving',
          child: Icon(Icons.trending_up_rounded, color: Colors.greenAccent, size: 20),
        );
      case 'declining':
        return const Tooltip(
          message: 'Performance declining',
          child: Icon(Icons.trending_down_rounded, color: Colors.redAccent, size: 20),
        );
      case 'steady':
      default:
        return const Tooltip(
          message: 'Consistent score',
          child: Icon(Icons.trending_flat_rounded, color: Colors.white38, size: 20),
        );
    }
  }

  void _showTeamDrillDownBottomSheet(BuildContext context, QualRankedTeam team) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF50F172A) : const Color(0xF8F8FAFC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.lightGreenAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.rate_review_rounded, color: Colors.lightGreenAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Team ${team.teamNumber} Breakdown',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                '${team.nickname} • Rank #${team.rank} (${team.score.toStringAsFixed(1)} score)',
                                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      children: [
                        Text(
                          'Scouted Matches (${team.entries.length})',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 10),
                        ...team.entries.map((entry) {
                          final score = _extractMetricValue(entry.data, _selectedMetric);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      entry.matchNumber != null ? 'Match ${entry.matchNumber}' : 'Qual Entry',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Rating: ${score.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.lightGreenAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                if (entry.scoutUsername != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Scouted by: ${entry.scoutUsername}', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                ],
                                const SizedBox(height: 8),
                                ...entry.data.entries.map((d) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(d.key, style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                        Text(_formatVal(d.value), style: TextStyle(color: primaryTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showQualEntryDetailBottomSheet(BuildContext context, QualScoutingRecord entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        final teamObj = _teamsByNumber[entry.targetTeamNumber];

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF50F172A) : const Color(0xF8F8FAFC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.lightGreenAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.rate_review_rounded, color: Colors.lightGreenAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Team ${entry.targetTeamNumber} Qualitative',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                teamObj?.nickname ?? 'Event: ${entry.eventKey}',
                                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      children: [
                        if (_getConflictingRecordsFor(entry).length > 1)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 22),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Multiple qualitative submissions exist for this team and match.',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amberAccent,
                                    foregroundColor: Colors.black87,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _openConflictResolver(entry);
                                  },
                                  icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                                  label: const Text('Resolve'),
                                ),
                              ],
                            ),
                          ),

                        // Metadata card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (entry.matchNumber != null)
                                _buildDetailRow('Match Number', 'Match ${entry.matchNumber}', primaryTextColor, secondaryTextColor),
                              _buildDetailRow('Event Key', entry.eventKey, primaryTextColor, secondaryTextColor),
                              if (entry.scoutUsername != null)
                                _buildDetailRow('Scouted By', entry.scoutUsername!, primaryTextColor, secondaryTextColor),
                              if (entry.createdAt != null)
                                _buildDetailRow('Timestamp', entry.createdAt!, primaryTextColor, secondaryTextColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Observed Qualitative Metrics',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 10),

                        if (_qualConfig != null && _qualConfig!.fields.isNotEmpty)
                          ..._qualConfig!.fields.map((f) {
                            final val = entry.data[f.id];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      f.label.isNotEmpty ? f.label : f.id,
                                      style: TextStyle(fontSize: 13, color: primaryTextColor),
                                    ),
                                  ),
                                  Text(
                                    _formatVal(val),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.lightGreenAccent,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        else
                          ...entry.data.entries.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(item.key, style: TextStyle(fontWeight: FontWeight.w600, color: primaryTextColor)),
                                  Text(
                                    _formatVal(item.value),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.lightGreenAccent),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
          Text(value, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatVal(dynamic val) {
    if (val == null) return '--';
    if (val is bool) return val ? 'Yes' : 'No';
    if (val is List) return val.join(', ');
    return val.toString();
  }

  Widget _buildMetricTile(String title, String value, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x521E293B) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
