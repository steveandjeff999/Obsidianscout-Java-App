import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/predictor_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_glass_card.dart';

class PredictorScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final String? initialMatchKey;

  const PredictorScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.initialMatchKey,
  });

  @override
  State<PredictorScreen> createState() => _PredictorScreenState();
}

class _PredictorScreenState extends State<PredictorScreen> {
  List<MatchModel> _matches = [];
  String? _selectedMatchKey;
  MatchPredictionResponse? _prediction;

  bool _isLoadingMatches = true;
  bool _isCalculating = false;
  String _dataSource = 'scouted'; // 'all', 'scouted', 'epa', 'opr'
  bool _usePrescout = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
    _loadMatches();
  }

  @override
  void didUpdateWidget(covariant PredictorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadMatches();
    }
  }

  void _initSettings() {
    final settings = widget.apiService.currentSettings;
    final isFtc = widget.apiService.currentProgram.toUpperCase() == 'FTC';
    final effectiveEpa = !isFtc && (settings?.useStatboticsEpa ?? false);
    final effectiveOpr = settings?.useTbaOpr ?? false;

    if (effectiveEpa && effectiveOpr) {
      _dataSource = 'all';
    } else if (effectiveEpa) {
      _dataSource = 'epa';
    } else if (effectiveOpr) {
      _dataSource = 'opr';
    } else {
      _dataSource = 'scouted';
    }
  }

  Future<void> _loadMatches() async {
    final eventKey = widget.apiService.currentSettings?.eventKey ?? await widget.apiService.getCachedEventKey();
    final cachedMatches = await widget.apiService.getCachedMatches(eventKey);

    if (mounted && cachedMatches.isNotEmpty) {
      setState(() {
        _matches = cachedMatches;
        _isLoadingMatches = false;
        if (_selectedMatchKey == null && widget.initialMatchKey != null) {
          _selectedMatchKey = widget.initialMatchKey;
        }
      });
      if (_selectedMatchKey != null) {
        _fetchPrediction(_selectedMatchKey!);
      }
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoadingMatches) setState(() => _isLoadingMatches = false);
      return;
    }

    try {
      final matches = await widget.apiService.fetchMatches(eventKey);
      if (mounted) {
        setState(() {
          if (matches.isNotEmpty) {
            _matches = matches;
          }
          _isLoadingMatches = false;
          if (_selectedMatchKey == null && widget.initialMatchKey != null) {
            _selectedMatchKey = widget.initialMatchKey;
          }
        });
        if (_selectedMatchKey != null && _prediction == null) {
          _fetchPrediction(_selectedMatchKey!);
        }
      }
    } catch (_) {
      if (mounted && _isLoadingMatches) {
        setState(() => _isLoadingMatches = false);
      }
    }
  }

  Future<void> _fetchPrediction(String matchKey) async {
    final eventKey = widget.apiService.currentSettings?.eventKey ?? await widget.apiService.getCachedEventKey() ?? '';

    // 1. Immediately render cached prediction if available
    final cached = await widget.apiService.getCachedMatchPrediction(
      eventKey: eventKey,
      matchKey: matchKey,
      usePrescout: _usePrescout,
    );
    if (cached != null && mounted) {
      setState(() {
        _prediction = cached;
        _isCalculating = false;
      });
    } else if (mounted) {
      setState(() => _isCalculating = true);
    }

    // 2. Fetch fresh prediction from network in background
    try {
      final pred = await widget.apiService.fetchMatchPrediction(
        matchKey,
        eventKey: eventKey,
        usePrescout: _usePrescout,
      );
      if (mounted && pred != null) {
        setState(() {
          _prediction = pred;
          _isCalculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCalculating = false);
        if (_prediction == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to calculate prediction: $e'),
              backgroundColor: const Color(0xFFB91C1C),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    final settings = widget.apiService.currentSettings;
    final isFtc = widget.apiService.currentProgram.toUpperCase() == 'FTC';
    final effectiveEpa = !isFtc && (settings?.useStatboticsEpa ?? false);
    final effectiveOpr = settings?.useTbaOpr ?? false;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadMatches();
        if (_selectedMatchKey != null) {
          await _fetchPrediction(_selectedMatchKey!);
        }
      },
      color: Colors.cyanAccent,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 32.0 : 16.0,
          isDesktop ? 24.0 : 100.0,
          isDesktop ? 32.0 : 16.0,
          isDesktop ? 32.0 : 110.0,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Header Controls Card
          ObsidianGlassCard(
            borderRadius: 16.0,
            margin: const EdgeInsets.only(bottom: 16.0),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 22.0),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('predictor.title'),
                            style: TextStyle(
                              fontSize: isDesktop ? 20.0 : 17.0,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            isFtc
                                ? context.tr('predictor.notice_ftc')
                                : context.tr('predictor.notice'),
                            style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18.0),

                // Match Selector Dropdown
                Text(
                  context.tr('predictor.choose_match'),
                  style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600, color: secondaryTextColor),
                ),
                const SizedBox(height: 6.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _matches.any((m) => m.matchKey == _selectedMatchKey) ? _selectedMatchKey : null,
                      hint: Text(
                        _isLoadingMatches
                            ? context.tr('predictor.loading_matches')
                            : (_matches.isEmpty
                                ? context.tr('predictor.no_matches_found')
                                : context.tr('predictor.choose_match')),
                        style: TextStyle(color: secondaryTextColor, fontSize: 14.0),
                      ),
                      dropdownColor: isDark ? const Color(0xFF1E2430) : Colors.white,
                      style: TextStyle(color: primaryTextColor, fontSize: 14.0, fontWeight: FontWeight.w600),
                      items: _matches.map((m) {
                        final label = m.label.isNotEmpty
                            ? m.label
                            : '${m.compLevel.toUpperCase()} ${m.matchNumber}';
                        return DropdownMenuItem<String>(
                          value: m.matchKey,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedMatchKey = val);
                          _fetchPrediction(val);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14.0),

                // Controls Row: Data Source & Prescout Toggle
                Wrap(
                  spacing: 16.0,
                  runSpacing: 12.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (effectiveEpa || effectiveOpr) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('predictor.data_source'),
                            style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: secondaryTextColor),
                          ),
                          const SizedBox(height: 6.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _dataSource,
                                dropdownColor: isDark ? const Color(0xFF1E2430) : Colors.white,
                                style: TextStyle(color: primaryTextColor, fontSize: 13.0, fontWeight: FontWeight.w500),
                                items: [
                                  if (effectiveEpa && effectiveOpr)
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text(context.tr('predictor.all_3')),
                                    ),
                                  DropdownMenuItem(
                                    value: 'scouted',
                                    child: Text(context.tr('predictor.scouted_data')),
                                  ),
                                  if (effectiveEpa)
                                    DropdownMenuItem(
                                      value: 'epa',
                                      child: Text(context.tr('predictor.statbotics_epa')),
                                    ),
                                  if (effectiveOpr)
                                    DropdownMenuItem(
                                      value: 'opr',
                                      child: Text(isFtc ? context.tr('predictor.ftcscout_opr') : context.tr('predictor.tba_opr')),
                                    ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _dataSource = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Force Prescout Data Checkbox
                    Padding(
                      padding: const EdgeInsets.only(top: 14.0),
                      child: InkWell(
                        onTap: () {
                          setState(() => _usePrescout = !_usePrescout);
                          if (_selectedMatchKey != null) {
                            _fetchPrediction(_selectedMatchKey!);
                          }
                        },
                        borderRadius: BorderRadius.circular(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _usePrescout,
                              activeColor: Colors.cyanAccent,
                              checkColor: Colors.black,
                              onChanged: (val) {
                                setState(() => _usePrescout = val ?? false);
                                if (_selectedMatchKey != null) {
                                  _fetchPrediction(_selectedMatchKey!);
                                }
                              },
                            ),
                            Text(
                              context.tr('event_predictor.force_prescout'),
                              style: TextStyle(fontSize: 13.0, color: primaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Workspace
          if (_isCalculating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48.0),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(height: 16.0),
                    Text(
                      context.tr('event_predictor.calculating'),
                      style: TextStyle(color: secondaryTextColor, fontSize: 14.0),
                    ),
                  ],
                ),
              ),
            )
          else if (_prediction == null)
            _buildEmptyState(context, isDark, primaryTextColor, secondaryTextColor)
          else
            ..._buildPredictionDetails(context, isDark, primaryTextColor, secondaryTextColor, isDesktop, effectiveEpa, effectiveOpr, isFtc),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark, Color primaryTextColor, Color secondaryTextColor) {
    return ObsidianGlassCard(
      borderRadius: 16.0,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(36.0),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.sports_score_rounded, size: 54.0, color: secondaryTextColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16.0),
            Text(
              context.tr('predictor.no_match_selected'),
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
            const SizedBox(height: 8.0),
            Text(
              context.tr('predictor.please_choose_a_match_from_the'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.0, color: secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPredictionDetails(
    BuildContext context,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    bool isDesktop,
    bool effectiveEpa,
    bool effectiveOpr,
    bool isFtc,
  ) {
    final pred = _prediction!;
    final red = pred.redAlliance;
    final blue = pred.blueAlliance;

    final redScouted = red.totalScoutedScore;
    final blueScouted = blue.totalScoutedScore;
    final redEpa = red.totalEpa;
    final blueEpa = blue.totalEpa;
    final redOpr = red.totalOpr;
    final blueOpr = blue.totalOpr;

    return [
      // Spotlight Winner Cards
      if (_dataSource == 'all' || _dataSource == 'scouted')
        _buildSpotlightCard(
          context: context,
          title: context.tr('predictor.scouted_prediction'),
          icon: Icons.sports_score_rounded,
          accentColor: Colors.amberAccent,
          redScore: redScouted,
          blueScore: blueScouted,
          unit: 'pts',
          isDark: isDark,
        ),

      if (effectiveEpa && (_dataSource == 'all' || _dataSource == 'epa'))
        _buildSpotlightCard(
          context: context,
          title: context.tr('predictor.epa_prediction'),
          icon: Icons.bolt_rounded,
          accentColor: Colors.cyanAccent,
          redScore: redEpa,
          blueScore: blueEpa,
          unit: 'EPA',
          isDark: isDark,
        ),

      if (effectiveOpr && (_dataSource == 'all' || _dataSource == 'opr'))
        _buildSpotlightCard(
          context: context,
          title: isFtc ? 'FTC Scout OPR Prediction' : context.tr('predictor.opr_prediction'),
          icon: Icons.insights_rounded,
          accentColor: Colors.purpleAccent,
          redScore: redOpr,
          blueScore: blueOpr,
          unit: 'OPR',
          isDark: isDark,
        ),

      // Comparison Progress Bars Card
      ObsidianGlassCard(
        borderRadius: 16.0,
        margin: const EdgeInsets.only(bottom: 16.0),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: Colors.cyanAccent, size: 20.0),
                const SizedBox(width: 8.0),
                Text(
                  context.tr('predictor.alliance_comparison'),
                  style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: 6.0),
            Text(
              context.tr('predictor.visual_representation_of_relat'),
              style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
            ),
            const SizedBox(height: 16.0),

            if (_dataSource == 'all' || _dataSource == 'scouted') ...[
              _buildComparisonBar(
                title: context.tr('predictor.scouted_score'),
                redVal: redScouted,
                blueVal: blueScouted,
                unit: 'pts',
                isDark: isDark,
              ),
              const SizedBox(height: 14.0),
            ],

            if (effectiveEpa && (_dataSource == 'all' || _dataSource == 'epa')) ...[
              _buildComparisonBar(
                title: context.tr('predictor.statbotics_epa'),
                redVal: redEpa,
                blueVal: blueEpa,
                unit: 'EPA',
                isDark: isDark,
              ),
              const SizedBox(height: 14.0),
            ],

            if (effectiveOpr && (_dataSource == 'all' || _dataSource == 'opr')) ...[
              _buildComparisonBar(
                title: isFtc ? context.tr('predictor.ftcscout_opr') : context.tr('predictor.tba_opr'),
                redVal: redOpr,
                blueVal: blueOpr,
                unit: 'OPR',
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),

      // Alliance Breakdown Cards (Red & Blue side by side on desktop, stacked on mobile)
      if (isDesktop)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildAllianceRoster(context, 'Red Alliance', red, const Color(0xFFEF4444), isDark, effectiveEpa, effectiveOpr)),
            const SizedBox(width: 16.0),
            Expanded(child: _buildAllianceRoster(context, 'Blue Alliance', blue, const Color(0xFF3B82F6), isDark, effectiveEpa, effectiveOpr)),
          ],
        )
      else ...[
        _buildAllianceRoster(context, 'Red Alliance', red, const Color(0xFFEF4444), isDark, effectiveEpa, effectiveOpr),
        const SizedBox(height: 16.0),
        _buildAllianceRoster(context, 'Blue Alliance', blue, const Color(0xFF3B82F6), isDark, effectiveEpa, effectiveOpr),
      ],
    ];
  }

  Widget _buildSpotlightCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color accentColor,
    required double redScore,
    required double blueScore,
    required String unit,
    required bool isDark,
  }) {
    String winnerText;
    Color winnerColor;
    String subtext;

    if (redScore == 0 && blueScore == 0) {
      winnerText = context.tr('predictor.no_data');
      winnerColor = Colors.grey;
      subtext = 'Insufficient $unit entries for predictions.';
    } else {
      final diff = (redScore - blueScore).abs();
      if (redScore > blueScore) {
        winnerText = context.tr('predictor.red_alliance');
        winnerColor = const Color(0xFFEF4444);
        subtext = 'Predicted to win by ${diff.toStringAsFixed(1)} $unit';
      } else if (blueScore > redScore) {
        winnerText = context.tr('predictor.blue_alliance');
        winnerColor = const Color(0xFF3B82F6);
        subtext = 'Predicted to win by ${diff.toStringAsFixed(1)} $unit';
      } else {
        winnerText = context.tr('predictor.dead_heat');
        winnerColor = Colors.amberAccent;
        subtext = 'Alliances have identical combined $unit values.';
      }
    }

    return ObsidianGlassCard(
      borderRadius: 16.0,
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(18.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: winnerColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: winnerColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: winnerColor, size: 28.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: ObsidianUITheme.getSecondaryTextColor(context)),
                ),
                const SizedBox(height: 2.0),
                Text(
                  winnerText,
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w800, color: winnerColor),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtext,
                  style: TextStyle(fontSize: 12.0, color: ObsidianUITheme.getSecondaryTextColor(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonBar({
    required String title,
    required double redVal,
    required double blueVal,
    required String unit,
    required bool isDark,
  }) {
    final total = redVal + blueVal;
    final redPct = total > 0 ? (redVal / total).clamp(0.05, 0.95) : 0.5;
    final bluePct = 1.0 - redPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Red: ${redVal.toStringAsFixed(1)} $unit',
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.0, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12.0, fontWeight: FontWeight.w600),
            ),
            Text(
              'Blue: ${blueVal.toStringAsFixed(1)} $unit',
              style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 12.0, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            height: 12.0,
            child: Row(
              children: [
                Expanded(
                  flex: (redPct * 100).round(),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                      ),
                    ),
                  ),
                ),
                Container(width: 2.0, color: isDark ? Colors.black : Colors.white),
                Expanded(
                  flex: (bluePct * 100).round(),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Computes the displayed point value for an individual team based on the active dataSource.
  /// If scouted/epa/opr is selected: returns that metric's value if present and non-zero.
  /// If 'all' is selected: returns the composite average of the available non-zero metrics among
  /// [averageScoutedScore, epa, opr] (excluding 0s and nulls).
  double? _getTeamPoints(MatchTeamPrediction team, bool effectiveEpa, bool effectiveOpr) {
    if (_dataSource == 'scouted') {
      final s = team.averageScoutedScore;
      return (s != null && s > 0) ? s : null;
    } else if (_dataSource == 'epa') {
      final e = team.epa;
      return (effectiveEpa && e != null && e > 0) ? e : null;
    } else if (_dataSource == 'opr') {
      final o = team.opr;
      return (effectiveOpr && o != null && o > 0) ? o : null;
    } else {
      // 'all': composite average of the 3 (scouted, epa, opr) excluding 0s and nulls
      final values = <double>[];
      if (team.averageScoutedScore != null && team.averageScoutedScore! > 0) {
        values.add(team.averageScoutedScore!);
      }
      if (effectiveEpa && team.epa != null && team.epa! > 0) {
        values.add(team.epa!);
      }
      if (effectiveOpr && team.opr != null && team.opr! > 0) {
        values.add(team.opr!);
      }
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }
  }

  double _getAllianceTotal(AlliancePrediction alliance, bool effectiveEpa, bool effectiveOpr) {
    if (_dataSource == 'scouted') {
      return alliance.totalScoutedScore;
    } else if (_dataSource == 'epa') {
      return effectiveEpa ? alliance.totalEpa : 0.0;
    } else if (_dataSource == 'opr') {
      return effectiveOpr ? alliance.totalOpr : 0.0;
    } else {
      // 'all': sum of composite team points
      double sum = 0.0;
      bool hasAny = false;
      for (final t in alliance.teams) {
        final p = _getTeamPoints(t, effectiveEpa, effectiveOpr);
        if (p != null) {
          sum += p;
          hasAny = true;
        }
      }
      if (hasAny) return sum;
      final totals = <double>[];
      if (alliance.totalScoutedScore > 0) totals.add(alliance.totalScoutedScore);
      if (effectiveEpa && alliance.totalEpa > 0) totals.add(alliance.totalEpa);
      if (effectiveOpr && alliance.totalOpr > 0) totals.add(alliance.totalOpr);
      if (totals.isEmpty) return 0.0;
      return totals.reduce((a, b) => a + b) / totals.length;
    }
  }

  Widget _buildAllianceRoster(
    BuildContext context,
    String allianceName,
    AlliancePrediction alliance,
    Color allianceColor,
    bool isDark,
    bool effectiveEpa,
    bool effectiveOpr,
  ) {
    final allianceTotal = _getAllianceTotal(alliance, effectiveEpa, effectiveOpr);
    final unit = _dataSource == 'opr' ? 'OPR' : (_dataSource == 'epa' ? 'EPA' : 'pts');

    return ObsidianGlassCard(
      borderRadius: 16.0,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10.0,
                height: 10.0,
                decoration: BoxDecoration(color: allianceColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8.0),
              Text(
                allianceName,
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: allianceColor),
              ),
              const Spacer(),
              Text(
                '${allianceTotal.toStringAsFixed(1)} $unit',
                style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w800, color: ObsidianUITheme.getPrimaryTextColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // Teams List
          if (alliance.teams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text('No teams in alliance', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
            )
          else
            ...alliance.teams.map((t) {
              final teamPts = _getTeamPoints(t, effectiveEpa, effectiveOpr);

              return Container(
                margin: const EdgeInsets.only(bottom: 10.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: allianceColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(color: allianceColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '#${t.teamNumber}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: allianceColor, fontSize: 13.0),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            t.nickname ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13.0),
                          ),
                        ),
                        Text(
                          teamPts != null ? '${teamPts.toStringAsFixed(1)} $unit' : 'No data',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: teamPts != null ? Colors.cyanAccent : ObsidianUITheme.getSecondaryTextColor(context),
                            fontSize: 13.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 4.0,
                      children: [
                        _buildPill('${t.scoutedMatchesCount} matches', isDark),
                        if (effectiveEpa && t.epa != null)
                          _buildPill('EPA: ${t.epa!.toStringAsFixed(1)}', isDark),
                        if (effectiveOpr && t.opr != null)
                          _buildPill('OPR: ${t.opr!.toStringAsFixed(1)}', isDark),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPill(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5.0),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.0, color: isDark ? Colors.white70 : Colors.black87),
      ),
    );
  }
}
