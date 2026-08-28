import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/obsidian_glass_card.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../models/custom_analytics_models.dart';
import '../models/graph_models.dart';
import 'graphs_screen.dart';

class CustomAnalyticsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const CustomAnalyticsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<CustomAnalyticsScreen> createState() => _CustomAnalyticsScreenState();
}

class _CustomAnalyticsScreenState extends State<CustomAnalyticsScreen> {
  bool _isLoading = true;
  CustomAnalyticsDataset _dataset = CustomAnalyticsDataset(
    generatedAt: DateTime.now().toIso8601String(),
    fields: [],
    matchEntries: [],
    pitEntries: [],
    qualEntries: [],
    teams: [],
    totalMatches: 0,
    totalTeams: 0,
  );

  List<CustomAnalyticsReportRecord> _savedReports = [];
  CustomAnalyticsConfig _currentReport = CustomAnalyticsConfig();
  int? _activeCrossFilterTeam;
  bool _isSlicersExpanded = true;
  String _teamSearch = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant CustomAnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final reports = await widget.apiService.fetchCustomAnalyticsReports();
      final dataset = await widget.apiService.fetchCustomAnalyticsDataset(
        eventKey: _currentReport.slicers.eventKey.isNotEmpty ? _currentReport.slicers.eventKey : null,
        includePrescout: _currentReport.slicers.includePrescout,
      );

      if (dataset != null) {
        _dataset = dataset;
      }

      _savedReports = reports;

      // Check if there is a default report to load
      final defaultRep = reports.firstWhere(
        (r) => r.isDefault,
        orElse: () => CustomAnalyticsReportRecord(
          id: '',
          ownerTeamNumber: 0,
          program: 'FRC',
          userId: '',
          title: '',
          configJson: '',
          createdAt: '',
          updatedAt: '',
        ),
      );

      if (defaultRep.id.isNotEmpty) {
        try {
          final parsed = jsonDecode(defaultRep.configJson);
          if (parsed is Map<String, dynamic>) {
            _currentReport = CustomAnalyticsConfig.fromJson(parsed);
            _currentReport.id = defaultRep.id;
            _currentReport.title = defaultRep.title;
            _currentReport.category = defaultRep.category;
            _currentReport.isDefault = true;
          }
        } catch (_) {}
      }

      _applyCalculatedMetrics();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _reloadDataset() async {
    setState(() => _isLoading = true);
    final dataset = await widget.apiService.fetchCustomAnalyticsDataset(
      eventKey: _currentReport.slicers.eventKey.isNotEmpty ? _currentReport.slicers.eventKey : null,
      includePrescout: _currentReport.slicers.includePrescout,
    );
    if (dataset != null) {
      _dataset = dataset;
      _applyCalculatedMetrics();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _applyCalculatedMetrics() {
    for (final metric in _currentReport.calculatedMetrics) {
      if (!_dataset.fields.any((f) => f.id == metric.id)) {
        _dataset.fields.add(CustomAnalyticsField(
          id: metric.id,
          label: 'Calc: ${metric.name}',
          type: 'number',
          source: 'calculated',
          section: 'Custom Calculated',
        ));
      }

      for (final entry in _dataset.matchEntries) {
        final res = CustomAnalyticsMath.evaluateFormula(metric.formula, entry);
        entry[metric.id] = res;
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredEntries() {
    List<Map<String, dynamic>> entries = List.from(_dataset.matchEntries);

    // Event filter
    if (_currentReport.slicers.eventKey.isNotEmpty) {
      entries = entries.where((e) => e['eventKey'] == _currentReport.slicers.eventKey).toList();
    }

    // Prescout filter
    if (!_currentReport.slicers.includePrescout) {
      entries = entries.where((e) => e['isPrescout'] != true).toList();
    }

    // Scope filter (practice, quals, playoffs)
    entries = entries.where((e) {
      final mKey = (e['matchKey']?.toString() ?? '').toLowerCase();
      final isPractice = mKey.contains('_practice') || mKey.contains('_pr') || mKey.contains('_pm');
      final isPlayoff = mKey.contains('_sf') || mKey.contains('_f') || mKey.contains('_qf') || mKey.contains('_ef');
      final isQual = !isPractice && !isPlayoff;

      if (isPractice && !_currentReport.slicers.practice) return false;
      if (isQual && !_currentReport.slicers.quals) return false;
      if (isPlayoff && !_currentReport.slicers.playoffs) return false;
      return true;
    }).toList();

    // Slicer: Team filter
    if (_currentReport.slicers.teamNumbers.isNotEmpty) {
      entries = entries.where((e) {
        final tNum = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
        return _currentReport.slicers.teamNumbers.contains(tNum);
      }).toList();
    }

    // Interactive Cross-Filter
    if (_activeCrossFilterTeam != null) {
      entries = entries.where((e) {
        final tNum = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
        return tNum == _activeCrossFilterTeam;
      }).toList();
    }

    return entries;
  }

  String _getFieldLabel(String fieldId) {
    final f = _dataset.fields.firstWhere(
      (item) => item.id == fieldId,
      orElse: () => CustomAnalyticsField(id: fieldId, label: fieldId, type: 'string', source: 'match'),
    );
    return f.label;
  }

  List<int> _getAllUniqueTeams() {
    final teams = <int>{};
    for (final e in _dataset.matchEntries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '');
      if (t != null && t > 0) teams.add(t);
    }
    for (final t in _dataset.teams) {
      if (t.teamNumber > 0) teams.add(t.teamNumber);
    }
    return teams.toList()..sort();
  }

  List<int> _getTop8Teams() {
    final scores = <int, List<double>>{};
    for (final e in _dataset.matchEntries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '');
      if (t != null && t > 0) {
        final val = (e['calc_total_score'] is num) ? (e['calc_total_score'] as num).toDouble() : double.tryParse(e['calc_total_score']?.toString() ?? '') ?? 0.0;
        scores.putIfAbsent(t, () => []).add(val);
      }
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) {
        final avgA = a.value.isEmpty ? 0.0 : (a.value.fold<double>(0.0, (x, y) => x + y) / a.value.length);
        final avgB = b.value.isEmpty ? 0.0 : (b.value.fold<double>(0.0, (x, y) => x + y) / b.value.length);
        return avgB.compareTo(avgA);
      });
    return sorted.take(8).map((e) => e.key).toList();
  }

  // --- Modals & Dialogs ---

  void _openRenameDialog() {
    final controller = TextEditingController(text: _currentReport.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        title: Text('Rename Report', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
          decoration: InputDecoration(
            labelText: 'Report Title',
            labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                setState(() => _currentReport.title = newTitle);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openTemplatesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: ObsidianUITheme.getSurfaceColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dashboard Templates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
              ],
            ),
            const SizedBox(height: 8),
            Text('Select a starter template to instantly generate an analytical workspace:', style: TextStyle(fontSize: 13, color: ObsidianUITheme.getSecondaryTextColor(context))),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildTemplateOption(
                    title: 'Blank Dashboard',
                    desc: 'Start with a clean slate to build your own custom visuals from scratch.',
                    icon: Icons.dashboard_customize_rounded,
                    onTap: () {
                      setState(() {
                        _currentReport.widgets.clear();
                      });
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTemplateOption(
                    title: 'Match Strategy & Offense',
                    desc: 'Auto vs Teleop points, stacked phase contributions, consistency box plots, and ranking matrix.',
                    icon: Icons.sports_score_rounded,
                    onTap: () {
                      setState(() {
                        _currentReport.title = 'Match Strategy & Offense';
                        _currentReport.category = 'Strategy';
                        _currentReport.widgets = CustomAnalyticsConfig.getDefaultWidgets();
                      });
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTemplateOption(
                    title: 'Pick List & Capability',
                    desc: 'Multi-dimensional team radar profiles, EPA correlation scatter, driver ratings, and scoring breakdown.',
                    icon: Icons.star_rounded,
                    onTap: () {
                      setState(() {
                        _currentReport.title = 'Pick List & Capability';
                        _currentReport.category = 'Pick List';
                        _currentReport.widgets = [
                          CustomAnalyticsWidget(
                            id: 'w_kpi_total',
                            type: 'kpi',
                            title: 'Scoring Leader',
                            subtitle: 'Peak Average Total Points',
                            width: 'col-4',
                            dimension: 'teamNumber',
                            measure: 'calc_total_score',
                            aggregation: 'avg',
                            palette: 'obsidian',
                          ),
                          CustomAnalyticsWidget(
                            id: 'w_kpi_epa',
                            type: 'kpi',
                            title: 'Statbotics EPA',
                            subtitle: 'Expected Points Added',
                            width: 'col-4',
                            dimension: 'teamNumber',
                            measure: 'statbotics_epa',
                            aggregation: 'avg',
                            palette: 'emerald',
                          ),
                          CustomAnalyticsWidget(
                            id: 'w_kpi_opr',
                            type: 'kpi',
                            title: 'Event OPR',
                            subtitle: 'Offensive Power Rating',
                            width: 'col-4',
                            dimension: 'teamNumber',
                            measure: 'tba_opr',
                            aggregation: 'avg',
                            palette: 'sunset',
                          ),
                          CustomAnalyticsWidget(
                            id: 'w_radar_profile',
                            type: 'radar',
                            title: 'Multi-Dimensional Capability Radar',
                            subtitle: 'Phase Comparison across Top Teams',
                            width: 'col-6',
                            dimension: 'teamNumber',
                            measure: 'calc_auto_score',
                            secondaryMeasures: ['calc_teleop_score', 'calc_endgame_score', 'calc_total_score'],
                            palette: 'cyberpunk',
                          ),
                          CustomAnalyticsWidget(
                            id: 'w_scatter_epa_scouted',
                            type: 'scatter',
                            title: 'Scouted Points vs EPA Correlation',
                            subtitle: 'X: Total Score, Y: Statbotics EPA',
                            width: 'col-6',
                            dimension: 'teamNumber',
                            measure: 'calc_total_score',
                            secondaryMeasures: ['statbotics_epa'],
                            palette: 'alliance',
                          ),
                          CustomAnalyticsWidget(
                            id: 'w_pick_matrix',
                            type: 'matrix',
                            title: 'Draft Pick Matrix',
                            subtitle: 'Complete metric breakdown for picking order',
                            width: 'col-12',
                            dimension: 'teamNumber',
                            measure: 'calc_total_score',
                            secondaryMeasures: ['calc_auto_score', 'calc_teleop_score', 'calc_endgame_score', 'statbotics_epa', 'tba_opr'],
                            palette: 'obsidian',
                          ),
                        ];
                      });
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateOption({
    required String title,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = ObsidianUITheme.isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: ObsidianUITheme.primaryAccent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCalculatedMetricModal() {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    final formulaController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = ObsidianUITheme.isDark(context);
          return AlertDialog(
            backgroundColor: ObsidianUITheme.getSurfaceColor(context),
            title: Text('Create Calculated Metric', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Write mathematical expressions referencing field IDs in square brackets. E.g. [calc_auto_score] * 1.5 + [calc_teleop_score]',
                    style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    onChanged: (v) {
                      if (idController.text.isEmpty || idController.text.startsWith('calc_')) {
                        idController.text = 'calc_${v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
                      }
                    },
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Metric Display Name',
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13),
                      hintText: 'e.g. Weighted Offense Power',
                      hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: idController,
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Metric ID (alphanumeric)',
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13),
                      hintText: 'e.g. calc_custom_power',
                      hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: formulaController,
                    maxLines: 3,
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Formula Expression',
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13),
                      hintText: '[calc_auto_score] * 1.5 + [calc_teleop_score]',
                      hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12),
                      border: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Insert Available Fields:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _dataset.fields.where((f) => f.type == 'number').take(12).map((f) {
                      return InkWell(
                        onTap: () {
                          formulaController.text += ' [${f.id}] ';
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            f.label,
                            style: TextStyle(fontSize: 11, color: ObsidianUITheme.getPrimaryTextColor(context)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                onPressed: () {
                  final name = nameController.text.trim();
                  final id = idController.text.trim();
                  final formula = formulaController.text.trim();

                  if (name.isEmpty || id.isEmpty || formula.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill out all metric fields'), backgroundColor: ObsidianUITheme.warningOrange),
                    );
                    return;
                  }

                  setState(() {
                    _currentReport.calculatedMetrics.removeWhere((m) => m.id == id);
                    _currentReport.calculatedMetrics.add(CustomCalculatedMetric(id: id, name: name, formula: formula));
                    _applyCalculatedMetrics();
                  });

                  Navigator.of(ctx).pop();
                },
                child: const Text('Save Metric', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openWidgetEditor([int index = -1]) {
    final isEditing = index >= 0 && index < _currentReport.widgets.length;
    final widget = isEditing
        ? _currentReport.widgets[index].clone()
        : CustomAnalyticsWidget(
            id: 'w_${DateTime.now().millisecondsSinceEpoch}',
            type: 'bar',
            title: 'New Visual',
            subtitle: '',
            width: 'col-6',
            dimension: 'teamNumber',
            measure: 'calc_total_score',
            aggregation: 'avg',
            palette: 'obsidian',
          );

    final titleController = TextEditingController(text: widget.title);
    final subtitleController = TextEditingController(text: widget.subtitle);
    final targetLineController = TextEditingController(text: widget.targetLine != null ? widget.targetLine.toString() : '');
    final topNController = TextEditingController(text: widget.topN.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final numericFields = _dataset.fields.where((f) => f.type == 'number').toList();

          return AlertDialog(
            backgroundColor: ObsidianUITheme.getSurfaceColor(context),
            title: Text(isEditing ? 'Configure Visual' : 'Add Visual', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 16)),
            content: SizedBox(
              width: min(600, MediaQuery.of(context).size.width * 0.9),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VISUAL TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildVisualTypeChip(label: 'Bar / Col', type: 'bar', icon: Icons.bar_chart_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'bar')),
                        _buildVisualTypeChip(label: 'Stacked Bar', type: 'stacked_bar', icon: Icons.align_horizontal_left_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'stacked_bar')),
                        _buildVisualTypeChip(label: 'Line / Trend', type: 'line', icon: Icons.show_chart_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'line')),
                        _buildVisualTypeChip(label: 'Scatter', type: 'scatter', icon: Icons.scatter_plot_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'scatter')),
                        _buildVisualTypeChip(label: 'Box Plot', type: 'box', icon: Icons.candlestick_chart_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'box')),
                        _buildVisualTypeChip(label: 'Violin', type: 'violin', icon: Icons.graphic_eq_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'violin')),
                        _buildVisualTypeChip(label: 'Radar', type: 'radar', icon: Icons.radar_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'radar')),
                        _buildVisualTypeChip(label: 'Donut', type: 'donut', icon: Icons.pie_chart_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'donut')),
                        _buildVisualTypeChip(label: 'KPI Card', type: 'kpi', icon: Icons.speed_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'kpi')),
                        _buildVisualTypeChip(label: 'Matrix', type: 'matrix', icon: Icons.table_chart_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'matrix')),
                        _buildVisualTypeChip(label: 'Heatmap', type: 'heatmap', icon: Icons.grid_view_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'heatmap')),
                        _buildVisualTypeChip(label: 'Histogram', type: 'histogram', icon: Icons.analytics_rounded, currentType: widget.type, onSelect: () => setModalState(() => widget.type = 'histogram')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Visual Title',
                        labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: subtitleController,
                      style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Subtitle (Optional)',
                        labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: widget.width,
                            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Card Width Span',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'col-3', child: Text('1/4 Width (3/12)')),
                              DropdownMenuItem(value: 'col-4', child: Text('1/3 Width (4/12)')),
                              DropdownMenuItem(value: 'col-6', child: Text('1/2 Width (6/12)')),
                              DropdownMenuItem(value: 'col-8', child: Text('2/3 Width (8/12)')),
                              DropdownMenuItem(value: 'col-12', child: Text('Full Width (12/12)')),
                            ],
                            onChanged: (v) => setModalState(() => widget.width = v ?? 'col-6'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: widget.palette,
                            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Color Palette',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'obsidian', child: Text('Obsidian Blue')),
                              DropdownMenuItem(value: 'emerald', child: Text('Emerald & Teal')),
                              DropdownMenuItem(value: 'sunset', child: Text('Sunset Orange')),
                              DropdownMenuItem(value: 'cyberpunk', child: Text('Cyberpunk Neon')),
                              DropdownMenuItem(value: 'alliance', child: Text('Alliance Red/Blue')),
                            ],
                            onChanged: (v) => setModalState(() => widget.palette = v ?? 'obsidian'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: numericFields.any((f) => f.id == widget.measure) ? widget.measure : (numericFields.isNotEmpty ? numericFields.first.id : 'calc_total_score'),
                      dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                      style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Primary Measure (Y)',
                        labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                      ),
                      items: numericFields.map((f) {
                        return DropdownMenuItem(
                          value: f.id,
                          child: Text('${f.label} (${f.section})', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => setModalState(() => widget.measure = v ?? 'calc_total_score'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: widget.aggregation,
                            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Aggregation',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'avg', child: Text('Mean (AVG)')),
                              DropdownMenuItem(value: 'sum', child: Text('Total (SUM)')),
                              DropdownMenuItem(value: 'median', child: Text('Median')),
                              DropdownMenuItem(value: 'max', child: Text('Maximum')),
                              DropdownMenuItem(value: 'min', child: Text('Minimum')),
                              DropdownMenuItem(value: 'count', child: Text('Count')),
                              DropdownMenuItem(value: 'stdev', child: Text('Std Deviation')),
                              DropdownMenuItem(value: 'p75', child: Text('75th Percentile')),
                            ],
                            onChanged: (v) => setModalState(() => widget.aggregation = v ?? 'avg'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: widget.sort,
                            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Sort Order',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'val_desc', child: Text('High → Low')),
                              DropdownMenuItem(value: 'val_asc', child: Text('Low → High')),
                              DropdownMenuItem(value: 'dim_asc', child: Text('Team Low → High')),
                              DropdownMenuItem(value: 'dim_desc', child: Text('Team High → Low')),
                            ],
                            onChanged: (v) => setModalState(() => widget.sort = v ?? 'val_desc'),
                          ),
                        ),
                      ],
                    ),
                    if (['stacked_bar', 'radar', 'matrix', 'donut', 'scatter'].contains(widget.type)) ...[
                      const SizedBox(height: 12),
                      Text('Secondary Measures / Breakdown:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                      const SizedBox(height: 6),
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          children: numericFields.map((f) {
                            final isChecked = widget.secondaryMeasures.contains(f.id);
                            return CheckboxListTile(
                              dense: true,
                              value: isChecked,
                              activeColor: ObsidianUITheme.primaryAccent,
                              title: Text(f.label, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12)),
                              onChanged: (val) {
                                setModalState(() {
                                  if (val == true) {
                                    widget.secondaryMeasures.add(f.id);
                                  } else {
                                    widget.secondaryMeasures.remove(f.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: topNController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Top N Items (0=All)',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: targetLineController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'Target Benchmark Line',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                onPressed: () {
                  widget.title = titleController.text.trim().isNotEmpty ? titleController.text.trim() : 'Visual';
                  widget.subtitle = subtitleController.text.trim();
                  widget.topN = int.tryParse(topNController.text.trim()) ?? 0;
                  widget.targetLine = double.tryParse(targetLineController.text.trim());

                  setState(() {
                    if (isEditing) {
                      _currentReport.widgets[index] = widget;
                    } else {
                      _currentReport.widgets.add(widget);
                    }
                  });

                  Navigator.of(ctx).pop();
                },
                child: Text(isEditing ? 'Apply Visual' : 'Add Visual', style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVisualTypeChip({
    required String label,
    required String type,
    required IconData icon,
    required String currentType,
    required VoidCallback onSelect,
  }) {
    final isSelected = currentType == type;
    final isDark = ObsidianUITheme.isDark(context);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? ObsidianUITheme.primaryAccent
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : ObsidianUITheme.getSecondaryTextColor(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReportLibraryModal(bool openSaveDirectly) {
    final titleController = TextEditingController(text: _currentReport.title);
    final descController = TextEditingController(text: _currentReport.description);
    String category = _currentReport.category;
    bool isShared = _currentReport.isShared;
    bool isDefault = _currentReport.isDefault;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: ObsidianUITheme.getSurfaceColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Saved Report Dashboards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    // Save section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.isDark(context) ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SAVE CURRENT DASHBOARD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 0.5)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: titleController,
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Report Title',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: category,
                            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Category',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Strategy', child: Text('Strategy')),
                              DropdownMenuItem(value: 'Pick List', child: Text('Pick List')),
                              DropdownMenuItem(value: 'Driver Analysis', child: Text('Driver Analysis')),
                              DropdownMenuItem(value: 'Scoring Breakdown', child: Text('Scoring Breakdown')),
                              DropdownMenuItem(value: 'Alliance Partner', child: Text('Alliance Partner')),
                              DropdownMenuItem(value: 'General', child: Text('General')),
                            ],
                            onChanged: (v) => setModalState(() => category = v ?? 'General'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: descController,
                            style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Description (Optional)',
                              labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Checkbox(
                                value: isShared,
                                activeColor: ObsidianUITheme.primaryAccent,
                                onChanged: (v) => setModalState(() => isShared = v ?? false),
                              ),
                              Text('Share with Team', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getPrimaryTextColor(context))),
                              const SizedBox(width: 12),
                              Checkbox(
                                value: isDefault,
                                activeColor: ObsidianUITheme.primaryAccent,
                                onChanged: (v) => setModalState(() => isDefault = v ?? false),
                              ),
                              Text('Set as Default', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getPrimaryTextColor(context))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent, minimumSize: const Size.fromHeight(40)),
                            onPressed: () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) return;

                              _currentReport.title = title;
                              _currentReport.category = category;
                              _currentReport.description = descController.text.trim();
                              _currentReport.isShared = isShared;
                              _currentReport.isDefault = isDefault;

                              final configJson = jsonEncode(_currentReport.toJson());
                              if (_currentReport.id != null && _currentReport.id!.isNotEmpty) {
                                await widget.apiService.updateCustomAnalyticsReport(
                                  _currentReport.id!,
                                  title: title,
                                  category: category,
                                  description: _currentReport.description,
                                  configJson: configJson,
                                  isShared: isShared,
                                  isDefault: isDefault,
                                );
                              } else {
                                final created = await widget.apiService.createCustomAnalyticsReport(
                                  title: title,
                                  category: category,
                                  description: _currentReport.description,
                                  configJson: configJson,
                                  isShared: isShared,
                                  isDefault: isDefault,
                                );
                                if (created != null) {
                                  _currentReport.id = created.id;
                                }
                              }

                              final updatedReports = await widget.apiService.fetchCustomAnalyticsReports();
                              if (!mounted) return;

                              setState(() {
                                _savedReports = updatedReports;
                              });

                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.of(ctx).pop();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Report saved successfully!'), backgroundColor: ObsidianUITheme.successGreen),
                              );
                            },
                            child: const Text('Save Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text("YOUR TEAM'S SAVED REPORTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                    const SizedBox(height: 8),
                    if (_savedReports.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(child: Text('No saved reports yet.', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)))),
                      )
                    else
                      ..._savedReports.map((rep) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.isDark(context) ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(rep.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.getPrimaryTextColor(context))),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(rep.category, style: const TextStyle(fontSize: 10, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold)),
                                        ),
                                        if (rep.isDefault) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: ObsidianUITheme.successGreen.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text('Default', style: TextStyle(fontSize: 10, color: ObsidianUITheme.successGreen, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (rep.description != null && rep.description!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(rep.description!, style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
                                    ],
                                    const SizedBox(height: 2),
                                    Text('By ${rep.authorUsername}', style: TextStyle(fontSize: 10, color: ObsidianUITheme.getFaintTextColor(context))),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                                tooltip: 'Load Report',
                                onPressed: () {
                                  try {
                                    final parsed = jsonDecode(rep.configJson);
                                    if (parsed is Map<String, dynamic>) {
                                      setState(() {
                                        _currentReport = CustomAnalyticsConfig.fromJson(parsed);
                                        _currentReport.id = rep.id;
                                        _currentReport.title = rep.title;
                                        _currentReport.category = rep.category;
                                        _currentReport.isDefault = rep.isDefault;
                                        _applyCalculatedMetrics();
                                      });
                                    }
                                    Navigator.of(ctx).pop();
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to load report: $e'), backgroundColor: ObsidianUITheme.errorRed),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: ObsidianUITheme.secondaryAccent, size: 18),
                                tooltip: 'Duplicate',
                                onPressed: () async {
                                  await widget.apiService.duplicateCustomAnalyticsReport(rep.id);
                                  final list = await widget.apiService.fetchCustomAnalyticsReports();
                                  setModalState(() => _savedReports = list);
                                  setState(() => _savedReports = list);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: ObsidianUITheme.errorRed, size: 18),
                                tooltip: 'Delete',
                                onPressed: () async {
                                  await widget.apiService.deleteCustomAnalyticsReport(rep.id);
                                  final list = await widget.apiService.fetchCustomAnalyticsReports();
                                  setModalState(() => _savedReports = list);
                                  setState(() => _savedReports = list);
                                },
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
        ),
      ),
    );
  }

  void _openDrillDownModal(int teamNumber) {
    final teamEntries = _dataset.matchEntries.where((e) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      return t == teamNumber;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: ObsidianUITheme.getSurfaceColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Team $teamNumber Match Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
              ],
            ),
            const SizedBox(height: 6),
            Text('${teamEntries.length} scouting entries recorded for Team $teamNumber', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
            const SizedBox(height: 14),
            Expanded(
              child: teamEntries.isEmpty
                  ? Center(child: Text('No match entries recorded for Team $teamNumber', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context))))
                  : ListView.builder(
                      itemCount: teamEntries.length,
                      itemBuilder: (ctx, i) {
                        final entry = teamEntries[i];
                        final matchNum = entry['matchNumber'] ?? i + 1;
                        final totalScore = (entry['calc_total_score'] is num) ? (entry['calc_total_score'] as num).toDouble() : 0.0;
                        final autoScore = (entry['calc_auto_score'] is num) ? (entry['calc_auto_score'] as num).toDouble() : 0.0;
                        final teleopScore = (entry['calc_teleop_score'] is num) ? (entry['calc_teleop_score'] as num).toDouble() : 0.0;
                        final endgameScore = (entry['calc_endgame_score'] is num) ? (entry['calc_endgame_score'] as num).toDouble() : 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.isDark(context) ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Match #$matchNum', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.getPrimaryTextColor(context))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('Total: ${totalScore.toStringAsFixed(1)} pts', style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Auto: ${autoScore.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                                  Text('Teleop: ${teleopScore.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                                  Text('Endgame: ${endgameScore.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                                ],
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
  }

  // --- Widget Renderers ---

  Widget _buildWidgetCard(CustomAnalyticsWidget widget, int index, List<Map<String, dynamic>> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ObsidianGlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ObsidianUITheme.getPrimaryTextColor(context))),
                        if (widget.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.subtitle, style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index > 0)
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 16),
                          tooltip: 'Move Left',
                          onPressed: () {
                            setState(() {
                              final item = _currentReport.widgets.removeAt(index);
                              _currentReport.widgets.insert(index - 1, item);
                            });
                          },
                        ),
                      if (index < _currentReport.widgets.length - 1)
                        IconButton(
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          tooltip: 'Move Right',
                          onPressed: () {
                            setState(() {
                              final item = _currentReport.widgets.removeAt(index);
                              _currentReport.widgets.insert(index + 1, item);
                            });
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        tooltip: 'Edit Visual',
                        onPressed: () => _openWidgetEditor(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: 'Duplicate',
                        onPressed: () {
                          setState(() {
                            final copy = widget.clone();
                            copy.id = 'w_${DateTime.now().millisecondsSinceEpoch}';
                            copy.title = '${widget.title} (Copy)';
                            _currentReport.widgets.insert(index + 1, copy);
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: ObsidianUITheme.errorRed),
                        tooltip: 'Delete',
                        onPressed: () {
                          setState(() {
                            _currentReport.widgets.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: widget.type == 'kpi'
                    ? 140
                    : (['box', 'violin'].contains(widget.type) ? 350 : 260),
                child: _renderVisual(widget, entries),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _renderVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    if (entries.isEmpty && widget.type != 'kpi') {
      return Center(
        child: Text('No data matching current filters', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12)),
      );
    }

    switch (widget.type) {
      case 'kpi':
        return _renderKpiVisual(widget, entries);
      case 'matrix':
        return _renderMatrixVisual(widget, entries);
      case 'donut':
        return _renderDonutVisual(widget, entries);
      case 'line':
        return _renderLineVisual(widget, entries);
      case 'scatter':
        return _renderScatterVisual(widget, entries);
      case 'radar':
        return _renderRadarVisual(widget, entries);
      case 'box':
        return _renderBoxVisual(widget, entries);
      case 'violin':
        return _renderViolinVisual(widget, entries);
      case 'histogram':
        return _renderHistogramVisual(widget, entries);
      case 'heatmap':
        return _renderHeatmapVisual(widget, entries);
      case 'stacked_bar':
      case 'bar':
      default:
        return _renderBarVisual(widget, entries);
    }
  }

  // --- Chart Type Renderers ---

  Widget _renderKpiVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final values = entries.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : double.tryParse(e[widget.measure]?.toString() ?? '') ?? 0.0)).toList();
    final calcVal = CustomAnalyticsMath.computeAggregation(values, widget.aggregation);

    final allValues = _dataset.matchEntries.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : double.tryParse(e[widget.measure]?.toString() ?? '') ?? 0.0)).toList();
    final overallAvg = allValues.isNotEmpty ? CustomAnalyticsMath.computeAggregation(allValues, 'avg') : 0.0;
    final delta = calcVal - overallAvg;

    final palette = CustomAnalyticsPalettes.getPalette(widget.palette);
    final accentColor = palette.isNotEmpty ? palette.first : ObsidianUITheme.primaryAccent;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            calcVal.toStringAsFixed(1),
            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: accentColor, height: 1.0),
          ),
          const SizedBox(height: 6),
          Text(
            '${_getFieldLabel(widget.measure)} (${widget.aggregation.toUpperCase()})',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context)),
          ),
          if (overallAvg > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (delta >= 0 ? ObsidianUITheme.successGreen : ObsidianUITheme.errorRed).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${delta >= 0 ? "▲ +" : "▼ "}${delta.toStringAsFixed(1)} vs Event Mean (${overallAvg.toStringAsFixed(1)})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: delta >= 0 ? ObsidianUITheme.successGreen : ObsidianUITheme.errorRed,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renderBarVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final isStacked = widget.type == 'stacked_bar';
    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);

    // Group by teamNumber
    final groups = <int, List<Map<String, dynamic>>>{};
    for (final e in entries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      if (t > 0) groups.putIfAbsent(t, () => []).add(e);
    }

    final teams = groups.keys.toList();
    teams.sort((a, b) {
      final aVal = CustomAnalyticsMath.computeAggregation(groups[a]!.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : 0.0)).toList(), widget.aggregation);
      final bVal = CustomAnalyticsMath.computeAggregation(groups[b]!.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : 0.0)).toList(), widget.aggregation);
      if (widget.sort == 'val_asc') return aVal.compareTo(bVal);
      if (widget.sort == 'dim_asc') return a.compareTo(b);
      if (widget.sort == 'dim_desc') return b.compareTo(a);
      return bVal.compareTo(aVal);
    });

    final displayTeams = (widget.topN > 0) ? teams.take(widget.topN).toList() : teams.take(16).toList();
    final allMeasures = [widget.measure, ...widget.secondaryMeasures];

    double maxY = 10.0;
    final barGroups = <BarChartGroupData>[];

    for (int i = 0; i < displayTeams.length; i++) {
      final tNum = displayTeams[i];
      final teamData = groups[tNum] ?? [];

      if (isStacked) {
        double currentStackY = 0;
        final rodStackItems = <BarChartRodStackItem>[];

        for (int mIdx = 0; mIdx < allMeasures.length; mIdx++) {
          final m = allMeasures[mIdx];
          final val = CustomAnalyticsMath.computeAggregation(
            teamData.map((e) => (e[m] is num ? (e[m] as num).toDouble() : 0.0)).toList(),
            widget.aggregation,
          );
          final fromY = currentStackY;
          currentStackY += val;
          rodStackItems.add(BarChartRodStackItem(fromY, currentStackY, colors[mIdx % colors.length]));
        }

        if (currentStackY > maxY) maxY = currentStackY;

        barGroups.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: currentStackY,
              rodStackItems: rodStackItems,
              borderRadius: BorderRadius.circular(4),
              width: 14,
            ),
          ],
        ));
      } else {
        final val = CustomAnalyticsMath.computeAggregation(
          teamData.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : 0.0)).toList(),
          widget.aggregation,
        );
        if (val > maxY) maxY = val;

        barGroups.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: val,
              color: (_activeCrossFilterTeam == tNum) ? ObsidianUITheme.primaryAccent : colors[0],
              borderRadius: BorderRadius.circular(4),
              width: 14,
            ),
          ],
        ));
      }
    }

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY * 1.15,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final tNum = displayTeams[groupIndex];
                    return BarTooltipItem(
                      'Team $tNum\n${rod.toY.toStringAsFixed(1)} pts',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent && response?.spot != null) {
                    final groupIdx = response!.spot!.touchedBarGroupIndex;
                    if (groupIdx >= 0 && groupIdx < displayTeams.length) {
                      final tappedTeam = displayTeams[groupIdx];
                      setState(() {
                        _activeCrossFilterTeam = (_activeCrossFilterTeam == tappedTeam) ? null : tappedTeam;
                      });
                    }
                  }
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= displayTeams.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '${displayTeams[idx]}',
                          style: TextStyle(fontSize: 10, color: ObsidianUITheme.getSecondaryTextColor(context)),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (val, meta) {
                      return Text(
                        val.toInt().toString(),
                        style: TextStyle(fontSize: 9, color: ObsidianUITheme.getFaintTextColor(context)),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (val) => FlLine(color: ObsidianUITheme.getBorderColor(context), strokeWidth: 0.8),
              ),
              borderData: FlBorderData(show: false),
              barGroups: barGroups,
            ),
          ),
        ),
      ],
    );
  }

  Widget _renderLineVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);
    final teams = _getAllUniqueTeams().take(6).toList();

    final lineBarsData = <LineChartBarData>[];
    double maxY = 10.0;

    for (int tIdx = 0; tIdx < teams.length; tIdx++) {
      final tNum = teams[tIdx];
      final teamEntries = entries.where((e) {
        final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
        return t == tNum;
      }).toList()
        ..sort((a, b) => ((a['matchNumber'] as num?) ?? 0).compareTo((b['matchNumber'] as num?) ?? 0));

      final spots = <FlSpot>[];
      for (int i = 0; i < teamEntries.length; i++) {
        final val = (teamEntries[i][widget.measure] is num ? (teamEntries[i][widget.measure] as num).toDouble() : 0.0);
        if (val > maxY) maxY = val;
        spots.add(FlSpot(i.toDouble(), val));
      }

      if (spots.isNotEmpty) {
        lineBarsData.add(LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[tIdx % colors.length],
          barWidth: 2.5,
          dotData: const FlDotData(show: true),
        ));
      }
    }

    return LineChart(
      LineChartData(
        maxY: maxY * 1.15,
        lineBarsData: lineBarsData,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => Text('M${v.toInt() + 1}', style: TextStyle(fontSize: 9, color: ObsidianUITheme.getFaintTextColor(context))),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: TextStyle(fontSize: 9, color: ObsidianUITheme.getFaintTextColor(context))),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _renderScatterVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final xMeasure = widget.measure;
    final yMeasure = widget.secondaryMeasures.isNotEmpty ? widget.secondaryMeasures.first : 'calc_teleop_score';
    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);

    final groups = <int, List<Map<String, dynamic>>>{};
    for (final e in entries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      if (t > 0) groups.putIfAbsent(t, () => []).add(e);
    }

    final spots = <ScatterSpot>[];
    final teams = groups.keys.toList();
    double maxX = 10.0;
    double maxY = 10.0;

    for (final t in teams) {
      final tData = groups[t]!;
      final xVal = CustomAnalyticsMath.computeAggregation(tData.map((e) => (e[xMeasure] is num ? (e[xMeasure] as num).toDouble() : 0.0)).toList(), 'avg');
      final yVal = CustomAnalyticsMath.computeAggregation(tData.map((e) => (e[yMeasure] is num ? (e[yMeasure] as num).toDouble() : 0.0)).toList(), 'avg');

      if (xVal > maxX) maxX = xVal;
      if (yVal > maxY) maxY = yVal;

      spots.add(ScatterSpot(
        xVal,
        yVal,
        dotPainter: FlDotCirclePainter(
          radius: 6,
          color: colors[0].withValues(alpha: 0.8),
          strokeColor: Colors.white,
          strokeWidth: 1.5,
        ),
      ));
    }

    return ScatterChart(
      ScatterChartData(
        maxX: maxX * 1.15,
        maxY: maxY * 1.15,
        scatterSpots: spots,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            axisNameWidget: Text('X: ${_getFieldLabel(xMeasure)}', style: TextStyle(fontSize: 10, color: ObsidianUITheme.getSecondaryTextColor(context))),
            sideTitles: SideTitles(showTitles: true, reservedSize: 20),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text('Y: ${_getFieldLabel(yMeasure)}', style: TextStyle(fontSize: 10, color: ObsidianUITheme.getSecondaryTextColor(context))),
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _renderDonutVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);
    final measures = [widget.measure, ...widget.secondaryMeasures];

    final totals = measures.map((m) {
      final vals = entries.map((e) => (e[m] is num ? (e[m] as num).toDouble() : 0.0)).toList();
      return CustomAnalyticsMath.computeAggregation(vals, 'sum');
    }).toList();

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < measures.length; i++) {
      sections.add(PieChartSectionData(
        value: totals[i],
        title: '${totals[i].toStringAsFixed(0)}',
        color: colors[i % colors.length],
        radius: 35,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: measures.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, color: colors[e.key % colors.length]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_getFieldLabel(e.value), style: TextStyle(fontSize: 11, color: ObsidianUITheme.getPrimaryTextColor(context)), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _renderMatrixVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final allMeasures = [widget.measure, ...widget.secondaryMeasures];
    final groups = <int, List<Map<String, dynamic>>>{};

    for (final e in entries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      if (t > 0) groups.putIfAbsent(t, () => []).add(e);
    }

    final rows = groups.entries.map((g) {
      final rowMap = <String, dynamic>{'teamNumber': g.key, 'matchCount': g.value.length};
      for (final m in allMeasures) {
        final vals = g.value.map((e) => (e[m] is num ? (e[m] as num).toDouble() : 0.0)).toList();
        rowMap[m] = CustomAnalyticsMath.computeAggregation(vals, widget.aggregation);
      }
      return rowMap;
    }).toList();

    rows.sort((a, b) => ((b[widget.measure] as num?) ?? 0).compareTo((a[widget.measure] as num?) ?? 0));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 38,
          horizontalMargin: 12,
          columnSpacing: 18,
          columns: [
            const DataColumn(label: Text('Team', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            const DataColumn(label: Text('Matches', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ...allMeasures.map((m) => DataColumn(label: Text(_getFieldLabel(m), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
          ],
          rows: rows.map((r) {
            final tNum = r['teamNumber'] as int;
            return DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => _openDrillDownModal(tNum),
                    child: Text('Team $tNum', style: const TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, fontSize: 12)),
                  ),
                ),
                DataCell(Text('${r['matchCount']}', style: const TextStyle(fontSize: 12))),
                ...allMeasures.map((m) {
                  final val = (r[m] is num) ? (r[m] as num).toDouble() : 0.0;
                  return DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(val.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _renderBoxVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final groups = <int, List<double>>{};
    for (final e in entries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      if (t > 0) {
        final val = (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : double.tryParse(e[widget.measure]?.toString() ?? '') ?? 0.0);
        groups.putIfAbsent(t, () => []).add(val);
      }
    }

    if (groups.isEmpty) {
      return Center(
        child: Text('No data for distribution', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12)),
      );
    }

    final teams = groups.keys.toList();
    teams.sort((a, b) {
      final aStats = DistributionStats.fromValues('Team $a', groups[a]!);
      final bStats = DistributionStats.fromValues('Team $b', groups[b]!);
      if (widget.sort == 'val_asc') return aStats.median.compareTo(bStats.median);
      if (widget.sort == 'dim_asc') return a.compareTo(b);
      if (widget.sort == 'dim_desc') return b.compareTo(a);
      return bStats.median.compareTo(aStats.median);
    });

    final displayTeams = (widget.topN > 0) ? teams.take(widget.topN).toList() : teams.take(12).toList();
    final statsList = displayTeams.map((t) => DistributionStats.fromValues('Team $t', groups[t]!)).toList();

    return ObsidianDistributionChart(
      statsList: statsList,
      isViolin: false,
      palette: CustomAnalyticsPalettes.getPalette(widget.palette),
      canvasHeight: 200.0,
    );
  }

  Widget _renderViolinVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final groups = <int, List<double>>{};
    for (final e in entries) {
      final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
      if (t > 0) {
        final val = (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : double.tryParse(e[widget.measure]?.toString() ?? '') ?? 0.0);
        groups.putIfAbsent(t, () => []).add(val);
      }
    }

    if (groups.isEmpty) {
      return Center(
        child: Text('No data for distribution', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12)),
      );
    }

    final teams = groups.keys.toList();
    teams.sort((a, b) {
      final aStats = DistributionStats.fromValues('Team $a', groups[a]!);
      final bStats = DistributionStats.fromValues('Team $b', groups[b]!);
      if (widget.sort == 'val_asc') return aStats.median.compareTo(bStats.median);
      if (widget.sort == 'dim_asc') return a.compareTo(b);
      if (widget.sort == 'dim_desc') return b.compareTo(a);
      return bStats.median.compareTo(aStats.median);
    });

    final displayTeams = (widget.topN > 0) ? teams.take(widget.topN).toList() : teams.take(12).toList();
    final statsList = displayTeams.map((t) => DistributionStats.fromValues('Team $t', groups[t]!)).toList();

    return ObsidianDistributionChart(
      statsList: statsList,
      isViolin: true,
      palette: CustomAnalyticsPalettes.getPalette(widget.palette),
      canvasHeight: 200.0,
    );
  }

  Widget _renderRadarVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final measures = [widget.measure, ...widget.secondaryMeasures];
    final teams = _getAllUniqueTeams().take(4).toList();
    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);

    return CustomPaint(
      size: const Size(double.infinity, double.infinity),
      painter: _RadarChartPainter(
        measures: measures.map((m) => _getFieldLabel(m)).toList(),
        teams: teams,
        dataset: entries,
        measureIds: measures,
        colors: colors,
        isDark: ObsidianUITheme.isDark(context),
      ),
    );
  }

  Widget _renderHistogramVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final values = entries.map((e) => (e[widget.measure] is num ? (e[widget.measure] as num).toDouble() : 0.0)).toList();
    if (values.isEmpty) return const SizedBox.shrink();

    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);
    const binsCount = 6;
    final range = maxVal - minVal;
    final binWidth = (range > 0) ? range / binsCount : 1.0;

    final bins = List.generate(binsCount, (i) {
      if (range == 0) {
        final count = i == 0 ? values.length : 0;
        return {'label': i == 0 ? minVal.toStringAsFixed(0) : '-', 'count': count};
      }
      final start = minVal + i * binWidth;
      final end = start + binWidth;
      final count = values.where((v) => i == binsCount - 1 ? (v >= start && v <= end) : (v >= start && v < end)).length;
      return {'label': '${start.toStringAsFixed(0)}-${end.toStringAsFixed(0)}', 'count': count};
    });

    final colors = CustomAnalyticsPalettes.getPalette(widget.palette);

    return BarChart(
      BarChartData(
        barGroups: bins.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: (e.value['count'] as int).toDouble(),
                color: colors[0],
                width: 20,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final idx = v.toInt();
                if (idx < 0 || idx >= bins.length) return const SizedBox.shrink();
                return Text(bins[idx]['label'] as String, style: TextStyle(fontSize: 8, color: ObsidianUITheme.getFaintTextColor(context)));
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 24),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _renderHeatmapVisual(CustomAnalyticsWidget widget, List<Map<String, dynamic>> entries) {
    final numFields = _dataset.fields.where((f) => f.type == 'number').take(6).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        children: numFields.map((f1) {
          return Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(f1.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              ...numFields.map((f2) {
                final corr = CustomAnalyticsMath.computeCorrelation(entries, f1.id, f2.id);
                final alpha = corr.abs().clamp(0.1, 1.0);
                return Container(
                  width: 44,
                  height: 34,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: (corr >= 0 ? ObsidianUITheme.primaryAccent : ObsidianUITheme.errorRed).withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      corr.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                );
              }),
            ],
          );
        }).toList(),
      ),
    );
  }

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
    }

    final filteredEntries = _getFilteredEntries();
    final allTeams = _getAllUniqueTeams();
    final filteredTeams = _teamSearch.trim().isEmpty
        ? allTeams
        : allTeams.where((t) => t.toString().contains(_teamSearch.trim())).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Studio Toolbar
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: _openRenameDialog,
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _currentReport.title,
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _currentReport.category,
                                style: const TextStyle(fontSize: 10, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit, size: 14, color: ObsidianUITheme.getFaintTextColor(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Action Buttons Bar
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildToolbarButton('Reports', Icons.folder_open_rounded, () => _openReportLibraryModal(false)),
                    _buildToolbarButton('Templates', Icons.auto_awesome_mosaic_rounded, _openTemplatesModal),
                    _buildToolbarButton(_isSlicersExpanded ? 'Hide Filters' : 'Filters', Icons.filter_alt_rounded, () {
                      setState(() => _isSlicersExpanded = !_isSlicersExpanded);
                    }),
                    _buildToolbarButton('New Metric', Icons.calculate_rounded, _openCalculatedMetricModal),
                    _buildToolbarButton('Add Visual', Icons.add_chart_rounded, () => _openWidgetEditor(-1), isPrimary: true),
                    _buildToolbarButton('Save', Icons.save_rounded, () => _openReportLibraryModal(true)),
                  ],
                ),
              ],
            ),
          ),

          // Global Slicers & Filters Ribbon
          if (_isSlicersExpanded)
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GLOBAL SLICERS & FILTERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context), letterSpacing: 0.5)),
                      Text('${_currentReport.slicers.teamNumbers.isEmpty ? "All" : _currentReport.slicers.teamNumbers.length} teams selected', style: const TextStyle(fontSize: 11, color: ObsidianUITheme.primaryAccent)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Event Filter
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _currentReport.slicers.eventKey,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Event Filter',
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All Events')),
                      ...{..._dataset.matchEntries.map((e) => e['eventKey']?.toString() ?? '')}.where((e) => e.isNotEmpty).map((ev) {
                        return DropdownMenuItem(value: ev, child: Text(ev.toUpperCase()));
                      }),
                    ],
                    onChanged: (v) {
                      setState(() => _currentReport.slicers.eventKey = v ?? '');
                      _reloadDataset();
                    },
                  ),
                  const SizedBox(height: 10),
                  // Scope checkboxes
                  Wrap(
                    spacing: 12,
                    children: [
                      _buildCheckbox('Practice', _currentReport.slicers.practice, (v) => setState(() => _currentReport.slicers.practice = v)),
                      _buildCheckbox('Quals', _currentReport.slicers.quals, (v) => setState(() => _currentReport.slicers.quals = v)),
                      _buildCheckbox('Playoffs', _currentReport.slicers.playoffs, (v) => setState(() => _currentReport.slicers.playoffs = v)),
                      _buildCheckbox('Prescout', _currentReport.slicers.includePrescout, (v) {
                        setState(() => _currentReport.slicers.includePrescout = v);
                        _reloadDataset();
                      }),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Team Selection bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Team Filter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context))),
                      Row(
                        children: [
                          _buildMiniChip('All', () => setState(() => _currentReport.slicers.teamNumbers = List.from(allTeams))),
                          const SizedBox(width: 4),
                          _buildMiniChip('Top 8', () => setState(() => _currentReport.slicers.teamNumbers = _getTop8Teams())),
                          const SizedBox(width: 4),
                          _buildMiniChip('Clear', () => setState(() => _currentReport.slicers.teamNumbers.clear())),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    onChanged: (v) => setState(() => _teamSearch = v),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filter team pills (e.g. 254)...',
                      hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 11),
                      prefixIcon: Icon(Icons.search, size: 16, color: ObsidianUITheme.getFaintTextColor(context)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 50,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: filteredTeams.map((teamNum) {
                        final isSelected = _currentReport.slicers.teamNumbers.contains(teamNum);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('$teamNum', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context))),
                            selected: isSelected,
                            selectedColor: ObsidianUITheme.primaryAccent,
                            backgroundColor: ObsidianUITheme.isDark(context) ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _currentReport.slicers.teamNumbers.add(teamNum);
                                } else {
                                  _currentReport.slicers.teamNumbers.remove(teamNum);
                                }
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          // Cross-Filter Banner
          if (_activeCrossFilterTeam != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ObsidianUITheme.primaryAccent),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('📌 Interactive Cross-Filter Active: Team $_activeCrossFilterTeam', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                  InkWell(
                    onTap: () => setState(() => _activeCrossFilterTeam = null),
                    child: const Text('Clear Filter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                  ),
                ],
              ),
            ),

          // Canvas Visual Grid
          if (_currentReport.widgets.isEmpty)
            ObsidianGlassCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.dashboard_customize_rounded, size: 48, color: ObsidianUITheme.primaryAccent),
                      const SizedBox(height: 12),
                      Text('Your Dashboard is Empty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
                      const SizedBox(height: 6),
                      Text('Add a visual or pick a starter template to get started:', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                        icon: const Icon(Icons.auto_awesome_mosaic_rounded, color: Colors.white, size: 18),
                        label: const Text('Choose a Starter Template', style: TextStyle(color: Colors.white)),
                        onPressed: _openTemplatesModal,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._currentReport.widgets.asMap().entries.map((entry) {
              return _buildWidgetCard(entry.value, entry.key, filteredEntries);
            }),
        ],
      ),
    );
  }

  Widget _buildToolbarButton(String label, IconData icon, VoidCallback onTap, {bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary
              ? ObsidianUITheme.primaryAccent
              : (ObsidianUITheme.isDark(context) ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isPrimary ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isPrimary ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          activeColor: ObsidianUITheme.primaryAccent,
          visualDensity: VisualDensity.compact,
          onChanged: (v) => onChanged(v ?? false),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: ObsidianUITheme.getPrimaryTextColor(context))),
      ],
    );
  }

  Widget _buildMiniChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// Custom Painter for Radar / Spider charts
class _RadarChartPainter extends CustomPainter {
  final List<String> measures;
  final List<int> teams;
  final List<Map<String, dynamic>> dataset;
  final List<String> measureIds;
  final List<Color> colors;
  final bool isDark;

  _RadarChartPainter({
    required this.measures,
    required this.teams,
    required this.dataset,
    required this.measureIds,
    required this.colors,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (measures.isEmpty || teams.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2.5;
    final count = measures.length;

    final gridPaint = Paint()
      ..color = isDark ? Colors.white12 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw background concentric polygons
    for (int step = 1; step <= 4; step++) {
      final r = radius * (step / 4.0);
      final path = Path();
      for (int i = 0; i < count; i++) {
        final angle = (i * 2 * pi / count) - (pi / 2);
        final pt = center + Offset(cos(angle) * r, sin(angle) * r);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Draw spoke lines
    for (int i = 0; i < count; i++) {
      final angle = (i * 2 * pi / count) - (pi / 2);
      final pt = center + Offset(cos(angle) * radius, sin(angle) * radius);
      canvas.drawLine(center, pt, gridPaint);
    }

    // Compute max for each measure
    final maxPerMeasure = List.generate(count, (mIdx) {
      double mMax = 1.0;
      final mId = measureIds[mIdx];
      for (final e in dataset) {
        final val = (e[mId] is num ? (e[mId] as num).toDouble() : 0.0);
        if (val > mMax) mMax = val;
      }
      return mMax;
    });

    // Draw team polygons
    for (int tIdx = 0; tIdx < teams.length; tIdx++) {
      final tNum = teams[tIdx];
      final teamData = dataset.where((e) {
        final t = (e['teamNumber'] is num) ? (e['teamNumber'] as num).toInt() : int.tryParse(e['teamNumber']?.toString() ?? '') ?? 0;
        return t == tNum;
      }).toList();

      final teamColor = colors[tIdx % colors.length];
      final fillPaint = Paint()
        ..color = teamColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      final linePaint = Paint()
        ..color = teamColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final path = Path();
      for (int i = 0; i < count; i++) {
        final mId = measureIds[i];
        final vals = teamData.map((e) => (e[mId] is num ? (e[mId] as num).toDouble() : 0.0)).toList();
        final avg = CustomAnalyticsMath.computeAggregation(vals, 'avg');
        final normalized = (avg / maxPerMeasure[i]).clamp(0.0, 1.0);

        final angle = (i * 2 * pi / count) - (pi / 2);
        final pt = center + Offset(cos(angle) * radius * normalized, sin(angle) * radius * normalized);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
