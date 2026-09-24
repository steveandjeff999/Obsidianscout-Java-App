import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/assignment_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/scout_history_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import 'match_scout_screen.dart';
import 'pit_scout_screen.dart';
import 'qual_scout_screen.dart';

class MyAssignmentsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final void Function(String? matchKey, int? matchNumber, int? targetTeamNumber, String? sourceAssignmentId)? onNavigateMatch;
  final void Function(int? targetTeamNumber, String? sourceAssignmentId)? onNavigatePit;
  final void Function(String? matchKey, int? matchNumber, String? allianceColor, int? targetTeamNumber, String? sourceAssignmentId)? onNavigateQual;

  const MyAssignmentsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.onNavigateMatch,
    this.onNavigatePit,
    this.onNavigateQual,
  });

  @override
  State<MyAssignmentsScreen> createState() => _MyAssignmentsScreenState();
}

class _MyAssignmentsScreenState extends State<MyAssignmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _countdownTimer;

  String? _eventKey;
  List<ScoutingAssignment> _assignments = [];
  List<TeamModel> _teams = [];
  List<MatchModel> _matches = [];

  List<ScoutingAssignment> _cachedActive = [];
  List<ScoutingAssignment> _cachedCompleted = [];
  List<ScoutingAssignment> _cachedAll = [];
  ScoutingAssignment? _cachedNextUp;
  Map<String, MatchModel> _matchesByKey = {};
  Map<int, TeamModel> _teamsByNumber = {};

  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _startCountdownTimer();
  }

  @override
  void didUpdateWidget(covariant MyAssignmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && widget.isVisible) {
        setState(() {});
      }
    });
  }

  void _recomputeCachedLists() {
    _matchesByKey = {for (final m in _matches) m.matchKey.toLowerCase(): m};
    _teamsByNumber = {for (final t in _teams) t.teamNumber: t};

    _cachedActive = _assignments
        .where((a) => a.status == 'PENDING' || a.status == 'IN_PROGRESS')
        .toList()
      ..sort((a, b) {
        final timeA = a.effectiveScheduledTime;
        final timeB = b.effectiveScheduledTime;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

    _cachedCompleted = _assignments
        .where((a) => a.status == 'COMPLETED' || a.status == 'SKIPPED')
        .toList()
      ..sort((a, b) => (b.effectiveScheduledTime ?? 0).compareTo(a.effectiveScheduledTime ?? 0));

    _cachedAll = List.from(_assignments)
      ..sort((a, b) {
        final timeA = a.effectiveScheduledTime;
        final timeB = b.effectiveScheduledTime;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

    if (_cachedActive.isEmpty) {
      _cachedNextUp = null;
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      ScoutingAssignment? next;
      for (final a in _cachedActive) {
        final time = a.effectiveScheduledTime;
        if (time != null) {
          final diff = time - now;
          if (diff > -12 * 3600 * 1000 && diff <= 2 * 3600 * 1000) {
            next = a;
            break;
          }
        } else {
          next = a;
          break;
        }
      }
      _cachedNextUp = next ?? _cachedActive.firstOrNull;
    }
  }

  Future<void> _loadData() async {
    // 1. Instant Cache Hydration (0ms)
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    final cachedAssignments =
        await widget.apiService.getCachedMyAssignments(cachedEventKey);
    final hydratedAssignments = await ScoutHistoryService.applyLocalScoutStatus(
      cachedAssignments,
      eventKey: cachedEventKey,
    );
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);
    final cachedMatches = await widget.apiService.getCachedMatches(cachedEventKey);

    if (mounted && hydratedAssignments.isNotEmpty) {
      setState(() {
        _eventKey = cachedEventKey;
        _assignments = hydratedAssignments;
        _teams = cachedTeams;
        _matches = cachedMatches;
        _recomputeCachedLists();
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Refresh
    try {
      final eventKey = await widget.apiService.fetchCurrentEventKey();
      final results = await Future.wait([
        widget.apiService.fetchMyAssignments(eventKey),
        widget.apiService.fetchTeams(eventKey),
        widget.apiService.fetchMatches(eventKey),
      ]);

      if (!mounted) return;

      final fetchedAssignments = results[0] as List<ScoutingAssignment>;
      final hydratedFetched = await ScoutHistoryService.applyLocalScoutStatus(
        fetchedAssignments,
        eventKey: eventKey,
      );

      setState(() {
        _eventKey = eventKey;
        _assignments = hydratedFetched;
        _teams = results[1] as List<TeamModel>;
        _matches = results[2] as List<MatchModel>;
        _recomputeCachedLists();
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadData();
  }

  // Filter & sort assignments for tabs
  List<ScoutingAssignment> get _activeAssignments => _cachedActive;
  List<ScoutingAssignment> get _completedAssignments => _cachedCompleted;
  List<ScoutingAssignment> get _allAssignments => _cachedAll;
  ScoutingAssignment? get _nextUpAssignment => _cachedNextUp;

  void _startScouting(ScoutingAssignment a) async {
    // Mark as in-progress on start
    if (a.status == 'PENDING') {
      widget.apiService.updateAssignmentStatus(a.id, 'IN_PROGRESS');
      setState(() {
        final idx = _assignments.indexWhere((item) => item.id == a.id);
        if (idx >= 0) {
          _assignments[idx] = a.copyWith(status: 'IN_PROGRESS');
        }
      });
    }

    if (a.assignmentType == 'MATCH') {
      if (widget.onNavigateMatch != null) {
        widget.onNavigateMatch!(a.matchKey, a.matchNumber, a.targetTeamNumber, a.id);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: ObsidianUITheme.getBackgroundColor(ctx),
            appBar: AppBar(
              title: Text(ctx.tr('nav.match_scout', 'Match Scouting')),
              backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: MatchScoutScreen(
              apiService: widget.apiService,
              initialMatchKey: a.matchKey,
              initialMatchNumber: a.matchNumber,
              initialTargetTeamNumber: a.targetTeamNumber,
              sourceAssignmentId: a.id,
            ),
          ),
        ),
      );
    } else if (a.assignmentType == 'PIT') {
      if (widget.onNavigatePit != null) {
        widget.onNavigatePit!(a.targetTeamNumber, a.id);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: ObsidianUITheme.getBackgroundColor(ctx),
            appBar: AppBar(
              title: Text(ctx.tr('nav.pit_scout', 'Pit Scouting')),
              backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: PitScoutScreen(
              apiService: widget.apiService,
              initialTargetTeamNumber: a.targetTeamNumber,
              sourceAssignmentId: a.id,
            ),
          ),
        ),
      );
    } else if (a.assignmentType == 'QUALITATIVE') {
      if (widget.onNavigateQual != null) {
        widget.onNavigateQual!(a.matchKey, a.matchNumber, a.allianceColor ?? a.targetAlliance, a.targetTeamNumber, a.id);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: ObsidianUITheme.getBackgroundColor(ctx),
            appBar: AppBar(
              title: Text(ctx.tr('nav.qual_scout', 'Qualitative Scouting')),
              backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: QualScoutScreen(
              apiService: widget.apiService,
              initialMatchKey: a.matchKey,
              initialMatchNumber: a.matchNumber,
              initialAllianceColor: a.allianceColor ?? a.targetAlliance,
              initialTargetTeamNumber: a.targetTeamNumber,
              sourceAssignmentId: a.id,
            ),
          ),
        ),
      );
    }

    // Refresh after return
    _loadData();
  }

  String _formatCountdown(int? scheduledTimeMs) {
    if (scheduledTimeMs == null || scheduledTimeMs <= 0) return 'Scheduled';
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = scheduledTimeMs - now;

    if (diff < -3600 * 1000 * 24) {
      return 'Past Match';
    } else if (diff < 0) {
      final minsAgo = (-diff / 60000).floor();
      if (minsAgo < 60) {
        return '${minsAgo}m ago';
      } else {
        return '${(minsAgo / 60).floor()}h ago';
      }
    } else if (diff < 60000) {
      return 'Starting Now';
    } else if (diff < 3600 * 1000) {
      final mins = (diff / 60000).floor();
      return 'in ${mins}m';
    } else if (diff < 3600 * 1000 * 24) {
      final hours = (diff / 3600000).floor();
      final mins = ((diff % 3600000) / 60000).floor();
      return 'in ${hours}h ${mins}m';
    } else {
      final days = (diff / (3600000 * 24)).floor();
      return 'in ${days}d';
    }
  }

  String _getAssignmentTargetTitle(ScoutingAssignment a) {
    if (a.assignmentType == 'MATCH') {
      final matchedObj = _matchesByKey[(a.matchKey ?? '').toLowerCase()];
      final matchLabel = matchedObj?.shortLabel ?? a.formattedMatchName;
      final teamLabel =
          a.targetTeamNumber != null ? 'Team ${a.targetTeamNumber}' : '';
      return '$matchLabel${teamLabel.isNotEmpty ? ' • $teamLabel' : ''}';
    } else if (a.assignmentType == 'PIT') {
      return 'Pit Scouting • Team ${a.targetTeamNumber ?? '—'}';
    } else if (a.assignmentType == 'QUALITATIVE') {
      final matchedObj = _matchesByKey[(a.matchKey ?? '').toLowerCase()];
      final matchLabel = matchedObj?.shortLabel ?? a.formattedMatchName;
      final targetText = a.targetTeamNumber != null
          ? 'Team #${a.targetTeamNumber}${a.allianceColor != null ? " (${a.allianceColor!.toUpperCase()})" : ""}'
          : ((a.allianceColor ?? a.targetAlliance)?.isNotEmpty == true
              ? '${(a.allianceColor ?? a.targetAlliance)!.toUpperCase()} Alliance'
              : 'Alliance');
      return 'Qualitative • $matchLabel ($targetText)';
    }
    return 'Scout Assignment';
  }

  String? _getTeamNickname(int? teamNumber) {
    if (teamNumber == null) return null;
    final team = _teamsByNumber[teamNumber];
    return team?.nickname ?? team?.name;
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'MATCH':
        return const Color(0xFF3B82F6); // Blue
      case 'PIT':
        return const Color(0xFF8B5CF6); // Purple
      case 'QUALITATIVE':
        return const Color(0xFFEC4899); // Pink
      default:
        return const Color(0xFF06B6D4); // Cyan
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'MATCH':
        return Icons.sports_esports_rounded;
      case 'PIT':
        return Icons.build_circle_rounded;
      case 'QUALITATIVE':
        return Icons.rate_review_rounded;
      default:
        return Icons.assignment_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return const Color(0xFF10B981); // Green
      case 'IN_PROGRESS':
        return const Color(0xFF3B82F6); // Blue
      case 'SKIPPED':
      case 'MISSED':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFFF59E0B); // Amber
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = widget.isBarsVisible ? 100.0 : 20.0;
    final bottomPadding = widget.isBarsVisible ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
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
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (_nextUpAssignment != null) ...[
                    _buildHeroUpNextCard(_nextUpAssignment!),
                    const SizedBox(height: 20),
                  ],
                  _buildTabBar(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          ..._buildTabSlivers(),
          SliverToBoxAdapter(
            child: SizedBox(height: bottomPadding),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('my_assignments.title', 'My Assignments'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: ObsidianUITheme.getPrimaryTextColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _eventKey != null && _eventKey!.isNotEmpty
                    ? 'Event: ${_eventKey!.toUpperCase()}'
                    : 'Personal scouting queue',
                style: TextStyle(
                  fontSize: 13,
                  color: ObsidianUITheme.getSecondaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: _isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                  ),
                )
              : const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh Assignments',
          onPressed: _handleRefresh,
        ),
      ],
    );
  }

  Widget _buildHeroUpNextCard(ScoutingAssignment a) {
    final typeColor = _getTypeColor(a.assignmentType);
    final targetTitle = _getAssignmentTargetTitle(a);
    final nickname = _getTeamNickname(a.targetTeamNumber);
    final countdownStr = _formatCountdown(a.effectiveScheduledTime);
    final isImminent = a.effectiveScheduledTime != null &&
        (a.effectiveScheduledTime! - DateTime.now().millisecondsSinceEpoch < 600000);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            typeColor.withValues(alpha: 0.25),
            ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: typeColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: typeColor.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: typeColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getTypeIcon(a.assignmentType), size: 14, color: typeColor),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('my_assignments.up_next', 'UP NEXT'),
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isImminent
                      ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isImminent
                        ? const Color(0xFFEF4444)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      countdownStr,
                      style: TextStyle(
                        color: isImminent ? const Color(0xFFEF4444) : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildOffsetBadge(a.scheduleOffsetSeconds),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            targetTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: ObsidianUITheme.getPrimaryTextColor(context),
            ),
          ),
          if (nickname != null && nickname.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              nickname,
              style: TextStyle(
                fontSize: 13,
                color: ObsidianUITheme.getSecondaryTextColor(context),
              ),
            ),
          ],
          if (a.notes != null && a.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Note: ${a.notes!}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: typeColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                context.tr('my_assignments.start_now', 'Start Scouting Now'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () => _startScouting(a),
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
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: [
          Tab(
            text: '${context.tr('my_assignments.tab_active', 'Active')} (${_activeAssignments.length})',
          ),
          Tab(
            text: '${context.tr('my_assignments.tab_completed', 'Completed')} (${_completedAssignments.length})',
          ),
          Tab(
            text: '${context.tr('my_assignments.tab_all', 'All')} (${_allAssignments.length})',
          ),
        ],
        onTap: (_) => setState(() {}),
      ),
    );
  }

  List<Widget> _buildTabSlivers() {
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

    final currentTabIndex = _tabController.index;
    final List<ScoutingAssignment> displayList;
    final String emptyMessage;

    if (currentTabIndex == 0) {
      displayList = _activeAssignments;
      emptyMessage = context.tr('my_assignments.empty_active', 'No active assignments pending for you.');
    } else if (currentTabIndex == 1) {
      displayList = _completedAssignments;
      emptyMessage = context.tr('my_assignments.empty_completed', 'No completed assignments yet.');
    } else {
      displayList = _allAssignments;
      emptyMessage = context.tr('my_assignments.empty_all', 'No assignments assigned to you for this event.');
    }

    if (displayList.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SliverToBoxAdapter(
            child: ObsidianGlassCard(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_turned_in_rounded,
                      size: 48,
                      color: ObsidianUITheme.getTertiaryTextColor(context),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: ObsidianUITheme.getSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.crossAxisExtent > 900
                ? 3
                : (constraints.crossAxisExtent > 600 ? 2 : 1);

            if (crossAxisCount == 1) {
              return SliverList.builder(
                itemCount: displayList.length,
                itemBuilder: (context, index) => _buildAssignmentCard(displayList[index]),
              );
            }

            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: displayList.length,
              itemBuilder: (context, index) => _buildAssignmentCard(displayList[index]),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildAssignmentCard(ScoutingAssignment a) {
    final typeColor = _getTypeColor(a.assignmentType);
    final statusColor = _getStatusColor(a.status);
    final targetTitle = _getAssignmentTargetTitle(a);
    final nickname = _getTeamNickname(a.targetTeamNumber);
    final countdownStr = _formatCountdown(a.effectiveScheduledTime);
    final isDone = a.status == 'COMPLETED';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ObsidianUITheme.getBorderColor(context),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left color accent bar
              Container(
                width: 6,
                color: typeColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getTypeIcon(a.assignmentType),
                                    size: 12, color: typeColor),
                                const SizedBox(width: 4),
                                Text(
                                  a.assignmentType,
                                  style: TextStyle(
                                    color: typeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              a.status.replaceAll('_', ' '),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                countdownStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ObsidianUITheme.getSecondaryTextColor(context),
                                ),
                              ),
                              _buildOffsetBadge(a.scheduleOffsetSeconds),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        targetTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: ObsidianUITheme.getPrimaryTextColor(context),
                        ),
                      ),
                      if (nickname != null && nickname.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          nickname,
                          style: TextStyle(
                            fontSize: 12,
                            color: ObsidianUITheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                      if (a.notes != null && a.notes!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Note: ${a.notes!}',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: ObsidianUITheme.getTertiaryTextColor(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDone ? Colors.grey : typeColor,
                            side: BorderSide(
                              color: isDone
                                  ? Colors.grey.withValues(alpha: 0.4)
                                  : typeColor.withValues(alpha: 0.6),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                          ),
                          icon: Icon(
                            isDone ? Icons.edit_rounded : Icons.play_arrow_rounded,
                            size: 16,
                          ),
                          label: Text(
                            isDone
                                ? context.tr('my_assignments.edit_entry', 'Edit Entry')
                                : context.tr('my_assignments.scout_match', 'Start Scouting'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _startScouting(a),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetBadge(int? offsetSeconds) {
    if (offsetSeconds == null || offsetSeconds == 0) return const SizedBox.shrink();
    final offsetMins = (offsetSeconds / 60).round();
    if (offsetMins.abs() < 1) return const SizedBox.shrink();
    final isLate = offsetMins > 0;
    final color = isLate ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4);
    final sign = isLate ? '+' : '';
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        '$sign${offsetMins}m',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
