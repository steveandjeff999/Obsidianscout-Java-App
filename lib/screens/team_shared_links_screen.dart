import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/share_models.dart';
import '../services/api_service.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_glass_app_bar.dart';

class TeamSharedLinksScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const TeamSharedLinksScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<TeamSharedLinksScreen> createState() => _TeamSharedLinksScreenState();
}

class _TeamSharedLinksScreenState extends State<TeamSharedLinksScreen> {
  bool _isLoading = true;
  List<ShareLinkModel> _shares = [];
  String _statusFilter = 'all'; // all, active, expired, revoked
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getTeamSharedLinks(
        statusFilter: _statusFilter != 'all' ? _statusFilter : null,
      );
      if (mounted) {
        setState(() {
          _shares = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load shared links: $e')),
        );
      }
    }
  }

  Future<void> _handleRevoke(ShareLinkModel link) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('shares.revoke')),
        content: Text(context.tr('shares.confirm_revoke')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('shares.revoke')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await widget.apiService.revokeSharedLink(link.token);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('shares.revoked_success'))),
        );
        _loadShares();
      }
    }
  }

  List<ShareLinkModel> get _filteredShares {
    if (_searchQuery.isEmpty) return _shares;
    final q = _searchQuery.toLowerCase();
    return _shares.where((s) {
      final matchTitle = s.title.toLowerCase().contains(q);
      final matchCreator = s.createdByUsername.toLowerCase().contains(q);
      final matchEvent = (s.targetEventKey ?? '').toLowerCase().contains(q);
      return matchTitle || matchCreator || matchEvent;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    int activeCount = _shares.where((s) => !s.isRevoked && !s.isExpired).length;
    int totalViews = _shares.fold(0, (sum, s) => sum + s.viewCount);
    int expiredCount = _shares.where((s) => s.isExpired && !s.isRevoked).length;
    int revokedCount = _shares.where((s) => s.isRevoked).length;

    return Scaffold(
      appBar: widget.isBarsVisible
          ? ObsidianGlassAppBar(
              title: context.tr('shares.title'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadShares,
                  tooltip: context.tr('common.refresh'),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadShares,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Stats Row
            Row(
              children: [
                _buildStatCard(context.tr('shares.active_links'), activeCount.toString(), Colors.green, theme),
                const SizedBox(width: 8),
                _buildStatCard(context.tr('shares.total_views'), totalViews.toString(), Colors.blue, theme),
                const SizedBox(width: 8),
                _buildStatCard(context.tr('share_modal.expiration'), expiredCount.toString(), Colors.orange, theme),
                const SizedBox(width: 8),
                _buildStatCard(context.tr('shares.status_revoked'), revokedCount.toString(), Colors.purple, theme),
              ],
            ),
            const SizedBox(height: 16),

            // Search & Filter
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '${context.tr('common.search')}...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(context.tr('shares.filter_all_status'))),
                    DropdownMenuItem(value: 'active', child: Text(context.tr('shares.active_links'))),
                    DropdownMenuItem(value: 'expired', child: Text(context.tr('share_modal.expiration'))),
                    DropdownMenuItem(value: 'revoked', child: Text(context.tr('shares.status_revoked'))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _statusFilter = val);
                      _loadShares();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Links List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_filteredShares.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.share_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No shared links found', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              ..._filteredShares.map((link) => _buildShareCard(link, theme, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color accent, ThemeData theme) {
    return Expanded(
      child: ObsidianGlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildShareCard(ShareLinkModel link, ThemeData theme, bool isDark) {
    final fullUrl = link.shareUrl != null && link.shareUrl!.isNotEmpty
        ? (link.shareUrl!.startsWith('http') ? link.shareUrl! : '${widget.apiService.serverUrl}${link.shareUrl}')
        : '${widget.apiService.serverUrl}/shared/${link.token}';

    Color statusColor = Colors.green;
    String statusText = 'ACTIVE';
    if (link.isRevoked) {
      statusColor = Colors.purple;
      statusText = 'REVOKED';
    } else if (link.isExpired) {
      statusColor = Colors.red;
      statusText = 'EXPIRED';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ObsidianGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    link.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildBadge(link.resourceType.toUpperCase(), Colors.blue),
                _buildBadge(link.accessScope.toUpperCase(), Colors.orange),
                _buildBadge('${link.viewCount} ${context.tr('shares.views')}', Colors.teal),
                if (link.hasPin) _buildBadge(context.tr('shares.scope_pin'), Colors.amber),
                if (link.shareMode == 'frozen_snapshot') _buildBadge(context.tr('shares.mode_snapshot'), Colors.indigo),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${context.tr('shares.created_by')} ${link.createdByUsername} • ${link.targetEventKey ?? "All Events"}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            if (link.expiresAt != null)
              Text(
                '${context.tr('share_modal.expiration')}: ${link.expiresAt!.toLocal().toString().split(".")[0]}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 20),
                  tooltip: context.tr('shares.preview', 'Open in Browser'),
                  onPressed: () async {
                    final uri = Uri.tryParse(fullUrl);
                    if (uri != null) {
                      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                        await launchUrl(uri, mode: LaunchMode.platformDefault);
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  tooltip: context.tr('shares.view_qr', 'Show QR Code'),
                  onPressed: () => _showQrCodeDialog(link, fullUrl),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: context.tr('shares.copy_link', 'Copy Link'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('shares.copied_to_clipboard', 'Link copied to clipboard!'))),
                    );
                  },
                ),
                if (!link.isRevoked)
                  IconButton(
                    icon: const Icon(Icons.block, size: 20, color: Colors.redAccent),
                    tooltip: context.tr('shares.revoke', 'Revoke'),
                    onPressed: () => _handleRevoke(link),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showQrCodeDialog(ShareLinkModel link, String fullUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                link.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: QrImageView(
                      data: fullUrl,
                      version: QrVersions.auto,
                      size: 186.0,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      errorStateBuilder: (cxt, err) {
                        return const Center(
                          child: Text(
                            'Unable to render QR code',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  fullUrl,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(context.tr('shares.copy_link', 'Copy Link')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullUrl));
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(context.tr('shares.copied_to_clipboard', 'Link copied to clipboard!'))),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('share_modal.btn_done', 'Done')),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
