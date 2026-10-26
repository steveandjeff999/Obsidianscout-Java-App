import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';
import 'alliance_edit_screen.dart';
import '../services/net/adaptive_timer.dart';

/// Scouting alliances with partner teams: create, invite, accept, import data, and pick the active one.
/// Same data as the website's alliances.html; Edit opens [AllianceEditScreen] (alliance-edit.html).
class AlliancesScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const AlliancesScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<AlliancesScreen> createState() => _AlliancesScreenState();
}

class _AlliancesScreenState extends State<AlliancesScreen> {
  static const _liveRefresh = Duration(seconds: 10);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alliances = [];
  List<Map<String, dynamic>> _invites = [];
  Timer? _timer;

  int? get _myTeam => widget.apiService.currentUser?.teamNumber;
  bool get _isAdmin => widget.apiService.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AlliancesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _load(quiet: true);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Polls like the website does, but only while the tab is on screen.
  void _syncTimer() {
    if (widget.isVisible && _timer == null) {
      _timer = AdaptiveTimer(_liveRefresh, (_) => _load(quiet: true));
    } else if (!widget.isVisible) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final api = widget.apiService;
    final results = await Future.wait([
      api.requestJson('GET', '/api/alliances', cacheKey: 'cache_alliances'),
      api.requestJson('GET', '/api/alliances/invites'),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0].success) {
        _alliances = jsonMaps(results[0].data);
        _error = null;
      } else if (!quiet) {
        _error = results[0].message ?? 'Request failed';
      }
      if (results[1].success) _invites = jsonMaps(results[1].data);
      _loading = false;
    });
  }

  Future<void> _run(Future<dynamic> Function() call, String action, {String? success}) async {
    final res = await call();
    if (!mounted) return;
    if (reportResult(context, res, action: action, success: success)) await _load(quiet: true);
  }

  // ------------------------------------------------------------------ actions

  Future<void> _create() async {
    final values = await showAllianceDetailsDialog(context);
    if (values == null || !mounted) return;
    final res = await widget.apiService.requestJson('POST', '/api/alliances', body: values);
    if (!mounted) return;
    if (!reportResult(context, res, action: context.tr('alliances.new_alliance', 'New Alliance'), success: 'Alliance created!')) return;
    final id = jsonStr(jsonMap(res.data)['id']);
    await _load(quiet: true);
    if (id.isNotEmpty && mounted) _openEdit(id);
  }

  Future<void> _openEdit(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AllianceEditScreen(apiService: widget.apiService, allianceId: id),
    ));
    if (mounted) _load(quiet: true);
  }

  Future<void> _invite(String id) async {
    final text = await promptPortedText(context,
        title: context.tr('alliances.invite_team', '+ Invite Team'),
        label: context.tr('alliances.team_number', 'Team Number'),
        keyboardType: TextInputType.number);
    if (text == null || !mounted) return;
    final team = int.tryParse(text.trim());
    if (team == null || team <= 0) {
      ObsidianFeedback.showError(context, message: 'Please enter a valid team number.');
      return;
    }
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$id/invite', body: {'partnerTeamNumber': team}),
        context.tr('alliances.invite_team', 'Invite'),
        success: 'Invite sent to Team $team!');
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('common.delete', 'Delete'),
        message: 'Delete alliance "${a['name']}"? All memberships will be removed and data sharing will stop.',
        destructive: true);
    if (!ok || !mounted) return;
    await _run(() => widget.apiService.requestJson('DELETE', '/api/alliances/${a['id']}'), context.tr('common.delete', 'Delete'),
        success: 'Alliance deleted.');
  }

  Future<void> _removeMember(String id, int team) async {
    final self = team == _myTeam;
    final ok = await confirmPortedAction(context,
        title: self ? context.tr('alliances.leave', 'Leave') : context.tr('alliances.remove_team', 'Remove team'),
        message: self ? 'Leave this alliance? You will no longer see their scouting data.' : 'Remove Team $team from this alliance?',
        destructive: true);
    if (!ok || !mounted) return;
    await _run(() => widget.apiService.requestJson('DELETE', '/api/alliances/$id/members/$team'),
        self ? context.tr('alliances.leave', 'Leave') : context.tr('alliances.remove_team', 'Remove team'),
        success: self ? 'You left the alliance.' : 'Team $team removed.');
  }

  Future<void> _promote(String id, int team) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('alliances.make_admin', 'Make Admin'), message: 'Promote Team $team to alliance admin?');
    if (!ok || !mounted) return;
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$id/members/$team/promote'),
        context.tr('alliances.make_admin', 'Make Admin'),
        success: 'Team $team promoted to admin.');
  }

  Future<void> _toggleActive(String id, bool active) async {
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$id/toggle-active', body: {'active': active}),
        context.tr('alliances.active_badge', 'Active'),
        success: active ? 'Alliance activated.' : 'Alliance deactivated.');
  }

  Future<void> _respond(String id, bool accept) async {
    await _run(() => widget.apiService.requestJson('POST', '/api/alliances/$id/respond', body: {'accept': accept}),
        accept ? context.tr('alliances.accept', 'Accept') : context.tr('alliances.decline', 'Decline'),
        success: accept ? 'You joined the alliance! Data is now shared.' : 'Invite declined.');
  }

  Future<void> _import(String id) async {
    final res = await widget.apiService.requestJson('GET', '/api/alliances/import-sources');
    if (!mounted) return;
    if (!res.success) {
      reportResult(context, res, action: context.tr('alliances.import_data', 'Import Data'));
      return;
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ImportDialog(sources: jsonMaps(res.data)),
    );
    if (body == null || !mounted) return;
    final out = await widget.apiService.requestJson('POST', '/api/alliances/$id/import', body: body);
    if (!mounted) return;
    final r = jsonMap(out.data);
    final m = jsonInt(r['importedMatchScouting']) ?? 0;
    final p = jsonInt(r['importedPitScouting']) ?? 0;
    final q = jsonInt(r['importedQualitativeScouting']) ?? 0;
    final skipped = jsonInt(r['skippedDuplicates']) ?? 0;
    final skippedText = skipped > 0 ? ' Skipped $skipped duplicate${skipped == 1 ? '' : 's'}.' : '';
    if (reportResult(context, out,
        action: context.tr('alliances.import_data', 'Import Data'),
        success: 'Imported ${m + p + q} entries (match $m, pit $p, qual $q).$skippedText')) {
      _load(quiet: true);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final count = _alliances.length;
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('alliances.alliances', 'Alliances'),
          subtitle: context.tr('alliances.create_alliances_with_partner_',
              'Create alliances with partner teams to share scouting data in real time across all data types.'),
          actions: [
            if (_isAdmin)
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.tr('alliances.new_alliance', '+ New Alliance').replaceFirst('+ ', '')),
              ),
          ],
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '${context.tr('alliances.how_data_sharing_works', 'How data sharing works:')} ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: context.tr('alliances.sharing_explanation',
                      'Once a team accepts your invite, their match scouting, pit scouting, and qualitative scouting data will automatically appear in your Analytics, Graphs, and all data views — in real time, no exports needed.')),
            ]),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: ObsidianUITheme.getSecondaryTextColor(context)),
          ),
        ),
        if (_invites.isNotEmpty) _buildInvites(context),
        if (_loading)
          const PortedLoading()
        else if (_error != null)
          PortedError(message: 'Failed to load alliances: $_error', onRetry: _load)
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(children: [
              Text(context.tr('alliances.my_alliances', 'My Alliances'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context))),
              const SizedBox(width: 8),
              PortedBadge(count == 1
                  ? context.tr('alliances.alliance_count_singular', '1 alliance')
                  : context.tr('alliances.alliance_count_plural', '{count} alliances').replaceAll('{count}', '$count')),
            ]),
          ),
          if (_alliances.isEmpty)
            PortedNotice(
              context.tr('alliances.no_alliances', 'No alliances yet. Create one and invite partner teams to start sharing data.'),
              icon: Icons.handshake_rounded,
            )
          else
            for (final a in _alliances) _buildAllianceCard(context, a),
        ],
      ],
    );
  }

  Widget _buildInvites(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return PortedSection(
      icon: Icons.mark_email_unread_rounded,
      title: 'Pending Invites',
      child: Column(
        children: [
          for (final inv in _invites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(jsonStr(inv['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          [
                            context.tr('alliances.created_by_team', 'Created by Team {team}').replaceAll('{team}', '${inv['ownerTeamNumber']}'),
                            if (jsonStr(inv['eventKey']).isNotEmpty) jsonStr(inv['eventKey']),
                            context.tr('alliances.members_count', '{count} member(s)').replaceAll('{count}', '${jsonList(inv['members']).length}'),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                      onPressed: () => _respond(jsonStr(inv['id']), true),
                      child: Text(context.tr('alliances.accept', 'Accept'))),
                  TextButton(
                    onPressed: () => _respond(jsonStr(inv['id']), false),
                    style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                    child: Text(context.tr('alliances.decline', 'Decline')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllianceCard(BuildContext context, Map<String, dynamic> a) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final id = jsonStr(a['id']);
    final members = jsonMaps(a['members']);
    final mine = members.where((m) => jsonInt(m['teamNumber']) == _myTeam).firstOrNull;
    final canManage = _isAdmin && mine?['status'] == 'ADMIN';
    final isMember = mine != null && (mine['status'] == 'ADMIN' || mine['status'] == 'ACCEPTED');
    final isActive = mine != null && jsonBool(mine['active']);
    final admins = members.where((m) => m['status'] == 'ADMIN').map((m) => m['teamNumber']).toList();
    final adminCount = admins.length;
    final validation = jsonMap(a['validation']);
    final issues = jsonMaps(validation['issues']);
    final misconfigured = isActive && jsonBool(validation['isMisconfigured']);

    return ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Container(
        decoration: isActive
            ? BoxDecoration(border: Border(left: BorderSide(color: ObsidianUITheme.primaryAccent, width: 3)))
            : null,
        padding: isActive ? const EdgeInsets.only(left: 10) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(jsonStr(a['name']), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary)),
                if (isActive) PortedBadge(context.tr('alliances.active_badge', 'Active'), color: ObsidianUITheme.successGreen),
                if (misconfigured) PortedBadge('Needs Setup (${issues.length})', color: ObsidianUITheme.warningOrange),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (jsonStr(a['eventKey']).isNotEmpty) jsonStr(a['eventKey']),
                adminCount > 1
                    ? context.tr('alliances.admins', 'Admins: Teams {teams}').replaceAll('{teams}', admins.join(', '))
                    : context.tr('alliances.admin', 'Admin: Team {team}')
                        .replaceAll('{team}', '${admins.isNotEmpty ? admins.first : a['ownerTeamNumber']}'),
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
            if (misconfigured) ...[
              const SizedBox(height: 8),
              Text(
                'Configuration Incomplete: ${issues.map((i) => i['category']).join(', ')}. Scouting forms and schedule syncing are falling back to local team settings.',
                style: const TextStyle(fontSize: 12, color: ObsidianUITheme.warningOrange),
              ),
            ],
            if (jsonStr(a['notes']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(jsonStr(a['notes']), style: TextStyle(fontSize: 13, color: muted, height: 1.4)),
            ],
            const SizedBox(height: 10),
            Text(context.tr('alliances.members', 'Members').toUpperCase(),
                style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 6),
            if (members.isEmpty)
              Text(context.tr('alliances.no_members', 'No members yet'), style: TextStyle(fontSize: 13, color: muted))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final m in members) _memberChip(context, id, m, members, canManage)],
              ),
            if (isMember)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: isActive,
                title: Text(context.tr('alliances.active_label', 'Active Alliance (use config and share data)'),
                    style: TextStyle(fontSize: 12.5, color: muted)),
                onChanged: (v) => _toggleActive(id, v),
              ),
            if (canManage || (mine != null && mine['status'] == 'ACCEPTED')) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (canManage) ...[
                    OutlinedButton(onPressed: () => _openEdit(id), child: Text(context.tr('common.edit', 'Edit'))),
                    OutlinedButton(
                        onPressed: () => _invite(id),
                        child: Text(context.tr('alliances.invite_team', '+ Invite Team'))),
                    OutlinedButton(
                        onPressed: () => _import(id),
                        child: Text(context.tr('alliances.import_data', 'Import Data'))),
                    TextButton(
                      onPressed: () => _delete(a),
                      style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                      child: Text(context.tr('common.delete', 'Delete')),
                    ),
                  ] else
                    TextButton(
                      onPressed: () => _removeMember(id, _myTeam ?? 0),
                      style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                      child: Text(context.tr('alliances.leave', 'Leave')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberChip(BuildContext context, String allianceId, Map<String, dynamic> m, List<Map<String, dynamic>> all, bool canManage) {
    final team = jsonInt(m['teamNumber']) ?? 0;
    final status = jsonStr(m['status']);
    final cls = status.toLowerCase();
    final label = context.tr('alliances.invite_badge_$cls', status.isEmpty ? '' : status[0] + status.substring(1).toLowerCase());
    final self = team == _myTeam;
    final canLeave = self && (status != 'ADMIN' || all.where((x) => x['status'] == 'ADMIN').length > 1);
    final canRemove = (canManage && !self) || canLeave;
    final canPromote = canManage && status == 'ACCEPTED';
    final color = switch (status) {
      'ADMIN' => ObsidianUITheme.primaryAccent,
      'ACCEPTED' => ObsidianUITheme.successGreen,
      'PENDING' => ObsidianUITheme.warningOrange,
      _ => ObsidianUITheme.getSecondaryTextColor(context),
    };
    return InputChip(
      label: Text('Team $team ($label)${jsonBool(m['disabled']) ? ' · ${context.tr('alliances.invite_badge_disabled', 'Disabled')}' : ''}',
          style: TextStyle(fontSize: 12, color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
      onPressed: canPromote ? () => _promote(allianceId, team) : null,
      avatar: canPromote ? Icon(Icons.upgrade_rounded, size: 16, color: color) : null,
      tooltip: canPromote ? context.tr('alliances.make_admin', 'Make Admin') : null,
      onDeleted: canRemove ? () => _removeMember(allianceId, team) : null,
      deleteButtonTooltipMessage: context.tr('alliances.remove_team', 'Remove team'),
    );
  }
}

/// Name, year, event code and notes for a new or edited alliance; null when cancelled.
Future<Map<String, dynamic>?> showAllianceDetailsDialog(BuildContext context, {Map<String, dynamic>? initial}) {
  return showDialog<Map<String, dynamic>>(context: context, builder: (_) => _AllianceDetailsDialog(initial: initial));
}

class _AllianceDetailsDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _AllianceDetailsDialog({this.initial});

  @override
  State<_AllianceDetailsDialog> createState() => _AllianceDetailsDialogState();
}

class _AllianceDetailsDialogState extends State<_AllianceDetailsDialog> {
  late final _name = TextEditingController(text: jsonStr(widget.initial?['name']));
  late final _year = TextEditingController(text: jsonStr(widget.initial?['year']));
  late final _code = TextEditingController(text: jsonStr(widget.initial?['eventCode']));
  late final _notes = TextEditingController(text: jsonStr(widget.initial?['notes']));
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _year, _code, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      title: Text(widget.initial == null ? 'New Alliance' : 'Edit Alliance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: context.tr('alliances.alliance_name', 'Alliance Name *'),
                hintText: context.tr('alliances.placeholder_eg_thunder_alliance', 'e.g. Thunder Alliance'),
                errorText: _error,
              ),
            ),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('alliances.event_year_optional', 'Event Year (optional)'),
                hintText: context.tr('alliance-edit.placeholder_eg_2026', 'e.g. 2026'),
              ),
            ),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: context.tr('alliances.event_code_optional', 'Event Code (optional)'),
                hintText: context.tr('alliance-edit.placeholder_eg_okok', 'e.g. okok'),
              ),
            ),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr('alliances.notes_optional', 'Notes (optional)'),
                hintText: context.tr('alliances.placeholder_any_notes_about_this_alliance', 'Any notes about this alliance…'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel', 'Cancel'))),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Alliance name is required.');
              return;
            }
            String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
            Navigator.pop(context, {
              'name': name,
              'year': int.tryParse(_year.text.trim()),
              'eventCode': orNull(_code.text),
              'notes': orNull(_notes.text),
            });
          },
          child: Text(widget.initial == null ? 'Create Alliance' : 'Save Changes'),
        ),
      ],
    );
  }
}

/// Picks a team and event whose scouting data to copy into the alliance.
class _ImportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> sources;
  const _ImportDialog({required this.sources});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  static const _noEvent = '__NO_EVENT__';
  int? _team;
  String? _event;
  bool _match = true;
  bool _pit = true;
  bool _qual = true;

  List<Map<String, dynamic>> get _forTeam => widget.sources.where((s) => jsonInt(s['teamNumber']) == _team).toList()
    ..sort((a, b) => jsonStr(a['eventKey']).compareTo(jsonStr(b['eventKey'])));

  @override
  Widget build(BuildContext context) {
    final teams = widget.sources.map((s) => jsonInt(s['teamNumber'])).whereType<int>().toSet().toList()..sort();
    final sources = _forTeam;
    final eventValue = _event == _noEvent ? '' : _event;
    final source = sources.where((s) => jsonStr(s['eventKey']) == eventValue).firstOrNull;
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return AlertDialog(
      backgroundColor: surface,
      title: Text(context.tr('alliances.import_data', 'Import Data')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _team,
              dropdownColor: surface,
              decoration: const InputDecoration(labelText: 'Source team'),
              hint: Text(teams.isEmpty ? 'No scouting data found' : 'Select a team...'),
              items: [for (final t in teams) DropdownMenuItem(value: t, child: Text('Team $t'))],
              onChanged: (v) => setState(() {
                _team = v;
                final first = _forTeam.firstOrNull;
                _event = first == null ? null : (jsonStr(first['eventKey']).isEmpty ? _noEvent : jsonStr(first['eventKey']));
              }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _event,
              dropdownColor: surface,
              decoration: const InputDecoration(labelText: 'Event'),
              hint: Text(_team == null ? 'Select a team first' : 'No events found'),
              items: [
                for (final s in sources)
                  DropdownMenuItem(
                    value: jsonStr(s['eventKey']).isEmpty ? _noEvent : jsonStr(s['eventKey']),
                    child: Text(
                      '${jsonStr(s['eventKey']).isEmpty ? 'No event key' : s['eventKey']} - '
                      '${(jsonInt(s['matchScoutingCount']) ?? 0) + (jsonInt(s['pitScoutingCount']) ?? 0) + (jsonInt(s['qualitativeScoutingCount']) ?? 0)} entries',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _event = v),
            ),
            if (source != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                PortedBadge('Match ${source['matchScoutingCount'] ?? 0}'),
                PortedBadge('Pit ${source['pitScoutingCount'] ?? 0}'),
                PortedBadge('Qual ${source['qualitativeScoutingCount'] ?? 0}'),
              ]),
            ],
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _match,
                title: const Text('Match scouting'),
                onChanged: (v) => setState(() => _match = v ?? false)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _pit,
                title: const Text('Pit scouting'),
                onChanged: (v) => setState(() => _pit = v ?? false)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _qual,
                title: const Text('Qualitative scouting'),
                onChanged: (v) => setState(() => _qual = v ?? false)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel', 'Cancel'))),
        FilledButton(
          onPressed: _team == null || !(_match || _pit || _qual)
              ? null
              : () => Navigator.pop(context, {
                    'sourceTeamNumber': _team,
                    'eventKey': _event,
                    'includeMatchScouting': _match,
                    'includePitScouting': _pit,
                    'includeQualitativeScouting': _qual,
                  }),
          child: Text(context.tr('alliances.import_data', 'Import Data')),
        ),
      ],
    );
  }
}
