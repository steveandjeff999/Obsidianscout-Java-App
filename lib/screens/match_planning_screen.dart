import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/graph_models.dart';
import '../models/match_planning_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/file_download_helper.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/match_planning/canvas_toolbar.dart';
import '../widgets/match_planning/strategy_field_canvas.dart';
import '../widgets/match_planning/team_strategy_card.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

class MatchPlanningScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final String? initialMatchKey;

  const MatchPlanningScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.initialMatchKey,
  });

  @override
  State<MatchPlanningScreen> createState() => _MatchPlanningScreenState();
}

class _MatchPlanningScreenState extends State<MatchPlanningScreen> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  bool _isLoading = true;
  String _currentEventKey = '';
  int _currentYear = 2026;
  List<EventModel> _events = [];
  List<MatchModel> _matches = [];
  final Map<int, TeamModel> _teamMap = {};

  MatchModel? _selectedMatch;
  MatchPlanModel _plan = MatchPlanModel();
  final List<MatchPlanModel> _undoStack = [];
  final List<MatchPlanModel> _redoStack = [];

  // Drawing tools state
  String _activeTool = 'pen'; // 'pen' | 'eraser'
  String _currentColor = '#ffffff';
  double _strokeWidth = 6.0;
  String _saveStatus = 'saved'; // 'saving' | 'saved' | 'error' | 'idle'
  bool _isFullscreen = false;

  Timer? _autoSaveTimer;
  Timer? _pollTimer;
  int _lastSyncedTime = 0;
  bool _isSaving = false;

  ui.Image? _fieldImage;

  // Scouting data cache for team statistics
  ScoutingConfigModel? _matchConfig;
  ScoutingConfigModel? _pitConfig;
  ScoutingConfigModel? _qualConfig;
  List<dynamic> _matchEntries = [];
  List<dynamic> _pitEntries = [];
  List<dynamic> _qualEntries = [];
  StatsHistoryModel? _statsHistory;

  StreamSubscription<bool>? _onlineSub;

  @override
  void initState() {
    super.initState();
    _currentYear = widget.apiService.currentSettings?.year ?? DateTime.now().year;
    _initData();
    _onlineSub = widget.apiService.onOnlineStatusChanged.listen((online) {
      if (online) {
        widget.apiService.syncPendingMatchPlans();
        _pollServer();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MatchPlanningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      widget.apiService.syncPendingMatchPlans();
      _startPolling();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _stopPolling();
    _onlineSub?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollServer());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    try {
      final settings = await widget.apiService.fetchSettings();
      _currentYear = settings?.year ?? widget.apiService.currentSettings?.year ?? DateTime.now().year;
      _currentEventKey = settings?.eventKey ?? widget.apiService.currentSettings?.eventKey ?? '';

      // Load events list
      final rawEvents = await widget.apiService.fetchEvents(year: _currentYear);
      final Map<String, EventModel> uniqueEvents = {};
      for (final e in rawEvents) {
        if (e.eventKey.isNotEmpty) {
          uniqueEvents[e.eventKey] = e;
        }
      }
      final events = uniqueEvents.values.toList();

      if (mounted) {
        setState(() {
          _events = events;
          if ((_currentEventKey.isEmpty || !uniqueEvents.containsKey(_currentEventKey)) && events.isNotEmpty) {
            _currentEventKey = events.first.eventKey;
          }
        });
      }

      if (_currentEventKey.isNotEmpty) {
        await _loadEventMatches(_currentEventKey);
      }
    } catch (e) {
      debugPrint('Error initializing match planning screen: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (widget.isVisible) {
        _startPolling();
      }
    }
  }

  int _getCompLevelRank(String compLevel) {
    final lvl = compLevel.trim().toLowerCase();
    switch (lvl) {
      case 'p':
      case 'pr':
      case 'pm':
      case 'practice':
        return 0;
      case 'q':
      case 'qm':
      case 'qual':
      case 'quals':
      case 'qualification':
        return 1;
      case 'ef':
      case 'octofinal':
      case 'octofinals':
        return 2;
      case 'qf':
      case 'quarterfinal':
      case 'quarterfinals':
        return 3;
      case 'sf':
      case 'semifinal':
      case 'semifinals':
        return 4;
      case 'f':
      case 'final':
      case 'finals':
        return 5;
      case 'playoff':
      case 'playoffs':
        return 6;
      default:
        return 1;
    }
  }

  int _compareMatches(MatchModel a, MatchModel b) {
    final rankA = _getCompLevelRank(a.compLevel);
    final rankB = _getCompLevelRank(b.compLevel);
    if (rankA != rankB) return rankA.compareTo(rankB);
    final numA = a.matchNumber ?? 0;
    final numB = b.matchNumber ?? 0;
    return numA.compareTo(numB);
  }

  Future<void> _loadEventMatches(String eventKey) async {
    try {
      final results = await Future.wait([
        widget.apiService.fetchMatches(eventKey),
        widget.apiService.fetchTeams(eventKey),
        widget.apiService.fetchStatsHistory(eventKey),
        widget.apiService.fetchMatchConfig(),
        widget.apiService.fetchPitConfig(),
        widget.apiService.fetchQualConfig(),
        widget.apiService.fetchScoutingEntries(),
        widget.apiService.fetchPitScoutingEntries(),
        widget.apiService.fetchQualScoutingEntries(),
      ]);

      final rawMatches = List<MatchModel>.from(results[0] as List<dynamic>? ?? []);
      final Map<String, MatchModel> uniqueMatches = {};
      for (final m in rawMatches) {
        if (m.matchKey.isNotEmpty) {
          uniqueMatches[m.matchKey] = m;
        }
      }
      final matchesList = uniqueMatches.values.toList();
      matchesList.sort(_compareMatches);

      final teamsList = List<TeamModel>.from(results[1] as List<dynamic>? ?? []);
      final statsHistory = results[2] as StatsHistoryModel?;
      final matchCfg = results[3] as ScoutingConfigModel?;
      final pitCfg = results[4] as ScoutingConfigModel?;
      final qualCfg = results[5] as ScoutingConfigModel?;
      final matchEntries = results[6] as List<dynamic>? ?? [];
      final pitEntries = results[7] as List<dynamic>? ?? [];
      final qualEntries = results[8] as List<dynamic>? ?? [];

      _teamMap.clear();
      for (final t in teamsList) {
        _teamMap[t.teamNumber] = t;
      }

      if (mounted) {
        setState(() {
          _matches = matchesList;
          _statsHistory = statsHistory;
          _matchConfig = matchCfg;
          _pitConfig = pitCfg;
          _qualConfig = qualCfg;
          _matchEntries = matchEntries;
          _pitEntries = pitEntries;
          _qualEntries = qualEntries;
        });
      }

      // Load Season Field Backdrop
      await _loadFieldImage();

      // Auto-select match if specified by initialMatchKey or select first
      if (_matches.isNotEmpty) {
        MatchModel? target;
        if (widget.initialMatchKey != null) {
          target = _matches.firstWhere(
            (m) => m.matchKey == widget.initialMatchKey,
            orElse: () => _matches.first,
          );
        } else if (_selectedMatch != null) {
          target = _matches.firstWhere(
            (m) => m.matchKey == _selectedMatch!.matchKey,
            orElse: () => _matches.first,
          );
        } else {
          target = _matches.first;
        }
        await _selectMatch(target);
      }
    } catch (e) {
      debugPrint('Failed to load event matches: $e');
    }
  }

  Future<void> _loadFieldImage() async {
    // 1. Try ApiService cached / downloaded field image bytes
    try {
      final bytes = await widget.apiService.fetchFieldImageBytes(_currentYear);
      if (bytes != null && bytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() => _fieldImage = frame.image);
          return;
        }
      }
    } catch (_) {}

    // 2. Try bundled Flutter asset paths & cache them locally
    final localAssetCandidates = [
      'assets/images/field-images/$_currentYear/rebuilt.png',
      'assets/images/field-images/$_currentYear/reefscape.png',
      'assets/images/field-images/2026/rebuilt.png',
      'assets/images/field-images/2025/reefscape.png',
    ];

    for (final assetPath in localAssetCandidates) {
      try {
        final byteData = await rootBundle.load(assetPath);
        final bytes = byteData.buffer.asUint8List();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() => _fieldImage = frame.image);
          // Persist bundled asset bytes into cache for offline retrieval
          unawaited(widget.apiService.cacheFieldImageBytes(_currentYear, bytes));
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _fieldImage = null);
    }
  }

  Future<void> _selectMatch(MatchModel match) async {
    _autoSaveTimer?.cancel();
    setState(() {
      _selectedMatch = match;
      _undoStack.clear();
      _redoStack.clear();
      _plan = MatchPlanModel();
      _saveStatus = 'saved';
    });

    try {
      final saved = await widget.apiService.fetchMatchPlan(_currentEventKey, match.matchKey);
      if (saved != null && mounted) {
        setState(() {
          _plan = saved;
          _lastSyncedTime = saved.updatedAt;
        });
      }
    } catch (e) {
      debugPrint('Failed to load saved match plan: $e');
    }
  }

  void _scheduleAutoSave() {
    if (_selectedMatch == null || _currentEventKey.isEmpty) return;
    setState(() => _saveStatus = 'saving');

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _selectedMatch == null) return;
      _isSaving = true;
      try {
        final planJson = _plan.toJsonString();
        final ts = await widget.apiService.saveMatchPlan(
          _currentEventKey,
          _selectedMatch!.matchKey,
          planJson,
        );
        if (mounted) {
          setState(() {
            _saveStatus = ts != null ? 'saved' : 'error';
            if (ts != null) _lastSyncedTime = ts;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _saveStatus = 'error');
      } finally {
        _isSaving = false;
      }
    });
  }

  Future<void> _pollServer() async {
    if (!widget.isVisible || _selectedMatch == null || _currentEventKey.isEmpty || _isSaving) {
      return;
    }

    try {
      // 1. Check for remote match plan updates
      final remotePlan = await widget.apiService.fetchMatchPlan(
        _currentEventKey,
        _selectedMatch!.matchKey,
      );
      if (remotePlan != null && remotePlan.updatedAt > _lastSyncedTime && mounted) {
        setState(() {
          _plan = remotePlan;
          _lastSyncedTime = remotePlan.updatedAt;
          _saveStatus = 'saved';
        });
      }

      // 2. Poll for fresh scouting entries
      final entries = await widget.apiService.fetchScoutingEntries();
      if (entries.length != _matchEntries.length && mounted) {
        setState(() {
          _matchEntries = entries;
        });
      }
    } catch (_) {}
  }

  void _pushUndoState() {
    _undoStack.add(_plan.copyWith());
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _handleUndo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(_plan.copyWith());
      final prev = _undoStack.removeLast();
      setState(() => _plan = prev);
      _scheduleAutoSave();
    }
  }

  void _handleRedo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(_plan.copyWith());
      final next = _redoStack.removeLast();
      setState(() => _plan = next);
      _scheduleAutoSave();
    }
  }

  void _handleClearCanvas() {
    if (_plan.annotations.isEmpty) return;
    _pushUndoState();
    setState(() {
      _plan = _plan.copyWith(annotations: []);
    });
    _scheduleAutoSave();
    ObsidianFeedback.showSuccess(context, message: 'Canvas cleared. Tap Undo to restore.');
  }

  void _handleStrokeCompleted(StrokeAnnotation stroke) {
    _pushUndoState();
    setState(() {
      _plan.annotations.add(stroke);
    });
    _scheduleAutoSave();
  }

  void _handleMarkerPositionChanged(String stationId, TeamMarkerPosition pos) {
    setState(() {
      _plan.teamMarkerPositions[stationId] = pos;
    });
  }

  void _handleMarkerDragEnd() {
    _scheduleAutoSave();
  }

  Future<void> _exportPlanImage() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final matchLabel = _selectedMatch?.label ?? 'match-plan';
      final filename = 'obsidianscout-plan-${matchLabel.replaceAll(' ', '_').toLowerCase()}.png';

      final result = await downloadOrSaveBytes(
        filename: filename,
        bytes: pngBytes,
        mimeType: 'image/png',
      );

      if (!mounted) return;
      if (result.success) {
        ObsidianFeedback.showSuccess(context, message: result.message ?? 'Plan exported successfully.');
      } else {
        ObsidianFeedback.showError(context, message: result.message ?? 'Failed to export image.');
      }
    } catch (e) {
      if (!mounted) return;
      ObsidianFeedback.showError(context, message: 'Export failed: $e');
    }
  }

  int _parseTeamNumber(dynamic raw) {
    if (raw == null) return 0;
    final str = raw.toString().replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
    return int.tryParse(str) ?? 0;
  }

  int? _extractTeamNumberFromEntry(dynamic e) {
    if (e == null) return null;
    if (e is Map) {
      final raw = e['targetTeamNumber'] ??
          e['teamNumber'] ??
          e['team_number'] ??
          e['target_team_number'] ??
          (e['data'] is Map ? e['data']['targetTeamNumber'] ?? e['data']['teamNumber'] : null);
      if (raw != null) return _parseTeamNumber(raw);
    } else {
      try {
        final raw = (e as dynamic).targetTeamNumber ?? (e as dynamic).teamNumber;
        if (raw != null) return _parseTeamNumber(raw);
      } catch (_) {}
    }
    return null;
  }

  List<dynamic> _filterEntriesForTeam(List<dynamic> list, int teamNumber) {
    return list.where((e) {
      final num = _extractTeamNumberFromEntry(e);
      return num == teamNumber;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isFullscreen) {
      return _buildFullscreenWorkspace(context);
    }

    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 20.0 : 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Controls Card
              ObsidianGlassCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('nav.match_planning', 'Match Planning'),
                            style: TextStyle(
                              fontSize: isDesktop ? 22 : 18,
                              fontWeight: FontWeight.w900,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr(
                              'subtitle.match_planning',
                              'Strategize matches with interactive field drawings and comprehensive alliance data',
                            ),
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Event Filter Dropdown
                    Builder(
                      builder: (context) {
                        final seenEventKeys = <String>{};
                        final eventItems = <DropdownMenuItem<String>>[];
                        for (final e in _events) {
                          if (e.eventKey.isNotEmpty && seenEventKeys.add(e.eventKey)) {
                            eventItems.add(
                              DropdownMenuItem<String>(
                                value: e.eventKey,
                                child: Text(
                                  e.name.isNotEmpty ? e.name : e.eventKey,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            );
                          }
                        }

                        final String? safeEventValue = seenEventKeys.contains(_currentEventKey)
                            ? _currentEventKey
                            : (eventItems.isNotEmpty ? eventItems.first.value : null);

                        return SizedBox(
                          width: isDesktop ? 200 : 130,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: safeEventValue,
                            decoration: InputDecoration(
                              labelText: context.tr('events.title', 'Event'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            items: eventItems,
                            onChanged: (val) {
                              if (val != null && val != _currentEventKey) {
                                setState(() => _currentEventKey = val);
                                _loadEventMatches(val);
                              }
                            },
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    // Match Selector Dropdown
                    Builder(
                      builder: (context) {
                        final seenMatchKeys = <String>{};
                        final matchItems = <DropdownMenuItem<String>>[];
                        for (final m in _matches) {
                          if (m.matchKey.isNotEmpty && seenMatchKeys.add(m.matchKey)) {
                            final label = m.label.isNotEmpty ? m.label : (m.matchNumber != null ? 'Match ${m.matchNumber}' : m.matchKey);
                            matchItems.add(
                              DropdownMenuItem<String>(
                                value: m.matchKey,
                                child: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            );
                          }
                        }

                        final currentSelectedKey = _selectedMatch?.matchKey;
                        final String? safeMatchValue = (currentSelectedKey != null && seenMatchKeys.contains(currentSelectedKey))
                            ? currentSelectedKey
                            : (matchItems.isNotEmpty ? matchItems.first.value : null);

                        return SizedBox(
                          width: isDesktop ? 180 : 130,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: safeMatchValue,
                            decoration: InputDecoration(
                              labelText: context.tr('nav.matches', 'Select Match'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            items: matchItems,
                            onChanged: (val) {
                              if (val != null && _matches.isNotEmpty) {
                                final match = _matches.firstWhere(
                                  (m) => m.matchKey == val,
                                  orElse: () => _matches.first,
                                );
                                _selectMatch(match);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Strategy Workspace Card (Toolbar + Driver Stations + Canvas)
              ObsidianGlassCard(
                child: Column(
                  children: [
                    // Canvas Toolbar
                    Center(
                      child: CanvasToolbar(
                        activeTool: _activeTool,
                        currentColor: _currentColor,
                        strokeWidth: _strokeWidth,
                        canUndo: _undoStack.isNotEmpty,
                        canRedo: _redoStack.isNotEmpty,
                        isFullscreen: _isFullscreen,
                        saveStatus: _saveStatus,
                        onToolChanged: (tool) => setState(() => _activeTool = tool),
                        onColorChanged: (color) => setState(() => _currentColor = color),
                        onStrokeWidthChanged: (val) => setState(() => _strokeWidth = val),
                        onUndo: _handleUndo,
                        onRedo: _handleRedo,
                        onClear: _handleClearCanvas,
                        onToggleFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
                        onExport: _exportPlanImage,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Workspace Layout: Left Driver Station (Blue) - Canvas - Right Driver Station (Red)
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Blue Driver Station (Left)
                          SizedBox(
                            width: 140,
                            child: _buildDriverStationColumn('Blue Alliance', 'blue', _selectedMatch?.blueTeams ?? []),
                          ),

                          const SizedBox(width: 12),

                          // Strategy Canvas (Center)
                          Expanded(
                            child: StrategyFieldCanvas(
                              repaintBoundaryKey: _repaintBoundaryKey,
                              plan: _plan,
                              activeTool: _activeTool,
                              currentColor: _currentColor,
                              strokeWidth: _strokeWidth,
                              fieldImage: _fieldImage,
                              currentMatch: _selectedMatch,
                              teamMap: _teamMap,
                              onStrokeCompleted: _handleStrokeCompleted,
                              onMarkerPositionChanged: _handleMarkerPositionChanged,
                              onMarkerDragEnd: _handleMarkerDragEnd,
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Red Driver Station (Right)
                          SizedBox(
                            width: 140,
                            child: _buildDriverStationColumn('Red Alliance', 'red', _selectedMatch?.redTeams ?? []),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          // Canvas on mobile
                          StrategyFieldCanvas(
                            repaintBoundaryKey: _repaintBoundaryKey,
                            plan: _plan,
                            activeTool: _activeTool,
                            currentColor: _currentColor,
                            strokeWidth: _strokeWidth,
                            fieldImage: _fieldImage,
                            currentMatch: _selectedMatch,
                            teamMap: _teamMap,
                            onStrokeCompleted: _handleStrokeCompleted,
                            onMarkerPositionChanged: _handleMarkerPositionChanged,
                            onMarkerDragEnd: _handleMarkerDragEnd,
                          ),

                          const SizedBox(height: 12),

                          // Driver stations side-by-side on mobile
                          Row(
                            children: [
                              Expanded(
                                child: _buildDriverStationColumn('Blue Alliance', 'blue', _selectedMatch?.blueTeams ?? []),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildDriverStationColumn('Red Alliance', 'red', _selectedMatch?.redTeams ?? []),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Alliance & Team Performance Stats Section
              if (_selectedMatch != null) ...[
                Text(
                  'Alliance & Team Performance Stats',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Comprehensive stats, pit specs, and qualitative scouter notes for each team in this match',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),

                const SizedBox(height: 14),

                // Blue Alliance Cards Row
                _buildAllianceTeamCardsSection('Blue Alliance', 'blue', _selectedMatch!.blueTeams),

                const SizedBox(height: 20),

                // Red Alliance Cards Row
                _buildAllianceTeamCardsSection('Red Alliance', 'red', _selectedMatch!.redTeams),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverStationColumn(String title, String alliance, List<String> teamKeys) {
    final isBlue = alliance.toLowerCase() == 'blue';
    final headerColor = isBlue ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final borderColor = isBlue ? const Color(0x4D3B82F6) : const Color(0x4DEF4444);
    final bg = isBlue ? const Color(0x0A3B82F6) : const Color(0x0AEF4444);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: headerColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          ...List.generate(3, (i) {
            final stationLabel = '${alliance.toUpperCase()[0]}${i + 1}';
            final teamKey = i < teamKeys.length ? teamKeys[i] : null;
            final teamNum = _parseTeamNumber(teamKey);
            final teamObj = teamNum > 0 ? _teamMap[teamNum] : null;
            final nick = teamObj?.nickname ?? teamObj?.name ?? '';

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: headerColor.withValues(alpha: 0.35), width: 1.0),
              ),
              child: Column(
                children: [
                  Text(
                    'Station $stationLabel',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: headerColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    teamNum > 0 ? '#$teamNum' : '—',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (nick.isNotEmpty)
                    Text(
                      nick,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildAllianceTeamCardsSection(String title, String alliance, List<String> teamKeys) {
    final isBlue = alliance.toLowerCase() == 'blue';
    final headerColor = isBlue ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final settings = widget.apiService.currentSettings;
    final isFtc = widget.apiService.currentProgram == 'FTC';

    final useStatbotics = !isFtc && (settings?.useStatboticsEpa ?? false);
    final useMatch13 = !isFtc && (settings?.useMatch13Exp ?? false);
    final useOpr = settings?.useTbaOpr ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_rounded, size: 18, color: headerColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: headerColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 900;
            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(teamKeys.length, (i) {
                  final teamNum = _parseTeamNumber(teamKeys[i]);
                  final teamObj = teamNum > 0 ? _teamMap[teamNum] : null;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < teamKeys.length - 1 ? 12.0 : 0.0),
                      child: TeamStrategyCard(
                        teamNumber: teamNum,
                        alliance: alliance,
                        stationNumber: i + 1,
                        team: teamObj,
                        matchEntries: _filterEntriesForTeam(_matchEntries, teamNum),
                        pitEntries: _filterEntriesForTeam(_pitEntries, teamNum),
                        qualEntries: _filterEntriesForTeam(_qualEntries, teamNum),
                        matchConfig: _matchConfig,
                        pitConfig: _pitConfig,
                        qualConfig: _qualConfig,
                        allMatches: _matches,
                        statsHistory: _statsHistory,
                        useStatboticsEpa: useStatbotics,
                        useMatch13Exp: useMatch13,
                        useTbaOpr: useOpr,
                        isFtc: isFtc,
                      ),
                    ),
                  );
                }),
              );
            } else {
              return Column(
                children: List.generate(teamKeys.length, (i) {
                  final teamNum = _parseTeamNumber(teamKeys[i]);
                  final teamObj = teamNum > 0 ? _teamMap[teamNum] : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TeamStrategyCard(
                      teamNumber: teamNum,
                      alliance: alliance,
                      stationNumber: i + 1,
                      team: teamObj,
                      matchEntries: _filterEntriesForTeam(_matchEntries, teamNum),
                      pitEntries: _filterEntriesForTeam(_pitEntries, teamNum),
                      qualEntries: _filterEntriesForTeam(_qualEntries, teamNum),
                      matchConfig: _matchConfig,
                      pitConfig: _pitConfig,
                      qualConfig: _qualConfig,
                      allMatches: _matches,
                      statsHistory: _statsHistory,
                      useStatboticsEpa: useStatbotics,
                      useMatch13Exp: useMatch13,
                      useTbaOpr: useOpr,
                      isFtc: isFtc,
                    ),
                  );
                }),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildFullscreenWorkspace(BuildContext context) {
    final matchLabel = _selectedMatch?.label ?? (_selectedMatch?.matchNumber != null ? 'Match ${_selectedMatch!.matchNumber}' : 'Match Planning');
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() => _isFullscreen = false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar in Fullscreen
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xE60F172A),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ),
                child: Row(
                  children: [
                    // Back / Exit Button
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                      tooltip: 'Exit Fullscreen',
                      onPressed: () => setState(() => _isFullscreen = false),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      matchLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Canvas Toolbar (Centered)
                    Expanded(
                      child: Center(
                        child: CanvasToolbar(
                          activeTool: _activeTool,
                          currentColor: _currentColor,
                          strokeWidth: _strokeWidth,
                          canUndo: _undoStack.isNotEmpty,
                          canRedo: _redoStack.isNotEmpty,
                          isFullscreen: _isFullscreen,
                          saveStatus: _saveStatus,
                          onToolChanged: (tool) => setState(() => _activeTool = tool),
                          onColorChanged: (color) => setState(() => _currentColor = color),
                          onStrokeWidthChanged: (val) => setState(() => _strokeWidth = val),
                          onUndo: _handleUndo,
                          onRedo: _handleRedo,
                          onClear: _handleClearCanvas,
                          onToggleFullscreen: () => setState(() => _isFullscreen = false),
                          onExport: _exportPlanImage,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Exit Fullscreen Action Button
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _isFullscreen = false),
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 18),
                      label: const Text('Exit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Fullscreen Workspace Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Blue Stations
                            SizedBox(
                              width: 140,
                              child: _buildDriverStationColumn('Blue Alliance', 'blue', _selectedMatch?.blueTeams ?? []),
                            ),
                            const SizedBox(width: 12),
                            // Strategy Canvas in Center
                            Expanded(
                              child: Center(
                                child: StrategyFieldCanvas(
                                  repaintBoundaryKey: _repaintBoundaryKey,
                                  plan: _plan,
                                  activeTool: _activeTool,
                                  currentColor: _currentColor,
                                  strokeWidth: _strokeWidth,
                                  fieldImage: _fieldImage,
                                  currentMatch: _selectedMatch,
                                  teamMap: _teamMap,
                                  onStrokeCompleted: _handleStrokeCompleted,
                                  onMarkerPositionChanged: _handleMarkerPositionChanged,
                                  onMarkerDragEnd: _handleMarkerDragEnd,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Red Stations
                            SizedBox(
                              width: 140,
                              child: _buildDriverStationColumn('Red Alliance', 'red', _selectedMatch?.redTeams ?? []),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            // Canvas expanded
                            Expanded(
                              child: Center(
                                child: StrategyFieldCanvas(
                                  repaintBoundaryKey: _repaintBoundaryKey,
                                  plan: _plan,
                                  activeTool: _activeTool,
                                  currentColor: _currentColor,
                                  strokeWidth: _strokeWidth,
                                  fieldImage: _fieldImage,
                                  currentMatch: _selectedMatch,
                                  teamMap: _teamMap,
                                  onStrokeCompleted: _handleStrokeCompleted,
                                  onMarkerPositionChanged: _handleMarkerPositionChanged,
                                  onMarkerDragEnd: _handleMarkerDragEnd,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Driver stations row on mobile
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDriverStationColumn('Blue Alliance', 'blue', _selectedMatch?.blueTeams ?? []),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildDriverStationColumn('Red Alliance', 'red', _selectedMatch?.redTeams ?? []),
                                ),
                              ],
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
}
