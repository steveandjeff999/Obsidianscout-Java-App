import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_glass_card.dart';
import 'team_details_screen.dart';

class RankingsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const RankingsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  List<TeamModel> _teams = [];
  List<EventModel> _events = [];
  String _selectedEventKey = '';
  String _selectedMetric = 'scouted'; // 'scouted', 'epa', 'opr', 'all'
  String _activeSortMetric = 'scouted'; // 'scouted', 'epa', 'opr'
  bool _sortAsc = false;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(covariant RankingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadTeams();
    }
  }

  bool get _isFtc => widget.apiService.currentProgram.toUpperCase() == 'FTC';
  bool get _effectiveUseEpa => !_isFtc && (widget.apiService.currentSettings?.useStatboticsEpa ?? false);
  bool get _effectiveUseOpr => widget.apiService.currentSettings?.useTbaOpr ?? false;

  Future<void> _initData() async {
    final settings = widget.apiService.currentSettings;
    final cachedEventKey = settings?.eventKey ?? await widget.apiService.getCachedEventKey() ?? '';
    _selectedEventKey = cachedEventKey;

    // Normalize selected metric if options are disabled
    if (!_effectiveUseEpa && _selectedMetric == 'epa') {
      _selectedMetric = 'scouted';
      _activeSortMetric = 'scouted';
    }
    if (!_effectiveUseOpr && _selectedMetric == 'opr') {
      _selectedMetric = 'scouted';
      _activeSortMetric = 'scouted';
    }
    if ((!_effectiveUseEpa || !_effectiveUseOpr) && _selectedMetric == 'all') {
      _selectedMetric = 'scouted';
      _activeSortMetric = 'scouted';
    }

    // Hydrate events
    final cachedEvents = await widget.apiService.getCachedEvents();
    if (mounted && cachedEvents.isNotEmpty) {
      setState(() => _events = cachedEvents);
    }

    // Hydrate teams
    final cachedTeams = await widget.apiService.getCachedTeams(_selectedEventKey);
    if (mounted && cachedTeams.isNotEmpty) {
      setState(() {
        _teams = cachedTeams;
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // Fetch live events & teams
    try {
      final fetchedEvents = await widget.apiService.fetchEvents();
      if (mounted && fetchedEvents.isNotEmpty) {
        setState(() => _events = fetchedEvents);
      }
    } catch (_) {}

    await _loadTeams();
  }

  Future<void> _loadTeams() async {
    if (_selectedEventKey.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final cachedTeams = await widget.apiService.getCachedTeams(_selectedEventKey);
    if (mounted && cachedTeams.isNotEmpty) {
      setState(() {
        _teams = cachedTeams;
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    try {
      final teams = await widget.apiService.fetchTeams(_selectedEventKey);
      if (mounted) {
        setState(() {
          if (teams.isNotEmpty) {
            _teams = teams;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSort(String metric) {
    setState(() {
      if (_activeSortMetric == metric) {
        _sortAsc = !_sortAsc;
      } else {
        _activeSortMetric = metric;
        _sortAsc = false;
      }
      if (_selectedMetric != 'all') {
        _selectedMetric = metric;
      }
    });
  }

  List<TeamModel> get _sortedAndFilteredTeams {
    final q = _searchQuery.toLowerCase().trim();
    List<TeamModel> list = _teams.where((t) {
      if (q.isEmpty) return true;
      return t.teamNumber.toString().contains(q) ||
          (t.nickname ?? '').toLowerCase().contains(q) ||
          (t.name ?? '').toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) {
      double valA = -999999;
      double valB = -999999;

      if (_activeSortMetric == 'scouted') {
        valA = a.averagePoints ?? -999999;
        valB = b.averagePoints ?? -999999;
      } else if (_activeSortMetric == 'epa') {
        valA = a.epa ?? -999999;
        valB = b.epa ?? -999999;
      } else if (_activeSortMetric == 'opr') {
        valA = a.opr ?? -999999;
        valB = b.opr ?? -999999;
      }

      final hasA = valA != -999999;
      final hasB = valB != -999999;
      if (hasA && !hasB) return -1;
      if (!hasA && hasB) return 1;
      if (!hasA && !hasB) return a.teamNumber.compareTo(b.teamNumber);

      final comp = _sortAsc ? valA.compareTo(valB) : valB.compareTo(valA);
      if (comp != 0) return comp;
      return a.teamNumber.compareTo(b.teamNumber);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final sortedTeams = _sortedAndFilteredTeams;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadTeams,
        color: ObsidianUITheme.primaryAccent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, isDesktop ? 16 : 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filter & Metric Selector Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.leaderboard_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('rankings.title', 'Team Rankings'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr('rankings.notice', 'Rank teams based on selected metrics.'),
                                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Metric selector
                              SizedBox(
                                width: 230,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('rankings.metric', 'Ranking Metric'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.getSurfaceColor(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedMetric,
                                          isExpanded: true,
                                          items: [
                                            DropdownMenuItem(
                                              value: 'scouted',
                                              child: Text(context.tr('rankings.metric.scouted', 'Scouted Average Points')),
                                            ),
                                            if (_effectiveUseEpa)
                                              DropdownMenuItem(
                                                value: 'epa',
                                                child: Text(context.tr('rankings.metric.epa', 'Statbotics EPA')),
                                              ),
                                            if (_effectiveUseOpr)
                                              DropdownMenuItem(
                                                value: 'opr',
                                                child: Text(_isFtc
                                                    ? context.tr('predictor.ftcscout_opr', 'FTC Scout OPR')
                                                    : context.tr('rankings.metric.opr', 'TBA OPR')),
                                              ),
                                            if (_effectiveUseEpa && _effectiveUseOpr)
                                              DropdownMenuItem(
                                                value: 'all',
                                                child: Text(context.tr('rankings.metric.all', 'All Three')),
                                              ),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _selectedMetric = val;
                                                if (val != 'all') {
                                                  _activeSortMetric = val;
                                                  _sortAsc = false;
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Event filter dropdown
                              SizedBox(
                                width: 260,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('matches.view_event', 'View Event'),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.getSurfaceColor(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _events.any((e) => e.eventKey == _selectedEventKey)
                                              ? _selectedEventKey
                                              : (_events.isNotEmpty ? _events.first.eventKey : ''),
                                          isExpanded: true,
                                          items: _events.map((e) {
                                            return DropdownMenuItem(
                                              value: e.eventKey,
                                              child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null && val != _selectedEventKey) {
                                              setState(() {
                                                _selectedEventKey = val;
                                                _isLoading = true;
                                              });
                                              _loadTeams();
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Search input
                              SizedBox(
                                width: 220,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Search',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Team # or name...',
                                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                        filled: true,
                                        fillColor: ObsidianUITheme.getSurfaceColor(context),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: borderColor),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      onChanged: (val) => setState(() => _searchQuery = val),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Rankings Table / Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Rankings (${sortedTeams.length} teams)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              if (_isLoading)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLoading && _teams.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                              ),
                            )
                          else if (sortedTeams.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No teams found for this event',
                                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                                ),
                              ),
                            )
                          else if (isDesktop)
                            _buildDesktopTable(sortedTeams)
                          else
                            _buildMobileList(sortedTeams),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTable(List<TeamModel> teams) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    final showScouted = _selectedMetric == 'scouted' || _selectedMetric == 'all';
    final showOpr = (_selectedMetric == 'opr' || _selectedMetric == 'all') && _effectiveUseOpr;
    final showEpa = (_selectedMetric == 'epa' || _selectedMetric == 'all') && _effectiveUseEpa;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 800),
        child: DataTable(
          headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 13),
          dataTextStyle: TextStyle(color: primaryTextColor, fontSize: 13),
          dividerThickness: 0.5,
          horizontalMargin: 12,
          columnSpacing: 28,
          columns: [
            DataColumn(label: Text(context.tr('rankings.rank', 'Rank'))),
            DataColumn(label: Text(context.tr('rankings.team', 'Team'))),
            DataColumn(label: Text(context.tr('rankings.name', 'Name'))),
            if (showScouted)
              DataColumn(
                label: InkWell(
                  onTap: () => _onSort('scouted'),
                  child: Row(
                    children: [
                      Text(
                        'Scouted Average',
                        style: TextStyle(
                          color: _activeSortMetric == 'scouted' ? ObsidianUITheme.primaryAccent : primaryTextColor,
                          fontWeight: _activeSortMetric == 'scouted' ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      if (_activeSortMetric == 'scouted')
                        Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14, color: ObsidianUITheme.primaryAccent),
                    ],
                  ),
                ),
              ),
            if (showOpr)
              DataColumn(
                label: InkWell(
                  onTap: () => _onSort('opr'),
                  child: Row(
                    children: [
                      Text(
                        _isFtc ? 'FTC OPR' : 'OPR',
                        style: TextStyle(
                          color: _activeSortMetric == 'opr' ? ObsidianUITheme.primaryAccent : primaryTextColor,
                          fontWeight: _activeSortMetric == 'opr' ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      if (_activeSortMetric == 'opr')
                        Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14, color: ObsidianUITheme.primaryAccent),
                    ],
                  ),
                ),
              ),
            if (showEpa)
              DataColumn(
                label: InkWell(
                  onTap: () => _onSort('epa'),
                  child: Row(
                    children: [
                      Text(
                        'EPA',
                        style: TextStyle(
                          color: _activeSortMetric == 'epa' ? ObsidianUITheme.primaryAccent : primaryTextColor,
                          fontWeight: _activeSortMetric == 'epa' ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      if (_activeSortMetric == 'epa')
                        Icon(_sortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14, color: ObsidianUITheme.primaryAccent),
                    ],
                  ),
                ),
              ),
          ],
          rows: teams.asMap().entries.map((entry) {
            final index = entry.key;
            final t = entry.value;

            return DataRow(
              cells: [
                DataCell(_buildRankBadge(index + 1)),
                DataCell(
                  InkWell(
                    onTap: () => _openTeamDetails(t),
                    child: Text(
                      t.teamNumber.toString(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                    ),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => _openTeamDetails(t),
                    child: Text(t.nickname ?? t.name ?? '—', overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (showScouted)
                  DataCell(
                    Text(
                      t.averagePoints != null ? t.averagePoints!.toStringAsFixed(1) : '—',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (showOpr)
                  DataCell(
                    Text(
                      t.opr != null ? t.opr!.toStringAsFixed(2) : '—',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                  ),
                if (showEpa)
                  DataCell(
                    Text(
                      t.epa != null ? t.epa!.toStringAsFixed(2) : '—',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(List<TeamModel> teams) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    final showScouted = _selectedMetric == 'scouted' || _selectedMetric == 'all';
    final showOpr = (_selectedMetric == 'opr' || _selectedMetric == 'all') && _effectiveUseOpr;
    final showEpa = (_selectedMetric == 'epa' || _selectedMetric == 'all') && _effectiveUseEpa;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teams.length,
      separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
      itemBuilder: (ctx, index) {
        final t = teams[index];

        return InkWell(
          onTap: () => _openTeamDetails(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildRankBadge(index + 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team ${t.teamNumber}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                      ),
                      if (t.nickname != null || t.name != null)
                        Text(
                          t.nickname ?? t.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showScouted && t.averagePoints != null)
                      Text(
                        '${t.averagePoints!.toStringAsFixed(1)} pts',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ObsidianUITheme.primaryAccent),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showOpr && t.opr != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('OPR: ${t.opr!.toStringAsFixed(1)}', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                          ),
                        if (showEpa && t.epa != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('EPA: ${t.epa!.toStringAsFixed(1)}', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: secondaryTextColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRankBadge(int rank) {
    Color bg = Colors.transparent;
    Color border = ObsidianUITheme.getBorderColor(context);
    Color textColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (rank == 1) {
      bg = const Color(0xFFFFD700).withValues(alpha: 0.2);
      border = const Color(0xFFFFD700);
      textColor = const Color(0xFFFFD700);
    } else if (rank == 2) {
      bg = const Color(0xFFC0C0C0).withValues(alpha: 0.2);
      border = const Color(0xFFC0C0C0);
      textColor = const Color(0xFFC0C0C0);
    } else if (rank == 3) {
      bg = const Color(0xFFCD7F32).withValues(alpha: 0.2);
      border = const Color(0xFFCD7F32);
      textColor = const Color(0xFFCD7F32);
    }

    return Container(
      width: 32,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        '#$rank',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: textColor),
      ),
    );
  }

  void _openTeamDetails(TeamModel team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => TeamDetailsScreen(
          team: team,
          apiService: widget.apiService,
          eventKey: _selectedEventKey,
        ),
      ),
    );
  }
}
