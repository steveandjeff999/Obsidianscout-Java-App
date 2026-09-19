import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/error_report_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

// ============================================================================
// Error & Bug Reports Management Screen — Mirrors website error-reports.html/js
// Strictly restricted to Superadministrators only with mobile responsiveness.
// ============================================================================

class ErrorReportsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onNavigateCluster;

  const ErrorReportsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onNavigateCluster,
  });

  @override
  State<ErrorReportsScreen> createState() => _ErrorReportsScreenState();
}

class _ErrorReportsScreenState extends State<ErrorReportsScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // Data
  List<ReportedErrorItem> _errors = [];
  List<ReportedErrorGroupItem> _groups = [];
  final Set<String> _expandedGroupKeys = {};
  ReportedErrorStatsResponse? _stats;

  // Filter state
  String _selectedType = 'ALL'; // "ALL" | "SERVER" | "CLIENT_JS"
  String _selectedStatus = 'OPEN'; // "ALL" | "OPEN" | "RESOLVED"
  final TextEditingController _searchController = TextEditingController();
  bool _isGroupedView = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ErrorReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSuperAdmin {
    final caller = widget.apiService.currentUser;
    return caller?.isSuperAdmin ?? (widget.apiService.currentUserRole == 'SUPERADMIN');
  }

  Future<void> _loadData() async {
    if (!_isSuperAdmin) return;
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final statsFuture = widget.apiService.fetchReportedErrorStats();
      final errorsFuture = widget.apiService.fetchReportedErrors(
        type: _selectedType,
        status: _selectedStatus,
        search: _searchController.text.trim(),
        limit: 500,
      );

      final results = await Future.wait([statsFuture, errorsFuture]);
      final statsRes = results[0] as ReportedErrorStatsResponse?;
      final errorsRes = results[1] as ReportedErrorsListResponse?;

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (statsRes != null) {
          _stats = statsRes;
        }
        if (errorsRes != null) {
          _errors = errorsRes.errors;
          _groups = errorsRes.groups;
          // Sync stats if available
          if (errorsRes.totalCount > 0 || _stats == null) {
            _stats = ReportedErrorStatsResponse(
              totalCount: errorsRes.totalCount,
              openCount: errorsRes.openCount,
              resolvedCount: errorsRes.resolvedCount,
              serverCount: errorsRes.serverCount,
              clientCount: errorsRes.clientCount,
            );
          }
        } else if (statsRes == null) {
          _errorMessage = 'Failed to load error reports. Check your server connection.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred: $e';
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadData();
    });
  }

  void _resetFilters() {
    setState(() {
      _selectedType = 'ALL';
      _selectedStatus = 'OPEN';
      _searchController.clear();
    });
    _loadData();
  }

  void _toggleGroupExpand(String groupKey) {
    setState(() {
      if (_expandedGroupKeys.contains(groupKey)) {
        _expandedGroupKeys.remove(groupKey);
      } else {
        _expandedGroupKeys.add(groupKey);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  Future<void> _updateStatus(String id, String newStatus) async {
    final success = await widget.apiService.updateReportedErrorStatus(id, newStatus);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report marked as ${newStatus.toLowerCase()}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update report status'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteSingle(ReportedErrorItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: const Text('Delete Error Report?'),
        content: Text(
          'Are you sure you want to permanently delete this error report? This cannot be undone.',
          style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.apiService.deleteReportedError(item.id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error report deleted'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
          _loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete error report'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateGroupStatus(ReportedErrorGroupItem group, String newStatus) async {
    final errorIds = group.occurrences.isNotEmpty
        ? group.occurrences.map((o) => o.id).toList()
        : [group.sampleError.id];

    final count = await widget.apiService.updateReportedErrorGroupStatus(errorIds, newStatus);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $count error(s) in group as ${newStatus.toLowerCase()}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      _loadData();
    }
  }

  Future<void> _deleteGroup(ReportedErrorGroupItem group) async {
    final count = group.occurrences.isNotEmpty ? group.occurrences.length : group.count;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: const Text('Delete Error Group?'),
        content: Text(
          'Are you sure you want to permanently delete all $count error report(s) in this group? This cannot be undone.',
          style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final errorIds = group.occurrences.isNotEmpty
          ? group.occurrences.map((o) => o.id).toList()
          : [group.sampleError.id];
      final deleted = await widget.apiService.deleteReportedErrorGroup(errorIds);
      if (mounted) {
        _expandedGroupKeys.remove(group.groupKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $deleted error report(s)'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        _loadData();
      }
    }
  }

  void _showClearDialog() {
    String clearTarget = 'RESOLVED';
    bool isClearing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final surface = ObsidianUITheme.getSurfaceColor(dialogCtx);
          final textPrimary = ObsidianUITheme.getPrimaryTextColor(dialogCtx);
          final textSecondary = ObsidianUITheme.getSecondaryTextColor(dialogCtx);

          return AlertDialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            title: Text(
              'Clear Error Reports',
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select which error reports you want to permanently clear from the database:',
                      style: TextStyle(color: textSecondary, fontSize: 13.0),
                    ),
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.isDark(dialogCtx)
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(
                          color: ObsidianUITheme.getBorderColor(dialogCtx),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: clearTarget,
                          isExpanded: true,
                          dropdownColor: surface,
                          items: const [
                            DropdownMenuItem(
                              value: 'RESOLVED',
                              child: Text('Resolved errors only (Safe)'),
                            ),
                            DropdownMenuItem(
                              value: 'OPEN',
                              child: Text('Open errors only'),
                            ),
                            DropdownMenuItem(
                              value: 'ALL',
                              child: Text('All error reports (Complete purge)'),
                            ),
                          ],
                          onChanged: isClearing
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setDialogState(() => clearTarget = val);
                                  }
                                },
                        ),
                      ),
                    ),
                    if (clearTarget == 'ALL') ...[
                      const SizedBox(height: 12.0),
                      Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Warning: This will delete ALL reports including open issues that have not been investigated.',
                                style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isClearing ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
                onPressed: isClearing
                    ? null
                    : () async {
                        setDialogState(() => isClearing = true);
                        final cleared = await widget.apiService.clearReportedErrors(clearTarget);
                        if (mounted) {
                          Navigator.of(ctx).pop();
                          if (cleared != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cleared $cleared error report(s)'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            _loadData();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to clear error reports'),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                child: isClearing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Clear Errors'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetailModal(ReportedErrorItem item) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final surface = ObsidianUITheme.getSurfaceColor(dialogCtx);
          final textPrimary = ObsidianUITheme.getPrimaryTextColor(dialogCtx);
          final textSecondary = ObsidianUITheme.getSecondaryTextColor(dialogCtx);
          final isServer = item.isServer;
          final isOpen = item.isOpen;

          return Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720.0, maxHeight: 680.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: ObsidianUITheme.getBorderColor(dialogCtx),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Error Report Details',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 17.0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),

                  // Dialog Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badges Row
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 6.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildTypeBadge(isServer),
                              _buildStatusBadge(isOpen),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: textSecondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                                child: Text(
                                  'ID: ${item.id}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.0,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14.0),

                          // Message Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                              ),
                            ),
                            child: SelectableText(
                              item.errorMessage.isNotEmpty ? item.errorMessage : 'No message provided.',
                              style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.w600,
                                fontSize: 14.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16.0),

                          // Metadata Table
                          _buildDetailRow(dialogCtx, 'Request / Location:', item.requestDetails ?? '-'),
                          _buildDetailRow(dialogCtx, 'Client IP / Type:', item.clientIp ?? '-'),
                          _buildDetailRow(
                            dialogCtx,
                            'User Session:',
                            item.username != null && item.username!.isNotEmpty
                                ? '${item.username} (Team ${item.teamNumber ?? "?"} ${item.program ?? ""}, Role: ${item.userRole ?? "N/A"})'
                                : 'Unauthenticated / Anonymous Client',
                          ),
                          _buildDetailRow(dialogCtx, 'Reported At:', _formatDate(item.createdAt)),
                          if (item.isResolved)
                            _buildDetailRow(
                              dialogCtx,
                              'Resolution:',
                              'Resolved by ${item.resolvedBy ?? "Superadmin"} on ${_formatDate(item.resolvedAt ?? "")}',
                              valueColor: const Color(0xFF10B981),
                            ),

                          const SizedBox(height: 16.0),

                          // Stack Trace Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'STACK TRACE',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (item.errorStack != null && item.errorStack!.isNotEmpty)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  ),
                                  icon: const Icon(Icons.copy_rounded, size: 14),
                                  label: const Text('Copy Stack', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: item.errorStack!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Stack trace copied to clipboard'),
                                        duration: Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 6.0),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12.0),
                            constraints: const BoxConstraints(maxHeight: 240.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090D16),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                item.errorStack != null && item.errorStack!.isNotEmpty
                                    ? item.errorStack!
                                    : 'No stack trace provided.',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.0,
                                  color: item.errorStack != null && item.errorStack!.isNotEmpty
                                      ? const Color(0xFFFCA5A5)
                                      : const Color(0xFF64748B),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Dialog Footer Actions
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: ObsidianUITheme.getBorderColor(dialogCtx),
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          label: const Text('Delete Report', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _deleteSingle(item);
                          },
                        ),
                        Wrap(
                          spacing: 8.0,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              icon: Icon(isOpen ? Icons.check_circle_outline_rounded : Icons.replay_rounded, size: 16),
                              label: Text(
                                isOpen ? 'Mark as Resolved' : 'Reopen Report',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateStatus(item.id, isOpen ? 'RESOLVED' : 'OPEN');
                              },
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(BuildContext ctx, String label, String value, {Color? valueColor}) {
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(ctx);
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(ctx);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ObsidianUITheme.isDark(ctx)
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.0,
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: valueColor ?? textPrimary,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_isSuperAdmin) {
      return _buildSuperadminLockedView();
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24.0 : 14.0,
          vertical: 16.0,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isDesktop),
              const SizedBox(height: 16.0),
              _buildStatsGrid(isDesktop),
              const SizedBox(height: 16.0),
              _buildFilterControls(isDesktop),
              const SizedBox(height: 16.0),
              if (_isLoading && _errors.isEmpty && _groups.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null && _errors.isEmpty && _groups.isEmpty)
                _buildErrorBanner()
              else
                _buildReportsList(isDesktop),
              const SizedBox(height: 48.0),
            ],
          ),
        ),
      ),
    );
  }

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
                  'You must be logged in as a Superadmin (Site Admin) to view and manage Error Reports.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.0, color: textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage ?? 'Failed to load error reports.',
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12.0,
          runSpacing: 12.0,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error & Bug Reports',
                    style: TextStyle(
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Review unexpected server code exceptions and client-side bug reports submitted across the cluster.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                  onPressed: _isLoading ? null : _loadData,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('Clear Errors', style: TextStyle(fontSize: 12)),
                  onPressed: _showClearDialog,
                ),
                if (widget.onNavigateCluster != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 14),
                    label: const Text('Server Management', style: TextStyle(fontSize: 12)),
                    onPressed: widget.onNavigateCluster,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isDesktop) {
    final stats = _stats;
    final total = stats?.totalCount ?? 0;
    final open = stats?.openCount ?? 0;
    final resolved = stats?.resolvedCount ?? 0;
    final server = stats?.serverCount ?? 0;
    final client = stats?.clientCount ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Adjust column count based on width to eliminate mobile overflow
        final width = constraints.maxWidth;
        final isNarrow = width < 500;

        return GridView.count(
          crossAxisCount: isDesktop ? 5 : (isNarrow ? 2 : 3),
          crossAxisSpacing: 10.0,
          mainAxisSpacing: 10.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isDesktop ? 1.6 : (isNarrow ? 1.45 : 1.6),
          children: [
            _buildStatCard(
              label: 'Total Reports',
              value: total.toString(),
              subtext: 'Logged exceptions',
              badgeText: 'Active',
              badgeBg: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              badgeColor: const Color(0xFFF59E0B),
            ),
            _buildStatCard(
              label: 'Open Issues',
              value: open.toString(),
              subtext: 'Requires review',
              badgeText: 'Unresolved',
              badgeBg: const Color(0xFFEF4444).withValues(alpha: 0.15),
              badgeColor: const Color(0xFFEF4444),
              valueColor: const Color(0xFFEF4444),
            ),
            _buildStatCard(
              label: 'Resolved',
              value: resolved.toString(),
              subtext: 'Marked fixed',
              badgeText: 'Fixed',
              badgeBg: const Color(0xFF10B981).withValues(alpha: 0.15),
              badgeColor: const Color(0xFF10B981),
              valueColor: const Color(0xFF10B981),
            ),
            _buildStatCard(
              label: 'Server Exceptions',
              value: server.toString(),
              subtext: 'JVM / backend crashes',
              badgeText: 'Backend',
              badgeBg: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              badgeColor: const Color(0xFFF59E0B),
            ),
            _buildStatCard(
              label: 'Client JS Errors',
              value: client.toString(),
              subtext: 'Frontend bug reports',
              badgeText: 'Frontend',
              badgeBg: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              badgeColor: const Color(0xFF3B82F6),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String subtext,
    required String badgeText,
    required Color badgeBg,
    required Color badgeColor,
    Color? valueColor,
  }) {
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999.0),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 22.0,
                fontWeight: FontWeight.w800,
                color: valueColor ?? textPrimary,
                height: 1.1,
              ),
            ),
            Text(
              subtext,
              style: TextStyle(
                fontSize: 10.5,
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

  Widget _buildFilterControls(bool isDesktop) {
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Wrap(
          spacing: 10.0,
          runSpacing: 10.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Type Dropdown
            _buildDropdown(
              value: _selectedType,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Error Types')),
                DropdownMenuItem(value: 'SERVER', child: Text('Server Exceptions Only')),
                DropdownMenuItem(value: 'CLIENT_JS', child: Text('Client JS Reports Only')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedType = val);
                  _loadData();
                }
              },
            ),

            // Status Dropdown
            _buildDropdown(
              value: _selectedStatus,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                DropdownMenuItem(value: 'OPEN', child: Text('Open Only')),
                DropdownMenuItem(value: 'RESOLVED', child: Text('Resolved Only')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedStatus = val);
                  _loadData();
                }
              },
            ),

            // Search Bar
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 300.0 : double.infinity,
                minWidth: 160.0,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search message, URL, user...',
                  hintStyle: TextStyle(fontSize: 12.0, color: textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  ),
                  filled: true,
                  fillColor: ObsidianUITheme.isDark(context)
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),

            // Reset Button
            TextButton(
              onPressed: _resetFilters,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),

            // Grouping Switch
            InkWell(
              onTap: () {
                setState(() => _isGroupedView = !_isGroupedView);
              },
              borderRadius: BorderRadius.circular(6.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 38,
                      child: Switch(
                        value: _isGroupedView,
                        onChanged: (val) {
                          setState(() => _isGroupedView = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Group Identical',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                        color: ObsidianUITheme.getPrimaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final surface = ObsidianUITheme.getSurfaceColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: ObsidianUITheme.isDark(context)
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: surface,
          isDense: true,
          style: TextStyle(
            fontSize: 12.0,
            color: ObsidianUITheme.getPrimaryTextColor(context),
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Reports List (Grouped or Flat)
  // ---------------------------------------------------------------------------

  Widget _buildReportsList(bool isDesktop) {
    if (_isGroupedView) {
      if (_groups.isEmpty) {
        return _buildEmptyNotice();
      }
      return Column(
        children: _groups.map((g) => _buildGroupItem(g, isDesktop)).toList(),
      );
    } else {
      if (_errors.isEmpty) {
        return _buildEmptyNotice();
      }
      return Column(
        children: _errors.map((e) => _buildFlatItem(e, isDesktop)).toList(),
      );
    }
  }

  Widget _buildEmptyNotice() {
    return ObsidianGlassCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 40.0, color: Colors.green.withValues(alpha: 0.7)),
            const SizedBox(height: 12.0),
            Text(
              'No error reports match the current filter criteria.',
              style: TextStyle(
                fontSize: 13.0,
                color: ObsidianUITheme.getSecondaryTextColor(context),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(ReportedErrorGroupItem group, bool isDesktop) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final isExpanded = _expandedGroupKeys.contains(group.groupKey);
    final isServer = group.isServer;
    final isOpen = group.hasOpen;
    final occurrences = group.occurrences.isNotEmpty ? group.occurrences : [group.sampleError];

    // User / Team Context label
    String userContext = 'Unauthenticated';
    if (group.affectedTeams.isNotEmpty) {
      final teamsStr = group.affectedTeams.take(3).join(', ') +
          (group.affectedTeams.length > 3 ? ' (+${group.affectedTeams.length - 3})' : '');
      final uCount = group.affectedUsers.length;
      userContext = 'Teams: $teamsStr${uCount > 0 ? " ($uCount user${uCount == 1 ? "" : "s"})" : ""}';
    } else if (group.affectedUsers.isNotEmpty) {
      userContext = 'Users: ${group.affectedUsers.take(3).join(", ")}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row (Clickable)
            InkWell(
              onTap: () => _toggleGroupExpand(group.groupKey),
              borderRadius: BorderRadius.circular(12.0),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Badges, Count, Date & Expand Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Wrap(
                          spacing: 6.0,
                          runSpacing: 4.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildTypeBadge(isServer),
                            _buildGroupStatusBadge(group),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: group.count > 1
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                    : textSecondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999.0),
                                border: Border.all(
                                  color: group.count > 1
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                                      : textSecondary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                group.count == 1 ? '1 occurrence' : '${group.count} occurrences',
                                style: TextStyle(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.bold,
                                  color: group.count > 1 ? const Color(0xFFEF4444) : textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatDate(group.latestCreatedAt),
                              style: TextStyle(fontSize: 11.0, color: textSecondary),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              size: 20.0,
                              color: textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10.0),

                    // Error Message
                    Text(
                      group.errorMessage.isNotEmpty ? group.errorMessage : 'Unknown error',
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6.0),

                    // Location & User Context Row
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 4.0,
                      children: [
                        if (group.location.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link_rounded, size: 13, color: textSecondary),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 320.0),
                                child: Text(
                                  group.location,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    color: textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_outline_rounded, size: 13, color: textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              userContext,
                              style: TextStyle(fontSize: 11.5, color: textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Group Action Buttons
                    const SizedBox(height: 10.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Wrap(
                          spacing: 6.0,
                          runSpacing: 6.0,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                              onPressed: () => _toggleGroupExpand(group.groupKey),
                              child: Text(
                                isExpanded ? 'Hide (${group.count})' : 'View (${group.count})',
                                style: const TextStyle(fontSize: 11.0),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                              onPressed: () => _updateGroupStatus(group, isOpen ? 'RESOLVED' : 'OPEN'),
                              child: Text(
                                isOpen ? 'Resolve All' : 'Reopen All',
                                style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFEF4444),
                                side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                              ),
                              onPressed: () => _deleteGroup(group),
                              child: const Text('Delete All', style: TextStyle(fontSize: 11.0)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Expanded Occurrences Drawer
            if (isExpanded)
              Container(
                decoration: BoxDecoration(
                  color: ObsidianUITheme.isDark(context)
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.03),
                  border: Border(
                    top: BorderSide(
                      color: ObsidianUITheme.getBorderColor(context),
                    ),
                  ),
                ),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INDIVIDUAL OCCURRENCES (${occurrences.length})',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    ...occurrences.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return _buildOccurrenceCard(item, idx + 1);
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccurrenceCard(ReportedErrorItem item, int index) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final isOpen = item.isOpen;

    final userContext = item.username != null && item.username!.isNotEmpty
        ? '${item.username} (Team ${item.teamNumber ?? "?"} ${item.program ?? ""})'
        : 'Unauthenticated';

    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: ObsidianUITheme.isDark(context)
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#$index',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(isOpen),
                ],
              ),
              Text(
                _formatDate(item.createdAt),
                style: TextStyle(fontSize: 10.5, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            userContext,
            style: TextStyle(fontSize: 11.5, color: textPrimary, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.requestDetails != null && item.requestDetails!.isNotEmpty) ...[
            const SizedBox(height: 2.0),
            Text(
              item.requestDetails!,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11.0, color: textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Wrap(
                spacing: 6.0,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    onPressed: () => _showDetailModal(item),
                    child: const Text('View', style: TextStyle(fontSize: 11.0)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    onPressed: () => _updateStatus(item.id, isOpen ? 'RESOLVED' : 'OPEN'),
                    child: Text(
                      isOpen ? 'Resolve' : 'Reopen',
                      style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                    ),
                    onPressed: () => _deleteSingle(item),
                    child: const Text('Delete', style: TextStyle(fontSize: 11.0)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlatItem(ReportedErrorItem item, bool isDesktop) {
    final textPrimary = ObsidianUITheme.getPrimaryTextColor(context);
    final textSecondary = ObsidianUITheme.getSecondaryTextColor(context);
    final isServer = item.isServer;
    final isOpen = item.isOpen;

    final userContext = item.username != null && item.username!.isNotEmpty
        ? '${item.username} (Team ${item.teamNumber ?? "?"} ${item.program ?? ""})'
        : 'Unauthenticated';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ObsidianGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildTypeBadge(isServer),
                      _buildStatusBadge(isOpen),
                    ],
                  ),
                  Text(
                    _formatDate(item.createdAt),
                    style: TextStyle(fontSize: 11.0, color: textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              Text(
                item.errorMessage.isNotEmpty ? item.errorMessage : 'Unknown error',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 4.0,
                children: [
                  if (item.requestDetails != null && item.requestDetails!.isNotEmpty)
                    Text(
                      item.requestDetails!,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11.0, color: textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    userContext,
                    style: TextStyle(fontSize: 11.5, color: textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 6.0,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                        onPressed: () => _showDetailModal(item),
                        child: const Text('View', style: TextStyle(fontSize: 11.0)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                        onPressed: () => _updateStatus(item.id, isOpen ? 'RESOLVED' : 'OPEN'),
                        child: Text(
                          isOpen ? 'Resolve' : 'Reopen',
                          style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                        ),
                        onPressed: () => _deleteSingle(item),
                        child: const Text('Delete', style: TextStyle(fontSize: 11.0)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Badges
  // ---------------------------------------------------------------------------

  Widget _buildTypeBadge(bool isServer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: isServer
            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
            : const Color(0xFF3B82F6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: isServer
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : const Color(0xFF3B82F6).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        isServer ? 'SERVER' : 'CLIENT JS',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: isServer ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: isOpen
            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
            : const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Text(
        isOpen ? 'OPEN' : 'RESOLVED',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: isOpen ? const Color(0xFFF87171) : const Color(0xFF34D399),
        ),
      ),
    );
  }

  Widget _buildGroupStatusBadge(ReportedErrorGroupItem group) {
    if (group.openCount > 0 && group.resolvedCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999.0),
        ),
        child: Text(
          '${group.openCount} OPEN',
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFFF87171),
          ),
        ),
      );
    } else if (group.openCount > 0) {
      return _buildStatusBadge(true);
    } else {
      return _buildStatusBadge(false);
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;

      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      final month = _monthName(dt.month);

      if (isToday) {
        return 'Today $hour:$minute';
      }
      return '$month ${dt.day}, $hour:$minute';
    } catch (_) {
      return dateStr;
    }
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
