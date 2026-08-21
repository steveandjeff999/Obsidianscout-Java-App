import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/conflict_resolution_modal.dart';

class TeamPitCoverageItem {
  final int teamNumber;
  final String nickname;
  final bool hasPitData;
  final String? lastUpdated;
  final String? scoutUsername;
  final Map<String, dynamic> pitData;
  final String? entryId;

  TeamPitCoverageItem({
    required this.teamNumber,
    required this.nickname,
    required this.hasPitData,
    this.lastUpdated,
    this.scoutUsername,
    this.pitData = const {},
    this.entryId,
  });

  DateTime? get updatedDateTime {
    if (lastUpdated == null || lastUpdated!.isEmpty) return null;
    return DateTime.tryParse(lastUpdated!);
  }
}

class PitDataScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const PitDataScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<PitDataScreen> createState() => _PitDataScreenState();
}

class _PitDataScreenState extends State<PitDataScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<TeamPitCoverageItem> _coverageList = [];
  List<EventModel> _events = [];
  List<Map<String, dynamic>> _rawPitEntries = [];
  ScoutingConfigModel? _pitConfig;
  List<ScoutingFieldModel> _quickFieldOptions = [];

  // Filters State
  String _selectedEventKey = '';
  String _teamQuery = '';
  bool _missingOnly = false;
  bool _conflictsOnly = false;
  String _selectedQuickFieldId = '';
  TeamPitCoverageItem? _selectedTeam;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant PitDataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await widget.apiService.fetchSettings();
      final currentYear = settings?.year ?? DateTime.now().year;
      final targetEventKey = _selectedEventKey.isNotEmpty ? _selectedEventKey : (settings?.eventKey ?? '');

      final results = await Future.wait([
        widget.apiService.fetchPitConfig(),
        widget.apiService.fetchPitScoutingEntries(),
        widget.apiService.fetchEvents(year: currentYear),
        widget.apiService.fetchTeams(targetEventKey),
      ]);

      final pitCfg = results[0] as ScoutingConfigModel?;
      final pitRaw = results[1] as List<dynamic>;
      final events = results[2] as List<EventModel>;
      final teams = results[3] as List<TeamModel>;

      final rawList = <Map<String, dynamic>>[];
      final Map<int, Map<String, dynamic>> pitMap = {};
      final Map<int, String?> updateTimeMap = {};
      final Map<int, String?> scoutUserMap = {};
      final Map<int, String?> entryIdMap = {};

      for (final e in pitRaw) {
        if (e is Map<String, dynamic>) {
          final tNum = (e['targetTeamNumber'] as num?)?.toInt() ?? 0;
          final entryEvent = e['isPrescout'] == true ? 'prescout' : (e['eventKey']?.toString() ?? '');
          
          if (targetEventKey.isEmpty || entryEvent == targetEventKey || entryEvent == 'prescout') {
            if (tNum > 0) {
              rawList.add(e);
              pitMap[tNum] = e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : {};
              updateTimeMap[tNum] = e['createdAt']?.toString();
              scoutUserMap[tNum] = e['scoutUsername']?.toString() ?? e['username']?.toString();
              entryIdMap[tNum] = e['id']?.toString();
            }
          }
        }
      }

      // Build coverage items
      final List<TeamPitCoverageItem> items = [];
      for (final t in teams) {
        final hasData = pitMap.containsKey(t.teamNumber);
        items.add(TeamPitCoverageItem(
          teamNumber: t.teamNumber,
          nickname: t.nickname ?? 'Team ${t.teamNumber}',
          hasPitData: hasData,
          lastUpdated: updateTimeMap[t.teamNumber],
          scoutUsername: scoutUserMap[t.teamNumber],
          pitData: pitMap[t.teamNumber] ?? {},
          entryId: entryIdMap[t.teamNumber],
        ));
      }

      // Also include any teams that have pit entries but weren't in official team list
      for (final entry in pitMap.entries) {
        if (!items.any((i) => i.teamNumber == entry.key)) {
          items.add(TeamPitCoverageItem(
            teamNumber: entry.key,
            nickname: 'Team ${entry.key}',
            hasPitData: true,
            lastUpdated: updateTimeMap[entry.key],
            scoutUsername: scoutUserMap[entry.key],
            pitData: entry.value,
            entryId: entryIdMap[entry.key],
          ));
        }
      }

      // Extract valid quick fields
      final fields = pitCfg?.fields.where((f) => f.type != 'section').toList() ?? [];
      String defaultQuickField = '';
      if (fields.isNotEmpty) {
        defaultQuickField = fields.firstWhere(
          (f) => f.id.toLowerCase().contains('drivetrain') || f.id.toLowerCase().contains('drive'),
          orElse: () => fields.first,
        ).id;
      }

      if (mounted) {
        setState(() {
          _pitConfig = pitCfg;
          _rawPitEntries = rawList;
          _quickFieldOptions = fields;
          _coverageList = items;
          _events = events;
          if (_selectedEventKey.isEmpty) {
            _selectedEventKey = targetEventKey;
          }
          if (_selectedQuickFieldId.isEmpty) {
            _selectedQuickFieldId = defaultQuickField;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getConflictingEntriesForTeam(int teamNumber) {
    return _rawPitEntries.where((e) => ((e['targetTeamNumber'] as num?)?.toInt() ?? 0) == teamNumber).toList();
  }

  void _openConflictResolver(TeamPitCoverageItem item) {
    final conflicts = _getConflictingEntriesForTeam(item.teamNumber);
    if (conflicts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No duplicate pit submissions found for this team.')),
      );
      return;
    }

    final rawEntries = conflicts.map((c) => {
      'id': c['id']?.toString() ?? '',
      'scoutUsername': c['scoutUsername']?.toString() ?? c['username']?.toString() ?? 'Scouter',
      'createdAt': c['createdAt'],
      'data': c['data'] is Map ? Map<String, dynamic>.from(c['data'] as Map) : {},
      'targetTeamNumber': c['targetTeamNumber'] ?? item.teamNumber,
      'eventKey': c['eventKey'],
    }).toList();

    ConflictResolutionModal.show(
      context: context,
      apiService: widget.apiService,
      title: 'Pit Conflict: Team ${item.teamNumber}',
      subtitle: '${conflicts.length} scouter pit profiles submitted. Compare side-by-side.',
      type: 'pit',
      fields: _pitConfig?.fields ?? [],
      conflictingEntries: rawEntries,
      onResolved: _loadData,
    );
  }

  List<TeamPitCoverageItem> get _filteredTeams {
    final query = _teamQuery.trim().toLowerCase();

    final filtered = _coverageList.where((item) {
      if (_missingOnly && item.hasPitData) {
        return false;
      }
      if (_conflictsOnly) {
        final conflicts = _getConflictingEntriesForTeam(item.teamNumber);
        if (conflicts.length <= 1) return false;
      }
      if (query.isNotEmpty) {
        final numStr = item.teamNumber.toString();
        final name = item.nickname.toLowerCase();
        if (!numStr.contains(query) && !name.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
    return filtered;
  }

  void _exportCsv() {
    final items = _filteredTeams;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pit data to export')),
      );
      return;
    }

    final StringBuffer csv = StringBuffer();
    csv.writeln('TeamNumber,TeamName,Status,LastUpdated,Scout,PitDataJSON');

    for (final item in items) {
      final safeData = jsonEncode(item.pitData).replaceAll('"', '""');
      csv.writeln('${item.teamNumber},"${item.nickname}","${item.hasPitData ? 'Complete' : 'Missing'}","${item.lastUpdated ?? ""}","${item.scoutUsername ?? ""}","$safeData"');
    }

    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.cyanAccent,
        content: Text('Exported ${items.length} team pit records to clipboard as CSV!'),
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _teamQuery = '';
      _missingOnly = false;
      _selectedTeam = null;
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
                'Failed to load pit scouting data',
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

    final filtered = _filteredTeams;
    final totalTeams = _coverageList.length;
    final scoutedCount = _coverageList.where((i) => i.hasPitData).length;
    final coveragePercent = totalTeams > 0 ? ((scoutedCount / totalTeams) * 100).toStringAsFixed(0) : '0';

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
                    const Icon(Icons.build_circle_rounded, color: Colors.cyanAccent, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Pit Scouting Data',
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
                  'Review robot specifications, pit inspection coverage, and find un-scouted teams.',
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
                              Expanded(child: _buildMetricTile('Teams Scouted', '$scoutedCount / $totalTeams', Colors.cyanAccent, isDark)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildMetricTile('Coverage', '$coveragePercent%', coveragePercent == '100' ? Colors.greenAccent : Colors.tealAccent, isDark)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildMetricTile('Missing', '${totalTeams - scoutedCount}', (totalTeams - scoutedCount) > 0 ? Colors.orangeAccent : Colors.greenAccent, isDark),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _buildMetricTile('Teams Scouted', '$scoutedCount / $totalTeams', Colors.cyanAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Coverage', '$coveragePercent%', coveragePercent == '100' ? Colors.greenAccent : Colors.tealAccent, isDark)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMetricTile('Missing', '${totalTeams - scoutedCount}', (totalTeams - scoutedCount) > 0 ? Colors.orangeAccent : Colors.greenAccent, isDark)),
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
                  'Filters & Quick Field View',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                ),
                const SizedBox(height: 12),
                // Event selector
                DropdownButtonFormField<String>(
                  value: _events.any((e) => e.eventKey == _selectedEventKey) ? _selectedEventKey : (_events.isNotEmpty ? _events.first.eventKey : ''),
                  decoration: InputDecoration(
                    labelText: 'Event',
                    prefixIcon: const Icon(Icons.event_rounded, size: 20),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: _events.map((e) => DropdownMenuItem(
                        value: e.eventKey,
                        child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                      )).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedEventKey = val);
                      _loadData();
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Search row & Quick field selector
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search Team # or name',
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
                    if (_quickFieldOptions.isNotEmpty)
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          value: _quickFieldOptions.any((f) => f.id == _selectedQuickFieldId) ? _selectedQuickFieldId : _quickFieldOptions.first.id,
                          decoration: InputDecoration(
                            labelText: 'Quick Field',
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          isExpanded: true,
                          items: _quickFieldOptions.map((f) => DropdownMenuItem(
                                value: f.id,
                                child: Text(f.label.isNotEmpty ? f.label : f.id, overflow: TextOverflow.ellipsis),
                              )).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedQuickFieldId = val);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Missing toggle and Conflicts toggle
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected: _missingOnly,
                      showCheckmark: true,
                      checkmarkColor: Colors.black87,
                      label: const Text('Needs Pit Scouting'),
                      avatar: const Icon(Icons.incomplete_circle_rounded, size: 16, color: Colors.orangeAccent),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _missingOnly ? Colors.black87 : Colors.orangeAccent,
                      ),
                      selectedColor: Colors.orangeAccent,
                      backgroundColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                      side: BorderSide(color: Colors.orangeAccent.withOpacity(0.4)),
                      onSelected: (val) => setState(() => _missingOnly = val),
                    ),
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
                        color: Colors.cyanAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${filtered.length} teams',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Team Coverage List
          if (filtered.isEmpty)
            ObsidianGlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.build_circle_outlined, size: 48, color: secondaryTextColor.withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text(
                        'No teams found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text('Try adjusting your search query or filters.', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            )
          else
            ...filtered.map((item) {
              final isSelected = _selectedTeam?.teamNumber == item.teamNumber;
              final quickFieldVal = item.pitData[_selectedQuickFieldId];
              final quickFieldLabel = _quickFieldOptions.where((f) => f.id == _selectedQuickFieldId).firstOrNull?.label ?? _selectedQuickFieldId;
              final conflicts = _getConflictingEntriesForTeam(item.teamNumber);
              final hasConflict = conflicts.length > 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedTeam = isSelected ? null : item;
                    });
                    if (item.hasPitData) {
                      _showPitDetailBottomSheet(context, item);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('No pit profile recorded yet for Team ${item.teamNumber}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
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
                            ? Colors.amberAccent.withOpacity(0.7)
                            : (isSelected
                                ? Colors.cyanAccent
                                : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08))),
                        width: hasConflict || isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.hasPitData ? Colors.tealAccent.withOpacity(0.2) : Colors.orangeAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: item.hasPitData ? Colors.tealAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                item.hasPitData ? 'COMPLETE' : 'MISSING',
                                style: TextStyle(
                                  color: item.hasPitData ? Colors.tealAccent : Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Team ${item.teamNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: primaryTextColor,
                              ),
                            ),
                            const Spacer(),
                            if (hasConflict) ...[
                              InkWell(
                                onTap: () => _openConflictResolver(item),
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
                                item.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (quickFieldVal != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$quickFieldLabel: ${_formatVal(quickFieldVal)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.cyanAccent,
                                  ),
                                ),
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

  void _showPitDetailBottomSheet(BuildContext context, TeamPitCoverageItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

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
                            color: Colors.cyanAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.build_circle_rounded, color: Colors.cyanAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Team ${item.teamNumber} Pit Profile',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                item.nickname,
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
                        if (_getConflictingEntriesForTeam(item.teamNumber).length > 1)
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
                                    'Multiple pit scouting submissions exist for this team.',
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
                                    _openConflictResolver(item);
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
                              _buildDetailRow('Status', 'Complete', Colors.tealAccent, secondaryTextColor),
                              if (item.scoutUsername != null)
                                _buildDetailRow('Scouted By', item.scoutUsername!, primaryTextColor, secondaryTextColor),
                              if (item.lastUpdated != null)
                                _buildDetailRow('Last Updated', item.lastUpdated!, primaryTextColor, secondaryTextColor),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Robot Specs & Inspection Details',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 10),

                        if (_pitConfig != null && _pitConfig!.fields.isNotEmpty)
                          ..._pitConfig!.fields.map((f) {
                            if (f.type == 'section') {
                              return Padding(
                                padding: const EdgeInsets.only(top: 14, bottom: 6),
                                child: Text(
                                  f.label.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.cyanAccent,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              );
                            }

                            final val = item.pitData[f.id];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                      f.label.isNotEmpty ? f.label : f.id,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      _formatVal(val),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.cyanAccent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        else
                          ...item.pitData.entries.map((entry) {
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
                                  Text(entry.key, style: TextStyle(fontWeight: FontWeight.w600, color: primaryTextColor)),
                                  Text(
                                    _formatVal(entry.value),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent),
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

  String _formatVal(dynamic val) {
    if (val == null) return '--';
    if (val is bool) return val ? 'Yes' : 'No';
    if (val is List) return val.join(', ');
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
