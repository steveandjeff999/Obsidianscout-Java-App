import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// One alliance: details, members, the shared scouting forms, and the entries partner teams have shared.
/// Same data as the website's alliance-edit.html. The shared forms are edited as JSON here; the website's
/// visual builder and live co-editing stay on the website.
class AllianceEditScreen extends StatefulWidget {
  final ApiService apiService;
  final String allianceId;

  const AllianceEditScreen({super.key, required this.apiService, required this.allianceId});

  @override
  State<AllianceEditScreen> createState() => _AllianceEditScreenState();
}

class _AllianceEditScreenState extends State<AllianceEditScreen> with SingleTickerProviderStateMixin {
  static const _kinds = ['game', 'pit', 'qual'];
  static const _localConfigPaths = {'game': '/api/config', 'pit': '/api/pit-config', 'qual': '/api/qual-config'};
  static const _dataPaths = {'match': '/api/scouting', 'pit': '/api/pit-scouting', 'qual': '/api/qual-scouting'};

  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  Map<String, dynamic> _alliance = {};

  final _name = TextEditingController();
  final _year = TextEditingController();
  final _code = TextEditingController();
  final _notes = TextEditingController();

  String _configKind = 'game';
  final _configText = TextEditingController();
  bool _configLoading = false;
  String? _configError;

  String _dataKind = 'match';
  bool _dataLoading = false;
  bool _dataLoaded = false;
  List<Map<String, dynamic>> _entries = [];
  String _search = '';

  String get _id => widget.allianceId;
  int? get _myTeam => widget.apiService.currentUser?.teamNumber;

  Map<String, dynamic>? get _mine =>
      jsonMaps(_alliance['members']).where((m) => jsonInt(m['teamNumber']) == _myTeam).firstOrNull;

  bool get _canEdit => _mine?['status'] == 'ADMIN' || widget.apiService.isAdmin;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_dataLoaded && !_tabs.indexIsChanging) _loadData();
    });
    _load().then((_) => _loadConfig());
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_name, _year, _code, _notes, _configText]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await widget.apiService.requestJson('GET', '/api/alliances/$_id');
    if (!mounted) return;
    if (!res.success) {
      reportResult(context, res, action: 'Failed to load alliance data');
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _alliance = jsonMap(res.data);
      _name.text = jsonStr(_alliance['name']);
      _year.text = jsonStr(_alliance['year']);
      _code.text = jsonStr(_alliance['eventCode']);
      _notes.text = jsonStr(_alliance['notes']);
      _loading = false;
    });
  }

  Future<void> _run(Future<dynamic> Function() call, String action, {String? success}) async {
    final res = await call();
    if (!mounted) return;
    if (reportResult(context, res, action: action, success: success)) await _load();
  }

  Future<void> _saveDetails() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ObsidianFeedback.showError(context, message: 'Alliance name is required.');
      return;
    }
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
    await _run(
      () => widget.apiService.requestJson('PUT', '/api/alliances/$_id', body: {
        'name': name,
        'year': int.tryParse(_year.text.trim()),
        'eventCode': orNull(_code.text),
        'notes': orNull(_notes.text),
      }),
      context.tr('alliance-edit.save_details', 'Save Details'),
      success: 'Alliance updated!',
    );
  }

  Future<void> _invite() async {
    final text = await promptPortedText(context,
        title: context.tr('alliance-edit.invite_partner_team', 'Invite Partner Team'),
        label: context.tr('alliances.team_number', 'Team Number'),
        keyboardType: TextInputType.number);
    if (text == null || !mounted) return;
    final team = int.tryParse(text.trim());
    if (team == null || team <= 0) {
      ObsidianFeedback.showError(context, message: 'Please enter a valid team number.');
      return;
    }
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$_id/invite', body: {'partnerTeamNumber': team}),
        context.tr('alliance-edit.invite', 'Invite'),
        success: 'Invite sent to Team $team!');
  }

  Future<void> _removeMember(int team) async {
    final self = team == _myTeam;
    final ok = await confirmPortedAction(context,
        title: context.tr('alliances.remove_team', 'Remove team'),
        message: self ? 'Leave this alliance? You will no longer see their scouting data.' : 'Remove Team $team from this alliance?',
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.requestJson('DELETE', '/api/alliances/$_id/members/$team');
    if (!mounted) return;
    if (reportResult(context, res, action: context.tr('alliances.remove_team', 'Remove team'))) {
      if (self) {
        Navigator.of(context).maybePop();
      } else {
        _load();
      }
    }
  }

  Future<void> _promote(int team) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('alliances.make_admin', 'Make Admin'), message: 'Promote Team $team to alliance admin?');
    if (!ok || !mounted) return;
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$_id/members/$team/promote'),
        context.tr('alliances.make_admin', 'Make Admin'),
        success: 'Team $team promoted to admin.');
  }

  // ------------------------------------------------------------------ shared configs

  Future<void> _loadConfig() async {
    setState(() {
      _configLoading = true;
      _configError = null;
    });
    final res = await widget.apiService.requestJson('GET', '/api/alliances/$_id/config/$_configKind');
    if (!mounted) return;
    setState(() {
      _configLoading = false;
      _configText.text = res.success ? const JsonEncoder.withIndent('  ').convert(res.data ?? {}) : '';
      if (!res.success) _configError = res.message;
    });
  }

  Future<void> _saveConfig() async {
    dynamic doc;
    try {
      doc = jsonDecode(_configText.text);
    } catch (e) {
      setState(() => _configError = 'Invalid JSON: $e');
      return;
    }
    if (doc is! Map) {
      setState(() => _configError = 'The config must be a JSON object.');
      return;
    }
    setState(() => _configError = null);
    final res = await widget.apiService.requestJson('PUT', '/api/alliances/$_id/config/$_configKind', body: doc);
    if (!mounted) return;
    if (reportResult(context, res, action: context.tr('alliance-edit.scouting_config_json', 'Scouting config JSON'), success: 'Saved')) {
      _load();
    }
  }

  /// Copies this team's own form for the selected kind into the editor (the website's Import Team Config).
  Future<void> _importLocalConfig() async {
    final res = await widget.apiService.requestJson('GET', _localConfigPaths[_configKind]!, query: {'local': 'true'});
    if (!mounted) return;
    if (!res.success) {
      reportResult(context, res, action: context.tr('alliance-edit.import_team_config', 'Import Team Config'));
      return;
    }
    final doc = jsonMap(res.data);
    doc.putIfAbsent('fields', () => []);
    doc.putIfAbsent('analytics', () => []);
    setState(() => _configText.text = const JsonEncoder.withIndent('  ').convert(doc));
    ObsidianFeedback.showSuccess(context, message: 'Imported local team configurations! Save to share it with the alliance.');
  }

  // ------------------------------------------------------------------ shared data

  Future<void> _loadData() async {
    setState(() => _dataLoading = true);
    final res = await widget.apiService
        .requestJson('GET', _dataPaths[_dataKind]!, query: {'includePrescout': 'true', 'all': 'true'});
    if (!mounted) return;
    final members = jsonMaps(_alliance['members']).map((m) => jsonInt(m['teamNumber'])).toSet();
    final eventKey = jsonStr(_alliance['eventKey']);
    final all = jsonMaps(res.data);
    setState(() {
      _entries = all
          .where((e) =>
              members.contains(jsonInt(e['ownerTeamNumber'])) || (eventKey.isNotEmpty && e['eventKey'] == eventKey))
          .toList();
      _dataLoading = false;
      _dataLoaded = true;
    });
  }

  String get _entryType => _dataKind == 'match' ? 'match' : _dataKind;

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final type = _dataKind == 'match' ? 'Match' : (_dataKind == 'pit' ? 'Pit' : 'Qualitative');
    final target = entry['targetTeamNumber'] != null ? 'for Team ${entry['targetTeamNumber']}' : '';
    final ok = await confirmPortedAction(context,
        title: context.tr('alliance-edit.delete_entry', 'Delete Entry'),
        message: 'Are you sure you want to delete this shared $type entry $target?',
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.deleteScoutingEntry(jsonStr(entry['id']), type: _entryType);
    if (!mounted) return;
    if (reportResult(context, res, action: context.tr('alliance-edit.delete_entry', 'Delete Entry'), success: 'Entry deleted successfully')) {
      _loadData();
    }
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final data = jsonMap(entry['data']);
    final text = await promptPortedText(context,
        title: '${context.tr('alliance-edit.entry_details', 'Entry Details')} · Team ${entry['targetTeamNumber']}',
        label: 'data (JSON)',
        initial: const JsonEncoder.withIndent('  ').convert(data),
        multiline: true);
    if (text == null || !mounted) return;
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (e) {
      ObsidianFeedback.showError(context, message: 'Invalid JSON: $e');
      return;
    }
    if (parsed is! Map) {
      ObsidianFeedback.showError(context, message: 'Entry data must be a JSON object.');
      return;
    }
    // Keep the entry's event, team and match like the website does.
    final payload = Map<String, dynamic>.from(parsed)
      ..['eventKey'] = entry['eventKey']
      ..['targetTeamNumber'] = entry['targetTeamNumber'];
    if (_dataKind != 'pit') {
      payload['matchKey'] = entry['matchKey'];
      payload['matchNumber'] = entry['matchNumber'];
    }
    final res = await widget.apiService.updateScoutingEntry(jsonStr(entry['id']), payload, type: _entryType);
    if (!mounted) return;
    if (reportResult(context, res,
        action: context.tr('alliance-edit.save_entry_changes', 'Save Entry Changes'), success: 'Entry updated successfully')) {
      _loadData();
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return Scaffold(
      backgroundColor: ObsidianUITheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_loading
            ? context.tr('alliance-edit.edit_alliance', 'Edit Alliance')
            : '${context.tr('alliance-edit.edit_alliance', 'Edit Alliance')}: ${_alliance['name']}'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: ObsidianUITheme.primaryAccent,
          unselectedLabelColor: muted,
          indicatorColor: ObsidianUITheme.primaryAccent,
          tabs: [
            Tab(text: context.tr('alliance-edit.manage_alliance', 'Manage Alliance')),
            Tab(text: context.tr('alliance-edit.shared_alliance_data', 'Shared Alliance Data')),
          ],
        ),
      ),
      body: _loading
          ? const PortedLoading()
          : TabBarView(controller: _tabs, children: [_buildManage(context), _buildData(context)]),
    );
  }

  Widget _buildManage(BuildContext context) {
    final validation = jsonMap(_alliance['validation']);
    final issues = jsonMaps(validation['issues']);
    final mine = _mine;
    final members = jsonMaps(_alliance['members']);
    final adminCount = members.where((m) => m['status'] == 'ADMIN').length;
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: false,
      children: [
        if (jsonBool(validation['isMisconfigured']) && issues.isNotEmpty)
          PortedSection(
            icon: Icons.warning_amber_rounded,
            title: 'Alliance Configuration Incomplete (${issues.length} issue${issues.length == 1 ? '' : 's'})',
            subtitle:
                'This alliance is active or missing required setup. Because of this, scouting forms and match schedules are automatically falling back to individual team local settings.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < issues.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${i + 1}. ${issues[i]['category']} — ${issues[i]['location']}\n',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: ObsidianUITheme.warningOrange)),
                        TextSpan(text: 'Error: ${issues[i]['error']}\n'),
                        TextSpan(text: 'Fix: ${issues[i]['fixAction']}\n'),
                        TextSpan(text: 'Impact: ${issues[i]['impact']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                      ]),
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        PortedSection(
          title: context.tr('alliance-edit.alliance_details', 'Alliance Details'),
          subtitle: context.tr('alliance-edit.tying_this_alliance_to_a_speci',
              'Tying this alliance to a specific event filters synced data for this event. Event key is year + code (e.g. 2026 + okok → 2026okok).'),
          actions: [
            if (_canEdit)
              FilledButton(onPressed: _saveDetails, child: Text(context.tr('alliance-edit.save_details', 'Save Details'))),
          ],
          child: Column(
            children: [
              TextField(
                  controller: _name,
                  enabled: _canEdit,
                  decoration: InputDecoration(labelText: context.tr('alliance-edit.alliance_name', 'Alliance Name'))),
              TextField(
                  controller: _year,
                  enabled: _canEdit,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.tr('alliance-edit.event_year_optional', 'Event Year (Optional)'))),
              TextField(
                  controller: _code,
                  enabled: _canEdit,
                  decoration: InputDecoration(labelText: context.tr('alliance-edit.event_code_optional', 'Event Code (Optional)'))),
              TextField(
                  controller: _notes,
                  enabled: _canEdit,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: context.tr('alliance-edit.notes', 'Notes'))),
              if (mine != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: jsonBool(mine['active']),
                  title: Text(context.tr('alliance-edit.active_alliance', 'Active Alliance')),
                  subtitle: Text(
                    context.tr('alliance-edit.only_one_alliance_can_be_activ',
                        'Only one alliance can be active at a time. Activating this alliance uses its shared configurations and shares scouting data.'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => _run(
                    () => widget.apiService.requestJson('POST', '/api/alliances/$_id/toggle-active', body: {'active': v}),
                    context.tr('alliance-edit.active_alliance', 'Active Alliance'),
                    success: v ? 'Alliance activated!' : 'Alliance deactivated.',
                  ),
                ),
            ],
          ),
        ),
        PortedSection(
          title: context.tr('alliance-edit.alliance_members', 'Alliance Members'),
          actions: [
            if (_canEdit)
              OutlinedButton.icon(
                onPressed: _invite,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(context.tr('alliance-edit.invite_partner_team', 'Invite Partner Team')),
              ),
          ],
          child: Column(
            children: [
              for (final m in members)
                Builder(builder: (context) {
                  final team = jsonInt(m['teamNumber']) ?? 0;
                  final status = jsonStr(m['status']);
                  final label = status.isEmpty ? '' : status[0] + status.substring(1).toLowerCase();
                  final self = team == _myTeam;
                  final canRemove = (_canEdit && !self) || (self && (status != 'ADMIN' || adminCount > 1));
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(status == 'ADMIN' ? Icons.shield_rounded : Icons.groups_rounded,
                        color: status == 'ADMIN' ? ObsidianUITheme.primaryAccent : null),
                    title: Text('Team $team'),
                    subtitle: Text('$label (${jsonBool(m['active']) ? 'Active' : 'Inactive'})'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_canEdit && status == 'ACCEPTED')
                          TextButton(onPressed: () => _promote(team), child: Text(context.tr('alliances.make_admin', 'Make Admin'))),
                        if (canRemove)
                          IconButton(
                            tooltip: context.tr('alliances.remove_team', 'Remove team'),
                            onPressed: () => _removeMember(team),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        _buildConfigEditor(context),
      ],
    );
  }

  Widget _buildConfigEditor(BuildContext context) {
    final labels = {
      'game': context.tr('alliance-edit.game_form', 'Game form'),
      'pit': context.tr('alliance-edit.pit_form', 'Pit form'),
      'qual': context.tr('alliance-edit.qualitative_form', 'Qualitative form'),
    };
    return PortedSection(
      title: context.tr('alliance-edit.shared_scouting_configurations', 'Shared Scouting Configurations'),
      subtitle: context.tr('alliance-edit.directly_edit_the_scouting_for',
          'Directly edit the scouting form JSON. Auto-saves and syncs in real time on valid JSON input.')
          .replaceFirst(' Auto-saves and syncs in real time on valid JSON input.', ''),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: [for (final k in _kinds) ButtonSegment(value: k, label: Text(labels[k]!))],
            selected: {_configKind},
            onSelectionChanged: (s) {
              setState(() => _configKind = s.first);
              _loadConfig();
            },
          ),
          const SizedBox(height: 10),
          if (_configLoading)
            const PortedLoading()
          else
            TextField(
              controller: _configText,
              readOnly: !_canEdit,
              minLines: 8,
              maxLines: 20,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText: context.tr('alliance-edit.scouting_config_json', 'Scouting config JSON'),
                errorText: _configError,
                errorMaxLines: 3,
              ),
            ),
          const SizedBox(height: 10),
          if (_canEdit)
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton(onPressed: _configLoading ? null : _saveConfig, child: Text(context.tr('common.save', 'Save'))),
              OutlinedButton(
                onPressed: _configLoading ? null : _importLocalConfig,
                child: Text(context.tr('alliance-edit.import_team_config', 'Import Team Config')),
              ),
            ])
          else
            Text('Alliance Config (ReadOnly)', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
        ],
      ),
    );
  }

  Widget _buildData(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final q = _search.trim().toLowerCase();
    final shown = _entries.where((e) {
      if (q.isEmpty) return true;
      return '${e['targetTeamNumber'] ?? ''}'.contains(q) ||
          '${e['ownerTeamNumber'] ?? ''}'.contains(q) ||
          '${e['matchNumber'] ?? ''}'.contains(q);
    }).toList();
    final adminHere = _mine?['status'] == 'ADMIN';
    return PortedPageList(
      onRefresh: _loadData,
      isBarsVisible: false,
      children: [
        PortedSection(
          title: context.tr('alliance-edit.shared_alliance_data', 'Shared Alliance Data'),
          subtitle: context.tr('alliance-edit.view_edit_or_delete_shared_sco',
              'View, edit, or delete shared scouting entries submitted by alliance partner teams. Alliance admins can edit any entry. Regular member teams can edit their own entries.'),
          child: Column(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'match', label: Text('Match')),
                  ButtonSegment(value: 'pit', label: Text('Pit')),
                  ButtonSegment(value: 'qual', label: Text('Qual')),
                ],
                selected: {_dataKind},
                onSelectionChanged: (s) {
                  setState(() => _dataKind = s.first);
                  _loadData();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    isDense: true, prefixIcon: Icon(Icons.search_rounded, size: 18), hintText: 'Team or match number'),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),
        if (_dataLoading)
          const PortedLoading()
        else if (shown.isEmpty)
          const PortedNotice('No entries found')
        else
          for (final e in shown)
            ObsidianGlassCard(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Team ${e['targetTeamNumber']}${_dataKind != 'pit' ? ' - Match ${e['matchNumber'] ?? e['matchKey'] ?? '?'}' : ''}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: primary),
                        ),
                      ),
                      if (jsonBool(e['hasDiscrepancy']))
                        Tooltip(
                          message:
                              'Discrepancy detected between partner teams: ${jsonList(e['conflictingTeams']).join(', ')}',
                          child: const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 18),
                        ),
                    ],
                  ),
                  Text('Owner: Team ${e['ownerTeamNumber']} · ${fmtDateTime(context, e['createdAt'])}',
                      style: TextStyle(fontSize: 11.5, color: muted)),
                  const SizedBox(height: 6),
                  for (final kv in jsonMap(e['data']).entries.take(12))
                    PortedKeyValue(kv.key, kv.value is Map || kv.value is List ? jsonEncode(kv.value) : '${kv.value}'),
                  if (adminHere || widget.apiService.isAdmin || jsonInt(e['ownerTeamNumber']) == _myTeam)
                    Wrap(spacing: 8, children: [
                      TextButton(onPressed: () => _editEntry(e), child: Text(context.tr('common.edit', 'Edit'))),
                      TextButton(
                        onPressed: () => _deleteEntry(e),
                        style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                        child: Text(context.tr('alliance-edit.delete_entry', 'Delete Entry')),
                      ),
                    ]),
                ],
              ),
            ),
      ],
    );
  }
}
