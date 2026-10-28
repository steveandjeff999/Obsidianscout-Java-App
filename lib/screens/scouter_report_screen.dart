import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// How much each scout contributed for an event, a season, or all time, with CSV export (admins only).
/// Same data as the website's scouter-report.html.
class ScouterReportScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ScouterReportScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<ScouterReportScreen> createState() => _ScouterReportScreenState();
}

class _ScouterReportScreenState extends State<ScouterReportScreen> {
  bool _loading = true;
  String _scope = 'event';
  String? _eventKey;
  int? _year;
  bool _includePrescout = false;
  bool _hideInactive = true;
  String _search = '';
  String _sortBy = 'totalEntries';
  bool _sortAsc = false;
  List<Map<String, dynamic>> _events = [];
  List<int> _years = [];
  Map<String, dynamic>? _report;
  final Set<String> _expanded = {};

  static const _sortKeys = [
    'totalEntries', 'username', 'role', 'matchesScouted', 'pitEntries', 'qualEntries', 'eventsScouted', 'teamsScouted',
    'avgCompletenessPct', 'discrepancyEntries', 'assignmentCompletionPct', 'lastSubmission',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.apiService.canUseAdminPage('scouter-report')) _init();
  }

  Future<void> _init() async {
    final res = await widget.apiService.requestJson('GET', '/api/admin/scouter-report/options');
    if (!mounted) return;
    final opts = jsonMap(res.data);
    final settings = widget.apiService.currentSettings;
    final current = (settings?.eventKey ?? '').toLowerCase();
    final events = jsonMaps(opts['events']);
    final hasCurrent = events.any((e) => e['eventKey'] == current);
    if (current.isNotEmpty && !hasCurrent) events.insert(0, {'eventKey': current, 'name': null});
    final years = jsonList(opts['years']).map(jsonInt).whereType<int>().toSet();
    if (settings?.year != null) years.add(settings!.year);
    _events = events;
    _years = years.toList()..sort((a, b) => b.compareTo(a));
    _eventKey = current.isNotEmpty ? current : (events.isNotEmpty ? jsonStr(events.first['eventKey']) : null);
    _year = settings?.year ?? (_years.isNotEmpty ? _years.first : null);
    if (!hasCurrent && _years.isNotEmpty) _scope = 'year';
    await _load();
  }

  Map<String, String> _query([Map<String, String> extra = const {}]) => {
        if (_scope == 'event' && _eventKey != null) 'eventKey': _eventKey!,
        if (_scope == 'year' && _year != null) 'year': '$_year',
        if (_includePrescout) 'includePrescout': 'true',
        ...extra,
      };

  Future<void> _load() async {
    if (_scope == 'event' && (_eventKey == null || _eventKey!.isEmpty)) {
      setState(() {
        _report = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final res = await widget.apiService.requestJson('GET', '/api/admin/scouter-report', query: _query());
    if (!mounted) return;
    if (!res.success) reportResult(context, res, action: context.tr('scouter-report.title', 'Scouter Report'));
    setState(() {
      _report = res.success ? jsonMap(res.data) : null;
      _expanded.clear();
      _loading = false;
    });
  }

  Future<void> _export(String? detail) async {
    final res = await widget.apiService.requestBytes('/api/admin/scouter-report',
        query: _query({'format': 'csv', if (detail != null) 'detail': detail}));
    if (!mounted) return;
    await saveDownloadedBytes(context, res, detail == null ? 'scouter-report.csv' : 'scouter-report-by-event.csv', 'text/csv');
  }

  String _scopeLabel(Map<String, dynamic> r) {
    if (r['scope'] == 'event') {
      final name = jsonStr(r['eventName']);
      return name.isNotEmpty ? '$name (${r['eventKey']})' : jsonStr(r['eventKey']);
    }
    if (r['scope'] == 'year') return context.tr('scouter-report.season_label', '{year} season').replaceAll('{year}', '${r['year']}');
    return context.tr('scouter-report.all_time', 'All time');
  }

  int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final av = a[_sortBy];
    final bv = b[_sortBy];
    if (av == null && bv == null) return 0;
    if (av == null) return 1; // blanks always last
    if (bv == null) return -1;
    var r = (av is num && bv is num) ? av.compareTo(bv) : av.toString().toLowerCase().compareTo(bv.toString().toLowerCase());
    if (r == 0) r = jsonStr(a['username']).toLowerCase().compareTo(jsonStr(b['username']).toLowerCase());
    return _sortAsc ? r : -r;
  }

  String _sortLabel(String key) {
    const cols = {
      'username': 'col_scout', 'role': 'col_role', 'matchesScouted': 'col_matches', 'pitEntries': 'col_pit',
      'qualEntries': 'col_qual', 'totalEntries': 'col_total', 'eventsScouted': 'col_events', 'teamsScouted': 'col_teams',
      'avgCompletenessPct': 'col_completeness', 'discrepancyEntries': 'col_discrepancies',
      'assignmentCompletionPct': 'col_assignments', 'lastSubmission': 'col_last',
    };
    return context.tr('scouter-report.${cols[key]}', key);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.canUseAdminPage('scouter-report')) {
      return PortedLocked(
        title: context.tr('scouter-report.admin_only', 'Admin only'),
        message: context.tr('scouter-report.admin_only_notice', 'You need admin access to view scouter reports.'),
      );
    }
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        _buildControls(context),
        if (_loading) const PortedLoading() else ..._buildReport(context),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return PortedSection(
      title: context.tr('scouter-report.title', 'Scouter Report'),
      subtitle: context.tr('scouter-report.notice', 'See how much each scout contributed for an event or a whole season, then export it.'),
      actions: [
        FilledButton.icon(
          onPressed: _report == null ? null : () => _export(null),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(context.tr('scouter-report.export_summary', 'Export CSV')),
        ),
        OutlinedButton.icon(
          onPressed: _report == null ? null : () => _export('events'),
          icon: const Icon(Icons.table_view_rounded, size: 18),
          label: Text(context.tr('scouter-report.export_by_event', 'Export CSV by Event')),
        ),
      ],
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _scope,
            dropdownColor: surface,
            decoration: InputDecoration(labelText: context.tr('scouter-report.scope', 'Report For'), isDense: true),
            items: [
              DropdownMenuItem(value: 'event', child: Text(context.tr('scouter-report.scope_event', 'One event'))),
              DropdownMenuItem(value: 'year', child: Text(context.tr('scouter-report.scope_year', 'Whole season'))),
              DropdownMenuItem(value: 'all', child: Text(context.tr('scouter-report.scope_all', 'All time'))),
            ],
            onChanged: (v) {
              _scope = v ?? 'event';
              _load();
            },
          ),
          const SizedBox(height: 10),
          if (_scope == 'event')
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _eventKey,
              dropdownColor: surface,
              decoration: InputDecoration(labelText: context.tr('scouter-report.event', 'Event'), isDense: true),
              hint: Text(context.tr('scouter-report.no_events', 'No events with scouting data')),
              items: [
                for (final e in _events)
                  DropdownMenuItem(
                    value: jsonStr(e['eventKey']),
                    child: Text(
                      jsonStr(e['name']).isNotEmpty ? '${e['name']} (${e['eventKey']})' : jsonStr(e['eventKey']),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                _eventKey = v;
                _load();
              },
            ),
          if (_scope == 'year')
            DropdownButtonFormField<int>(
              initialValue: _year,
              dropdownColor: surface,
              decoration: InputDecoration(labelText: context.tr('scouter-report.season', 'Season'), isDense: true),
              items: [for (final y in _years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) {
                _year = v;
                _load();
              },
            ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              labelText: context.tr('scouter-report.search', 'Search Scouts'),
              hintText: context.tr('scouter-report.search_placeholder', 'Name or role'),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _includePrescout,
            title: Text(context.tr('scouter-report.include_prescout', 'Include prescout entries')),
            onChanged: (v) {
              _includePrescout = v;
              _load();
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _hideInactive,
            title: Text(context.tr('scouter-report.hide_inactive', 'Hide users with no activity')),
            onChanged: (v) => setState(() => _hideInactive = v),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _sortBy,
                  dropdownColor: surface,
                  decoration: InputDecoration(labelText: context.tr('common.sort_by', 'Sort by'), isDense: true),
                  items: [for (final k in _sortKeys) DropdownMenuItem(value: k, child: Text(_sortLabel(k)))],
                  onChanged: (v) => setState(() {
                    _sortBy = v ?? 'totalEntries';
                    _sortAsc = _sortBy == 'username' || _sortBy == 'role';
                  }),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _sortAsc = !_sortAsc),
                icon: Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildReport(BuildContext context) {
    final r = _report;
    if (r == null) return [PortedNotice(context.tr('scouter-report.empty', 'No scouting activity for this selection.'))];
    final totals = jsonMap(r['totals']);
    final scouters = jsonMaps(r['scouters']);
    final totalEntries =
        (jsonInt(totals['matchEntries']) ?? 0) + (jsonInt(totals['pitEntries']) ?? 0) + (jsonInt(totals['qualEntries']) ?? 0);
    final aTotal = jsonInt(totals['assignmentsTotal']) ?? 0;
    final aDone = jsonInt(totals['assignmentsCompleted']) ?? 0;
    final active = scouters.where((s) => (jsonInt(s['totalEntries']) ?? 0) > 0).toList();
    final avg = active.isEmpty ? 0 : (totalEntries * 10 / active.length).round() / 10;
    final top = active.isEmpty ? null : active.first;
    final q = _search.trim().toLowerCase();
    final rows = scouters
        .where((s) => !_hideInactive || (jsonInt(s['totalEntries']) ?? 0) > 0 || (jsonInt(s['assignmentsTotal']) ?? 0) > 0)
        .where((s) => q.isEmpty || jsonStr(s['username']).toLowerCase().contains(q) || jsonStr(s['role']).toLowerCase().contains(q))
        .toList()
      ..sort(_compare);
    final multiEvent = r['scope'] != 'event';
    final muted = ObsidianUITheme.getSecondaryTextColor(context);

    return [
      ObsidianGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PortedStatGrid(stats: [
              PortedStat(context.tr('scouter-report.kpi_active', 'Active Scouts'), '${totals['activeScouters'] ?? 0}',
                  '${scouters.length} ${context.tr('scouter-report.kpi_users_total', 'users listed')}'),
              PortedStat(context.tr('scouter-report.kpi_matches', 'Matches Covered'), '${totals['matchesCovered'] ?? 0}',
                  '${totals['matchEntries'] ?? 0} ${context.tr('scouter-report.kpi_match_entries', 'match entries')}'),
              PortedStat(context.tr('scouter-report.kpi_pit', 'Pit Entries'), '${totals['pitEntries'] ?? 0}'),
              PortedStat(context.tr('scouter-report.kpi_qual', 'Qual Entries'), '${totals['qualEntries'] ?? 0}'),
              PortedStat(context.tr('scouter-report.kpi_avg', 'Entries per Active Scout'), fmtNum(avg, digits: 1)),
              PortedStat(
                context.tr('scouter-report.kpi_assignments', 'Assignments Done'),
                aTotal == 0 ? '-' : '${(aDone * 1000 / aTotal).round() / 10}%',
                aTotal == 0 ? context.tr('scouter-report.kpi_no_assignments', 'No assignments') : '$aDone / $aTotal',
              ),
              PortedStat(context.tr('scouter-report.kpi_top', 'Top Scout'), top == null ? '-' : jsonStr(top['username']),
                  top == null ? null : '${top['totalEntries']} ${context.tr('scouter-report.kpi_entries', 'entries')}'),
            ]),
            const SizedBox(height: 10),
            Text(
              [
                '${context.tr('scouter-report.team', 'Team')} ${r['teamNumber']}',
                _scopeLabel(r),
                '${context.tr('scouter-report.generated', 'Generated')} ${fmtDateTime(context, r['generatedAt'])}',
                if (jsonBool(r['includePrescout'])) context.tr('scouter-report.with_prescout', 'includes prescout'),
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      ),
      if (rows.isEmpty) PortedNotice(context.tr('scouter-report.empty', 'No scouting activity for this selection.')),
      for (final s in rows) _buildScoutCard(context, s, multiEvent),
    ];
  }

  Widget _buildScoutCard(BuildContext context, Map<String, dynamic> s, bool multiEvent) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final id = jsonStr(s['userId']);
    final events = jsonMaps(s['events']);
    final canExpand = multiEvent && events.isNotEmpty;
    final open = canExpand && _expanded.contains(id);
    final inactive = (jsonInt(s['totalEntries']) ?? 0) == 0;
    final pct = jsonDouble(s['assignmentCompletionPct']);
    String col(String key, String fallback) => context.tr('scouter-report.$key', fallback);
    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: ObsidianGlassCard(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
        onTap: canExpand ? () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(jsonStr(s['username']), style: TextStyle(fontWeight: FontWeight.w800, color: primary))),
                PortedBadge(jsonStr(s['role'])),
                const SizedBox(width: 8),
                Text('${s['totalEntries'] ?? 0}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primary)),
                if (canExpand) Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: muted),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                '${col('col_matches', 'Matches')} ${s['matchesScouted'] ?? 0}',
                '${col('col_pit', 'Pit')} ${s['pitEntries'] ?? 0}',
                '${col('col_qual', 'Qual')} ${s['qualEntries'] ?? 0}',
                '${col('col_events', 'Events')} ${s['eventsScouted'] ?? 0}',
                '${col('col_teams', 'Teams')} ${s['teamsScouted'] ?? 0}',
                '${col('col_completeness', 'Avg Complete')} ${s['avgCompletenessPct'] == null ? '-' : '${s['avgCompletenessPct']}%'}',
                '${col('col_discrepancies', 'Discrepancies')} ${s['discrepancyEntries'] ?? 0}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
            if (pct != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Text(col('col_assignments', 'Assignments Done'), style: TextStyle(fontSize: 11.5, color: muted)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0, 1).toDouble(),
                      minHeight: 5,
                      backgroundColor: ObsidianUITheme.getBorderColor(context),
                      color: ObsidianUITheme.primaryAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${fmtNum(pct, digits: 1)}% (${s['assignmentsCompleted']}/${s['assignmentsTotal']})',
                    style: TextStyle(fontSize: 11.5, color: primary)),
              ]),
            ],
            if (jsonStr(s['lastSubmission']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${col('col_last', 'Last Entry')}: ${fmtDateTime(context, s['lastSubmission'])}',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ],
            if (open) ...[
              const Divider(height: 18),
              for (final e in events)
                PortedKeyValue(
                  jsonStr(e['eventName']).isNotEmpty
                      ? '${e['eventName']} (${e['eventKey']})'
                      : (jsonStr(e['eventKey']).isNotEmpty ? jsonStr(e['eventKey']) : col('no_event', 'No event')),
                  '${e['matchEntries'] ?? 0} / ${e['pitEntries'] ?? 0} / ${e['qualEntries'] ?? 0}',
                ),
              Text('${col('col_match_entries', 'Match Entries')} / ${col('col_pit', 'Pit')} / ${col('col_qual', 'Qual')}',
                  style: TextStyle(fontSize: 10.5, color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}
