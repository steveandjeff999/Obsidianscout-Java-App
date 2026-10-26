import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/assignment_models.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../services/net/adaptive_timer.dart';

class ScoutAssignmentsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ScoutAssignmentsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ScoutAssignmentsScreen> createState() => _ScoutAssignmentsScreenState();
}

class _ScoutAssignmentsScreenState extends State<ScoutAssignmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _pollTimer;

  String? _currentEventKey;
  List<ScoutingAssignment> _assignments = [];
  List<MatchModel> _matches = [];
  List<TeamModel> _teams = [];
  List<UserModel> _users = [];
  List<EventModel> _events = [];
  List<PitScoutGroup> _pitGroups = [];

  _AssignmentIndex _index = _AssignmentIndex.empty();

  bool _isLoading = true;
  bool _isModalOpen = false;

  // Filter state for Tab 2 (List View)
  String _filterType = '';
  String _filterScouter = '';
  String _filterStatus = '';
  String _filterSearch = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pitSearchController = TextEditingController();

  // Stage filters for Matrix tabs
  String _matrixStage = 'all'; // all, qm, pr, playoffs
  String _qualMatrixStage = 'all';
  String _pitFilter = 'all'; // all, unassigned, assigned, completed, conflicts

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant ScoutAssignmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _startPolling();
      _loadEventData();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _pitSearchController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!widget.isVisible) return;
    _pollTimer = AdaptiveTimer(const Duration(seconds: 20), (_) {
      if (mounted && widget.isVisible && !_isModalOpen && widget.apiService.isOnline) {
        _pollAssignmentsSilently();
      }
    });
  }

  void _recomputeIndex() {
    _index = _AssignmentIndex.compute(_assignments, _matches);
  }

  bool _areAssignmentsEqual(List<ScoutingAssignment> a, List<ScoutingAssignment> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].status != b[i].status ||
          a[i].assignedUserId != b[i].assignedUserId ||
          a[i].targetTeamNumber != b[i].targetTeamNumber ||
          a[i].matchKey != b[i].matchKey ||
          a[i].allianceColor != b[i].allianceColor ||
          a[i].scoutGroup != b[i].scoutGroup ||
          a[i].notes != b[i].notes) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadInitialData() async {
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    _currentEventKey = cachedEventKey;

    // Cache hydration
    final cachedAssignments = await widget.apiService.getCachedAllAssignments(cachedEventKey);
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);
    final cachedMatches = await widget.apiService.getCachedMatches(cachedEventKey);

    if (mounted && cachedAssignments.isNotEmpty) {
      setState(() {
        _assignments = cachedAssignments;
        _teams = cachedTeams;
        _matches = cachedMatches;
        _recomputeIndex();
        _isLoading = false;
      });
    }

    // Load users & events list
    try {
      final events = await widget.apiService.fetchEvents();
      if (mounted) {
        setState(() => _events = events);
      }
    } catch (_) {}

    await _loadUsers();
    await _loadPitGroups();
    await _loadEventData();
  }

  Future<void> _loadPitGroups() async {
    final groups = await widget.apiService.fetchPitScoutGroups();
    if (mounted) setState(() => _pitGroups = groups);
  }

  Future<void> _loadUsers() async {
    try {
      final me = widget.apiService.currentUser;
      final activeTeam = me?.teamNumber ?? 0;
      final activeProgram = widget.apiService.currentProgram;

      final list = await widget.apiService.fetchTeamMembers(
        teamNumber: activeTeam > 0 ? activeTeam : null,
        program: activeProgram.isNotEmpty ? activeProgram : null,
      );

      if (mounted && list.isNotEmpty) {
        setState(() {
          _users = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadEventData() async {
    if (_currentEventKey == null || _currentEventKey!.isEmpty) {
      _currentEventKey = await widget.apiService.fetchCurrentEventKey();
    }
    if (_currentEventKey == null || _currentEventKey!.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        widget.apiService.fetchAllAssignments(_currentEventKey),
        widget.apiService.fetchTeams(_currentEventKey),
        widget.apiService.fetchMatches(_currentEventKey),
      ]);

      if (!mounted) return;

      setState(() {
        _assignments = results[0] as List<ScoutingAssignment>;
        _teams = results[1] as List<TeamModel>;
        _matches = (results[2] as List<MatchModel>)..sort(MatchModel.compareMatches);
        _recomputeIndex();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pollAssignmentsSilently() async {
    if (_currentEventKey == null || _currentEventKey!.isEmpty) return;
    try {
      final results = await widget.apiService.fetchAllAssignments(_currentEventKey);
      if (mounted) {
        if (_areAssignmentsEqual(_assignments, results)) return;
        setState(() {
          _assignments = results;
          _recomputeIndex();
        });
      }
    } catch (_) {}
  }

  // Helper match filtering
  List<MatchModel> _getFilteredMatches(String stage) {
    List<MatchModel> list;
    if (stage == 'all') {
      list = List.from(_matches);
    } else {
      list = _matches.where((m) {
        final lvl = m.compLevel.toLowerCase();
        final key = m.matchKey.toLowerCase();
        if (stage == 'qm') return lvl == 'qm' || key.contains('_qm');
        if (stage == 'pr') return lvl == 'pr' || lvl == 'practice' || key.contains('_pr') || key.contains('_practice');
        if (stage == 'playoffs') {
          return lvl == 'qf' ||
              lvl == 'sf' ||
              lvl == 'f' ||
              lvl == 'playoff' ||
              key.contains('_qf') ||
              key.contains('_sf') ||
              key.contains('_f');
        }
        return true;
      }).toList();
    }
    list.sort(MatchModel.compareMatches);
    return list;
  }

  Future<void> _autoResolveAllConflicts() async {
    final toDelete = _index.conflictIdsToDelete.toList();
    if (toDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No conflicts found to resolve!')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: const Text('Auto-Resolve Conflicts'),
        content: Text(
          'Found ${toDelete.length} duplicate/conflicting assignment(s). Safe resolution will keep completed and primary assignments and clear duplicates. Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.primaryAccent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resolve Now'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final res = await widget.apiService.autoResolveConflicts(_currentEventKey ?? '');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message.isNotEmpty
                ? res.message
                : 'Auto-resolved ${res.resolvedCount} conflict(s)!'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      _loadEventData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    if (!widget.apiService.isAdmin) {
      return Center(
        child: Text(
          'Admin access required for assignment management.',
          style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
        ),
      );
    }

    final topPadding = 12.0;
    final bottomPadding = widget.isBarsVisible ? 120.0 : 24.0;

    final conflictCount = _index.totalConflictCount;

    return RefreshIndicator(
      onRefresh: _loadEventData,
      color: ObsidianUITheme.primaryAccent,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: topPadding,
              left: 16.0,
              right: 16.0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(conflictCount),
                  const SizedBox(height: 16),
                  _buildTabBar(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          ..._buildActiveTabSlivers(),
          SliverToBoxAdapter(
            child: SizedBox(height: bottomPadding),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(int conflictCount) {
    final pendingCount = _assignments.where((a) => a.status == 'PENDING').length;
    final inProgressCount =
        _assignments.where((a) => a.status == 'IN_PROGRESS').length;
    final completedCount =
        _assignments.where((a) => a.status == 'COMPLETED').length;

    return ObsidianGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('nav.scout_assignments', 'Scout Assignments'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: ObsidianUITheme.getPrimaryTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage, rotate, and monitor scout coverage',
                      style: TextStyle(
                        fontSize: 12,
                        color: ObsidianUITheme.getSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (_events.isNotEmpty)
                DropdownButton<String>(
                  value: _currentEventKey,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  underline: const SizedBox.shrink(),
                  items: _events.map((e) {
                    return DropdownMenuItem(
                      value: e.eventKey,
                      child: Text(
                        e.eventKey.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null && val != _currentEventKey) {
                      setState(() {
                        _currentEventKey = val;
                        _isLoading = true;
                      });
                      _loadEventData();
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          // KPI Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKpiChip('Total', _assignments.length, Colors.cyanAccent),
                const SizedBox(width: 8),
                _buildKpiChip('Pending', pendingCount, const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _buildKpiChip('In Progress', inProgressCount, const Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                _buildKpiChip('Completed', completedCount, const Color(0xFF10B981)),
                if (conflictCount > 0) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: conflictCount == 1
                        ? '1 conflict detected across matches. Click to auto-resolve safely.'
                        : '$conflictCount conflicts detected across matches. Click to auto-resolve safely.',
                    waitDuration: const Duration(milliseconds: 250),
                    child: InkWell(
                      onTap: _autoResolveAllConflicts,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFEF4444)),
                            const SizedBox(width: 4),
                            Text(
                              'Resolve Conflicts ($conflictCount)',
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _openCreateEditModal(),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Bulk Wizard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _openBulkWizardModal(),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(context.tr('assignments.shifts_btn', 'Planned Shifts'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _openPlannedShiftsModal(),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.build_circle_rounded, size: 18),
                label: const Text('Auto-Assign Pit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _openPitAutoModal(),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text('Pit Groups', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _openPitGroupsModal(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
          border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.6)),
        ),
        labelColor: ObsidianUITheme.primaryAccent,
        unselectedLabelColor: ObsidianUITheme.getSecondaryTextColor(context),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        tabs: const [
          Tab(text: 'Match Matrix'),
          Tab(text: 'Qual Matrix'),
          Tab(text: 'Assignments List'),
          Tab(text: 'Pit Coverage'),
        ],
        onTap: (_) => setState(() {}),
      ),
    );
  }

  List<Widget> _buildActiveTabSlivers() {
    if (_isLoading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }

    switch (_tabController.index) {
      case 0:
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverToBoxAdapter(child: _buildMatchMatrixTab()),
          ),
        ];
      case 1:
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverToBoxAdapter(child: _buildQualMatrixTab()),
          ),
        ];
      case 2:
        return _buildAssignmentsListSlivers();
      case 3:
        return _buildPitCoverageSlivers();
      default:
        return const [];
    }
  }

  // ==========================================
  // TAB 0: MATCH MATRIX
  // ==========================================
  Widget _buildMatchMatrixTab() {
    final matches = _getFilteredMatches(_matrixStage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStageFilterRow(_matrixStage, (s) => setState(() => _matrixStage = s)),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          const ObsidianGlassCard(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No matches found for this stage.')),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columnSpacing: 12,
                    horizontalMargin: 8,
                    headingRowColor: WidgetStateProperty.all(
                      ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.8),
                    ),
                    columns: const [
                      DataColumn(label: Text('Match', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 1', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 2', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 3', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 1', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 2', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 3', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                    ],
                    rows: matches.map((m) {
                      final label = m.shortLabel;
                      final hasConflict = _index.hasMatchConflict(m, 'MATCH');
                      final matchTooltip = _index.getMatchConflictTooltip(m, 'MATCH');

                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasConflict) ...[
                                  Tooltip(
                                    message: matchTooltip ?? 'Conflict detected in this match.\nClick conflicted slots to resolve.',
                                    preferBelow: false,
                                    waitDuration: const Duration(milliseconds: 200),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: hasConflict ? const Color(0xFFEF4444) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildSlotDataCell(m, 0, 'RED'),
                          _buildSlotDataCell(m, 1, 'RED'),
                          _buildSlotDataCell(m, 2, 'RED'),
                          _buildSlotDataCell(m, 0, 'BLUE'),
                          _buildSlotDataCell(m, 1, 'BLUE'),
                          _buildSlotDataCell(m, 2, 'BLUE'),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  DataCell _buildSlotDataCell(
    MatchModel match,
    int slotIndex,
    String alliance,
  ) {
    final teamKeys = alliance == 'RED' ? match.redTeams : match.blueTeams;
    if (slotIndex >= teamKeys.length) {
      return const DataCell(Text('—', style: TextStyle(color: Colors.grey)));
    }

    final tKey = teamKeys[slotIndex];
    final teamNum = int.tryParse(tKey.replaceAll(RegExp(r'[^0-9]'), ''));
    if (teamNum == null) {
      return const DataCell(Text('—', style: TextStyle(color: Colors.grey)));
    }

    final matching = _index.getMatchSlot(match, teamNum);

    final isConflict = matching.length > 1;
    final isAssigned = matching.length == 1;
    final asgn = isAssigned ? matching.first : null;
    final isDone = asgn?.status == 'COMPLETED';

    final scouterName = asgn?.assignedUserDisplayName ??
        asgn?.assignedUsername ??
        (isConflict ? '${matching.length} Scouts (Fix)' : '+ Assign');

    final slotKey = 'MATCH:${match.matchKey}:$teamNum';
    final slotTooltip = isConflict
        ? (_index.getSlotConflictTooltip(slotKey) ??
            'Conflict: Multiple scouts assigned to Team #$teamNum in ${match.shortLabel}.\nClick to resolve.')
        : (isAssigned
            ? 'Team #$teamNum: Assigned to @$scouterName (Status: ${asgn?.status ?? "PENDING"})\nClick to edit'
            : 'Team #$teamNum: Unassigned in ${match.shortLabel}\nClick to assign');

    final color = isConflict
        ? const Color(0xFFEF4444)
        : (isDone
            ? const Color(0xFF10B981)
            : (isAssigned ? (alliance == 'RED' ? Colors.redAccent : Colors.blueAccent) : Colors.grey));

    return DataCell(
      Tooltip(
        message: slotTooltip,
        waitDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: () {
            if (isConflict) {
              _openConflictResolverModal(matching, title: '${match.matchKey} - Team #$teamNum');
            } else if (isAssigned) {
              _openCreateEditModal(asgn: asgn);
            } else {
              _openCreateEditModal(
                defaultType: 'MATCH',
                defaultMatchKey: match.matchKey,
                defaultMatchNumber: match.matchNumber,
                defaultTeamNumber: teamNum,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: isAssigned || isConflict ? 0.8 : 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isConflict) ...[
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFEF4444)),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      '#$teamNum',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                Text(
                  scouterName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isAssigned || isConflict ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: QUALITATIVE MATRIX
  // ==========================================
  Widget _buildQualMatrixTab() {
    final matches = _getFilteredMatches(_qualMatrixStage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStageFilterRow(_qualMatrixStage, (s) => setState(() => _qualMatrixStage = s)),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          const ObsidianGlassCard(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No matches found for this stage.')),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columnSpacing: 12,
                    horizontalMargin: 8,
                    headingRowColor: WidgetStateProperty.all(
                      ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.8),
                    ),
                    columns: const [
                      DataColumn(label: Text('Match', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red Alliance', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue Alliance', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 1 (Qual)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 2 (Qual)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Red 3 (Qual)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 1 (Qual)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 2 (Qual)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Blue 3 (Qual)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                    ],
                    rows: matches.map((m) {
                      final label = m.shortLabel;
                      final hasConflict = _index.hasMatchConflict(m, 'QUALITATIVE');
                      final matchTooltip = _index.getMatchConflictTooltip(m, 'QUALITATIVE');

                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasConflict) ...[
                                  Tooltip(
                                    message: matchTooltip ?? 'Conflict detected in this match.\nClick conflicted slots to resolve.',
                                    preferBelow: false,
                                    waitDuration: const Duration(milliseconds: 200),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: hasConflict ? const Color(0xFFEF4444) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildQualAllianceDataCell(m, 'RED'),
                          _buildQualAllianceDataCell(m, 'BLUE'),
                          _buildQualTeamDataCell(m, 0, 'RED'),
                          _buildQualTeamDataCell(m, 1, 'RED'),
                          _buildQualTeamDataCell(m, 2, 'RED'),
                          _buildQualTeamDataCell(m, 0, 'BLUE'),
                          _buildQualTeamDataCell(m, 1, 'BLUE'),
                          _buildQualTeamDataCell(m, 2, 'BLUE'),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  DataCell _buildQualAllianceDataCell(
    MatchModel match,
    String alliance,
  ) {
    final matchingAlliance = _index.getQualAlliance(match, alliance);
    final teamKeys = alliance == 'RED' ? match.redTeams : match.blueTeams;
    final teamNums = teamKeys.map((k) => int.tryParse(k.replaceAll(RegExp(r'[^0-9]'), ''))).whereType<int>().toList();
    final matchingTeams = teamNums.expand((t) => _index.getQualTeam(match, t)).toList();

    final isConflict = matchingAlliance.length > 1 || (matchingAlliance.isNotEmpty && matchingTeams.isNotEmpty);
    final isAssigned = matchingAlliance.length == 1;
    final asgn = isAssigned ? matchingAlliance.first : null;
    final isDone = asgn?.status == 'COMPLETED';

    String scouterName;
    if (isConflict) {
      if (matchingAlliance.length > 1) {
        scouterName = '${matchingAlliance.length} Scouts (Fix)';
      } else {
        scouterName = 'Conflict: Alliance + Team';
      }
    } else if (isAssigned) {
      scouterName = '${asgn!.assignedUserDisplayName ?? asgn.assignedUsername} (All)';
    } else if (matchingTeams.isNotEmpty) {
      scouterName = '${matchingTeams.length}/${teamNums.length} Teams Indiv.';
    } else {
      scouterName = '+ $alliance Qual';
    }

    final allianceSlotKey = 'QUAL:${match.matchKey.toLowerCase()}:alliance_${alliance.toLowerCase()}';
    final allianceTooltip = isConflict
        ? (_index.getSlotConflictTooltip(allianceSlotKey) ??
            'Conflict: $alliance Alliance qualitative coverage overlaps with individual team scouts.\nClick to resolve.')
        : (isAssigned
            ? '$alliance Alliance: Assigned to @${asgn?.assignedUserDisplayName ?? asgn?.assignedUsername} (Status: ${asgn?.status ?? "PENDING"})\nClick to edit'
            : (matchingTeams.isNotEmpty
                ? '$alliance Alliance: Covered by individual team scouts (${matchingTeams.length}/${teamNums.length})\nClick to manage'
                : '$alliance Alliance: Unassigned in ${match.shortLabel}\nClick to assign whole alliance'));

    final color = isConflict
        ? const Color(0xFFEF4444)
        : (isDone
            ? const Color(0xFF10B981)
            : (isAssigned ? (alliance == 'RED' ? Colors.redAccent : Colors.blueAccent) : Colors.grey));

    return DataCell(
      Tooltip(
        message: allianceTooltip,
        waitDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: () {
            if (isConflict) {
              final allConflicted = [...matchingAlliance, ...matchingTeams];
              _openConflictResolverModal(allConflicted, title: '${match.shortLabel} - $alliance Alliance Qual');
            } else if (isAssigned) {
              _openCreateEditModal(asgn: asgn);
            } else {
              _openCreateEditModal(
                defaultType: 'QUALITATIVE',
                defaultMatchKey: match.matchKey,
                defaultMatchNumber: match.matchNumber,
                defaultAlliance: alliance,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: isAssigned || isConflict ? 0.8 : 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isConflict) ...[
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFEF4444)),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      '$alliance ALLIANCE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                Text(
                  scouterName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isAssigned || isConflict ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataCell _buildQualTeamDataCell(
    MatchModel match,
    int slotIndex,
    String alliance,
  ) {
    final teamKeys = alliance == 'RED' ? match.redTeams : match.blueTeams;
    if (slotIndex >= teamKeys.length) {
      return const DataCell(Text('—', style: TextStyle(color: Colors.grey)));
    }

    final tKey = teamKeys[slotIndex];
    final teamNum = int.tryParse(tKey.replaceAll(RegExp(r'[^0-9]'), ''));
    if (teamNum == null) {
      return const DataCell(Text('—', style: TextStyle(color: Colors.grey)));
    }

    final matchingTeam = _index.getQualTeam(match, teamNum);
    final matchingAlliance = _index.getQualAlliance(match, alliance);

    final isConflict = matchingTeam.length > 1 || (matchingTeam.isNotEmpty && matchingAlliance.isNotEmpty);
    final isAssigned = matchingTeam.length == 1;
    final asgn = isAssigned ? matchingTeam.first : null;
    final isDone = asgn?.status == 'COMPLETED';
    final isCoveredByAlliance = !isAssigned && matchingAlliance.isNotEmpty;

    String scouterName;
    if (isConflict) {
      if (matchingTeam.length > 1) {
        scouterName = '${matchingTeam.length} Scouts (Fix)';
      } else {
        scouterName = 'Conflict: Team + Alliance';
      }
    } else if (isAssigned) {
      scouterName = asgn!.assignedUserDisplayName ?? asgn.assignedUsername;
    } else if (isCoveredByAlliance) {
      final aAsgn = matchingAlliance.first;
      scouterName = 'Covered: @${aAsgn.assignedUserDisplayName ?? aAsgn.assignedUsername}';
    } else {
      scouterName = '+ Qual';
    }

    final teamSlotKey = 'QUAL:${match.matchKey.toLowerCase()}:team_$teamNum';
    final teamTooltip = isConflict
        ? (_index.getSlotConflictTooltip(teamSlotKey) ??
            'Conflict: Team #$teamNum qualitative assignment has multiple scouts or overlaps with $alliance Alliance.\nClick to resolve.')
        : (isAssigned
            ? 'Team #$teamNum (Qual): Assigned to @$scouterName (Status: ${asgn?.status ?? "PENDING"})\nClick to edit'
            : (isCoveredByAlliance
                ? 'Team #$teamNum: Covered under $alliance Alliance by @${matchingAlliance.first.assignedUserDisplayName ?? matchingAlliance.first.assignedUsername}\nClick to assign dedicated team scout'
                : 'Team #$teamNum (Qual): Unassigned in ${match.shortLabel}\nClick to assign'));

    final color = isConflict
        ? const Color(0xFFEF4444)
        : (isDone
            ? const Color(0xFF10B981)
            : (isAssigned
                ? (alliance == 'RED' ? Colors.redAccent : Colors.blueAccent)
                : (isCoveredByAlliance ? Colors.grey : Colors.grey.shade600)));

    return DataCell(
      Tooltip(
        message: teamTooltip,
        waitDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: () {
            if (isConflict) {
              final allConflicted = [...matchingTeam, ...matchingAlliance];
              _openConflictResolverModal(allConflicted, title: '${match.shortLabel} - Team #$teamNum (Qual)');
            } else if (isAssigned) {
              _openCreateEditModal(asgn: asgn);
            } else {
              _openCreateEditModal(
                defaultType: 'QUALITATIVE',
                defaultMatchKey: match.matchKey,
                defaultMatchNumber: match.matchNumber,
                defaultTeamNumber: teamNum,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: isAssigned || isConflict ? 0.8 : 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isConflict) ...[
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFEF4444)),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      '#$teamNum',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                Text(
                  scouterName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isAssigned || isConflict ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageFilterRow(String current, Function(String) onSelect) {
    final stages = [
      {'id': 'all', 'label': 'All Stages'},
      {'id': 'qm', 'label': 'Qualifications'},
      {'id': 'pr', 'label': 'Practice'},
      {'id': 'playoffs', 'label': 'Playoffs'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: stages.map((s) {
          final isSelected = current == s['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(s['label']!),
              selected: isSelected,
              selectedColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
              onSelected: (_) => onSelect(s['id']!),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==========================================
  // TAB 2: ASSIGNMENTS LIST VIEW (SLIVERS)
  // ==========================================
  List<Widget> _buildAssignmentsListSlivers() {
    final filtered = _assignments.where((a) {
      if (_filterType.isNotEmpty && a.assignmentType != _filterType) return false;
      if (_filterScouter.isNotEmpty && a.assignedUserId != _filterScouter) return false;
      if (_filterStatus.isNotEmpty && a.status != _filterStatus) return false;
      if (_filterSearch.isNotEmpty) {
        final query = _filterSearch.toLowerCase();
        final matchStr = '${a.matchKey ?? ''} ${a.matchNumber ?? ''} ${a.targetTeamNumber ?? ''} ${a.assignedUsername} ${a.notes ?? ''}'.toLowerCase();
        if (!matchStr.contains(query)) return false;
      }
      return true;
    }).toList();

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter bar
              ObsidianGlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by team, match, or scouter...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) => setState(() => _filterSearch = val),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _filterType.isEmpty ? null : _filterType,
                            decoration: const InputDecoration(isDense: true, labelText: 'Type'),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('All Types')),
                              DropdownMenuItem(value: 'MATCH', child: Text('Match')),
                              DropdownMenuItem(value: 'PIT', child: Text('Pit')),
                              DropdownMenuItem(value: 'QUALITATIVE', child: Text('Qualitative')),
                            ],
                            onChanged: (val) => setState(() => _filterType = val ?? ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SearchablePersonField(
                            label: 'Scouter',
                            users: _users,
                            selectedId: _filterScouter.isEmpty ? null : _filterScouter,
                            emptyOptionLabel: 'All Scouters',
                            onSelected: (val) => setState(() => _filterScouter = val ?? ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _filterStatus.isEmpty ? null : _filterStatus,
                            decoration: const InputDecoration(isDense: true, labelText: 'Status'),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('All Statuses')),
                              DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                              DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress')),
                              DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
                            ],
                            onChanged: (val) => setState(() => _filterStatus = val ?? ''),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Showing ${filtered.length} assignments', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: Text(filtered.length != _assignments.length ? 'Delete Filtered' : 'Delete All'),
                    onPressed: () => _confirmDeleteFiltered(filtered),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const ObsidianGlassCard(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No assignments matching filter criteria.')),
                ),
            ],
          ),
        ),
      ),
      if (filtered.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final a = filtered[index];
              return _buildAssignmentListTile(a);
            },
          ),
        ),
    ];
  }

  Widget _buildAssignmentListTile(ScoutingAssignment a) {
    final statusColor = a.status == 'COMPLETED'
        ? const Color(0xFF10B981)
        : (a.status == 'IN_PROGRESS' ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B));

    final isConflict = _index.conflictIdsToDelete.contains(a.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: ObsidianUITheme.getSurfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isConflict
            ? const BorderSide(color: Color(0xFFEF4444), width: 1.2)
            : BorderSide.none,
      ),
      child: ListTile(
        title: Row(
          children: [
            if (isConflict) ...[
              Tooltip(
                message: 'Conflict detected on this assignment.\nClick edit to adjust scouter or resolve via conflict resolver.',
                preferBelow: false,
                waitDuration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444),
                    size: 14,
                  ),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(a.assignmentType, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text(
              a.assignmentType == 'MATCH'
                  ? '${a.formattedMatchName} • #${a.targetTeamNumber}'
                  : (a.assignmentType == 'PIT'
                      ? 'Pit #${a.targetTeamNumber}'
                      : 'Qual • ${a.formattedMatchName} (${a.allianceColor ?? a.targetAlliance ?? 'Target'})'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isConflict ? const Color(0xFFEF4444) : null,
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Scouter: ${a.assignedUserDisplayName ?? a.assignedUsername}${a.notes != null ? " • Note: ${a.notes}" : ""}',
          style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(a.status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.cyanAccent),
              tooltip: 'Send reminder',
              onPressed: () async {
                await widget.apiService.sendAssignmentReminder(a.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reminder sent!')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16),
              tooltip: 'Edit assignment',
              onPressed: () => _openCreateEditModal(asgn: a),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, size: 16, color: Color(0xFFEF4444)),
              tooltip: 'Delete assignment',
              onPressed: () => _deleteSingleAssignment(a.id),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: PIT COVERAGE (SLIVERS)
  // ==========================================
  List<Widget> _buildPitCoverageSlivers() {
    final search = _pitSearchController.text.trim().toLowerCase();

    final totalTeams = _teams.length;
    int completedCount = 0;
    int assignedCount = 0;
    int unassignedCount = 0;
    int conflictCount = 0;

    for (final team in _teams) {
      final matching = _index.getPitTeam(team.teamNumber);
      if (groupPitUnits(matching).length > 1) {
        conflictCount++;
      } else if (matching.any((a) => a.status == 'COMPLETED')) {
        completedCount++;
      } else if (matching.isNotEmpty) {
        assignedCount++;
      } else {
        unassignedCount++;
      }
    }

    final filteredTeams = _teams.where((t) {
      if (search.isNotEmpty) {
        final matchesQuery = t.teamNumber.toString().contains(search) ||
            (t.nickname ?? '').toLowerCase().contains(search) ||
            (t.name ?? '').toLowerCase().contains(search);
        if (!matchesQuery) return false;
      }

      final matching = _index.getPitTeam(t.teamNumber);
      if (_pitFilter == 'unassigned') {
        return matching.isEmpty;
      } else if (_pitFilter == 'assigned') {
        return matching.isNotEmpty && !matching.any((a) => a.status == 'COMPLETED') && groupPitUnits(matching).length == 1;
      } else if (_pitFilter == 'completed') {
        return matching.any((a) => a.status == 'COMPLETED');
      } else if (_pitFilter == 'conflicts') {
        return groupPitUnits(matching).length > 1;
      }
      return true;
    }).toList();

    final progress = totalTeams > 0 ? (completedCount / totalTeams) : 0.0;

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pit Progress Overview Card
              ObsidianGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pit Scouting Progress',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          '$completedCount / $totalTeams scouted (${(progress * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: progress == 1.0 ? const Color(0xFF10B981) : ObsidianUITheme.primaryAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress == 1.0 ? const Color(0xFF10B981) : ObsidianUITheme.primaryAccent,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Search & Filter Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pitSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search pit teams...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Quick Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPitFilterChip('all', 'All ($totalTeams)'),
                    const SizedBox(width: 8),
                    _buildPitFilterChip('unassigned', 'Unassigned ($unassignedCount)', const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    _buildPitFilterChip('assigned', 'Assigned ($assignedCount)', const Color(0xFF8B5CF6)),
                    const SizedBox(width: 8),
                    _buildPitFilterChip('completed', 'Scouted ($completedCount)', const Color(0xFF10B981)),
                    if (conflictCount > 0) ...[
                      const SizedBox(width: 8),
                      _buildPitFilterChip('conflicts', 'Conflicts ($conflictCount)', const Color(0xFFEF4444)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (filteredTeams.isEmpty)
                const ObsidianGlassCard(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No teams match the current pit filter.')),
                ),
            ],
          ),
        ),
      ),
      if (filteredTeams.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 310,
              mainAxisExtent: 110,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filteredTeams.length,
            itemBuilder: (context, index) {
              final team = filteredTeams[index];
              return _buildPitTeamCard(team);
            },
          ),
        ),
    ];
  }

  Widget _buildPitFilterChip(String filterKey, String label, [Color? activeColor]) {
    final isSelected = _pitFilter == filterKey;
    final color = activeColor ?? ObsidianUITheme.primaryAccent;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? (activeColor ?? ObsidianUITheme.primaryAccent) : null,
      ),
      selectedColor: color.withValues(alpha: 0.2),
      onSelected: (_) => setState(() => _pitFilter = filterKey),
    );
  }

  Widget _buildPitTeamCard(TeamModel team) {
    final matching = _index.getPitTeam(team.teamNumber);
    final units = groupPitUnits(matching);

    final isConflict = units.length > 1;
    final isAssigned = units.length == 1;
    final unit = isAssigned ? units.first : const <ScoutingAssignment>[];
    final asgn = isAssigned ? unit.first : null;
    final isDone = unit.any((a) => a.status == 'COMPLETED');
    final groupName = asgn?.scoutGroup?.trim() ?? '';
    final isGroup = groupName.isNotEmpty;

    final statusLabel = isConflict
        ? 'Conflict'
        : (isDone
            ? '✓ Scouted'
            : (isAssigned ? (asgn?.status == 'IN_PROGRESS' ? 'In Progress' : 'Assigned') : 'Unassigned'));

    final color = isConflict
        ? const Color(0xFFEF4444)
        : (isDone
            ? const Color(0xFF10B981)
            : (isAssigned ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B)));

    final pitSlotKey = 'PIT:${team.teamNumber}';
    final pitTooltip = isConflict
        ? (_index.getSlotConflictTooltip(pitSlotKey) ??
            'Conflict: Multiple scouts assigned to Pit Scouting for Team #${team.teamNumber}.\nClick to resolve.')
        : (isDone
            ? 'Team #${team.teamNumber}: Pit scouting completed\nClick to edit'
            : (isAssigned
                ? (isGroup
                    ? 'Team #${team.teamNumber}: Pit group "$groupName" (${unit.map((a) => '@${a.assignedUserDisplayName ?? a.assignedUsername}').join(', ')})\nClick to edit'
                    : 'Team #${team.teamNumber}: Pit assigned to @${asgn?.assignedUserDisplayName ?? asgn?.assignedUsername} (Status: ${asgn?.status ?? "PENDING"})\nClick to edit')
                : 'Team #${team.teamNumber}: Unassigned in pit\nClick to assign'));

    final scouterDisplayName = isGroup
        ? '$groupName (${unit.length})'
        : '@${asgn?.assignedUserDisplayName ?? asgn?.assignedUsername ?? ''}';

    return Tooltip(
      message: pitTooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (isConflict) {
              _openConflictResolverModal(matching, title: 'Pit Scouting - Team #${team.teamNumber}');
            } else if (isAssigned) {
              _openCreateEditModal(asgn: asgn);
            } else {
              _openCreateEditModal(
                defaultType: 'PIT',
                defaultTeamNumber: team.teamNumber,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ObsidianUITheme.getSurfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConflict
                    ? const Color(0xFFEF4444)
                    : (isDone
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : (isAssigned
                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.4)
                            : ObsidianUITheme.getBorderColor(context).withValues(alpha: 0.6))),
                width: isConflict ? 1.4 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Row: Team Number & Status Pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isConflict) ...[
                          const Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFEF4444)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '#${team.teamNumber}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: isConflict
                                ? const Color(0xFFEF4444)
                                : ObsidianUITheme.getPrimaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDone) ...[
                            const Icon(Icons.check_rounded, size: 11, color: Color(0xFF10B981)),
                            const SizedBox(width: 2),
                          ],
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Middle Row: Team Name / Nickname
                Text(
                  team.nickname?.isNotEmpty == true
                      ? team.nickname!
                      : (team.name ?? 'Team #${team.teamNumber}'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ObsidianUITheme.getSecondaryTextColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Bottom Row: Interactive Scout Assignment Action Pill
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConflict
                        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                        : (isDone
                            ? const Color(0xFF10B981).withValues(alpha: 0.08)
                            : (isAssigned
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                                : ObsidianUITheme.primaryAccent.withValues(alpha: 0.08))),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isConflict
                          ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                          : (isDone
                              ? const Color(0xFF10B981).withValues(alpha: 0.25)
                              : (isAssigned
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                  : ObsidianUITheme.primaryAccent.withValues(alpha: 0.25))),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isConflict
                            ? Icons.warning_amber_rounded
                            : (isDone
                                ? Icons.task_alt_rounded
                                : (isAssigned
                                    ? (isGroup ? Icons.groups_rounded : Icons.person_rounded)
                                    : Icons.person_add_alt_1_rounded)),
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          isConflict
                              ? 'Resolve ${units.length} assignees'
                              : (isAssigned
                                  ? scouterDisplayName
                                  : (isDone ? 'Completed' : 'Assign Scout')),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isAssigned || isDone || isConflict ? FontWeight.bold : FontWeight.w600,
                            color: color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        isConflict
                            ? Icons.build_circle_outlined
                            : (isAssigned ? Icons.edit_rounded : Icons.arrow_forward_ios_rounded),
                        size: isAssigned || isConflict ? 12 : 9,
                        color: color.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MODALS & DIALOGS
  // ==========================================
  void _openCreateEditModal({
    ScoutingAssignment? asgn,
    String? defaultType,
    String? defaultMatchKey,
    int? defaultMatchNumber,
    int? defaultTeamNumber,
    String? defaultAlliance,
  }) {
    _isModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateEditAssignmentBottomSheet(
        apiService: widget.apiService,
        assignment: asgn,
        eventKey: _currentEventKey ?? '',
        matches: _matches,
        teams: _teams,
        users: _users,
        defaultType: defaultType,
        defaultMatchKey: defaultMatchKey,
        defaultMatchNumber: defaultMatchNumber,
        defaultTeamNumber: defaultTeamNumber,
        defaultAlliance: defaultAlliance,
        existingAssignments: _assignments,
        pitGroups: _pitGroups,
        onSaved: () {
          _isModalOpen = false;
          _loadEventData();
        },
      ),
    ).then((_) => _isModalOpen = false);
  }

  void _openBulkWizardModal() {
    _isModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BulkWizardBottomSheet(
        apiService: widget.apiService,
        eventKey: _currentEventKey ?? '',
        matches: _matches,
        teams: _teams,
        users: _users,
        existingAssignments: _assignments,
        pitGroups: _pitGroups,
        onGenerated: () {
          _isModalOpen = false;
          _loadEventData();
        },
      ),
    ).then((_) => _isModalOpen = false);
  }

  void _openPlannedShiftsModal() {
    final eventKey = _currentEventKey ?? '';
    if (eventKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('assignments.shift_select_event', 'Select an event first.'))),
      );
      return;
    }
    EventModel? event;
    for (final e in _events) {
      if (e.eventKey == eventKey) event = e;
    }
    // FTC fields have two robots per alliance; synced matches show it, the event key covers before the schedule
    final isFtc = eventKey.toLowerCase().startsWith('ftc') ||
        _users.any((u) => u.program.toUpperCase() == 'FTC') ||
        _matches.any((m) => m.redTeams.length == 2);
    _isModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PlannedShiftsBottomSheet(
        apiService: widget.apiService,
        eventKey: eventKey,
        event: event,
        users: _users,
        stationsPerAlliance: isFtc ? 2 : 3,
        onAssignmentsCreated: _loadEventData,
      ),
    ).then((_) => _isModalOpen = false);
  }

  void _openPitAutoModal() {
    _isModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PitAutoBottomSheet(
        apiService: widget.apiService,
        eventKey: _currentEventKey ?? '',
        teams: _teams,
        users: _users,
        existingAssignments: _assignments,
        pitGroups: _pitGroups,
        onGenerated: () {
          _isModalOpen = false;
          _loadEventData();
        },
      ),
    ).then((_) => _isModalOpen = false);
  }

  void _openPitGroupsModal() {
    _isModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PitGroupsBottomSheet(
        apiService: widget.apiService,
        users: _users,
        groups: _pitGroups,
        onSaved: (saved) {
          _isModalOpen = false;
          if (mounted) setState(() => _pitGroups = saved);
        },
      ),
    ).then((_) => _isModalOpen = false);
  }

  void _openConflictResolverModal(
    List<ScoutingAssignment> conflicted, {
    String? title,
  }) {
    _isModalOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text(title ?? 'Resolve Assignment Conflict'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: conflicted.length,
            itemBuilder: (c, idx) {
              final a = conflicted[idx];
              return Card(
                color: Colors.black12,
                child: ListTile(
                  title: Text(a.assignedUserDisplayName ?? a.assignedUsername, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Status: ${a.status} • Notes: ${a.notes ?? "None"}'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                    onPressed: () async {
                      final toDelete = conflicted.where((item) => item.id != a.id).map((i) => i.id).toList();
                      try {
                        await widget.apiService.deleteAllAssignments(_currentEventKey ?? '', specificIds: toDelete);
                        if (!ctx.mounted) return;
                        final delSet = toDelete.toSet();
                        if (mounted) {
                          setState(() {
                            _assignments.removeWhere((item) => delSet.contains(item.id));
                            _recomputeIndex();
                          });
                        }
                        Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Conflict resolved! Kept selected scouter.')),
                          );
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        final msg = e.toString().replaceAll('Exception: ', '');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      }
                      _loadEventData();
                    },
                    child: const Text('Keep This Scout', style: TextStyle(color: Colors.black, fontSize: 11)),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              final toDelete = conflicted.map((i) => i.id).toList();
              try {
                await widget.apiService.deleteAllAssignments(_currentEventKey ?? '', specificIds: toDelete);
                if (!ctx.mounted) return;
                final delSet = toDelete.toSet();
                if (mounted) {
                  setState(() {
                    _assignments.removeWhere((item) => delSet.contains(item.id));
                    _recomputeIndex();
                  });
                }
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cleared all assignments in slot.')),
                  );
                }
              } catch (e) {
                if (!ctx.mounted) return;
                final msg = e.toString().replaceAll('Exception: ', '');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                }
              }
              _loadEventData();
            },
            child: const Text('Clear All In Slot'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    ).then((_) => _isModalOpen = false);
  }

  Future<void> _deleteSingleAssignment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: const Text('Delete Assignment'),
        content: const Text('Are you sure you want to delete this assignment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await widget.apiService.deleteAssignment(id);
        if (mounted) {
          if (success) {
            setState(() {
              _assignments.removeWhere((a) => a.id == id);
              _recomputeIndex();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Assignment deleted')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to delete assignment.')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().replaceAll('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
      _loadEventData();
    }
  }

  Future<void> _confirmDeleteFiltered(List<ScoutingAssignment> filtered) async {
    final isAll = filtered.length == _assignments.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text(isAll ? 'Delete All Assignments' : 'Delete Filtered Assignments'),
        content: Text(
          isAll
              ? 'Are you sure you want to delete all ${_assignments.length} assignments for this event?'
              : 'Are you sure you want to delete the ${filtered.length} currently filtered assignments?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        bool success;
        if (isAll) {
          success = await widget.apiService.deleteAllAssignments(_currentEventKey ?? '');
        } else {
          success = await widget.apiService.deleteAllAssignments(
            _currentEventKey ?? '',
            specificIds: filtered.map((a) => a.id).toList(),
          );
        }
        if (mounted) {
          if (success) {
            final deletedIds = filtered.map((a) => a.id).toSet();
            setState(() {
              _assignments.removeWhere((a) => isAll || deletedIds.contains(a.id));
              _recomputeIndex();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isAll ? 'Deleted all assignments' : 'Deleted ${filtered.length} filtered assignment(s)')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to delete assignments.')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          final msg = e.toString().replaceAll('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
      _loadEventData();
    }
  }
}

// ==========================================
// BOTTOM SHEET: CREATE / EDIT ASSIGNMENT
// ==========================================
class _CreateEditAssignmentBottomSheet extends StatefulWidget {
  final ApiService apiService;
  final ScoutingAssignment? assignment;
  final String eventKey;
  final List<MatchModel> matches;
  final List<TeamModel> teams;
  final List<UserModel> users;
  final String? defaultType;
  final String? defaultMatchKey;
  final int? defaultMatchNumber;
  final int? defaultTeamNumber;
  final String? defaultAlliance;
  final List<ScoutingAssignment> existingAssignments;
  final List<PitScoutGroup> pitGroups;
  final VoidCallback onSaved;

  const _CreateEditAssignmentBottomSheet({
    required this.apiService,
    this.assignment,
    required this.eventKey,
    required this.matches,
    required this.teams,
    required this.users,
    this.defaultType,
    this.defaultMatchKey,
    this.defaultMatchNumber,
    this.defaultTeamNumber,
    this.defaultAlliance,
    required this.existingAssignments,
    this.pitGroups = const [],
    required this.onSaved,
  });

  @override
  State<_CreateEditAssignmentBottomSheet> createState() =>
      _CreateEditAssignmentBottomSheetState();
}

class _CreateEditAssignmentBottomSheetState
    extends State<_CreateEditAssignmentBottomSheet> {
  late String _type;
  String _qualScope = 'team'; // team, red, blue, both
  String? _selectedMatchKey;
  int? _selectedTeamNumber;
  String? _selectedAlliance;
  String? _selectedUserId;
  String _status = 'PENDING';
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;
  String? _selectedGroupId; // pit only: send a whole group instead of one scouter

  PitScoutGroup? get _selectedGroup =>
      widget.pitGroups.where((g) => g.id == _selectedGroupId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    final existingGroup = a?.scoutGroup?.trim().toLowerCase() ?? '';
    if (existingGroup.isNotEmpty) {
      _selectedGroupId = widget.pitGroups.where((g) => g.name.toLowerCase() == existingGroup).firstOrNull?.id;
    }
    _type = a?.assignmentType ?? widget.defaultType ?? 'MATCH';
    _selectedMatchKey = a?.matchKey ?? widget.defaultMatchKey;
    _selectedTeamNumber = a?.targetTeamNumber ?? widget.defaultTeamNumber;
    _selectedAlliance = a?.allianceColor ?? a?.targetAlliance ?? widget.defaultAlliance;
    _selectedUserId = a?.assignedUserId;
    _status = a?.status ?? 'PENDING';
    _notesController.text = a?.notes ?? '';

    if (_type == 'QUALITATIVE') {
      if (a != null) {
        if (a.targetTeamNumber != null) {
          _qualScope = 'team';
        } else if ((a.allianceColor ?? a.targetAlliance ?? '').toUpperCase() == 'RED') {
          _qualScope = 'red';
        } else if ((a.allianceColor ?? a.targetAlliance ?? '').toUpperCase() == 'BLUE') {
          _qualScope = 'blue';
        } else {
          _qualScope = 'both';
        }
      } else if (widget.defaultAlliance != null) {
        _qualScope = widget.defaultAlliance!.toLowerCase();
      } else if (widget.defaultTeamNumber != null) {
        _qualScope = 'team';
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<int> get _teamsInMatch {
    final match = widget.matches.where((m) => m.matchKey == _selectedMatchKey).firstOrNull;
    if (match != null) {
      final allKeys = [...match.redTeams, ...match.blueTeams];
      return allKeys
          .map((k) => int.tryParse(k.replaceAll(RegExp(r'[^0-9]'), '')))
          .whereType<int>()
          .toList();
    }
    return widget.teams.map((t) => t.teamNumber).toList();
  }

  String? _checkConflictWarning() {
    final match = widget.matches.where((m) => m.matchKey == _selectedMatchKey).firstOrNull;
    if (_type == 'MATCH' && match != null && _selectedTeamNumber != null) {
      final duplicate = widget.existingAssignments.where((a) {
        if (a.id == widget.assignment?.id) return false;
        return a.assignmentType == 'MATCH' && a.isForSlot(match, _selectedTeamNumber);
      }).firstOrNull;
      if (duplicate != null) {
        return 'Warning: Team $_selectedTeamNumber is already assigned to @${duplicate.assignedUserDisplayName ?? duplicate.assignedUsername}!';
      }
    } else if (_type == 'PIT' && _selectedTeamNumber != null) {
      final editingUnit = widget.assignment?.pitUnitKey;
      final chosenUnit = _selectedGroup != null ? 'group:${_selectedGroup!.name.toLowerCase()}' : null;
      final duplicate = widget.existingAssignments.where((a) {
        if (a.id == widget.assignment?.id) return false;
        if (a.pitUnitKey == editingUnit || a.pitUnitKey == chosenUnit) return false;
        return a.assignmentType == 'PIT' && a.targetTeamNumber == _selectedTeamNumber;
      }).firstOrNull;
      if (duplicate != null) {
        return 'Warning: Team $_selectedTeamNumber is already assigned to @${duplicate.assignedUserDisplayName ?? duplicate.assignedUsername}!';
      }
    } else if (_type == 'QUALITATIVE' && match != null) {
      if (_qualScope == 'team' && _selectedTeamNumber != null) {
        final duplicate = widget.existingAssignments.where((a) {
          if (a.id == widget.assignment?.id) return false;
          return a.assignmentType == 'QUALITATIVE' && a.isForSlot(match, _selectedTeamNumber);
        }).firstOrNull;
        if (duplicate != null) {
          return 'Warning: Team $_selectedTeamNumber is already individually assigned to @${duplicate.assignedUserDisplayName ?? duplicate.assignedUsername} (Qual)!';
        }

        final teamStr = _selectedTeamNumber.toString();
        final isRed = match.redTeams.any((k) => k.replaceAll(RegExp(r'[^0-9]'), '') == teamStr);
        final isBlue = match.blueTeams.any((k) => k.replaceAll(RegExp(r'[^0-9]'), '') == teamStr);
        final teamAlliance = isRed ? 'RED' : (isBlue ? 'BLUE' : null);
        if (teamAlliance != null) {
          final allianceDuplicate = widget.existingAssignments.where((a) {
            if (a.id == widget.assignment?.id) return false;
            return a.assignmentType == 'QUALITATIVE' && a.isForQualAlliance(match, teamAlliance);
          }).firstOrNull;
          if (allianceDuplicate != null) {
            return 'Warning: Team $_selectedTeamNumber is already covered under $teamAlliance Alliance assignment (@${allianceDuplicate.assignedUserDisplayName ?? allianceDuplicate.assignedUsername})!';
          }
        }
      } else if (_qualScope == 'red' || _qualScope == 'blue') {
        final alliance = _qualScope.toUpperCase();
        final duplicate = widget.existingAssignments.where((a) {
          if (a.id == widget.assignment?.id) return false;
          return a.assignmentType == 'QUALITATIVE' && a.isForQualAlliance(match, alliance);
        }).firstOrNull;
        if (duplicate != null) {
          return 'Warning: $alliance Alliance is already assigned to @${duplicate.assignedUserDisplayName ?? duplicate.assignedUsername} (Qual)!';
        }

        final teamKeys = alliance == 'RED' ? match.redTeams : match.blueTeams;
        final teamNums = teamKeys
            .map((k) => int.tryParse(k.replaceAll(RegExp(r'[^0-9]'), '')))
            .whereType<int>()
            .toList();
        final teamDuplicate = widget.existingAssignments.where((a) {
          if (a.id == widget.assignment?.id) return false;
          return a.assignmentType == 'QUALITATIVE' &&
              a.isMatchFor(match) &&
              a.targetTeamNumber != null &&
              teamNums.contains(a.targetTeamNumber);
        }).firstOrNull;
        if (teamDuplicate != null) {
          return 'Warning: Team #${teamDuplicate.targetTeamNumber} in $alliance Alliance is already individually assigned to @${teamDuplicate.assignedUserDisplayName ?? teamDuplicate.assignedUsername}!';
        }
      } else if (_qualScope == 'both') {
        final anyQual = widget.existingAssignments.where((a) {
          if (a.id == widget.assignment?.id) return false;
          return a.assignmentType == 'QUALITATIVE' && a.isMatchFor(match);
        }).firstOrNull;
        if (anyQual != null) {
          return 'Warning: Match already has qualitative assignments assigned!';
        }
      }
    }
    return null;
  }

  /// Assigning a group (or editing a grouped row) replaces that whole unit on the pit team.
  Future<void> _savePitGroupAssignment() async {
    final group = _selectedGroup;
    final teamNum = _selectedTeamNumber;
    if (teamNum == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a team to pit scout.')),
      );
      return;
    }
    if (group == null && (_selectedUserId == null || _selectedUserId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a scouter or a pit group.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final editing = widget.assignment;
      final replaceUnits = <String>{
        if (editing != null) editing.pitUnitKey,
        if (group != null) 'group:${group.name.toLowerCase()}',
      };
      final toReplace = widget.existingAssignments.where((a) =>
          a.assignmentType == 'PIT' &&
          (a.targetTeamNumber == teamNum || (editing != null && a.targetTeamNumber == editing.targetTeamNumber)) &&
          replaceUnits.contains(a.pitUnitKey));
      for (final a in toReplace) {
        await widget.apiService.deleteAssignment(a.id);
      }

      final team = widget.teams.where((t) => t.teamNumber == teamNum).firstOrNull;
      final nickname = team?.nickname ?? team?.name ?? '';
      final typedNotes = _notesController.text.trim();
      final baseNote = typedNotes.isNotEmpty
          ? typedNotes
          : (nickname.isNotEmpty ? 'Pit Scouting - $nickname' : 'Pit Scouting');
      final memberIds = group != null ? group.memberIds : [_selectedUserId!];
      await widget.apiService.bulkCreateAssignments(
        BulkCreateAssignmentsRequest(
          eventKey: widget.eventKey,
          assignments: memberIds
              .map((uid) => BulkAssignmentItem(
                    assignedUserId: uid,
                    assignmentType: 'PIT',
                    targetTeamNumber: teamNum,
                    scoutGroup: group?.name,
                    notes: group != null ? '$baseNote (Group: ${group.name})' : baseNote,
                  ))
              .toList(),
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save pit group assignment: $e')),
        );
      }
    }
  }

  Future<void> _handleSave() async {
    final editingGrouped = (widget.assignment?.scoutGroup?.trim().isNotEmpty ?? false);
    if (_type == 'PIT' && (_selectedGroup != null || editingGrouped)) {
      await _savePitGroupAssignment();
      return;
    }

    if (_selectedUserId == null || _selectedUserId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a scouter.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final match = widget.matches.where((m) => m.matchKey == _selectedMatchKey).firstOrNull;
      final matchNum = match?.matchNumber ?? widget.defaultMatchNumber;

      if (_type == 'QUALITATIVE' && _qualScope == 'both') {
        // Bulk create for both RED and BLUE alliances
        final bulkItems = [
          BulkAssignmentItem(
            assignedUserId: _selectedUserId!,
            assignmentType: 'QUALITATIVE',
            matchKey: _selectedMatchKey,
            matchNumber: matchNum,
            compLevel: match?.compLevel ?? 'qm',
            allianceColor: 'RED',
            targetAlliance: 'RED',
            notes: _notesController.text.trim().isNotEmpty
                ? '${_notesController.text.trim()} (Red Alliance)'
                : 'Qualitative scouting for RED alliance',
          ),
          BulkAssignmentItem(
            assignedUserId: _selectedUserId!,
            assignmentType: 'QUALITATIVE',
            matchKey: _selectedMatchKey,
            matchNumber: matchNum,
            compLevel: match?.compLevel ?? 'qm',
            allianceColor: 'BLUE',
            targetAlliance: 'BLUE',
            notes: _notesController.text.trim().isNotEmpty
                ? '${_notesController.text.trim()} (Blue Alliance)'
                : 'Qualitative scouting for BLUE alliance',
          ),
        ];

        await widget.apiService.bulkCreateAssignments(
          BulkCreateAssignmentsRequest(
            eventKey: widget.eventKey,
            assignments: bulkItems,
          ),
        );
      } else if (widget.assignment != null) {
        // Edit
        await widget.apiService.updateAssignment(
          widget.assignment!.id,
          UpdateAssignmentRequest(
            assignedUserId: _selectedUserId,
            targetTeamNumber: _type == 'QUALITATIVE'
                ? (_qualScope == 'team' ? _selectedTeamNumber : null)
                : _selectedTeamNumber,
            allianceColor: _type == 'QUALITATIVE'
                ? (_qualScope == 'red' ? 'RED' : (_qualScope == 'blue' ? 'BLUE' : null))
                : _selectedAlliance,
            status: _status,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          ),
        );
      } else {
        // Create single
        await widget.apiService.createAssignment(
          CreateAssignmentRequest(
            assignedUserId: _selectedUserId!,
            assignmentType: _type,
            eventKey: widget.eventKey,
            matchKey: _selectedMatchKey,
            matchNumber: matchNum,
            compLevel: match?.compLevel ?? 'qm',
            targetTeamNumber: _type == 'QUALITATIVE'
                ? (_qualScope == 'team' ? _selectedTeamNumber : null)
                : _selectedTeamNumber,
            allianceColor: _type == 'QUALITATIVE'
                ? (_qualScope == 'red' ? 'RED' : (_qualScope == 'blue' ? 'BLUE' : null))
                : _selectedAlliance,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          ),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save assignment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflictWarning = _checkConflictWarning();
    final teamsInMatch = _teamsInMatch;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.assignment != null ? 'Edit Assignment' : 'New Assignment',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            // Type dropdown
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Assignment Type', isDense: true),
              items: const [
                DropdownMenuItem(value: 'MATCH', child: Text('Match Scouting')),
                DropdownMenuItem(value: 'PIT', child: Text('Pit Scouting')),
                DropdownMenuItem(value: 'QUALITATIVE', child: Text('Qualitative Scouting')),
              ],
              onChanged: widget.assignment == null
                  ? (val) => setState(() {
                        _type = val ?? 'MATCH';
                        if (_type == 'QUALITATIVE' && _selectedAlliance == null) {
                          _selectedAlliance = 'RED';
                        }
                      })
                  : null,
            ),
            const SizedBox(height: 10),

            // MATCH SCOUTING FIELDS
            if (_type == 'MATCH') ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedMatchKey,
                decoration: const InputDecoration(labelText: 'Select Match', isDense: true),
                items: widget.matches.map((m) {
                  return DropdownMenuItem(
                    value: m.matchKey,
                    child: Text('${m.shortLabel} (${m.matchKey})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() {
                  _selectedMatchKey = val;
                  final available = _teamsInMatch;
                  if (available.isNotEmpty && !available.contains(_selectedTeamNumber)) {
                    _selectedTeamNumber = available.first;
                  }
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _selectedTeamNumber,
                decoration: const InputDecoration(
                  labelText: 'Select Team in Match',
                  isDense: true,
                ),
                items: (teamsInMatch.isNotEmpty ? teamsInMatch : widget.teams.map((t) => t.teamNumber)).map((tNum) {
                  final teamObj = widget.teams.where((t) => t.teamNumber == tNum).firstOrNull;
                  return DropdownMenuItem(
                    value: tNum,
                    child: Text('#$tNum ${teamObj?.nickname != null ? "(${teamObj!.nickname})" : ""}'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedTeamNumber = val),
              ),
              const SizedBox(height: 10),
            ],

            // PIT SCOUTING FIELDS
            if (_type == 'PIT') ...[
              DropdownButtonFormField<int>(
                initialValue: _selectedTeamNumber,
                decoration: const InputDecoration(
                  labelText: 'Select Team to Pit Scout',
                  isDense: true,
                ),
                items: widget.teams.map((t) {
                  return DropdownMenuItem(
                    value: t.teamNumber,
                    child: Text('#${t.teamNumber} ${t.nickname != null ? "(${t.nickname})" : ""}'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedTeamNumber = val),
              ),
              const SizedBox(height: 10),
              if (widget.pitGroups.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedGroupId ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Assign To',
                    helperText: 'Pick a pit group to send all of its members together.',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Individual scouter')),
                    ...widget.pitGroups.map((g) => DropdownMenuItem(
                          value: g.id,
                          child: Text('Group: ${g.name} (${g.memberIds.length})'),
                        )),
                  ],
                  onChanged: (val) => setState(() => _selectedGroupId = (val == null || val.isEmpty) ? null : val),
                ),
                const SizedBox(height: 10),
              ],
            ],

            // QUALITATIVE SCOUTING FIELDS
            if (_type == 'QUALITATIVE') ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedMatchKey,
                decoration: const InputDecoration(labelText: 'Select Match', isDense: true),
                items: widget.matches.map((m) {
                  return DropdownMenuItem(
                    value: m.matchKey,
                    child: Text('${m.shortLabel} (${m.matchKey})'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedMatchKey = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _qualScope,
                decoration: const InputDecoration(labelText: 'Target Scope', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'team', child: Text('Single Team')),
                  DropdownMenuItem(value: 'red', child: Text('Red Alliance (3 teams)')),
                  DropdownMenuItem(value: 'blue', child: Text('Blue Alliance (3 teams)')),
                  DropdownMenuItem(value: 'both', child: Text('Both Alliances (6 teams)')),
                ],
                onChanged: (val) => setState(() => _qualScope = val ?? 'team'),
              ),
              const SizedBox(height: 10),
              if (_qualScope == 'team') ...[
                DropdownButtonFormField<int>(
                  initialValue: _selectedTeamNumber,
                  decoration: const InputDecoration(labelText: 'Select Team', isDense: true),
                  items: (teamsInMatch.isNotEmpty ? teamsInMatch : widget.teams.map((t) => t.teamNumber)).map((tNum) {
                    final teamObj = widget.teams.where((t) => t.teamNumber == tNum).firstOrNull;
                    return DropdownMenuItem(
                      value: tNum,
                      child: Text('#$tNum ${teamObj?.nickname != null ? "(${teamObj!.nickname})" : ""}'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedTeamNumber = val),
                ),
                const SizedBox(height: 10),
              ],
            ],

            // Scouter dropdown (hidden when a whole pit group is chosen)
            if (!(_type == 'PIT' && _selectedGroup != null)) ...[
              _SearchablePersonField(
                label: 'Assign to Scouter',
                users: widget.users,
                selectedId: _selectedUserId,
                showRole: true,
                onSelected: (val) => setState(() => _selectedUserId = val),
              ),
              const SizedBox(height: 10),
            ],
            if (widget.assignment != null && !(_type == 'PIT' && (_selectedGroup != null || (widget.assignment!.scoutGroup?.isNotEmpty ?? false)))) ...[
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                  DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress')),
                  DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
                  DropdownMenuItem(value: 'SKIPPED', child: Text('Skipped')),
                ],
                onChanged: (val) => setState(() => _status = val ?? 'PENDING'),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)', isDense: true),
            ),
            if (conflictWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conflictWarning,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.assignment != null ? 'Update Assignment' : 'Create Assignment', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// BOTTOM SHEET: BULK MATCH WIZARD
// ==========================================
class _BulkWizardBottomSheet extends StatefulWidget {
  final ApiService apiService;
  final String eventKey;
  final List<MatchModel> matches;
  final List<TeamModel> teams;
  final List<UserModel> users;
  final List<ScoutingAssignment> existingAssignments;
  final List<PitScoutGroup> pitGroups;
  final VoidCallback onGenerated;

  const _BulkWizardBottomSheet({
    required this.apiService,
    required this.eventKey,
    required this.matches,
    required this.teams,
    required this.users,
    required this.existingAssignments,
    this.pitGroups = const [],
    required this.onGenerated,
  });

  @override
  State<_BulkWizardBottomSheet> createState() => _BulkWizardBottomSheetState();
}

class _BulkWizardBottomSheetState extends State<_BulkWizardBottomSheet> {
  String _bulkType = 'MATCH';
  String _stage = 'all';
  String? _startMatchKey;
  String? _endMatchKey;
  int _consecutiveBlocks = 5;
  bool _overwrite = false;
  String _pitScope = 'unassigned';
  final Set<String> _selectedScouterIds = {};
  final Set<String> _selectedGroupIds = {};
  bool _isGenerating = false;

  // Time block (shift) mode: assign only the matches starting inside [_shiftStart, _shiftEnd) on [_timeDay]
  String _rangeMode = 'matches'; // matches | time
  String? _timeDay; // yyyy-mm-dd in device-local time, like the rest of the app's match times
  TimeOfDay _shiftStart = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 12, minute: 0);

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Days that have scheduled matches in the current stage, with how many each.
  Map<String, int> get _matchDays {
    final counts = <String, int>{};
    for (final m in _stageMatches) {
      final start = m.predictedStart?.toLocal();
      if (start != null) counts[_dayKey(start)] = (counts[_dayKey(start)] ?? 0) + 1;
    }
    return Map.fromEntries(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  String _dayLabel(String key) {
    final parts = key.split('-').map(int.parse).toList();
    final d = DateTime(parts[0], parts[1], parts[2]);
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  }

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  List<MatchModel> get _matchesInBlock {
    final day = _timeDay;
    final startMin = _minutesOf(_shiftStart);
    final endMin = _minutesOf(_shiftEnd);
    if (day == null || endMin <= startMin) return const [];
    return _stageMatches.where((m) {
      final start = m.predictedStart?.toLocal();
      if (start == null || _dayKey(start) != day) return false;
      final minutes = start.hour * 60 + start.minute;
      return minutes >= startMin && minutes < endMin;
    }).toList();
  }

  void _ensureTimeDay() {
    final days = _matchDays.keys.toList();
    if (_timeDay == null || !days.contains(_timeDay)) {
      _timeDay = days.isNotEmpty ? days.first : null;
    }
  }

  Future<void> _pickShiftTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _shiftStart : _shiftEnd);
    if (picked != null && mounted) {
      setState(() => isStart ? _shiftStart = picked : _shiftEnd = picked);
    }
  }

  @override
  void initState() {
    super.initState();
    // Default select all users
    _selectedScouterIds.addAll(widget.users.map((u) => u.id));
    final available = _stageMatches;
    if (available.isNotEmpty) {
      _startMatchKey = available.first.matchKey;
      _endMatchKey = available.last.matchKey;
    }
  }

  List<MatchModel> get _stageMatches {
    List<MatchModel> list;
    if (_stage == 'all') {
      list = List.from(widget.matches);
    } else {
      list = widget.matches.where((m) {
        final lvl = m.compLevel.toLowerCase();
        final key = m.matchKey.toLowerCase();
        if (_stage == 'qm') return lvl == 'qm' || key.contains('_qm');
        if (_stage == 'pr') return lvl == 'pr' || lvl == 'practice' || key.contains('_pr') || key.contains('_practice');
        if (_stage == 'playoffs') {
          return lvl == 'qf' ||
              lvl == 'sf' ||
              lvl == 'f' ||
              lvl == 'playoff' ||
              key.contains('_qf') ||
              key.contains('_sf') ||
              key.contains('_f');
        }
        return true;
      }).toList();
    }
    list.sort(MatchModel.compareMatches);
    return list;
  }

  Future<void> _handleGenerate() async {
    final groups = _bulkType == 'PIT_AUTO'
        ? widget.pitGroups.where((g) => _selectedGroupIds.contains(g.id)).toList()
        : <PitScoutGroup>[];
    final pool = {..._selectedScouterIds, ...groups.expand((g) => g.memberIds)};
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 scouter.')),
      );
      return;
    }

    final useTimeBlock = _bulkType != 'PIT_AUTO' && _rangeMode == 'time';
    final blockKeys = useTimeBlock ? _matchesInBlock.map((m) => m.matchKey).toList() : <String>[];
    if (useTimeBlock && blockKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matches are scheduled in the selected time block.')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final req = AutoGenerateAssignmentsRequest(
        eventKey: widget.eventKey,
        assignmentType: _bulkType,
        scouterUserIds: pool.toList(),
        pitGroups: groups,
        stageFilter: _stage,
        startMatchKey: _startMatchKey,
        endMatchKey: _endMatchKey,
        matchKeys: blockKeys,
        consecutiveMatches: _consecutiveBlocks,
        overwrite: _overwrite,
        pitScope: _pitScope,
      );

      final res = await widget.apiService.autoGenerateAssignments(req);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message.isNotEmpty
                ? res.message
                : 'Successfully created ${res.createdCount} assignments!'),
          ),
        );
        widget.onGenerated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk generation failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bulk Match Wizard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _bulkType,
              decoration: const InputDecoration(labelText: 'Bulk Type', isDense: true),
              items: const [
                DropdownMenuItem(value: 'MATCH', child: Text('Match Scouting (6 Robot Stations: Red 1-3, Blue 1-3)')),
                DropdownMenuItem(value: 'QUALITATIVE_BOTH', child: Text('Qualitative Scouting (Both Alliances: Red & Blue)')),
                DropdownMenuItem(value: 'QUALITATIVE_RED', child: Text('Qualitative Scouting (Red Alliance Only)')),
                DropdownMenuItem(value: 'QUALITATIVE_BLUE', child: Text('Qualitative Scouting (Blue Alliance Only)')),
                DropdownMenuItem(value: 'QUALITATIVE_TEAMS', child: Text('Qualitative Scouting (Individual Match Teams: 6 Teams)')),
                DropdownMenuItem(value: 'PIT_AUTO', child: Text('Pit Scouting (Auto-Distribute Attending Teams)')),
              ],
              onChanged: (val) => setState(() => _bulkType = val ?? 'MATCH'),
            ),
            const SizedBox(height: 10),
            if (_bulkType != 'PIT_AUTO') ...[
              DropdownButtonFormField<String>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: 'Match Stage Filter', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Matches')),
                  DropdownMenuItem(value: 'qm', child: Text('Qualification Matches (QM)')),
                  DropdownMenuItem(value: 'pr', child: Text('Practice Matches (PM)')),
                  DropdownMenuItem(value: 'playoffs', child: Text('Playoff Matches (QF/SF/F)')),
                ],
                onChanged: (val) {
                  setState(() {
                    _stage = val ?? 'all';
                    final available = _stageMatches;
                    if (available.isNotEmpty) {
                      _startMatchKey = available.first.matchKey;
                      _endMatchKey = available.last.matchKey;
                    } else {
                      _startMatchKey = null;
                      _endMatchKey = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _rangeMode,
                decoration: const InputDecoration(labelText: 'Assign By', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'matches', child: Text('Match Range')),
                  DropdownMenuItem(value: 'time', child: Text('Time Block (Shift)')),
                ],
                onChanged: (val) => setState(() {
                  _rangeMode = val ?? 'matches';
                  if (_rangeMode == 'time') _ensureTimeDay();
                }),
              ),
              const SizedBox(height: 10),
              if (_rangeMode == 'time')
                Builder(
                  builder: (context) {
                    _ensureTimeDay();
                    final days = _matchDays;
                    final inBlock = _matchesInBlock;
                    final badRange = _minutesOf(_shiftEnd) <= _minutesOf(_shiftStart);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey('day-$_stage'),
                          initialValue: _timeDay,
                          decoration: const InputDecoration(labelText: 'Day', isDense: true),
                          items: days.entries
                              .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text('${_dayLabel(e.key)} (${e.value} matches)'),
                                  ))
                              .toList(),
                          onChanged: (val) => setState(() => _timeDay = val),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.schedule_rounded, size: 16),
                                label: Text('Start ${_shiftStart.format(context)}'),
                                onPressed: () => _pickShiftTime(true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.schedule_rounded, size: 16),
                                label: Text('End ${_shiftEnd.format(context)}'),
                                onPressed: () => _pickShiftTime(false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          days.isEmpty
                              ? 'No scheduled match times for this stage.'
                              : badRange
                                  ? 'Shift end must be after shift start.'
                                  : inBlock.isEmpty
                                      ? 'No matches scheduled in this time block.'
                                      : '${inBlock.length} match(es): ${inBlock.first.shortLabel} – ${inBlock.last.shortLabel}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: inBlock.isEmpty ? const Color(0xFFF59E0B) : ObsidianUITheme.primaryAccent,
                          ),
                        ),
                      ],
                    );
                  },
                )
              else
              Builder(
                builder: (context) {
                  final available = _stageMatches;
                  final validStartKey = available.any((m) => m.matchKey == _startMatchKey)
                      ? _startMatchKey
                      : (available.isNotEmpty ? available.first.matchKey : null);
                  final validEndKey = available.any((m) => m.matchKey == _endMatchKey)
                      ? _endMatchKey
                      : (available.isNotEmpty ? available.last.matchKey : null);

                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: validStartKey,
                          decoration: const InputDecoration(labelText: 'Start Match', isDense: true),
                          items: available.map((m) {
                            return DropdownMenuItem(value: m.matchKey, child: Text(m.shortLabel));
                          }).toList(),
                          onChanged: (val) => setState(() => _startMatchKey = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: validEndKey,
                          decoration: const InputDecoration(labelText: 'End Match', isDense: true),
                          items: available.map((m) {
                            return DropdownMenuItem(value: m.matchKey, child: Text(m.shortLabel));
                          }).toList(),
                          onChanged: (val) => setState(() => _endMatchKey = val),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _consecutiveBlocks,
                      decoration: const InputDecoration(labelText: 'Matches per Block', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 matches / scout')),
                        DropdownMenuItem(value: 5, child: Text('5 matches / scout')),
                        DropdownMenuItem(value: 10, child: Text('10 matches / scout')),
                      ],
                      onChanged: (val) => setState(() => _consecutiveBlocks = val ?? 5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Checkbox(value: _overwrite, onChanged: (v) => setState(() => _overwrite = v ?? false)),
                  const Text('Overwrite', style: TextStyle(fontSize: 12)),
                ],
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _pitScope,
                decoration: const InputDecoration(labelText: 'Teams Scope', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'unassigned', child: Text('Unassigned Teams Only')),
                  DropdownMenuItem(value: 'all', child: Text('All Attending Teams')),
                ],
                onChanged: (val) => setState(() => _pitScope = val ?? 'unassigned'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(value: _overwrite, onChanged: (v) => setState(() => _overwrite = v ?? false)),
                  const Text('Overwrite existing pit assignments', style: TextStyle(fontSize: 12)),
                ],
              ),
              _PitGroupChecklist(
                groups: widget.pitGroups,
                users: widget.users,
                selectedIds: _selectedGroupIds,
                onChanged: () => setState(() {}),
              ),
            ],
            const SizedBox(height: 14),
            _ScouterChecklist(
              title: 'Scouters for Pool',
              users: widget.users,
              selectedIds: _selectedScouterIds,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isGenerating ? null : _handleGenerate,
                child: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Generate Bulk Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// BOTTOM SHEET: PLANNED SHIFTS
// ==========================================
/// Shifts planned by time before the match schedule is out. Each scout gets a seat (a robot station, or an
/// alliance for qualitative) and keeps it for every match in the window. The server fills the open slots
/// every time the schedule syncs; this sheet only creates, edits and deletes shifts.
class _PlannedShiftsBottomSheet extends StatefulWidget {
  final ApiService apiService;
  final String eventKey;
  final EventModel? event;
  final List<UserModel> users;

  /// Robot stations per alliance: 3 for FRC, 2 for FTC.
  final int stationsPerAlliance;
  final VoidCallback onAssignmentsCreated;

  const _PlannedShiftsBottomSheet({
    required this.apiService,
    required this.eventKey,
    required this.event,
    required this.users,
    required this.stationsPerAlliance,
    required this.onAssignmentsCreated,
  });

  @override
  State<_PlannedShiftsBottomSheet> createState() => _PlannedShiftsBottomSheetState();
}

class _PlannedShiftsBottomSheetState extends State<_PlannedShiftsBottomSheet> {
  static const _stageFallbacks = {'all': 'All stages', 'qm': 'Quals', 'pr': 'Practice', 'playoffs': 'Playoffs'};
  static const _red = Color(0xFFEF4444);
  static const _blue = Color(0xFF3B82F6);

  List<AssignmentShiftView> _shifts = [];
  bool _loading = true;
  bool _busy = false;

  // Form state; [_formVersion] rebuilds the dropdowns when the form is reset or loaded for editing
  int _formVersion = 0;
  String _editingId = '';
  final TextEditingController _nameController = TextEditingController();
  DateTime? _day;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 12, minute: 0);
  String _stage = 'all';
  List<String> _matchSeats = [];
  String _qualMode = 'TEAMS';
  List<String> _qualSeats = [];

  @override
  void initState() {
    super.initState();
    _resetForm();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Robot station labels in the order the server fills them: red 1..n, then blue 1..n.
  List<(String, Color)> get _stationLabels => [
        for (var i = 1; i <= widget.stationsPerAlliance; i++)
          (context.tr('assignments.shift_seat_red', {'n': '$i'}), _red),
        for (var i = 1; i <= widget.stationsPerAlliance; i++)
          (context.tr('assignments.shift_seat_blue', {'n': '$i'}), _blue),
      ];

  String _stageLabel(String stage) => _stageFallbacks.containsKey(stage)
      ? context.tr('assignments.shift_stage_short_$stage', _stageFallbacks[stage])
      : stage;

  List<(String, Color)> _qualLabels(String mode) =>
      mode == 'ALLIANCE'
          ? [
              (context.tr('assignments.shift_seat_red_alliance', 'Red Alliance'), _red),
              (context.tr('assignments.shift_seat_blue_alliance', 'Blue Alliance'), _blue),
            ]
          : _stationLabels;

  int get _stationCount => widget.stationsPerAlliance * 2;

  int _qualCount(String mode) => mode == 'ALLIANCE' ? 2 : _stationCount;

  static List<String> _sized(List<String> ids, int length) =>
      List.generate(length, (i) => i < ids.length ? ids[i] : '');

  DateTime? _eventDay(String? value) {
    if (value == null || value.length < 10) return null;
    return DateTime.tryParse(value.substring(0, 10));
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _timeKey(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _dayLabel(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }

  String _timeLabel(String key) => _parseTime(key)?.format(context) ?? key;

  void _resetForm() {
    _formVersion++;
    _editingId = '';
    _nameController.text = '';
    _day = _eventDay(widget.event?.startDate);
    _start = const TimeOfDay(hour: 8, minute: 0);
    _end = const TimeOfDay(hour: 12, minute: 0);
    _stage = 'all';
    _qualMode = 'TEAMS';
    _matchSeats = _sized(const [], _stationCount);
    _qualSeats = _sized(const [], _qualCount(_qualMode));
  }

  void _edit(AssignmentShift s) {
    setState(() {
      _formVersion++;
      _editingId = s.id;
      _nameController.text = s.name;
      _day = DateTime.tryParse(s.day);
      _start = _parseTime(s.startTime) ?? _start;
      _end = _parseTime(s.endTime) ?? _end;
      _stage = _stageFallbacks.containsKey(s.stageFilter) ? s.stageFilter : 'all';
      _qualMode = s.qualMode;
      _matchSeats = _sized(s.matchScouterIds, _stationCount);
      _qualSeats = _sized(s.qualScouterIds, _qualCount(_qualMode));
    });
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    final res = await widget.apiService.fetchAssignmentShifts(widget.eventKey);
    if (mounted) {
      setState(() {
        _shifts = res.shifts;
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final initial = _day ?? _eventDay(widget.event?.startDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start : _end);
    if (picked != null && mounted) {
      setState(() => isStart ? _start = picked : _end = picked);
    }
  }

  Future<void> _save() async {
    final day = _day;
    if (day == null) {
      _showMessage(context.tr('assignments.shift_need_day', 'Pick the day of the shift.'));
      return;
    }
    if (_end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute) {
      _showMessage(context.tr('assignments.shift_bad_range', 'Shift end must be after shift start.'));
      return;
    }
    final picked = [..._matchSeats, ..._qualSeats].where((id) => id.isNotEmpty).toList();
    if (picked.isEmpty) {
      _showMessage(context.tr('assignments.shift_need_seat', 'Pick a scout for at least one seat.'));
      return;
    }
    if (picked.toSet().length != picked.length) {
      _showMessage(context.tr('assignments.shift_duplicate', 'Each scout can only have one seat in a shift.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.apiService.saveAssignmentShift(AssignmentShift(
        id: _editingId,
        eventKey: widget.eventKey,
        name: _nameController.text.trim(),
        day: _dayKey(day),
        startTime: _timeKey(_start),
        endTime: _timeKey(_end),
        stageFilter: _stage,
        matchScouterIds: _matchSeats,
        qualMode: _qualMode,
        qualScouterIds: _qualSeats,
      ));
      if (!mounted) return;
      setState(() {
        _shifts = res.shifts;
        _busy = false;
        _resetForm();
      });
      if (res.createdCount > 0) {
        _showMessage(context.tr('assignments.shift_saved_created', {'count': '${res.createdCount}'}));
        widget.onAssignmentsCreated();
      } else {
        _showMessage(context.tr('assignments.shift_saved_waiting', 'Shift saved. Scouts will be assigned to its matches when the schedule syncs.'));
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showMessage('${context.tr('assignments.shift_save_failed', 'Failed to save shift')}: $e');
    }
  }

  Future<void> _delete(AssignmentShift s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('assignments.shift_delete_title', 'Delete Shift')),
        content: Text(context.tr('assignments.shift_delete_confirm', 'Delete this shift? Assignments it already created will stay.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('assignments.cancel', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('assignments.shift_delete', 'Delete'), style: const TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteAssignmentShift(s.id);
      if (!mounted) return;
      if (_editingId == s.id) setState(_resetForm);
      _showMessage(context.tr('assignments.shift_deleted', 'Shift deleted'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage('${context.tr('assignments.shift_delete_failed', 'Failed to delete shift')}: $e');
    }
  }

  String _describeSeats(List<(String, Color)> labels, List<String> ids, Map<String, String> names) {
    final parts = <String>[];
    for (var i = 0; i < labels.length && i < ids.length; i++) {
      if (ids[i].isNotEmpty) parts.add('${labels[i].$1}: ${names[ids[i]] ?? '?'}');
    }
    return parts.join(', ');
  }

  Widget _buildShiftCard(AssignmentShiftView view) {
    final s = view.shift;
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final when = '${_dayLabel(s.day)} · ${_timeLabel(s.startTime)} – ${_timeLabel(s.endTime)}'
        ' · ${_stageLabel(s.stageFilter)}';
    final matchSeats = _describeSeats(_stationLabels, s.matchScouterIds, view.scouterNames);
    final qualSeats = _describeSeats(_qualLabels(s.qualMode), s.qualScouterIds, view.scouterNames);
    final applied = s.appliedCount > 0
        ? ' · ${context.tr('assignments.shift_applied', {'count': '${s.appliedCount}'})}'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: secondary.withValues(alpha: 0.3)),
        color: _editingId == s.id ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.08) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name.isNotEmpty ? s.name : when, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (s.name.isNotEmpty) Text(when, style: const TextStyle(fontSize: 12)),
                if (matchSeats.isNotEmpty)
                  Text('${context.tr('assignments.shift_list_match', 'Match')} · $matchSeats', style: TextStyle(fontSize: 12, color: secondary)),
                if (qualSeats.isNotEmpty)
                  Text('${context.tr('assignments.shift_list_qual', 'Qualitative')} · $qualSeats', style: TextStyle(fontSize: 12, color: secondary)),
                const SizedBox(height: 2),
                Text(
                  (view.matchCount > 0
                          ? context.tr('assignments.shift_in_window', {'count': '${view.matchCount}'})
                          : context.tr('assignments.shift_waiting', 'Waiting for the match schedule')) +
                      applied,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: view.matchCount > 0 ? ObsidianUITheme.primaryAccent : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('assignments.shift_edit', 'Edit'),
            icon: const Icon(Icons.edit_rounded, size: 18),
            onPressed: _busy ? null : () => _edit(s),
          ),
          IconButton(
            tooltip: context.tr('assignments.shift_delete', 'Delete'),
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _red),
            onPressed: _busy ? null : () => _delete(s),
          ),
        ],
      ),
    );
  }

  /// One searchable person picker per seat; picking "Nobody" leaves the seat open.
  Widget _buildSeatGrid(String group, List<(String, Color)> labels, List<String> seats) {
    final scouters = widget.users.where((u) => u.role != 'NONE').toList();
    final nobody = context.tr('assignments.shift_nobody', 'Nobody');
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: width,
                child: _SearchablePersonField(
                  key: ValueKey('$group-$i'),
                  label: labels[i].$1,
                  labelColor: labels[i].$2,
                  users: scouters,
                  selectedId: seats[i].isEmpty ? null : seats[i],
                  emptyOptionLabel: nobody,
                  onSelected: (id) => setState(() => seats[i] = id ?? ''),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.tr('assignments.shifts_title', 'Planned Shifts'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text(
              context.tr(
                'assignments.shifts_notice',
                'Plan who scouts when, before the match schedule is out. Give each seat a scout; they keep '
                    'that seat for every match that starts inside the shift. Every time the schedule syncs, open '
                    'slots in those matches are filled. Slots that already have a scout are never changed.',
              ),
              style: TextStyle(fontSize: 12, color: secondary),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_shifts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(context.tr('assignments.shifts_empty', 'No shifts planned for this event yet.'), style: TextStyle(fontSize: 13, color: secondary)),
              )
            else
              ..._shifts.map(_buildShiftCard),
            const Divider(height: 24),
            Text(
              _editingId.isEmpty
                  ? context.tr('assignments.shift_add_title', 'Add a Shift')
                  : context.tr('assignments.shift_edit_title', 'Edit Shift'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: context.tr('assignments.shift_name', 'Name (optional)'),
                hintText: context.tr('assignments.shift_name_placeholder', 'Friday morning'),
                isDense: true,
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(_day == null ? context.tr('assignments.shift_pick_day', 'Pick Day') : _dayLabel(_dayKey(_day!))),
                onPressed: _pickDay,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text('${context.tr('assignments.time_block_start', 'Shift Start')} ${_start.format(context)}'),
                    onPressed: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text('${context.tr('assignments.time_block_end', 'Shift End')} ${_end.format(context)}'),
                    onPressed: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                    'assignments.shift_time_hint',
                    "Times are in the event's local timezone. A match belongs to the shift if its scheduled "
                        'start is at or after the start and before the end.',
                  ) +
                  ((widget.event?.timezone ?? '').isNotEmpty ? ' (${widget.event!.timezone})' : ''),
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('shift-stage-$_formVersion'),
              initialValue: _stage,
              decoration: InputDecoration(labelText: context.tr('assignments.tournament_level', 'Tournament Stage'), isDense: true),
              items: [
                DropdownMenuItem(value: 'all', child: Text(context.tr('assignments.shift_stage_all', 'All Match Stages'))),
                DropdownMenuItem(value: 'qm', child: Text(context.tr('assignments.shift_stage_qm', 'Qualifications (qm)'))),
                DropdownMenuItem(value: 'pr', child: Text(context.tr('assignments.shift_stage_pr', 'Practice (pr)'))),
                DropdownMenuItem(value: 'playoffs', child: Text(context.tr('assignments.shift_stage_playoffs', 'Playoffs (Quarterfinals, Semis, Finals)'))),
              ],
              onChanged: (val) => setState(() => _stage = val ?? 'all'),
            ),
            const SizedBox(height: 16),
            Text(context.tr('assignments.shift_match_seats', 'Match Scouting'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildSeatGrid('match', _stationLabels, _matchSeats),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('assignments.shift_qual_seats', 'Qualitative Scouting'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                DropdownButton<String>(
                  value: _qualMode,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: 'TEAMS',
                      child: Text(context.tr('assignments.shift_qual_per_robot', 'One scout per robot'), style: const TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 'ALLIANCE',
                      child: Text(context.tr('assignments.shift_qual_per_alliance', 'One scout per alliance'), style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                  // Switching keeps the picks that still have a seat
                  onChanged: (val) => setState(() {
                    _qualMode = val ?? 'TEAMS';
                    _qualSeats = _sized(_qualSeats, _qualCount(_qualMode));
                    _matchSeats = List.of(_matchSeats);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSeatGrid('qual', _qualLabels(_qualMode), _qualSeats),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'assignments.shift_seat_hint',
                'Tap a seat to search for a scout. Pick "Nobody" to leave it open. Each scout can have one seat per shift.',
              ),
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_editingId.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => setState(_resetForm),
                      child: Text(context.tr('assignments.shift_cancel_edit', 'Cancel Edit')),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ObsidianUITheme.primaryAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(context.tr('assignments.shift_save', 'Save Shift'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// BOTTOM SHEET: AUTO-ASSIGN PIT
// ==========================================
class _PitAutoBottomSheet extends StatefulWidget {
  final ApiService apiService;
  final String eventKey;
  final List<TeamModel> teams;
  final List<UserModel> users;
  final List<ScoutingAssignment> existingAssignments;
  final List<PitScoutGroup> pitGroups;
  final VoidCallback onGenerated;

  const _PitAutoBottomSheet({
    required this.apiService,
    required this.eventKey,
    required this.teams,
    required this.users,
    required this.existingAssignments,
    this.pitGroups = const [],
    required this.onGenerated,
  });

  @override
  State<_PitAutoBottomSheet> createState() => _PitAutoBottomSheetState();
}

class _PitAutoBottomSheetState extends State<_PitAutoBottomSheet> {
  String _scope = 'unassigned'; // unassigned, all
  bool _overwrite = false;
  final Set<String> _selectedScouterIds = {};
  final Set<String> _selectedGroupIds = {};
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _selectedScouterIds.addAll(widget.users.map((u) => u.id));
  }

  List<PitScoutGroup> get _checkedGroups =>
      widget.pitGroups.where((g) => _selectedGroupIds.contains(g.id) && g.memberIds.isNotEmpty).toList();

  String get _summary {
    final pitTeams = widget.existingAssignments
        .where((a) => a.assignmentType == 'PIT')
        .map((a) => a.targetTeamNumber)
        .toSet();
    final teamCount = _scope == 'unassigned'
        ? widget.teams.where((t) => !pitTeams.contains(t.teamNumber)).length
        : widget.teams.length;
    final groups = _checkedGroups;
    final grouped = groups.expand((g) => g.memberIds).toSet();
    final solo = _selectedScouterIds.where((id) => !grouped.contains(id)).length;
    final units = groups.length + solo;
    if (units == 0) return 'Select at least 1 scouter or group.';
    final parts = [
      if (groups.isNotEmpty) '${groups.length} group${groups.length == 1 ? '' : 's'}',
      if (solo > 0) '$solo solo scout${solo == 1 ? '' : 's'}',
    ];
    return '$teamCount team${teamCount == 1 ? '' : 's'} across ${parts.join(' + ')} (~${(teamCount / units).toStringAsFixed(1)} each)';
  }

  Future<void> _handleGenerate() async {
    final groups = _checkedGroups;
    final pool = {..._selectedScouterIds, ...groups.expand((g) => g.memberIds)};
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 pit scouter or group.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final req = AutoGenerateAssignmentsRequest(
        eventKey: widget.eventKey,
        assignmentType: 'PIT_AUTO',
        scouterUserIds: pool.toList(),
        pitGroups: groups,
        pitScope: _scope,
        overwrite: _overwrite,
      );

      final res = await widget.apiService.autoGenerateAssignments(req);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message.isNotEmpty
                ? res.message
                : 'Created ${res.createdCount} pit assignments!'),
          ),
        );
        widget.onGenerated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pit auto-assignment failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Auto-Assign Pit Scouters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _scope,
                    decoration: const InputDecoration(labelText: 'Scope', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'unassigned', child: Text('Unassigned Teams Only')),
                      DropdownMenuItem(value: 'all', child: Text('All Attending Teams')),
                    ],
                    onChanged: (val) => setState(() => _scope = val ?? 'unassigned'),
                  ),
                ),
                const SizedBox(width: 10),
                Checkbox(value: _overwrite, onChanged: (v) => setState(() => _overwrite = v ?? false)),
                const Text('Overwrite', style: TextStyle(fontSize: 12)),
              ],
            ),
            _PitGroupChecklist(
              groups: widget.pitGroups,
              users: widget.users,
              selectedIds: _selectedGroupIds,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 14),
            _ScouterChecklist(
              title: 'Pit Scouters',
              users: widget.users,
              selectedIds: _selectedScouterIds,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _summary,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isGenerating ? null : _handleGenerate,
                child: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Distribute Pit Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentIndex {
  final List<ScoutingAssignment> assignments;
  final List<MatchModel> matches;

  final List<ScoutingAssignment> matchAssignments;
  final List<ScoutingAssignment> qualAssignments;
  final List<ScoutingAssignment> pitAssignments;

  final Map<String, List<ScoutingAssignment>> matchSlotMap;
  final Map<String, List<ScoutingAssignment>> qualAllianceMap;
  final Map<String, List<ScoutingAssignment>> qualTeamMap;
  final Map<int, List<ScoutingAssignment>> pitTeamMap;

  final Set<String> conflictIdsToDelete;
  final Map<String, List<String>> matchConflicts;
  final Map<String, String> slotConflictTooltips;
  final int totalConflictCount;

  _AssignmentIndex._({
    required this.assignments,
    required this.matches,
    required this.matchAssignments,
    required this.qualAssignments,
    required this.pitAssignments,
    required this.matchSlotMap,
    required this.qualAllianceMap,
    required this.qualTeamMap,
    required this.pitTeamMap,
    required this.conflictIdsToDelete,
    required this.matchConflicts,
    required this.slotConflictTooltips,
    required this.totalConflictCount,
  });

  static _AssignmentIndex empty() {
    return _AssignmentIndex._(
      assignments: const [],
      matches: const [],
      matchAssignments: const [],
      qualAssignments: const [],
      pitAssignments: const [],
      matchSlotMap: const {},
      qualAllianceMap: const {},
      qualTeamMap: const {},
      pitTeamMap: const {},
      conflictIdsToDelete: const {},
      matchConflicts: const {},
      slotConflictTooltips: const {},
      totalConflictCount: 0,
    );
  }

  factory _AssignmentIndex.compute(
    List<ScoutingAssignment> assignments,
    List<MatchModel> matches,
  ) {
    final matchAssignments = <ScoutingAssignment>[];
    final qualAssignments = <ScoutingAssignment>[];
    final pitAssignments = <ScoutingAssignment>[];

    final matchSlotMap = <String, List<ScoutingAssignment>>{};
    final qualAllianceMap = <String, List<ScoutingAssignment>>{};
    final qualTeamMap = <String, List<ScoutingAssignment>>{};
    final pitTeamMap = <int, List<ScoutingAssignment>>{};

    // Fast O(1) match lookup table by matchKey and normalized (compLevel + matchNumber)
    final matchByKey = <String, MatchModel>{};
    for (final m in matches) {
      final k = m.matchKey.trim().toLowerCase();
      if (k.isNotEmpty) {
        matchByKey[k] = m;
      }
      final normLvl = MatchFormatUtils.normalizeCompLevel(m.compLevel);
      if (m.matchNumber != null) {
        matchByKey['${normLvl}_${m.matchNumber}'] = m;
        final setNum = MatchFormatUtils.extractSetNumber(m.matchKey);
        if (setNum != null) {
          matchByKey['${normLvl}_${setNum}_${m.matchNumber}'] = m;
        }
      }
    }

    MatchModel? resolveMatch(ScoutingAssignment a) {
      final k = (a.matchKey ?? '').trim().toLowerCase();
      if (k.isNotEmpty && matchByKey.containsKey(k)) {
        return matchByKey[k];
      }
      final cLvl = MatchFormatUtils.normalizeCompLevel(a.compLevel);
      final mNum = a.matchNumber ?? MatchFormatUtils.extractMatchNumber(a.matchKey, null);
      if (mNum != null) {
        final setNum = MatchFormatUtils.extractSetNumber(a.matchKey);
        if (setNum != null && matchByKey.containsKey('${cLvl}_${setNum}_$mNum')) {
          return matchByKey['${cLvl}_${setNum}_$mNum'];
        }
        if (matchByKey.containsKey('${cLvl}_$mNum')) {
          return matchByKey['${cLvl}_$mNum'];
        }
      }
      return null;
    }

    final rawSlotGroups = <String, List<ScoutingAssignment>>{};
    final qualAllianceByMatch = <String, Map<String, List<ScoutingAssignment>>>{};
    final qualTeamsByMatch = <String, Map<int, List<ScoutingAssignment>>>{};
    final userAssignmentsByMatch = <String, Map<String, List<ScoutingAssignment>>>{};

    for (final a in assignments) {
      final resolved = resolveMatch(a);
      final mKey = (resolved?.matchKey ?? a.matchKey ?? '').trim().toLowerCase();
      final cLvl = MatchFormatUtils.normalizeCompLevel(a.compLevel != null && a.compLevel!.isNotEmpty ? a.compLevel : resolved?.compLevel);
      final mNum = a.matchNumber ?? resolved?.matchNumber ?? MatchFormatUtils.extractMatchNumber(mKey, null);
      final matchIdentifier = mKey.isNotEmpty ? mKey : '${cLvl}_$mNum';

      if (a.assignmentType == 'MATCH') {
        matchAssignments.add(a);
        if (a.targetTeamNumber != null) {
          matchSlotMap.putIfAbsent('${mKey}_${a.targetTeamNumber}', () => []).add(a);
          rawSlotGroups.putIfAbsent('MATCH:$matchIdentifier:${a.targetTeamNumber}', () => []).add(a);
        }
        if (mKey.isNotEmpty && a.assignedUserId.isNotEmpty) {
          userAssignmentsByMatch
              .putIfAbsent(mKey, () => {})
              .putIfAbsent(a.assignedUserId, () => [])
              .add(a);
        }
      } else if (a.assignmentType == 'QUALITATIVE') {
        qualAssignments.add(a);
        final rawAlliance = (a.allianceColor ?? a.targetAlliance ?? '').trim().toUpperCase();
        final alliance = (rawAlliance == 'RED' || rawAlliance == 'BLUE') ? rawAlliance : '';

        if (a.targetTeamNumber != null) {
          qualTeamMap.putIfAbsent('${mKey}_${a.targetTeamNumber}', () => []).add(a);
          rawSlotGroups.putIfAbsent('QUAL:$matchIdentifier:team_${a.targetTeamNumber}', () => []).add(a);
          if (mKey.isNotEmpty) {
            qualTeamsByMatch
                .putIfAbsent(mKey, () => {})
                .putIfAbsent(a.targetTeamNumber!, () => [])
                .add(a);
          }
        } else if (alliance.isNotEmpty) {
          qualAllianceMap.putIfAbsent('${mKey}_$alliance', () => []).add(a);
          rawSlotGroups.putIfAbsent('QUAL:$matchIdentifier:alliance_${alliance.toLowerCase()}', () => []).add(a);
          if (mKey.isNotEmpty) {
            qualAllianceByMatch
                .putIfAbsent(mKey, () => {})
                .putIfAbsent(alliance, () => [])
                .add(a);
          }
        }
        if (mKey.isNotEmpty && a.assignedUserId.isNotEmpty) {
          userAssignmentsByMatch
              .putIfAbsent(mKey, () => {})
              .putIfAbsent(a.assignedUserId, () => [])
              .add(a);
        }
      } else if (a.assignmentType == 'PIT') {
        pitAssignments.add(a);
        if (a.targetTeamNumber != null) {
          pitTeamMap.putIfAbsent(a.targetTeamNumber!, () => []).add(a);
          rawSlotGroups.putIfAbsent('PIT:${a.targetTeamNumber}', () => []).add(a);
        }
      }
    }

    final toDelete = <String>{};
    final matchConflicts = <String, List<String>>{};
    final slotConflictTooltips = <String, String>{};

    // 1. Same-slot duplicate assignments (a pit group on one team counts as a single assignee)
    for (final entry in rawSlotGroups.entries) {
      final list = entry.value;
      final isPit = entry.key.startsWith('PIT:');
      if (isPit ? groupPitUnits(list).length > 1 : list.length > 1) {
        final sorted = List<ScoutingAssignment>.from(list)..sort((x, y) {
          int score(ScoutingAssignment a) =>
              a.status == 'COMPLETED' ? 3 : (a.status == 'IN_PROGRESS' ? 2 : 1);
          if (score(x) != score(y)) return score(y) - score(x);
          if ((x.notes != null && x.notes!.isNotEmpty) !=
              (y.notes != null && y.notes!.isNotEmpty)) {
            return (x.notes != null && x.notes!.isNotEmpty) ? -1 : 1;
          }
          return 0;
        });

        final names = list.map((a) => '@${a.assignedUserDisplayName ?? a.assignedUsername}').join(', ');
        final slotDesc = entry.key.startsWith('MATCH:')
            ? 'Team #${list.first.targetTeamNumber}'
            : (entry.key.startsWith('PIT:')
                ? 'Pit Team #${list.first.targetTeamNumber}'
                : (list.first.targetTeamNumber != null
                    ? 'Qualitative Team #${list.first.targetTeamNumber}'
                    : 'Qualitative ${list.first.allianceColor ?? list.first.targetAlliance ?? "Alliance"}'));

        final errorMsg = '$slotDesc has ${list.length} scouts assigned ($names)';
        slotConflictTooltips[entry.key] = errorMsg;

        for (final a in list) {
          if (a.matchKey != null && a.matchKey!.isNotEmpty) {
            matchConflicts.putIfAbsent(a.matchKey!.toLowerCase(), () => []).add(errorMsg);
          }
        }

        for (int i = 1; i < sorted.length; i++) {
          if (isPit && sorted[i].pitUnitKey == sorted.first.pitUnitKey) continue;
          toDelete.add(sorted[i].id);
        }
      }
    }

    // 2. Redundant qualitative scouting (Alliance + Individual team)
    for (final match in matches) {
      final mKey = match.matchKey.toLowerCase();
      final allianceMap = qualAllianceByMatch[mKey];
      final teamMap = qualTeamsByMatch[mKey];
      if (allianceMap == null || teamMap == null) continue;

      for (final alliance in ['RED', 'BLUE']) {
        final allianceAsgns = allianceMap[alliance];
        if (allianceAsgns == null || allianceAsgns.isEmpty) continue;
        final allianceAsgn = allianceAsgns.where((a) => !toDelete.contains(a.id)).firstOrNull;
        if (allianceAsgn == null) continue;

        final teamKeys = alliance == 'RED' ? match.redTeams : match.blueTeams;
        final teamNums = teamKeys
            .map((k) => int.tryParse(k.replaceAll(RegExp(r'[^0-9]'), '')))
            .whereType<int>()
            .toList();

        final teamAsgns = <ScoutingAssignment>[];
        for (final tn in teamNums) {
          final tList = teamMap[tn];
          if (tList != null) {
            teamAsgns.addAll(tList.where((a) => !toDelete.contains(a.id)));
          }
        }

        if (teamAsgns.isNotEmpty) {
          final teamNames = teamAsgns.map((t) => '#${t.targetTeamNumber} (@${t.assignedUserDisplayName ?? t.assignedUsername})').join(', ');
          final errorMsg = '$alliance Alliance qualitative is assigned to @${allianceAsgn.assignedUserDisplayName ?? allianceAsgn.assignedUsername}, but individual team scout(s) are also assigned: $teamNames';

          matchConflicts.putIfAbsent(mKey, () => []).add(errorMsg);
          slotConflictTooltips['QUAL:$mKey:alliance_${alliance.toLowerCase()}'] = errorMsg;
          for (final t in teamAsgns) {
            slotConflictTooltips['QUAL:$mKey:team_${t.targetTeamNumber}'] = errorMsg;
          }

          final completedTeam = teamAsgns.where((t) => t.status == 'COMPLETED').firstOrNull;
          if (completedTeam != null && allianceAsgn.status != 'COMPLETED') {
            toDelete.add(allianceAsgn.id);
          } else {
            for (final t in teamAsgns) {
              toDelete.add(t.id);
            }
          }
        }
      }
    }

    // 3. Dual-scouter match overlaps
    for (final match in matches) {
      final mKey = match.matchKey.toLowerCase();
      final userGroups = userAssignmentsByMatch[mKey];
      if (userGroups == null) continue;

      for (final userAsgns in userGroups.values) {
        final activeUserAsgns = userAsgns.where((a) => !toDelete.contains(a.id)).toList();
        final isBothAlliancesQualPair = activeUserAsgns.length == 2 &&
            activeUserAsgns.every((a) => a.assignmentType == 'QUALITATIVE' && a.targetTeamNumber == null) &&
            ((activeUserAsgns[0].allianceColor ?? activeUserAsgns[0].targetAlliance ?? '').toUpperCase() !=
                (activeUserAsgns[1].allianceColor ?? activeUserAsgns[1].targetAlliance ?? '').toUpperCase());

        if (activeUserAsgns.length > 1 && !isBothAlliancesQualPair) {
          final uName = activeUserAsgns.first.assignedUserDisplayName ?? activeUserAsgns.first.assignedUsername;
          final roleDescs = activeUserAsgns.map((a) => a.assignmentType == 'MATCH' ? 'Match #${a.targetTeamNumber}' : (a.targetAlliance != null ? '${a.targetAlliance} Qual' : 'Team #${a.targetTeamNumber} Qual')).join(' and ');
          final errorMsg = 'Scouter @$uName is assigned to multiple overlapping roles in ${match.shortLabel}: $roleDescs';

          matchConflicts.putIfAbsent(mKey, () => []).add(errorMsg);

          final sorted = List<ScoutingAssignment>.from(activeUserAsgns)..sort((x, y) {
            if ((x.status == 'COMPLETED') != (y.status == 'COMPLETED')) {
              return x.status == 'COMPLETED' ? -1 : 1;
            }
            if ((x.assignmentType == 'MATCH') != (y.assignmentType == 'MATCH')) {
              return x.assignmentType == 'MATCH' ? -1 : 1;
            }
            if ((x.status == 'IN_PROGRESS') != (y.status == 'IN_PROGRESS')) {
              return x.status == 'IN_PROGRESS' ? -1 : 1;
            }
            return 0;
          });
          for (int i = 1; i < sorted.length; i++) {
            toDelete.add(sorted[i].id);
          }
        }
      }
    }

    for (final k in matchConflicts.keys) {
      matchConflicts[k] = matchConflicts[k]!.toSet().toList();
    }

    return _AssignmentIndex._(
      assignments: assignments,
      matches: matches,
      matchAssignments: matchAssignments,
      qualAssignments: qualAssignments,
      pitAssignments: pitAssignments,
      matchSlotMap: matchSlotMap,
      qualAllianceMap: qualAllianceMap,
      qualTeamMap: qualTeamMap,
      pitTeamMap: pitTeamMap,
      conflictIdsToDelete: toDelete,
      matchConflicts: matchConflicts,
      slotConflictTooltips: slotConflictTooltips,
      totalConflictCount: toDelete.length,
    );
  }

  bool hasMatchConflict(MatchModel match, [String? type]) {
    final mKey = match.matchKey.toLowerCase();
    if (!matchConflicts.containsKey(mKey) || matchConflicts[mKey]!.isEmpty) {
      return false;
    }
    if (type == null) return true;
    return assignments.any((a) =>
        conflictIdsToDelete.contains(a.id) &&
        a.isMatchFor(match) &&
        a.assignmentType == type);
  }

  String? getMatchConflictTooltip(MatchModel match, [String? type]) {
    final mKey = match.matchKey.toLowerCase();
    final list = matchConflicts[mKey];
    if (list == null || list.isEmpty) return null;
    return 'Conflicts in ${match.shortLabel}:\n• ${list.join('\n• ')}';
  }

  String? getSlotConflictTooltip(String key) {
    return slotConflictTooltips[key] ?? slotConflictTooltips[key.toLowerCase()];
  }

  List<ScoutingAssignment> getMatchSlot(MatchModel match, int teamNumber) {
    final key = '${match.matchKey.toLowerCase()}_$teamNumber';
    return matchSlotMap[key] ?? const [];
  }

  List<ScoutingAssignment> getQualAlliance(MatchModel match, String alliance) {
    final key = '${match.matchKey.toLowerCase()}_${alliance.toUpperCase()}';
    return qualAllianceMap[key] ?? const [];
  }

  List<ScoutingAssignment> getQualTeam(MatchModel match, int teamNumber) {
    final key = '${match.matchKey.toLowerCase()}_$teamNumber';
    return qualTeamMap[key] ?? const [];
  }

  List<ScoutingAssignment> getPitTeam(int teamNumber) {
    return pitTeamMap[teamNumber] ?? const [];
  }
}


/// Splits a team's pit assignments into units: one per scout group, one per ungrouped row.
List<List<ScoutingAssignment>> groupPitUnits(List<ScoutingAssignment> list) {
  final units = <String, List<ScoutingAssignment>>{};
  for (final a in list) {
    units.putIfAbsent(a.pitUnitKey, () => []).add(a);
  }
  return units.values.toList();
}

String _userLabel(List<UserModel> users, String id) {
  final u = users.where((u) => u.id == id).firstOrNull;
  if (u == null) return 'Unknown';
  return u.displayName.isNotEmpty ? u.displayName : u.username;
}

/// Checkbox list of saved pit groups for the auto-assign sheets.
class _PitGroupChecklist extends StatelessWidget {
  final List<PitScoutGroup> groups;
  final List<UserModel> users;
  final Set<String> selectedIds;
  final VoidCallback onChanged;

  const _PitGroupChecklist({
    required this.groups,
    required this.users,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Pit Groups (scout together):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        if (groups.isEmpty)
          Text(
            'No pit groups yet. Create them with the Pit Groups button.',
            style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context)),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
            child: ListView(
              shrinkWrap: true,
              children: groups.map((g) {
                return CheckboxListTile(
                  dense: true,
                  value: selectedIds.contains(g.id),
                  title: Text(g.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    g.memberIds.map((id) => _userLabel(users, id)).join(', '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) {
                    if (v == true) {
                      selectedIds.add(g.id);
                    } else {
                      selectedIds.remove(g.id);
                    }
                    onChanged();
                  },
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Each checked group takes a team as one unit. Selected scouters not in a checked group still get their own teams.',
          style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context)),
        ),
      ],
    );
  }
}

// ==========================================
// BOTTOM SHEET: MANAGE PIT SCOUT GROUPS
// ==========================================
class _PitGroupsBottomSheet extends StatefulWidget {
  final ApiService apiService;
  final List<UserModel> users;
  final List<PitScoutGroup> groups;
  final ValueChanged<List<PitScoutGroup>> onSaved;

  const _PitGroupsBottomSheet({
    required this.apiService,
    required this.users,
    required this.groups,
    required this.onSaved,
  });

  @override
  State<_PitGroupsBottomSheet> createState() => _PitGroupsBottomSheetState();
}

class _EditableGroup {
  final String id;
  final TextEditingController name;
  final Set<String> memberIds;

  _EditableGroup(this.id, String initialName, Iterable<String> members)
      : name = TextEditingController(text: initialName),
        memberIds = members.toSet();
}

class _PitGroupsBottomSheetState extends State<_PitGroupsBottomSheet> {
  late final List<_EditableGroup> _groups;
  bool _isSaving = false;
  String _memberQuery = '';

  @override
  void initState() {
    super.initState();
    _groups = widget.groups.map((g) => _EditableGroup(g.id, g.name, g.memberIds)).toList();
    if (_groups.isEmpty) _addGroup();
  }

  @override
  void dispose() {
    for (final g in _groups) {
      g.name.dispose();
    }
    super.dispose();
  }

  void _addGroup() {
    _groups.add(_EditableGroup('grp-${DateTime.now().microsecondsSinceEpoch}', '', const []));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final out = <PitScoutGroup>[];
    final seen = <String>{};
    for (final g in _groups) {
      final name = g.name.text.trim();
      if (name.isEmpty && g.memberIds.isEmpty) continue;
      if (name.isEmpty) return _showError('Every group needs a name.');
      if (!seen.add(name.toLowerCase())) return _showError('Group name "$name" is used twice.');
      if (g.memberIds.isEmpty) return _showError('Group "$name" has no members.');
      out.add(PitScoutGroup(id: g.id, name: name, memberIds: g.memberIds.toList()));
    }

    setState(() => _isSaving = true);
    try {
      final saved = await widget.apiService.savePitScoutGroups(out);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        widget.onSaved(saved);
        messenger.showSnackBar(
          SnackBar(content: Text('Saved ${saved.length} pit group${saved.length == 1 ? '' : 's'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showError('Failed to save pit groups: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pit Scout Groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text(
              'Pit scouting is usually 2-3 people walking the pits together. Build groups here, then assign a whole group to a team manually or with Auto-Assign.',
              style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search team members...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _memberQuery = v),
            ),
            const SizedBox(height: 10),
            ..._groups.map((g) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ObsidianUITheme.getBorderColor(context).withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: g.name,
                            maxLength: 64,
                            decoration: const InputDecoration(
                              labelText: 'Group name',
                              hintText: 'e.g. Pit Crew A',
                              isDense: true,
                              counterText: '',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove group',
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                          onPressed: () => setState(() {
                            _groups.remove(g);
                            g.name.dispose();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      // Members already in the group stay visible while searching
                      children: widget.users
                          .where((u) => g.memberIds.contains(u.id) || _userMatches(u, _memberQuery))
                          .map((u) {
                        final selected = g.memberIds.contains(u.id);
                        return FilterChip(
                          label: Text(u.displayName.isNotEmpty ? u.displayName : u.username,
                              style: const TextStyle(fontSize: 11.5)),
                          selected: selected,
                          selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                          onSelected: (v) => setState(() {
                            if (v) {
                              g.memberIds.add(u.id);
                            } else {
                              g.memberIds.remove(u.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(_addGroup),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Group'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Groups', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _userMatches(UserModel u, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return u.displayName.toLowerCase().contains(q) || u.username.toLowerCase().contains(q);
}

/// Checkbox list of team members with a search box; All / Clear act on the people the search shows.
class _ScouterChecklist extends StatefulWidget {
  final String title;
  final List<UserModel> users;
  final Set<String> selectedIds;
  final VoidCallback onChanged;

  const _ScouterChecklist({
    required this.title,
    required this.users,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<_ScouterChecklist> createState() => _ScouterChecklistState();
}

class _ScouterChecklistState extends State<_ScouterChecklist> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.users.where((u) => _userMatches(u, _query)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${widget.title} (${widget.selectedIds.length} selected)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    widget.selectedIds.addAll(visible.map((u) => u.id));
                    widget.onChanged();
                  },
                  child: Text(_query.isEmpty ? 'All' : 'All shown', style: const TextStyle(fontSize: 11)),
                ),
                TextButton(
                  onPressed: () {
                    widget.selectedIds.removeAll(visible.map((u) => u.id));
                    widget.onChanged();
                  },
                  child: Text(_query.isEmpty ? 'Clear' : 'Clear shown', style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search people...',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 6),
        Container(
          height: 160,
          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
          child: visible.isEmpty
              ? const Center(child: Text('No one matches that search.', style: TextStyle(fontSize: 12)))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (c, idx) {
                    final u = visible[idx];
                    return CheckboxListTile(
                      title: Text(u.displayName.isNotEmpty ? u.displayName : u.username, style: const TextStyle(fontSize: 12)),
                      value: widget.selectedIds.contains(u.id),
                      dense: true,
                      onChanged: (v) {
                        if (v == true) {
                          widget.selectedIds.add(u.id);
                        } else {
                          widget.selectedIds.remove(u.id);
                        }
                        widget.onChanged();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A form field that opens a searchable list of team members instead of a long dropdown.
class _SearchablePersonField extends StatelessWidget {
  final String label;
  final List<UserModel> users;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  /// When set, adds a first entry that clears the pick (e.g. "All Scouters").
  final String? emptyOptionLabel;
  final bool showRole;
  final Color? labelColor;

  const _SearchablePersonField({
    super.key,
    required this.label,
    required this.users,
    required this.selectedId,
    required this.onSelected,
    this.emptyOptionLabel,
    this.showRole = false,
    this.labelColor,
  });

  String _name(UserModel u) => u.displayName.isNotEmpty ? u.displayName : u.username;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PersonSearchSheet(
        title: label,
        users: users,
        selectedId: selectedId,
        emptyOptionLabel: emptyOptionLabel,
        showRole: showRole,
      ),
    );
    // '' is the empty option; null means the sheet was dismissed
    if (picked != null) onSelected(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final selected = users.where((u) => u.id == selectedId).firstOrNull;
    final text = selected != null
        ? (showRole ? '${_name(selected)} (${selected.roleDisplayLabel})' : _name(selected))
        : (emptyOptionLabel ?? context.tr('assignments.select_member', 'Select team member...'));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: labelColor != null ? TextStyle(color: labelColor, fontWeight: FontWeight.bold) : null,
          isDense: true,
          suffixIcon: const Icon(Icons.search_rounded, size: 18),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: selected == null ? TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)) : null,
        ),
      ),
    );
  }
}

class _PersonSearchSheet extends StatefulWidget {
  final String title;
  final List<UserModel> users;
  final String? selectedId;
  final String? emptyOptionLabel;
  final bool showRole;

  const _PersonSearchSheet({
    required this.title,
    required this.users,
    required this.selectedId,
    required this.emptyOptionLabel,
    required this.showRole,
  });

  @override
  State<_PersonSearchSheet> createState() => _PersonSearchSheetState();
}

class _PersonSearchSheetState extends State<_PersonSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.users.where((u) => _userMatches(u, _query)).toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.tr('assignments.person_search_hint', 'Search by name or username...'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _query = v),
              // Enter picks the only match
              onSubmitted: (_) {
                if (visible.length == 1) Navigator.pop(context, visible.first.id);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (widget.emptyOptionLabel != null && _query.trim().isEmpty)
                    ListTile(
                      dense: true,
                      title: Text(widget.emptyOptionLabel!),
                      trailing: widget.selectedId == null ? const Icon(Icons.check_rounded, size: 18) : null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(context.tr('assignments.person_search_none', 'No one matches that search.'))),
                    ),
                  ...visible.map((u) {
                    final name = u.displayName.isNotEmpty ? u.displayName : u.username;
                    return ListTile(
                      dense: true,
                      title: Text(name),
                      subtitle: Text(widget.showRole ? '@${u.username} · ${u.roleDisplayLabel}' : '@${u.username}'),
                      trailing: u.id == widget.selectedId ? const Icon(Icons.check_rounded, size: 18) : null,
                      onTap: () => Navigator.pop(context, u.id),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
