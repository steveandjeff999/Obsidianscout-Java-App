import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/share_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_glass_app_bar.dart';

class SharedViewScreen extends StatefulWidget {
  final ApiService apiService;
  final String token;

  const SharedViewScreen({
    super.key,
    required this.apiService,
    required this.token,
  });

  @override
  State<SharedViewScreen> createState() => _SharedViewScreenState();
}

class _SharedViewScreenState extends State<SharedViewScreen> {
  bool _isLoading = true;
  ResolvedSharePayload? _payload;
  final TextEditingController _pinController = TextEditingController();
  bool _isVerifyingPin = false;

  // Graph Viewer State
  Set<int> _selectedTeams = {};
  Set<String> _selectedGraphTypes = {'bar'};
  String _datasource = 'scouted';
  String _dataView = 'averages';
  String _sort = 'value_desc';
  bool _includePrescout = false;
  String _selectedMetricId = 'score_total';
  String _teamSearch = '';

  // All Data Viewer State
  String _dataSearchQuery = '';
  String _dataTypeFilter = 'all';
  String _dataSortBy = 'match-type';

  @override
  void initState() {
    super.initState();
    _loadPayload();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadPayload([String? pin]) async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.resolveSharedLink(widget.token, pin: pin);
      if (mounted) {
        setState(() {
          _payload = res;
          _isLoading = false;
          _initializeViewerState(res);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _initializeViewerState(ResolvedSharePayload? payload) {
    if (payload == null) return;
    Map<String, dynamic> queryConfig = {};
    Map<String, dynamic> snapshotData = {};

    try {
      if (payload.queryConfigJson.isNotEmpty) {
        queryConfig = jsonDecode(payload.queryConfigJson);
      }
    } catch (_) {}

    try {
      if (payload.snapshotDataJson != null && payload.snapshotDataJson!.isNotEmpty) {
        snapshotData = jsonDecode(payload.snapshotDataJson!);
      }
    } catch (_) {}

    final dataObj = snapshotData.isNotEmpty ? snapshotData : queryConfig;

    _datasource = (dataObj['datasource'] as String?) ?? 'scouted';
    _dataView = (dataObj['dataView'] as String?) ?? 'averages';
    _sort = (dataObj['sort'] as String?) ?? 'value_desc';
    _includePrescout = (dataObj['includePrescout'] as bool?) ?? false;
    _selectedMetricId = (dataObj['metricId'] as String?) ?? (dataObj['metric'] as String?) ?? 'score_total';

    final teamsList = (dataObj['selectedTeams'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [];
    if (teamsList.isNotEmpty) {
      _selectedTeams = teamsList.toSet();
    } else {
      final entries = (dataObj['entries'] as List<dynamic>?) ?? [];
      final tSet = <int>{};
      for (final e in entries) {
        if (e is Map<String, dynamic>) {
          final tNum = (e['targetTeamNumber'] as num?)?.toInt() ?? (e['teamNumber'] as num?)?.toInt();
          if (tNum != null && tNum > 0) tSet.add(tNum);
        }
      }
      _selectedTeams = tSet;
    }

    final gtList = (dataObj['selectedGraphTypes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        (dataObj['graphTypes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        ['bar'];
    if (gtList.isNotEmpty) {
      _selectedGraphTypes = gtList.toSet();
    }
  }

  Future<void> _handlePinSubmit() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;

    setState(() => _isVerifyingPin = true);
    try {
      final res = await widget.apiService.verifySharedPin(widget.token, pin);
      if (mounted) {
        setState(() {
          _payload = res;
          _isVerifyingPin = false;
          _initializeViewerState(res);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifyingPin = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shares.title')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_payload == null) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shares.title')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(context.tr('shared_viewer.link_not_found_desc'), style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _loadPayload(),
                  child: Text(context.tr('common.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_payload!.isRevoked) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shares.title')),
        body: _buildErrorBanner(context.tr('shared_viewer.link_revoked_desc')),
      );
    }

    if (_payload!.isExpired) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shares.title')),
        body: _buildErrorBanner(context.tr('shared_viewer.link_expired_desc')),
      );
    }

    if (_payload!.requiresPin && !_payload!.pinVerified) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shared_viewer.pin_required_title')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ObsidianGlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48, color: Colors.amber),
                    const SizedBox(height: 16),
                    Text(context.tr('shared_viewer.pin_required_title'), style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      _payload!.errorMessage ?? context.tr('shared_viewer.pin_prompt'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, letterSpacing: 6),
                      decoration: InputDecoration(
                        hintText: context.tr('shared_viewer.pin_placeholder'),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _handlePinSubmit(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: _isVerifyingPin
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_open),
                      label: Text(context.tr('shared_viewer.pin_submit')),
                      onPressed: _isVerifyingPin ? null : _handlePinSubmit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!_payload!.isAllowed) {
      return Scaffold(
        appBar: ObsidianGlassAppBar(title: context.tr('shares.title')),
        body: _buildErrorBanner(_payload!.errorMessage ?? context.tr('shared_viewer.team_restricted_desc')),
      );
    }

    return Scaffold(
      appBar: ObsidianGlassAppBar(
        title: _payload!.title,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadPayload(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _payload!.accessScope.toUpperCase(),
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _payload!.shareMode == 'frozen_snapshot' ? 'SNAPSHOT' : 'LIVE FEED',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _payload!.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_payload!.description != null && _payload!.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_payload!.description!, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                Text(
                  'Shared by Team ${_payload!.ownerTeamNumber} (${_payload!.program}) • Event: ${_payload!.targetEventKey ?? "All"}',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Render Full Counterpart Page
          _buildCounterpartPage(theme),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterpartPage(ThemeData theme) {
    Map<String, dynamic> snapshotData = {};
    Map<String, dynamic> queryConfig = {};

    try {
      if (_payload!.snapshotDataJson != null && _payload!.snapshotDataJson!.isNotEmpty) {
        snapshotData = jsonDecode(_payload!.snapshotDataJson!);
      }
    } catch (_) {}

    try {
      if (_payload!.queryConfigJson.isNotEmpty) {
        queryConfig = jsonDecode(_payload!.queryConfigJson);
      }
    } catch (_) {}

    final dataObj = snapshotData.isNotEmpty ? snapshotData : queryConfig;

    if (_payload!.resourceType == 'graph') {
      return _buildSharedGraphsView(theme, dataObj);
    } else if (_payload!.resourceType == 'all_data' || _payload!.resourceType == 'data') {
      return _buildSharedAllDataView(theme, dataObj);
    } else if (_payload!.resourceType == 'predictor' || _payload!.resourceType == 'event_predictor') {
      return _buildSharedPredictorView(theme, dataObj);
    } else if (_payload!.resourceType == 'custom_analytics') {
      return _buildSharedCustomAnalyticsView(theme, dataObj);
    } else {
      return _buildSharedAllDataView(theme, dataObj);
    }
  }

  // ==========================================================================
  // GRAPHS DASHBOARD VIEW (Identical to GraphsScreen)
  // ==========================================================================
  Widget _buildSharedGraphsView(ThemeData theme, Map<String, dynamic> dataObj) {
    final rawEntries = (dataObj['entries'] as List<dynamic>?) ?? [];
    final rawTeams = (dataObj['teams'] as List<dynamic>?) ?? [];
    final statsHistory = (dataObj['statsHistory'] as Map<String, dynamic>?) ?? {};
    final settings = (dataObj['settings'] as Map<String, dynamic>?) ?? {};

    final isFtc = (settings['program'] as String?)?.toUpperCase() == 'FTC';
    final effectiveUseEpa = !isFtc && (settings['useStatboticsEpa'] == true || rawTeams.any((t) => (t['epa'] as num?) != null && (t['epa'] as num) > 0) || (statsHistory['epaHistory'] is List && (statsHistory['epaHistory'] as List).isNotEmpty));
    final effectiveUseExp = !isFtc && (settings['useMatch13Exp'] == true || (statsHistory['match13History'] is List && (statsHistory['match13History'] as List).isNotEmpty) || rawTeams.any((t) => ((t['exp'] as num?) != null && (t['exp'] as num) > 0) || ((t['match13Exp'] as num?) != null && (t['match13Exp'] as num) > 0)));
    final effectiveUseOpr = settings['useTbaOpr'] == true || rawTeams.any((t) => (t['opr'] as num?) != null && (t['opr'] as num) > 0) || (statsHistory['oprs'] is Map && (statsHistory['oprs'] as Map).isNotEmpty);
    final showDatasource = effectiveUseEpa || effectiveUseExp || effectiveUseOpr;

    final allTeamNumbers = <int>{};
    for (final t in rawTeams) {
      if (t is Map<String, dynamic>) {
        final tNum = (t['teamNumber'] as num?)?.toInt();
        if (tNum != null) allTeamNumbers.add(tNum);
      }
    }
    for (final e in rawEntries) {
      if (e is Map<String, dynamic>) {
        final tNum = (e['targetTeamNumber'] as num?)?.toInt() ?? (e['teamNumber'] as num?)?.toInt();
        if (tNum != null && tNum > 0) allTeamNumbers.add(tNum);
      }
    }
    final sortedAllTeams = allTeamNumbers.toList()..sort();

    final filteredTeamNumbers = sortedAllTeams.where((t) {
      final q = _teamSearch.toLowerCase().trim();
      return q.isEmpty || t.toString().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Summary Stats
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('dashboard.data_summary').toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statChip(context.tr('dashboard.entries'), '${rawEntries.length}', Icons.description_rounded),
                  _statChip(context.tr('dashboard.teams'), '${sortedAllTeams.length}', Icons.group_rounded),
                  _statChip(context.tr('dashboard.matches'), '${rawEntries.map((e) => e['matchNumber']).whereType<int>().toSet().length}', Icons.sports_esports_rounded),
                  _statChip(context.tr('dashboard.events'), '1', Icons.event_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Team Selection Card
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.tr('graphs.team_selection').toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.warningOrange, letterSpacing: 1.0)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedTeams.isNotEmpty ? '${_selectedTeams.length} selected' : 'No teams selected',
                      style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: context.tr('all-data.search_teams'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _teamSearch = v),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: Text(context.tr('graphs.select_all')),
                    onPressed: () => setState(() => _selectedTeams = sortedAllTeams.toSet()),
                  ),
                  ActionChip(
                    label: Text(context.tr('graphs.select_top')),
                    onPressed: () => setState(() => _selectedTeams = sortedAllTeams.take(8).toSet()),
                  ),
                  ActionChip(
                    label: Text(context.tr('graphs.clear_all')),
                    onPressed: () => setState(() => _selectedTeams.clear()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_selectedTeams.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (_selectedTeams.toList()..sort()).map((teamNum) {
                    return Chip(
                      label: Text('Team $teamNum', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                      onDeleted: () => setState(() => _selectedTeams.remove(teamNum)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredTeamNumbers.length,
                  itemBuilder: (ctx, idx) {
                    final tNum = filteredTeamNumbers[idx];
                    final isChecked = _selectedTeams.contains(tNum);
                    return CheckboxListTile(
                      dense: true,
                      title: Text('Team $tNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      value: isChecked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedTeams.add(tNum);
                          } else {
                            _selectedTeams.remove(tNum);
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
        const SizedBox(height: 16),

        // 3. Graph Options Card
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('graphs.graph_options').toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0)),
              const SizedBox(height: 12),
              if (showDatasource) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _datasource,
                  decoration: InputDecoration(
                    labelText: context.tr('predictor.data_source'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Sources')),
                    const DropdownMenuItem(value: 'scouted', child: Text('Scouted Data')),
                    if (effectiveUseEpa) const DropdownMenuItem(value: 'epa', child: Text('Statbotics EPA')),
                    if (effectiveUseExp) const DropdownMenuItem(value: 'exp', child: Text('Match 13 EXP')),
                    if (effectiveUseOpr) DropdownMenuItem(value: 'opr', child: Text(isFtc ? 'FTC Scout OPR' : 'TBA OPR')),
                  ],
                  onChanged: (v) => setState(() => _datasource = v ?? 'scouted'),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedMetricId,
                decoration: InputDecoration(
                  labelText: context.tr('graphs.metric'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'score_total', child: Text('Total Score (Estimated)')),
                  DropdownMenuItem(value: 'teleop_score', child: Text('Teleop Score')),
                  DropdownMenuItem(value: 'auto_score', child: Text('Auto Score')),
                  DropdownMenuItem(value: 'endgame_score', child: Text('Endgame Score')),
                ],
                onChanged: (v) => setState(() => _selectedMetricId = v ?? 'score_total'),
              ),
              const SizedBox(height: 12),
              if (_datasource == 'scouted' || _datasource == 'exp' || _datasource == 'all') ...[
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'averages', label: Text(context.tr('graphs.team_averages'))),
                    ButtonSegment(value: 'matches', label: Text(context.tr('graphs.match_by_match'))),
                  ],
                  selected: {_dataView},
                  onSelectionChanged: (s) => setState(() => _dataView = s.first),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _sort,
                decoration: InputDecoration(
                  labelText: context.tr('graphs.sort_teams'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'value_desc', child: Text('Value: High → Low')),
                  DropdownMenuItem(value: 'value_asc', child: Text('Value: Low → High')),
                  DropdownMenuItem(value: 'team_asc', child: Text('Team # Low → High')),
                  DropdownMenuItem(value: 'team_desc', child: Text('Team # High → Low')),
                ],
                onChanged: (v) => setState(() => _sort = v ?? 'value_desc'),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('graphs.include_prescout'), style: const TextStyle(fontSize: 13)),
                value: _includePrescout,
                onChanged: (v) => setState(() => _includePrescout = v ?? false),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['bar', 'line', 'scatter', 'area', 'box', 'violin', 'histogram'].map((gt) {
                  final active = _selectedGraphTypes.contains(gt);
                  return FilterChip(
                    label: Text(gt.toUpperCase(), style: const TextStyle(fontSize: 12)),
                    selected: active,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          _selectedGraphTypes.add(gt);
                        } else if (_selectedGraphTypes.length > 1) {
                          _selectedGraphTypes.remove(gt);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Generated Graphs Output
        ..._buildRenderedGraphs(theme, rawEntries, rawTeams, statsHistory),
      ],
    );
  }

  List<Widget> _buildRenderedGraphs(ThemeData theme, List<dynamic> entries, List<dynamic> teams, Map<String, dynamic> statsHistory) {
    if (_selectedTeams.isEmpty) {
      return [
        ObsidianGlassCard(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(context.tr('graphs.select_team_prompt'))),
        )
      ];
    }

    final widgets = <Widget>[];

    for (final gt in _selectedGraphTypes) {
      widgets.add(
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${gt.toUpperCase()} — ${_dataView == 'averages' ? 'Team Averages' : 'Match-by-match'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: _buildSingleFlChart(gt, entries, teams, statsHistory),
              ),
            ],
          ),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    return widgets;
  }

  Widget _buildSingleFlChart(String graphType, List<dynamic> entries, List<dynamic> teams, Map<String, dynamic> statsHistory) {
    final sortedTeams = _selectedTeams.toList()..sort();

    if (_dataView == 'averages') {
      final barGroups = <BarChartGroupData>[];
      for (int i = 0; i < sortedTeams.length; i++) {
        final tNum = sortedTeams[i];
        double val = 0.0;

        if (_datasource == 'epa') {
          final tObj = teams.firstWhere((t) => t['teamNumber'] == tNum, orElse: () => {});
          val = ((tObj['epa'] as num?) ?? (tObj['statboticsEpa'] as num?) ?? 0.0).toDouble();
        } else if (_datasource == 'opr') {
          final tObj = teams.firstWhere((t) => t['teamNumber'] == tNum, orElse: () => {});
          val = ((tObj['opr'] as num?) ?? 0.0).toDouble();
          if (val == 0.0) {
            final oprs = (statsHistory['oprs'] as Map<String, dynamic>?) ?? {};
            val = ((oprs['$tNum'] as num?) ?? (oprs['frc$tNum'] as num?) ?? (oprs['ftc$tNum'] as num?) ?? 0.0).toDouble();
          }
        } else if (_datasource == 'exp') {
          final tObj = teams.firstWhere((t) => t['teamNumber'] == tNum, orElse: () => {});
          val = ((tObj['exp'] as num?) ?? (tObj['match13Exp'] as num?) ?? (tObj['match13_exp'] as num?) ?? 0.0).toDouble();
        } else {
          final teamEntries = entries.where((e) => (e['targetTeamNumber'] ?? e['teamNumber']) == tNum).toList();
          if (teamEntries.isNotEmpty) {
            val = teamEntries.length.toDouble() * 10.0;
          }
        }

        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: max(val, 0.5),
                color: ObsidianUITheme.primaryAccent,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }

      return BarChart(
        BarChartData(
          barGroups: barGroups,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < sortedTeams.length) {
                    return Text('#${sortedTeams[idx]}', style: const TextStyle(fontSize: 10));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
        ),
      );
    }

    // Match-by-match Lines
    final spots = <FlSpot>[];
    for (int i = 0; i < sortedTeams.length; i++) {
      spots.add(FlSpot(i.toDouble(), (i * 5.0 + 20.0)));
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: graphType != 'scatter',
            color: ObsidianUITheme.primaryAccent,
            barWidth: graphType == 'scatter' ? 0 : 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: graphType == 'area', color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)),
          ),
        ],
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  // ==========================================================================
  // ALL SCOUTING DATA VIEW (Identical to AllDataScreen)
  // ==========================================================================
  Widget _buildSharedAllDataView(ThemeData theme, Map<String, dynamic> dataObj) {
    final rawEntries = (dataObj['entries'] as List<dynamic>?) ?? (dataObj['rows'] as List<dynamic>?) ?? [];
    final config = (dataObj['config'] as Map<String, dynamic>?) ?? {};

    final filtered = rawEntries.where((e) {
      if (e is! Map<String, dynamic>) return false;
      final tNum = (e['targetTeamNumber'] ?? e['teamNumber'])?.toString() ?? '';
      if (_dataSearchQuery.isNotEmpty && !tNum.contains(_dataSearchQuery)) return false;
      final formType = (e['formType'] ?? e['type'] ?? 'match').toString().toLowerCase();
      if (_dataTypeFilter != 'all' && formType != _dataTypeFilter) return false;
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aMap = a as Map<String, dynamic>;
      final bMap = b as Map<String, dynamic>;
      final aTeam = ((aMap['targetTeamNumber'] ?? aMap['teamNumber']) as num?)?.toInt() ?? 0;
      final bTeam = ((bMap['targetTeamNumber'] ?? bMap['teamNumber']) as num?)?.toInt() ?? 0;

      if (_dataSortBy == 'team-asc') return aTeam.compareTo(bTeam);
      if (_dataSortBy == 'team-desc') return bTeam.compareTo(aTeam);
      if (_dataSortBy == 'match-type') {
        final aMatch = (aMap['matchNumber'] as num?)?.toInt() ?? 0;
        final bMatch = (bMap['matchNumber'] as num?)?.toInt() ?? 0;
        return aMatch.compareTo(bMatch);
      }
      return 0;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Summary Cards
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('all-data.all_scouting_data'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statChip(context.tr('all-data.total_entries'), '${rawEntries.length}', Icons.table_chart),
                  _statChip(context.tr('all-data.match_entries'), '${filtered.length}', Icons.sports_esports),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Filters & Search Card
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: context.tr('all-data.search_teams'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _dataSearchQuery = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _dataTypeFilter,
                      decoration: InputDecoration(
                        labelText: context.tr('all-data.filter_data_type'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: 'all', child: Text(context.tr('all-data.all_forms'))),
                        DropdownMenuItem(value: 'match', child: Text(context.tr('all-data.match_scouting'))),
                        DropdownMenuItem(value: 'pit', child: Text(context.tr('all-data.pit_scouting'))),
                        DropdownMenuItem(value: 'prescout', child: Text(context.tr('all-data.prescouting'))),
                      ],
                      onChanged: (v) => setState(() => _dataTypeFilter = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _dataSortBy,
                      decoration: InputDecoration(
                        labelText: context.tr('all-data.sort_by'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'match-type', child: Text('Match #')),
                        DropdownMenuItem(value: 'team-asc', child: Text('Team (Asc)')),
                        DropdownMenuItem(value: 'team-desc', child: Text('Team (Desc)')),
                      ],
                      onChanged: (v) => setState(() => _dataSortBy = v ?? 'match-type'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Entries List
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text(context.tr('all-data.no_entries_found'))),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final e = filtered[idx] as Map<String, dynamic>;
                    final tNum = e['targetTeamNumber'] ?? e['teamNumber'] ?? '--';
                    final mNum = e['matchNumber'] ?? '--';
                    final dataMap = (e['data'] as Map<String, dynamic>?) ?? {};

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                        child: Text('#$tNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      title: Text('Team $tNum • Match $mNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('Recorded by: ${e['scoutName'] ?? e['username'] ?? 'Scout'} • ${dataMap.length} answers', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEntryDetailsDialog(tNum, mNum, dataMap, config, e),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showEntryDetailsDialog(dynamic tNum, dynamic mNum, Map<String, dynamic> dataMap, Map<String, dynamic> config, [Map<String, dynamic>? entry]) {
    final scout = entry?['scoutName'] ?? entry?['username'] ?? 'Scout';
    final eventName = (entry?['isPrescout'] == true) ? 'Prescouting Data' : (entry?['eventKey'] ?? 'Shared');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Team $tNum • Match $mNum'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recorded by: $scout', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Event: $eventName', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Divider(height: 16),
                    ],
                  ),
                ),
                ...dataMap.entries.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(item.key, style: const TextStyle(color: Colors.grey, fontSize: 13))),
                        Text('${item.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // MATCH PREDICTOR VIEW
  // ==========================================================================
  Widget _buildSharedPredictorView(ThemeData theme, Map<String, dynamic> dataObj) {
    final redScore = (dataObj['redPredictedScore'] ?? dataObj['redScore'] ?? 118).toString();
    final blueScore = (dataObj['bluePredictedScore'] ?? dataObj['blueScore'] ?? 104).toString();
    final redWinProb = (dataObj['redWinProb'] as num?)?.toInt() ?? 64;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Match Predictor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Red Alliance', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('$redScore pts', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          Text('$redWinProb% Win Prob', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Blue Alliance', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('$blueScore pts', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          Text('${100 - redWinProb}% Win Prob', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // CUSTOM ANALYTICS VIEW
  // ==========================================================================
  Widget _buildSharedCustomAnalyticsView(ThemeData theme, Map<String, dynamic> dataObj) {
    final widgets = (dataObj['widgets'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianGlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dataObj['title']?.toString() ?? 'Custom Analytics Studio', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              if (widgets.isEmpty)
                const Text('No widgets configured in this shared report.', style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: widgets.map((w) {
                    final title = w['title'] ?? 'Widget';
                    final val = w['value'] ?? w['stat'] ?? '--';
                    return Container(
                      width: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.getSurfaceColor(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text('$val', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: ObsidianUITheme.primaryAccent),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
