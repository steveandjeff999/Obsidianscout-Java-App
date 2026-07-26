import 'package:flutter/material.dart';
import '../widgets/obsidian_glass_card.dart';
import '../models/config_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  final ApiService apiService;

  const AnalyticsScreen({super.key, required this.apiService});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<AnalyticsWidgetModel> _widgets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  void _fetchAnalytics() async {
    final data = await widget.apiService.fetchAnalyticsWidgets();
    setState(() {
      _widgets = data;
      _isLoading = false;
    });
  }

  Widget _buildBarChart(BuildContext context, List<AnalyticsSeriesPointModel> series) {
    if (series.isEmpty) {
      return Text('No chart data recorded yet', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context), fontSize: 12.0));
    }

    double maxVal = 1.0;
    for (var point in series) {
      if (point.value > maxVal) maxVal = point.value;
    }

    return Column(
      children: series.map((point) {
        double pct = (point.value / maxVal).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(point.label, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13.0)),
                  Text(point.value.toStringAsFixed(1), style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13.0)),
                ],
              ),
              const SizedBox(height: 4.0),
              LayoutBuilder(builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 8.0,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.getBorderColor(context),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: 8.0,
                      width: constraints.maxWidth * pct,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [ObsidianUITheme.primaryAccent, ObsidianUITheme.secondaryAccent],
                        ),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.successGreen),
      );
    }

    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 100.0, bottom: 120.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          ObsidianGlassCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.leaderboard_rounded, color: ObsidianUITheme.primaryAccent),
                ),
                const SizedBox(width: 14.0),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Competition Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryText)),
                    Text('Calculated from Server Scouting Entries', style: TextStyle(fontSize: 12.0, color: secondaryText)),
                  ],
                ),
              ],
            ),
          ),

          if (_widgets.isEmpty)
            ObsidianGlassCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No analytics data or scouting entries available on server.',
                    style: TextStyle(color: secondaryText),
                  ),
                ),
              ),
            ),

          // Render Real Dynamic Widgets returned by Server
          ..._widgets.map((widgetModel) {
            return ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widgetModel.title,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: primaryText),
                  ),
                  const SizedBox(height: 12.0),
                  if (widgetModel.type.toLowerCase() == 'bar')
                    _buildBarChart(context, widgetModel.series)
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Calculated Metric', style: TextStyle(color: secondaryText, fontSize: 13.0)),
                        Text(
                          widgetModel.value != null
                              ? (widgetModel.value! % 1 == 0 ? widgetModel.value!.toInt().toString() : widgetModel.value!.toStringAsFixed(2))
                              : '0',
                          style: const TextStyle(
                            fontSize: 28.0,
                            fontWeight: FontWeight.w900,
                            color: ObsidianUITheme.primaryAccent,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
