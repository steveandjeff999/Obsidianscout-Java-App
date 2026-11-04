import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/redis_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

// ============================================================================
// Redis Cache Management & Cluster Topology Screen
// Mirrors website redis-status.html and redis-status.js
// Strictly restricted to Superadministrators only with mobile responsiveness.
// ============================================================================

const Color _green = Color(0xFF10B981);
const Color _red = Color(0xFFEF4444);
const Color _orange = Color(0xFFF97316);
const Color _blue = Color(0xFF3B82F6);
const Color _purple = Color(0xFF8B5CF6);
const Color _muted = Color(0xFF94A3B8);
const Color _borderSubtle = Color(0xFF334155);

class RedisStatusScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onNavigateCluster;
  final VoidCallback? onNavigateSettings;

  const RedisStatusScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onNavigateCluster,
    this.onNavigateSettings,
  });

  @override
  State<RedisStatusScreen> createState() => _RedisStatusScreenState();
}

class _RedisStatusScreenState extends State<RedisStatusScreen> {
  static const int _statusRefreshIntervalSeconds = 4;
  static const int _configRefreshIntervalSeconds = 12;

  bool _isLoading = false;
  String? _errorMessage;

  RedisStatusResponse? _status;
  List<RedisNodeConfigDto> _nodes = [];

  Timer? _statusTimer;
  Timer? _configTimer;
  Timer? _installPollTimer;

  // Install Form
  String _selectedInstallTargetNode = 'all';
  final TextEditingController _sudoPasswordController =
      TextEditingController();
  bool _isInstalling = false;
  String? _installMessage;
  Color _installMessageColor = _blue;

  // Actions
  bool _isPurging = false;
  bool _isResizing = false;
  bool _isFailingOver = false;
  String? _actionMessage;
  Color _actionMessageColor = _green;

  // Config Form
  bool _cfgDirty = false;
  bool _cfgSaving = false;
  String? _cfgMessage;
  Color _cfgMessageColor = _green;
  List<String> _cfgResults = [];

  bool _formEnabled = false;
  bool _formRequirePassword = true;
  final TextEditingController _formPasswordController =
      TextEditingController();
  bool _formClearPassword = false;
  final TextEditingController _formHostController = TextEditingController();
  final TextEditingController _formPortController =
      TextEditingController(text: '6379');
  final TextEditingController _formMaxPercentController =
      TextEditingController(text: '40');
  final TextEditingController _formMinMbController =
      TextEditingController(text: '64');
  final TextEditingController _formMaxMbController =
      TextEditingController(text: '8192');
  bool _formPasswordSet = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) {
      _loadData();
      _startTimers();
    }
  }

  @override
  void didUpdateWidget(covariant RedisStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
      _startTimers();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _stopTimers();
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _sudoPasswordController.dispose();
    _formPasswordController.dispose();
    _formHostController.dispose();
    _formPortController.dispose();
    _formMaxPercentController.dispose();
    _formMinMbController.dispose();
    _formMaxMbController.dispose();
    super.dispose();
  }

  void _startTimers() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: _statusRefreshIntervalSeconds),
      (_) {
        if (mounted && widget.isVisible && !_isLoading) {
          _fetchStatusSilent();
        }
      },
    );

    _configTimer?.cancel();
    _configTimer = Timer.periodic(
      const Duration(seconds: _configRefreshIntervalSeconds),
      (_) {
        if (mounted && widget.isVisible && !_cfgDirty && !_cfgSaving) {
          _fetchConfigSilent();
        }
      },
    );
  }

  void _stopTimers() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _configTimer?.cancel();
    _configTimer = null;
    _installPollTimer?.cancel();
    _installPollTimer = null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final statusFuture = widget.apiService.fetchRedisStatus();
      final configFuture = widget.apiService.fetchRedisConfig();

      final res = await Future.wait([statusFuture, configFuture]);
      if (!mounted) return;

      final status = res[0] as RedisStatusResponse?;
      final config = res[1] as List<RedisNodeConfigDto>;

      setState(() {
        _status = status;
        _nodes = config;
        _isLoading = false;
        if (!_cfgDirty && config.isNotEmpty) {
          _fillFormFromNodes(config);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchStatusSilent() async {
    try {
      final status = await widget.apiService.fetchRedisStatus();
      if (!mounted) return;
      if (status != null) {
        setState(() {
          _status = status;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchConfigSilent() async {
    try {
      final config = await widget.apiService.fetchRedisConfig();
      if (!mounted) return;
      setState(() {
        _nodes = config;
        if (!_cfgDirty && config.isNotEmpty) {
          _fillFormFromNodes(config);
        }
      });
    } catch (_) {}
  }

  void _fillFormFromNodes(List<RedisNodeConfigDto> nodes) {
    final reachable = nodes.where((n) => n.reachable).toList();
    if (reachable.isEmpty) return;
    final ref = reachable.firstWhere((n) => n.isLocal, orElse: () => reachable.first);

    _formEnabled = ref.enabled;
    _formRequirePassword = ref.requirePassword;
    _formPasswordController.clear();
    _formClearPassword = false;
    _formPasswordSet = ref.passwordSet;
    _formHostController.text = ref.host;
    _formPortController.text = ref.port.toString();
    _formMaxPercentController.text = (ref.maxMemoryPercent * 100).round().toString();
    _formMinMbController.text = ref.minMemoryMb.toString();
    _formMaxMbController.text = ref.maxMemoryMb.toString();
    _cfgDirty = false;
  }

  Future<void> _handleInstall() async {
    final target = _selectedInstallTargetNode;
    final sudo = _sudoPasswordController.text.trim();

    setState(() {
      _isInstalling = true;
      _installMessage = 'Initiating background installation on $target...';
      _installMessageColor = _blue;
    });

    try {
      final results = await widget.apiService.installRedis(
        sudoPassword: sudo.isEmpty ? null : sudo,
        targetIp: target,
      );
      if (!mounted) return;

      final failed = results.where((r) => !r.success).toList();
      setState(() {
        _isInstalling = false;
        if (failed.isEmpty) {
          _installMessageColor = _green;
          _installMessage =
              'Installation started. Progress will update in the cluster table below.';
        } else {
          _installMessageColor = _red;
          _installMessage = failed
              .map((r) => '${r.targetIp}: ${r.message ?? "Failed"}')
              .join(' | ');
        }
      });

      _startInstallPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installMessageColor = _red;
        _installMessage = 'Failed to trigger install: $e';
      });
    }
  }

  void _startInstallPolling() {
    _installPollTimer?.cancel();
    int cycles = 0;
    _installPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      cycles++;
      await _fetchConfigSilent();
      await _fetchStatusSilent();
      if (cycles > 40) {
        t.cancel();
      }
    });
  }

  Future<void> _handlePurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: Text(
          ctx.tr('redis.purge_title', 'Purge Entire Cluster Cache?'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          ctx.tr('redis.purge_confirm',
              'This will flush all cached keys across the Redis cluster and broadcast an invalidation to all nodes.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('common.cancel', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.tr('redis.purge_btn', 'Purge All'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isPurging = true;
      _actionMessage = 'Purging cache...';
      _actionMessageColor = _blue;
    });

    try {
      final res = await widget.apiService.purgeRedisCache();
      if (!mounted) return;
      setState(() {
        _isPurging = false;
        _actionMessageColor = _green;
        _actionMessage = res?['message']?.toString() ??
            'Redis cache successfully flushed and invalidation broadcast.';
      });
      _fetchStatusSilent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPurging = false;
        _actionMessageColor = _red;
        _actionMessage = 'Failed to purge: $e';
      });
    }
  }

  Future<void> _handleResize() async {
    setState(() {
      _isResizing = true;
      _actionMessage = 'Recalculating memory limits...';
      _actionMessageColor = _blue;
    });

    try {
      final res = await widget.apiService.resizeRedisMemory();
      if (!mounted) return;
      final maxMb = res?['maxmemory_mb']?.toString();
      setState(() {
        _isResizing = false;
        _actionMessageColor = _green;
        _actionMessage = maxMb != null
            ? 'Memory auto-sizer re-evaluated: maxmemory set to $maxMb MB.'
            : 'Memory auto-sizer re-evaluated.';
      });
      _fetchStatusSilent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResizing = false;
        _actionMessageColor = _red;
        _actionMessage = 'Resize error: $e';
      });
    }
  }

  Future<void> _handleFailover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: Text(
          ctx.tr('redis.failover_title', 'Trigger Test Failover?'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          ctx.tr('redis.failover_confirm',
              'The current host node will resign leadership to verify standby replica promotion.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('common.cancel', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.tr('redis.failover_btn', 'Trigger Failover'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isFailingOver = true;
      _actionMessage = 'Resigning leadership...';
      _actionMessageColor = _blue;
    });

    try {
      final res = await widget.apiService.triggerRedisFailover();
      if (!mounted) return;
      setState(() {
        _isFailingOver = false;
        _actionMessageColor = _green;
        _actionMessage = res?['message']?.toString() ??
            'Lease resigned. Standby failover initiated.';
      });
      Future.delayed(const Duration(milliseconds: 1500), _fetchStatusSilent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFailingOver = false;
        _actionMessageColor = _red;
        _actionMessage = 'Failover error: $e';
      });
    }
  }

  Future<void> _handleSaveConfig() async {
    setState(() {
      _cfgSaving = true;
      _cfgMessage = 'Saving to all reachable nodes...';
      _cfgMessageColor = _blue;
      _cfgResults = [];
    });

    final percentVal = double.tryParse(_formMaxPercentController.text);
    final percent = percentVal != null ? (percentVal / 100.0) : 0.40;
    final port = int.tryParse(_formPortController.text) ?? 6379;
    final minMb = int.tryParse(_formMinMbController.text) ?? 64;
    final maxMb = int.tryParse(_formMaxMbController.text) ?? 8192;

    final req = RedisConfigUpdateRequest(
      enabled: _formEnabled,
      requirePassword: _formRequirePassword,
      password: _formPasswordController.text.trim().isNotEmpty
          ? _formPasswordController.text.trim()
          : null,
      clearPassword: _formClearPassword,
      host: _formHostController.text.trim(),
      port: port,
      maxMemoryPercent: percent,
      minMemoryMb: minMb,
      maxMemoryMb: maxMb,
    );

    try {
      final results = await widget.apiService.updateRedisConfig(req);
      if (!mounted) return;

      final savedCount = results.where((r) => r.success).length;
      final failedCount = results.length - savedCount;

      final resultLines = results.map((r) {
        return '${r.targetIp}: ${r.success ? "Saved and restarted" : ("Failed - " + (r.message ?? "unknown error"))}';
      }).toList();

      setState(() {
        _cfgSaving = false;
        _cfgResults = resultLines;
        if (failedCount == 0) {
          _cfgMessageColor = _green;
          _cfgMessage =
              'Saved successfully across all $savedCount reachable node(s).';
        } else {
          _cfgMessageColor = _red;
          _cfgMessage =
              'Saved to $savedCount node(s), but failed on $failedCount.';
        }
        _cfgDirty = false;
      });

      if (failedCount == 0) {
        ObsidianFeedback.showSuccess(
          context,
          message: 'Redis configuration updated on cluster',
        );
      } else {
        ObsidianFeedback.showWarning(
          context,
          message: 'Saved with some errors',
        );
      }

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _loadData();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cfgSaving = false;
        _cfgMessageColor = _red;
        _cfgMessage = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = widget.apiService.currentUser?.isSuperAdmin ?? false;
    final bottomPadding = widget.isBarsVisible ? 120.0 : 24.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: ObsidianUITheme.primaryAccent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
            children: [
              if (!isSuperAdmin) ...[
                _buildLockedCard(),
              ] else ...[
                _buildHeaderCard(),
                const SizedBox(height: 16),
                _buildInstallCard(),
                const SizedBox(height: 16),
                _buildMetricsGrid(),
                const SizedBox(height: 16),
                _buildTopologyCard(),
                const SizedBox(height: 16),
                _buildMemoryDiagnosticsCard(),
                const SizedBox(height: 16),
                _buildClusterActionsCard(),
                const SizedBox(height: 16),
                _buildSettingsCard(),
                const SizedBox(height: 16),
                _buildClusterNodesTable(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedCard() {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.lock_rounded, size: 48, color: _red),
            const SizedBox(height: 12),
            Text(
              context.tr('redis.locked_title', 'SuperAdmin Access Required'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('redis.locked_desc',
                  'You need superadministrator privileges to access Redis cache & cluster management.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final isReady = _status?.isReady ?? false;
    final badgeColor = isReady ? _green : _red;
    final badgeText = isReady ? 'ACTIVE (Cached)' : 'DEGRADED (Direct DB Fallback)';

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.memory_rounded, color: _red, size: 24),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('redis.title', 'Redis Cache & Topology'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('redis.subtitle',
                            'Real-time memory auto-sizing, leader election & telemetry'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onNavigateCluster != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: BorderSide(color: _purple.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.dns_rounded, size: 16),
                    label: Text(
                      context.tr('nav.cluster_management', 'Server Management'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: widget.onNavigateCluster,
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    border: Border.all(color: badgeColor.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  onPressed: _isLoading ? null : _loadData,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallCard() {
    final nodeOptions = <String>['all', ..._nodes.map((n) => n.nodeIp)];

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: _blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.tr('redis.install_title', 'Install & Deploy Redis on Nodes'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('redis.install_desc',
                  'Installs redis-server via package managers (apt-get, dnf, yum) on Linux, or WSL/Docker on Windows.'),
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                return Flex(
                  direction: isNarrow ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: isNarrow
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: isNarrow ? 0 : 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('redis.target_node', 'Target Node'),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: ObsidianUITheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _borderSubtle),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: nodeOptions.contains(_selectedInstallTargetNode)
                                    ? _selectedInstallTargetNode
                                    : 'all',
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(context.tr(
                                        'redis.all_nodes', 'All Cluster Nodes')),
                                  ),
                                  ..._nodes.map(
                                    (n) => DropdownMenuItem(
                                      value: n.nodeIp,
                                      child: Text(
                                        '${n.nodeIp}${n.isLocal ? " (this node)" : ""}',
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedInstallTargetNode = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isNarrow ? 0 : 12, height: isNarrow ? 10 : 0),
                    Expanded(
                      flex: isNarrow ? 0 : 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('redis.sudo_pw', 'Linux Sudo Password (optional)'),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _sudoPasswordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'Sudo password (unneeded for root/WSL)',
                              hintStyle: TextStyle(
                                  fontSize: 12, color: _muted),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: _borderSubtle),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isNarrow ? 0 : 12, height: isNarrow ? 12 : 0),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isInstalling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        context.tr('redis.install_btn', 'Install Redis on Target'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isInstalling ? null : _handleInstall,
                    ),
                  ],
                );
              },
            ),
            if (_installMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _installMessage!,
                style: TextStyle(
                  color: _installMessageColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final hits = _status?.hits ?? 0;
    final misses = _status?.misses ?? 0;
    final total = hits + misses;
    final isReady = _status?.isReady ?? false;
    final rateStr = total > 0
        ? ((hits / total) * 100).toStringAsFixed(1)
        : (isReady ? '100.0' : '0.0');

    final stampedes = _status?.stampedesAvoided ?? 0;
    final isHost = _status?.isHost ?? false;
    final roleStr = isHost ? 'MASTER (Host)' : 'STANDBY REPLICA';
    final activeEp = _status?.activeEndpoint ?? 'None';

    final savedMs = hits * 285;
    final savedStr = savedMs >= 1000
        ? '${(savedMs / 1000.0).toStringAsFixed(1)} s saved'
        : '$savedMs ms saved';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final cardWidth = isWide
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: context.tr('redis.hit_rate', 'Cache Hit Rate'),
                value: '$rateStr %',
                subtitle: '$hits hits / $misses misses (this node)',
                valueColor: _green,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: context.tr('redis.stampedes', 'Stampedes Avoided'),
                value: '$stampedes',
                subtitle: 'SingleFlight deduplicated DB loads',
                valueColor: ObsidianUITheme.primaryAccent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: context.tr('redis.role', 'Active Role'),
                value: roleStr,
                subtitle: 'Active: $activeEp',
                valueColor: isHost ? _green : _purple,
                fontSize: 16,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMetricCard(
                title: context.tr('redis.latency_saved', 'Est. Latency Saved'),
                value: savedStr,
                subtitle: '~285 ms avg saved per hit',
                valueColor: _green,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    Color? valueColor,
    double fontSize = 22,
  }) {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? ObsidianUITheme.getPrimaryTextColor(context),
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: _muted,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopologyCard() {
    final canHost = _status?.canHostRedis ?? false;
    final endpoint = _status?.activeEndpoint ?? 'None';
    final leaseHolder = _status?.leaseHolder ?? 'None';

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('redis.topo_title',
                  'Cluster Topology & Autonomous Leader Election'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                _buildInfoColumn(
                  label: context.tr('redis.host_cap', 'Host Capability (can_host)'),
                  value: canHost ? 'YES (Runtime Ready)' : 'NO (Client Only)',
                  valueColor: canHost ? _green : _orange,
                ),
                _buildInfoColumn(
                  label: context.tr('redis.active_endpoint', 'Active Redis Endpoint'),
                  value: endpoint,
                  isMonospace: true,
                ),
                _buildInfoColumn(
                  label: context.tr('redis.lease_holder', 'Coordinator / Lease Holder'),
                  value: leaseHolder,
                  isMonospace: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryDiagnosticsCard() {
    final assessment = _status?.memoryAssessment;
    final totalOs = assessment?.totalOsMb ?? 0;
    final availOs = assessment?.availableOsMb ?? 0;
    final maxRedis = assessment?.recommendedRedisMb ?? 0;
    final usedHuman = _status?.usedMemoryHuman ?? '0 MB';
    final usedBytes = _status?.usedMemoryBytes ?? 0;

    final maxBytes = maxRedis * 1024 * 1024;
    final pct = maxBytes > 0 ? (usedBytes / maxBytes).clamp(0.0, 1.0) : 0.0;

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('redis.memory_title', 'OS-Aware Dynamic Memory Auto-Sizing'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                _buildInfoColumn(
                  label: context.tr('redis.total_ram', 'Total System RAM'),
                  value: '$totalOs MB',
                ),
                _buildInfoColumn(
                  label: context.tr('redis.avail_ram', 'Available Host RAM'),
                  value: '$availOs MB',
                ),
                _buildInfoColumn(
                  label: context.tr('redis.max_mem', 'Configured MaxMemory'),
                  value: '$maxRedis MB',
                  valueColor: ObsidianUITheme.primaryAccent,
                ),
                _buildInfoColumn(
                  label: context.tr('redis.used_mem', 'Used Memory (Redis)'),
                  value: usedHuman,
                  valueColor: _green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 12,
                backgroundColor: _borderSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct > 0.85 ? _red : ObsidianUITheme.primaryAccent,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 MB',
                    style: TextStyle(fontSize: 11, color: _muted)),
                Text(
                  'Dynamic Eviction Threshold (allkeys-lru)',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClusterActionsCard() {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('redis.actions_title', 'Cluster Cache Actions'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('redis.actions_desc',
                  'Administrative operations executed through CockroachDB lease coordination and Redis Pub/Sub.'),
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red.withOpacity(0.15),
                    foregroundColor: _red,
                    elevation: 0,
                    side: BorderSide(color: _red.withOpacity(0.35)),
                  ),
                  icon: _isPurging
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: Text(
                    context.tr('redis.purge_btn_label', 'Purge Entire Cluster Cache'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isPurging ? null : _handlePurge,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ObsidianUITheme.primaryAccent,
                    side: BorderSide(
                        color: ObsidianUITheme.primaryAccent.withOpacity(0.4)),
                  ),
                  icon: _isResizing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    context.tr('redis.resize_btn_label', 'Recalculate Memory Limit'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: _isResizing ? null : _handleResize,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _orange,
                    side: BorderSide(color: _orange.withOpacity(0.4)),
                  ),
                  icon: _isFailingOver
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                    context.tr('redis.failover_btn_label', 'Trigger Graceful Failover'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: _isFailingOver ? null : _handleFailover,
                ),
              ],
            ),
            if (_actionMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _actionMessage!,
                style: TextStyle(
                  color: _actionMessageColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('redis.settings_title', 'Redis Settings (All Nodes)'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('redis.settings_desc',
                  'Saving writes these settings to app-config.json on every node and restarts Redis on each one.'),
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildSwitchRow(
                  label: context.tr('redis.enabled', 'Redis enabled'),
                  value: _formEnabled,
                  onChanged: (val) {
                    setState(() {
                      _formEnabled = val;
                      _cfgDirty = true;
                    });
                  },
                ),
                _buildSwitchRow(
                  label: context.tr('redis.require_pw', 'Require password'),
                  value: _formRequirePassword,
                  onChanged: (val) {
                    setState(() {
                      _formRequirePassword = val;
                      _cfgDirty = true;
                    });
                  },
                ),
                _buildSwitchRow(
                  label: context.tr('redis.clear_pw', 'Clear stored password'),
                  value: _formClearPassword,
                  onChanged: (val) {
                    setState(() {
                      _formClearPassword = val;
                      _cfgDirty = true;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 3 : 1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: isWide ? 2.5 : 4.0,
                  children: [
                    _buildTextField(
                      controller: _formPasswordController,
                      label: context.tr('redis.field_pw', 'Password'),
                      hint: _formPasswordSet
                          ? 'A custom password is set. Blank keeps it.'
                          : 'Blank derives from cluster secret',
                      obscureText: true,
                      enabled: _formRequirePassword,
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                    _buildTextField(
                      controller: _formHostController,
                      label: context.tr('redis.field_host', 'External Host (optional)'),
                      hint: 'Blank = nodes elect host',
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                    _buildTextField(
                      controller: _formPortController,
                      label: context.tr('redis.field_port', 'Port'),
                      hint: '6379',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                    _buildTextField(
                      controller: _formMaxPercentController,
                      label: context.tr('redis.field_max_pct', 'Max Share of Free RAM (%)'),
                      hint: '40',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                    _buildTextField(
                      controller: _formMinMbController,
                      label: context.tr('redis.field_min_mb', 'Min Memory (MB)'),
                      hint: '64',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                    _buildTextField(
                      controller: _formMaxMbController,
                      label: context.tr('redis.field_max_mb', 'Max Memory (MB)'),
                      hint: '8192',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _cfgDirty = true),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: _cfgSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    context.tr('redis.save_btn', 'Save to All Nodes'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _cfgSaving ? null : _handleSaveConfig,
                ),
                OutlinedButton(
                  onPressed: () {
                    _fillFormFromNodes(_nodes);
                    setState(() {
                      _cfgDirty = false;
                      _cfgMessage = null;
                      _cfgResults = [];
                    });
                  },
                  child: Text(context.tr('redis.reload_btn', 'Reload Settings')),
                ),
              ],
            ),
            if (_cfgMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _cfgMessage!,
                style: TextStyle(
                  color: _cfgMessageColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
            if (_cfgResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._cfgResults.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• $line',
                    style: TextStyle(
                      fontSize: 12,
                      color: line.contains('Failed') ? _red : _muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClusterNodesTable() {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('redis.nodes_table_title', 'Cluster Nodes Status'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    MaterialStateProperty.all(ObsidianUITheme.surface),
                columns: const [
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('Capability')),
                  DataColumn(label: Text('Enabled')),
                  DataColumn(label: Text('State')),
                  DataColumn(label: Text('Password')),
                  DataColumn(label: Text('Host:Port')),
                  DataColumn(label: Text('Memory')),
                  DataColumn(label: Text('Download / Progress')),
                ],
                rows: _nodes.map((n) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(n.nodeIp,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (n.isLocal) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _blue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'this node',
                                  style: TextStyle(fontSize: 10, color: _blue),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (n.canHostRedis ? _green : _orange)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n.canHostRedis ? 'Can Host' : 'Client Only',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: n.canHostRedis ? _green : _orange,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(n.enabled ? 'Yes' : 'No')),
                      DataCell(
                        Text(
                          !n.enabled
                              ? 'Off'
                              : (n.isReady
                                  ? (n.isHost ? 'Host (Master)' : 'Standby Replica')
                                  : 'Not connected'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: !n.enabled
                                ? _muted
                                : (n.isReady ? _green : _red),
                          ),
                        ),
                      ),
                      DataCell(Text(
                        !n.requirePassword
                            ? 'None'
                            : (n.passwordSet ? 'Custom' : 'Derived'),
                      )),
                      DataCell(Text('${n.host.isEmpty ? "Auto" : n.host}:${n.port}')),
                      DataCell(Text(
                          '${(n.maxMemoryPercent * 100).round()}% (${n.minMemoryMb}-${n.maxMemoryMb} MB)')),
                      DataCell(
                        Text(
                          n.installProgress ??
                              (n.canHostRedis ? 'Ready to Host' : 'Needs Install'),
                          style: TextStyle(
                            fontSize: 12,
                            color: n.installProgress != null
                                ? _blue
                                : (n.canHostRedis
                                    ? _green
                                    : _muted),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn({
    required String label,
    required String value,
    Color? valueColor,
    bool isMonospace = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: _muted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: isMonospace ? 'monospace' : null,
            color: valueColor ?? ObsidianUITheme.getPrimaryTextColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: ObsidianUITheme.primaryAccent,
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 11.5, color: _muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
