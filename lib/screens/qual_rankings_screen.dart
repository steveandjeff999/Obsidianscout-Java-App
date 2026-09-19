import 'dart:math';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_glass_card.dart';
import 'team_details_screen.dart';

class QualRankingsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const QualRankingsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<QualRankingsScreen> createState() => _QualRankingsScreenState();
}

class _QualRankingMetric {
  final String id;
  final String label;
  final ScoutingFieldModel? field;

  _QualRankingMetric({
    required this.id,
    required this.label,
    this.field,
  });
}

class _TeamQualScore {
  final TeamModel team;
  final Map<String, double?> scores;
  final int entriesCount;
  final List<String> roles;

  _TeamQualScore({
    required this.team,
    required this.scores,
    required this.entriesCount,
    required this.roles,
  });
}

class _QualRankingsScreenState extends State<QualRankingsScreen> {
  ScoutingConfigModel? _qualConfig;
  List<ScoutingFieldModel> _metricFields = [];
  List<_QualRankingMetric> _rankingMetrics = [];
  List<EventModel> _events = [];
  List<TeamModel> _teams = [];
  List<Map<String, dynamic>> _rawEntries = [];

  String _selectedEventKey = 'all';
  String _selectedMetric = 'all_metrics'; // 'all_metrics', '__composite__', or fieldId
  String _activeSortMetric = '__composite__';
  String _aggregateMode = 'avg'; // 'avg', 'median', 'latest', 'max', 'min'
  bool _sortAsc = false;
  final List<String> _selectedRoles = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant QualRankingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Hydration
    final cachedSettings = await widget.apiService.getCachedSettings();
    final cachedQualCfg = await widget.apiService.getCachedQualConfig();
    final cachedQualRaw = await widget.apiService.getCachedQualScoutingEntries();
    final cachedEvents = await widget.apiService.getCachedEvents(year: cachedSettings?.year);
    final cachedTeams = await widget.apiService.getCachedTeams(cachedSettings?.eventKey);

    if (mounted && (cachedQualRaw.isNotEmpty || cachedTeams.isNotEmpty)) {
      setState(() {
        _qualConfig = cachedQualCfg;
        _setupMetrics(cachedQualCfg);
        _events = cachedEvents;
        _teams = cachedTeams;
        _rawEntries = cachedQualRaw.whereType<Map<String, dynamic>>().toList();
        if (_selectedEventKey == 'all' && cachedSettings?.eventKey != null && cachedSettings!.eventKey.isNotEmpty) {
          _selectedEventKey = cachedSettings.eventKey;
        }
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation
    try {
      final settings = await widget.apiService.fetchSettings();
      final currentYear = settings?.year ?? DateTime.now().year;

      final results = await Future.wait([
        widget.apiService.fetchQualConfig(),
        widget.apiService.fetchQualScoutingEntries(),
        widget.apiService.fetchEvents(year: currentYear),
        widget.apiService.fetchTeams(
          (_selectedEventKey != 'all' && _selectedEventKey != 'prescout') ? _selectedEventKey : settings?.eventKey,
        ),
      ]);

      if (mounted) {
        setState(() {
          _qualConfig = results[0] as ScoutingConfigModel?;
          _setupMetrics(_qualConfig);
          final raw = results[1] as List<dynamic>;
          _rawEntries = raw.whereType<Map<String, dynamic>>().toList();
          _events = results[2] as List<EventModel>;
          _teams = results[3] as List<TeamModel>;
          if (_selectedEventKey == 'all' && settings?.eventKey != null && settings!.eventKey.isNotEmpty) {
            _selectedEventKey = settings.eventKey;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupMetrics(ScoutingConfigModel? config) {
    if (config == null) return;
    final validFields = config.fields.where((f) {
      return f.type != 'section' &&
          !['eventKey', 'matchKey', 'matchNumber', 'targetTeamNumber'].contains(f.id);
    }).toList();

    _metricFields = validFields.where((f) {
      return ['rating', 'number', 'counter', 'checkbox', 'select'].contains(f.type);
    }).toList();

    _rankingMetrics = [
      _QualRankingMetric(
        id: '__composite__',
        label: 'Composite average',
      ),
      ..._metricFields.map((f) => _QualRankingMetric(
            id: f.id,
            label: f.label.isNotEmpty ? f.label : f.id,
            field: f,
          )),
    ];
  }

  double? _extractFieldValue(ScoutingFieldModel? field, dynamic rawValue) {
    if (rawValue == null || rawValue == '') return null;
    if (field == null) {
      if (rawValue is num) return rawValue.toDouble();
      return double.tryParse(rawValue.toString());
    }

    if (field.type == 'checkbox') {
      return (rawValue == true || rawValue == 1 || rawValue == 'true') ? 1.0 : 0.0;
    }
    if (field.type == 'select') {
      final options = field.options;
      final idx = options.indexWhere((opt) => opt.value == rawValue || opt.label == rawValue);
      if (idx >= 0) return (idx + 1).toDouble();
      if (rawValue is num) return rawValue.toDouble();
      return double.tryParse(rawValue.toString());
    }
    if (field.type == 'rating' || field.type == 'number' || field.type == 'counter') {
      if (rawValue is num) return rawValue.toDouble();
      return double.tryParse(rawValue.toString());
    }
    if (rawValue is num) return rawValue.toDouble();
    return double.tryParse(rawValue.toString());
  }

  double? _calculateAggregate(List<double> values, String mode) {
    if (values.isEmpty) return null;
    switch (mode) {
      case 'median':
        final sorted = List<double>.from(values)..sort();
        final mid = sorted.length ~/ 2;
        if (sorted.length % 2 == 0) {
          return (sorted[mid - 1] + sorted[mid]) / 2.0;
        }
        return sorted[mid];
      case 'latest':
        return values.last;
      case 'max':
        return values.reduce(max);
      case 'min':
        return values.reduce(min);
      case 'avg':
      default:
        return values.reduce((a, b) => a + b) / values.length;
    }
  }

  List<_TeamQualScore> _calculateTeamScores() {
    // Filter raw entries based on selected event
    final filteredEntries = _rawEntries.where((e) {
      final isPrescout = e['isPrescout'] == true;
      if (_selectedEventKey == 'prescout') return isPrescout;
      if (_selectedEventKey != 'all') {
        return e['eventKey'] == _selectedEventKey && !isPrescout;
      }
      return true;
    }).toList();

    // Group entries by team number
    final Map<int, List<Map<String, dynamic>>> entriesByTeam = {};
    for (final e in filteredEntries) {
      final teamNum = (e['targetTeamNumber'] as num?)?.toInt();
      if (teamNum != null && teamNum > 0) {
        entriesByTeam.putIfAbsent(teamNum, () => []).add(e);
      }
    }

    // Map all known teams or teams present in scouting entries
    final Set<int> allTeamNumbers = {
      ..._teams.map((t) => t.teamNumber),
      ...entriesByTeam.keys,
    };

    final List<_TeamQualScore> results = [];

    for (final teamNum in allTeamNumbers) {
      final team = _teams.firstWhere(
        (t) => t.teamNumber == teamNum,
        orElse: () => TeamModel(eventKey: _selectedEventKey, teamKey: 'frc$teamNum', teamNumber: teamNum),
      );

      final teamEntries = entriesByTeam[teamNum] ?? [];
      final Map<String, double?> metricScores = {};

      // 1. Calculate each numeric field score
      for (final mf in _metricFields) {
        final List<double> values = [];
        for (final entry in teamEntries) {
          final data = entry['data'] as Map<String, dynamic>? ?? {};
          final val = _extractFieldValue(mf, data[mf.id]);
          if (val != null && !val.isNaN) values.add(val);
        }
        metricScores[mf.id] = _calculateAggregate(values, _aggregateMode);
      }

      // 2. Composite average across all numeric fields
      final List<double> compositeValues = [];
      for (final entry in teamEntries) {
        final data = entry['data'] as Map<String, dynamic>? ?? {};
        final List<double> entryNumericValues = [];
        for (final mf in _metricFields) {
          final val = _extractFieldValue(mf, data[mf.id]);
          if (val != null && !val.isNaN) entryNumericValues.add(val);
        }
        if (entryNumericValues.isNotEmpty) {
          compositeValues.add(entryNumericValues.reduce((a, b) => a + b) / entryNumericValues.length);
        }
      }
      metricScores['__composite__'] = _calculateAggregate(compositeValues, _aggregateMode);

      // 3. Extract distinct robot roles
      final Set<String> rolesSet = {};
      for (final entry in teamEntries) {
        final data = entry['data'] as Map<String, dynamic>? ?? {};
        final rolesList = data['robotRoles'];
        if (rolesList is List) {
          for (final r in rolesList) {
            if (r != null && r.toString().trim().isNotEmpty) {
              rolesSet.add(r.toString().trim());
            }
          }
        }
      }

      results.add(_TeamQualScore(
        team: team,
        scores: metricScores,
        entriesCount: teamEntries.length,
        roles: rolesSet.toList()..sort(),
      ));
    }

    // Role filter
    List<_TeamQualScore> filtered = results;
    if (_selectedRoles.isNotEmpty) {
      filtered = results.where((item) {
        return _selectedRoles.any((r) => item.roles.contains(r));
      }).toList();
    }

    // Search query filter
    final q = _searchQuery.toLowerCase().trim();
    if (q.isNotEmpty) {
      filtered = filtered.where((item) {
        return item.team.teamNumber.toString().contains(q) ||
            (item.team.nickname ?? '').toLowerCase().contains(q) ||
            (item.team.name ?? '').toLowerCase().contains(q);
      }).toList();
    }

    // Sort
    filtered.sort((a, b) {
      final valA = a.scores[_activeSortMetric];
      final valB = b.scores[_activeSortMetric];

      final hasA = valA != null && !valA.isNaN;
      final hasB = valB != null && !valB.isNaN;

      if (hasA && !hasB) return -1;
      if (!hasA && hasB) return 1;
      if (!hasA && !hasB) return a.team.teamNumber.compareTo(b.team.teamNumber);

      final comp = _sortAsc ? valA!.compareTo(valB!) : valB!.compareTo(valA!);
      if (comp != 0) return comp;
      return a.team.teamNumber.compareTo(b.team.teamNumber);
    });

    return filtered;
  }

  void _onSort(String metricId) {
    setState(() {
      if (_activeSortMetric == metricId) {
        _sortAsc = !_sortAsc;
      } else {
        _activeSortMetric = metricId;
        _sortAsc = false;
      }
      if (_selectedMetric != 'all_metrics') {
        _selectedMetric = metricId;
      }
    });
  }

  void _toggleRoleFilter(String role) {
    setState(() {
      if (role == 'all') {
        _selectedRoles.clear();
      } else {
        if (_selectedRoles.contains(role)) {
          _selectedRoles.remove(role);
        } else {
          _selectedRoles.add(role);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final showRoleFilter = _qualConfig?.enableRobotRoleCollection ?? false;

    final teamScores = _calculateTeamScores();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: ObsidianUITheme.primaryAccent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, isDesktop ? 16 : 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Robot Role Filter Section (if enabled in qual config)
                  if (showRoleFilter) ...[
                    ObsidianGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.filter_alt_outlined, size: 16, color: secondaryTextColor),
                                const SizedBox(width: 6),
                                Text(
                                  'FILTER BY ROBOT ROLE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildRoleChip('all', 'All Teams', Icons.grid_view_rounded),
                                _buildRoleChip('Cycling', 'Cycling', Icons.repeat_rounded),
                                _buildRoleChip('Stealing', 'Stealing', Icons.pan_tool_rounded),
                                _buildRoleChip('Scoring', 'Scoring', Icons.adjust_rounded),
                                _buildRoleChip('Feeding', 'Feeding', Icons.arrow_upward_rounded),
                                _buildRoleChip('Defending', 'Defending', Icons.shield_rounded),
                                _buildRoleChip('N/C', 'N/C', Icons.cancel_outlined),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Header & Controls Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.stars_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          context.tr('qual_rankings.title', 'Qualitative Rankings'),
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: primaryTextColor,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${teamScores.length} teams',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: ObsidianUITheme.primaryAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr('qual_rankings.notice', 'Rank teams based on qualitative metrics computed from scouting entries.'),
                                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Metric Selector
                              SizedBox(
                                width: 230,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('qual_rankings.metric', 'Qualitative Metric'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.getSurfaceColor(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedMetric,
                                          isExpanded: true,
                                          items: [
                                            DropdownMenuItem(
                                              value: 'all_metrics',
                                              child: Text(context.tr('qual_rankings.metric.all', 'All Metrics')),
                                            ),
                                            ..._rankingMetrics.map((m) {
                                              return DropdownMenuItem(
                                                value: m.id,
                                                child: Text(m.label, overflow: TextOverflow.ellipsis),
                                              );
                                            }),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _selectedMetric = val;
                                                _activeSortMetric = val == 'all_metrics' ? '__composite__' : val;
                                                _sortAsc = false;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Aggregation Selector
                              SizedBox(
                                width: 160,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('qual-data.aggregation', 'Aggregation'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.getSurfaceColor(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _aggregateMode,
                                          isExpanded: true,
                                          items: [
                                            DropdownMenuItem(value: 'avg', child: Text(context.tr('qual-data.average', 'Average'))),
                                            DropdownMenuItem(value: 'median', child: Text(context.tr('qual-data.median', 'Median'))),
                                            DropdownMenuItem(value: 'latest', child: Text(context.tr('qual-data.latest', 'Latest'))),
                                            DropdownMenuItem(value: 'max', child: Text(context.tr('settings.max', 'Max'))),
                                            DropdownMenuItem(value: 'min', child: Text(context.tr('settings.min', 'Min'))),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() => _aggregateMode = val);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Event filter dropdown
                              SizedBox(
                                width: 240,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('matches.view_event', 'View Event'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.getSurfaceColor(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedEventKey,
                                          isExpanded: true,
                                          items: [
                                            DropdownMenuItem(
                                              value: 'all',
                                              child: Text(context.tr('qual_data.all_events', 'All events')),
                                            ),
                                            ..._events.map((e) {
                                              return DropdownMenuItem(
                                                value: e.eventKey,
                                                child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                                              );
                                            }),
                                            const DropdownMenuItem(
                                              value: 'prescout',
                                              child: Text('Prescouting Data'),
                                            ),
                                          ],
                                          onChanged: (val) {
                                            if (val != null && val != _selectedEventKey) {
                                              setState(() {
                                                _selectedEventKey = val;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Search input
                              SizedBox(
                                width: 200,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Search',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Team # or name...',
                                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                        filled: true,
                                        fillColor: ObsidianUITheme.getSurfaceColor(context),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: borderColor),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      onChanged: (val) => setState(() => _searchQuery = val),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Rankings Table / List Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isLoading && _rawEntries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                              ),
                            )
                          else if (teamScores.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No teams or qualitative entries found',
                                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                                ),
                              ),
                            )
                          else if (isDesktop)
                            _buildDesktopTable(teamScores)
                          else
                            _buildMobileList(teamScores),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleChip(String roleId, String label, IconData icon) {
    final isSelected = roleId == 'all'
        ? _selectedRoles.isEmpty
        : _selectedRoles.contains(roleId);

    return InkWell(
      onTap: () => _toggleRoleFilter(roleId),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)
              : ObsidianUITheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? ObsidianUITheme.primaryAccent
                : ObsidianUITheme.getBorderColor(context),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_QualRankingMetric> get _renderedMetrics {
    if (_selectedMetric == 'all_metrics') {
      return _rankingMetrics;
    }
    final found = _rankingMetrics.where((m) => m.id == _selectedMetric).toList();
    return found.isNotEmpty ? found : _rankingMetrics;
  }

  Widget _buildDesktopTable(List<_TeamQualScore> teams) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final showRoles = _qualConfig?.enableRobotRoleCollection ?? false;
    final metrics = _renderedMetrics;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: max(800, 300 + metrics.length * 150 + (showRoles ? 240 : 0))),
        child: DataTable(
          headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 13),
          dataTextStyle: TextStyle(color: primaryTextColor, fontSize: 13),
          dividerThickness: 0.5,
          horizontalMargin: 12,
          columnSpacing: 24,
          columns: [
            DataColumn(
              label: InkWell(
                onTap: () => _onSort('__composite__'),
                child: Row(
                  children: [
                    Text('Rank', style: TextStyle(fontWeight: _activeSortMetric == '__composite__' ? FontWeight.bold : FontWeight.w600)),
                    if (_activeSortMetric == '__composite__')
                      Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                  ],
                ),
              ),
            ),
            const DataColumn(label: Text('TEAM')),
            ...metrics.map((m) {
              return DataColumn(
                label: InkWell(
                  onTap: () => _onSort(m.id),
                  child: Row(
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          color: _activeSortMetric == m.id ? ObsidianUITheme.primaryAccent : primaryTextColor,
                          fontWeight: _activeSortMetric == m.id ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      if (_activeSortMetric == m.id)
                        Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                    ],
                  ),
                ),
              );
            }),
            if (showRoles) const DataColumn(label: Text('APPEARANCES')),
            if (showRoles) const DataColumn(label: Text('ROLES')),
          ],
          rows: teams.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;

            return DataRow(
              cells: [
                DataCell(_buildRankBadge(index + 1)),
                DataCell(
                  InkWell(
                    onTap: () => _openTeamDetails(item.team),
                    child: Text(
                      'Team ${item.team.teamNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                    ),
                  ),
                ),
                ...metrics.map((m) {
                  final score = item.scores[m.id];
                  if (score != null && !score.isNaN) {
                    final maxVal = (m.field?.max != null && m.field!.max! > 0) ? m.field!.max!.toDouble() : 5.0;
                    final pct = (score / maxVal).clamp(0.0, 1.0);

                    return DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 38,
                            child: Text(
                              score.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 60,
                            height: 6,
                            decoration: BoxDecoration(
                              color: ObsidianUITheme.getSurfaceColor(context),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 60 * pct,
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.primaryAccent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return DataCell(Text('—', style: TextStyle(color: secondaryTextColor)));
                }),
                if (showRoles)
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.entriesCount} times',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                      ),
                    ),
                  ),
                if (showRoles)
                  DataCell(
                    item.roles.isNotEmpty
                        ? Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: item.roles.map((r) => _buildRoleBadge(r)).toList(),
                          )
                        : Text('None', style: TextStyle(fontStyle: FontStyle.italic, color: secondaryTextColor, fontSize: 11)),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(List<_TeamQualScore> teams) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final metrics = _renderedMetrics;
    final showRoles = _qualConfig?.enableRobotRoleCollection ?? false;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teams.length,
      separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
      itemBuilder: (ctx, index) {
        final item = teams[index];
        final primaryScore = item.scores[_activeSortMetric] ?? item.scores['__composite__'];

        return InkWell(
          onTap: () => _openTeamDetails(item.team),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildRankBadge(index + 1),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Team ${item.team.teamNumber}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                      ),
                    ),
                    if (primaryScore != null && !primaryScore.isNaN) ...[
                      Text(
                        primaryScore.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ObsidianUITheme.primaryAccent),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded, size: 16, color: Colors.amberAccent),
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: secondaryTextColor),
                  ],
                ),
                const SizedBox(height: 8),

                // Metrics summary wrap
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: metrics.map((m) {
                    final s = item.scores[m.id];
                    if (s == null || s.isNaN) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${m.label}: ', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                        Text(s.toStringAsFixed(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor)),
                      ],
                    );
                  }).toList(),
                ),

                if (showRoles && (item.roles.isNotEmpty || item.entriesCount > 0)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.entriesCount} entries',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: item.roles.map((r) => _buildRoleBadge(r)).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color = Colors.cyanAccent;
    final rLower = role.toLowerCase();
    if (rLower.contains('cycl')) {
      color = Colors.lightGreenAccent;
    } else if (rLower.contains('steal')) {
      color = Colors.orangeAccent;
    } else if (rLower.contains('scor')) {
      color = Colors.amberAccent;
    } else if (rLower.contains('feed')) {
      color = Colors.cyanAccent;
    } else if (rLower.contains('defend')) {
      color = Colors.redAccent;
    } else if (rLower.contains('n/c')) {
      color = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        role,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Color bg = Colors.transparent;
    Color border = ObsidianUITheme.getBorderColor(context);
    Color textColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (rank == 1) {
      bg = const Color(0xFFFFD700).withValues(alpha: 0.2);
      border = const Color(0xFFFFD700);
      textColor = const Color(0xFFFFD700);
    } else if (rank == 2) {
      bg = const Color(0xFFC0C0C0).withValues(alpha: 0.2);
      border = const Color(0xFFC0C0C0);
      textColor = const Color(0xFFC0C0C0);
    } else if (rank == 3) {
      bg = const Color(0xFFCD7F32).withValues(alpha: 0.2);
      border = const Color(0xFFCD7F32);
      textColor = const Color(0xFFCD7F32);
    }

    return Container(
      width: 32,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        '#$rank',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: textColor),
      ),
    );
  }

  void _openTeamDetails(TeamModel team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => TeamDetailsScreen(
          team: team,
          apiService: widget.apiService,
          eventKey: (_selectedEventKey != 'all' && _selectedEventKey != 'prescout') ? _selectedEventKey : null,
        ),
      ),
    );
  }
}
