import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLogout;
  final VoidCallback? onNavigateConfigEditor;
  final bool isVisible;
  final bool isBarsVisible;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.onLogout,
    this.onNavigateConfigEditor,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoadingCache = true;
  bool _isSyncing = false;
  Map<String, int> _cacheSummary = {};

  List<Map<String, dynamic>> _sessions = [];
  bool _isLoadingSessions = false;
  bool _isRevokingSession = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSummary();
    _loadSessions();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadCacheSummary();
      _loadSessions();
    }
  }

  Future<void> _loadCacheSummary() async {
    if (!mounted) return;
    setState(() => _isLoadingCache = true);
    final summary = await widget.apiService.getCacheSummary();
    if (mounted) {
      setState(() {
        _cacheSummary = summary;
        _isLoadingCache = false;
      });
    }
  }

  Future<void> _loadSessions() async {
    if (!widget.apiService.isLoggedIn || !mounted) return;
    setState(() => _isLoadingSessions = true);
    final sessions = await widget.apiService.fetchSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _isLoadingSessions = false;
      });
    }
  }

  Future<void> _revokeSession(String sessionId, String deviceName) async {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text('Revoke Session', style: TextStyle(color: primaryTextColor)),
        content: Text(
          'Are you sure you want to revoke session for "$deviceName"? This device will be signed out immediately.',
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: tertiaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isRevokingSession = true);
      final res = await widget.apiService.revokeSession(sessionId);
      if (mounted) {
        setState(() => _isRevokingSession = false);
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session revoked successfully'),
              backgroundColor: ObsidianUITheme.primaryAccent,
              duration: Duration(seconds: 2),
            ),
          );
          _loadSessions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message ?? 'Failed to revoke session'),
              backgroundColor: ObsidianUITheme.errorRed,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _revokeAllOtherSessions() async {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text('Revoke Other Sessions', style: TextStyle(color: primaryTextColor)),
        content: Text(
          'Are you sure you want to revoke all other active sessions? All other logged-in devices will be signed out immediately.',
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: tertiaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke All Others', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isRevokingSession = true);
      final res = await widget.apiService.revokeAllOtherSessions();
      if (mounted) {
        setState(() => _isRevokingSession = false);
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All other sessions revoked successfully'),
              backgroundColor: ObsidianUITheme.primaryAccent,
              duration: Duration(seconds: 2),
            ),
          );
          _loadSessions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message ?? 'Failed to revoke sessions'),
              backgroundColor: ObsidianUITheme.errorRed,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  IconData _getDeviceIcon(String clientType, String deviceName) {
    final name = deviceName.toLowerCase();
    if (name.contains('android') || name.contains('iphone') || name.contains('ios') || clientType.toLowerCase() == 'mobile') {
      return Icons.smartphone_rounded;
    } else if (name.contains('ipad') || name.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    } else if (name.contains('mac') || name.contains('windows') || name.contains('linux') || name.contains('pc')) {
      return Icons.computer_rounded;
    }
    return Icons.devices_rounded;
  }

  String _formatSessionTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Unknown';
    try {
      final dt = DateTime.tryParse(dateStr)?.toLocal();
      if (dt == null) return dateStr;
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _handleSyncNow() async {
    if (!mounted) return;
    setState(() => _isSyncing = true);
    await widget.apiService.syncAllServerDataInBackground();
    if (!mounted) return;
    await _loadCacheSummary();
    if (!mounted) return;
    await _loadSessions();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('dashboard.sync_complete')),
          backgroundColor: ObsidianUITheme.primaryAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleClearCache() async {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('settings.clear_cache'), style: TextStyle(color: primaryTextColor)),
        content: Text(
          'This will purge all locally saved teams, matches, configs, and analytics. New data will be fetched when online.',
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: tertiaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('graphs.clear_all'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.apiService.clearAllCache();
      await _loadCacheSummary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All local cache cleared!'),
            backgroundColor: ObsidianUITheme.warningOrange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showEditServerUrlDialog() {
    final controller = TextEditingController(text: widget.apiService.serverUrl);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('login.server_url'), style: TextStyle(color: primaryTextColor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: 'Server URL (e.g. http://192.168.1.50:8080)',
            labelStyle: const TextStyle(color: ObsidianUITheme.primaryAccent),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: tertiaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await widget.apiService.setServerUrl(newUrl);
                if (ctx.mounted) Navigator.of(ctx).pop();
                _handleSyncNow();
              }
            },
            child: Text(context.tr('settings.save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatKeyName(String rawKey) {
    switch (rawKey) {
      case 'cache_config':
        return 'Match Scouting Config';
      case 'cache_pit_config':
        return 'Pit Scouting Config';
      case 'cache_qual_config':
        return 'Qual Scouting Config';
      case 'cache_settings':
        return 'App & Event Settings';
      case 'cache_scouting':
        return 'Scouting Submissions';
      case 'cache_pit_scouting':
        return 'Pit Scouting Submissions';
      case 'cache_qual_scouting':
        return 'Qual Scouting Submissions';
      case 'cache_prescout_scouting':
        return 'Prescout Match Submissions';
      case 'cache_prescout_pit_scouting':
        return 'Prescout Pit Submissions';
      case 'cache_prescout_qual_scouting':
        return 'Prescout Qual Submissions';
      case 'cache_analytics':
        return 'Analytics & Visualizations';
      default:
        if (rawKey.startsWith('cache_teams_')) return 'Teams List (${rawKey.replaceAll('cache_teams_', '')})';
        if (rawKey.startsWith('cache_matches_')) return 'Match Schedule (${rawKey.replaceAll('cache_matches_', '')})';
        return rawKey.replaceAll('cache_', '').replaceAll('_', ' ');
    }
  }

  int get _totalBytes => _cacheSummary.values.fold(0, (sum, size) => sum + size);

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16.0, 4.0, 16.0, widget.isBarsVisible ? 100.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          ObsidianGlassCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.settings_suggest_rounded, color: ObsidianUITheme.primaryAccent, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('nav.settings_cache'),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('subtitle.settings'),
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Language Selector Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language_rounded, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('settings.language'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('settings.language_subtitle'), style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: widget.apiService.currentLocale.languageCode,
                      dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                      style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                      underline: Container(height: 2, color: ObsidianUITheme.primaryAccent),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English 🇺🇸')),
                        DropdownMenuItem(value: 'es', child: Text('Español 🇪🇸')),
                        DropdownMenuItem(value: 'he', child: Text('עברית 🇮🇱')),
                        DropdownMenuItem(value: 'tr', child: Text('Türkçe 🇹🇷')),
                      ],
                      onChanged: (newLang) {
                        if (newLang != null) {
                          widget.apiService.setLocale(Locale(newLang));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Network Request Timeout Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Network Request Timeout',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HTTP & Sync Timeout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor)),
                          const SizedBox(height: 2),
                          Text(
                            'Duration before requests abort and fall back to offline cache.',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: widget.apiService.timeoutNotifier,
                      builder: (context, currentTimeout, _) {
                        final allowedTimeouts = [3, 6, 10, 15, 20, 30];
                        final effectiveValue = allowedTimeouts.contains(currentTimeout) ? currentTimeout : 6;

                        return DropdownButton<int>(
                          value: effectiveValue,
                          dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                          underline: Container(height: 2, color: ObsidianUITheme.primaryAccent),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3s (Fast / Local)')),
                            DropdownMenuItem(value: 6, child: Text('6s (Standard)')),
                            DropdownMenuItem(value: 10, child: Text('10s (Crowded Wi-Fi)')),
                            DropdownMenuItem(value: 15, child: Text('15s (Slow Arena LTE)')),
                            DropdownMenuItem(value: 20, child: Text('20s (High Latency)')),
                            DropdownMenuItem(value: 30, child: Text('30s (Maximum)')),
                          ],
                          onChanged: (newTimeout) async {
                            if (newTimeout != null) {
                              await widget.apiService.setRequestTimeoutSeconds(newTimeout);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Request timeout set to ${newTimeout}s'),
                                    backgroundColor: ObsidianUITheme.primaryAccent,
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Form Configuration Editor Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: ObsidianUITheme.primaryAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Scouting Forms Editor',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                      ],
                    ),
                    if (widget.onNavigateConfigEditor != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ObsidianUITheme.primaryAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
                        label: const Text('Open Editor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: widget.onNavigateConfigEditor,
                      ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Text(
                  'Customize field inputs, numeric ranges, double-stepping, scoring points, dropdown options, and form schemas for Match, Pit, and Qualitative scouting.',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: widget.onNavigateConfigEditor,
                        child: Text('Match Form', style: TextStyle(color: primaryTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: widget.onNavigateConfigEditor,
                        child: Text('Pit Form', style: TextStyle(color: primaryTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: widget.onNavigateConfigEditor,
                        child: Text('Qual Form', style: TextStyle(color: primaryTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                        label: const Text('Schema History', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: widget.onNavigateConfigEditor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.transform_rounded, size: 14, color: Colors.cyanAccent),
                        label: const Text('Data Migration', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: widget.onNavigateConfigEditor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cache Manager Section
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.folder_zip_rounded, color: ObsidianUITheme.primaryAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('settings.offline_cache'),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${(_totalBytes / 1024).toStringAsFixed(1)} KB ${context.tr("dashboard.total")}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),

                if (_isLoadingCache)
                  const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)))
                else if (_cacheSummary.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(context.tr('settings.no_cache'), style: TextStyle(color: tertiaryTextColor, fontSize: 13)),
                  )
                else
                  Column(
                    children: _cacheSummary.entries.map((entry) {
                      final name = _formatKeyName(entry.key);
                      final kb = (entry.value / 1024).toStringAsFixed(1);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(color: primaryTextColor, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$kb KB', style: TextStyle(color: tertiaryTextColor, fontSize: 12, fontFamily: 'monospace')),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ObsidianUITheme.primaryAccent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isSyncing ? null : _handleSyncNow,
                        icon: _isSyncing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                        label: Text(
                          _isSyncing ? context.tr('dashboard.quick_sync') : context.tr('settings.sync_now'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: ObsidianUITheme.errorRed),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _handleClearCache,
                      icon: const Icon(Icons.delete_sweep_rounded, color: ObsidianUITheme.errorRed, size: 20),
                      label: Text(context.tr('graphs.clear_all'), style: const TextStyle(color: ObsidianUITheme.errorRed, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Server Endpoint Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dns_rounded, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('login.server_url'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('settings.active_server'), style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                          const SizedBox(height: 2),
                          Text(
                            widget.apiService.serverUrl,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: ObsidianUITheme.primaryAccent),
                      onPressed: _showEditServerUrlDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active Sessions Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.devices_rounded, color: ObsidianUITheme.primaryAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Active Sessions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: _isLoadingSessions
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent))
                          : const Icon(Icons.refresh_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                      tooltip: 'Refresh Sessions',
                      onPressed: _isLoadingSessions ? null : _loadSessions,
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Text(
                  'Manage devices signed in to your account. You can revoke sessions from other devices at any time.',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(height: 12),
                if (_isLoadingSessions && _sessions.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                    ),
                  )
                else if (_sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No active sessions found.',
                      style: TextStyle(fontSize: 13, color: secondaryTextColor, fontStyle: FontStyle.italic),
                    ),
                  )
                else ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isCurrent = session['isCurrent'] == true;
                      final clientType = session['clientType']?.toString() ?? 'web';
                      final deviceName = session['deviceName']?.toString() ?? 'Unknown Device';
                      final ipAddress = session['ipAddress']?.toString() ?? 'Unknown IP';
                      final lastActiveAt = session['lastActiveAt']?.toString();
                      final sessionId = session['id']?.toString() ?? '';

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.08)
                              : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)
                                : borderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _getDeviceIcon(clientType, deviceName),
                                color: isCurrent ? ObsidianUITheme.primaryAccent : secondaryTextColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          deviceName,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: primaryTextColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isCurrent) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                                          ),
                                          child: const Text(
                                            'This Device',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$ipAddress • Last active ${_formatSessionTime(lastActiveAt)}',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            if (!isCurrent && sessionId.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.logout_rounded, color: ObsidianUITheme.errorRed, size: 20),
                                tooltip: 'Revoke this session',
                                onPressed: _isRevokingSession ? null : () => _revokeSession(sessionId, deviceName),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_sessions.any((s) => s['isCurrent'] != true)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: ObsidianUITheme.errorRed),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isRevokingSession ? null : _revokeAllOtherSessions,
                        icon: const Icon(Icons.phonelink_erase_rounded, color: ObsidianUITheme.errorRed, size: 18),
                        label: const Text(
                          'Revoke All Other Sessions',
                          style: TextStyle(color: ObsidianUITheme.errorRed, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Account & Logout Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('settings.account_session'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                Divider(color: borderColor, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.apiService.savedUsername.isNotEmpty ? widget.apiService.savedUsername : 'Operator',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          const SizedBox(height: 2),
                          Text('Session: ${context.tr("connection.online")}', style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ObsidianUITheme.errorRed.withValues(alpha: 0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 18),
                      label: Text(context.tr('settings.logout'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
