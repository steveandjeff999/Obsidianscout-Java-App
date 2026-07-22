import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.onLogout,
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
        const SnackBar(
          content: Text('Offline cache refreshed successfully!'),
          backgroundColor: ObsidianUITheme.primaryAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleClearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: const Text('Clear All Offline Cache?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will purge all locally saved teams, matches, configs, and analytics. New data will be fetched when online.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Cache', style: TextStyle(color: Colors.white)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: const Text('Change Server URL', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Server URL (e.g. http://192.168.1.50:8080)',
            labelStyle: TextStyle(color: ObsidianUITheme.primaryAccent),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
            child: const Text('Save & Reconnect', style: TextStyle(color: Colors.white)),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16.0, 96.0, 16.0, 100.0),
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
                      const Text(
                        'App Settings & Cache',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage offline data, server endpoint, & authentication',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
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
                    const Row(
                      children: [
                        Icon(Icons.folder_zip_rounded, color: ObsidianUITheme.primaryAccent),
                        SizedBox(width: 8),
                        Text(
                          'Offline Cache Manager',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    Text(
                      '${(_totalBytes / 1024).toStringAsFixed(1)} KB Total',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),

                if (_isLoadingCache)
                  const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)))
                else if (_cacheSummary.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('No offline cache stored yet. Sync data to enable full offline support.', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
                            Row(
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 16),
                                const SizedBox(width: 8),
                                Text(name, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                              ],
                            ),
                            Text('$kb KB', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontFamily: 'monospace')),
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
                          _isSyncing ? 'Syncing...' : 'Sync Cache Now',
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
                      label: const Text('Clear', style: TextStyle(color: ObsidianUITheme.errorRed, fontWeight: FontWeight.bold)),
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
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, color: ObsidianUITheme.primaryAccent),
                    SizedBox(width: 8),
                    Text(
                      'Server Endpoint',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active Server URL', style: TextStyle(fontSize: 12, color: Colors.white54)),
                          const SizedBox(height: 2),
                          Text(
                            widget.apiService.serverUrl,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
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
                const Row(
                  children: [
                    Icon(Icons.person_pin_rounded, color: ObsidianUITheme.primaryAccent),
                    SizedBox(width: 8),
                    Text(
                      'Account & Session',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.apiService.savedUsername.isNotEmpty ? widget.apiService.savedUsername : 'Logged In User',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          const Text('Session Status: Active (Keep Logged In)', style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
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
                      label: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
