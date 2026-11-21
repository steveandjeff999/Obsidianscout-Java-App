import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Public Data directory: teams that chose to share their scouting data, by team and event.
/// Each view (Graphs, Rankings, ...) opens the server's read-only public page in the browser,
/// the same pages the site's /public-data links to.
class PublicDataScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const PublicDataScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<PublicDataScreen> createState() => _PublicDataScreenState();
}

/// Views offered for each team + event, in the site's order. `needs` says which data the view uses.
const List<(String page, String label, String needs)> _publicViews = [
  ('graphs', 'Graphs', 'match'),
  ('analytics', 'Analytics', 'match'),
  ('compare', 'Compare Teams', 'match'),
  ('custom-analytics', 'Custom Analytics', 'match'),
  ('rankings', 'Rankings', 'match'),
  ('projected-rankings', 'Projected Rankings', 'match'),
  ('predictor', 'Match Predictor', 'match'),
  ('event-predictor', 'Event Predictor', 'match'),
  ('match-data', 'Match Data', 'match'),
  ('pit-data', 'Pit Data', 'pit'),
  ('qual-data', 'Qual Data', 'qual'),
  ('qual-rankings', 'Qual Rankings', 'notes'),
  ('all-data', 'All Data', 'any'),
];

class _PublicDataScreenState extends State<PublicDataScreen> {
  List<Map<String, dynamic>> _teams = [];
  bool _loading = true;
  String _query = '';
  int? _year;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dir = await widget.apiService.fetchPublicDirectory();
    if (!mounted) return;
    final teams = (dir?['teams'] as List? ?? const [])
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList()
      ..sort((a, b) => ((a['teamNumber'] as num?) ?? 0).compareTo((b['teamNumber'] as num?) ?? 0));
    setState(() {
      _teams = teams;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _events(Map<String, dynamic> team) {
    final list = (team['events'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final filtered = _year == null ? list : list.where((e) => (e['year'] as num?)?.toInt() == _year).toList();
    filtered.sort((a, b) => ((b['year'] as num?) ?? 0).compareTo((a['year'] as num?) ?? 0));
    return filtered;
  }

  List<int> get _years {
    final ys = <int>{};
    for (final t in _teams) {
      for (final e in (t['events'] as List? ?? const [])) {
        final y = (e is Map ? e['year'] as num? : null)?.toInt();
        if (y != null && y > 0) ys.add(y);
      }
    }
    return ys.toList()..sort((a, b) => b.compareTo(a));
  }

  bool _matches(Map<String, dynamic> team) {
    if (_events(team).isEmpty) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      team['teamNumber']?.toString() ?? '',
      team['teamName']?.toString() ?? '',
      for (final e in _events(team)) ...[e['eventKey']?.toString() ?? '', e['eventName']?.toString() ?? ''],
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  bool _available(String needs, Map<String, dynamic> ev, bool notesIncluded) {
    final match = (ev['matchEntries'] as num?)?.toInt() ?? 0;
    final pit = (ev['pitEntries'] as num?)?.toInt() ?? 0;
    final qual = (ev['qualEntries'] as num?)?.toInt() ?? 0;
    switch (needs) {
      case 'match':
        return match > 0;
      case 'pit':
        return pit > 0;
      case 'qual':
        return qual > 0;
      case 'notes':
        return notesIncluded && qual > 0;
      default:
        return match + pit + qual > 0;
    }
  }

  Future<void> _openView(Map<String, dynamic> team, String eventKey, String page) async {
    final program = team['program']?.toString() ?? 'FRC';
    final params = <String, String>{'event': eventKey, if (program != 'FRC') 'program': program};
    final base = Uri.parse(widget.apiService.currentServerUrl);
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/public/${team['teamNumber']}/$page',
      queryParameters: params,
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final shown = _teams.where(_matches).toList();
    final years = _years;

    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        const PortedSection(
          title: 'Public Data',
          subtitle: 'Scouting data other teams have chosen to share. Views open read-only in your browser.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search team or event',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (years.isNotEmpty) ...[
                const SizedBox(width: 10),
                DropdownButton<int?>(
                  value: _year,
                  hint: const Text('All years'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                    for (final y in years) DropdownMenuItem<int?>(value: y, child: Text('$y')),
                  ],
                  onChanged: (v) => setState(() => _year = v),
                ),
              ],
            ],
          ),
        ),
        if (_loading)
          const PortedLoading()
        else if (_teams.isEmpty)
          const PortedNotice('No teams have shared their data on this server yet.', icon: Icons.public_off_rounded)
        else if (shown.isEmpty)
          const PortedNotice('No teams match your search.', icon: Icons.search_off_rounded)
        else
          for (final team in shown)
            ObsidianGlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${team['program'] == 'FTC' ? 'FTC ' : ''}${team['teamNumber']}'
                    '${(team['teamName'] ?? '').toString().isNotEmpty ? ' · ${team['teamName']}' : ''}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary),
                  ),
                  const SizedBox(height: 6),
                  for (final ev in _events(team)) _buildEvent(context, team, ev, primary, muted),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildEvent(BuildContext context, Map<String, dynamic> team, Map<String, dynamic> ev, Color primary, Color muted) {
    final eventKey = ev['eventKey']?.toString() ?? '';
    final id = '${team['program']}-${team['teamNumber']}-$eventKey';
    final open = _expanded.contains(id);
    final notes = team['notesIncluded'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${ev['eventName'] ?? eventKey}', style: TextStyle(fontWeight: FontWeight.w600, color: primary)),
                      Text(
                        '$eventKey · ${ev['matchEntries'] ?? 0} match · ${ev['pitEntries'] ?? 0} pit · ${ev['qualEntries'] ?? 0} qual',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: muted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (page, label, needs) in _publicViews)
                  ActionChip(
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                    onPressed: _available(needs, ev, notes) ? () => _openView(team, eventKey, page) : null,
                    tooltip: _available(needs, ev, notes) ? null : 'Not enough shared data for this view',
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
