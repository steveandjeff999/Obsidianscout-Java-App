import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/team_match_models.dart';
import '../../theme/obsidian_ui_theme.dart';

class GraphDataSeries {
  final List<String> labels;
  final List<double> values;
  final String title;
  final String unit;
  final Color color;

  const GraphDataSeries({
    required this.labels,
    required this.values,
    required this.title,
    required this.unit,
    required this.color,
  });
}

class FullscreenGraphModal extends StatefulWidget {
  final int teamNumber;
  final TeamModel? team;
  final String initialDatasource; // 'scouted' | 'statbotics' | 'match13'
  final bool enableStatbotics;
  final bool enableMatch13;
  final GraphDataSeries Function(String datasource) dataProvider;

  const FullscreenGraphModal({
    super.key,
    required this.teamNumber,
    required this.team,
    this.initialDatasource = 'scouted',
    required this.enableStatbotics,
    required this.enableMatch13,
    required this.dataProvider,
  });

  @override
  State<FullscreenGraphModal> createState() => _FullscreenGraphModalState();
}

class _FullscreenGraphModalState extends State<FullscreenGraphModal> {
  late String _currentDatasource;
  late GraphDataSeries _currentSeries;

  @override
  void initState() {
    super.initState();
    _currentDatasource = widget.initialDatasource;
    _currentSeries = widget.dataProvider(_currentDatasource);
  }

  void _switchDatasource(String source) {
    setState(() {
      _currentDatasource = source;
      _currentSeries = widget.dataProvider(source);
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final isDark = ObsidianUITheme.isDark(context);
    final teamNick = widget.team?.nickname ?? widget.team?.name ?? '';
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 16,
        vertical: isCompact ? 12 : 24,
      ),
      child: Container(
        width: screenSize.width < 960 ? screenSize.width * 0.95 : 900,
        height: screenSize.height < 640 ? screenSize.height * 0.88 : 540,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black12,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(isCompact ? 12 : 20, 14, 10, 12),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Team #${widget.teamNumber}${teamNick.isNotEmpty ? ' — $teamNick' : ''}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: primaryTextColor,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Close',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildDatasourcePills(),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Team #${widget.teamNumber}${teamNick.isNotEmpty ? ' — $teamNick' : ''}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Performance Progression Across Matches',
                                style: TextStyle(fontSize: 12, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildDatasourcePills(),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
            ),

            const Divider(height: 1),

            // Chart Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 12 : 24,
                  isCompact ? 14 : 24,
                  isCompact ? 14 : 28,
                  isCompact ? 10 : 18,
                ),
                child: _currentSeries.values.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.show_chart_rounded, size: 48, color: secondaryTextColor.withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            Text(
                              'No ${_currentSeries.title} data recorded for Team #${widget.teamNumber}.',
                              style: TextStyle(fontSize: 13, color: secondaryTextColor, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      )
                    : _buildChart(isDark, primaryTextColor, secondaryTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatasourcePills() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillButton('scouted', 'Scouted'),
          if (widget.enableStatbotics) _buildPillButton('statbotics', 'Statbotics'),
          if (widget.enableMatch13) _buildPillButton('match13', 'Match 13'),
        ],
      ),
    );
  }

  Widget _buildPillButton(String key, String label) {
    final isActive = _currentDatasource == key;
    return InkWell(
      onTap: () => _switchDatasource(key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? ObsidianUITheme.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildChart(bool isDark, Color primaryTextColor, Color secondaryTextColor) {
    final values = _currentSeries.values;
    final labels = _currentSeries.labels;

    double minY = values.reduce((a, b) => a < b ? a : b);
    double maxY = values.reduce((a, b) => a > b ? a : b);
    if (minY > 0) minY = 0;
    if (maxY == minY) maxY += 10;
    final yInterval = ((maxY - minY) / 5).clamp(1.0, 100.0);

    final spots = <FlSpot>[];
    for (int i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY * 1.12,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (val) => FlLine(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (val) => FlLine(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 1,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[idx],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: yInterval,
              getTitlesWidget: (val, meta) {
                return Text(
                  val.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: secondaryTextColor,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
            left: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xE60F172A),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final matchLabel = idx >= 0 && idx < labels.length ? labels[idx] : 'Match ${idx + 1}';
                return LineTooltipItem(
                  '$matchLabel\n',
                  const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: '${spot.y.toStringAsFixed(1)} ${_currentSeries.unit}',
                      style: TextStyle(color: _currentSeries.color, fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: _currentSeries.color,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 5.5,
                  color: _currentSeries.color,
                  strokeWidth: 2,
                  strokeColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: _currentSeries.color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
