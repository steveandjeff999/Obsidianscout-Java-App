import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_tokens.dart';
import '../theme/obsidian_ui_theme.dart';
import 'team_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ApiService? apiService;
  final VoidCallback onNavigateMatch;
  final VoidCallback onNavigatePit;
  final VoidCallback onNavigateAnalytics;
  final VoidCallback onNavigateQrScanner;
  final VoidCallback? onNavigateAlliance;
  final VoidCallback? onNavigatePrescout;
  final VoidCallback? onNavigateHistory;
  final ValueChanged<int>? onNavigateScreen;
  final bool isVisible;
  final bool isBarsVisible;

  const DashboardScreen({
    super.key,
    this.apiService,
    required this.onNavigateMatch,
    required this.onNavigatePit,
    required this.onNavigateAnalytics,
    required this.onNavigateQrScanner,
    this.onNavigateAlliance,
    this.onNavigatePrescout,
    this.onNavigateHistory,
    this.onNavigateScreen,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _teamLookupCtrl = TextEditingController();

  int _entriesCount = 0;
  int _pitCount = 0;
  int _qualCount = 0;
  int _teamsCount = 0;
  int _matchesCount = 0;
  int _eventsCount = 0;
  List<TeamModel> _teams = const [];
  List<MatchModel> _upcomingMatches = const [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadDashboardData();
    }
  }

  @override
  void dispose() {
    _teamLookupCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    final api = widget.apiService;
    if (api == null) return;
    final eventKey = api.currentSettings?.eventKey;
    try {
      final results = await Future.wait([
        api.getCachedScoutingEntries(),
        api.getCachedPitScoutingEntries(),
        api.getCachedQualScoutingEntries(),
        api.getCachedTeams(eventKey),
        api.getCachedMatches(eventKey),
        api.getCachedEvents(),
      ]);
      if (!mounted) return;
      final entries = results[0];
      final pit = results[1];
      final qual = results[2];
      final teams = results[3] as List<TeamModel>;
      final matches = results[4] as List<MatchModel>;
      final events = results[5];

      final unplayed = matches
          .where((m) => !m.assumedPlayed && m.redScore == null && m.blueScore == null)
          .toList();
      final preview = (unplayed.isNotEmpty ? unplayed : matches).take(5).toList();

      setState(() {
        _entriesCount = entries.length;
        _pitCount = pit.length;
        _qualCount = qual.length;
        _teams = teams;
        _teamsCount = teams.length;
        _matchesCount = matches.length;
        _eventsCount = events.length;
        _upcomingMatches = preview;
      });
    } catch (_) {}
  }

  Future<void> _handleSync() async {
    final api = widget.apiService;
    if (api == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      await api.recacheAll();
      await _loadDashboardData();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _navigateToIndex(int index, {VoidCallback? fallback}) {
    if (widget.onNavigateScreen != null) {
      widget.onNavigateScreen!(index);
    } else {
      fallback?.call();
    }
  }

  void _lookupTeam() {
    final raw = _teamLookupCtrl.text.trim();
    final numVal = int.tryParse(raw);
    if (numVal == null || numVal <= 0) return;
    final api = widget.apiService;
    if (api == null) return;

    final eventKey = api.currentSettings?.eventKey ?? '';
    final match = _teams.where((t) => t.teamNumber == numVal).firstOrNull ??
        TeamModel(
          eventKey: eventKey,
          teamKey: 'frc$numVal',
          teamNumber: numVal,
          nickname: 'Team $numVal',
        );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailsScreen(
          team: match,
          apiService: api,
          eventKey: api.currentSettings?.eventKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService?.uiMode);
    if (isDesktop) {
      return _buildDesktopDashboard(context);
    }
    return _buildMobileDashboard(context);
  }

  // ── Mobile Dashboard ──────────────────────────────────────────────────────
  Widget _buildMobileDashboard(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final api = widget.apiService;
    final user = api?.currentUser;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (api?.savedUsername.isNotEmpty == true ? api!.savedUsername : 'Scout');
    final program = api?.currentProgram ?? 'FRC';
    final roleLabel = user?.roleDisplayLabel ?? (api?.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');
    final eventKey = api?.currentSettings?.eventKey ?? '';
    final isConnected = api?.isLoggedIn ?? true;

    final kpis = _buildKpiItems(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 12, 16, widget.isBarsVisible ? 120 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(
            username: username,
            teamNumber: user?.teamNumber ?? 0,
            program: program,
            roleLabel: roleLabel,
            eventKey: eventKey,
            isConnected: isConnected,
            compact: true,
            actions: [
              if (api?.hasPageAccess('scout') ?? true)
                ElevatedButton.icon(
                  onPressed: widget.onNavigateMatch,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(context.tr('nav.match_scout')),
                ),
              if (api?.hasPageAccess('pit-scout') ?? true)
                OutlinedButton.icon(
                  onPressed: widget.onNavigatePit,
                  icon: const Icon(Icons.build_outlined, size: 16),
                  label: Text(context.tr('nav.pit_scout')),
                ),
              if (api?.hasPageAccess('qr-scanner') ?? true)
                OutlinedButton.icon(
                  onPressed: widget.onNavigateQrScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                  label: Text(context.tr('scanner.title')),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.view_in_ar_rounded, size: 18, color: t.ink),
              const SizedBox(width: 8),
              Text(
                'Scouting Overview',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final itemW = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: kpis
                    .map((item) => SizedBox(width: itemW, child: _KpiCard(item: item)))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          _buildTeamLookupCard(context),
          const SizedBox(height: 16),
          _buildLaunchpadCard(context),
        ],
      ),
    );
  }

  // ── Desktop Dashboard (mirrors dashboard.html + dashboard.css) ────────────
  Widget _buildDesktopDashboard(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final api = widget.apiService;
    final user = api?.currentUser;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (api?.savedUsername.isNotEmpty == true ? api!.savedUsername : 'Scout');
    final program = api?.currentProgram ?? 'FRC';
    final roleLabel = user?.roleDisplayLabel ?? (api?.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');
    final eventKey = api?.currentSettings?.eventKey ?? '';
    final isConnected = api?.isLoggedIn ?? true;

    final canScout = api?.hasPageAccess('scout') ?? true;
    final canPit = api?.hasPageAccess('pit-scout') ?? true;
    final canQr = api?.hasPageAccess('qr-scanner') ?? true;
    final canPredictor = api?.hasPageAccess('predictor') ?? true;
    final kpis = _buildKpiItems(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Hero Command Header
          _HeroCard(
            username: username,
            teamNumber: user?.teamNumber ?? 0,
            program: program,
            roleLabel: roleLabel,
            eventKey: eventKey,
            isConnected: isConnected,
            actions: [
              if (canScout)
                ElevatedButton.icon(
                  onPressed: widget.onNavigateMatch,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Scout Match'),
                ),
              if (canPit)
                OutlinedButton.icon(
                  onPressed: widget.onNavigatePit,
                  icon: const Icon(Icons.build_outlined, size: 17),
                  label: const Text('Pit Scout'),
                ),
              if (canQr)
                OutlinedButton.icon(
                  onPressed: widget.onNavigateQrScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                  label: const Text('QR Scanner'),
                ),
              if (canPredictor)
                OutlinedButton.icon(
                  onPressed: () => _navigateToIndex(20),
                  icon: const Icon(Icons.star_outline_rounded, size: 17),
                  label: const Text('Predictor'),
                ),
            ],
          ),

          const SizedBox(height: 22),

          // 2. Scouting Overview Header
          Row(
            children: [
              Icon(Icons.view_in_ar_rounded, size: 18, color: t.ink),
              const SizedBox(width: 8),
              Text(
                'Scouting Overview',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: t.ink),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 3. 6 KPI Metric Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 1060 ? 6 : (w >= 640 ? 3 : 2);
              const gap = 16.0;
              final itemW = (w - (cols - 1) * gap) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: kpis
                    .map((item) => SizedBox(width: itemW, child: _KpiCard(item: item)))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // 4. Two-Column Operational Hub (1.35fr / 1fr)
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 880;
              final left = Column(
                children: [
                  _buildEventContextCard(context),
                  const SizedBox(height: 20),
                  _buildUpcomingMatchesCard(context),
                ],
              );
              final right = Column(
                children: [
                  _buildTeamLookupCard(context),
                  const SizedBox(height: 20),
                  _buildQuickSyncCard(context, isConnected),
                  const SizedBox(height: 20),
                  _buildLaunchpadCard(context),
                ],
              );

              if (!twoCol) {
                return Column(children: [left, const SizedBox(height: 20), right]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 135, child: left),
                  const SizedBox(width: 20),
                  Expanded(flex: 100, child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<_KpiItem> _buildKpiItems(BuildContext context) {
    return [
      _KpiItem(
        title: 'Match Entries',
        value: '$_entriesCount',
        subtext: 'Scouted match forms',
        icon: Icons.description_outlined,
        onTap: () => _navigateToIndex(12),
      ),
      _KpiItem(
        title: 'Pit Forms',
        value: '$_pitCount',
        subtext: 'Robots inspected',
        icon: Icons.build_outlined,
        onTap: () => _navigateToIndex(14),
      ),
      _KpiItem(
        title: 'Qualitative',
        value: '$_qualCount',
        subtext: 'Subjective scout logs',
        icon: Icons.chat_bubble_outline_rounded,
        onTap: () => _navigateToIndex(15),
      ),
      _KpiItem(
        title: 'Teams',
        value: '$_teamsCount',
        subtext: 'Attending teams',
        icon: Icons.groups_outlined,
        onTap: () => _navigateToIndex(8),
      ),
      _KpiItem(
        title: 'Matches',
        value: '$_matchesCount',
        subtext: 'Event match schedule',
        icon: Icons.calendar_today_outlined,
        onTap: () => _navigateToIndex(9),
      ),
      _KpiItem(
        title: 'Events',
        value: '$_eventsCount',
        subtext: 'Synced competitions',
        icon: Icons.location_on_outlined,
        onTap: () => _navigateToIndex(25),
      ),
    ];
  }

  Widget _buildEventContextCard(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final s = widget.apiService?.currentSettings;
    final source = s == null
        ? '-'
        : (s.useStatboticsEpa
            ? 'Statbotics'
            : (s.useTbaOpr ? 'TBA' : (s.useMatch13xP ? 'Match13' : 'Server')));

    return _SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.emoji_events_outlined,
            title: 'Active Competition',
            trailing: _PillLink(
              label: 'Manage Events →',
              onTap: () => _navigateToIndex(25),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Season and event settings are used for API sync and match times.',
            style: TextStyle(fontSize: 14, color: t.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
              border: Border.all(color: t.borderSubtle),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth > 420 ? 4 : 2;
                final w = (c.maxWidth - (cols - 1) * 14) / cols;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(width: w, child: _DetailItem(label: 'Season', value: s != null && s.year > 0 ? '${s.year}' : '-')),
                    SizedBox(width: w, child: _DetailItem(label: 'Event Key', value: s?.eventKey.isNotEmpty == true ? s!.eventKey.toUpperCase() : '-', mono: true)),
                    SizedBox(width: w, child: _DetailItem(label: 'Timezone', value: s?.timezone.isNotEmpty == true ? s!.timezone : '-')),
                    SizedBox(width: w, child: _DetailItem(label: 'Data Source', value: source)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingMatchesCard(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return _SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.schedule_rounded,
            title: 'Upcoming Matches',
            trailing: _PillLink(
              label: 'View all →',
              onTap: () => _navigateToIndex(9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Next scheduled matches for the active event.',
            style: TextStyle(fontSize: 14, color: t.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_upcomingMatches.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
                border: Border.all(color: t.border),
              ),
              child: Text(
                'No upcoming matches cached for this event.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
            )
          else
            Column(
              children: _upcomingMatches
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UpcomingMatchRow(
                          match: m,
                          onScout: widget.onNavigateMatch,
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamLookupCard(BuildContext context) {
    return _SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.search_rounded,
            title: 'Quick Team Lookup',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _teamLookupCtrl,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _lookupTeam(),
                  decoration: const InputDecoration(
                    hintText: 'Enter team # (e.g. 254)',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _lookupTeam,
                child: const Text('Lookup'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSyncCard(BuildContext context, bool isConnected) {
    final t = ObsidianTokens.of(context);
    final dotColor = _syncing ? t.warning : (isConnected ? t.success : t.danger);
    final statusTitle = _syncing
        ? 'Syncing data...'
        : (isConnected ? 'Connected & ready' : 'Offline mode');
    final statusSub = _syncing
        ? 'Fetching teams, matches and entries'
        : 'Cached locally for offline scouting';

    return _SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.sync_rounded,
            title: 'Quick sync',
          ),
          const SizedBox(height: 8),
          Text(
            'Teams, matches and scouting entries sync with the server.',
            style: TextStyle(fontSize: 14, color: t.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusTitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.ink)),
                      const SizedBox(height: 2),
                      Text(statusSub, style: TextStyle(fontSize: 12, color: t.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _syncing ? null : _handleSync,
                child: Text(_syncing ? 'Syncing...' : 'Sync data'),
              ),
              OutlinedButton(
                onPressed: _loadDashboardData,
                child: const Text('Refresh counts'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchpadCard(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final tiles = [
      _LaunchTile('Rankings', 'Team Stats', Icons.show_chart_rounded, () => _navigateToIndex(26)),
      _LaunchTile('Graphs', 'Visual Trends', Icons.bar_chart_rounded, widget.onNavigateAnalytics),
      _LaunchTile('Draft Board', 'Pick List', Icons.groups_outlined, () => _navigateToIndex(7, fallback: widget.onNavigateAlliance)),
      _LaunchTile('Validation', 'Data Health', Icons.check_circle_outline_rounded, () => _navigateToIndex(16)),
      _LaunchTile('Data Sharing', 'Export / Import', Icons.download_rounded, () => _navigateToIndex(49)),
      _LaunchTile('Settings', 'Preferences', Icons.tune_rounded, () => _navigateToIndex(5)),
    ];

    return _SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.grid_view_rounded,
            title: 'Operations Launchpad',
          ),
          const SizedBox(height: 8),
          Text(
            'Quick access to core scouting, strategy, and management tools.',
            style: TextStyle(fontSize: 14, color: t.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 420 ? 3 : 2;
              const gap = 10.0;
              final w = (c.maxWidth - (cols - 1) * gap) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: tiles.map((tile) => SizedBox(width: w, child: _LaunchTileWidget(tile: tile))).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Building Blocks (1:1 with dashboard.css & design.css) ────────────────────

class _SiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SiteCard({required this.child, this.padding = const EdgeInsets.all(24)});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(ObsidianUITheme.getCardBorderRadius(context)),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: t.ink),
        child: child,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String username;
  final int teamNumber;
  final String program;
  final String roleLabel;
  final String eventKey;
  final bool isConnected;
  final List<Widget> actions;
  final bool compact;

  const _HeroCard({
    required this.username,
    required this.teamNumber,
    required this.program,
    required this.roleLabel,
    required this.eventKey,
    required this.isConnected,
    required this.actions,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);

    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, $username!',
          style: ObsidianTokens.serif(
            base: TextStyle(color: t.ink, height: 1.15),
            size: compact ? 26 : 32,
            weight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (teamNumber > 0) _HeroBadge(label: 'Team $teamNumber', fg: t.ink),
            _HeroBadge(
              label: program,
              fg: accent,
              bg: accent.withValues(alpha: 0.12),
              border: accent.withValues(alpha: 0.25),
            ),
            _HeroBadge(label: roleLabel, fg: t.ink),
            _HeroBadge(
              label: eventKey.isNotEmpty ? 'Event: ${eventKey.toUpperCase()}' : 'Event: None',
              fg: t.muted,
            ),
            _HeroBadge(
              label: isConnected ? 'Online' : 'Offline',
              fg: isConnected ? t.success : t.danger,
              bg: (isConnected ? t.success : t.danger).withValues(alpha: 0.12),
              border: (isConnected ? t.success : t.danger).withValues(alpha: 0.25),
            ),
          ],
        ),
      ],
    );

    return _SiteCard(
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28, vertical: compact ? 18 : 26),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                greeting,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: greeting),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 20),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: actions,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final Color fg;
  final Color? bg;
  final Color? border;
  const _HeroBadge({required this.label, required this.fg, this.bg, this.border});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? t.surface2,
        borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
        border: Border.all(color: border ?? t.border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _KpiItem {
  final String title;
  final String value;
  final String subtext;
  final IconData icon;
  final VoidCallback onTap;
  const _KpiItem({
    required this.title,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.onTap,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiItem item;
  const _KpiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);
    final radius = ObsidianUITheme.getCardBorderRadius(context);

    return Material(
      color: ObsidianUITheme.getSurfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: t.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(ObsidianTokens.radius),
                      border: Border.all(color: t.border),
                    ),
                    child: Icon(item.icon, size: 15, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.value,
                style: ObsidianTokens.mono(
                  base: TextStyle(color: t.ink, height: 1.1),
                  size: 30,
                  weight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.subtext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ),
                  Text('→', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(icon, size: 19, color: t.ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ObsidianTokens.serif(
                    base: TextStyle(color: t.ink),
                    size: 21,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _PillLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted)),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailItem({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.muted)),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono
              ? ObsidianTokens.mono(base: TextStyle(color: t.ink), size: 14, weight: FontWeight.w600)
              : TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
        ),
      ],
    );
  }
}

class _UpcomingMatchRow extends StatelessWidget {
  final MatchModel match;
  final VoidCallback onScout;
  const _UpcomingMatchRow({required this.match, required this.onScout});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);
    String cleanTeam(String raw) => raw.replaceFirst(RegExp(r'^frc', caseSensitive: false), '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              match.label.isNotEmpty ? match.label : 'Match ${match.matchNumber ?? ''}',
              style: ObsidianTokens.mono(base: TextStyle(color: t.ink), size: 13, weight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _AllianceChips(
                  teams: match.redTeams.map(cleanTeam).toList(),
                  color: t.danger,
                  bg: t.danger.withValues(alpha: 0.10),
                  border: t.danger.withValues(alpha: 0.22),
                ),
                _AllianceChips(
                  teams: match.blueTeams.map(cleanTeam).toList(),
                  color: accent,
                  bg: accent.withValues(alpha: 0.10),
                  border: accent.withValues(alpha: 0.22),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onScout,
            borderRadius: BorderRadius.circular(ObsidianTokens.radius),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(ObsidianTokens.radius),
                border: Border.all(color: t.border),
              ),
              child: Text('Scout', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.ink)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllianceChips extends StatelessWidget {
  final List<String> teams;
  final Color color;
  final Color bg;
  final Color border;
  const _AllianceChips({required this.teams, required this.color, required this.bg, required this.border});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        border: Border.all(color: border),
      ),
      child: Wrap(
        spacing: 5,
        children: teams
            .map((tm) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(ObsidianTokens.radiusSm),
                  ),
                  child: Text(
                    tm,
                    style: ObsidianTokens.mono(base: TextStyle(color: color), size: 12, weight: FontWeight.w600),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _LaunchTile {
  final String title;
  final String desc;
  final IconData icon;
  final VoidCallback onTap;
  const _LaunchTile(this.title, this.desc, this.icon, this.onTap);
}

class _LaunchTileWidget extends StatelessWidget {
  final _LaunchTile tile;
  const _LaunchTileWidget({required this.tile});

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);
    final isDark = ObsidianUITheme.isDark(context);

    return Material(
      color: t.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        side: BorderSide(color: t.borderSubtle),
      ),
      child: InkWell(
        onTap: tile.onTap,
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? t.surface3 : t.surface,
                  borderRadius: BorderRadius.circular(ObsidianTokens.radius),
                ),
                child: Icon(tile.icon, size: 18, color: accent),
              ),
              const SizedBox(height: 8),
              Text(
                tile.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.ink),
              ),
              const SizedBox(height: 2),
              Text(
                tile.desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
