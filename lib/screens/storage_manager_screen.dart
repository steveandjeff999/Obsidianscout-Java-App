import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Database footprint, API event caches, per-team data use, and pruning (superadmins).
/// Same data as the website's storage-manager.html (its local AI models panel stays on the website).
class StorageManagerScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const StorageManagerScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends State<StorageManagerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _teams = [];

  String _eventSearch = '';
  String? _eventYear;
  String _teamSearch = '';
  String _teamProgram = '';
  final _keepRevisions = TextEditingController(text: '10');
  final _chatDays = TextEditingController(text: '90');
  String _errorScope = 'resolved';
  final Set<String> _busy = {};

  bool get _isSuper => widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN';

  @override
  void initState() {
    super.initState();
    if (_isSuper) _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _keepRevisions.dispose();
    _chatDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = widget.apiService;
    final r = await Future.wait([
      api.requestJson('GET', '/api/admin/storage/overview'),
      api.requestJson('GET', '/api/admin/storage/events'),
      api.requestJson('GET', '/api/admin/storage/teams'),
    ]);
    if (!mounted) return;
    if (!r[0].success) reportResult(context, r[0], action: 'Failed to load storage data');
    setState(() {
      _overview = jsonMap(r[0].data);
      _events = jsonMaps(r[1].data);
      _teams = jsonMaps(r[2].data);
      _loading = false;
    });
  }

  Future<void> _post(String key, String path, Map<String, dynamic> body, String action) async {
    setState(() => _busy.add(key));
    final res = await widget.apiService.requestJson('POST', path, body: body);
    if (!mounted) return;
    setState(() => _busy.remove(key));
    final data = jsonMap(res.data);
    final failed = data['success'] == false;
    if (failed) {
      ObsidianFeedback.showError(context, message: jsonStr(data['message'], 'Request failed'));
      return;
    }
    if (reportResult(context, res, action: action, success: jsonStr(data['message']).isEmpty ? null : jsonStr(data['message']))) {
      _load();
    }
  }

  Future<void> _safe(String key, String title, String message, String path, Map<String, dynamic> body) async {
    final ok = await confirmPortedAction(context, title: title, message: message);
    if (ok && mounted) await _post(key, path, body, title);
  }

  /// Destructive deletes ask the user to type [expected] first, like the website's danger modal.
  Future<void> _danger(String key, String title, String message, String expected, String path, Map<String, dynamic> body) async {
    final typed = await promptPortedText(context, title: title, label: '$message\n\nType "$expected" to confirm');
    if (typed == null || !mounted) return;
    if (typed.trim() != expected) {
      ObsidianFeedback.showError(context, message: 'Confirmation text did not match.');
      return;
    }
    await _post(key, path, body, title);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSuper) {
      return PortedLocked(
        title: context.tr('storage.locked_title', 'Superadmin Access Required'),
        message: context.tr('storage.locked_notice',
            'You must be logged in as a Superadmin (Site Admin) to access Site Storage Management.'),
      );
    }
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: ObsidianUITheme.primaryAccent,
          unselectedLabelColor: muted,
          indicatorColor: ObsidianUITheme.primaryAccent,
          tabs: [
            Tab(text: context.tr('storage.tab_events', 'API Event Caches')),
            Tab(text: context.tr('storage.tab_teams', 'Data Usage by Scouting Team')),
            Tab(text: context.tr('storage.tab_maintenance', 'Pruning & Maintenance')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _page([_buildOverview(context), if (_loading) const PortedLoading() else ..._buildEvents(context)]),
              _page([if (_loading) const PortedLoading() else ..._buildTeams(context)]),
              _page(_buildMaintenance(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _page(List<Widget> children) => PortedPageList(onRefresh: _load, isBarsVisible: widget.isBarsVisible, children: children);

  Widget _buildOverview(BuildContext context) {
    final o = _overview;
    var engine = jsonStr(o['databaseType'], 'sqlite').toUpperCase();
    if (jsonBool(o['isCockroach'])) engine = 'COCKROACHDB';
    final chatAccountBytes = (jsonDouble(o['chatBytes']) ?? 0) + (jsonDouble(o['accountsBytes']) ?? 0);
    final chatAccountRecords = (jsonInt(o['chatRecords']) ?? 0) + (jsonInt(o['accountsRecords']) ?? 0);
    final total = (jsonDouble(o['totalEstimatedBytes']) ?? 0) > 0 ? jsonDouble(o['totalEstimatedBytes'])! : 1.0;
    final segments = <(String, String, Color)>[
      ('apiCacheBytes', context.tr('storage.legend_api', 'API Event Caches'), const Color(0xFF3B82F6)),
      ('userScoutingBytes', context.tr('storage.legend_scout', 'User Scouting Records'), const Color(0xFF10B981)),
      ('chatBytes', context.tr('storage.legend_chat', 'Team Chat Messages'), const Color(0xFFF59E0B)),
      ('accountsBytes', context.tr('storage.legend_accounts', 'Accounts & Sessions'), const Color(0xFF8B5CF6)),
      ('systemConfigBytes', context.tr('storage.legend_config', 'Configurations & System'), const Color(0xFF64748B)),
      ('errorReportsBytes', context.tr('storage.legend_errors', 'Error & Bug Reports'), const Color(0xFFEF4444)),
    ];
    return PortedSection(
      title: context.tr('storage.title', 'Site Storage Management'),
      subtitle: context.tr('storage.notice',
          'Monitor database footprint, manage re-syncable API event caches, view data use by scouting team number, and run safe or deep data pruning.'),
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(context.tr('storage.btn_refresh', 'Refresh Storage Data')),
        ),
      ],
      child: _loading
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PortedStatGrid(stats: [
                  PortedStat('${context.tr('storage.db_storage', 'Database Storage')} · $engine', fmtBytes(o['totalPhysicalSizeBytes']),
                      '${fmtNum(o['totalRecords'])} ${context.tr('storage.total_records', 'total records')}'),
                  PortedStat(context.tr('storage.api_caches', 'API Event Caches'), fmtBytes(o['apiCacheBytes']),
                      '${fmtNum(o['apiCacheRecords'])} ${context.tr('storage.cached_api_rows', 'cached event rows')}'),
                  PortedStat(context.tr('storage.user_scouting_data', 'User Scouting Data'), fmtBytes(o['userScoutingBytes']),
                      '${fmtNum(o['userScoutingRecords'])} ${context.tr('storage.user_scouting_forms', 'match/pit/qual forms')}'),
                  PortedStat(context.tr('storage.chat_accounts', 'Team Chat & Accounts'), fmtBytes(chatAccountBytes),
                      '$chatAccountRecords messages & users'),
                ]),
                const SizedBox(height: 14),
                Text(context.tr('storage.allocation_ratio', 'Database Allocation Ratio'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      for (final s in segments)
                        if ((jsonDouble(o[s.$1]) ?? 0) > 0)
                          Expanded(
                            flex: ((jsonDouble(o[s.$1])! / total) * 1000).round().clamp(1, 1000),
                            child: Container(color: s.$3),
                          ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final s in segments)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text('${s.$2} ${((jsonDouble(o[s.$1]) ?? 0) / total * 100).toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
                    ]),
                ]),
              ],
            ),
    );
  }

  List<Widget> _buildEvents(BuildContext context) {
    final years = _events.map((e) => jsonStr(e['year'])).where((y) => y.isNotEmpty).toSet().toList()..sort((a, b) => b.compareTo(a));
    final q = _eventSearch.trim().toLowerCase();
    final shown = _events.where((e) {
      if (_eventYear != null && jsonStr(e['year']) != _eventYear) return false;
      if (q.isNotEmpty && !jsonStr(e['eventKey']).toLowerCase().contains(q) && !jsonStr(e['name']).toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return [
      PortedSection(
        title: context.tr('storage.tab_events', 'API Event Caches'),
        actions: [
          OutlinedButton(
            onPressed: _busy.contains('old') ? null : _clearOldYears,
            child: Text(context.tr('storage.btn_prune_years', 'Prune Events ≤ Year')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ObsidianUITheme.warningOrange),
            onPressed: _busy.contains('all')
                ? null
                : () => _safe('all', 'Clear ALL API Event Caches',
                    'Are you sure you want to clear all cached events, match schedules, teams, and Statbotics EPA history across all seasons?',
                    '/api/admin/storage/cache/clear-all', {}),
            child: Text(context.tr('storage.btn_clear_all_api', 'Clear All API Caches')),
          ),
        ],
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: context.tr('storage.search_event_placeholder', 'Search event key or name...'),
              ),
              onChanged: (v) => setState(() => _eventSearch = v),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String?>(
            value: _eventYear,
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('storage.all_years', 'All Years'))),
              for (final y in years) DropdownMenuItem(value: y, child: Text(y)),
            ],
            onChanged: (v) => setState(() => _eventYear = v),
          ),
        ]),
      ),
      if (shown.isEmpty) const PortedNotice('No cached events matched your filter.'),
      for (final e in shown)
        Builder(builder: (context) {
          final key = jsonStr(e['eventKey']);
          final name = jsonStr(e['name'], key);
          final forms = jsonInt(e['userScoutingEntryCount']) ?? 0;
          return ObsidianGlassCard(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$key · ${e['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  [
                    '${context.tr('storage.th_year', 'Year')} ${e['year'] ?? '-'}',
                    '${context.tr('storage.th_matches', 'Matches')} ${fmtNum(e['matchCount'])}',
                    '${context.tr('storage.th_teams', 'Teams')} ${fmtNum(e['teamCount'])}',
                    '${context.tr('storage.th_cache_size', 'Cache Size')} ${fmtBytes(e['cacheBytes'])}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  PortedBadge(
                    'EPA ${jsonBool(e['hasEpaHistory']) ? context.tr('storage.cached', 'Cached') : context.tr('storage.none', 'None')}',
                    color: jsonBool(e['hasEpaHistory']) ? ObsidianUITheme.successGreen : muted,
                  ),
                  PortedBadge('$forms ${context.tr('storage.forms', 'Forms')}',
                      color: forms > 0 ? ObsidianUITheme.errorRed : ObsidianUITheme.successGreen),
                ]),
                Wrap(spacing: 4, children: [
                  TextButton(
                    onPressed: _busy.contains('c$key')
                        ? null
                        : () => _safe('c$key', 'Clear API Event Cache',
                            'Are you sure you want to clear the cached match schedules, team rosters, and EPA stats for $name ($key)?',
                            '/api/admin/storage/cache/clear-event', {'eventKey': key}),
                    child: Text(context.tr('storage.btn_clear_cache', 'Clear Cache')),
                  ),
                  if (forms > 0)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                      onPressed: _busy.contains('d$key')
                          ? null
                          : () => _danger(
                              'd$key',
                              context.tr('storage.btn_delete_scouting', 'Delete Scouting'),
                              'You are about to permanently delete ALL submitted match, pit, and qualitative scouting entries for $name ($key) across all scouting teams.',
                              'CONFIRM',
                              '/api/admin/storage/user-data/delete-event',
                              {'eventKey': key, 'confirmText': 'CONFIRM'}),
                      child: Text(context.tr('storage.btn_delete_scouting', 'Delete Scouting')),
                    ),
                ]),
              ],
            ),
          );
        }),
    ];
  }

  Future<void> _clearOldYears() async {
    final def = DateTime.now().year - 1;
    final text = await promptPortedText(context,
        title: context.tr('storage.btn_prune_years', 'Prune Events ≤ Year'),
        label: 'Enter cutoff competition year to clear API event caches (e.g. $def)',
        initial: '$def',
        keyboardType: TextInputType.number);
    if (text == null || !mounted) return;
    final year = int.tryParse(text.trim());
    if (year == null || year < 2000 || year > 2100) {
      ObsidianFeedback.showError(context, message: 'Invalid year entered.');
      return;
    }
    await _safe('old', 'Clear API Caches for Events ≤ $year',
        'Are you sure you want to purge external API caches for all events from year $year or earlier?',
        '/api/admin/storage/cache/clear-old-years', {'olderThanYear': year});
  }

  List<Widget> _buildTeams(BuildContext context) {
    final q = _teamSearch.trim();
    final shown = _teams.where((t) {
      if (_teamProgram.isNotEmpty && t['program'] != _teamProgram) return false;
      if (q.isNotEmpty && !'${t['teamNumber']}'.contains(q)) return false;
      return true;
    }).toList();
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return [
      PortedSection(
        title: context.tr('storage.tab_teams', 'Data Usage by Scouting Team'),
        subtitle: context.tr('storage.team_group_notice', 'Grouped by scouting team number across all events'),
        child: Row(children: [
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: context.tr('storage.search_team_placeholder', 'Search team number (e.g. 254)...'),
              ),
              onChanged: (v) => setState(() => _teamSearch = v),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _teamProgram,
            items: [
              DropdownMenuItem(value: '', child: Text(context.tr('storage.all_programs', 'All Programs (FRC / FTC)'))),
              const DropdownMenuItem(value: 'FRC', child: Text('FRC')),
              const DropdownMenuItem(value: 'FTC', child: Text('FTC')),
            ],
            onChanged: (v) => setState(() => _teamProgram = v ?? ''),
          ),
        ]),
      ),
      if (shown.isEmpty) const PortedNotice('No scouting teams matched your filter.'),
      for (final t in shown)
        Builder(builder: (context) {
          final team = jsonInt(t['teamNumber']) ?? 0;
          final program = jsonStr(t['program'], 'FRC');
          final expected = 'DELETE TEAM $team';
          return ObsidianGlassCard(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Team $team', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  PortedBadge(program),
                  const Spacer(),
                  Text(fmtBytes(t['totalBytes']), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(
                  [
                    '${context.tr('storage.th_match_entries', 'Match Entries')} ${fmtNum(t['matchEntryCount'])} (${fmtBytes(t['matchBytes'])})',
                    '${context.tr('storage.th_pit_entries', 'Pit Entries')} ${fmtNum(t['pitEntryCount'])} (${fmtBytes(t['pitBytes'])})',
                    '${context.tr('storage.th_qual_entries', 'Qual Entries')} ${fmtNum(t['qualEntryCount'])} (${fmtBytes(t['qualBytes'])})',
                    '${fmtNum(t['configRevisionCount'])} ${context.tr('storage.revs', 'revs')}',
                    '${fmtNum(t['chatMessageCount'])} ${context.tr('storage.msgs', 'msgs')}',
                    '${fmtNum(t['userCount'])} ${context.tr('storage.users_count', 'users')}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                Wrap(spacing: 4, children: [
                  TextButton(onPressed: () => _teamDetail(team, program), child: Text(context.tr('storage.btn_details', 'Details'))),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                    onPressed: _busy.contains('t$team$program')
                        ? null
                        : () => _danger(
                            't$team$program',
                            context.tr('storage.btn_wipe_team', 'Wipe Team Data'),
                            'You are about to permanently delete the entire dataset for Team $team ($program), including all match scouting, pit scouting, qualitative notes, custom form configurations, revision history, analytics reports, and chat channels.',
                            expected,
                            '/api/admin/storage/user-data/delete-team',
                            {'teamNumber': team, 'program': program, 'confirmText': expected}),
                    child: Text(context.tr('storage.btn_wipe_team', 'Wipe Team Data')),
                  ),
                ]),
              ],
            ),
          );
        }),
    ];
  }

  Future<void> _teamDetail(int team, String program) async {
    final res = await widget.apiService.requestJson('GET', '/api/admin/storage/teams/$team', query: {'program': program});
    if (!mounted) return;
    if (!res.success) {
      reportResult(context, res, action: 'Team $team');
      return;
    }
    final detail = jsonMap(res.data);
    final sum = jsonMap(detail['summary']);
    final events = jsonMaps(detail['events']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text('Team $team ($program)'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PortedKeyValue('Total Data Size', fmtBytes(sum['totalBytes'])),
                PortedKeyValue('Total Records', fmtNum(sum['totalRecords'])),
                PortedKeyValue('Match Forms', '${fmtNum(sum['matchEntryCount'])} (${fmtBytes(sum['matchBytes'])})'),
                PortedKeyValue('Pit Forms', '${fmtNum(sum['pitEntryCount'])} (${fmtBytes(sum['pitBytes'])})'),
                PortedKeyValue('Qual Forms', '${fmtNum(sum['qualEntryCount'])} (${fmtBytes(sum['qualBytes'])})'),
                PortedKeyValue('Config Revisions', '${fmtNum(sum['configRevisionCount'])} (${fmtBytes(sum['configRevisionBytes'])})'),
                PortedKeyValue('Chat Messages', '${fmtNum(sum['chatMessageCount'])} (${fmtBytes(sum['chatBytes'])})'),
                PortedKeyValue('Registered Users', fmtNum(sum['userCount'])),
                const Divider(),
                if (events.isEmpty)
                  const Text('No scouting data by event.')
                else
                  for (final ev in events)
                    PortedKeyValue(jsonStr(ev['eventKey'], '-'),
                        '${fmtNum(ev['matchCount'])} / ${fmtNum(ev['pitCount'])} / ${fmtNum(ev['qualCount'])} · ${fmtBytes(ev['totalBytes'])}'),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  List<Widget> _buildMaintenance(BuildContext context) {
    return [
      PortedNotice(context.tr('storage.maintenance_notice',
          'Perform routine cleanup of historical drafts, chat logs, inactive sessions, and defragment database files to reclaim space.')),
      PortedSection(
        title: context.tr('storage.prune_revs_title', 'Prune Config Revisions'),
        subtitle: context.tr('storage.prune_revs_desc',
            'Retain only the latest N revision snapshots per form kind for each team, pruning obsolete draft revisions.'),
        actions: [
          OutlinedButton(
            onPressed: _busy.contains('revs')
                ? null
                : () => _post('revs', '/api/admin/storage/prune/config-revisions',
                    {'keepLatestPerKind': int.tryParse(_keepRevisions.text) ?? 10}, context.tr('storage.btn_prune_revs', 'Prune Older Revisions')),
            child: Text(context.tr('storage.btn_prune_revs', 'Prune Older Revisions')),
          ),
        ],
        child: TextField(
          controller: _keepRevisions,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.tr('storage.prune_revs_label', 'Keep Latest Revisions Per Form'), isDense: true),
        ),
      ),
      PortedSection(
        title: context.tr('storage.prune_chat_title', 'Prune Team Chat Messages'),
        subtitle: context.tr('storage.prune_chat_desc',
            'Clean up historic team chat messages older than a specified number of days to reduce table size.'),
        actions: [
          OutlinedButton(
            onPressed: _busy.contains('chat')
                ? null
                : () {
                    final days = int.tryParse(_chatDays.text) ?? 90;
                    _safe('chat', context.tr('storage.btn_prune_chat', 'Prune Chat History'),
                        'Are you sure you want to delete all team chat messages older than $days days?',
                        '/api/admin/storage/prune/chat', {'olderThanDays': days});
                  },
            child: Text(context.tr('storage.btn_prune_chat', 'Prune Chat History')),
          ),
        ],
        child: TextField(
          controller: _chatDays,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.tr('storage.prune_chat_label', 'Delete Messages Older Than (Days)'), isDense: true),
        ),
      ),
      PortedSection(
        title: context.tr('storage.clean_sessions_title', 'Clean Expired Sessions & Tokens'),
        subtitle: context.tr('storage.clean_sessions_desc',
            'Remove expired user login sessions, stale device tokens, and used password reset tokens.'),
        actions: [
          OutlinedButton(
            onPressed: _busy.contains('sessions')
                ? null
                : () => _post('sessions', '/api/admin/storage/prune/sessions', {},
                    context.tr('storage.btn_clean_sessions', 'Clean Expired Sessions')),
            child: Text(context.tr('storage.btn_clean_sessions', 'Clean Expired Sessions')),
          ),
        ],
      ),
      PortedSection(
        title: context.tr('storage.prune_errors_title', 'Prune Error & Bug Reports'),
        subtitle: context.tr('storage.prune_errors_desc',
            'Clean up accumulated server exceptions and client bug reports to free database storage.'),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
            onPressed: _busy.contains('errors')
                ? null
                : () => _safe(
                    'errors',
                    context.tr('storage.btn_prune_errors', 'Delete Error Reports'),
                    _errorScope == 'resolved'
                        ? context.tr('storage.confirm_prune_resolved_errors', 'Are you sure you want to delete all resolved error reports?')
                        : context.tr('storage.confirm_prune_all_errors',
                            'Are you sure you want to delete all error reports, including open ones?'),
                    '/api/admin/storage/prune/errors',
                    {'deleteOnlyResolved': _errorScope == 'resolved'}),
            child: Text(context.tr('storage.btn_prune_errors', 'Delete Error Reports')),
          ),
        ],
        child: DropdownButtonFormField<String>(
          initialValue: _errorScope,
          isExpanded: true,
          dropdownColor: ObsidianUITheme.getSurfaceColor(context),
          decoration: InputDecoration(labelText: context.tr('storage.prune_errors_scope_label', 'Deletion Scope'), isDense: true),
          items: [
            DropdownMenuItem(
                value: 'resolved', child: Text(context.tr('storage.prune_errors_scope_resolved', 'Resolved Error Reports Only'))),
            DropdownMenuItem(value: 'all', child: Text(context.tr('storage.prune_errors_scope_all', 'All Error Reports (Open & Resolved)'))),
          ],
          onChanged: (v) => setState(() => _errorScope = v ?? 'resolved'),
        ),
      ),
      PortedSection(
        title: context.tr('storage.reclaim_title', 'Reclaim Physical Disk Space'),
        subtitle: context
            .tr('storage.reclaim_desc',
                'Runs SQLite VACUUM or PostgreSQL optimization to defragment storage and shrink physical database file size after large deletions.')
            .replaceAll(RegExp(r'</?code>'), ''),
        actions: [
          FilledButton(
            onPressed: _busy.contains('vacuum')
                ? null
                : () => _post('vacuum', '/api/admin/storage/maintenance/reclaim', {}, context.tr('storage.btn_reclaim', 'Execute Database VACUUM')),
            child: Text(_busy.contains('vacuum') ? 'Executing VACUUM...' : context.tr('storage.btn_reclaim', 'Execute Database VACUUM')),
          ),
        ],
      ),
    ];
  }
}
