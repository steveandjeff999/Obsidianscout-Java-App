import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Imports an old ObsidianScout database into this server, and the full database reset (superadmins).
/// Same data as the website's migration.html.
class MigrationScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const MigrationScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  static const _statusKeys = {
    'Migrating users...': 'migration.status.users',
    'Migrating events...': 'migration.status.events',
    'Migrating teams...': 'migration.status.teams',
    'Migrating matches...': 'migration.status.matches',
    'Migrating scouting data...': 'migration.status.scouting',
    'Migrating alliances...': 'migration.status.alliances',
    'Migration completed successfully!': 'migration.status.success',
  };

  String _sourceType = 'sqlite';
  final _sqlitePath = TextEditingController();
  final _pg = {
    'host': TextEditingController(text: 'localhost'),
    'port': TextEditingController(text: '5432'),
    'user': TextEditingController(text: 'postgres'),
    'passwordPlain': TextEditingController(),
    'database': TextEditingController(text: 'obsidian_scout'),
    'databaseUsers': TextEditingController(text: 'obsidian_scout_users'),
    'databasePages': TextEditingController(text: 'obsidian_scout_pages'),
    'databaseMisc': TextEditingController(text: 'obsidian_scout_misc'),
    'databaseImages': TextEditingController(text: 'obsidian_scout_images'),
    'databaseStatboticsepa': TextEditingController(text: 'obsidian_scout_statboticsepa'),
  };
  final _resetPassword = TextEditingController();

  Map<String, dynamic>? _status;
  Timer? _poll;
  bool _starting = false;
  bool _resetting = false;

  bool get _isSuper => widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN';

  @override
  void initState() {
    super.initState();
    if (_isSuper) _checkInitial();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sqlitePath.dispose();
    _resetPassword.dispose();
    for (final c in _pg.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkInitial() async {
    final res = await widget.apiService.requestJson('GET', '/api/admin/migration/status');
    if (!mounted || !res.success) return;
    final s = jsonMap(res.data);
    setState(() => _status = s);
    if (jsonBool(s['running'])) _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      final res = await widget.apiService.requestJson('GET', '/api/admin/migration/status');
      if (!mounted || !res.success) return;
      final s = jsonMap(res.data);
      setState(() => _status = s);
      if (!jsonBool(s['running'])) {
        _poll?.cancel();
        _poll = null;
        if (jsonBool(s['success'])) {
          ObsidianFeedback.showSuccess(context, message: context.tr('migration.status.success', 'Migration completed successfully!'));
        } else {
          ObsidianFeedback.showError(context,
              message: '${context.tr('migration.failed', 'Migration failed: ')}${_localized(jsonStr(s['message']))}');
        }
      }
    });
  }

  String _localized(String msg) => _statusKeys[msg] == null ? msg : context.tr(_statusKeys[msg]!, msg);

  Future<void> _start() async {
    final payload = <String, dynamic>{'sourceType': _sourceType};
    if (_sourceType == 'sqlite') {
      final path = _sqlitePath.text.trim();
      if (path.isEmpty) {
        ObsidianFeedback.showError(context, message: context.tr('migration.sqlite_path_required', 'Please enter the folder path'));
        return;
      }
      payload['sqliteInstancePath'] = path;
    } else {
      final cfg = <String, dynamic>{for (final e in _pg.entries) e.key: e.key == 'passwordPlain' ? e.value.text : e.value.text.trim()};
      cfg['port'] = int.tryParse(cfg['port'] as String) ?? 5432;
      if ((cfg['host'] as String).isEmpty || (cfg['user'] as String).isEmpty || (cfg['database'] as String).isEmpty) {
        ObsidianFeedback.showError(context,
            message: context.tr('migration.pg_fields_required', 'Host, Username, and Main Database are required.'));
        return;
      }
      payload['pgConfig'] = cfg;
    }
    setState(() => _starting = true);
    final res = await widget.apiService.requestJson('POST', '/api/admin/migration/run', body: payload);
    if (!mounted) return;
    setState(() => _starting = false);
    final data = jsonMap(res.data);
    if (res.success && jsonBool(data['success'])) {
      _startPolling();
    } else {
      ObsidianFeedback.showError(context,
          message: '${context.tr('migration.failed_start', 'Failed to start migration: ')}${data['error'] ?? res.message ?? 'Unknown error'}');
    }
  }

  Future<void> _reset() async {
    final password = _resetPassword.text;
    if (password.isEmpty) {
      ObsidianFeedback.showError(context, message: 'Please enter your password to confirm database reset.');
      return;
    }
    final ok = await confirmPortedAction(context,
        title: 'Reset Database Completely',
        message: 'ARE YOU ABSOLUTELY SURE? This will permanently delete all data in the database!',
        confirmLabel: 'Reset Database',
        destructive: true);
    if (!ok || !mounted) return;
    setState(() => _resetting = true);
    final res = await widget.apiService.requestJson('POST', '/api/admin/reset-database', body: {'password': password});
    if (!mounted) return;
    setState(() => _resetting = false);
    _resetPassword.clear();
    final data = jsonMap(res.data);
    if (res.success && jsonBool(data['success'])) {
      ObsidianFeedback.showSuccess(context, message: 'Database reset completed successfully!');
    } else {
      ObsidianFeedback.showError(context, message: 'Failed to reset database: ${data['error'] ?? res.message ?? 'Unknown error'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSuper) {
      return PortedLocked(
        title: context.tr('migration.locked_title', 'Superadmin Only'),
        message: context.tr('migration.locked_notice', 'You need superadmin access to manage database migrations.'),
      );
    }
    final running = jsonBool(_status?['running']);
    return PortedPageList(
      onRefresh: _checkInitial,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('migration.title', 'Database Migration'),
          subtitle: context.tr('migration.notice',
              'Migrate configuration, users, matches, teams, and scouting data from the old ObsidianScout site database directly into this PostgreSQL server.'),
        ),
        _buildSource(context, running),
        _buildStatus(context),
        _buildDanger(context),
      ],
    );
  }

  Widget _buildSource(BuildContext context, bool running) {
    final labels = {
      'host': context.tr('migration.pg_host', 'Postgres Host'),
      'port': context.tr('migration.pg_port', 'Postgres Port'),
      'user': context.tr('migration.pg_user', 'Postgres Username'),
      'passwordPlain': context.tr('migration.pg_password', 'Postgres Password'),
      'database': context.tr('migration.pg_db_main', 'Main Database Name'),
      'databaseUsers': context.tr('migration.pg_db_users', 'Users DB'),
      'databasePages': context.tr('migration.pg_db_pages', 'Pages DB'),
      'databaseMisc': context.tr('migration.pg_db_misc', 'Misc DB'),
      'databaseImages': context.tr('migration.pg_db_images', 'Images DB'),
      'databaseStatboticsepa': context.tr('migration.pg_db_statbotics', 'Statboticsepa DB'),
    };
    return PortedSection(
      title: context.tr('migration.source_title', 'Migration Source'),
      subtitle: context.tr('migration.source_notice', "Configure connection details for the old server's databases."),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _sourceType,
            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
            decoration: InputDecoration(labelText: context.tr('migration.source_type', 'Source Database Type'), isDense: true),
            items: [
              DropdownMenuItem(value: 'sqlite', child: Text(context.tr('migration.type_sqlite', 'SQLite Database Files'))),
              DropdownMenuItem(value: 'postgres', child: Text(context.tr('migration.type_postgres', 'PostgreSQL Database'))),
            ],
            onChanged: (v) => setState(() => _sourceType = v ?? 'sqlite'),
          ),
          const SizedBox(height: 8),
          if (_sourceType == 'sqlite')
            TextField(
              controller: _sqlitePath,
              decoration: InputDecoration(
                labelText: context.tr('migration.sqlite_path', 'Old Instance Folder Path'),
                hintText: r'C:\path\to\old\Obsidian-Scout\instance',
                helperText: context.tr('migration.sqlite_hint', 'Contains sqlite files like scouting.db, users.db, etc.'),
              ),
            )
          else
            for (final e in _pg.entries)
              TextField(
                controller: e.value,
                obscureText: e.key == 'passwordPlain',
                keyboardType: e.key == 'port' ? TextInputType.number : null,
                decoration: InputDecoration(labelText: labels[e.key]),
              ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: running || _starting ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(running ? 'Migrating...' : context.tr('migration.btn_start', 'Start Migration')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final s = _status;
    final progress = jsonInt(s?['progress']) ?? 0;
    if (s == null || (!jsonBool(s['running']) && progress == 0)) {
      return PortedSection(
        icon: Icons.nightlight_round,
        title: context.tr('migration.idle_title', 'No active migration'),
        subtitle: context.tr('migration.idle_subtext', 'Configure parameters on the left and start to migrate.'),
      );
    }
    return PortedSection(
      title: context.tr('migration.status_title', 'Migration Status'),
      subtitle: context.tr('migration.status_notice', 'Tracks the live status of the data migration.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (progress / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: ObsidianUITheme.getBorderColor(context),
                  color: ObsidianUITheme.primaryAccent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$progress%', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(_localized(jsonStr(s['message'])), style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getSecondaryTextColor(context))),
          const SizedBox(height: 12),
          Text(context.tr('migration.migrated_counts', 'Migrated Records Count'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          PortedStatGrid(stats: [
            PortedStat(context.tr('migration.stat_users', 'Users'), '${s['usersMigrated'] ?? 0}'),
            PortedStat(context.tr('migration.stat_events', 'Events'), '${s['eventsMigrated'] ?? 0}'),
            PortedStat(context.tr('migration.stat_teams', 'Teams'), '${s['teamsMigrated'] ?? 0}'),
            PortedStat(context.tr('migration.stat_matches', 'Matches'), '${s['matchesMigrated'] ?? 0}'),
            PortedStat(context.tr('migration.stat_scouting', 'Scouting Entries'), '${s['scoutingDataMigrated'] ?? 0}'),
            PortedStat(context.tr('migration.stat_alliances', 'Alliances'), '${s['alliancesMigrated'] ?? 0}'),
          ]),
        ],
      ),
    );
  }

  Widget _buildDanger(BuildContext context) {
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.errorRed),
            SizedBox(width: 8),
            Expanded(
              child: Text('Danger Zone: Reset Database',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ObsidianUITheme.errorRed)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'This will completely delete all data in the database, including users, scouting records, configurations, settings, matches, and alliances. This action is irreversible.',
            style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getSecondaryTextColor(context)),
          ),
          TextField(
            controller: _resetPassword,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Confirm with your Superadmin Password', hintText: 'Enter password to confirm'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: _resetting ? null : _reset,
            child: Text(_resetting ? 'Resetting...' : 'Reset Database Completely'),
          ),
        ],
      ),
    );
  }
}
