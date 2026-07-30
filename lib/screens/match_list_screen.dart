import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class MatchListScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const MatchListScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  List<MatchModel> _matches = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterLevel = 'all'; // 'all', 'qm', 'qf', 'sf', 'f'

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void didUpdateWidget(covariant MatchListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadMatches();
    }
  }

  Future<void> _loadMatches() async {
    setState(() => _isLoading = true);
    final eventKey = await widget.apiService.fetchCurrentEventKey();
    final matches = await widget.apiService.fetchMatches(eventKey);
    if (mounted) {
      setState(() {
        _matches = matches;
        _isLoading = false;
      });
    }
  }

  List<MatchModel> get _filteredMatches {
    final q = _searchQuery.toLowerCase();
    return _matches.where((m) {
      final levelOk = _filterLevel == 'all' || m.compLevel.toLowerCase() == _filterLevel;
      final searchOk = q.isEmpty ||
          m.displayLabel.toLowerCase().contains(q) ||
          m.matchKey.toLowerCase().contains(q) ||
          m.redTeams.any((t) => t.contains(q)) ||
          m.blueTeams.any((t) => t.contains(q));
      return levelOk && searchOk;
    }).toList()
      ..sort((a, b) {
        final levelOrder = {'qm': 0, 'qf': 1, 'sf': 2, 'f': 3};
        final la = levelOrder[a.compLevel.toLowerCase()] ?? 4;
        final lb = levelOrder[b.compLevel.toLowerCase()] ?? 4;
        if (la != lb) return la.compareTo(lb);
        return (a.matchNumber ?? 0).compareTo(b.matchNumber ?? 0);
      });
  }

  Color _levelColor(String compLevel) {
    switch (compLevel.toLowerCase()) {
      case 'qm':
        return ObsidianUITheme.primaryAccent;
      case 'qf':
        return Colors.orange;
      case 'sf':
        return Colors.deepOrangeAccent;
      case 'f':
        return Colors.amber;
      default:
        return Colors.white54;
    }
  }

  String _levelLabel(String compLevel) {
    switch (compLevel.toLowerCase()) {
      case 'qm':
        return 'QUAL';
      case 'qf':
        return 'QF';
      case 'sf':
        return 'SF';
      case 'f':
        return 'FINAL';
      default:
        return compLevel.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final filtered = _filteredMatches;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: widget.isBarsVisible ? 95.0 : 16.0,
        ),

        // Header + Search + Filter
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
                        color: ObsidianUITheme.secondaryAccent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.sports_esports_rounded, color: ObsidianUITheme.secondaryAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('nav.matches').toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${filtered.length} / ${_matches.length} ${context.tr("dashboard.matches")}',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: ObsidianUITheme.secondaryAccent),
                      tooltip: context.tr('dashboard.quick_sync'),
                      onPressed: _loadMatches,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  style: TextStyle(color: primaryTextColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by match label or team...',
                    hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: ObsidianUITheme.secondaryAccent, size: 20),
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
                      borderSide: const BorderSide(color: ObsidianUITheme.secondaryAccent),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 10),
                // Level filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('Level: ', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      const SizedBox(width: 6),
                      for (final entry in [
                        ('all', 'All'),
                        ('qm', 'Qualifications'),
                        ('qf', 'Quarterfinals'),
                        ('sf', 'Semifinals'),
                        ('f', 'Finals'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(entry.$2),
                            selected: _filterLevel == entry.$1,
                            selectedColor: ObsidianUITheme.secondaryAccent,
                            backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _filterLevel == entry.$1 ? Colors.white : secondaryTextColor,
                              fontWeight: _filterLevel == entry.$1 ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (_) => setState(() => _filterLevel = entry.$1),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Match list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: ObsidianUITheme.secondaryAccent))
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sports_esports_outlined, size: 56, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty && _filterLevel == 'all'
                                ? 'No matches loaded'
                                : 'No matches match your filter',
                            style: TextStyle(color: secondaryTextColor, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.isBarsVisible ? 100.0 : 20.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final match = filtered[i];
                        final levelColor = _levelColor(match.compLevel);

                        return ObsidianGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Match label + level badge
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: levelColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: levelColor.withValues(alpha: 0.5)),
                                    ),
                                    child: Text(
                                      _levelLabel(match.compLevel),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: levelColor,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      match.displayLabel,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '#${match.matchNumber ?? '–'}',
                                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                              if (match.redTeams.isNotEmpty || match.blueTeams.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    // Red alliance
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
                                              const SizedBox(width: 4),
                                              Text('Red Alliance', style: TextStyle(fontSize: 10, color: Colors.redAccent.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: match.redTeams
                                                .map((t) => Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(t, style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                                    ))
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(width: 1, height: 36, color: ObsidianUITheme.getBorderColor(context)),
                                    const SizedBox(width: 12),
                                    // Blue alliance
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent)),
                                              const SizedBox(width: 4),
                                              Text('Blue Alliance', style: TextStyle(fontSize: 10, color: Colors.blueAccent.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: match.blueTeams
                                                .map((t) => Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(t, style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                                    ))
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
