import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/obsidian_ui_theme.dart';
import '../models/team_match_models.dart';
import '../screens/team_details_screen.dart';
import '../services/api_service.dart';

/// Haptic helper for chart interactions
class ObsidianChartHaptics {
  static void lightTouch() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  static void impact() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }
}

/// Custom scroll behavior enabling drag-to-scroll on PC (mouse, trackpad) and mobile.
class ObsidianChartScrollBehavior extends MaterialScrollBehavior {
  const ObsidianChartScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Model for interactive legend items
class ChartLegendSeries {
  final String name;
  final Color color;
  final bool isVisible;
  final bool isDimmed;

  const ChartLegendSeries({
    required this.name,
    required this.color,
    this.isVisible = true,
    this.isDimmed = false,
  });

  ChartLegendSeries copyWith({
    String? name,
    Color? color,
    bool? isVisible,
    bool? isDimmed,
  }) {
    return ChartLegendSeries(
      name: name ?? this.name,
      color: color ?? this.color,
      isVisible: isVisible ?? this.isVisible,
      isDimmed: isDimmed ?? this.isDimmed,
    );
  }
}

/// Reusable interactive container wrapping any chart with controls, legend, and inspection
class ObsidianChartInteractiveWrapper extends StatefulWidget {
  final String title;
  final Widget chart;
  final List<ChartLegendSeries>? legendSeries;
  final ValueChanged<int>? onToggleSeries;
  final ValueChanged<int?>? onHoverSeries;
  final bool showDataLabels;
  final ValueChanged<bool>? onToggleDataLabels;
  final bool showBenchmark;
  final ValueChanged<bool>? onToggleBenchmark;
  final double? benchmarkValue;
  final String? benchmarkLabel;
  final double minContentWidth;
  final double chartHeight;
  final VoidCallback? onRefresh;
  final WidgetBuilder? fullscreenChartBuilder;
  final String? subtitle;

  const ObsidianChartInteractiveWrapper({
    super.key,
    required this.title,
    required this.chart,
    this.legendSeries,
    this.onToggleSeries,
    this.onHoverSeries,
    this.showDataLabels = false,
    this.onToggleDataLabels,
    this.showBenchmark = false,
    this.onToggleBenchmark,
    this.benchmarkValue,
    this.benchmarkLabel,
    this.minContentWidth = 0.0,
    this.chartHeight = 320.0,
    this.onRefresh,
    this.fullscreenChartBuilder,
    this.subtitle,
  });

  @override
  State<ObsidianChartInteractiveWrapper> createState() =>
      _ObsidianChartInteractiveWrapperState();
}

class _ObsidianChartInteractiveWrapperState
    extends State<ObsidianChartInteractiveWrapper> {
  final ScrollController _scrollController = ScrollController();
  double _zoomScale = 1.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    ObsidianChartHaptics.lightTouch();
    setState(() {
      _zoomScale = (_zoomScale + 0.25).clamp(1.0, 3.0);
    });
  }

  void _zoomOut() {
    ObsidianChartHaptics.lightTouch();
    setState(() {
      _zoomScale = (_zoomScale - 0.25).clamp(1.0, 3.0);
    });
  }

  void _resetZoom() {
    ObsidianChartHaptics.lightTouch();
    setState(() {
      _zoomScale = 1.0;
    });
  }

  void _openFullscreenModal(BuildContext context) {
    ObsidianChartHaptics.impact();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 750),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fullscreen_rounded,
                            color: ObsidianUITheme.primaryAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ObsidianUITheme.getPrimaryTextColor(context),
                              ),
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ObsidianUITheme.getSecondaryTextColor(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: widget.fullscreenChartBuilder != null
                        ? widget.fullscreenChartBuilder!(dialogCtx)
                        : widget.chart,
                  ),
                  if (widget.legendSeries != null && widget.legendSeries!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildInteractiveLegend(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasZoomControls = widget.minContentWidth > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Toolbar
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: ObsidianUITheme.getPrimaryTextColor(context),
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: ObsidianUITheme.getTertiaryTextColor(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Controls Toolbar Buttons
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Benchmark line toggle
                if (widget.onToggleBenchmark != null)
                  _buildToolbarButton(
                    icon: Icons.show_chart_rounded,
                    tooltip: widget.showBenchmark
                        ? 'Hide Benchmark Line'
                        : 'Show Average Benchmark Line',
                    isActive: widget.showBenchmark,
                    onPressed: () {
                      ObsidianChartHaptics.lightTouch();
                      widget.onToggleBenchmark!(!widget.showBenchmark);
                    },
                  ),

                // Data labels toggle
                if (widget.onToggleDataLabels != null)
                  _buildToolbarButton(
                    icon: Icons.label_outline_rounded,
                    tooltip: widget.showDataLabels
                        ? 'Hide Value Labels'
                        : 'Show Value Labels',
                    isActive: widget.showDataLabels,
                    onPressed: () {
                      ObsidianChartHaptics.lightTouch();
                      widget.onToggleDataLabels!(!widget.showDataLabels);
                    },
                  ),

                // Zoom Out
                if (hasZoomControls && _zoomScale > 1.0)
                  _buildToolbarButton(
                    icon: Icons.zoom_out_rounded,
                    tooltip: 'Zoom Out',
                    onPressed: _zoomOut,
                  ),

                // Zoom In
                if (hasZoomControls && _zoomScale < 3.0)
                  _buildToolbarButton(
                    icon: Icons.zoom_in_rounded,
                    tooltip: 'Zoom In',
                    onPressed: _zoomIn,
                  ),

                // Reset Zoom
                if (hasZoomControls && _zoomScale > 1.0)
                  _buildToolbarButton(
                    icon: Icons.restart_alt_rounded,
                    tooltip: 'Reset Zoom',
                    onPressed: _resetZoom,
                  ),

                // Refresh
                if (widget.onRefresh != null)
                  _buildToolbarButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh Graph',
                    onPressed: widget.onRefresh!,
                  ),

                // Fullscreen
                _buildToolbarButton(
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'Fullscreen View',
                  onPressed: () => _openFullscreenModal(context),
                ),
              ],
            ),
          ],
        ),

        // Benchmark Pill Indicator if active
        if (widget.showBenchmark && widget.benchmarkValue != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 2,
                  color: ObsidianUITheme.primaryAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.benchmarkLabel ??
                      'Avg: ${widget.benchmarkValue!.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: ObsidianUITheme.primaryAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Interactive Scrollable / Scalable Chart Area
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final targetWidth = max(
              availableWidth,
              (widget.minContentWidth > 0 ? widget.minContentWidth : availableWidth) *
                  _zoomScale,
            );
            final overflows = targetWidth > availableWidth + 1.0;

            return Stack(
              children: [
                ScrollConfiguration(
                  behavior: const ObsidianChartScrollBehavior(),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: targetWidth,
                      height: widget.chartHeight,
                      child: widget.chart,
                    ),
                  ),
                ),

                // Scroll hints for desktop & mobile
                if (overflows)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              ObsidianUITheme.getSurfaceColor(context)
                                  .withValues(alpha: 0.8),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        // Interactive Legend Bar
        if (widget.legendSeries != null && widget.legendSeries!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildInteractiveLegend(),
        ],
      ],
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    final activeBg = ObsidianUITheme.primaryAccent.withValues(alpha: 0.22);
    final activeColor = ObsidianUITheme.primaryAccent;
    final inactiveColor = ObsidianUITheme.getSecondaryTextColor(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Icon(
              icon,
              size: 17,
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveLegend() {
    if (widget.legendSeries == null || widget.legendSeries!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: widget.legendSeries!.asMap().entries.map((entry) {
        final idx = entry.key;
        final series = entry.value;
        final isTappable = widget.onToggleSeries != null;

        return MouseRegion(
          cursor: isTappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) {
            if (isTappable && widget.onHoverSeries != null) {
              scheduleMicrotask(() {
                if (mounted) widget.onHoverSeries!(idx);
              });
            }
          },
          onExit: (_) {
            if (isTappable && widget.onHoverSeries != null) {
              scheduleMicrotask(() {
                if (mounted) widget.onHoverSeries!(null);
              });
            }
          },
          child: GestureDetector(
            onTap: () {
              if (isTappable) {
                ObsidianChartHaptics.lightTouch();
                widget.onToggleSeries!(idx);
              }
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: series.isVisible ? (series.isDimmed ? 0.35 : 1.0) : 0.4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: series.isVisible
                      ? series.color.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: series.isVisible
                        ? series.color.withValues(alpha: 0.45)
                        : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: series.isVisible ? series.color : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      series.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: series.isVisible
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: series.isVisible
                            ? ObsidianUITheme.getPrimaryTextColor(context)
                            : ObsidianUITheme.getTertiaryTextColor(context),
                        decoration: series.isVisible
                            ? TextDecoration.none
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Interactive Team Quick-Inspection Bottom Sheet / Modal
class ObsidianTeamQuickInspect {
  static Future<int?> show({
    required BuildContext context,
    required int teamNumber,
    required String? teamName,
    required String metricLabel,
    required double metricValue,
    required ApiService apiService,
    int? rank,
    int? totalRankCount,
    int? matchCount,
    double? teamMin,
    double? teamMax,
    double? teamAverage,
    bool showFilterButton = true,
    VoidCallback? onFilterToTeam,
  }) async {
    ObsidianChartHaptics.impact();

    final isDesktop = MediaQuery.of(context).size.width >= 650;

    if (isDesktop) {
      return await showDialog<int>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: _buildInspectContent(
                ctx,
                teamNumber: teamNumber,
                teamName: teamName,
                metricLabel: metricLabel,
                metricValue: metricValue,
                apiService: apiService,
                rank: rank,
                totalRankCount: totalRankCount,
                matchCount: matchCount,
                teamMin: teamMin,
                teamMax: teamMax,
                teamAverage: teamAverage,
                showFilterButton: showFilterButton || onFilterToTeam != null,
              ),
            ),
          ),
        ),
      );
    } else {
      return await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: _buildInspectContent(
              ctx,
              teamNumber: teamNumber,
              teamName: teamName,
              metricLabel: metricLabel,
              metricValue: metricValue,
              apiService: apiService,
              rank: rank,
              totalRankCount: totalRankCount,
              matchCount: matchCount,
              teamMin: teamMin,
              teamMax: teamMax,
              teamAverage: teamAverage,
              showFilterButton: showFilterButton || onFilterToTeam != null,
            ),
          ),
        ),
      );
    }
  }

  static Widget _buildInspectContent(
    BuildContext context, {
    required int teamNumber,
    required String? teamName,
    required String metricLabel,
    required double metricValue,
    required ApiService apiService,
    int? rank,
    int? totalRankCount,
    int? matchCount,
    double? teamMin,
    double? teamMax,
    double? teamAverage,
    bool showFilterButton = true,
  }) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar on mobile
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Team Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Team $teamNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: ObsidianUITheme.primaryAccent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                teamName ?? '',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rank != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$rank${totalRankCount != null ? " of $totalRankCount" : ""}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.tealAccent,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Primary Metric Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metricLabel,
                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metricValue.toStringAsFixed(
                        metricValue == metricValue.truncate() ? 0 : 2),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              if (matchCount != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Matches',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                    const SizedBox(height: 2),
                    Text('$matchCount',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor)),
                  ],
                ),
            ],
          ),
        ),

        // Stat Pills Row (Min, Avg, Max)
        if (teamMin != null && teamMax != null && teamAverage != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMiniStatBox(context, 'Min', teamMin.toStringAsFixed(1)),
              const SizedBox(width: 8),
              _buildMiniStatBox(context, 'Avg', teamAverage.toStringAsFixed(1),
                  isHighlight: true),
              const SizedBox(width: 8),
              _buildMiniStatBox(context, 'Max', teamMax.toStringAsFixed(1)),
            ],
          ),
        ],

        const SizedBox(height: 18),

        // Action Buttons Row
        Row(
          children: [
            if (showFilterButton) ...[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.filter_alt_rounded, size: 16),
                  label: const Text('Filter Only'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: ObsidianUITheme.primaryAccent,
                    side: BorderSide(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(teamNumber);
                  },
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.analytics_rounded, size: 16),
                label: const Text('Team Details'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeamDetailsScreen(
                        team: TeamModel(
                          eventKey: '',
                          teamKey: 'frc$teamNumber',
                          teamNumber: teamNumber,
                          nickname: teamName ?? 'Team $teamNumber',
                        ),
                        apiService: apiService,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildMiniStatBox(
      BuildContext context, String label, String value,
      {bool isHighlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isHighlight
              ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlight
                ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)
                : ObsidianUITheme.getBorderColor(context),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isHighlight
                    ? ObsidianUITheme.primaryAccent
                    : ObsidianUITheme.getSecondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isHighlight
                    ? ObsidianUITheme.primaryAccent
                    : ObsidianUITheme.getPrimaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
