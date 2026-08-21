import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../models/validation_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import 'team_details_screen.dart';

class DataValidationScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const DataValidationScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<DataValidationScreen> createState() => _DataValidationScreenState();
}

class _DataValidationScreenState extends State<DataValidationScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<EventModel> _events = [];
  String _selectedEventKey = '';
  double _threshold = 15.0;
  String _filterStatus = 'all'; // 'all', 'anomalies', 'incomplete', 'complete'
  bool _forcePrescout = false;
  final TextEditingController _searchController = TextEditingController();

  int _currentTab = 0; // 0: Matches, 1: Teams
  ValidationSummaryModel? _summaryData;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
    _loadEventsAndData();
  }

  @override
  void didUpdateWidget(covariant DataValidationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEventsAndData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final events = await widget.apiService.fetchEvents();
      final currentEventKey = await widget.apiService.fetchCurrentEventKey() ?? '';

      String initialEvent = currentEventKey;
      if (initialEvent.isEmpty && events.isNotEmpty) {
        initialEvent = events.first.eventKey;
      }

      if (mounted) {
        setState(() {
          _events = events;
          _selectedEventKey = initialEvent;
        });
      }

      if (initialEvent.isNotEmpty) {
        await _loadData();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load events: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    if (_selectedEventKey.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await widget.apiService.fetchValidationData(
        eventKey: _selectedEventKey,
        threshold: _threshold,
        forcePrescout: _forcePrescout,
      );

      if (mounted) {
        setState(() {
          _summaryData = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Validation check failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<MatchValidationModel> _getFilteredMatches() {
    if (_summaryData == null) return [];
    var list = _summaryData!.matches;

    // Filter by status
    if (_filterStatus == 'anomalies') {
      list = list.where((m) => m.hasAnomaly).toList();
    } else if (_filterStatus == 'incomplete') {
      list = list
          .where((m) =>
              !m.isFullyScouted &&
              (m.redAlliance.scoutedTeams.isNotEmpty || m.blueAlliance.scoutedTeams.isNotEmpty))
          .toList();
    } else if (_filterStatus == 'complete') {
      list = list.where((m) => m.isFullyScouted).toList();
    }

    // Filter by search
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((m) {
        final label = m.label.toLowerCase();
        final key = m.matchKey.toLowerCase();
        final redTeams = m.redAlliance.teams.map((t) => t.toString());
        final blueTeams = m.blueAlliance.teams.map((t) => t.toString());
        return label.contains(q) ||
            key.contains(q) ||
            redTeams.any((t) => t.contains(q)) ||
            blueTeams.any((t) => t.contains(q));
      }).toList();
    }

    return list;
  }

  List<TeamValidationModel> _getFilteredTeams() {
    if (_summaryData == null) return [];
    var list = _summaryData!.teams;

    // Filter by status
    if (_filterStatus == 'anomalies' || _filterStatus == 'incomplete') {
      list = list.where((t) => t.isAnomaly).toList();
    } else if (_filterStatus == 'complete') {
      list = list.where((t) => t.scoutedMatchCount > 0 && !t.isAnomaly).toList();
    }

    // Filter by search
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((t) {
        final numStr = t.teamNumber.toString();
        final name = t.nickname.toLowerCase();
        return numStr.contains(q) || name.contains(q);
      }).toList();
    }

    return list;
  }

  void _showMatchInspectionModal(MatchValidationModel match) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MatchInspectionBottomSheet(
        match: match,
        apiService: widget.apiService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    return RefreshIndicator(
      onRefresh: _loadData,
      color: ObsidianUITheme.primaryAccent,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 8.0,
          bottom: widget.isBarsVisible ? 120.0 : 24.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controls Card
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                        ),
                        child: const Icon(
                          Icons.fact_check_rounded,
                          color: ObsidianUITheme.primaryAccent,
                          size: 24.0,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('nav.data-validation', 'Data Validation & Anomaly Detection'),
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            Text(
                              context.tr('subtitle.data-validation', 'Compare scouting entries vs official match scores & EPA/OPR'),
                              style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),

                  // Event Selector Dropdown
                  Text(
                    'EVENT',
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w700,
                      color: tertiaryTextColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedEventKey.isNotEmpty && _events.any((e) => e.eventKey == _selectedEventKey)
                            ? _selectedEventKey
                            : (_events.isNotEmpty ? _events.first.eventKey : null),
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(
                          color: primaryTextColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.0,
                        ),
                        items: _events.map((e) {
                          return DropdownMenuItem<String>(
                            value: e.eventKey,
                            child: Text(
                              '${e.name} (${e.eventKey.toUpperCase()})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && val != _selectedEventKey) {
                            setState(() {
                              _selectedEventKey = val;
                            });
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14.0),

                  // Threshold & Filter Status row
                  Row(
                    children: [
                      // Threshold Selector
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ANOMALY THRESHOLD',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.w700,
                                color: tertiaryTextColor,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  value: _threshold,
                                  isExpanded: true,
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  style: TextStyle(color: primaryTextColor, fontSize: 13.0, fontWeight: FontWeight.w600),
                                  items: const [
                                    DropdownMenuItem(value: 5.0, child: Text('5+ pts delta')),
                                    DropdownMenuItem(value: 10.0, child: Text('10+ pts delta')),
                                    DropdownMenuItem(value: 15.0, child: Text('15+ pts (Default)')),
                                    DropdownMenuItem(value: 20.0, child: Text('20+ pts delta')),
                                    DropdownMenuItem(value: 30.0, child: Text('30+ pts delta')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null && val != _threshold) {
                                      setState(() => _threshold = val);
                                      _loadData();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12.0),

                      // Status Filter
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FILTER STATUS',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.w700,
                                color: tertiaryTextColor,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _filterStatus,
                                  isExpanded: true,
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  style: TextStyle(color: primaryTextColor, fontSize: 13.0, fontWeight: FontWeight.w600),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All Records')),
                                    DropdownMenuItem(value: 'anomalies', child: Text('Anomalies Only')),
                                    DropdownMenuItem(value: 'incomplete', child: Text('Incomplete Only')),
                                    DropdownMenuItem(value: 'complete', child: Text('Complete Only')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _filterStatus = val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),

                  // Prescout toggle
                  InkWell(
                    onTap: () {
                      setState(() {
                        _forcePrescout = !_forcePrescout;
                      });
                      _loadData();
                    },
                    borderRadius: BorderRadius.circular(8.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _forcePrescout,
                            activeColor: ObsidianUITheme.primaryAccent,
                            onChanged: (val) {
                              setState(() {
                                _forcePrescout = val ?? false;
                              });
                              _loadData();
                            },
                          ),
                          Text(
                            'Include Prescout',
                            style: TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Search Field
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by Match (e.g. QM 4) or Team Number (e.g. 254)...',
                      hintStyle: TextStyle(fontSize: 13.0, color: tertiaryTextColor),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18.0),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12.0),

            // KPI Grid
            if (_summaryData != null) ...[
              _buildKpiMetricsGrid(context, _summaryData!),
              const SizedBox(height: 14.0),
            ],

            // Tabs Header
            _buildTabSwitcher(context),
            const SizedBox(height: 12.0),

            // Content Views
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48.0),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                      SizedBox(height: 14.0),
                      Text(
                        'Analyzing scouting data & computing match comparisons...',
                        style: TextStyle(color: Colors.white70, fontSize: 13.0),
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              ObsidianGlassCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36.0),
                        const SizedBox(height: 10.0),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12.0),
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh_rounded, size: 18.0),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ObsidianUITheme.primaryAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_currentTab == 0)
              _buildMatchesView(context)
            else
              _buildTeamsView(context),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiMetricsGrid(BuildContext context, ValidationSummaryModel summary) {
    final isDark = ObsidianUITheme.isDark(context);
    final cardBg = isDark ? const Color(0x18FFFFFF) : const Color(0x0C000000);
    final borderColor = isDark ? Colors.white10 : Colors.black12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 12.0,
          runSpacing: 10.0,
          children: [
            _buildMetricItem(
              title: 'TOTAL MATCHES',
              value: '${summary.totalMatches}',
              subtitle: 'Scheduled matches',
              color: ObsidianUITheme.primaryAccent,
              width: cardWidth,
              bg: cardBg,
              border: borderColor,
            ),
            _buildMetricItem(
              title: 'FULLY SCOUTED',
              value: '${summary.fullyScoutedMatches}',
              subtitle: 'All teams recorded',
              color: const Color(0xFF4ADE80),
              width: cardWidth,
              bg: cardBg,
              border: borderColor,
            ),
            _buildMetricItem(
              title: 'INCOMPLETE',
              value: '${summary.incompleteMatches}',
              subtitle: 'Missing 1+ teams',
              color: const Color(0xFFFBBF24),
              width: cardWidth,
              bg: cardBg,
              border: borderColor,
            ),
            _buildMetricItem(
              title: 'MATCH ANOMALIES',
              value: '${summary.matchesWithAnomalies}',
              subtitle: 'Score delta >= threshold',
              color: const Color(0xFFF87171),
              width: cardWidth,
              bg: cardBg,
              border: borderColor,
            ),
            _buildMetricItem(
              title: 'TEAM ALERTS',
              value: '${summary.teamsWithAnomalies}',
              subtitle: 'Scouted vs EPA/OPR delta',
              color: const Color(0xFF60A5FA),
              width: constraints.maxWidth,
              bg: cardBg,
              border: borderColor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricItem({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required double width,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w700,
              color: ObsidianUITheme.getTertiaryTextColor(context),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              color: ObsidianUITheme.getTertiaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final unselectedColor = isDark ? Colors.white70 : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentTab = 0),
              borderRadius: BorderRadius.circular(12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                decoration: BoxDecoration(
                  color: _currentTab == 0 ? ObsidianUITheme.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12.0),
                  boxShadow: _currentTab == 0
                      ? [
                          BoxShadow(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.35),
                            blurRadius: 10.0,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Match Validation (${_getFilteredMatches().length})',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.bold,
                    color: _currentTab == 0 ? Colors.white : unselectedColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6.0),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentTab = 1),
              borderRadius: BorderRadius.circular(12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                decoration: BoxDecoration(
                  color: _currentTab == 1 ? ObsidianUITheme.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12.0),
                  boxShadow: _currentTab == 1
                      ? [
                          BoxShadow(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.35),
                            blurRadius: 10.0,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Team EPA / OPR (${_getFilteredTeams().length})',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.bold,
                    color: _currentTab == 1 ? Colors.white : unselectedColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchesView(BuildContext context) {
    final matches = _getFilteredMatches();
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (matches.isEmpty) {
      return ObsidianGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.search_off_rounded, size: 40.0, color: Colors.white38),
                const SizedBox(height: 10.0),
                Text(
                  'No matches matching current filter criteria',
                  style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w600, color: primaryTextColor),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Try clearing the search or changing status filter.',
                  style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: matches.length,
      itemBuilder: (ctx, idx) {
        final match = matches[idx];
        return _buildMatchCard(context, match);
      },
    );
  }

  Widget _buildMatchCard(BuildContext context, MatchValidationModel match) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Match Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.label,
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  Text(
                    match.matchKey,
                    style: TextStyle(fontSize: 11.0, color: secondaryTextColor),
                  ),
                ],
              ),
              _buildMatchStatusBadge(match),
            ],
          ),
          const SizedBox(height: 12.0),

          // Red Alliance Box
          _buildAllianceBox(context, match.redAlliance, isRed: true),
          const SizedBox(height: 8.0),

          // Blue Alliance Box
          _buildAllianceBox(context, match.blueAlliance, isRed: false),
          const SizedBox(height: 12.0),

          // Inspect Button
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _showMatchInspectionModal(match),
              icon: const Icon(Icons.visibility_outlined, size: 16.0),
              label: const Text('Inspect Breakdown', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: ObsidianUITheme.primaryAccent,
                side: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllianceBox(BuildContext context, AllianceValidationModel alliance, {required bool isRed}) {
    final borderColor = isRed ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    final allianceBg = isRed
        ? const Color(0xFFEF4444).withValues(alpha: 0.08)
        : const Color(0xFF3B82F6).withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: allianceBg,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: borderColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Team Chips Row
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: alliance.teams.map((t) {
              final isScouted = alliance.scoutedTeams.contains(t);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: isScouted
                      ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: isScouted
                        ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isScouted ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                      size: 13.0,
                      color: isScouted ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      '$t',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: isScouted ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8.0),

          // Scores Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Scouted: ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ObsidianUITheme.getSecondaryTextColor(context),
                    ),
                  ),
                  Text(
                    '${alliance.scoutedScoreSum}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 12.0),
                  Text(
                    'Official: ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ObsidianUITheme.getSecondaryTextColor(context),
                    ),
                  ),
                  Text(
                    alliance.actualScore != null ? '${alliance.actualScore}' : 'N/A',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (alliance.scoreDiff != null) _buildDeltaBadge(alliance.scoreDiff!, alliance.isAnomaly),
            ],
          ),

          if (alliance.missingTeams.isNotEmpty) ...[
            const SizedBox(height: 4.0),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 13.0, color: Color(0xFFFBBF24)),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Text(
                    'Missing: ${alliance.missingTeams.join(", ")}',
                    style: const TextStyle(fontSize: 11.0, color: Color(0xFFFBBF24), fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeltaBadge(double diff, bool isAnomaly) {
    final sign = diff > 0 ? '+$diff' : '$diff';
    final absDiff = diff.abs();

    Color bg;
    Color fg;
    Color border;

    if (isAnomaly) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.2);
      fg = const Color(0xFFF87171);
      border = const Color(0xFFEF4444).withValues(alpha: 0.5);
    } else if (absDiff > 8.0) {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.18);
      fg = const Color(0xFFFBBF24);
      border = const Color(0xFFF59E0B).withValues(alpha: 0.4);
    } else {
      bg = const Color(0xFF22C55E).withValues(alpha: 0.15);
      fg = const Color(0xFF4ADE80);
      border = const Color(0xFF22C55E).withValues(alpha: 0.35);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        'Δ $sign',
        style: TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildMatchStatusBadge(MatchValidationModel match) {
    if (match.hasAnomaly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🚨', style: TextStyle(fontSize: 11.0)),
            SizedBox(width: 4.0),
            Text(
              'Score Anomaly',
              style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFFF87171)),
            ),
          ],
        ),
      );
    }

    if (match.isFullyScouted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 12.0, color: Color(0xFF4ADE80)),
            SizedBox(width: 4.0),
            Text(
              'Fully Scouted',
              style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80)),
            ),
          ],
        ),
      );
    }

    final isUnscouted = match.redAlliance.scoutedTeams.isEmpty && match.blueAlliance.scoutedTeams.isEmpty;
    if (isUnscouted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          '○ Unscouted',
          style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600, color: Colors.white60),
        ),
      );
    }

    final missingCount = match.redAlliance.missingTeams.length + match.blueAlliance.missingTeams.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 12.0, color: Color(0xFFFBBF24)),
          const SizedBox(width: 4.0),
          Text(
            'Incomplete ($missingCount missing)',
            style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamsView(BuildContext context) {
    final teams = _getFilteredTeams();
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (teams.isEmpty) {
      return ObsidianGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.groups_outlined, size: 40.0, color: Colors.white38),
                const SizedBox(height: 10.0),
                Text(
                  'No teams matching current filter criteria',
                  style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w600, color: primaryTextColor),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Try adjusting the search query or anomaly filters.',
                  style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final useEpa = _summaryData?.useStatboticsEpa ?? true;
    final useOpr = _summaryData?.useTbaOpr ?? true;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teams.length,
      itemBuilder: (ctx, idx) {
        final team = teams[idx];
        return _buildTeamValidationCard(context, team, useEpa: useEpa, useOpr: useOpr);
      },
    );
  }

  Widget _buildTeamValidationCard(
    BuildContext context,
    TeamValidationModel team, {
    required bool useEpa,
    required bool useOpr,
  }) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      margin: const EdgeInsets.only(bottom: 10.0),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => TeamDetailsScreen(
              apiService: widget.apiService,
              team: TeamModel(
                eventKey: _selectedEventKey,
                teamNumber: team.teamNumber,
                teamKey: team.teamKey,
                nickname: team.nickname,
                name: team.nickname,
                epa: team.epa,
                opr: team.opr,
              ),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${team.teamNumber}',
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w800,
                        color: ObsidianUITheme.primaryAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Text(
                    team.nickname,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black12,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  '${team.scoutedMatchCount} matches',
                  style: TextStyle(fontSize: 11.0, color: secondaryTextColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10.0),

          // Scores Row: Scouted Avg, EPA, OPR
          Row(
            children: [
              // Scouted Avg
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCOUTED AVG',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      team.averageScoutedScore != null ? '${team.averageScoutedScore}' : 'N/A',
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w800,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              // EPA
              if (useEpa)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STATBOTICS EPA',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 2.0),
                      Row(
                        children: [
                          Text(
                            team.epa != null ? '${team.epa}' : 'N/A',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: primaryTextColor),
                          ),
                          if (team.epaDiff != null) ...[
                            const SizedBox(width: 4.0),
                            _buildDeltaBadge(team.epaDiff!, team.epaDiff!.abs() >= _threshold),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

              // OPR
              if (useOpr)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TBA OPR',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 2.0),
                      Row(
                        children: [
                          Text(
                            team.opr != null ? '${team.opr}' : 'N/A',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: primaryTextColor),
                          ),
                          if (team.oprDiff != null) ...[
                            const SizedBox(width: 4.0),
                            _buildDeltaBadge(team.oprDiff!, team.oprDiff!.abs() >= _threshold),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Anomaly Reason Banner
          if (team.isAnomaly && team.anomalyReason != null) ...[
            const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('🚨', style: TextStyle(fontSize: 12.0)),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      team.anomalyReason!,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFF87171), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (team.scoutedMatchCount > 0) ...[
            const SizedBox(height: 6.0),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 13.0, color: Color(0xFF4ADE80)),
                SizedBox(width: 4.0),
                Text('In Expected Range', style: TextStyle(fontSize: 11.0, color: Color(0xFF4ADE80), fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchInspectionBottomSheet extends StatelessWidget {
  final MatchValidationModel match;
  final ApiService apiService;

  const _MatchInspectionBottomSheet({
    required this.match,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 1.2),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Modal Handle & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 12.0, 16.0, 8.0),
              child: Column(
                children: [
                  Container(
                    width: 44.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${match.label} Validation Breakdown',
                            style: TextStyle(
                              fontSize: 17.0,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          Text(
                            '${match.matchKey} | Event: ${match.eventKey.toUpperCase()}',
                            style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0),

            // Alliance breakdowns
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildAllianceBreakdownSection(context, match.redAlliance, isRed: true),
                  const SizedBox(height: 16.0),
                  _buildAllianceBreakdownSection(context, match.blueAlliance, isRed: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllianceBreakdownSection(
    BuildContext context,
    AllianceValidationModel alliance, {
    required bool isRed,
  }) {
    final borderColor = isRed ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    final bg = isRed
        ? const Color(0xFFEF4444).withValues(alpha: 0.07)
        : const Color(0xFF3B82F6).withValues(alpha: 0.07);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Alliance Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${alliance.allianceColor.toUpperCase()} ALLIANCE',
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w800,
                  color: borderColor,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Text(
                    'Sum: ${alliance.scoutedScoreSum} pts  |  Official: ${alliance.actualScore ?? "N/A"}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10.0),

          // Team breakdown list
          ...alliance.teams.map((teamNum) {
            final breakdown = alliance.teamBreakdowns.where((b) => b.teamNumber == teamNum).firstOrNull;
            final isScouted = breakdown != null;

            return Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: ObsidianUITheme.isDark(context) ? const Color(0x18FFFFFF) : Colors.white,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: isScouted
                      ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Team $teamNum',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isScouted
                                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              isScouted ? '✓ Scouted' : '⚠️ Missing',
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.bold,
                                color: isScouted ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                          if (breakdown?.hasDiscrepancy == true) ...[
                            const SizedBox(width: 4.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: const Text(
                                'Conflict',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFF87171)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (breakdown?.scouterName != null) ...[
                        const SizedBox(height: 2.0),
                        Text(
                          'Scouter: ${breakdown!.scouterName}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: ObsidianUITheme.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    isScouted ? '${breakdown.scoutedScore} pts' : '0.0 pts',
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w800,
                      color: isScouted ? ObsidianUITheme.primaryAccent : Colors.white38,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
