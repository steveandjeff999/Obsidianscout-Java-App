import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLogout;
  final bool isVisible;
  final bool isBarsVisible;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.onLogout,
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

  @override
  void initState() {
    super.initState();
    _loadCacheSummary();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadCacheSummary();
    }
  }

  Future<void> _loadCacheSummary() async {
    setState(() => _isLoadingCache = true);
    final summary = await widget.apiService.getCacheSummary();
    if (mounted) {
      setState(() {
        _cacheSummary = summary;
        _isLoadingCache = false;
      });
    }
  }

  Future<void> _handleSyncNow() async {
    setState(() => _isSyncing = true);
    await widget.apiService.syncAllServerDataInBackground();
    await _loadCacheSummary();
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
