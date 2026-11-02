import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cluster_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

// ============================================================================
// Load Profiler Screen — Mirrors website load-profiler.html & load-profiler.js
// Strictly restricted to Superadministrators only with mobile responsiveness.
// ============================================================================

String _formatCount(num val) {
  final str = val.round().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }
  return buffer.toString();
}

String _formatClockTime(int epochMs, {bool withAmPm = true}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minute = dt.minute.toString().padLeft(2, '0');
  if (!withAmPm) return '$hour:$minute';
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

class LoadProfilerScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onNavigateCluster;
  final VoidCallback? onNavigateSettings;

  const LoadProfilerScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onNavigateCluster,
    this.onNavigateSettings,
  });

  @override
  State<LoadProfilerScreen> createState() => _LoadProfilerScreenState();
}

class _LoadProfilerScreenState extends State<LoadProfilerScreen> {
  static const int _refreshIntervalSeconds = 15;
  static const int _maxRoutesShown = 25;

  bool _isLoading = false;
  String? _errorMessage;

  ClusterLoadProfile? _latest;
  int _selectedWindowMinutes = 15;
  String _selectedNodeIp = 'all';

  Timer? _autoRefreshTimer;
  int? _hoveredMinuteIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(covariant LoadProfilerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
      _startAutoRefresh();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _stopAutoRefresh();
    }
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: _refreshIntervalSeconds),
      (_) {
        if (mounted && widget.isVisible && !_isLoading) {
          _loadData(silent: true);
        }
      },
    );
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  bool get _isSuperAdmin {
    final caller = widget.apiService.currentUser;
    return caller?.isSuperAdmin ??
        (widget.apiService.currentUserRole == 'SUPERADMIN');
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!_isSuperAdmin) return;
    if (_isLoading && !silent) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final profile = await widget.apiService
          .fetchClusterLoadProfile(minutes: _selectedWindowMinutes);

      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _latest = profile;
          _isLoading = false;
          _errorMessage = null;

          // Validate selected node
          final nodeIps = profile.nodes.map((n) => n.nodeIp).toSet();
          if (_selectedNodeIp != 'all' && !nodeIps.contains(_selectedNodeIp)) {
            _selectedNodeIp = 'all';
          }
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "Couldn't load the latest figures from server.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Couldn't load the latest figures: $e";
      });
    }
  }

  CombinedLoadProfile? _getCombinedProfile() {
    if (_latest == null) return null;
    final nodes = _selectedNodeIp == 'all'
        ? _latest!.nodes
        : _latest!.nodes.where((n) => n.nodeIp == _selectedNodeIp).toList();
    return combineProfiles(nodes);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    if (!_isSuperAdmin) {
      return _buildSuperadminLockedView();
    }

    final isDesktop = ObsidianResponsive.isDesktop(context,
        overrideMode: widget.apiService.uiMode);
    final combined = _getCombinedProfile();
    final summary = combined != null ? summarizeLoadProfile(combined) : null;

    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 24.0 : 14.0,
          16.0,
          isDesktop ? 24.0 : 14.0,
          widget.isBarsVisible ? 120.0 : 24.0,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isDesktop),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12.0),
                  _buildErrorBanner(_errorMessage!),
                ],
                if (_latest != null &&
                    _latest!.unreachableNodes.isNotEmpty) ...[
                  const SizedBox(height: 12.0),
                  _buildUnreachableBanner(_latest!.unreachableNodes),
                ],
                const SizedBox(height: 16.0),
                if (_isLoading && _latest == null)
                  const Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (combined != null && summary != null) ...[
                  _buildStatsGrid(isDesktop, summary, combined),
                  const SizedBox(height: 16.0),
                  _buildChartCard(isDesktop, combined),
                  const SizedBox(height: 16.0),
                  _buildHeaviestRoutesCard(isDesktop, combined),
                  const SizedBox(height: 16.0),
                  _buildInvalidationsByTopicCard(isDesktop, combined),
                ],
                const SizedBox(height: 32.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Superadmin Guard
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSuperadminLockedView() {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ObsidianGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 48.0,
                  color: Color(0xFFEF4444),
                ),
                const SizedBox(height: 16.0),
                Text(
                  'Superadmin Access Required',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'You must be logged in as a Superadmin (Site Admin) to view the Load Profiler.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.0, color: textSecondary),
                ),
                if (widget.onNavigateSettings != null) ...[
                  const SizedBox(height: 20.0),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 10.0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0)),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 16.0),
                    label: const Text(
                      'Return to Admin Settings',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: widget.onNavigateSettings,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Header & Controls
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDesktop) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16.0,
              runSpacing: 12.0,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(
                        Icons.speed_rounded,
                        color: Color(0xFFF97316),
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Load Profiler',
                          style: TextStyle(
                            fontSize: isDesktop ? 22.0 : 18.0,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'Real server load & live refresh traffic analysis',
                          style: TextStyle(
                            fontSize: 12.0,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10.0,
                  runSpacing: 8.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildWindowDropdown(),
                    if (_latest != null && _latest!.nodes.length > 1)
                      _buildNodeDropdown(),
                    if (widget.onNavigateCluster != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(
                              color: ObsidianUITheme.getBorderColor(context)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 8.0),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16.0),
                        label: const Text(
                          'Server Management',
                          style: TextStyle(
                              fontSize: 12.0, fontWeight: FontWeight.w600),
                        ),
                        onPressed: widget.onNavigateCluster,
                      ),
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18.0,
                              height: 18.0,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.0),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20.0),
                      tooltip: 'Refresh figures',
                      onPressed: _isLoading ? null : () => _loadData(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            Text(
              'What the servers are really doing, with pages updating themselves split from people using the site. Kept for the last hour; a restart clears it.',
              style: TextStyle(
                fontSize: 12.0,
                color: textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowDropdown() {
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.6),
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Window: ',
              style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500)),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedWindowMinutes,
              isDense: true,
              style: TextStyle(fontSize: 12.0, color: textPrimary),
              items: const [
                DropdownMenuItem(value: 5, child: Text('Last 5 minutes')),
                DropdownMenuItem(value: 15, child: Text('Last 15 minutes')),
                DropdownMenuItem(value: 60, child: Text('Last hour')),
              ],
              onChanged: (val) {
                if (val != null && val != _selectedWindowMinutes) {
                  setState(() {
                    _selectedWindowMinutes = val;
                  });
                  _loadData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeDropdown() {
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final nodes = _latest?.nodes ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.6),
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Node: ',
              style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedNodeIp,
              isDense: true,
              style: TextStyle(fontSize: 12.0, color: textPrimary),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('All nodes (${nodes.length})'),
                ),
                ...nodes.map(
                  (n) => DropdownMenuItem(
                    value: n.nodeIp,
                    child: Text(n.nodeIp),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedNodeIp = val;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
        border: Border.all(color: const Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 18.0),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreachableBanner(List<String> unreachableNodes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
        border: Border.all(color: const Color(0xFFF59E0B)),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 18.0),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              'No figures from ${unreachableNodes.join(", ")}, so the totals here are missing that traffic.',
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Headline Stats Grid
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildStatsGrid(
      bool isDesktop, LoadProfileSummary summary, CombinedLoadProfile profile) {
    final tiles = [
      _StatItem(
        label: 'Requests per second',
        value: formatLoadRate(summary.requestsPerSecond),
        detail: 'Peak minute ${formatLoadRate(summary.peakPerSecond)}/s',
        icon: Icons.speed_rounded,
        color: const Color(0xFF3B82F6),
      ),
      _StatItem(
        label: 'Live refresh per second',
        value: formatLoadRate(summary.livePerSecond),
        detail: '${formatLoadPercent(summary.liveShare)} of requests',
        icon: Icons.sync_rounded,
        color: const Color(0xFFF97316),
      ),
      _StatItem(
        label: 'Live refresh server time',
        value: formatLoadPercent(summary.liveServerShare),
        detail: 'Of all time spent answering',
        icon: Icons.timer_rounded,
        color: const Color(0xFFEC4899),
      ),
      _StatItem(
        label: 'Average response',
        value: formatLoadMs(summary.averageMs),
        detail: '${_formatCount(summary.errors)} server errors',
        icon: Icons.access_time_filled_rounded,
        color: const Color(0xFF10B981),
      ),
      _StatItem(
        label: 'Data sent per minute',
        value: formatLoadBytes(summary.bytesPerMinute),
        detail: '${formatLoadBytes(summary.liveBytes)} from live refresh',
        icon: Icons.cloud_upload_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      _StatItem(
        label: 'Users connected',
        value: _formatCount(profile.usersConnected),
        detail: '${_formatCount(summary.invalidations)} invalidations sent',
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF06B6D4),
      ),
      _StatItem(
        label: 'CPU',
        value: formatLoadPercent(profile.cpuLoad),
        detail: profile.nodeCount > 1 ? 'Busiest node, right now' : 'Right now',
        icon: Icons.memory_rounded,
        color: const Color(0xFFEAB308),
      ),
      _StatItem(
        label: 'Memory',
        value: formatLoadPercent(profile.heapShare),
        detail: profile.nodeCount > 1 ? 'Busiest node, right now' : 'Right now',
        icon: Icons.storage_rounded,
        color: const Color(0xFF14B8A6),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth >= 1000) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 600) {
          crossAxisCount = 3;
        }

        final double itemWidth =
            (constraints.maxWidth - ((crossAxisCount - 1) * 12.0)) /
                crossAxisCount;

        return Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          children: tiles.map((tile) {
            return SizedBox(
              width: itemWidth,
              child: _buildStatTile(tile),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStatTile(_StatItem item) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(item.icon, size: 16.0, color: item.color),
              ],
            ),
            const SizedBox(height: 6.0),
            Text(
              item.value,
              style: TextStyle(
                fontSize: 22.0,
                fontWeight: FontWeight.bold,
                color: textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              item.detail,
              style: TextStyle(
                fontSize: 11.0,
                color: textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Requests Per Minute Chart Card
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildChartCard(bool isDesktop, CombinedLoadProfile profile) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color liveColor =
        isDark ? const Color(0xFFD95926) : const Color(0xFFEB6834);
    final Color otherColor =
        isDark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Requests per minute',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLegendItem('Everything else', otherColor),
                    const SizedBox(width: 14.0),
                    _buildLegendItem('Live refresh', liveColor),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            if (profile.minutes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48.0),
                child: Center(
                  child: Text(
                    'No requests recorded in this window.',
                    style: TextStyle(color: textSecondary, fontSize: 13.0),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 240.0,
                child: _LoadChartWidget(
                  minutes: profile.minutes,
                  liveColor: liveColor,
                  otherColor: otherColor,
                  hoveredIndex: _hoveredMinuteIndex,
                  onHoverIndexChanged: (idx) {
                    setState(() {
                      _hoveredMinuteIndex = idx;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12.0),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8.0),
                  title: Text(
                    'Show as a table',
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: ObsidianUITheme.primaryAccent,
                    ),
                  ),
                  children: [
                    _buildMinutesTable(profile.minutes),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10.0,
          height: 10.0,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3.0),
          ),
        ),
        const SizedBox(width: 6.0),
        Text(
          label,
          style: TextStyle(fontSize: 12.0, color: textSecondary),
        ),
      ],
    );
  }

  Widget _buildMinutesTable(List<LoadMinute> minutes) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final reversedMinutes = minutes.reversed.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          Theme.of(context).cardColor.withValues(alpha: 0.5),
        ),
        dataRowMinHeight: 36.0,
        dataRowMaxHeight: 40.0,
        columnSpacing: 20.0,
        horizontalMargin: 12.0,
        border: TableBorder(
          horizontalInside:
              BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
        columns: const [
          DataColumn(
              label: Text('Minute',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
          DataColumn(
              numeric: true,
              label: Text('Requests',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
          DataColumn(
              numeric: true,
              label: Text('Live refresh',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
          DataColumn(
              numeric: true,
              label: Text('Server time',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
          DataColumn(
              numeric: true,
              label: Text('Data sent',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
          DataColumn(
              numeric: true,
              label: Text('Invalidations',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0))),
        ],
        rows: reversedMinutes.map((row) {
          final timeStr = _formatClockTime(row.minute);
          return DataRow(cells: [
            DataCell(Text(timeStr,
                style: TextStyle(fontSize: 12.0, color: textPrimary))),
            DataCell(Text(_formatCount(row.requests),
                style: TextStyle(fontSize: 12.0, color: textPrimary))),
            DataCell(Text(_formatCount(row.liveRequests),
                style: TextStyle(fontSize: 12.0, color: textPrimary))),
            DataCell(Text(formatLoadMs(row.serverMs),
                style: TextStyle(fontSize: 12.0, color: textSecondary))),
            DataCell(Text(formatLoadBytes(row.bytes),
                style: TextStyle(fontSize: 12.0, color: textSecondary))),
            DataCell(Text(_formatCount(row.invalidations),
                style: TextStyle(fontSize: 12.0, color: textSecondary))),
          ]);
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Heaviest Routes Card
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildHeaviestRoutesCard(bool isDesktop, CombinedLoadProfile profile) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    final totalServerMs =
        profile.routes.fold<double>(0.0, (sum, r) => sum + r.serverMs);
    final windowMinutes = _selectedWindowMinutes;
    final topRoutes = profile.routes.take(_maxRoutesShown).toList();

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Heaviest routes',
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              'Sorted by total server time, so a slow route used a little ranks with a fast one used a lot.',
              style: TextStyle(fontSize: 12.0, color: textSecondary),
            ),
            const SizedBox(height: 16.0),
            if (topRoutes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Text(
                    'No requests in this window.',
                    style: TextStyle(color: textSecondary, fontSize: 13.0),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).cardColor.withValues(alpha: 0.5),
                  ),
                  dataRowMinHeight: 40.0,
                  dataRowMaxHeight: 48.0,
                  columnSpacing: 18.0,
                  horizontalMargin: 12.0,
                  border: TableBorder(
                    horizontalInside:
                        BorderSide(color: borderColor.withValues(alpha: 0.5)),
                  ),
                  columns: const [
                    DataColumn(
                        label: Text('Route',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Requests',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Per min',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Live share',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Average',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Slowest',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Server time',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Data sent',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                  ],
                  rows: topRoutes.map((route) {
                    final liveShare = route.requests > 0
                        ? route.liveRequests / route.requests
                        : 0.0;
                    final avgMs = route.requests > 0
                        ? route.serverMs / route.requests
                        : 0.0;
                    final timeShare = totalServerMs > 0
                        ? route.serverMs / totalServerMs
                        : 0.0;
                    final perMin =
                        (route.requests / windowMinutes).toStringAsFixed(1);

                    return DataRow(cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320.0),
                          child: SelectableText(
                            route.route,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(_formatCount(route.requests),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(perMin,
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(formatLoadPercent(liveShare),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(formatLoadMs(avgMs),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(formatLoadMs(route.maxMs),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(formatLoadPercent(timeShare),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(formatLoadBytes(route.bytes),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invalidations by Topic Card
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildInvalidationsByTopicCard(
      bool isDesktop, CombinedLoadProfile profile) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invalidations by topic',
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              'The messages that tell open pages something changed. Each one can set off a refresh on every user it reaches.',
              style: TextStyle(fontSize: 12.0, color: textSecondary),
            ),
            const SizedBox(height: 16.0),
            if (profile.topics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Text(
                    'No invalidations in this window.',
                    style: TextStyle(color: textSecondary, fontSize: 13.0),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).cardColor.withValues(alpha: 0.5),
                  ),
                  dataRowMinHeight: 36.0,
                  dataRowMaxHeight: 40.0,
                  columnSpacing: 28.0,
                  horizontalMargin: 12.0,
                  border: TableBorder(
                    horizontalInside:
                        BorderSide(color: borderColor.withValues(alpha: 0.5)),
                  ),
                  columns: const [
                    DataColumn(
                        label: Text('Topic',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Messages',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                    DataColumn(
                        numeric: true,
                        label: Text('Users reached',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.0))),
                  ],
                  rows: profile.topics.map((t) {
                    return DataRow(cells: [
                      DataCell(Text(t.topic,
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textPrimary,
                              fontWeight: FontWeight.w500))),
                      DataCell(Text(_formatCount(t.messages),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                      DataCell(Text(_formatCount(t.usersReached),
                          style: TextStyle(
                              fontSize: 12.0,
                              color: textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  _StatItem({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

// ──────────────────────────────────────────────────────────────────────────
// Custom Chart Widget with Interactive Tooltip
// ──────────────────────────────────────────────────────────────────────────

class _LoadChartWidget extends StatelessWidget {
  final List<LoadMinute> minutes;
  final Color liveColor;
  final Color otherColor;
  final int? hoveredIndex;
  final ValueChanged<int?> onHoverIndexChanged;

  const _LoadChartWidget({
    required this.minutes,
    required this.liveColor,
    required this.otherColor,
    required this.hoveredIndex,
    required this.onHoverIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    final maxRequests = minutes.isEmpty
        ? 0
        : minutes.map((m) => m.requests).reduce((a, b) => a > b ? a : b);
    final topAxis = niceMaximum(maxRequests);

    return LayoutBuilder(
      builder: (context, constraints) {
        const double marginLeft = 48.0;
        const double marginRight = 12.0;
        const double marginTop = 12.0;
        const double marginBottom = 24.0;

        final plotWidth = constraints.maxWidth - marginLeft - marginRight;
        final plotHeight = constraints.maxHeight - marginTop - marginBottom;
        final band = plotWidth / (minutes.isEmpty ? 1 : minutes.length);
        final barWidth = (band - 2.0).clamp(2.0, 18.0);

        return Stack(
          children: [
            // Custom Painter for Gridlines, Bars and Axes
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _LoadChartPainter(
                minutes: minutes,
                topAxis: topAxis,
                liveColor: liveColor,
                otherColor: otherColor,
                gridColor: borderColor,
                axisTextColor: textSecondary,
                hoveredIndex: hoveredIndex,
                marginLeft: marginLeft,
                marginRight: marginRight,
                marginTop: marginTop,
                marginBottom: marginBottom,
                barWidth: barWidth,
                band: band,
                plotWidth: plotWidth,
                plotHeight: plotHeight,
              ),
            ),

            // Hit tester for mouse / gesture interaction
            Positioned(
              left: marginLeft,
              top: marginTop,
              width: plotWidth,
              height: plotHeight,
              child: MouseRegion(
                onHover: (event) {
                  final x = event.localPosition.dx;
                  final index = (x / band).floor().clamp(0, minutes.length - 1);
                  onHoverIndexChanged(index);
                },
                onExit: (_) => onHoverIndexChanged(null),
                child: GestureDetector(
                  onTapDown: (details) {
                    final x = details.localPosition.dx;
                    final index =
                        (x / band).floor().clamp(0, minutes.length - 1);
                    onHoverIndexChanged(index);
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            // Floating Tooltip
            if (hoveredIndex != null &&
                hoveredIndex! >= 0 &&
                hoveredIndex! < minutes.length)
              _buildTooltip(
                context: context,
                row: minutes[hoveredIndex!],
                hoveredIndex: hoveredIndex!,
                band: band,
                marginLeft: marginLeft,
                chartWidth: constraints.maxWidth,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTooltip({
    required BuildContext context,
    required LoadMinute row,
    required int hoveredIndex,
    required double band,
    required double marginLeft,
    required double chartWidth,
  }) {
    final others = row.requests - row.liveRequests;
    final timeStr = _formatClockTime(row.minute);
    final xPos = marginLeft + (band * hoveredIndex) + (band / 2);
    final flip = xPos > chartWidth / 2;

    return Positioned(
      top: 12.0,
      left: flip ? null : (xPos + 12.0).clamp(0.0, chartWidth - 190.0),
      right: flip
          ? (chartWidth - xPos + 12.0).clamp(0.0, chartWidth - 190.0)
          : null,
      child: IgnorePointer(
        child: Container(
          width: 180.0,
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
            borderRadius: BorderRadius.circular(8.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.0,
                ),
              ),
              const SizedBox(height: 4.0),
              Row(
                children: [
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: liveColor,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    'Live refresh: ${_formatCount(row.liveRequests)}',
                    style: const TextStyle(fontSize: 11.0),
                  ),
                ],
              ),
              const SizedBox(height: 2.0),
              Row(
                children: [
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: otherColor,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    'Everything else: ${_formatCount(others)}',
                    style: const TextStyle(fontSize: 11.0),
                  ),
                ],
              ),
              const SizedBox(height: 4.0),
              Text(
                'Server time: ${formatLoadMs(row.serverMs)}',
                style: const TextStyle(fontSize: 11.0),
              ),
              Text(
                'Data sent: ${formatLoadBytes(row.bytes)}',
                style: const TextStyle(fontSize: 11.0),
              ),
              Text(
                'Invalidations: ${_formatCount(row.invalidations)}',
                style: const TextStyle(fontSize: 11.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadChartPainter extends CustomPainter {
  final List<LoadMinute> minutes;
  final int topAxis;
  final Color liveColor;
  final Color otherColor;
  final Color gridColor;
  final Color axisTextColor;
  final int? hoveredIndex;
  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;
  final double barWidth;
  final double band;
  final double plotWidth;
  final double plotHeight;

  _LoadChartPainter({
    required this.minutes,
    required this.topAxis,
    required this.liveColor,
    required this.otherColor,
    required this.gridColor,
    required this.axisTextColor,
    required this.hoveredIndex,
    required this.marginLeft,
    required this.marginRight,
    required this.marginTop,
    required this.marginBottom,
    required this.barWidth,
    required this.band,
    required this.plotWidth,
    required this.plotHeight,
  });

  double _scale(double val) => (val / (topAxis > 0 ? topAxis : 1)) * plotHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = marginTop + plotHeight;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    // Y Axis Gridlines and Labels (0%, 50%, 100%)
    final textStyle = TextStyle(
      color: axisTextColor,
      fontSize: 10.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    for (final share in [0.0, 0.5, 1.0]) {
      final y = baseline - (plotHeight * share);
      canvas.drawLine(
        Offset(marginLeft, y),
        Offset(size.width - marginRight, y),
        gridPaint,
      );

      final labelVal = (topAxis * share).round();
      final tp = TextPainter(
        text: TextSpan(
          text: _formatCount(labelVal),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(marginLeft - tp.width - 6.0, y - (tp.height / 2)),
      );
    }

    if (minutes.isEmpty) return;

    final labelEvery = (minutes.length / 6).ceil().clamp(1, minutes.length);

    for (var i = 0; i < minutes.length; i++) {
      final row = minutes[i];
      final slot = marginLeft + (band * i);
      final x = slot + ((band - barWidth) / 2);

      final others = (row.requests - row.liveRequests).clamp(0, row.requests);
      final otherHeight = _scale(others.toDouble());
      final liveHeight = _scale(row.liveRequests.toDouble());
      const stackGap = 1.5;

      // Draw hover highlight column
      if (hoveredIndex == i) {
        final highlightPaint = Paint()
          ..color = axisTextColor.withValues(alpha: 0.08);
        canvas.drawRect(
          Rect.fromLTWH(slot, marginTop, band, plotHeight),
          highlightPaint,
        );
      }

      // Draw "Everything Else" bottom bar
      if (others > 0) {
        final r = (row.liveRequests == 0) ? 3.0 : 0.0;
        final barRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, baseline - otherHeight, barWidth, otherHeight),
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
        );
        canvas.drawRRect(barRect, Paint()..color = otherColor);
      }

      // Draw "Live Refresh" top stacked bar
      if (row.liveRequests > 0) {
        final gap = others > 0 ? stackGap : 0.0;
        final y = baseline - otherHeight - gap - liveHeight;
        final barRect = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, liveHeight),
          topLeft: const Radius.circular(3.0),
          topRight: const Radius.circular(3.0),
        );
        canvas.drawRRect(barRect, Paint()..color = liveColor);
      }

      // Draw X Axis Time Labels
      if (i % labelEvery == 0) {
        final timeStr = _formatClockTime(row.minute, withAmPm: false);
        final tp = TextPainter(
          text: TextSpan(text: timeStr, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(
          canvas,
          Offset(slot + (band / 2) - (tp.width / 2), size.height - 18.0),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoadChartPainter old) {
    return old.minutes != minutes ||
        old.topAxis != topAxis ||
        old.hoveredIndex != hoveredIndex ||
        old.liveColor != liveColor ||
        old.otherColor != otherColor;
  }
}
