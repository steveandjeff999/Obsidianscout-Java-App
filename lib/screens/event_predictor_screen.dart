import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/predictor_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_glass_card.dart';
import 'predictor_screen.dart';

class EventPredictorScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const EventPredictorScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<EventPredictorScreen> createState() => _EventPredictorScreenState();
}

class _EventPredictorScreenState extends State<EventPredictorScreen> {
  List<EventModel> _events = [];
  String? _selectedEventKey;
  List<MatchPredictionResponse> _predictions = [];

  bool _isLoadingEvents = true;
  bool _isCalculating = false;
  String _dataSource = 'all'; // 'all', 'scouted', 'epa', 'opr'
  bool _usePrescout = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initSettings();
    _loadEvents();
  }

  @override
  void didUpdateWidget(covariant EventPredictorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadEvents();
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

  Future<void> _loadEvents() async {
    final currentEventKey = widget.apiService.currentSettings?.eventKey ?? await widget.apiService.getCachedEventKey();
    final cachedEvents = await widget.apiService.getCachedEvents();

    if (mounted && cachedEvents.isNotEmpty) {
      setState(() {
        _events = cachedEvents;
        _isLoadingEvents = false;
        if (_selectedEventKey == null && (currentEventKey != null && currentEventKey.isNotEmpty)) {
          _selectedEventKey = currentEventKey;
        }
      });
      if (_selectedEventKey != null) {
        _fetchPredictions(_selectedEventKey!);
      }
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoadingEvents) setState(() => _isLoadingEvents = false);
      return;
    }

    try {
      final events = await widget.apiService.fetchEvents();
      if (mounted) {
        setState(() {
          if (events.isNotEmpty) {
            _events = events;
          }
          _isLoadingEvents = false;
          _selectedEventKey ??= (currentEventKey != null && currentEventKey.isNotEmpty)
                ? currentEventKey
                : (events.isNotEmpty ? events.first.eventKey : null);
        });
        if (_selectedEventKey != null && _predictions.isEmpty) {
          _fetchPredictions(_selectedEventKey!);
        }
      }
    } catch (_) {
      if (mounted && _isLoadingEvents) {
        setState(() => _isLoadingEvents = false);
      }
    }
  }

  Future<void> _fetchPredictions(String eventKey) async {
    // 1. Immediately render cached predictions if available
    final cached = await widget.apiService.getCachedEventPredictions(
      eventKey,
      usePrescout: _usePrescout,
    );
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _predictions = cached;
        _isCalculating = false;
      });
    } else if (mounted) {
      setState(() => _isCalculating = true);
    }

    // 2. Fetch fresh predictions from server in background
    try {
      final preds = await widget.apiService.fetchEventPredictions(
        eventKey,
        usePrescout: _usePrescout,
      );
      if (mounted && preds.isNotEmpty) {
        setState(() {
          _predictions = preds;
          _isCalculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCalculating = false);
        if (_predictions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to calculate event predictions: $e'),
              backgroundColor: const Color(0xFFB91C1C),
            ),
          );
        }
      }
    }
  }

  List<MatchPredictionResponse> get _filteredPredictions {
    if (_searchQuery.isEmpty) return _predictions;
    final q = _searchQuery.toLowerCase().trim();
    return _predictions.where((m) {
      if (m.label.toLowerCase().contains(q)) return true;
      final redContains = m.redAlliance.teams.any((t) => t.teamNumber.toString().contains(q) || (t.nickname?.toLowerCase().contains(q) ?? false));
      final blueContains = m.blueAlliance.teams.any((t) => t.teamNumber.toString().contains(q) || (t.nickname?.toLowerCase().contains(q) ?? false));
      return redContains || blueContains;
    }).toList();
  }

  void _openMatchDetailModal(MatchPredictionResponse match) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: ObsidianUITheme.getSurfaceColor(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
                child: Column(
                  children: [
                    // Sheet Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                      ),
                      child: Row(
                        children: [
                          Text(
                            match.label,
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              color: ObsidianUITheme.getPrimaryTextColor(context),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PredictorScreen(
                        apiService: widget.apiService,
                        initialMatchKey: match.matchKey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

    final filtered = _filteredPredictions;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadEvents();
        if (_selectedEventKey != null) {
          await _fetchPredictions(_selectedEventKey!);
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
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Icon(Icons.leaderboard_rounded, color: Colors.cyanAccent, size: 22.0),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('event_predictor.title'),
                            style: TextStyle(
                              fontSize: isDesktop ? 20.0 : 17.0,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            isFtc
                                ? context.tr('event_predictor.notice_ftc')
                                : context.tr('event_predictor.notice'),
                            style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18.0),

                // Event Selector Dropdown
                Text(
                  context.tr('event_predictor.choose_event'),
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
                      value: _events.any((e) => e.eventKey == _selectedEventKey) ? _selectedEventKey : null,
                      hint: Text(
                        _isLoadingEvents
                            ? context.tr('event_predictor.calculating')
                            : (_events.isEmpty
                                ? 'No events synced'
                                : context.tr('event_predictor.choose_event_placeholder')),
                        style: TextStyle(color: secondaryTextColor, fontSize: 14.0),
                      ),
                      dropdownColor: isDark ? const Color(0xFF1E2430) : Colors.white,
                      style: TextStyle(color: primaryTextColor, fontSize: 14.0, fontWeight: FontWeight.w600),
                      items: _events.map((e) {
                        return DropdownMenuItem<String>(
                          value: e.eventKey,
                          child: Text('${e.name} (${e.eventKey.toUpperCase()})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedEventKey = val);
                          _fetchPredictions(val);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14.0),

                // Options Row: Model Selector & Prescout Toggle
                Wrap(
                  spacing: 16.0,
                  runSpacing: 12.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('event_predictor.model'),
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

                    Padding(
                      padding: const EdgeInsets.only(top: 14.0),
                      child: InkWell(
                        onTap: () {
                          setState(() => _usePrescout = !_usePrescout);
                          if (_selectedEventKey != null) {
                            _fetchPredictions(_selectedEventKey!);
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
                                if (_selectedEventKey != null) {
                                  _fetchPredictions(_selectedEventKey!);
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

                const SizedBox(height: 14.0),

                // Search Bar
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, color: secondaryTextColor, size: 20.0),
                    hintText: context.tr('event_predictor.search_placeholder'),
                    hintStyle: TextStyle(color: secondaryTextColor.withValues(alpha: 0.6), fontSize: 13.0),
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.7),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Matches Predictions List
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
          else if (_predictions.isEmpty)
            ObsidianGlassCard(
              borderRadius: 16.0,
              margin: const EdgeInsets.only(bottom: 16.0),
              padding: const EdgeInsets.all(36.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy_rounded, size: 54.0, color: secondaryTextColor.withValues(alpha: 0.5)),
                    const SizedBox(height: 16.0),
                    Text(
                      context.tr('event_predictor.no_event_selected'),
                      style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      context.tr('event_predictor.please_choose_event'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.0, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            ObsidianGlassCard(
              borderRadius: 16.0,
              margin: const EdgeInsets.only(bottom: 16.0),
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  context.tr('event_predictor.no_matches_found'),
                  style: TextStyle(color: secondaryTextColor, fontSize: 14.0),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text(
                '${filtered.length} matches forecasted',
                style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 0.5),
              ),
            ),
            ...filtered.map((match) => _buildMatchCard(context, match, isDark, primaryTextColor, secondaryTextColor, effectiveEpa, effectiveOpr, isFtc)),
          ],
        ],
      ),
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

  Widget _buildMatchCard(
    BuildContext context,
    MatchPredictionResponse match,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    bool effectiveEpa,
    bool effectiveOpr,
    bool isFtc,
  ) {
    final red = match.redAlliance;
    final blue = match.blueAlliance;

    final redPoints = _getAllianceTotal(red, effectiveEpa, effectiveOpr);
    final bluePoints = _getAllianceTotal(blue, effectiveEpa, effectiveOpr);
    final unit = _dataSource == 'opr' ? 'OPR' : (_dataSource == 'epa' ? 'EPA' : 'pts');

    final diff = (redPoints - bluePoints).abs();
    final bool isRedWinner = redPoints > bluePoints && (redPoints > 0 || bluePoints > 0);
    final bool isBlueWinner = bluePoints > redPoints && (redPoints > 0 || bluePoints > 0);
    final bool noData = redPoints == 0 && bluePoints == 0;

    Color winnerColor;
    String winnerBadgeText;
    if (noData) {
      winnerColor = Colors.grey;
      winnerBadgeText = 'No Data';
    } else if (isRedWinner) {
      winnerColor = const Color(0xFFEF4444);
      winnerBadgeText = '🏆 Red +${diff.toStringAsFixed(1)} $unit';
    } else if (isBlueWinner) {
      winnerColor = const Color(0xFF3B82F6);
      winnerBadgeText = '🏆 Blue +${diff.toStringAsFixed(1)} $unit';
    } else {
      winnerColor = Colors.amberAccent;
      winnerBadgeText = '⚖️ Split / Tie';
    }

    final totalScore = redPoints + bluePoints;
    final redPct = totalScore > 0 ? (redPoints / totalScore).clamp(0.05, 0.95) : 0.5;
    final bluePct = 1.0 - redPct;

    return Container(
      margin: const EdgeInsets.only(bottom: 14.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isRedWinner
              ? const Color(0xFFEF4444).withValues(alpha: 0.35)
              : (isBlueWinner
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                  : (isDark ? Colors.white12 : Colors.black12)),
          width: (isRedWinner || isBlueWinner) ? 1.5 : 1.0,
        ),
      ),
      child: ObsidianGlassCard(
        borderRadius: 16.0,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16.0),
        child: InkWell(
          onTap: () => _openMatchDetailModal(match),
          borderRadius: BorderRadius.circular(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Match Label & Winner Badge Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        match.label,
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Icon(Icons.open_in_new_rounded, size: 14.0, color: secondaryTextColor.withValues(alpha: 0.7)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
                    decoration: BoxDecoration(
                      color: winnerColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: winnerColor.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      winnerBadgeText,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: winnerColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Visual Progress Bar
              if (totalScore > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.0),
                  child: SizedBox(
                    height: 8.0,
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
                const SizedBox(height: 12.0),
              ],

              // Alliances Teams and Score Cards Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Red Alliance Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: isRedWinner ? 0.14 : 0.06),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: isRedWinner ? 0.5 : 0.2),
                          width: isRedWinner ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8.0,
                                height: 8.0,
                                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6.0),
                              const Text(
                                'Red',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 13.0),
                              ),
                              if (isRedWinner) ...[
                                const SizedBox(width: 4.0),
                                const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14.0),
                              ],
                              const Spacer(),
                              Text(
                                '${redPoints.toStringAsFixed(1)} $unit',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFEF4444),
                                  fontSize: 14.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8.0),
                          Wrap(
                            spacing: 4.0,
                            runSpacing: 4.0,
                            children: red.teams.map((t) {
                              final teamPts = _getTeamPoints(t, effectiveEpa, effectiveOpr);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5.0),
                                ),
                                child: Text(
                                  teamPts != null
                                      ? '#${t.teamNumber} (${teamPts.toStringAsFixed(1)})'
                                      : '#${t.teamNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEF4444),
                                    fontSize: 11.5,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  // Blue Alliance Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: isBlueWinner ? 0.14 : 0.06),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: isBlueWinner ? 0.5 : 0.2),
                          width: isBlueWinner ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8.0,
                                height: 8.0,
                                decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6.0),
                              const Text(
                                'Blue',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6), fontSize: 13.0),
                              ),
                              if (isBlueWinner) ...[
                                const SizedBox(width: 4.0),
                                const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14.0),
                              ],
                              const Spacer(),
                              Text(
                                '${bluePoints.toStringAsFixed(1)} $unit',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3B82F6),
                                  fontSize: 14.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8.0),
                          Wrap(
                            spacing: 4.0,
                            runSpacing: 4.0,
                            children: blue.teams.map((t) {
                              final teamPts = _getTeamPoints(t, effectiveEpa, effectiveOpr);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5.0),
                                ),
                                child: Text(
                                  teamPts != null
                                      ? '#${t.teamNumber} (${teamPts.toStringAsFixed(1)})'
                                      : '#${t.teamNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3B82F6),
                                    fontSize: 11.5,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Details & Score Summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      noData
                          ? 'Insufficient data to predict'
                          : (isRedWinner
                              ? 'Red Alliance predicted to lead by ${diff.toStringAsFixed(1)} $unit'
                              : (isBlueWinner
                                  ? 'Blue Alliance predicted to lead by ${diff.toStringAsFixed(1)} $unit'
                                  : 'Alliances predicted to be evenly matched')),
                      style: TextStyle(fontSize: 12.0, color: secondaryTextColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    'Details →',
                    style: TextStyle(fontSize: 11.5, color: Colors.cyanAccent.withValues(alpha: 0.8), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
