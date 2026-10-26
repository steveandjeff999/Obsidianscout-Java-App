import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// System default form presets for FTC and FRC teams (site admins). Same data as the website's
/// default-configs.html; presets are edited as JSON here, the visual builder stays on the website.
class DefaultConfigsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const DefaultConfigsScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<DefaultConfigsScreen> createState() => _DefaultConfigsScreenState();
}

class _DefaultConfigsScreenState extends State<DefaultConfigsScreen> {
  bool _loading = true;
  String? _error;
  bool _denied = false;
  List<Map<String, dynamic>> _presets = [];
  String _program = 'ALL';
  String _type = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DefaultConfigsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.requestJson('GET', '/api/admin/default-configs');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _denied = res.statusCode == 401 || res.statusCode == 403;
      _error = res.success ? null : (res.message ?? 'Failed to fetch presets');
      if (res.success) _presets = jsonMaps(res.data);
    });
  }

  Future<void> _edit(Map<String, dynamic>? preset) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _PresetEditor(apiService: widget.apiService, preset: preset),
    ));
    if (saved == true && mounted) _load();
  }

  Future<void> _setActive(Map<String, dynamic> p) async {
    final res = await widget.apiService.requestJson('PUT', '/api/admin/default-configs/${p['id']}', body: {...p, 'isDefault': true});
    if (!mounted) return;
    if (reportResult(context, res, action: 'Set Active')) _load();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('common.delete', 'Delete'),
        message: "Are you sure you want to delete the default config preset '${p['name']}'?",
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.requestJson('DELETE', '/api/admin/default-configs/${p['id']}');
    if (!mounted) return;
    if (reportResult(context, res, action: context.tr('common.delete', 'Delete'))) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return PortedLocked(title: 'Admin only', message: 'You must be a site admin to manage default configs.');
    }
    final shown = _presets
        .where((p) =>
            (_program == 'ALL' || p['program'] == _program) &&
            (_type == 'ALL' || jsonStr(p['configType']).toLowerCase() == _type.toLowerCase()))
        .toList();
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: 'Default Configs Manager',
          subtitle: 'Create, edit, and set system default configurations for FTC and FRC teams.',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create New Default Preset'),
            ),
          ],
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _program,
                  dropdownColor: surface,
                  decoration: const InputDecoration(labelText: 'Program', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Programs')),
                    DropdownMenuItem(value: 'FTC', child: Text('FTC')),
                    DropdownMenuItem(value: 'FRC', child: Text('FRC')),
                  ],
                  onChanged: (v) => setState(() => _program = v ?? 'ALL'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  dropdownColor: surface,
                  decoration: const InputDecoration(labelText: 'Type', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Types')),
                    DropdownMenuItem(value: 'match', child: Text('Match')),
                    DropdownMenuItem(value: 'pit', child: Text('Pit')),
                    DropdownMenuItem(value: 'qualitative', child: Text('Qualitative')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'ALL'),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          const PortedLoading()
        else if (_error != null)
          PortedError(message: 'Error loading default configs: $_error', onRetry: _load)
        else if (shown.isEmpty)
          PortedNotice(_presets.isEmpty
              ? 'No default config presets exist yet. All default configurations are manually created.'
              : 'No default config presets match your filters.')
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Text('${shown.length} preset${shown.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
          ),
          for (final p in shown) _buildPreset(context, p),
        ],
      ],
    );
  }

  Widget _buildPreset(BuildContext context, Map<String, dynamic> p) {
    final isDefault = jsonBool(p['isDefault']);
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(jsonStr(p['name']),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            PortedBadge(jsonStr(p['program']), color: p['program'] == 'FTC' ? const Color(0xFFF97316) : const Color(0xFF38BDF8)),
            PortedBadge(jsonStr(p['configType'])),
            if (isDefault) PortedBadge('Active Default', color: ObsidianUITheme.successGreen),
          ]),
          const SizedBox(height: 6),
          Text('Modified: ${p['updatedAt'] == null ? 'N/A' : fmtDateTime(context, p['updatedAt'])}',
              style: TextStyle(fontSize: 11.5, color: ObsidianUITheme.getSecondaryTextColor(context))),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [
            if (!isDefault)
              TextButton.icon(
                  onPressed: () => _setActive(p), icon: const Icon(Icons.star_rounded, size: 16), label: const Text('Set Active')),
            TextButton(onPressed: () => _edit(p), child: Text(context.tr('common.edit', 'Edit'))),
            TextButton(
              onPressed: () => _edit({...p, 'id': '', 'name': '${p['name']}_copy', 'isDefault': false}),
              child: const Text('Duplicate'),
            ),
            TextButton(
              onPressed: () => _delete(p),
              style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
              child: Text(context.tr('common.delete', 'Delete')),
            ),
          ]),
        ],
      ),
    );
  }
}

class _PresetEditor extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? preset;
  const _PresetEditor({required this.apiService, this.preset});

  @override
  State<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<_PresetEditor> {
  static const _sample = {
    'title': 'Sample Scouting Config',
    'version': 1,
    'fields': [
      {'id': 'sec_auto', 'label': 'Autonomous', 'type': 'section', 'phase': 'auto'},
      {'id': 'auto_scored', 'label': 'Auto Scored', 'type': 'counter', 'phase': 'auto'},
    ],
    'analytics': [],
  };

  late final _name = TextEditingController(text: jsonStr(widget.preset?['name']));
  late final _json = TextEditingController(text: _initialJson());
  late String _program = jsonStr(widget.preset?['program'], 'FTC');
  late String _type = jsonStr(widget.preset?['configType'], 'match');
  late bool _isDefault = jsonBool(widget.preset?['isDefault']);
  String? _jsonError;
  bool _saving = false;

  String get _id => jsonStr(widget.preset?['id']);

  String _initialJson() {
    final p = widget.preset;
    dynamic doc = _sample;
    if (p != null) {
      try {
        doc = jsonDecode(jsonStr(p['configJson']));
      } catch (_) {
        doc = {'title': p['name'], 'version': 1, 'fields': [], 'analytics': []};
      }
    }
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  @override
  void dispose() {
    _name.dispose();
    _json.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    dynamic parsed;
    try {
      parsed = jsonDecode(_json.text);
    } catch (e) {
      setState(() => _jsonError = 'JSON Error: $e');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _jsonError = 'Preset name is required.');
      return;
    }
    setState(() {
      _jsonError = null;
      _saving = true;
    });
    final dto = {
      'name': _name.text.trim(),
      'program': _program,
      'configType': _type,
      'configJson': const JsonEncoder.withIndent('  ').convert(parsed),
      'isDefault': _isDefault,
    };
    final res = _id.isNotEmpty
        ? await widget.apiService.requestJson('PUT', '/api/admin/default-configs/$_id', body: dto)
        : await widget.apiService.requestJson('POST', '/api/admin/default-configs', body: dto);
    if (!mounted) return;
    setState(() => _saving = false);
    if (reportResult(context, res, action: context.tr('common.save', 'Save'))) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return Scaffold(
      backgroundColor: ObsidianUITheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_id.isNotEmpty ? 'Edit Default Config Preset' : 'Create Default Config Preset'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: Text(context.tr('common.save', 'Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Preset Name')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _program,
                      dropdownColor: surface,
                      decoration: const InputDecoration(labelText: 'Program', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'FTC', child: Text('FTC')),
                        DropdownMenuItem(value: 'FRC', child: Text('FRC')),
                      ],
                      onChanged: (v) => setState(() => _program = v ?? 'FTC'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      dropdownColor: surface,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'match', child: Text('Match')),
                        DropdownMenuItem(value: 'pit', child: Text('Pit')),
                        DropdownMenuItem(value: 'qualitative', child: Text('Qualitative')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'match'),
                    ),
                  ),
                ]),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isDefault,
                  title: const Text('Active default for this program and type'),
                  onChanged: (v) => setState(() => _isDefault = v),
                ),
                TextField(
                  controller: _json,
                  minLines: 12,
                  maxLines: 40,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(labelText: 'Config JSON', errorText: _jsonError, errorMaxLines: 3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
