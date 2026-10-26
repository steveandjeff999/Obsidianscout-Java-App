import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Widgets generated from the analytics section of the match config. Same data as the website's analytics.html.
class AnalyticsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const AnalyticsScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  bool _usePrescout = false;
  List<AnalyticsWidgetModel> _widgets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final widgets = await widget.apiService.fetchAnalyticsWidgets(usePrescout: _usePrescout);
    if (!mounted) return;
    setState(() {
      _widgets = widgets;
      _loading = false;
    });
  }

  String _format(AnalyticsWidgetModel w) {
    final v = w.value;
    if (v == null) return '0';
    if (w.type == 'rate' || w.type == 'pct' || w.type == 'percentage') {
      return v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';
    }
    return fmtNum(v);
  }

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final metrics = _widgets.where((w) => w.type != 'bar').toList();
    final bars = _widgets.where((w) => w.type == 'bar').toList();
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('analytics.title', 'Analytics from config'),
          subtitle: context.tr('analytics.notice', 'Widgets are generated from the analytics section of the config JSON.'),
          child: Row(
            children: [
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _usePrescout,
                  title: Text(context.tr('analytics.include_prescout', 'Include Prescouting Data'),
                      style: TextStyle(fontSize: 14, color: primary)),
                  onChanged: (v) {
                    setState(() => _usePrescout = v);
                    _load();
                  },
                ),
              ),
              IconButton(
                tooltip: context.tr('analytics.refresh', 'Refresh'),
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (_loading)
          const PortedLoading()
        else if (_widgets.isEmpty)
          PortedSection(
            icon: Icons.bar_chart_rounded,
            title: context.tr('analytics.no_widgets_configured', 'No analytics widgets configured.'),
            subtitle: context.tr('analytics.no_widgets_hint',
                'Configure fields in your scouting settings or collect match data to see live analytics.'),
          )
        else ...[
          if (metrics.isNotEmpty)
            ObsidianGlassCard(
              padding: const EdgeInsets.all(16),
              child: PortedStatGrid(stats: [for (final w in metrics) PortedStat(w.title, _format(w))]),
            ),
          for (final w in bars)
            PortedSection(
              title: w.title,
              child: PortedBarSeries(series: [for (final s in w.series) MapEntry(s.label, s.value)]),
            ),
        ],
      ],
    );
  }
}
