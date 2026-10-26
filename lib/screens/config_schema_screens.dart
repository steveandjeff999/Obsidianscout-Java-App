import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// The three form kinds both pages switch between, with the website's tab labels.
const _formKinds = {'game': 'Game Scouting Form', 'pit': 'Pit Scouting Form', 'qual': 'Qualitative Scouting Form'};

Widget _kindSwitcher(String kind, ValueChanged<String> onChanged) => SegmentedButton<String>(
      segments: [
        for (final e in _formKinds.entries)
          ButtonSegment(value: e.key, label: Text(e.value.replaceFirst(' Scouting Form', ''))),
      ],
      selected: {kind},
      onSelectionChanged: (s) => onChanged(s.first),
    );

/// Past revisions of the team's scouting forms: inspect, restore. Same data as the website's schema-history.html.
class SchemaHistoryScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onOpenMigration;
  final VoidCallback? onOpenFormEditor;

  const SchemaHistoryScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onOpenMigration,
    this.onOpenFormEditor,
  });

  @override
  State<SchemaHistoryScreen> createState() => _SchemaHistoryScreenState();
}

class _SchemaHistoryScreenState extends State<SchemaHistoryScreen> {
  String _kind = 'game';
  bool _loading = true;
  List<ConfigRevisionModel> _revisions = [];

  @override
  void initState() {
    super.initState();
    if (widget.apiService.isAdmin) _load();
  }

  @override
  void didUpdateWidget(covariant SchemaHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && widget.apiService.isAdmin) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final revisions = await widget.apiService.fetchConfigHistory(_kind);
    if (!mounted) return;
    setState(() {
      _revisions = revisions;
      _loading = false;
    });
  }

  Future<void> _inspect(ConfigRevisionModel rev) async {
    final detail = await widget.apiService.fetchConfigRevisionDetail(rev.id);
    if (!mounted) return;
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(detail?.configJson ?? ''));
    } catch (_) {
      pretty = detail?.configJson ?? 'Failed to load configuration.';
    }
    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text('Revision v${rev.version} - ${rev.title}'),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saved on ${fmtDateTime(ctx, rev.createdAt)} by ${rev.savedByUsername ?? 'admin'} · ${rev.configKind.toUpperCase()} Form',
                style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
          if (_revisions.isNotEmpty && _revisions.first.id != rev.id)
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (restore == true && mounted) _restore(rev);
  }

  Future<void> _restore(ConfigRevisionModel rev) async {
    final ok = await confirmPortedAction(context,
        title: 'Restore v${rev.version}',
        message:
            'Are you sure you want to restore schema version v${rev.version}?\n\nThis will update your active ${_kind.toUpperCase()} form configuration to match this historical version.');
    if (!ok || !mounted) return;
    final res = await widget.apiService.restoreConfigRevision(rev.id, _kind);
    if (!mounted) return;
    if (!reportResult(context, res, action: 'Restore', success: 'Restored version v${rev.version} successfully!')) return;
    await _load();
    // Offer Data Migration when saved records no longer match the restored fields.
    final status = await widget.apiService.fetchConfigMigrationStatus(_kind);
    if (!mounted || status == null || status.entryCount == 0 || status.unmatchedDataKeys.isEmpty) return;
    if (widget.onOpenMigration == null) return;
    final go = await confirmPortedAction(context,
        title: 'Schema restored',
        message:
            'You have ${status.entryCount} existing records that may have schema differences with this restored version.\n\nWould you like to open the Data Migration page now?',
        confirmLabel: 'Data Migration');
    if (go) widget.onOpenMigration!();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.isAdmin) {
      return const PortedLocked(title: 'Admin only', message: 'You need team admin access to view schema history.');
    }
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: 'Scouting Schema History',
          subtitle:
              'Review historical revisions of your scouting forms, inspect past field structures, restore previous versions, or run data migrations.',
          actions: [
            if (widget.onOpenMigration != null)
              OutlinedButton.icon(
                onPressed: widget.onOpenMigration,
                icon: const Icon(Icons.sync_alt_rounded, size: 18),
                label: const Text('Data Migration'),
              ),
          ],
          child: _kindSwitcher(_kind, (k) {
            setState(() => _kind = k);
            _load();
          }),
        ),
        if (_loading)
          const PortedLoading()
        else if (_revisions.isEmpty)
          PortedSection(
            icon: Icons.history_edu_rounded,
            title: 'No Historical Snapshots Recorded Yet',
            subtitle: 'Revisions are automatically captured whenever you save changes to your scouting form in Admin Settings.',
            actions: [
              if (widget.onOpenFormEditor != null)
                OutlinedButton(onPressed: widget.onOpenFormEditor, child: const Text('Go to Form Editor')),
            ],
          )
        else
          for (var i = 0; i < _revisions.length; i++)
            Builder(builder: (context) {
              final rev = _revisions[i];
              final latest = i == 0;
              return ObsidianGlassCard(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      PortedBadge('v${rev.version}'),
                      Text(rev.title.isNotEmpty ? rev.title : 'Scouting Form',
                          style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
                      if (latest) PortedBadge('Latest Active', color: ObsidianUITheme.successGreen),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      '${rev.createdAt == null ? 'Unknown date' : fmtDateTime(context, rev.createdAt)} · Saved by ${rev.savedByUsername ?? 'admin'} · ${rev.fieldCount} fields',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rev.changeSummary?.isNotEmpty == true ? 'Summary: ${rev.changeSummary}' : 'No change description',
                      style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(onPressed: () => _inspect(rev), child: const Text('Inspect Fields')),
                      TextButton(onPressed: latest ? null : () => _restore(rev), child: const Text('Restore')),
                    ]),
                  ],
                ),
              );
            }),
      ],
    );
  }
}

/// Rewrites stored scouting records to match the current form: map, keep, or delete each old key and
/// backfill new fields. Same data as the website's config-migration.html.
class ConfigMigrationScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final VoidCallback? onOpenHistory;

  const ConfigMigrationScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onOpenHistory,
  });

  @override
  State<ConfigMigrationScreen> createState() => _ConfigMigrationScreenState();
}

class _ConfigMigrationScreenState extends State<ConfigMigrationScreen> {
  String _kind = 'game';
  bool _loading = true;
  ConfigSchemaStatusModel? _status;
  final Map<String, String> _actions = {};
  final Map<String, String> _targets = {};
  final Map<String, dynamic> _defaults = {};
  ConfigMigrationPreviewModel? _preview;
  int _sample = 0;
  bool _previewLoading = false;
  bool _migrating = false;

  @override
  void initState() {
    super.initState();
    if (widget.apiService.isAdmin) _load();
  }

  @override
  void didUpdateWidget(covariant ConfigMigrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && widget.apiService.isAdmin) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _preview = null;
    });
    final status = await widget.apiService.fetchConfigMigrationStatus(_kind);
    if (!mounted) return;
    _actions.clear();
    _targets.clear();
    _defaults.clear();
    if (status != null) {
      for (final k in status.dataKeys) {
        _actions[k] = status.unmatchedDataKeys.contains(k) ? 'keep' : 'map';
        _targets[k] = k;
      }
    }
    setState(() {
      _status = status;
      _loading = false;
    });
    if (status != null && status.entryCount > 0) _fetchPreview();
  }

  List<Map<String, dynamic>> _mappings() => [
        for (final k in _status?.dataKeys ?? const <String>[])
          {
            'oldKey': k,
            'newKey': _actions[k] == 'map' ? (_targets[k] ?? k) : null,
            'action': _actions[k] ?? 'map',
          },
      ];

  Future<void> _fetchPreview() async {
    setState(() => _previewLoading = true);
    final prev = await widget.apiService.previewConfigMigration(_kind, _mappings(), _defaults);
    if (!mounted) return;
    setState(() {
      _preview = prev;
      _sample = 0;
      _previewLoading = false;
    });
  }

  Future<void> _apply() async {
    final status = _status;
    if (status == null) return;
    final ok = await confirmPortedAction(context,
        title: 'Execute Data Migration',
        message: 'Rewrite ${status.entryCount} stored ${_formKinds[_kind]} records with these mappings? This changes saved data.',
        destructive: true);
    if (!ok || !mounted) return;
    setState(() => _migrating = true);
    final res = await widget.apiService.applyConfigMigration(_kind, _mappings(), _defaults);
    if (!mounted) return;
    setState(() => _migrating = false);
    if (res.success && res.data?.success == true) {
      ObsidianFeedback.showSuccess(context,
          title: 'Migration Succeeded', message: 'Successfully migrated ${res.data!.migratedCount} records for ${_formKinds[_kind]}');
      _load();
    } else {
      reportResult(context, res, action: 'Migration Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.isAdmin) {
      return const PortedLocked(title: 'Admin only', message: 'You need team admin access to run data migrations.');
    }
    final status = _status;
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: 'Config Data Migration',
          subtitle: 'Migrate stored scouting records into your new form configuration format.',
          actions: [
            if (widget.onOpenHistory != null)
              OutlinedButton.icon(
                onPressed: widget.onOpenHistory,
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('Schema History'),
              ),
          ],
          child: _kindSwitcher(_kind, (k) {
            setState(() => _kind = k);
            _load();
          }),
        ),
        if (_loading)
          const PortedLoading()
        else if (status == null)
          PortedError(message: 'Failed to load migration status from server.', onRetry: _load)
        else ...[
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16),
            child: PortedStatGrid(stats: [
              PortedStat('Records', '${status.entryCount}'),
              PortedStat('Legacy Keys', '${status.unmatchedDataKeys.length}'),
              PortedStat('New Fields', '${status.newConfigKeys.length}'),
            ]),
          ),
          _buildMappings(context, status),
          if (status.newConfigKeys.isNotEmpty) _buildBackfill(context, status),
          _buildPreview(context, status),
          if (status.entryCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: _migrating ? null : _apply,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(_migrating ? 'Migrating Records...' : 'Execute Data Migration'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildMappings(BuildContext context, ConfigSchemaStatusModel status) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return PortedSection(
      title: 'Field Key Mappings',
      child: status.dataKeys.isEmpty
          ? Text('No existing stored records found for ${_formKinds[_kind]}.',
              style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getSecondaryTextColor(context)))
          : Column(
              children: [
                for (final k in status.dataKeys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(k,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: status.unmatchedDataKeys.contains(k)
                                      ? ObsidianUITheme.warningOrange
                                      : ObsidianUITheme.getPrimaryTextColor(context),
                                )),
                          ),
                          DropdownButton<String>(
                            value: _actions[k] ?? 'map',
                            isDense: true,
                            dropdownColor: surface,
                            items: const [
                              DropdownMenuItem(value: 'map', child: Text('Map to Field')),
                              DropdownMenuItem(value: 'keep', child: Text('Keep as-is')),
                              DropdownMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _actions[k] = v);
                              _fetchPreview();
                            },
                          ),
                        ]),
                        if ((_actions[k] ?? 'map') == 'map' && status.configFields.isNotEmpty)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            isDense: true,
                            initialValue: status.configFields.any((f) => f.id == _targets[k]) ? _targets[k] : status.configFields.first.id,
                            dropdownColor: surface,
                            decoration: const InputDecoration(labelText: 'Target Config Field', isDense: true),
                            items: [
                              for (final f in status.configFields)
                                DropdownMenuItem(value: f.id, child: Text('${f.label} (${f.id})', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _targets[k] = v);
                              _fetchPreview();
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildBackfill(BuildContext context, ConfigSchemaStatusModel status) {
    return PortedSection(
      title: 'New Fields Default Backfill',
      child: Column(
        children: [
          for (final nk in status.newConfigKeys)
            Builder(builder: (context) {
              final field = status.configFields.where((f) => f.id == nk).firstOrNull;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  decoration: InputDecoration(labelText: '${field?.label ?? nk} ($nk) default value', isDense: true),
                  onChanged: (v) => _defaults[nk] = v,
                  onSubmitted: (_) => _fetchPreview(),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, ConfigSchemaStatusModel status) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final samples = _preview?.samples ?? const <ConfigMigrationSampleModel>[];
    return PortedSection(
      title: 'Transformation Preview',
      actions: [
        if (status.entryCount > 0)
          TextButton.icon(
            onPressed: _previewLoading ? null : _fetchPreview,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_previewLoading ? 'Updating...' : 'Update Preview'),
          ),
      ],
      child: _previewLoading
          ? const PortedLoading()
          : status.entryCount == 0
              ? Text(
                  'No scouting records exist for ${_formKinds[_kind]}. Future records will be saved automatically with the current schema.',
                  style: TextStyle(fontSize: 12.5, color: muted))
              : samples.isEmpty
                  ? Text('No preview sample available.', style: TextStyle(fontSize: 12.5, color: muted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('Sample ${_sample + 1} of ${samples.length}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: _sample > 0 ? () => setState(() => _sample--) : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            onPressed: _sample < samples.length - 1 ? () => setState(() => _sample++) : null,
                          ),
                        ]),
                        Text('Before', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: muted)),
                        SelectableText(const JsonEncoder.withIndent('  ').convert(samples[_sample].before),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                        const SizedBox(height: 8),
                        const Text('Migrated Schema Output',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ObsidianUITheme.successGreen)),
                        SelectableText(const JsonEncoder.withIndent('  ').convert(samples[_sample].after),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                      ],
                    ),
    );
  }
}
