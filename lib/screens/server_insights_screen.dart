import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/server_analytics_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/security_admin_panel.dart';

// ============================================================================
// Server Insights & Analytics Screen
// Superadministrator-only real-time cluster telemetry & diagnostics dashboard.
// ============================================================================

const Color _green = Color(0xFF10B981);
const Color _red = Color(0xFFEF4444);
const Color _orange = Color(0xFFF97316);
const Color _amber = Color(0xFFF59E0B);
const Color _sky = Color(0xFF38BDF8);
const Color _indigo = Color(0xFF6366F1);
const Color _violet = Color(0xFF8B5CF6);
const Color _rose = Color(0xFFF43F5E);

String _formatDuration(int ms) {
  if (ms < 1000) return '$ms ms';
  if (ms < 60 * 1000) return '${(ms / 1000).toStringAsFixed(1)} s';
  if (ms < 60 * 60 * 1000) return '${(ms / 60000).toStringAsFixed(1)} min';
  return '${(ms / 3600000).toStringAsFixed(1)} h';
}

class ServerInsightsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onNavigateLoadProfiler;
  final VoidCallback? onNavigateCluster;
  final VoidCallback? onNavigateSettings;

  const ServerInsightsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onNavigateLoadProfiler,
    this.onNavigateCluster,
    this.onNavigateSettings,
  });

  @override
  State<ServerInsightsScreen> createState() => _ServerInsightsScreenState();
}

class _ServerInsightsScreenState extends State<ServerInsightsScreen>
    with SingleTickerProviderStateMixin {
  static const int _refreshIntervalSeconds = 10;
  static const int _highChurnPerMinute = 30;
  static const int _longQueueMs = 60 * 1000;
  static const String _allNodes = 'all';

  bool _isLoading = false;
  String? _errorMessage;
  ClusterAnalyticsOverview? _cluster;
  String _selectedNodeIp = _allNodes;

  Timer? _autoRefreshTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    if (widget.isVisible) {
      _loadData();
      _startAutoRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant ServerInsightsScreen oldWidget) {
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
    _tabController.dispose();
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

  /// The figures on screen: the whole cluster, or the node picked in the header.
  ServerAnalyticsOverview? get _overview {
    final cluster = _cluster;
    if (cluster == null) return null;
    if (_selectedNodeIp == _allNodes) return cluster.combined;
    for (final node in cluster.nodes) {
      if (node.nodeIp == _selectedNodeIp) return node;
    }
    return cluster.combined;
  }

  bool get _showingWholeCluster =>
      _selectedNodeIp == _allNodes && (_cluster?.nodes.length ?? 0) > 1;

  String _t(String key, String fallback) =>
      context.tr('server_insights.$key', fallback);

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
      final cluster = await widget.apiService.fetchServerAnalyticsOverview();

      if (!mounted) return;

      if (cluster != null && cluster.combined != null) {
        setState(() {
          _cluster = cluster;
          _isLoading = false;
          _errorMessage = null;
          if (!cluster.nodes.any((n) => n.nodeIp == _selectedNodeIp)) {
            _selectedNodeIp = _allNodes;
          }
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = _t('error_unavailable',
              "Couldn't load the latest figures from the server.");
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            '${_t('error_unavailable', "Couldn't load the latest figures from the server.")} $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);

    if (!_isSuperAdmin) return _buildLockedView(primaryText, secondaryText);

    final overview = _overview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(primaryText, secondaryText),
        if (_errorMessage != null && overview != null)
          _buildBanner(Icons.error_outline_rounded, _rose, _errorMessage!),
        if (_cluster?.unreachableNodes.isNotEmpty ?? false)
          _buildBanner(
            Icons.cloud_off_rounded,
            _amber,
            '${_t('unreachable_nodes', 'Not responding, left out of these figures')}: ${_cluster!.unreachableNodes.join(', ')}',
          ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: ObsidianUITheme.primaryAccent,
          unselectedLabelColor: secondaryText,
          indicatorColor: ObsidianUITheme.primaryAccent,
          tabs: [
            Tab(
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                text: _t('tab_overview', 'Overview')),
            Tab(
                icon: const Icon(Icons.storage_rounded, size: 18),
                text: _t('tab_database', 'Database Pool')),
            Tab(
                icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                text: _t('tab_websockets', 'WebSockets')),
            Tab(
                icon: const Icon(Icons.devices_rounded, size: 18),
                text: _t('tab_fleet', 'Fleet & Sync')),
            Tab(
                icon: const Icon(Icons.memory_rounded, size: 18),
                text: _t('tab_jvm', 'JVM & Latency')),
            Tab(
                icon: const Icon(Icons.security_rounded, size: 18),
                text: _t('tab_security', 'Security & Audit')),
          ],
        ),
        Expanded(
          child: overview == null
              ? (_isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildErrorView(primaryText, secondaryText))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(overview, primaryText, secondaryText),
                    _buildDatabasePoolTab(
                        overview.dbPool, primaryText, secondaryText),
                    _buildWebSocketsTab(
                        overview.webSockets, primaryText, secondaryText),
                    _buildFleetTab(
                        overview.clientFleet, primaryText, secondaryText),
                    _buildJvmTab(overview, primaryText, secondaryText),
                    _buildSecurityTab(
                        overview.security, primaryText, secondaryText),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildLockedView(Color primaryText, Color secondaryText) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 48, color: _red),
            const SizedBox(height: 16),
            Text(
              _t('locked_title', 'Superadmin Access Required'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t('locked_body',
                  'Server Analytics & Telemetry is strictly restricted to system superadministrators.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color primaryText, Color secondaryText) {
    final cluster = _cluster;
    final showPicker = cluster != null && cluster.nodes.length > 1;

    return ObsidianGlassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: _green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('title', 'Server Insights & Telemetry'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryText,
                      ),
                    ),
                    Text(
                      '${_t('auto_refresh', 'Auto-refresh')}: ${_refreshIntervalSeconds}s',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: secondaryText),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t('refresh', 'Refresh'),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                onPressed: () => _loadData(),
              ),
              if (widget.onNavigateLoadProfiler != null)
                IconButton(
                  tooltip: context.tr('nav.load_profiler', 'Load Profiler'),
                  icon: const Icon(Icons.speed_rounded, color: _orange),
                  onPressed: widget.onNavigateLoadProfiler,
                ),
              if (widget.onNavigateCluster != null)
                IconButton(
                  tooltip:
                      context.tr('nav.cluster_management', 'Server Management'),
                  icon: const Icon(Icons.dns_rounded, color: _sky),
                  onPressed: widget.onNavigateCluster,
                ),
            ],
          ),
          if (showPicker)
            DropdownButton<String>(
              value: _selectedNodeIp,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: _allNodes,
                  child: Text(_t('all_nodes', 'All nodes')),
                ),
                for (final node in cluster.nodes)
                  DropdownMenuItem(
                    value: node.nodeIp,
                    child: Text(node.nodeIp),
                  ),
              ],
              onChanged: (ip) {
                if (ip != null) setState(() => _selectedNodeIp = ip);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBanner(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(Color primaryText, Color secondaryText) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: _red),
            const SizedBox(height: 16),
            Text(
              _t('unavailable_title', 'Telemetry Unavailable'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ??
                  _t('error_unavailable',
                      "Couldn't load the latest figures from the server."),
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_t('try_again', 'Try Again')),
              onPressed: () => _loadData(),
            ),
          ],
        ),
      ),
    );
  }

  /// A pull-to-refresh tab that clears the shell's bars at the bottom.
  Widget _buildTab(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            0, 8, 0, widget.isBarsVisible ? 120.0 : 24.0),
        children: children,
      ),
    );
  }

  // ==========================================================================
  // TAB 1: OVERVIEW SUMMARY
  // ==========================================================================
  Widget _buildOverviewTab(
      ServerAnalyticsOverview o, Color primaryText, Color secondaryText) {
    return _buildTab([
      _buildMetricTile(
        icon: Icons.speed_rounded,
        iconColor: _green,
        title: _t('p95_latency', 'p95 Latency'),
        value: '${o.latency.p95Ms.toStringAsFixed(1)} ms',
        subtitle:
            'p50: ${o.latency.p50Ms.toStringAsFixed(1)} ms | p99: ${o.latency.p99Ms.toStringAsFixed(1)} ms',
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildMetricTile(
        icon: Icons.storage_rounded,
        iconColor: o.dbPool.isHealthy ? _sky : _red,
        title: _t('db_pool', 'Hikari DB Pool'),
        value: '${o.dbPool.activeConnections} / ${o.dbPool.maxPoolSize}',
        subtitle:
            '${o.dbPool.saturationPercent}% ${_t('saturated', 'saturated')} | ${o.dbPool.threadsAwaiting} ${_t('queued', 'queued')}',
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildMetricTile(
        icon: Icons.wifi_tethering_rounded,
        iconColor: _violet,
        title: _t('tab_websockets', 'WebSockets'),
        value: '${o.webSockets.activeConnections}',
        subtitle:
            '${o.webSockets.connectedUsers} ${_t('users', 'users')} | ${o.webSockets.churnRatePerMinute} ${_t('churn_per_min', 'churn/min')}',
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      _buildMetricTile(
        icon: Icons.devices_rounded,
        iconColor: _amber,
        title: _t('client_fleet', 'Client Fleet'),
        value: '${o.clientFleet.totalActiveDevices}',
        subtitle:
            '${o.clientFleet.syncSubmissionsCount} ${_t('uploads', 'uploads')} | ${_t('avg_queue', 'avg queue')}: ${_formatDuration(o.clientFleet.avgIngestLagMs)}',
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.monitor_heart_rounded,
              color: _green,
              title: _t('vitals', 'Node Vitals'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 12),
            _buildProgressRow(
              label:
                  '${_t('heap_usage', 'Heap Memory')} (${o.jvm.usedHeapMb} / ${o.jvm.maxHeapMb} MB)',
              percent: (o.jvm.heapUsagePercent / 100.0).clamp(0.0, 1.0),
              color: o.jvm.heapUsagePercent > 85 ? _red : _green,
              primaryText: primaryText,
              secondaryText: secondaryText,
            ),
            const SizedBox(height: 12),
            _buildProgressRow(
              label:
                  '${_t('pool_saturation', 'Pool Saturation')} (${o.dbPool.activeConnections} / ${o.dbPool.maxPoolSize})',
              percent: (o.dbPool.saturationPercent / 100.0).clamp(0.0, 1.0),
              color: o.dbPool.saturationPercent > 80 ? _orange : _sky,
              primaryText: primaryText,
              secondaryText: secondaryText,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildPill(
                    '${_t('live_threads', 'Live Threads')}: ${o.jvm.liveThreads}',
                    _indigo),
                _buildPill(
                    '${_t('peak_threads', 'Peak Threads')}: ${o.jvm.peakThreads}',
                    _violet),
                _buildPill(
                    '${_t('gc_time', 'GC Time')}: ${o.jvm.gcTimeMs} ms (${o.jvm.gcCount})',
                    _green),
                _buildPill(
                    '${_t('total_requests', 'Total Requests')}: ${o.latency.totalRequests}',
                    _sky),
                _buildPill(
                    '4xx: ${o.latency.error4xxCount} | 5xx: ${o.latency.error5xxCount}',
                    _rose),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  // ==========================================================================
  // TAB 2: DATABASE POOL & TRANSACTIONS
  // ==========================================================================
  Widget _buildDatabasePoolTab(
      DatabasePoolMetrics db, Color primaryText, Color secondaryText) {
    return _buildTab([
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.storage_rounded,
              color: _sky,
              title: _t('pool_title', 'HikariCP Connection Pool'),
              primaryText: primaryText,
              trailing: _buildPill(
                db.isHealthy
                    ? _t('healthy', 'HEALTHY')
                    : _t('starvation', 'STARVATION WARNING'),
                db.isHealthy ? _green : _red,
              ),
            ),
            const SizedBox(height: 16),
            _buildProgressRow(
              label:
                  '${_t('pool_saturation', 'Pool Saturation')} (${db.saturationPercent}%)',
              percent: (db.saturationPercent / 100.0).clamp(0.0, 1.0),
              color: db.saturationPercent > 85 ? _red : _sky,
              primaryText: primaryText,
              secondaryText: secondaryText,
            ),
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem(_t('active_connections', 'Active Connections'),
                  '${db.activeConnections}'),
              _StatItem(_t('idle_connections', 'Idle Connections'),
                  '${db.idleConnections}'),
              _StatItem(_t('threads_awaiting', 'Threads Awaiting'),
                  '${db.threadsAwaiting}',
                  highlight: db.threadsAwaiting > 0),
              _StatItem(_t('total_connections', 'Total Connections'),
                  '${db.totalConnections}'),
              _StatItem(_t('max_pool', 'Max Pool Size'), '${db.maxPoolSize}'),
              _StatItem(_t('min_idle', 'Min Idle Target'), '${db.minIdle}'),
              _StatItem(_t('engine', 'Engine Type'), db.engineType.toUpperCase()),
            ], primaryText, secondaryText),
          ],
        ),
      ),
      _buildDiagnosisCard(
        title: _t('pool_diagnosis', 'Pool Health'),
        healthy: db.threadsAwaiting == 0,
        healthyText: _t('pool_ok',
            'No requests are waiting for a database connection.'),
        warningText: _t('pool_warning',
            'Requests are waiting for database connections. Consider increasing maximumPoolSize or investigating slow queries.'),
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
    ]);
  }

  // ==========================================================================
  // TAB 3: WEBSOCKETS & REAL-TIME
  // ==========================================================================
  Widget _buildWebSocketsTab(
      WebSocketMetrics ws, Color primaryText, Color secondaryText) {
    return _buildTab([
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.wifi_tethering_rounded,
              color: _violet,
              title: _t('ws_title', 'WebSocket Sessions & Churn'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem(_t('active_sockets', 'Active Sockets'),
                  '${ws.activeConnections}'),
              _StatItem(_t('connected_users', 'Connected Users'),
                  '${ws.connectedUsers}'),
              _StatItem(_t('connects_min', 'Connects / Min'),
                  '${ws.connectsLastMinute}'),
              _StatItem(_t('disconnects_min', 'Disconnects / Min'),
                  '${ws.disconnectsLastMinute}'),
              _StatItem(_t('churn_rate', 'Churn / Min'),
                  '${ws.churnRatePerMinute}',
                  highlight: ws.churnRatePerMinute > _highChurnPerMinute),
              _StatItem(_t('topic_broadcasts', 'Topic Broadcasts'),
                  '${ws.totalTopicBroadcasts}'),
              _StatItem(_t('dropped_messages', 'Dropped Messages'),
                  '${ws.droppedBroadcasts}',
                  highlight: ws.droppedBroadcasts > 0),
            ], primaryText, secondaryText),
          ],
        ),
      ),
      _buildDiagnosisCard(
        title: _t('churn_diagnosis', 'Connection Stability'),
        healthy: ws.churnRatePerMinute <= _highChurnPerMinute,
        healthyText:
            _t('churn_ok', 'WebSocket connections are stable.'),
        warningText: _t('churn_warning',
            'High churn usually means unstable venue Wi-Fi or reconnect loops on mobile devices.'),
        primaryText: primaryText,
        secondaryText: secondaryText,
      ),
    ]);
  }

  // ==========================================================================
  // TAB 4: CLIENT FLEET & OFFLINE INGESTION
  // ==========================================================================
  Widget _buildFleetTab(
      ClientFleetMetrics fleet, Color primaryText, Color secondaryText) {
    final longQueue = fleet.avgIngestLagMs > _longQueueMs;
    return _buildTab([
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.sync_rounded,
              color: _green,
              title: _t('sync_title', 'Offline Uploads'),
              primaryText: primaryText,
              trailing: _buildPill(
                longQueue
                    ? _t('long_waits', 'LONG WAITS')
                    : _t('prompt_uploads', 'PROMPT'),
                longQueue ? _amber : _green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t('sync_note',
                  'How long saved entries waited on a device before reaching the server.'),
              style: TextStyle(fontSize: 12, color: secondaryText),
            ),
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem(_t('active_devices', 'Active Devices (1h)'),
                  '${fleet.totalActiveDevices}'),
              _StatItem(_t('outbox_uploads', 'Outbox Uploads'),
                  '${fleet.syncSubmissionsCount}'),
              _StatItem(_t('avg_queue_time', 'Avg Queue Time'),
                  _formatDuration(fleet.avgIngestLagMs)),
              _StatItem(_t('max_queue_time', 'Max Queue Time'),
                  _formatDuration(fleet.maxIngestLagMs)),
            ], primaryText, secondaryText),
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.devices_rounded,
              color: _amber,
              title: _t('by_platform', 'Active Devices by Platform'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 12),
            if (fleet.clientsByPlatform.isEmpty)
              Text(_t('no_clients', 'No active clients in the last hour.'),
                  style: TextStyle(color: secondaryText))
            else
              ...fleet.clientsByPlatform.entries.map((e) {
                final total =
                    fleet.totalActiveDevices > 0 ? fleet.totalActiveDevices : 1;
                final pct = (e.value / total).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildProgressRow(
                    label: '${e.key}: ${e.value} (${(pct * 100).round()}%)',
                    percent: pct,
                    color: _getPlatformColor(e.key),
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                );
              }),
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.new_releases_rounded,
              color: _indigo,
              title: _t('by_version', 'App Versions in Use'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 12),
            if (fleet.clientsByVersion.isEmpty)
              Text(_t('no_versions', 'No client versions reported.'),
                  style: TextStyle(color: secondaryText))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fleet.clientsByVersion.entries.map((e) {
                  return _buildPill('${e.key} (${e.value})', _indigo);
                }).toList(),
              ),
          ],
        ),
      ),
    ]);
  }

  // ==========================================================================
  // TAB 5: JVM DIAGNOSTICS & LATENCY
  // ==========================================================================
  Widget _buildJvmTab(
      ServerAnalyticsOverview o, Color primaryText, Color secondaryText) {
    final jvm = o.jvm;
    final lat = o.latency;

    return _buildTab([
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.timer_rounded,
              color: _green,
              title: _t('latency_title', 'API Response Latency'),
              primaryText: primaryText,
            ),
            if (_showingWholeCluster) ...[
              const SizedBox(height: 8),
              Text(
                _t('latency_note', 'Percentiles show the slowest node.'),
                style: TextStyle(fontSize: 12, color: secondaryText),
              ),
            ],
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem('p50', '${lat.p50Ms.toStringAsFixed(1)} ms'),
              _StatItem('p90', '${lat.p90Ms.toStringAsFixed(1)} ms'),
              _StatItem('p95', '${lat.p95Ms.toStringAsFixed(1)} ms'),
              _StatItem('p99', '${lat.p99Ms.toStringAsFixed(1)} ms',
                  highlight: lat.p99Ms > 250),
              _StatItem(_t('max_observed', 'Max Observed'),
                  '${lat.maxMs.toStringAsFixed(1)} ms'),
              _StatItem(_t('rate', 'Rate (req/s)'), '${lat.requestsPerSecond}'),
            ], primaryText, secondaryText),
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.memory_rounded,
              color: _amber,
              title: _t('jvm_title', 'JVM Memory & GC'),
              primaryText: primaryText,
              trailing: _buildPill(
                '${_t('uptime', 'Uptime')}: ${(jvm.uptimeSeconds / 3600).toStringAsFixed(1)} h',
                _sky,
              ),
            ),
            const SizedBox(height: 16),
            _buildProgressRow(
              label:
                  '${_t('heap_usage', 'Heap Memory')} (${jvm.usedHeapMb} / ${jvm.maxHeapMb} MB)',
              percent: (jvm.heapUsagePercent / 100.0).clamp(0.0, 1.0),
              color: jvm.heapUsagePercent > 85 ? _red : _green,
              primaryText: primaryText,
              secondaryText: secondaryText,
            ),
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem(
                  _t('non_heap', 'Non-Heap Used'), '${jvm.nonHeapUsedMb} MB'),
              _StatItem(
                  _t('live_threads', 'Live Threads'), '${jvm.liveThreads}'),
              _StatItem(
                  _t('peak_threads', 'Peak Threads'), '${jvm.peakThreads}'),
              _StatItem(_t('daemon_threads', 'Daemon Threads'),
                  '${jvm.daemonThreads}'),
              _StatItem(_t('gc_time', 'GC Time'), '${jvm.gcTimeMs} ms'),
              _StatItem(_t('gc_runs', 'GC Runs'), '${jvm.gcCount}'),
            ], primaryText, secondaryText),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _indigo,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.terminal_rounded, size: 18),
                label: Text(_t('view_dump', 'View Live Thread Dump')),
                onPressed: _showThreadDumpDialog,
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ==========================================================================
  // TAB 6: SECURITY & AUDIT TRAIL
  // ==========================================================================
  Widget _buildSecurityTab(
      SecurityInsightsMetrics sec, Color primaryText, Color secondaryText) {
    return _buildTab([
      SecurityAdminPanel(apiService: widget.apiService),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.security_rounded,
              color: _rose,
              title: _t('security_title', 'Security (Last Hour)'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 16),
            _buildStatGrid([
              _StatItem(_t('failed_logins', 'Failed Logins'),
                  '${sec.failedLoginsLastHour}',
                  highlight: sec.failedLoginsLastHour > 5),
              _StatItem(_t('rate_limit_hits', 'Rate Limit Hits'),
                  '${sec.rateLimitHitsLastHour}',
                  highlight: sec.rateLimitHitsLastHour > 0),
            ], primaryText, secondaryText),
          ],
        ),
      ),
      ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.receipt_long_rounded,
              color: _sky,
              title: _t('audit_title', 'Recent Security Events & Superadmin Actions'),
              primaryText: primaryText,
            ),
            const SizedBox(height: 12),
            if (sec.recentAuditLogs.isEmpty)
              Text(_t('audit_empty', 'Nothing recorded since the server started.'),
                  style: TextStyle(color: secondaryText))
            else
              for (final item in sec.recentAuditLogs)
                _buildAuditRow(item, primaryText, secondaryText),
          ],
        ),
      ),
    ]);
  }

  Widget _buildAuditRow(
      SecurityAuditItem item, Color primaryText, Color secondaryText) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
    final time = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: item.success ? _green : _red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildPill(item.action, _sky),
                    Text(time,
                        style: TextStyle(color: secondaryText, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.username} (${item.role})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryText,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.details} | IP: ${item.ipAddress}',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // THREAD DUMP MODAL
  // ==========================================================================
  void _showThreadDumpDialog() {
    final nodeIp = _selectedNodeIp == _allNodes ? null : _selectedNodeIp;
    showDialog<void>(
      context: context,
      builder: (context) => _ThreadDumpDialog(
        load: () => widget.apiService.fetchServerThreadDump(nodeIp: nodeIp),
      ),
    );
  }

  // ==========================================================================
  // WIDGET HELPERS
  // ==========================================================================
  Widget _buildCardHeader({
    required IconData icon,
    required Color color,
    required String title,
    required Color primaryText,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: primaryText,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _buildDiagnosisCard({
    required String title,
    required bool healthy,
    required String healthyText,
    required String warningText,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                healthy
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: healthy ? _green : _amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthy ? healthyText : warningText,
                  style: TextStyle(fontSize: 13, color: secondaryText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return ObsidianGlassCard(
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: secondaryText,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryText),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow({
    required String label,
    required double percent,
    required Color color,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12, color: primaryText, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: secondaryText.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildStatGrid(
      List<_StatItem> stats, Color primaryText, Color secondaryText) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: stats.map((s) {
        return SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.label,
                  style: TextStyle(fontSize: 11, color: secondaryText)),
              const SizedBox(height: 2),
              Text(
                s.value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: s.highlight ? _red : primaryText,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return _green;
      case 'ios':
        return _sky;
      case 'windows':
        return _indigo;
      case 'macos':
        return _violet;
      case 'linux':
        return _amber;
      default:
        return const Color(0xFF94A3B8);
    }
  }
}

/// Loads the dump itself, because a dialog doesn't rebuild when the screen behind it does.
class _ThreadDumpDialog extends StatefulWidget {
  final Future<String?> Function() load;

  const _ThreadDumpDialog({required this.load});

  @override
  State<_ThreadDumpDialog> createState() => _ThreadDumpDialogState();
}

class _ThreadDumpDialogState extends State<_ThreadDumpDialog> {
  bool _isLoading = true;
  String? _dump;

  String _t(String key, String fallback) =>
      context.tr('server_insights.$key', fallback);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    String? dump;
    try {
      dump = await widget.load();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _dump = dump;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final dump = _dump;

    return AlertDialog(
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _t('dump_title', 'JVM Thread Dump'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: primaryText),
            ),
          ),
          IconButton(
            tooltip: _t('dump_copy', 'Copy to Clipboard'),
            icon: Icon(Icons.copy_rounded, color: secondaryText, size: 20),
            onPressed: dump == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: dump));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            _t('dump_copied', 'Thread dump copied to clipboard'))));
                  },
          ),
          IconButton(
            tooltip: _t('refresh', 'Refresh'),
            icon: Icon(Icons.refresh_rounded, color: secondaryText, size: 20),
            onPressed: _isLoading ? null : _load,
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: Icon(Icons.close_rounded, color: secondaryText, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: SelectableText(
                  dump ?? _t('dump_unavailable', 'No thread dump available.'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: primaryText,
                  ),
                ),
              ),
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final bool highlight;
  _StatItem(this.label, this.value, {this.highlight = false});
}
