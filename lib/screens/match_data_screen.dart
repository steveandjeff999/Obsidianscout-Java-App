import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/csv_export_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/csv_export_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/conflict_resolution_modal.dart';
import '../widgets/obsidian_image_preview_card.dart';

class MatchScoutingRecord {
  final String id;
  final int targetTeamNumber;
  final String eventKey;
  final bool isPrescout;
  final int matchNumber;
  final String? matchKey;
  final String? createdAt;
  final Map<String, dynamic> data;
  final bool hasDiscrepancy;
  final List<String> conflictingTeams;
  final String? scoutUsername;

  MatchScoutingRecord({
    required this.id,
    required this.targetTeamNumber,
    required this.eventKey,
    this.isPrescout = false,
    required this.matchNumber,
    this.matchKey,
    this.createdAt,
    required this.data,
    this.hasDiscrepancy = false,
    this.conflictingTeams = const [],
    this.scoutUsername,
  });

  DateTime? get createdDateTime {
    if (createdAt == null || createdAt!.isEmpty) return null;
    return DateTime.tryParse(createdAt!);
  }
}

class MatchDataScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const MatchDataScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<MatchDataScreen> createState() => _MatchDataScreenState();
}

class _MatchDataScreenState extends State<MatchDataScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<MatchScoutingRecord> _records = [];
  List<EventModel> _events = [];
  Map<int, TeamModel> _teamsByNumber = {};
  ScoutingConfigModel? _matchConfig;

  // Filters State
  String _selectedEventKey = 'all';
  String _teamQuery = '';
  String _matchQuery = '';
  bool _discrepanciesOnly = false;
  String _sortBy = 'match-asc'; // 'match-asc', 'match-desc', 'team-asc', 'date-desc', 'date-asc'
  MatchScoutingRecord? _selectedRecord;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant MatchDataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Hydration
    final cachedSettings = await widget.apiService.getCachedSettings();
    final cachedMatchCfg = await widget.apiService.getCachedMatchConfig();
    final cachedRawEntries = await widget.apiService.getCachedScoutingEntries();
    final cachedEvents = await widget.apiService.getCachedEvents(year: cachedSettings?.year);
    final cachedTeams = await widget.apiService.getCachedTeams(cachedSettings?.eventKey);

    if (mounted && (cachedRawEntries.isNotEmpty || cachedTeams.isNotEmpty)) {
      final Map<int, TeamModel> teamMap = {};
      for (final t in cachedTeams) {
        teamMap[t.teamNumber] = t;
      }
      final List<MatchScoutingRecord> parsed = [];
      for (final e in cachedRawEntries) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          final matchNum = (e['matchNumber'] as num?)?.toInt() ?? 0;
          if (matchNum > 0 || isPrescout) {
            parsed.add(MatchScoutingRecord(
              id: e['id']?.toString() ?? '',
              targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
              eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
              isPrescout: isPrescout,
              matchNumber: matchNum,
              matchKey: e['matchKey']?.toString(),
              createdAt: e['createdAt']?.toString(),
              data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
              hasDiscrepancy: e['hasDiscrepancy'] == true,
              conflictingTeams: (e['conflictingTeams'] as List?)?.map((t) => t.toString()).toList() ?? [],
              scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
            ));
          }
        }
      }

      setState(() {
        _matchConfig = cachedMatchCfg;
        _records = parsed;
        _events = cachedEvents;
        _teamsByNumber = teamMap;
        if (_selectedEventKey == 'all' && cachedSettings?.eventKey != null && cachedSettings!.eventKey.isNotEmpty) {
          _selectedEventKey = cachedSettings.eventKey;
        }
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation
    try {
      final settings = await widget.apiService.fetchSettings();
      final currentYear = settings?.year ?? DateTime.now().year;

      final results = await Future.wait([
        widget.apiService.fetchMatchConfig(),
        widget.apiService.fetchScoutingEntries(),
        widget.apiService.fetchEvents(year: currentYear),
        widget.apiService.fetchTeams(settings?.eventKey ?? ''),
      ]);

      final matchCfg = results[0] as ScoutingConfigModel?;
      final rawEntries = results[1] as List<dynamic>;
      final events = results[2] as List<EventModel>;
      final teams = results[3] as List<TeamModel>;

      final Map<int, TeamModel> teamMap = {};
      for (final t in teams) {
        teamMap[t.teamNumber] = t;
      }

      final List<MatchScoutingRecord> parsed = [];
      for (final e in rawEntries) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          final matchNum = (e['matchNumber'] as num?)?.toInt() ?? 0;
          if (matchNum > 0 || isPrescout) {
            parsed.add(MatchScoutingRecord(
              id: e['id']?.toString() ?? '',
              targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
              eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
              isPrescout: isPrescout,
              matchNumber: matchNum,
              matchKey: e['matchKey']?.toString(),
              createdAt: e['createdAt']?.toString(),
              data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
              hasDiscrepancy: e['hasDiscrepancy'] == true,
              conflictingTeams: (e['conflictingTeams'] as List?)?.map((t) => t.toString()).toList() ?? [],
              scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _matchConfig = matchCfg ?? _matchConfig;
          if (parsed.isNotEmpty) _records = parsed;
          if (events.isNotEmpty) _events = events;
          if (teamMap.isNotEmpty) _teamsByNumber = teamMap;
          if (_selectedEventKey == 'all' && settings?.eventKey != null && settings!.eventKey.isNotEmpty) {
            _selectedEventKey = settings.eventKey;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<MatchScoutingRecord> _getConflictingRecordsFor(MatchScoutingRecord record) {
    return _records.where((r) {
      if (r.targetTeamNumber != record.targetTeamNumber) return false;
      if (r.matchNumber != record.matchNumber) return false;
      if (r.eventKey != record.eventKey) return false;
      return true;
    }).toList();
  }

  void _openConflictResolver(MatchScoutingRecord record) {
    final conflicts = _getConflictingRecordsFor(record);
    if (conflicts.length < 2 && !record.hasDiscrepancy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No conflicting match submissions found.')),
      );
      return;
    }

    final rawEntries = conflicts.map((c) => {
      'id': c.id,
      'scoutUsername': c.scoutUsername ?? 'Scouter',
      'createdAt': c.createdAt,
      'data': c.data,
      'targetTeamNumber': c.targetTeamNumber,
      'eventKey': c.eventKey,
      'matchKey': c.matchKey,
      'matchNumber': c.matchNumber,
    }).toList();

    ConflictResolutionModal.show(
      context: context,
      apiService: widget.apiService,
      title: 'Match ${record.matchNumber} - Team ${record.targetTeamNumber} Conflict',
      subtitle: '${conflicts.length} scouter submissions found. Compare side-by-side.',
      type: 'match',
      fields: _matchConfig?.fields ?? [],
      conflictingEntries: rawEntries,
      onResolved: _loadData,
    );
  }

  List<MatchScoutingRecord> get _filteredRecords {
    final query = _teamQuery.trim().toLowerCase();
    final matchQ = int.tryParse(_matchQuery.trim());

    final filtered = _records.where((r) {
      if (_selectedEventKey != 'all' && _selectedEventKey.isNotEmpty) {
        if (r.eventKey != _selectedEventKey) return false;
      }
      if (_discrepanciesOnly) {
        final conflicts = _getConflictingRecordsFor(r);
        if (conflicts.length <= 1 && !r.hasDiscrepancy) return false;
      }
      if (query.isNotEmpty) {
        final teamStr = r.targetTeamNumber.toString();
        final teamObj = _teamsByNumber[r.targetTeamNumber];
        final name = teamObj?.nickname?.toLowerCase() ?? '';
        if (!teamStr.contains(query) && !name.contains(query)) {
          return false;
        }
      }
      if (matchQ != null) {
        if (r.matchNumber != matchQ) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'match-desc':
          return b.matchNumber.compareTo(a.matchNumber);
        case 'team-asc':
          return a.targetTeamNumber.compareTo(b.targetTeamNumber);
        case 'date-desc':
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        case 'date-asc':
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return da.compareTo(db);
        case 'match-asc':
        default:
          return a.matchNumber.compareTo(b.matchNumber);
      }
    });

    return filtered;
  }

  void _exportCsv() {
    final records = _filteredRecords;
    if (records.isEmpty) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Export Unavailable',
        message: 'No match records match the current filters to export.',
      );
      return;
    }

    final exportData = CsvExportService.exportMatchData(
      records: records,
      config: _matchConfig,
      eventKey: _selectedEventKey != 'all' ? _selectedEventKey : null,
    );

    CsvExportModal.show(
      context,
      title: 'Export Match Scouting Data',
      exportData: exportData,
    );
  }

  void _resetFilters() {
    setState(() {
      _teamQuery = '';
      _matchQuery = '';
      _discrepanciesOnly = false;
      _sortBy = 'match-asc';
      _selectedRecord = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Failed to load match scouting data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: secondaryTextColor, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredRecords;
    final totalMatches = _records.length;
    final uniqueTeams = _records.map((r) => r.targetTeamNumber).toSet().length;
    final discrepancyCount = _records.where((r) => r.hasDiscrepancy).length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 24.0),
        children: [
          // Title Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_esports_rounded, color: Colors.amberAccent, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Match Scouting Data',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Explore submitted match scouting entries, breakdown robot cycle scores, and inspect conflicts.',
                  style: TextStyle(color: secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 18),
                // Metric cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Match Entries', totalMatches.toString(), Colors.amberAccent, isDark)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildMetricTile('Teams Scouted', uniqueTeams.toString(), Colors.tealAccent, isDark)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildMetricTile('Conflicts', discrepancyCount.toString(), discrepancyCount > 0 ? Colors.orangeAccent : Colors.greenAccent, isDark),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _buildMetricTile('Match Entries', totalMatches.toString(), Colors.amberAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Teams Scouted', uniqueTeams.toString(), Colors.tealAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Conflicts', discrepancyCount.toString(), discrepancyCount > 0 ? Colors.orangeAccent : Colors.greenAccent, isDark)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Filters Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter Match Records',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                ),
                const SizedBox(height: 12),
                // Event selector
                DropdownButtonFormField<String>(
                  value: _events.any((e) => e.eventKey == _selectedEventKey) ? _selectedEventKey : 'all',
                  decoration: InputDecoration(
                    labelText: 'Event',
                    prefixIcon: const Icon(Icons.event_rounded, size: 20),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Events')),
                    ..._events.map((e) => DropdownMenuItem(
                          value: e.eventKey,
                          child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedEventKey = val);
                  },
                ),
                const SizedBox(height: 10),
                // Team and Match number fields
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Team # or name',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) => setState(() => _teamQuery = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Match #',
                          prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) => setState(() => _matchQuery = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Discrepancy toggle and Sort dropdown
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        selected: _discrepanciesOnly,
                        showCheckmark: true,
                        checkmarkColor: Colors.black87,
                        label: const Text('Conflicts Only'),
                        avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orangeAccent),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _discrepanciesOnly ? Colors.black87 : Colors.orangeAccent,
                        ),
                        selectedColor: Colors.orangeAccent,
                        backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                        side: BorderSide(color: Colors.orangeAccent.withOpacity(0.4)),
                        onSelected: (val) => setState(() => _discrepanciesOnly = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sortBy,
                        decoration: InputDecoration(
                          labelText: 'Sort By',
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'match-asc', child: Text('Match (1 -> N)')),
                          DropdownMenuItem(value: 'match-desc', child: Text('Match (N -> 1)')),
                          DropdownMenuItem(value: 'team-asc', child: Text('Team #')),
                          DropdownMenuItem(value: 'date-desc', child: Text('Newest First')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _sortBy = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Reset and CSV export buttons
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _exportCsv,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('CSV'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${filtered.length} matches',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Matches List
          if (filtered.isEmpty)
            ObsidianGlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.sports_esports_outlined, size: 48, color: secondaryTextColor.withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text(
                        'No match scouting records found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text('Submit a match form or change your search filters.', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            )
          else
            ...filtered.map((record) {
              final teamObj = _teamsByNumber[record.targetTeamNumber];
              final teamName = teamObj?.nickname ?? 'Team ${record.targetTeamNumber}';
              final isSelected = _selectedRecord?.id == record.id;
              final conflicts = _getConflictingRecordsFor(record);
              final hasConflict = conflicts.length > 1 || record.hasDiscrepancy;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedRecord = isSelected ? null : record;
                    });
                    if (!isSelected) {
                      _showMatchDetailBottomSheet(context, record);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x731E293B) : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasConflict
                            ? Colors.orangeAccent.withOpacity(0.7)
                            : (isSelected
                                ? Colors.amberAccent
                                : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08))),
                        width: hasConflict || isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                              ),
                              child: Text(
                                'MATCH ${record.matchNumber}',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Team ${record.targetTeamNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: primaryTextColor,
                              ),
                            ),
                            const Spacer(),
                            if (hasConflict) ...[
                              InkWell(
                                onTap: () => _openConflictResolver(record),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orangeAccent),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orangeAccent),
                                      SizedBox(width: 4),
                                      Text(
                                        'Resolve',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white38),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                teamName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (record.scoutUsername != null)
                              Text(
                                'by ${record.scoutUsername}',
                                style: TextStyle(color: secondaryTextColor.withOpacity(0.8), fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showMatchDetailBottomSheet(BuildContext context, MatchScoutingRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        final teamObj = _teamsByNumber[record.targetTeamNumber];

        // Group fields by phase if config is present
        final autoFields = <ScoutingFieldModel>[];
        final teleopFields = <ScoutingFieldModel>[];
        final endgameFields = <ScoutingFieldModel>[];
        final otherFields = <ScoutingFieldModel>[];

        if (_matchConfig != null) {
          for (final f in _matchConfig!.fields) {
            final phase = f.phase?.toLowerCase();
            if (phase == 'auto') {
              autoFields.add(f);
            } else if (phase == 'teleop') {
              teleopFields.add(f);
            } else if (phase == 'endgame') {
              endgameFields.add(f);
            } else {
              otherFields.add(f);
            }
          }
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF50F172A) : const Color(0xF8F8FAFC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.sports_esports_rounded, color: Colors.amberAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Match ${record.matchNumber} • Team ${record.targetTeamNumber}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                teamObj?.nickname ?? 'Event: ${record.eventKey}',
                                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      children: [
                        if (_getConflictingRecordsFor(record).length > 1 || record.hasDiscrepancy)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Different match scouting data was recorded for this match.',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orangeAccent,
                                    foregroundColor: Colors.black87,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _openConflictResolver(record);
                                  },
                                  icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                                  label: const Text('Resolve'),
                                ),
                              ],
                            ),
                          ),

                        // Metadata
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow('Event Key', record.eventKey, primaryTextColor, secondaryTextColor),
                              if (record.scoutUsername != null)
                                _buildDetailRow('Scouted By', record.scoutUsername!, primaryTextColor, secondaryTextColor),
                              if (record.createdAt != null)
                                _buildDetailRow('Timestamp', record.createdAt!, primaryTextColor, secondaryTextColor),
                              if (record.hasDiscrepancy)
                                _buildDetailRow('Discrepancy Status', 'Conflict Flagged', Colors.orangeAccent, secondaryTextColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Phase Breakdown
                        if (autoFields.isNotEmpty)
                          _buildPhaseSection('Autonomous Phase', autoFields, record.data, Colors.cyanAccent, isDark, primaryTextColor, secondaryTextColor),
                        if (teleopFields.isNotEmpty)
                          _buildPhaseSection('Teleop Phase', teleopFields, record.data, Colors.amberAccent, isDark, primaryTextColor, secondaryTextColor),
                        if (endgameFields.isNotEmpty)
                          _buildPhaseSection('Endgame Phase', endgameFields, record.data, Colors.pinkAccent, isDark, primaryTextColor, secondaryTextColor),
                        if (otherFields.isNotEmpty)
                          _buildPhaseSection('Post-Match & Notes', otherFields, record.data, Colors.lightGreenAccent, isDark, primaryTextColor, secondaryTextColor),

                        // If no schema fields matched, show raw data map
                        if (autoFields.isEmpty && teleopFields.isEmpty && endgameFields.isEmpty && otherFields.isEmpty)
                          ...record.data.entries.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(item.key, style: TextStyle(fontWeight: FontWeight.w600, color: primaryTextColor)),
                                  Text(
                                    _formatVal(item.value),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPhaseSection(
    String title,
    List<ScoutingFieldModel> fields,
    Map<String, dynamic> data,
    Color accentColor,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...fields.map((f) {
          final val = data[f.id];
          if (val is String && val.startsWith('data:image/')) {
            return ObsidianImagePreviewCard(
              label: f.label.isNotEmpty ? f.label : f.id,
              imageSource: val,
              height: 180,
            );
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    f.label.isNotEmpty ? f.label : f.id,
                    style: TextStyle(fontSize: 13, color: primaryTextColor),
                  ),
                ),
                Text(
                  _formatVal(val),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: val != null && val != 0 && val != false ? accentColor : secondaryTextColor,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
          Text(value, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatVal(dynamic val) {
    if (val == null) return '--';
    if (val is bool) return val ? 'Yes' : 'No';
    if (val is List) return val.join(', ');
    if (val is String && val.startsWith('data:image/')) return '📷 [Photo]';
    return val.toString();
  }

  Widget _buildMetricTile(String title, String value, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x521E293B) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
