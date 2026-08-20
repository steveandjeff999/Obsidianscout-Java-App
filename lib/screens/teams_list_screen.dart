import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import 'team_details_screen.dart';

class TeamsListScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const TeamsListScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<TeamsListScreen> createState() => _TeamsListScreenState();
}

class _TeamsListScreenState extends State<TeamsListScreen> {
  List<TeamModel> _teams = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'number'; // 'number', 'name', 'epa', 'opr'

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void didUpdateWidget(covariant TeamsListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadTeams();
    }
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    final eventKey = await widget.apiService.fetchCurrentEventKey();
    final teams = await widget.apiService.fetchTeams(eventKey);
    if (mounted) {
      setState(() {
        _teams = teams;
        _isLoading = false;
      });
    }
  }

  List<TeamModel> get _filteredSorted {
    final q = _searchQuery.toLowerCase();
    List<TeamModel> filtered = _teams.where((t) {
      return q.isEmpty ||
          t.teamNumber.toString().contains(q) ||
          (t.nickname ?? '').toLowerCase().contains(q) ||
          (t.name ?? '').toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'name':
          return (a.nickname ?? a.name ?? '').compareTo(b.nickname ?? b.name ?? '');
        case 'epa':
          return (b.epa ?? 0).compareTo(a.epa ?? 0);
        case 'opr':
          return (b.opr ?? 0).compareTo(a.opr ?? 0);
        case 'number':
        default:
          return a.teamNumber.compareTo(b.teamNumber);
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: 4.0,
        ),

        // Search & Sort Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
          child: ObsidianGlassCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.groups_rounded, color: ObsidianUITheme.primaryAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('nav.teams').toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${_filteredSorted.length} / ${_teams.length} ${context.tr("dashboard.teams")}',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: ObsidianUITheme.primaryAccent),
                      tooltip: context.tr('dashboard.quick_sync'),
                      onPressed: _loadTeams,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  style: TextStyle(color: primaryTextColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: context.tr('alliance-selection.placeholder_search_team_number_or_name'),
                    hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                    filled: true,
                    fillColor: surfaceColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 10),
                // Sort chips
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('Sort: ', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      const SizedBox(width: 6),
                      for (final entry in [
                        ('number', Icons.tag_rounded, '# Number'),
                        ('name', Icons.sort_by_alpha_rounded, 'Name'),
                        ('epa', Icons.electric_bolt_rounded, 'EPA'),
                        ('opr', Icons.leaderboard_rounded, 'OPR'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(entry.$2, size: 14, color: _sortBy == entry.$1 ? Colors.white : secondaryTextColor),
                                const SizedBox(width: 4),
                                Text(entry.$3),
                              ],
                            ),
                            selected: _sortBy == entry.$1,
                            selectedColor: ObsidianUITheme.primaryAccent,
                            backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _sortBy == entry.$1 ? Colors.white : secondaryTextColor,
                              fontWeight: _sortBy == entry.$1 ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (_) => setState(() => _sortBy = entry.$1),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Teams list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent))
              : _filteredSorted.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups_outlined, size: 56, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty ? 'No teams loaded' : 'No teams match your search',
                            style: TextStyle(color: secondaryTextColor, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.isBarsVisible ? 100.0 : 20.0),
                      itemCount: _filteredSorted.length,
                      itemBuilder: (context, i) {
                        final team = _filteredSorted[i];
                        final hasStats = team.epa != null || team.opr != null || team.averagePoints != null;
                        return ObsidianGlassCard(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => TeamDetailsScreen(
                                  team: team,
                                  apiService: widget.apiService,
                                ),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      ObsidianUITheme.primaryAccent.withValues(alpha: 0.3),
                                      ObsidianUITheme.secondaryAccent.withValues(alpha: 0.2),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${team.teamNumber}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: ObsidianUITheme.primaryAccent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      team.nickname ?? team.name ?? 'Team ${team.teamNumber}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (team.name != null && team.nickname != null)
                                      Text(
                                        team.name!,
                                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (hasStats) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          if (team.epa != null)
                                            _statBadge(context, 'EPA', team.epa!.toStringAsFixed(1), Colors.amber),
                                          if (team.opr != null)
                                            _statBadge(context, 'OPR', team.opr!.toStringAsFixed(1), ObsidianUITheme.primaryAccent),
                                          if (team.averagePoints != null)
                                            _statBadge(context, 'AVG', team.averagePoints!.toStringAsFixed(1), ObsidianUITheme.secondaryAccent),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: secondaryTextColor.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _statBadge(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
