import 'package:flutter/material.dart';

import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

/// What the user picked in [showEventCodePicker]: the season and the event.
class EventCodePick {
  final int year;
  final EventCatalogEntryModel event;
  const EventCodePick(this.year, this.event);
}

/// "Don't know your event code?" sheet: a season selector and a searchable list of every event the server knows
/// of for that season (kept current by the server with its shared API keys). Returns the pick, or null.
Future<EventCodePick?> showEventCodePicker(
  BuildContext context, {
  required ApiService apiService,
  required int initialYear,
}) {
  return showModalBottomSheet<EventCodePick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EventCodePickerSheet(apiService: apiService, initialYear: initialYear),
  );
}

class _EventCodePickerSheet extends StatefulWidget {
  final ApiService apiService;
  final int initialYear;
  const _EventCodePickerSheet({required this.apiService, required this.initialYear});

  @override
  State<_EventCodePickerSheet> createState() => _EventCodePickerSheetState();
}

class _EventCodePickerSheetState extends State<_EventCodePickerSheet> {
  /// Lists already fetched this app session, by season.
  static final Map<int, EventCatalogModel> _cache = {};

  final TextEditingController _search = TextEditingController();
  late int _year;
  late final List<int> _years;
  EventCatalogModel? _catalog;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _years = [for (var y = now + 1; y >= now - 6; y--) y];
    if (!_years.contains(widget.initialYear)) {
      _years
        ..add(widget.initialYear)
        ..sort((a, b) => b.compareTo(a));
    }
    _year = widget.initialYear;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final year = _year;
    final cached = _cache[year];
    setState(() {
      _catalog = cached;
      _error = null;
      _loading = cached == null;
    });
    if (cached != null) return;
    final res = await widget.apiService.fetchEventCatalog(year);
    if (!mounted || year != _year) return;
    setState(() {
      _loading = false;
      if (res.isSuccess && res.data != null) {
        _catalog = res.data;
        // An "unavailable" answer (no keys yet) isn't cached, so adding keys takes effect without an app restart.
        if (res.data!.available) _cache[year] = res.data!;
      } else {
        _error = res.message ?? 'Failed to load the event list';
      }
    });
  }

  List<EventCatalogEntryModel> get _matches {
    final events = _catalog?.events ?? const <EventCatalogEntryModel>[];
    final terms = _search.text.trim().toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return events;
    return events.where((e) => terms.every(e.searchText.contains)).toList();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? (iso ?? '') : '${_months[d.month - 1]} ${d.day}';
  }

  String _meta(EventCatalogEntryModel e) {
    final dates = e.startDate == null
        ? ''
        : _date(e.startDate) + (e.endDate != null && e.endDate != e.startDate ? ' – ${_date(e.endDate)}' : '');
    return [dates, if (e.week != null) 'Week ${e.week}', e.type, e.location].where((s) => s.isNotEmpty).join(' · ');
  }

  String _updatedLine() {
    final at = _catalog?.fetchedAt;
    if (at == null) return '';
    final mins = DateTime.now().difference(at).inMinutes;
    if (mins < 1) return 'Updated just now';
    if (mins < 60) return 'Updated $mins min ago';
    final hours = (mins / 60).round();
    if (hours < 48) return 'Updated $hours h ago';
    return 'Updated ${(hours / 24).round()} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final border = ObsidianUITheme.getBorderColor(context);
    final accent = ObsidianUITheme.primaryAccent;
    final matches = _matches;
    final catalog = _catalog;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _message(Icons.error_outline_rounded, _error!, secondary, action: TextButton(onPressed: _load, child: const Text('Retry')));
    } else if (catalog != null && !catalog.available) {
      body = _message(Icons.key_off_rounded,
          "The server can't list events for this season yet: no TBA or FIRST API key is set up.", secondary);
    } else if (matches.isEmpty) {
      body = _message(Icons.search_off_rounded, 'No events match.', secondary);
    } else {
      body = ListView.separated(
        itemCount: matches.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: border.withValues(alpha: 0.5)),
        itemBuilder: (ctx, i) {
          final e = matches[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).pop(EventCodePick(_year, e)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(e.code, primary, border),
                      if (e.altCode.isNotEmpty) _chip('FIRST ${e.altCode}', accent, accent.withValues(alpha: 0.4)),
                    ],
                  ),
                  if (_meta(e).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_meta(e), style: TextStyle(color: secondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.travel_explore_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Find your event', style: TextStyle(color: primary, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: secondary),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<int>(
                      value: _year,
                      dropdownColor: bg,
                      style: TextStyle(color: primary, fontSize: 14),
                      items: [for (final y in _years) DropdownMenuItem(value: y, child: Text('$y'))],
                      onChanged: (y) {
                        if (y == null || y == _year) return;
                        _year = y;
                        _search.clear();
                        _load();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _search,
                    autofocus: false,
                    style: TextStyle(color: primary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name, code, or city',
                      hintStyle: TextStyle(color: secondary, fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded, color: secondary, size: 20),
                      isDense: true,
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: accent)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (catalog != null && catalog.available && !_loading)
              Text(
                [
                  '${matches.length} of ${catalog.events.length} events',
                  _updatedLine(),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(color: secondary, fontSize: 11),
              ),
            const SizedBox(height: 6),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color, Color borderColor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace')),
      );

  Widget _message(IconData icon, String text, Color color, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 13)),
              if (action != null) action,
            ],
          ),
        ),
      );
}
