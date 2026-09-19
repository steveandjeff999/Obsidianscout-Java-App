import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/cluster_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

// ============================================================================
// Cluster Management Screen — Mirrors website cluster-management.html/js
// Strictly restricted to Superadministrators only with mobile responsiveness.
// ============================================================================

class ClusterManagementScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ClusterManagementScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ClusterManagementScreen> createState() =>
      _ClusterManagementScreenState();
}

class _ClusterManagementScreenState extends State<ClusterManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Nodes
  ClusterNodesResponse? _nodesResponse;
  bool _nodesLoading = false;

  // Logs
  List<ServerLogEntry> _logs = [];
  bool _logsLoading = false;
  String _selectedLogNodeIp = 'all';
  final TextEditingController _logFilterController = TextEditingController();
  int _logLimit = 500;
  Timer? _logAutoRefreshTimer;
  bool _logAutoRefresh = false;

  // Load Balancer
  LoadBalancerStatus? _lbStatus;
  bool _lbLoading = false;

  // Stress Test
  StressTestStatus? _stressStatus;
  Timer? _stressPollTimer;

  // Alerts
  NodeAlertsEnrollment? _nodeAlerts;
  ServerErrorAlertsSettings? _errorAlerts;
  bool _alertsLoading = false;

  // Quorum Fallback
  List<QuorumFallbackNodeStatus> _qfNodes = [];
  bool _qfLoading = false;

  // Auto Backup & Snapshots
  AutoBackupCombinedStatus? _backupCombined;
  bool _backupLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCurrentTab();
  }

  @override
  void didUpdateWidget(ClusterManagementScreen old) {
    super.didUpdateWidget(old);
    if (widget.isVisible && !old.isVisible) {
      _loadCurrentTab();
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadCurrentTab();
  }

  void _loadCurrentTab() {
    // Hard Superadmin Guard: Do not load data for unauthorized users
    if (widget.apiService.currentUser?.isSuperAdmin != true) return;

    switch (_tabController.index) {
      case 0:
        _loadNodes();
        break;
      case 1:
        _loadLogs();
        break;
      case 2:
        _loadLbStatus();
        break;
      case 3:
        _loadAlerts();
        break;
      case 4:
        _loadQfStatus();
        break;
      case 5:
        _loadBackupStatus();
        break;
    }
  }

  // ─── Data Loaders ─────────────────────────────────────────────────────────

  Future<void> _loadNodes() async {
    if (_nodesLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _nodesLoading = true);
    final result = await widget.apiService.fetchClusterNodes();
    if (mounted) setState(() { _nodesResponse = result; _nodesLoading = false; });
  }

  Future<void> _loadLogs() async {
    if (_logsLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _logsLoading = true);
    final filter = _logFilterController.text.trim();
    List<ServerLogEntry> result;
    if (_selectedLogNodeIp == 'all') {
      result = await widget.apiService.fetchAllClusterLogs(
          limit: _logLimit, filter: filter.isEmpty ? null : filter);
    } else {
      result = await widget.apiService.fetchNodeLogs(_selectedLogNodeIp,
          limit: _logLimit, filter: filter.isEmpty ? null : filter);
    }
    if (mounted) setState(() { _logs = result; _logsLoading = false; });
  }

  Future<void> _loadLbStatus() async {
    if (_lbLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _lbLoading = true);
    final result = await widget.apiService.fetchLoadBalancerStatus();
    final stress = await widget.apiService.fetchStressTestStatus();
    if (mounted) {
      setState(() {
        _lbStatus = result;
        _stressStatus = stress;
        _lbLoading = false;
      });
      if (stress?.isRunning == true) {
        _startStressPolling();
      }
    }
  }

  void _startStressPolling() {
    _stressPollTimer?.cancel();
    _stressPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final s = await widget.apiService.fetchStressTestStatus();
      if (mounted) {
        setState(() => _stressStatus = s);
        if (s == null || !s.isRunning || s.remainingSeconds <= 0) {
          _stressPollTimer?.cancel();
          _loadLbStatus();
        }
      }
    });
  }

  Future<void> _loadAlerts() async {
    if (_alertsLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _alertsLoading = true);
    final r1 = await widget.apiService.fetchNodeAlertsEnrollment();
    final r2 = await widget.apiService.fetchErrorAlertSettings();
    if (mounted) setState(() { _nodeAlerts = r1; _errorAlerts = r2; _alertsLoading = false; });
  }

  Future<void> _loadQfStatus() async {
    if (_qfLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _qfLoading = true);
    final result = await widget.apiService.fetchQuorumFallbackStatus();
    if (mounted) setState(() { _qfNodes = result; _qfLoading = false; });
  }

  Future<void> _loadBackupStatus() async {
    if (_backupLoading || widget.apiService.currentUser?.isSuperAdmin != true) return;
    setState(() => _backupLoading = true);
    final result = await widget.apiService.fetchAutoBackupStatus();
    if (mounted) setState(() { _backupCombined = result; _backupLoading = false; });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'live':
      case 'online':
      case 'active':
      case 'healthy':
        return const Color(0xFF10B981);
      case 'suspect':
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'dead':
      case 'offline':
      case 'inactive':
      case 'error':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  Future<void> _showRebootDialog(String nodeIp, int nodeCount) async {
    final isAll = nodeIp == 'all';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.restart_alt_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(isAll ? 'Reboot Entire Cluster' : 'Reboot Node',
                style: const TextStyle(color: Colors.white, fontSize: 17),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: Text(
          isAll
              ? 'Are you sure you want to reboot ALL $nodeCount servers in the CockroachDB cluster?\n\nThis will send reboot signals to every server node.'
              : 'Are you sure you want to reboot server node $nodeIp?\n\nThis will terminate the node process and initiate a server reboot.',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reboot Now', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed == true) {
      _showSnack(isAll ? 'Dispatching reboot command to ENTIRE cluster…' : 'Initiating reboot for server node $nodeIp…');
      final result = await widget.apiService.rebootNode(nodeIp);
      _showSnack(result.message, isError: !result.success);
      if (result.success) Future.delayed(const Duration(seconds: 3), _loadNodes);
    }
  }

  Future<void> _showReinstallDialog(String nodeIp, int nodeCount) async {
    final isAll = nodeIp == 'all';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.system_update_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(isAll ? 'Confirm Reinstall ALL' : 'Confirm Force Reinstall',
                style: const TextStyle(color: Colors.white, fontSize: 17),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: Text(
          isAll
              ? 'Force reinstall and update ALL $nodeCount servers in the cluster?\n\nThis will trigger CockroachDB binary re-verification and pull release updates on every node.'
              : 'Force reinstall/update server node $nodeIp?\n\nThis will trigger binary verification, re-download CockroachDB binaries if corrupted, and pull release updates.',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Force Reinstall', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed == true) {
      _showSnack(isAll ? 'Dispatching force reinstall/update to ENTIRE cluster…' : 'Triggering force reinstall/update for node $nodeIp…');
      final result = await widget.apiService.reinstallNode(nodeIp);
      _showSnack(result.message, isError: !result.success);
    }
  }

  Future<void> _showKeyRegenDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.key_rounded, color: Color(0xFFA855F7)),
          SizedBox(width: 8),
          Expanded(
            child: Text('Regenerate Cluster Keys',
                style: TextStyle(color: Colors.white, fontSize: 17),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: const Text(
          'This will rotate session and VAPID push notification keys cluster-wide. All active sessions across all nodes will be invalidated. Are you sure?',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate Now', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed == true) {
      _showSnack('Rotating cluster session & VAPID keys…');
      final result = await widget.apiService.regenerateKeys();
      _showSnack(result.message, isError: !result.success);
    }
  }

  Future<void> _showAppConfigDialog(String nodeIp) async {
    final payload = await widget.apiService.fetchNodeAppConfig(nodeIp);
    if (!mounted) return;
    if (payload == null) {
      _showSnack('Failed to load app-config.json from $nodeIp', isError: true);
      return;
    }

    final controller = TextEditingController(
        text: payload.rawJson.isNotEmpty
            ? payload.rawJson
            : const JsonEncoder.withIndent('  ')
                .convert(payload.config ?? {}));
    String? jsonError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.settings_rounded, color: Color(0xFFC084FC), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Edit app-config.json',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('Target node: $nodeIp',
                                style: const TextStyle(color: Color(0xFFC084FC), fontSize: 11, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFF020617),
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.0, color: Color(0xFF38BDF8)),
                      decoration: const InputDecoration(border: InputBorder.none),
                      onChanged: (_) {
                        try {
                          jsonDecode(controller.text);
                          setDlg(() => jsonError = null);
                        } catch (e) {
                          setDlg(() => jsonError = e.toString());
                        }
                      },
                    ),
                  ),
                ),
                if (jsonError != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF450A0A),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(jsonError!,
                        style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: const Color(0xFF1E293B),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          jsonError == null ? '✓ Valid JSON' : '✗ Syntax Error',
                          style: TextStyle(
                              color: jsonError == null
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              fontSize: 11),
                        ),
                      ),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel',
                              style: TextStyle(color: Color(0xFF94A3B8)))),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: jsonError == null
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF374151)),
                        onPressed: jsonError != null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                _showSnack('Saving app-config.json to $nodeIp…');
                                final r = await widget.apiService
                                    .saveNodeAppConfig(nodeIp, controller.text);
                                _showSnack(r.message, isError: !r.success);
                              },
                        icon: const Icon(Icons.save_rounded, size: 14, color: Colors.white),
                        label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  // Load Balancer Configuration Modal (Mirrors web load-balancer-modal)
  Future<void> _showLbSettingsDialog() async {
    final settings = await widget.apiService.fetchLoadBalancerSettings();
    if (!mounted) return;
    if (settings == null) {
      _showSnack('Failed to load LB settings', isError: true);
      return;
    }

    final marginController = TextEditingController(
        text: settings.localPreferenceMargin.toString());
    final latencyController = TextEditingController(
        text: settings.maxExpectedLatencyMs.round().toString());
    final probeController = TextEditingController(
        text: settings.probeIntervalSeconds.toString());
    final timeoutController = TextEditingController(
        text: settings.forwardTimeoutSeconds.toString());
    final excludedController = TextEditingController(
        text: settings.excludedPathPrefixes.join(', '));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.tune_rounded, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Expanded(
            child: Text('Configure Cluster Load Balancer',
                style: TextStyle(color: Colors.white, fontSize: 16),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Settings are stored in CockroachDB and shared by every server node across the cluster.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 14),
                _buildTextField(marginController, 'Local Preference Margin (Tie Breaker)',
                    hint: '0.10',
                    helper: 'Peers must beat local score by at least this margin to trigger remote forward.'),
                const SizedBox(height: 10),
                _buildTextField(latencyController, 'Max Expected Latency Ceiling (ms)',
                    hint: '150',
                    helper: 'Latency normalization ceiling for score calculation (default: 150ms).'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(probeController, 'Probe Interval (s)',
                          hint: '15'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(timeoutController, 'Forward Timeout (s)',
                          hint: '30'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildTextField(excludedController, 'Excluded Path Prefixes (comma-separated)',
                    hint: '/api/admin, /api/cluster',
                    isNumeric: false,
                    helper: 'Paths that should never be forwarded across nodes.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () async {
              Navigator.pop(ctx);
              final excludedList = excludedController.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final updated = LoadBalancerSettings(
                enabled: _lbStatus?.enabled ?? settings.enabled,
                localPreferenceMargin: double.tryParse(marginController.text) ?? 0.10,
                maxExpectedLatencyMs: double.tryParse(latencyController.text) ?? 150.0,
                probeIntervalSeconds: int.tryParse(probeController.text) ?? 15,
                forwardTimeoutSeconds: int.tryParse(timeoutController.text) ?? 30,
                excludedPathPrefixes: excludedList.isNotEmpty
                    ? excludedList
                    : settings.excludedPathPrefixes,
              );
              final r = await widget.apiService.saveLoadBalancerSettings(updated);
              _showSnack(r.message, isError: !r.success);
              if (r.success) _loadLbStatus();
            },
            child: const Text('Save Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    marginController.dispose();
    latencyController.dispose();
    probeController.dispose();
    timeoutController.dispose();
    excludedController.dispose();
  }

  // Quorum Fallback Configuration Modal (Mirrors web quorum-config-modal)
  Future<void> _showQfConfigDialog(QuorumFallbackNodeStatus node) async {
    final cfg = node.config ?? const QuorumFallbackConfigDetails();
    bool mirrorAll = cfg.mirrorAllData;
    bool users = cfg.mirrorUsers;
    bool scouting = cfg.mirrorScouting;
    bool apiData = cfg.mirrorApiData;
    bool analytics = cfg.mirrorCustomAnalytics;
    bool alliances = cfg.mirrorAlliances;
    bool chat = cfg.mirrorChat;
    bool secrets = cfg.mirrorNotificationsSecrets;
    int retentionDays = cfg.scoutingRetentionDays;
    final intervalController =
        TextEditingController(text: cfg.syncIntervalSeconds.toString());
    final sqliteController =
        TextEditingController(text: cfg.sqliteFile);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.shield_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Customize Mirror: ${node.nodeIp}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select what datasets this specific node caches locally in SQLite for quorum loss fallback.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 12),
                  // Mode Selection
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setDlg(() => mirrorAll = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  mirrorAll ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: mirrorAll ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Mirror Everything (Full Replica)',
                                          style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                                      SizedBox(height: 2),
                                      Text('Caches all historical data without date cutoffs.',
                                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setDlg(() => mirrorAll = false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  !mirrorAll ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: !mirrorAll ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Customized Selective Cache',
                                          style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13)),
                                      SizedBox(height: 2),
                                      Text('Selective data categories & time retention window.',
                                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!mirrorAll) ...[
                    const SizedBox(height: 12),
                    const Text('Included Categories',
                        style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _filterChip('Users', users, (v) => setDlg(() => users = v)),
                        _filterChip('Scouting', scouting, (v) => setDlg(() => scouting = v)),
                        _filterChip('API Schedule', apiData, (v) => setDlg(() => apiData = v)),
                        _filterChip('Analytics', analytics, (v) => setDlg(() => analytics = v)),
                        _filterChip('Alliances', alliances, (v) => setDlg(() => alliances = v)),
                        _filterChip('Chat', chat, (v) => setDlg(() => chat = v)),
                        _filterChip('Secrets', secrets, (v) => setDlg(() => secrets = v)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: retentionDays,
                      decoration: _inputDecoration('Competition Window'),
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('±7 Days (1 Week - Recommended)')),
                        DropdownMenuItem(value: 14, child: Text('±14 Days (2 Weeks)')),
                        DropdownMenuItem(value: 30, child: Text('±30 Days (1 Month)')),
                        DropdownMenuItem(value: 90, child: Text('±90 Days (Quarter Season)')),
                        DropdownMenuItem(value: 365, child: Text('±365 Days (Full Year)')),
                      ],
                      onChanged: (v) => setDlg(() => retentionDays = v ?? 7),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(intervalController, 'Sync Interval (s)')),
                      const SizedBox(width: 10),
                      Expanded(child: _buildTextField(sqliteController, 'SQLite File Path', isNumeric: false)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
              onPressed: () async {
                Navigator.pop(ctx);
                final updated = QuorumFallbackConfigDetails(
                  mirrorAllData: mirrorAll,
                  mirrorUsers: users,
                  mirrorScouting: scouting,
                  mirrorApiData: apiData,
                  mirrorCustomAnalytics: analytics,
                  mirrorConfigs: true,
                  mirrorAlliances: alliances,
                  mirrorChat: chat,
                  mirrorNotificationsSecrets: secrets,
                  scoutingRetentionDays: retentionDays,
                  syncIntervalSeconds: int.tryParse(intervalController.text) ?? 30,
                  sqliteFile: sqliteController.text.trim().isNotEmpty
                      ? sqliteController.text.trim()
                      : "data/quorum_fallback.db",
                );
                final r = await widget.apiService
                    .saveQuorumFallbackConfig(node.nodeIp, updated);
                _showSnack(r.message, isError: !r.success);
                if (r.success) _loadQfStatus();
              },
              child: const Text('Save Config', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    intervalController.dispose();
    sqliteController.dispose();
  }

  // Quorum Fallback Inspection Modal (Mirrors web quorum-inspect-modal)
  Future<void> _showQfInspectDialog(String nodeIp) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
    );
    final data = await widget.apiService.inspectQuorumFallback(nodeIp);
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    if (data == null) {
      _showSnack('Failed to inspect fallback database on $nodeIp', isError: true);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Fallback SQLite DB: $nodeIp',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B))),
                ]),
              ),
              // Body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    // Top stats row
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _statCard('Mirror Status', data.status, const Color(0xFFF59E0B)),
                      _statCard('DB File Size', _formatBytes(data.databaseSizeBytes), const Color(0xFF38BDF8)),
                      _statCard('Free Disk', '${_formatBytes(data.freeDiskSpaceBytes)} / ${_formatBytes(data.totalDiskSpaceBytes)}', const Color(0xFF10B981)),
                      _statCard('Last Synced', data.lastSyncTimestamp != null ? _shortTimestamp(data.lastSyncTimestamp!) : 'Never', const Color(0xFFA855F7)),
                    ]),
                    const SizedBox(height: 14),
                    // Mirrored events table (Horizontal scroll for mobile safe rendering)
                    const Text('Mirrored Events (±1 Week Competition Window)',
                        style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (data.activeEvents.isEmpty)
                      const Text('No active events within ±1 week stored in this snapshot.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5))
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 480),
                          decoration: BoxDecoration(
                            color: const Color(0x0AFFFFFF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Table(
                            columnWidths: const {
                              0: FixedColumnWidth(100),
                              1: FixedColumnWidth(180),
                              2: FixedColumnWidth(65),
                              3: FixedColumnWidth(65),
                              4: FixedColumnWidth(70),
                            },
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(color: Color(0x15FFFFFF)),
                                children: const [
                                  Padding(padding: EdgeInsets.all(6), child: Text('Event', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(6), child: Text('Name', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(6), child: Text('Matches', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(6), child: Text('Teams', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(6), child: Text('Scout', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                ],
                              ),
                              ...data.activeEvents.map((ev) => TableRow(
                                    children: [
                                      Padding(padding: const EdgeInsets.all(6), child: Text(ev.eventKey, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(ev.name, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(ev.matchCount.toString(), style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(ev.teamCount.toString(), style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(6), child: Text(ev.matchScoutingCount.toString(), style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold))),
                                    ],
                                  )),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    // Table records count
                    Text('SQLite Table Record Counts (${data.tableCounts.length} tables)',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: data.tableCounts.entries.map((e) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0x0AFFFFFF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(e.key, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10.5, fontFamily: 'monospace')),
                                const SizedBox(width: 6),
                                Text(e.value.toString(),
                                    style: TextStyle(
                                        color: e.value > 0 ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _filterChip(String label, bool isSelected, ValueChanged<bool> onSelected) =>
      FilterChip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8), fontSize: 11)),
        selected: isSelected,
        selectedColor: const Color(0xFF7C3AED),
        backgroundColor: const Color(0xFF1E293B),
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: onSelected,
      );

  TextField _buildTextField(TextEditingController c, String label,
          {String? hint, String? helper, bool isNumeric = true}) =>
      TextField(
        controller: c,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: _inputDecoration(label, hint: hint, helper: helper),
      );

  InputDecoration _inputDecoration(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
        helperStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final isDark = ObsidianUITheme.isDark(context);
    final bgColor = isDark ? const Color(0xFF060B14) : const Color(0xFFF1F5F9);

    // Hard Access Guard: Superadmin Only
    if (widget.apiService.currentUser?.isSuperAdmin != true) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ObsidianGlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, color: Color(0xFFEF4444), size: 48),
                  const SizedBox(height: 16),
                  const Text('Access Restricted',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Cluster Management is strictly restricted to Superadministrators only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Tab bar
          Container(
            color: isDark ? const Color(0xFF0A0F1C) : const Color(0xFFE2E8F0),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF7C3AED),
              labelColor: const Color(0xFFC084FC),
              unselectedLabelColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              tabs: const [
                Tab(text: 'Servers', icon: Icon(Icons.dns_rounded, size: 18)),
                Tab(text: 'Logs', icon: Icon(Icons.terminal_rounded, size: 18)),
                Tab(text: 'Load Balancer', icon: Icon(Icons.bolt_rounded, size: 18)),
                Tab(text: 'Alerts', icon: Icon(Icons.notifications_rounded, size: 18)),
                Tab(text: 'Quorum Fallback', icon: Icon(Icons.shield_rounded, size: 18)),
                Tab(text: 'Auto Backup', icon: Icon(Icons.backup_rounded, size: 18)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNodesTab(),
                _buildLogsTab(),
                _buildLoadBalancerTab(),
                _buildAlertsTab(),
                _buildQuorumFallbackTab(),
                _buildAutoBackupTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 0: Servers / Nodes
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildNodesTab() {
    final nodeCount = _nodesResponse?.nodes.length ?? 0;
    return RefreshIndicator(
      onRefresh: _loadNodes,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cluster-Wide Server Actions',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _actionButton(
                      icon: Icons.refresh_rounded,
                      label: 'Refresh Nodes',
                      color: const Color(0xFF3B82F6),
                      onPressed: _loadNodes,
                    ),
                    _actionButton(
                      icon: Icons.restart_alt_rounded,
                      label: 'Reboot ALL',
                      color: const Color(0xFFDC2626),
                      onPressed: () => _showRebootDialog('all', nodeCount),
                    ),
                    _actionButton(
                      icon: Icons.system_update_rounded,
                      label: 'Reinstall ALL',
                      color: const Color(0xFFD97706),
                      onPressed: () => _showReinstallDialog('all', nodeCount),
                    ),
                    _actionButton(
                      icon: Icons.key_rounded,
                      label: 'Regenerate Keys',
                      color: const Color(0xFF7C3AED),
                      onPressed: _showKeyRegenDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (_nodesLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF7C3AED))))
          else if (_nodesResponse == null)
            _emptyCard('Could not load cluster nodes. Pull down to retry.')
          else if (_nodesResponse!.nodes.isEmpty)
            _emptyCard('No cluster nodes discovered.')
          else
            ..._nodesResponse!.nodes.map(_buildNodeCard),
        ],
      ),
    );
  }

  Widget _buildNodeCard(ClusterNodeInfo node) {
    final statusColor = _statusColor(node.status);
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(node.ip,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14)),
                    if (node.isLocal)
                      _badge('Local', const Color(0xFF7C3AED), const Color(0x337C3AED))
                    else
                      _badge('Peer', const Color(0xFF3B82F6), const Color(0x333B82F6)),
                    _badge(node.status.toUpperCase(), statusColor,
                        statusColor.withValues(alpha: 0.15)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: const Color(0xFF1E293B),
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                onSelected: (v) {
                  switch (v) {
                    case 'logs':
                      _tabController.animateTo(1);
                      setState(() => _selectedLogNodeIp = node.ip);
                      _loadLogs();
                      break;
                    case 'config':
                      _showAppConfigDialog(node.ip);
                      break;
                    case 'reboot':
                      _showRebootDialog(node.ip, 1);
                      break;
                    case 'reinstall':
                      _showReinstallDialog(node.ip, 1);
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'logs', child: Row(children: [
                    Icon(Icons.terminal_rounded, color: Color(0xFF94A3B8), size: 16),
                    SizedBox(width: 8), Text('View Node Logs', style: TextStyle(color: Colors.white)),
                  ])),
                  PopupMenuItem(value: 'config', child: Row(children: [
                    Icon(Icons.settings_rounded, color: Color(0xFF94A3B8), size: 16),
                    SizedBox(width: 8), Text('Edit app-config.json', style: TextStyle(color: Colors.white)),
                  ])),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'reboot', child: Row(children: [
                    Icon(Icons.restart_alt_rounded, color: Color(0xFFEF4444), size: 16),
                    SizedBox(width: 8), Text('Reboot Server', style: TextStyle(color: Color(0xFFEF4444))),
                  ])),
                  PopupMenuItem(value: 'reinstall', child: Row(children: [
                    Icon(Icons.system_update_rounded, color: Color(0xFFF59E0B), size: 16),
                    SizedBox(width: 8), Text('Force Reinstall / Update', style: TextStyle(color: Color(0xFFF59E0B))),
                  ])),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _nodeDetail('Node ID', node.nodeId),
              _nodeDetail('Role', node.role),
              _nodeDetail('DB Active', node.isDbActive ? 'Yes' : 'No'),
              if (node.cockroachVersion != null)
                _nodeDetail('CockroachDB', node.cockroachVersion!),
              if (node.serverVersion != null)
                _nodeDetail('Server', node.serverVersion!),
              if (node.executionMode != null)
                _nodeDetail('Mode', node.executionMode!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nodeDetail(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFCBD5E1), fontSize: 11.5, fontFamily: 'monospace')),
        ],
      );

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) =>
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15, color: color),
        label: Text(label,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 1: Logs
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLogsTab() {
    return Column(
      children: [
        Container(
          color: const Color(0xFF0A0F1C),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedLogNodeIp,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Nodes')),
                        ...(_nodesResponse?.nodes ?? []).map((n) => DropdownMenuItem(
                              value: n.ip,
                              child: Text(n.isLocal ? '${n.ip} (Local)' : n.ip),
                            )),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedLogNodeIp = v);
                          _loadLogs();
                        }
                      },
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _dropdownDeco('Node'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<int>(
                      initialValue: _logLimit,
                      items: const [
                        DropdownMenuItem(value: 100, child: Text('100')),
                        DropdownMenuItem(value: 250, child: Text('250')),
                        DropdownMenuItem(value: 500, child: Text('500')),
                        DropdownMenuItem(value: 1000, child: Text('1000')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _logLimit = v);
                          _loadLogs();
                        }
                      },
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _dropdownDeco('Limit'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _loadLogs,
                    icon: _logsLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF7C3AED)))
                        : const Icon(Icons.refresh_rounded, color: Color(0xFF7C3AED), size: 20),
                  ),
                  Tooltip(
                    message: _logAutoRefresh ? 'Auto-refresh ON' : 'Auto-refresh OFF',
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        setState(() => _logAutoRefresh = !_logAutoRefresh);
                        if (_logAutoRefresh) {
                          _logAutoRefreshTimer = Timer.periodic(
                              const Duration(seconds: 8), (_) => _loadLogs());
                        } else {
                          _logAutoRefreshTimer?.cancel();
                        }
                      },
                      icon: Icon(
                        Icons.sync_rounded,
                        color: _logAutoRefresh
                            ? const Color(0xFF10B981)
                            : const Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _logFilterController,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Filter logs…',
                  hintStyle: const TextStyle(color: Color(0xFF475569)),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  suffixIcon: TextButton(
                    onPressed: _loadLogs,
                    child: const Text('Search', style: TextStyle(color: Color(0xFF7C3AED), fontSize: 11)),
                  ),
                ),
                onSubmitted: (_) => _loadLogs(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${_logs.length} entries  •  Node: $_selectedLogNodeIp',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _logsLoading && _logs.isEmpty
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
              : _logs.isEmpty
                  ? Center(
                      child: Text('No log entries found.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4))))
                  : Container(
                      color: const Color(0xFF020617),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => _buildLogLine(_logs[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildLogLine(ServerLogEntry log) {
    Color levelColor;
    switch (log.level.toUpperCase()) {
      case 'ERROR':
      case 'FATAL':
        levelColor = const Color(0xFFEF4444);
        break;
      case 'WARN':
        levelColor = const Color(0xFFF59E0B);
        break;
      case 'DEBUG':
      case 'TRACE':
        levelColor = const Color(0xFF64748B);
        break;
      default:
        levelColor = const Color(0xFF10B981);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(log.timestamp,
              style: const TextStyle(
                  color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 6),
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4)),
            child: Text(log.level.toUpperCase().padRight(5).substring(0, 5),
                style: TextStyle(color: levelColor, fontSize: 9.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${log.logger != null ? "[${log.logger}] " : ""}${log.message}',
              style: const TextStyle(
                  color: Color(0xFFE2E8F0), fontSize: 11.5, fontFamily: 'monospace'),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 2: Load Balancer (Mirrors web load-balancer-card)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLoadBalancerTab() {
    return RefreshIndicator(
      onRefresh: _loadLbStatus,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Main Load Balancer Card
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row (Mobile Safe with Wrap)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: Color(0xFF10B981), size: 20),
                        SizedBox(width: 6),
                        Text('Peer Request Forwarding & Load Balancer',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ],
                    ),
                    _buildLbStatusPill(),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Automatically routes incoming requests to the best available server node based on heap availability, CPU load, and network latency.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 10),
                // Controls Row
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _lbStatus?.enabled ?? false,
                          activeThumbColor: const Color(0xFF10B981),
                          onChanged: (v) async {
                            final current = await widget.apiService.fetchLoadBalancerSettings() ??
                                const LoadBalancerSettings();
                            final updated = LoadBalancerSettings(
                              enabled: v,
                              probeIntervalSeconds: current.probeIntervalSeconds,
                              forwardTimeoutSeconds: current.forwardTimeoutSeconds,
                              localPreferenceMargin: current.localPreferenceMargin,
                              maxExpectedLatencyMs: current.maxExpectedLatencyMs,
                              excludedPathPrefixes: current.excludedPathPrefixes,
                            );
                            final r = await widget.apiService.saveLoadBalancerSettings(updated);
                            _showSnack(r.message, isError: !r.success);
                            _loadLbStatus();
                          },
                        ),
                        const Text('Enable Balancing',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ],
                    ),
                    _actionButton(
                      icon: Icons.tune_rounded,
                      label: 'Settings',
                      color: const Color(0xFF3B82F6),
                      onPressed: _showLbSettingsDialog,
                    ),
                    _actionButton(
                      icon: Icons.refresh_rounded,
                      label: 'Refresh',
                      color: const Color(0xFF64748B),
                      onPressed: _loadLbStatus,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_lbLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF10B981))))
                else if (_lbStatus == null)
                  const Text('Load balancer status unavailable.', style: TextStyle(color: Color(0xFF64748B)))
                else ...[
                  // Metrics Grid
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricBox(
                        'Forwarded Requests',
                        _lbStatus!.forwardedCount.toString(),
                        'Probe every ${_lbStatus!.probeIntervalSeconds}s',
                        const Color(0xFF10B981),
                      ),
                      _metricBox(
                        'Selected Target',
                        _lbStatus!.bestNodeIp.isNotEmpty ? _lbStatus!.bestNodeIp : 'local',
                        'Local Margin: +${_lbStatus!.localPreferenceMargin}',
                        const Color(0xFF60A5FA),
                      ),
                      _metricBox(
                        'Local Node Capacity',
                        'Score: ${((_lbStatus!.localNode?.score ?? 0) * 100).toStringAsFixed(1)}%',
                        '${_lbStatus!.localNode?.availableHeapMb ?? 0}MB free / ${_lbStatus!.localNode?.maxHeapMb ?? 0}MB (CPU: ${((_lbStatus!.localNode?.cpuLoad ?? 0) * 100).round()}%)',
                        const Color(0xFF38BDF8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Network Peer Load & Latency Ranking Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x0D000000),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NETWORK PEER LOAD & LATENCY RANKING',
                            style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        if (_lbStatus!.peerNodes.isEmpty)
                          const Text('No active remote peer nodes discovered on the cluster.',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5))
                        else
                          ..._lbStatus!.peerNodes.map((p) => _buildPeerScoreRow(p)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 30-Minute Activity Timeline
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart_rounded, color: Color(0xFF10B981), size: 16),
                        SizedBox(width: 6),
                        Text('Last ~30 Min Activity',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ],
                    ),
                    if (_lbStatus != null)
                      _badge(
                        '${_lbStatus!.recentStats.totalForwarded30m} fwd / ${_lbStatus!.recentStats.totalLocalServed30m} loc (${(_lbStatus!.recentStats.forwardedRatio30m * 100).round()}% offloaded)',
                        const Color(0xFF10B981),
                        const Color(0x2210B981),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lbStatus?.activityHistory.isEmpty ?? true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text('No load balancing activity recorded yet in the last 30 minutes.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                    ),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: _lbStatus!.activityHistory.length,
                      itemBuilder: (_, i) {
                        final item = _lbStatus!.activityHistory.reversed.toList()[i];
                        final timeStr = DateTime.fromMillisecondsSinceEpoch(item.timestampEpochMs)
                            .toLocal()
                            .toString()
                            .split(' ')[1]
                            .split('.')[0];
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white10))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('[$timeStr]',
                                      style: const TextStyle(
                                          color: Color(0xFF64748B), fontSize: 10.5, fontFamily: 'monospace')),
                                  const SizedBox(width: 6),
                                  _badge(
                                    item.isForwarded ? 'Forwarded -> ${item.targetIp}' : 'Served Locally',
                                    item.isForwarded ? const Color(0xFF10B981) : const Color(0xFF60A5FA),
                                    (item.isForwarded ? const Color(0xFF10B981) : const Color(0xFF60A5FA))
                                        .withValues(alpha: 0.15),
                                  ),
                                  if (item.note.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(item.note,
                                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '+${item.requestsForwarded} fwd / +${item.requestsServedLocally} loc  •  Heap: ${item.localHeapFreeMb}MB  •  CPU: ${item.localCpuPercent}%',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
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
          const SizedBox(height: 8),

          // Overload Simulation (Stress Test) Card
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Overload Simulation',
                          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    _stressStatus?.isRunning == true
                        ? _badge('Active (${_stressStatus!.remainingSeconds}s)',
                            const Color(0xFFEF4444), const Color(0x33EF4444))
                        : _badge('Idle', const Color(0xFF94A3B8), const Color(0x2294A3B8)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Simulates high CPU & memory utilization to verify automatic traffic offloading. Stops after 60s max.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                _stressStatus?.isRunning == true
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF475569)),
                        onPressed: () async {
                          final r = await widget.apiService.stopStressTest();
                          _showSnack(r.message, isError: !r.success);
                          _loadLbStatus();
                        },
                        icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 15),
                        label: const Text('Stop Overload', style: TextStyle(color: Colors.white, fontSize: 12)),
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                        onPressed: () async {
                          final r = await widget.apiService.startStressTest();
                          _showSnack(r.message, isError: !r.success);
                          if (r.success) {
                            setState(() => _stressStatus = const StressTestStatus(isRunning: true, remainingSeconds: 60));
                            _startStressPolling();
                          }
                        },
                        icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 15),
                        label: const Text('Simulate Overload (60s)', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLbStatusPill() {
    if (_lbStatus == null || !_lbStatus!.enabled) {
      return _badge('Disabled', const Color(0xFF94A3B8), const Color(0x2294A3B8));
    }
    if (_lbStatus!.isForwardingActive) {
      return _badge('Forwarding Active -> ${_lbStatus!.bestNodeIp}',
          const Color(0xFF10B981), const Color(0x3310B981));
    }
    return _badge('Active (Serving Locally)', const Color(0xFF60A5FA), const Color(0x3360A5FA));
  }

  Widget _metricBox(String title, String val, String sub, Color color) => Container(
        constraints: const BoxConstraints(minWidth: 140),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x0A000000),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(val,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
          ],
        ),
      );

  Widget _buildPeerScoreRow(NodeLoad peer) {
    final isWinner = (peer.ip == _lbStatus?.bestNodeIp);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isWinner ? const Color(0xFF10B981).withValues(alpha: 0.5) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(peer.ip,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: isWinner ? const Color(0xFF10B981) : Colors.white)),
              if (isWinner) ...[
                const SizedBox(width: 6),
                _badge('Top Route', const Color(0xFF10B981), const Color(0x3310B981)),
              ],
              const Spacer(),
              Text('${(peer.score * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 2),
          Text('Latency: ${peer.latencyMs}ms  •  Heap: ${peer.availableHeapMb}MB  •  CPU: ${(peer.cpuLoad * 100).round()}%',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 3: Alerts
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildAlertsTab() {
    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.notifications_active_rounded, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text('Node Down Alerts',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                const SizedBox(height: 4),
                const Text('Receive email and push notifications when any cluster node goes offline.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                if (_alertsLoading)
                  const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF10B981)))
                else if (_nodeAlerts != null) ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        _nodeAlerts!.enrolled ? 'Enrolled — receiving alerts' : 'Not enrolled',
                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13.5)),
                    subtitle: _nodeAlerts!.email != null
                        ? Text(_nodeAlerts!.email!, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5))
                        : null,
                    value: _nodeAlerts!.enrolled,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (v) async {
                      final r = await widget.apiService.toggleNodeAlertsEnrollment(v);
                      _showSnack(r.message, isError: !r.success);
                      if (r.success) _loadAlerts();
                    },
                  ),
                  const SizedBox(height: 6),
                  _actionButton(
                    icon: Icons.send_rounded,
                    label: 'Send Test Alert',
                    color: const Color(0xFF10B981),
                    onPressed: () async {
                      final r = await widget.apiService.sendTestNodeAlert();
                      _showSnack(r.message, isError: !r.success);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 8),
                  Text('Server Error Alerts',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                const SizedBox(height: 4),
                const Text('Receive email notifications for unhandled 500 server errors across the cluster.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                if (_alertsLoading)
                  const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                else if (_errorAlerts != null) ...[
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Error Alerts', style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13.5)),
                    value: _errorAlerts!.enabled,
                    activeThumbColor: const Color(0xFFF59E0B),
                    onChanged: (v) async {
                      final updated = ServerErrorAlertsSettings(
                        enabled: v,
                        additionalEmails: _errorAlerts!.additionalEmails,
                      );
                      final r = await widget.apiService.saveErrorAlertSettings(updated);
                      _showSnack(r.message, isError: !r.success);
                      if (r.success) _loadAlerts();
                    },
                  ),
                  if (_errorAlerts!.enrolledSuperadmins.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('Enrolled Admins: ${_errorAlerts!.enrolledSuperadmins.join(", ")}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.send_rounded,
                    label: 'Send Test Error Alert',
                    color: const Color(0xFFF59E0B),
                    onPressed: () async {
                      final r = await widget.apiService.sendTestErrorAlert();
                      _showSnack(r.message, isError: !r.success);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 4: Quorum Fallback (Mirrors web quorum-fallback-card)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildQuorumFallbackTab() {
    final anyActive = _qfNodes.any((n) => n.isActiveServingReads);
    final allEnabled = _qfNodes.isNotEmpty && _qfNodes.every((n) => n.enabled);

    return RefreshIndicator(
      onRefresh: _loadQfStatus,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 6),
                        Text('Quorum Loss Fallback Mirror Manager',
                            style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    if (anyActive)
                      _badge('Active (Quorum Lost)', const Color(0xFFEF4444), const Color(0x33EF4444))
                    else if (allEnabled)
                      _badge('Active Mirroring (Ready)', const Color(0xFF10B981), const Color(0x3310B981))
                    else
                      _badge('Partial Mirroring', const Color(0xFFF59E0B), const Color(0x33F59E0B)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Continually mirrors critical data into local SQLite storage. If CockroachDB cluster quorum is lost, servers automatically serve real-time reads from this snapshot.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 10),
                _actionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh Status',
                  color: const Color(0xFF64748B),
                  onPressed: _loadQfStatus,
                ),
                const SizedBox(height: 14),

                if (_qfLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFF59E0B))))
                else if (_qfNodes.isEmpty)
                  const Text('No quorum fallback nodes found.', style: TextStyle(color: Color(0xFF64748B)))
                else
                  ..._qfNodes.map(_buildQfNodeCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQfNodeCard(QuorumFallbackNodeStatus node) {
    final statusColor = node.isActiveServingReads
        ? const Color(0xFFF59E0B)
        : node.enabled && node.isAvailable
            ? const Color(0xFF10B981)
            : const Color(0xFF94A3B8);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(node.nodeIp,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13.5)),
                    if (node.isLocal)
                      _badge('Local', const Color(0xFF7C3AED), const Color(0x337C3AED))
                    else
                      _badge('Remote', const Color(0xFF3B82F6), const Color(0x333B82F6)),
                    _badge(node.status, statusColor, statusColor.withValues(alpha: 0.15)),
                  ],
                ),
              ),
              Switch(
                value: node.enabled,
                activeThumbColor: const Color(0xFF10B981),
                onChanged: (v) async {
                  final r = await widget.apiService.toggleQuorumFallback(node.nodeIp, v);
                  _showSnack(r.message, isError: !r.success);
                  if (r.success) _loadQfStatus();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _nodeDetail('DB Size', _formatBytes(node.databaseSizeBytes)),
            if (node.totalDiskSpaceBytes > 0)
              _nodeDetail('Free Disk', '${_formatBytes(node.freeDiskSpaceBytes)} (${(node.freeDiskSpaceBytes / node.totalDiskSpaceBytes * 100).round()}% free)'),
            if (node.lastSyncTimestamp != null)
              _nodeDetail('Last Synced', _shortTimestamp(node.lastSyncTimestamp!)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _smallButton(
              icon: Icons.tune_rounded,
              label: 'Configure',
              color: const Color(0xFFF59E0B),
              onPressed: () => _showQfConfigDialog(node),
            ),
            _smallButton(
              icon: Icons.search_rounded,
              label: 'Inspect DB',
              color: const Color(0xFF38BDF8),
              onPressed: () => _showQfInspectDialog(node.nodeIp),
            ),
            _smallButton(
              icon: Icons.sync_rounded,
              label: 'Sync Now',
              color: const Color(0xFF3B82F6),
              onPressed: () async {
                final r = await widget.apiService.syncQuorumFallback(node.nodeIp);
                _showSnack(r.message, isError: !r.success);
                if (r.success) _loadQfStatus();
              },
            ),
            _smallButton(
              icon: Icons.delete_sweep_rounded,
              label: 'Purge',
              color: const Color(0xFFEF4444),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Purge Quorum Storage', style: TextStyle(color: Colors.white)),
                    content: Text('Purge local fallback SQLite database on node ${node.nodeIp} to reclaim disk space?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Purge', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final r = await widget.apiService.purgeQuorumFallback(node.nodeIp);
                  _showSnack(r.message, isError: !r.success);
                  if (r.success) _loadQfStatus();
                }
              },
            ),
          ]),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 5: Auto Backup & Snapshots (Mirrors web auto-backup-section)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildAutoBackupTab() {
    final local = _backupCombined?.localNodeStatus ??
        const AutoBackupNodeStatus(nodeIp: 'local', isLocal: true, enabled: false);
    final clusterNodes = _backupCombined?.clusterNodes ?? [];

    return RefreshIndicator(
      onRefresh: _loadBackupStatus,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Section 1: Local Server Auto-Backup Settings
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 6),
                        Text('Database Snapshots & System Recovery',
                            style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    local.enabled
                        ? _badge('Daily Active (02:54 UTC)', const Color(0xFF10B981), const Color(0x3310B981))
                        : _badge('Auto-Backup Disabled', const Color(0xFF94A3B8), const Color(0x2294A3B8)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Creates an exact point-in-time snapshot stored locally as standalone SQLite files. Runs automatically at 02:54 UTC daily when enabled.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _actionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Create Snapshot Now',
                      color: const Color(0xFF22D3EE),
                      onPressed: () async {
                        _showSnack('Creating local database snapshot…');
                        final r = await widget.apiService.createLocalSnapshot();
                        _showSnack(r.message, isError: !r.success);
                        _loadBackupStatus();
                      },
                    ),
                    _actionButton(
                      icon: Icons.refresh_rounded,
                      label: 'Refresh',
                      color: const Color(0xFF64748B),
                      onPressed: _loadBackupStatus,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Settings Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x0A000000),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Auto-Backup Settings (This Server)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Daily Auto-Backup',
                            style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Trigger daily full snapshot at 02:54 UTC on this node.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                        value: local.enabled,
                        activeThumbColor: const Color(0xFF10B981),
                        onChanged: (v) async {
                          final r = await widget.apiService.saveLocalBackupConfig(v, local.retentionDays);
                          _showSnack(r.message, isError: !r.success);
                          _loadBackupStatus();
                        },
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            local.enabled && local.nextScheduledRunUtc != null
                                ? 'Next Run: ${local.nextScheduledRunUtc} UTC'
                                : 'Retention: ${local.retentionDays} days',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                          ),
                          _smallButton(
                            icon: Icons.tune_rounded,
                            label: 'Change (${local.retentionDays}d)',
                            color: const Color(0xFF38BDF8),
                            onPressed: () async {
                              final ctrl = TextEditingController(text: local.retentionDays.toString());
                              final days = await showDialog<int>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E293B),
                                  title: const Text('Auto-Deletion Retention (Days)', style: TextStyle(color: Colors.white)),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration('Days'),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text) ?? local.retentionDays),
                                      child: const Text('Save'),
                                    ),
                                  ],
                                ),
                              );
                              if (days != null) {
                                final r = await widget.apiService.saveLocalBackupConfig(local.enabled, days);
                                _showSnack(r.message, isError: !r.success);
                                _loadBackupStatus();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Section 2: Stored Database Snapshots (Local Server)
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Stored Database Snapshots (Local)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                          overflow: TextOverflow.ellipsis),
                    ),
                    _badge('${local.snapshots.length} files', const Color(0xFF38BDF8), const Color(0x2238BDF8)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_backupLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF22D3EE))))
                else if (local.snapshots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text('No local SQLite snapshots created yet.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                    ),
                  )
                else
                  ...local.snapshots.map((s) => _buildSnapshotItemRow(s)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Section 3: Cluster Nodes Backup Status Table
          ObsidianGlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cluster Nodes Backup Status (Per-Server)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5)),
                const SizedBox(height: 10),
                if (_backupLoading && clusterNodes.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF22D3EE))))
                else if (clusterNodes.isEmpty)
                  const Text('No remote cluster backup nodes discovered.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5))
                else
                  ...clusterNodes.map((cn) => _buildClusterNodeBackupCard(cn)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotItemRow(SnapshotInfoDto s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fileName,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12.0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(s.createdAtUtc.isNotEmpty ? s.createdAtUtc : _shortTimestampFromMs(s.createdAtEpochMs),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                    Text(_formatBytes(s.sizeBytes),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w600)),
                    s.isAutoBackup
                        ? _badge('Auto', const Color(0xFF3B82F6), const Color(0x223B82F6))
                        : _badge('Manual', const Color(0xFF94A3B8), const Color(0x2294A3B8)),
                  ],
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              _smallButton(
                icon: Icons.restore_rounded,
                label: 'Restore',
                color: const Color(0xFFEF4444),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      title: const Text('Restore Database from Snapshot', style: TextStyle(color: Color(0xFFEF4444))),
                      content: Text('Are you sure you want to restore the ENTIRE database from snapshot "${s.fileName}"?\n\nThis will replace current database tables with data from this snapshot.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Restore Database', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    _showSnack('Restoring database from ${s.fileName}…');
                    final r = await widget.apiService.restoreSnapshot(s.fileName);
                    _showSnack(r.message, isError: !r.success);
                  }
                },
              ),
              _smallButton(
                icon: Icons.delete_outline_rounded,
                label: '',
                color: const Color(0xFFEF4444),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      title: const Text('Delete Snapshot', style: TextStyle(color: Colors.white)),
                      content: Text('Delete snapshot "${s.fileName}"?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    final r = await widget.apiService.deleteSnapshot(s.fileName);
                    _showSnack(r.message, isError: !r.success);
                    _loadBackupStatus();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClusterNodeBackupCard(AutoBackupNodeStatus node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(node.nodeIp,
                        style: const TextStyle(
                            color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                    if (node.isLocal)
                      _badge('Local', const Color(0xFF7C3AED), const Color(0x337C3AED))
                    else
                      _badge('Peer', const Color(0xFF3B82F6), const Color(0x333B82F6)),
                  ],
                ),
              ),
              Switch(
                value: node.enabled,
                activeThumbColor: const Color(0xFF22D3EE),
                onChanged: (v) async {
                  final r = await widget.apiService.toggleNodeAutoBackup(node.nodeIp, v);
                  _showSnack(r.message, isError: !r.success);
                  _loadBackupStatus();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _nodeDetail('Retention', '${node.retentionDays}d'),
              _nodeDetail('Snapshots', node.snapshotCount.toString()),
              _nodeDetail('Storage', _formatBytes(node.totalStorageBytes)),
              if (node.lastBackupTimeUtc != null || node.lastBackupTimestamp != null)
                _nodeDetail('Last Backup', node.lastBackupTimeUtc ?? _shortTimestamp(node.lastBackupTimestamp!)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _smallButton(
                icon: Icons.camera_alt_rounded,
                label: 'Create Snapshot',
                color: const Color(0xFF22D3EE),
                onPressed: () async {
                  _showSnack('Triggering snapshot on ${node.nodeIp}…');
                  final r = await widget.apiService.createNodeSnapshot(node.nodeIp);
                  _showSnack(r.message, isError: !r.success);
                  _loadBackupStatus();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Shared UI Helpers ─────────────────────────────────────────────────────

  Widget _badge(String label, Color text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label,
            style: TextStyle(color: text, fontSize: 9.5, fontWeight: FontWeight.w600)),
      );

  Widget _smallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) =>
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          padding: EdgeInsets.symmetric(horizontal: label.isNotEmpty ? 8 : 6, vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 13, color: color),
        label: label.isNotEmpty
            ? Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600))
            : const SizedBox.shrink(),
      );

  Widget _emptyCard(String msg) => ObsidianGlassCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          ),
        ),
      );

  String _shortTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts;
    }
  }

  String _shortTimestampFromMs(int epochMs) {
    if (epochMs <= 0) return '--';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toUtc();
      final str = dt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
      return '$str UTC';
    } catch (_) {
      return '--';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logFilterController.dispose();
    _logAutoRefreshTimer?.cancel();
    _stressPollTimer?.cancel();
    super.dispose();
  }
}
