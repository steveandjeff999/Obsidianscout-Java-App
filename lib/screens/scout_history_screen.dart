import 'dart:async';
import 'package:flutter/material.dart';
import '../models/scout_history_models.dart';
import '../services/api_service.dart';
import '../services/scout_history_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

class ScoutHistoryScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ScoutHistoryScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ScoutHistoryScreen> createState() => _ScoutHistoryScreenState();
}

class _ScoutHistoryScreenState extends State<ScoutHistoryScreen> {
  List<ScoutHistoryEntry> _entries = [];
  bool _isLoading = true;
  bool _isBulkUploading = false;
  bool _isSyncingServer = false;

  // Filter state
  String _typeFilter = 'all';   // 'all', 'match', 'pit', 'qual', 'prescout'
  String _statusFilter = 'all'; // 'all', 'synced', 'pending', 'failed'

  @override
  void initState() {
    super.initState();
    _loadHistory().then((_) => _syncWithServer());
  }

  @override
  void didUpdateWidget(covariant ScoutHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadHistory().then((_) => _syncWithServer());
    }
  }

  Future<void> _loadHistory() async {
    final entries = await ScoutHistoryService.loadAll();
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-fetch server records to check what is already synced
  // ---------------------------------------------------------------------------

  static int _extractInt(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k) && map[k] != null) {
        final val = map[k];
        if (val is int) return val;
        final parsed = int.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static String _extractStr(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k) && map[k] != null) {
        final val = map[k].toString().trim();
        if (val.isNotEmpty) return val;
      }
    }
    return '';
  }

  static bool _matchesRecordMap(ScoutHistoryEntry local, Map<String, dynamic> record) {
    final serverTeam = _extractInt(record, ['targetTeamNumber', 'teamNumber', 'team_number']);
    if (serverTeam != 0 && serverTeam != local.teamNumber) return false;

    final serverEvent = _extractStr(record, ['eventKey', 'event_key', 'eventCode', 'event_code']);
    if (serverEvent.isNotEmpty && local.eventKey.isNotEmpty) {
      if (serverEvent.toLowerCase() != local.eventKey.toLowerCase()) return false;
    }

    if (local.type.contains('match') || local.type.contains('qual')) {
      final serverMatchKey = _extractStr(record, ['matchKey', 'match_key']);
      final serverMatchNum = _extractInt(record, ['matchNumber', 'match_number']);

      if (local.matchKey != null && local.matchKey!.isNotEmpty && serverMatchKey.isNotEmpty) {
        if (local.matchKey!.toLowerCase() != serverMatchKey.toLowerCase()) return false;
      } else if (local.matchNumber != null && serverMatchNum != 0) {
        if (local.matchNumber != serverMatchNum) return false;
      }
    }

    return true;
  }

  static bool _checkServerMatch(ScoutHistoryEntry entry, dynamic rawServerRecord) {
    if (rawServerRecord is! Map) return false;
    final map = Map<String, dynamic>.from(rawServerRecord);

    if (_matchesRecordMap(entry, map)) return true;

    if (map['data'] is Map) {
      final inner = Map<String, dynamic>.from(map['data'] as Map);
      if (_matchesRecordMap(entry, inner)) return true;
    }

    return false;
  }

  Future<void> _syncWithServer({bool showFeedback = false}) async {
    if (_isSyncingServer) return;
    setState(() => _isSyncingServer = true);

    int newlySyncedCount = 0;
    try {
      final results = await Future.wait([
        widget.apiService.fetchScoutingEntries(),
        widget.apiService.fetchPitScoutingEntries(),
        widget.apiService.fetchQualScoutingEntries(),
        widget.apiService.fetchPrescoutScoutingEntries(),
        widget.apiService.fetchPrescoutPitScoutingEntries(),
        widget.apiService.fetchPrescoutQualScoutingEntries(),
      ]);

      final matchEntries = results[0];
      final pitEntries = results[1];
      final qualEntries = results[2];
      final prescoutMatch = results[3];
      final prescoutPit = results[4];
      final prescoutQual = results[5];

      final localEntries = await ScoutHistoryService.loadAll();
      for (final local in localEntries) {
        if (local.status == 'synced') continue;

        List<dynamic> targetServerList;
        if (local.type == 'match') {
          targetServerList = matchEntries;
        } else if (local.type == 'pit') {
          targetServerList = pitEntries;
        } else if (local.type == 'qual') {
          targetServerList = qualEntries;
        } else if (local.type == 'prescout-match') {
          targetServerList = prescoutMatch;
        } else if (local.type == 'prescout-pit') {
          targetServerList = prescoutPit;
        } else if (local.type == 'prescout-qual') {
          targetServerList = prescoutQual;
        } else {
          targetServerList = [...matchEntries, ...pitEntries, ...qualEntries, ...prescoutMatch, ...prescoutPit, ...prescoutQual];
        }

        final foundOnServer = targetServerList.any((serverItem) => _checkServerMatch(local, serverItem));
        if (foundOnServer) {
          await ScoutHistoryService.updateStatus(local.id, 'synced');
          newlySyncedCount++;
        }
      }
    } catch (_) {}

    if (newlySyncedCount > 0 && (_statusFilter == 'pending' || _statusFilter == 'failed')) {
      _statusFilter = 'all';
    }

    await _loadHistory();
    if (mounted) {
      setState(() => _isSyncingServer = false);
      if (showFeedback) {
        if (newlySyncedCount > 0) {
          ObsidianFeedback.showSuccess(
            context,
            title: 'Server Sync Complete',
            message: 'Marked $newlySyncedCount records as already verified on server.',
          );
        } else {
          ObsidianFeedback.showSuccess(
            context,
            title: 'Server Sync',
            message: 'History is up to date with server records.',
          );
        }
      }
    }
  }

  List<ScoutHistoryEntry> get _filtered {
    return _entries.where((e) {
      final typeMatch = _typeFilter == 'all' ||
          e.type == _typeFilter ||
          (_typeFilter == 'match' && (e.type == 'match' || e.type == 'prescout-match')) ||
          (_typeFilter == 'pit' && (e.type == 'pit' || e.type == 'prescout-pit')) ||
          (_typeFilter == 'qual' && (e.type == 'qual' || e.type == 'prescout-qual')) ||
          (_typeFilter == 'prescout' && e.type.startsWith('prescout'));
      final statusMatch = _statusFilter == 'all' || e.status == _statusFilter;
      return typeMatch && statusMatch;
    }).toList();
  }

  Future<void> _uploadEntry(ScoutHistoryEntry entry) async {
    final api = widget.apiService;
    bool success = false;
    String? errorMsg;

    try {
      final data = Map<String, dynamic>.from(entry.payload);
      if (entry.type == 'match') {
        final resp = await api.submitMatchScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      } else if (entry.type == 'pit') {
        final resp = await api.submitPitScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      } else if (entry.type == 'qual') {
        final resp = await api.submitQualScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      } else if (entry.type == 'prescout-match') {
        final resp = await api.submitPrescoutMatchScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      } else if (entry.type == 'prescout-pit') {
        final resp = await api.submitPrescoutPitScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      } else if (entry.type == 'prescout-qual') {
        final resp = await api.submitPrescoutQualScouting(data);
        success = resp.success;
        errorMsg = resp.message;
      }
    } catch (e) {
      errorMsg = e.toString();
    }

    final newStatus = success ? 'synced' : 'failed';
    await ScoutHistoryService.updateStatus(entry.id, newStatus);
    await _loadHistory();

    if (mounted) {
      if (success) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Upload Successful',
          message: 'Record for Team ${entry.teamNumber} synced to server.',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: 'Upload Failed',
          message: errorMsg != null && errorMsg.isNotEmpty
              ? errorMsg
              : 'Could not upload record. Please try again.',
        );
      }
    }
  }

  void _regenerateQr(ScoutHistoryEntry entry) {
    final typeLabel = _typeLabel(entry.type);

    ObsidianBarcodeModal.show(
      context,
      payload: Map<String, dynamic>.from(entry.payload),
      typeLabel: typeLabel,
      targetTeamNumber: entry.teamNumber,
      matchKey: entry.matchKey,
    );
    if (entry.status == 'failed') {
      ScoutHistoryService.updateStatus(entry.id, 'pending').then((_) => _loadHistory());
    }
  }

  Future<void> _deleteEntry(ScoutHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Record?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
          content: Text(
            'Delete ${entry.displayLabel} from local history? This cannot be undone.',
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ScoutHistoryService.deleteEntry(entry.id);
      await _loadHistory();
    }
  }

  Future<void> _uploadAllPending() async {
    final pending = _entries.where((e) => e.status == 'pending' || e.status == 'failed').toList();
    if (pending.isEmpty) return;

    setState(() => _isBulkUploading = true);

    int successCount = 0;
    int failCount = 0;

    for (final entry in pending) {
      if (!mounted) break;
      final api = widget.apiService;
      bool ok = false;
      try {
        final data = Map<String, dynamic>.from(entry.payload);
        if (entry.type == 'match') {
          ok = (await api.submitMatchScouting(data)).success;
        } else if (entry.type == 'pit') {
          ok = (await api.submitPitScouting(data)).success;
        } else if (entry.type == 'qual') {
          ok = (await api.submitQualScouting(data)).success;
        } else if (entry.type == 'prescout-match') {
          ok = (await api.submitPrescoutMatchScouting(data)).success;
        } else if (entry.type == 'prescout-pit') {
          ok = (await api.submitPrescoutPitScouting(data)).success;
        } else if (entry.type == 'prescout-qual') {
          ok = (await api.submitPrescoutQualScouting(data)).success;
        }
      } catch (_) {}
      await ScoutHistoryService.updateStatus(entry.id, ok ? 'synced' : 'failed');
      if (ok) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (_statusFilter == 'pending' || _statusFilter == 'failed') {
      _statusFilter = 'all';
    }

    await _loadHistory();
    setState(() => _isBulkUploading = false);

    if (mounted) {
      ObsidianFeedback.showSuccess(
        context,
        title: 'Bulk Upload Complete',
        message: '$successCount synced${failCount > 0 ? ', $failCount failed' : ''}. Records are preserved in history as Synced.',
      );
    }
  }

  Future<void> _clearSynced() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Clear Synced Records?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
          content: Text(
            'Remove all already-synced records from local history? Unsynced records will remain safe.',
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.warningOrange),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear Synced', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ScoutHistoryService.clearSynced();
      await _loadHistory();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Clear All History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
              ),
            ],
          ),
          content: Text(
            'This will permanently delete all ${_entries.length} scouting history records from this device. Are you sure?',
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ScoutHistoryService.clearAll();
      await _loadHistory();
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'match':          return 'Match Scout';
      case 'pit':            return 'Pit Scout';
      case 'qual':           return 'Qual Scout';
      case 'prescout-match': return 'Match Prescout';
      case 'prescout-pit':   return 'Pit Prescout';
      case 'prescout-qual':  return 'Qual Prescout';
      default:               return type.toUpperCase();
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'match':          return ObsidianUITheme.primaryAccent;
      case 'pit':            return ObsidianUITheme.secondaryAccent;
      case 'qual':           return ObsidianUITheme.warningOrange;
      case 'prescout-match':
      case 'prescout-pit':
      case 'prescout-qual':  return const Color(0xFF38BDF8);
      default:               return Colors.white70;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'synced':  return ObsidianUITheme.successGreen;
      case 'pending': return ObsidianUITheme.warningOrange;
      case 'failed':  return ObsidianUITheme.errorRed;
      default:        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'synced':  return Icons.check_circle_rounded;
      case 'pending': return Icons.schedule_rounded;
      case 'failed':  return Icons.error_rounded;
      default:        return Icons.help_outline_rounded;
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'direct_upload':  return 'Uploaded';
      case 'qr_generated':   return 'QR Generated';
      case 'offline_cached': return 'Saved Locally';
      case 'qr_scanned':     return 'Scanned QR';
      case 'exported':       return 'Exported JSON';
      default:               return action;
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
      );
    }

    final filtered = _filtered;
    final pendingCount = _entries.where((e) => e.status == 'pending' || e.status == 'failed').length;
    final syncedCount  = _entries.where((e) => e.status == 'synced').length;

    return Column(
      children: [
        // Filter chips bar
        _buildFilterBar(),

        // Action / Bulk bar at TOP (never covered by floating bottom dock)
        if (_entries.isNotEmpty) _buildTopActionBar(pendingCount, syncedCount),

        // Main list
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _syncWithServer(showFeedback: true),
                  color: ObsidianUITheme.primaryAccent,
                  child: Builder(
                    builder: (context) {
                      final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
                      if (isDesktop) {
                        return GridView.builder(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: EdgeInsets.only(
                            top: 8,
                            left: 12,
                            right: 12,
                            bottom: widget.isBarsVisible ? 120 : 24,
                          ),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 460.0,
                            mainAxisExtent: 140.0,
                            crossAxisSpacing: 12.0,
                            mainAxisSpacing: 12.0,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _buildCard(filtered[i]),
                        );
                      }
                      return ListView.builder(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        padding: EdgeInsets.only(
                          top: 8,
                          left: 12,
                          right: 12,
                          bottom: widget.isBarsVisible ? 120 : 24,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _buildCard(filtered[i]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', _typeFilter == 'all', () => setState(() => _typeFilter = 'all'),
              ObsidianUITheme.primaryAccent),
          const SizedBox(width: 6),
          _filterChip('Match', _typeFilter == 'match', () => setState(() => _typeFilter = 'match'),
              ObsidianUITheme.primaryAccent),
          const SizedBox(width: 6),
          _filterChip('Pit', _typeFilter == 'pit', () => setState(() => _typeFilter = 'pit'),
              ObsidianUITheme.secondaryAccent),
          const SizedBox(width: 6),
          _filterChip('Qual', _typeFilter == 'qual', () => setState(() => _typeFilter = 'qual'),
              ObsidianUITheme.warningOrange),
          const SizedBox(width: 6),
          _filterChip('Prescout', _typeFilter == 'prescout', () => setState(() => _typeFilter = 'prescout'),
              const Color(0xFF38BDF8)),
          const SizedBox(width: 16),
          _filterChip('Synced ✓', _statusFilter == 'synced',
              () => setState(() => _statusFilter = _statusFilter == 'synced' ? 'all' : 'synced'),
              ObsidianUITheme.successGreen),
          const SizedBox(width: 6),
          _filterChip('Pending ⏳', _statusFilter == 'pending',
              () => setState(() => _statusFilter = _statusFilter == 'pending' ? 'all' : 'pending'),
              ObsidianUITheme.warningOrange),
          const SizedBox(width: 6),
          _filterChip('Failed ✗', _statusFilter == 'failed',
              () => setState(() => _statusFilter = _statusFilter == 'failed' ? 'all' : 'failed'),
              ObsidianUITheme.errorRed),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : ObsidianUITheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : ObsidianUITheme.getBorderColor(context),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? accent : ObsidianUITheme.getSecondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Action Bar (Pinned at top under filter chips)
  // ---------------------------------------------------------------------------

  Widget _buildTopActionBar(int pendingCount, int syncedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ObsidianGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: _isBulkUploading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent)),
                    SizedBox(width: 12),
                    Text('Uploading Pending Records...', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Left side actions: Upload & Server Verify
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Upload All Pending Button
                      ElevatedButton.icon(
                        onPressed: pendingCount > 0 ? _uploadAllPending : null,
                        icon: const Icon(Icons.cloud_upload_rounded, size: 15),
                        label: Text(
                          pendingCount > 0 ? 'Upload Pending ($pendingCount)' : 'All Synced',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ObsidianUITheme.primaryAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Check Server Sync Button
                      OutlinedButton.icon(
                        onPressed: _isSyncingServer ? null : () => _syncWithServer(showFeedback: true),
                        icon: _isSyncingServer
                            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                            : const Icon(Icons.sync_rounded, size: 15),
                        label: Text(_isSyncingServer ? 'Checking...' : 'Verify Server', style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        ),
                      ),
                    ],
                  ),

                  // Right side actions: Clear Synced & Delete All
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Clear Synced
                      OutlinedButton(
                        onPressed: syncedCount > 0 ? _clearSynced : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ObsidianUITheme.successGreen,
                          side: BorderSide(color: ObsidianUITheme.successGreen.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        ),
                        child: Text('Clear Synced ($syncedCount)', style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      // Clear All
                      OutlinedButton(
                        onPressed: _clearAll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ObsidianUITheme.errorRed,
                          side: BorderSide(color: ObsidianUITheme.errorRed.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        ),
                        child: const Icon(Icons.delete_sweep_rounded, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Entry Card
  // ---------------------------------------------------------------------------

  Widget _buildCard(ScoutHistoryEntry entry) {
    final primaryTextColor   = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor  = ObsidianUITheme.getTertiaryTextColor(context);
    final typeColor          = _typeColor(entry.type);
    final statusColor        = _statusColor(entry.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ObsidianGlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Type badge, status, action chip, relative time
            Row(
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    _typeLabel(entry.type).toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                // Status icon + text
                Icon(_statusIcon(entry.status), size: 13, color: statusColor),
                const SizedBox(width: 3),
                Text(
                  entry.status.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                ),
                const Spacer(),
                // Action badge & time
                Text(
                  '${_actionLabel(entry.action)}  ${_relativeTime(entry.timestamp)}',
                  style: TextStyle(fontSize: 10, color: tertiaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Middle row: Team info + match details
            Row(
              children: [
                const Icon(Icons.groups_rounded, size: 16, color: ObsidianUITheme.warningOrange),
                const SizedBox(width: 6),
                Text(
                  'Team ${entry.teamNumber}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                if (entry.matchKey != null || entry.matchNumber != null) ...[
                  Text('  •  ', style: TextStyle(color: tertiaryTextColor)),
                  Text(
                    entry.matchKey ?? 'Match #${entry.matchNumber}',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                ],
              ],
            ),
            if (entry.eventKey.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(entry.eventKey, style: TextStyle(fontSize: 11, color: tertiaryTextColor)),
            ],

            const SizedBox(height: 10),

            // Actions row: Upload now, Regenerate QR, Delete
            Row(
              children: [
                // Upload
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _uploadEntry(entry),
                    icon: const Icon(Icons.cloud_upload_rounded, size: 14),
                    label: Text(entry.status == 'synced' ? 'Re-Upload' : 'Upload', style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                      foregroundColor: ObsidianUITheme.primaryAccent,
                      elevation: 0,
                      side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // QR Code
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _regenerateQr(entry),
                    icon: const Icon(Icons.qr_code_rounded, size: 14),
                    label: const Text('QR Code', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ObsidianUITheme.secondaryAccent,
                      side: BorderSide(color: ObsidianUITheme.secondaryAccent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Delete
                SizedBox(
                  width: 40,
                  child: OutlinedButton(
                    onPressed: () => _deleteEntry(entry),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ObsidianUITheme.errorRed,
                      side: BorderSide(color: ObsidianUITheme.errorRed.withValues(alpha: 0.4)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 64, color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _typeFilter == 'all' && _statusFilter == 'all'
                  ? 'No scouting history on this device yet.'
                  : 'No records match the current filter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: secondaryTextColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Records appear here after you submit, save locally, or generate a QR code on any scout screen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ObsidianUITheme.getTertiaryTextColor(context)),
            ),
          ],
        ),
      ),
    );
  }
}
