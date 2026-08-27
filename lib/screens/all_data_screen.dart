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

class UnifiedScoutingEntry {
  final String id;
  final String originalId;
  final String type; // 'Match', 'Pit', 'Qualitative'
  final int targetTeamNumber;
  final String eventKey;
  final bool isPrescout;
  final int? matchNumber;
  final String? matchKey;
  final String? createdAt;
  final Map<String, dynamic> data;
  final bool hasDiscrepancy;
  final List<String> conflictingTeams;
  final String? scoutUsername;

  UnifiedScoutingEntry({
    required this.id,
    required this.originalId,
    required this.type,
    required this.targetTeamNumber,
    required this.eventKey,
    this.isPrescout = false,
    this.matchNumber,
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

class AllDataScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const AllDataScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<AllDataScreen> createState() => _AllDataScreenState();
}

class _AllDataScreenState extends State<AllDataScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<UnifiedScoutingEntry> _allEntries = [];
  List<EventModel> _events = [];
  Map<int, TeamModel> _teamsByNumber = {};
  ScoutingConfigModel? _matchConfig;
  ScoutingConfigModel? _pitConfig;
  ScoutingConfigModel? _qualConfig;

  // Filter State
  String _selectedEventKey = 'all';
  String _teamQuery = '';
  String _selectedType = 'all'; // 'all', 'match', 'pit', 'qualitative'
  String _matchNumberQuery = '';
  String _sortBy = 'newest'; // 'match-type', 'newest', 'oldest', 'team'
  bool _conflictsOnly = false;
  UnifiedScoutingEntry? _selectedEntry;

  List<UnifiedScoutingEntry> _getConflictingEntriesFor(UnifiedScoutingEntry entry) {
    return _allEntries.where((e) {
      if (e.type != entry.type) return false;
      if (e.targetTeamNumber != entry.targetTeamNumber) return false;
      if (e.eventKey != entry.eventKey) return false;
      if (e.type == 'Match' || e.type == 'Qualitative') {
        if (e.matchNumber != entry.matchNumber) return false;
      }
      return true;
    }).toList();
  }

  void _openConflictResolver(UnifiedScoutingEntry entry) {
    final conflicts = _getConflictingEntriesFor(entry);
    if (conflicts.length < 2 && !entry.hasDiscrepancy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No conflicting submissions found for this entry.')),
      );
      return;
    }

    final fields = entry.type == 'Pit'
        ? (_pitConfig?.fields ?? [])
        : (entry.type == 'Qualitative' ? (_qualConfig?.fields ?? []) : (_matchConfig?.fields ?? []));

    final rawEntries = conflicts.map((c) => {
      'id': c.originalId.isNotEmpty ? c.originalId : c.id,
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
      title: '${entry.type} Conflict: Team ${entry.targetTeamNumber}${entry.matchNumber != null ? ' (M${entry.matchNumber})' : ''}',
      subtitle: '${conflicts.length} conflicting submissions found. Compare and resolve.',
      type: entry.type == 'Pit' ? 'pit' : (entry.type == 'Qualitative' ? 'qual' : 'match'),
      fields: fields,
      conflictingEntries: rawEntries,
      onResolved: _loadData,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant AllDataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Hydration
    final cachedSettings = await widget.apiService.getCachedSettings();
    final cachedMatchCfg = await widget.apiService.getCachedMatchConfig();
    final cachedPitCfg = await widget.apiService.getCachedPitConfig();
    final cachedQualCfg = await widget.apiService.getCachedQualConfig();
    final cachedMatchRaw = await widget.apiService.getCachedScoutingEntries();
    final cachedPitRaw = await widget.apiService.getCachedPitScoutingEntries();
    final cachedQualRaw = await widget.apiService.getCachedQualScoutingEntries();
    final cachedEvents = await widget.apiService.getCachedEvents(year: cachedSettings?.year);
    final cachedTeams = await widget.apiService.getCachedTeams(cachedSettings?.eventKey);

    if (mounted && (cachedMatchRaw.isNotEmpty || cachedPitRaw.isNotEmpty || cachedQualRaw.isNotEmpty || cachedTeams.isNotEmpty)) {
      final Map<int, TeamModel> teamMap = {};
      for (final t in cachedTeams) {
        teamMap[t.teamNumber] = t;
      }

      final List<UnifiedScoutingEntry> combined = [];
      for (final e in cachedMatchRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'match-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Match',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            matchNumber: (e['matchNumber'] as num?)?.toInt(),
            matchKey: e['matchKey']?.toString(),
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            hasDiscrepancy: e['hasDiscrepancy'] == true,
            conflictingTeams: (e['conflictingTeams'] as List?)?.map((c) => c.toString()).toList() ?? [],
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      for (final e in cachedPitRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'pit-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Pit',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      for (final e in cachedQualRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'qual-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Qualitative',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            matchNumber: (e['matchNumber'] as num?)?.toInt(),
            matchKey: e['matchKey']?.toString(),
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      setState(() {
        _matchConfig = cachedMatchCfg;
        _pitConfig = cachedPitCfg;
        _qualConfig = cachedQualCfg;
        _allEntries = combined;
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
        widget.apiService.fetchPitConfig(),
        widget.apiService.fetchQualConfig(),
        widget.apiService.fetchScoutingEntries(),
        widget.apiService.fetchPitScoutingEntries(),
        widget.apiService.fetchQualScoutingEntries(),
        widget.apiService.fetchEvents(year: currentYear),
        widget.apiService.fetchTeams(settings?.eventKey ?? ''),
      ]);

      final matchCfg = results[0] as ScoutingConfigModel?;
      final pitCfg = results[1] as ScoutingConfigModel?;
      final qualCfg = results[2] as ScoutingConfigModel?;
      final matchRaw = results[3] as List<dynamic>;
      final pitRaw = results[4] as List<dynamic>;
      final qualRaw = results[5] as List<dynamic>;
      final events = results[6] as List<EventModel>;
      final teams = results[7] as List<TeamModel>;

      final Map<int, TeamModel> teamMap = {};
      for (final t in teams) {
        teamMap[t.teamNumber] = t;
      }

      final List<UnifiedScoutingEntry> combined = [];

      for (final e in matchRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'match-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Match',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            matchNumber: (e['matchNumber'] as num?)?.toInt(),
            matchKey: e['matchKey']?.toString(),
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            hasDiscrepancy: e['hasDiscrepancy'] == true,
            conflictingTeams: (e['conflictingTeams'] as List?)?.map((c) => c.toString()).toList() ?? [],
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      for (final e in pitRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'pit-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Pit',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      for (final e in qualRaw) {
        if (e is Map<String, dynamic>) {
          final isPrescout = e['isPrescout'] == true;
          combined.add(UnifiedScoutingEntry(
            id: 'qual-${e['id']}',
            originalId: e['id']?.toString() ?? '',
            type: 'Qualitative',
            targetTeamNumber: (e['targetTeamNumber'] as num?)?.toInt() ?? 0,
            eventKey: isPrescout ? 'prescout' : (e['eventKey']?.toString() ?? ''),
            isPrescout: isPrescout,
            matchNumber: (e['matchNumber'] as num?)?.toInt(),
            matchKey: e['matchKey']?.toString(),
            createdAt: e['createdAt']?.toString(),
            data: e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {},
            scoutUsername: e['scoutUsername']?.toString() ?? e['username']?.toString(),
          ));
        }
      }

      if (mounted) {
        setState(() {
          _matchConfig = matchCfg ?? _matchConfig;
          _pitConfig = pitCfg ?? _pitConfig;
          _qualConfig = qualCfg ?? _qualConfig;
          if (combined.isNotEmpty) _allEntries = combined;
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

  List<UnifiedScoutingEntry> get _filteredEntries {
    final query = _teamQuery.trim().toLowerCase();
    final matchQ = int.tryParse(_matchNumberQuery.trim());

    final filtered = _allEntries.where((e) {
      if (_selectedEventKey != 'all' && _selectedEventKey.isNotEmpty) {
        if (e.eventKey != _selectedEventKey) return false;
      }
      if (_selectedType != 'all' && e.type.toLowerCase() != _selectedType.toLowerCase()) {
        return false;
      }
      if (_conflictsOnly) {
        final conflicts = _getConflictingEntriesFor(e);
        if (conflicts.length <= 1 && !e.hasDiscrepancy) return false;
      }
      if (query.isNotEmpty) {
        final teamStr = e.targetTeamNumber.toString();
        final teamObj = _teamsByNumber[e.targetTeamNumber];
        final name = teamObj?.nickname?.toLowerCase() ?? '';
        if (!teamStr.contains(query) && !name.contains(query)) {
          return false;
        }
      }
      if (matchQ != null && e.matchNumber != null) {
        if (e.matchNumber != matchQ) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return da.compareTo(db);
        case 'team':
          return a.targetTeamNumber.compareTo(b.targetTeamNumber);
        case 'match-type':
          final ma = a.matchNumber ?? 0;
          final mb = b.matchNumber ?? 0;
          if (ma != mb) return ma.compareTo(mb);
          return a.type.compareTo(b.type);
        case 'newest':
        default:
          final da = a.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
      }
    });

    return filtered;
  }

  void _exportCsv() {
    final entries = _filteredEntries;
    if (entries.isEmpty) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Export Unavailable',
        message: 'No scouting entries match the current filters to export.',
      );
      return;
    }

    final exportData = CsvExportService.exportUnifiedData(
      entries: entries,
      matchConfig: _matchConfig,
      pitConfig: _pitConfig,
      qualConfig: _qualConfig,
      eventKey: _selectedEventKey != 'all' ? _selectedEventKey : null,
    );

    CsvExportModal.show(
      context,
      title: 'Export All Scouting Data',
      exportData: exportData,
    );
  }

  void _resetFilters() {
    setState(() {
      _teamQuery = '';
      _selectedType = 'all';
      _matchNumberQuery = '';
      _sortBy = 'newest';
      _conflictsOnly = false;
      _selectedEntry = null;
    });
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Match':
        return Colors.amberAccent;
      case 'Pit':
        return Colors.cyanAccent;
      case 'Qualitative':
        return Colors.lightGreenAccent;
      default:
        return Colors.white70;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'Match':
        return Icons.sports_esports_rounded;
      case 'Pit':
        return Icons.build_circle_rounded;
      case 'Qualitative':
        return Icons.rate_review_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
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
                'Failed to load scouting data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondaryTextColor, fontSize: 13),
              ),
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

    final filtered = _filteredEntries;
    final totalCount = _allEntries.length;
    final pitCount = _allEntries.where((e) => e.type == 'Pit').length;
    final matchCount = _allEntries.where((e) => e.type == 'Match').length;
    final qualCount = _allEntries.where((e) => e.type == 'Qualitative').length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 24.0),
        children: [
          // Header Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dataset_rounded, color: ObsidianUITheme.primaryAccent, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'All Scouting Data',
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
                  'Browse, search, and inspect pit, match, and qualitative scouting entries in one unified place.',
                  style: TextStyle(color: secondaryTextColor, fontSize: 13),
                ),
                const SizedBox(height: 18),
                // Metrics grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Total Entries', totalCount.toString(), Colors.blueAccent, isDark)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildMetricTile('Pit Entries', pitCount.toString(), Colors.cyanAccent, isDark)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Match Entries', matchCount.toString(), Colors.amberAccent, isDark)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildMetricTile('Qualitative', qualCount.toString(), Colors.lightGreenAccent, isDark)),
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _buildMetricTile('Total Entries', totalCount.toString(), Colors.blueAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Pit Entries', pitCount.toString(), Colors.cyanAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Match Entries', matchCount.toString(), Colors.amberAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Qualitative', qualCount.toString(), Colors.lightGreenAccent, isDark)),
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
                Row(
                  children: [
                    Text(
                      'Filters & Search',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                    ),
                    const Spacer(),
                    FilterChip(
                      selected: _conflictsOnly,
                      showCheckmark: true,
                      checkmarkColor: Colors.black87,
                      label: const Text('Conflicts Only'),
                      avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amberAccent),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _conflictsOnly ? Colors.black87 : Colors.amberAccent,
                      ),
                      selectedColor: Colors.amberAccent,
                      backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                      side: BorderSide(color: Colors.amberAccent.withOpacity(0.4)),
                      onSelected: (val) => setState(() => _conflictsOnly = val),
                    ),
                  ],
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
                // Search row: Team & Match number
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
                        onChanged: (val) => setState(() => _matchNumberQuery = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Type selector & Sort dropdown
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          labelText: 'Type',
                          filled: true,
                          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Types')),
                          DropdownMenuItem(value: 'match', child: Text('Match')),
                          DropdownMenuItem(value: 'pit', child: Text('Pit')),
                          DropdownMenuItem(value: 'qualitative', child: Text('Qualitative')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedType = val);
                        },
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
                          DropdownMenuItem(value: 'newest', child: Text('Newest')),
                          DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                          DropdownMenuItem(value: 'team', child: Text('Team #')),
                          DropdownMenuItem(value: 'match-type', child: Text('Match & Type')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _sortBy = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Buttons & Status Badge
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
                        color: ObsidianUITheme.primaryAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ObsidianUITheme.primaryAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${filtered.length} entries',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: ObsidianUITheme.primaryAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Entries List
          if (filtered.isEmpty)
            ObsidianGlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_rounded, size: 48, color: secondaryTextColor.withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text(
                        'No scouting entries found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing filters or syncing with the server.',
                        style: TextStyle(color: secondaryTextColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...filtered.map((entry) {
              final isSelected = _selectedEntry?.id == entry.id;
              final teamObj = _teamsByNumber[entry.targetTeamNumber];
              final teamName = teamObj?.nickname ?? 'Team ${entry.targetTeamNumber}';
              final typeColor = _getTypeColor(entry.type);
              final conflicts = _getConflictingEntriesFor(entry);
              final hasConflict = conflicts.length > 1 || entry.hasDiscrepancy;
              final imageVal = entry.data.values.where((v) => v is String && v.startsWith('data:image/')).firstOrNull?.toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedEntry = isSelected ? null : entry;
                    });
                    if (!isSelected) {
                      _showEntryDetailBottomSheet(context, entry);
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
                            ? Colors.amberAccent.withOpacity(0.6)
                            : (isSelected
                                ? ObsidianUITheme.primaryAccent
                                : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08))),
                        width: hasConflict || isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (imageVal != null) ...[
                          ObsidianImageThumbnail(
                            imageSource: imageVal,
                            size: 46,
                            title: 'Team ${entry.targetTeamNumber} Photo',
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Type Tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: typeColor.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: typeColor.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_getTypeIcon(entry.type), size: 14, color: typeColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          entry.type.toUpperCase(),
                                          style: TextStyle(
                                            color: typeColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Team Badge
                                  Text(
                                    'Team ${entry.targetTeamNumber}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  if (entry.matchNumber != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Match ${entry.matchNumber}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (hasConflict) ...[
                                    InkWell(
                                      onTap: () => _openConflictResolver(entry),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amberAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amberAccent),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amberAccent),
                                            SizedBox(width: 4),
                                            Text(
                                              'Resolve',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amberAccent,
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
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (entry.createdAt != null)
                                    Text(
                                      _formatDate(entry.createdDateTime),
                                      style: TextStyle(color: secondaryTextColor.withOpacity(0.7), fontSize: 11),
                                    ),
                                ],
                              ),
                            ],
                          ),
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

  void _showEntryDetailBottomSheet(BuildContext context, UnifiedScoutingEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        final teamObj = _teamsByNumber[entry.targetTeamNumber];

        ScoutingConfigModel? relevantConfig;
        if (entry.type == 'Match') relevantConfig = _matchConfig;
        if (entry.type == 'Pit') relevantConfig = _pitConfig;
        if (entry.type == 'Qualitative') relevantConfig = _qualConfig;

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
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
                  // Drag handle
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
                            color: _getTypeColor(entry.type).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_getTypeIcon(entry.type), color: _getTypeColor(entry.type), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Team ${entry.targetTeamNumber} • ${entry.type}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                teamObj?.nickname ?? 'Event: ${entry.eventKey}',
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
                        if (_getConflictingEntriesFor(entry).length > 1 || entry.hasDiscrepancy)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 22),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Discrepancy detected for this entry across submissions.',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amberAccent,
                                    foregroundColor: Colors.black87,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _openConflictResolver(entry);
                                  },
                                  icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                                  label: const Text('Resolve'),
                                ),
                              ],
                            ),
                          ),

                        // Metadata card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (entry.matchNumber != null)
                                _buildDetailRow('Match Number', 'Match ${entry.matchNumber}', primaryTextColor, secondaryTextColor),
                              _buildDetailRow('Event Key', entry.eventKey, primaryTextColor, secondaryTextColor),
                              if (entry.scoutUsername != null && entry.scoutUsername!.isNotEmpty)
                                _buildDetailRow('Scouted By', entry.scoutUsername!, primaryTextColor, secondaryTextColor),
                              if (entry.createdAt != null)
                                _buildDetailRow('Timestamp', entry.createdAt!, primaryTextColor, secondaryTextColor),
                              if (entry.isPrescout)
                                _buildDetailRow('Prescout', 'Yes', Colors.cyanAccent, secondaryTextColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Recorded Answers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 10),
                        if (entry.data.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Center(
                              child: Text('No custom fields recorded for this entry.', style: TextStyle(color: secondaryTextColor)),
                            ),
                          )
                        else
                          ...entry.data.entries.map((item) {
                            final fieldKey = item.key;
                            final fieldVal = item.value;

                            // Lookup label in relevant config if possible
                            String displayLabel = fieldKey;
                            if (relevantConfig != null) {
                              final found = relevantConfig.fields.where((f) => f.id == fieldKey).firstOrNull;
                              if (found != null && found.label.isNotEmpty) {
                                displayLabel = found.label;
                              }
                            }

                            if (fieldVal is String && fieldVal.startsWith('data:image/')) {
                              return ObsidianImagePreviewCard(
                                label: displayLabel,
                                imageSource: fieldVal,
                                height: 180,
                              );
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      displayLabel,
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: primaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      _formatValue(fieldVal),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: ObsidianUITheme.primaryAccent,
                                      ),
                                    ),
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

  String _formatValue(dynamic val) {
    if (val == null) return '--';
    if (val is bool) return val ? 'Yes' : 'No';
    if (val is List) return val.join(', ');
    if (val is String && val.startsWith('data:image/')) return '📷 [Photo]';
    return val.toString();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '--';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
