import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../models/gamepad_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../services/gamepad_service.dart';
import '../services/scout_history_service.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/dynamic_field_widget.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/sync_status_banner.dart';
import '../models/assignment_models.dart';
import '../services/assignment_advance_service.dart';
import '../widgets/next_assignment_chip.dart';
import '../widgets/match_prediction_card.dart';
import '../services/scouting_draft_service.dart';
import '../widgets/draft_restore_banner.dart';
import '../widgets/submit_review_sheet.dart';

class MatchScoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final String? initialMatchKey;
  final int? initialMatchNumber;
  final int? initialTargetTeamNumber;
  final String? sourceAssignmentId;

  const MatchScoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.initialMatchKey,
    this.initialMatchNumber,
    this.initialTargetTeamNumber,
    this.sourceAssignmentId,
  });

  @override
  State<MatchScoutScreen> createState() => _MatchScoutScreenState();
}

class _MatchScoutScreenState extends State<MatchScoutScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  ScoutingConfigModel? _config;
  List<TeamModel> _teams = [];
  List<MatchModel> _matches = [];
  String? _eventKey;

  TeamModel? _selectedTeam;
  MatchModel? _selectedMatch;

  String _activeTab = 'auto'; // 'auto', 'teleop', 'endgame', 'postmatch'

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isReviewing = false;
  final Map<String, dynamic> _formData = {};
  StreamSubscription<GamepadActionEvent>? _gamepadSubscription;

  // Assignment auto-advance: after a save, jump to the scout's next assignment.
  List<ScoutingAssignment> _assignments = [];
  NextAssignment? _nextAssignment;
  bool _advanced = false;
  bool _autoAdvance = true;
  bool _initialAdvanceDone = false;
  final Set<String> _doneIds = {};

  // Form draft persistence & accidental back protection
  Timer? _draftSaveTimer;
  ScoutingDraft? _availableDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPageData();
    _gamepadSubscription = GamepadService.instance.actionStream.listen(_handleGamepadAction);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftSaveTimer?.cancel();
    _gamepadSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isFormDirty) {
        _saveDraftImmediate();
      }
    }
  }

  bool get _isFormDirty {
    if (_isSubmitting) return false;
    return ScoutingDraftService.hasMeaningfulData(_formData, _config);
  }

  void _onFieldChanged(String fieldId, dynamic val) {
    setState(() => _formData[fieldId] = val);
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 800), _saveDraftImmediate);
  }

  Future<void> _saveDraftImmediate() async {
    _draftSaveTimer?.cancel();
    if (!mounted) return;
    await ScoutingDraftService.saveDraft(
      formType: 'match',
      data: _formData,
      teamNumber: _selectedTeam?.teamNumber,
      matchKey: _selectedMatch?.matchKey,
      matchNumber: _selectedMatch?.matchNumber,
      eventKey: _eventKey,
      config: _config,
    );
  }

  void _restoreDraft(ScoutingDraft draft) {
    setState(() {
      if (draft.teamNumber != null) {
        final team = _teams.where((t) => t.teamNumber == draft.teamNumber).firstOrNull ??
            TeamModel(eventKey: _eventKey ?? '', teamKey: 'frc${draft.teamNumber}', teamNumber: draft.teamNumber!);
        _selectedTeam = team;
      }
      if (draft.matchKey != null && draft.matchKey!.isNotEmpty) {
        final match = _matches.where((m) => m.matchKey.toLowerCase() == draft.matchKey!.toLowerCase()).firstOrNull;
        if (match != null) _selectedMatch = match;
      } else if (draft.matchNumber != null) {
        final match = _matches.where((m) => m.matchNumber == draft.matchNumber).firstOrNull;
        if (match != null) _selectedMatch = match;
      }
      for (final entry in draft.data.entries) {
        _formData[entry.key] = entry.value;
      }
      _availableDraft = null;
    });
    ObsidianFeedback.showSuccess(
      context,
      title: 'Draft Restored',
      message: 'Restored scouting draft for ${draft.contextDescription()}',
    );
  }

  void _discardDraft() async {
    await ScoutingDraftService.clearDraft('match');
    if (mounted) {
      setState(() {
        _availableDraft = null;
      });
      ObsidianFeedback.showWarning(context, title: 'Draft Discarded', message: 'In-progress draft was discarded.');
    }
  }

  Future<bool> _handlePopAttempt() async {
    if (!_isFormDirty) return true;

    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 28.0),
            const SizedBox(width: 10.0),
            Expanded(
              child: Text(
                'Discard Scouting Progress?',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
            ),
          ],
        ),
        content: Text(
          'You have unsaved scouting data for ${_selectedMatch?.displayLabel ?? 'this match'}${_selectedTeam != null ? ' (Team ${_selectedTeam!.teamNumber})' : ''}.\n\nWould you like to keep scouting, save your progress as a draft, or discard?',
          style: TextStyle(fontSize: 14.0, color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: Text('Keep Scouting', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Discard', style: TextStyle(color: ObsidianUITheme.errorRed)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () => Navigator.of(ctx).pop('save_draft'),
            child: const Text('Save Draft & Exit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == 'save_draft') {
      await _saveDraftImmediate();
      return true;
    } else if (result == 'discard') {
      await ScoutingDraftService.clearDraft('match');
      _resetForm();
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant MatchScoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasNewInitialParams = widget.initialMatchKey != oldWidget.initialMatchKey ||
        widget.initialMatchNumber != oldWidget.initialMatchNumber ||
        widget.initialTargetTeamNumber != oldWidget.initialTargetTeamNumber ||
        widget.sourceAssignmentId != oldWidget.sourceAssignmentId;

    if (hasNewInitialParams) {
      _applyInitialSelections(force: true);
    }

    if (widget.isVisible && !oldWidget.isVisible) {
      _loadPageData();
    }
  }

  void _loadPageData() async {
    // 1. Instant Cache Hydration (0ms! Zero spinner when data exists locally)
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    final cachedConfig = await widget.apiService.getCachedMatchConfig();
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);
    final cachedMatches = await widget.apiService.getCachedMatches(cachedEventKey);

    if (mounted && (cachedConfig != null || cachedTeams.isNotEmpty || cachedMatches.isNotEmpty)) {
      setState(() {
        _eventKey = cachedEventKey;
        _config = cachedConfig;
        _teams = cachedTeams;
        _matches = cachedMatches;
        _isLoading = false;
        if (cachedConfig != null && _formData.isEmpty) {
          _resetFormData(cachedConfig);
        }
        _applyInitialSelections();
      });
      _initAssignments();
    }

    final savedDraft = await ScoutingDraftService.loadDraft('match');
    if (mounted && savedDraft != null) {
      setState(() {
        _availableDraft = savedDraft;
      });
    }

    // If offline, stop immediately - don't wait for any network timeouts
    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation (fetch fresh updates without blocking UI)
    try {
      final eventKeyFuture = widget.apiService.fetchCurrentEventKey();
      final configFuture = widget.apiService.fetchMatchConfig();

      final eventKey = await eventKeyFuture;
      final config = await configFuture;

      final results = await Future.wait([
        widget.apiService.fetchTeams(eventKey),
        widget.apiService.fetchMatches(eventKey),
      ]);

      final teams = results[0] as List<TeamModel>;
      final matches = results[1] as List<MatchModel>;

      if (!mounted) return;

      setState(() {
        _eventKey = eventKey;
        _config = config ?? _config;
        if (teams.isNotEmpty) _teams = teams;
        if (matches.isNotEmpty) _matches = matches;
        if (_selectedTeam != null && !_teams.any((t) => t.teamNumber == _selectedTeam!.teamNumber)) {
          _selectedTeam = null;
        }
        if (_selectedMatch != null && !_matches.any((m) => m.matchKey == _selectedMatch!.matchKey)) {
          _selectedMatch = null;
        }
        final matchHasRoster = _selectedMatch != null && (_selectedMatch!.redTeams.isNotEmpty || _selectedMatch!.blueTeams.isNotEmpty);
        if (_selectedTeam != null && matchHasRoster && !_selectedMatch!.hasTeam(_selectedTeam!.teamNumber)) {
          _selectedMatch = null;
        }
        _isLoading = false;

        if (_config != null && _formData.isEmpty) {
          _resetFormData(_config!);
        }
        _applyInitialSelections();
      });
      _initAssignments();
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _initAssignments() async {
    try {
      final enabled = await AssignmentAdvanceService.isEnabled();
      final list = await widget.apiService.getCachedMyAssignments(_eventKey);
      if (!mounted) return;
      final next = AssignmentAdvanceService.next(
        list,
        type: 'MATCH',
        matches: _matches,
        afterMatchKey: _selectedMatch?.matchKey,
      );
      setState(() {
        _assignments = list;
        _autoAdvance = enabled;
        _nextAssignment = next;
        _advanced = false;
        final hasInitial = widget.initialMatchKey != null || widget.initialMatchNumber != null || widget.initialTargetTeamNumber != null;
        if (!_initialAdvanceDone && enabled && !hasInitial && _selectedMatch == null && _selectedTeam == null && next?.assignment != null) {
          _applyAssignment(next!.assignment!);
          _advanced = true;
        }
        if (_matches.isNotEmpty) _initialAdvanceDone = true;
      });
    } catch (_) {}
  }

  /// Selects an assignment's match and team. Call inside setState.
  void _applyAssignment(ScoutingAssignment a) {
    final match = _matches.where((m) => a.isMatchFor(m)).firstOrNull;
    if (match != null) _selectedMatch = match;
    final teamNumber = a.targetTeamNumber;
    if (teamNumber != null) {
      _selectedTeam = _teams.where((t) => t.teamNumber == teamNumber).firstOrNull ??
          TeamModel(eventKey: _eventKey ?? '', teamKey: 'frc$teamNumber', teamNumber: teamNumber);
    }
  }

  /// The assignment matching the current team + match, so the right one is marked complete
  /// even when the scout picked something other than what they were sent to.
  String? _assignmentIdForSelection() {
    final match = _selectedMatch;
    final team = _selectedTeam;
    if (match == null || team == null) return null;
    final hit = _assignments
        .where((a) => a.assignmentType.toUpperCase() == 'MATCH' && a.targetTeamNumber == team.teamNumber && a.isMatchFor(match))
        .firstOrNull;
    if (hit != null) return hit.id;
    final sourceId = widget.sourceAssignmentId;
    final sentHere = (widget.initialMatchKey ?? '').toLowerCase() == match.matchKey.toLowerCase() &&
        widget.initialTargetTeamNumber == team.teamNumber;
    return (sourceId != null && sourceId.isNotEmpty && sentHere) ? sourceId : null;
  }

  Future<void> _advanceAfterSave(Map<String, dynamic> data, String? completedId) async {
    if (completedId != null) _doneIds.add(completedId);
    try {
      final list = await widget.apiService.getCachedMyAssignments(_eventKey);
      if (!mounted) return;
      final source = list.isNotEmpty ? list : _assignments;
      final next = AssignmentAdvanceService.next(
        source,
        type: 'MATCH',
        matches: _matches,
        afterMatchKey: data['matchKey']?.toString(),
        afterMatchNumber: data['matchNumber'] is int ? data['matchNumber'] as int : null,
        justCompletedIds: {if (completedId != null) completedId},
      );
      setState(() {
        _assignments = source;
        _nextAssignment = next;
        _advanced = false;
        if (_autoAdvance && next?.assignment != null) {
          _applyAssignment(next!.assignment!);
          _advanced = true;
        }
      });
    } catch (_) {}
  }

  Future<void> _setAutoAdvance(bool enabled) async {
    await AssignmentAdvanceService.setEnabled(enabled);
    if (mounted) setState(() => _autoAdvance = enabled);
  }

  /// Match predictions game: the scout's red / blue call for the selected match (nothing while it's off).
  Widget _buildPredictionCard({EdgeInsetsGeometry? margin}) {
    final match = _selectedMatch;
    final eventKey = (_eventKey != null && _eventKey!.isNotEmpty) ? _eventKey! : (match?.eventKey ?? '');
    if (match == null || eventKey.isEmpty || !widget.apiService.matchPredictionsEnabled) {
      return const SizedBox.shrink();
    }
    return MatchPredictionCard(
      key: ValueKey('prediction_${match.matchKey}'),
      apiService: widget.apiService,
      eventKey: eventKey,
      match: match,
      margin: margin,
    );
  }

  Widget _buildNextAssignmentChip({EdgeInsetsGeometry? margin}) {
    final currentId = _assignmentIdForSelection();
    final current = currentId == null || _doneIds.contains(currentId)
        ? null
        : _assignments.where((a) => a.id == currentId && AssignmentAdvanceService.isOpen(a)).firstOrNull;
    final ahead = AssignmentAdvanceService.next(
      _assignments,
      type: 'MATCH',
      matches: _matches,
      afterMatchKey: _selectedMatch?.matchKey,
      afterMatchNumber: _selectedMatch?.matchNumber,
      justCompletedIds: {..._doneIds, if (current != null) current.id},
      noWrap: true,
    );
    // Nothing after the selection: point at the earliest open one instead (or report none left).
    final fallback = ahead?.assignment == null
        ? AssignmentAdvanceService.next(_assignments, type: 'MATCH', matches: _matches, justCompletedIds: {..._doneIds, if (current != null) current.id})
        : null;
    final upNext = current != null ? ahead?.assignment : (ahead?.assignment ?? fallback?.assignment);
    final earlierOpen = current != null && ahead?.assignment == null ? (ahead?.remaining ?? 0) : 0;
    return NextAssignmentChip(
      hasAssignments: _assignments.any((a) => a.assignmentType.toUpperCase() == 'MATCH'),
      current: current,
      upNext: upNext,
      earlierOpen: earlierOpen,
      skippedPast: _advanced ? (_nextAssignment?.skippedPast ?? 0) : 0,
      autoAdvance: _autoAdvance,
      onToggleAutoAdvance: _setAutoAdvance,
      // Change: clear the pre-filled selection so the scout picks manually.
      onChange: () => setState(() {
        _selectedMatch = null;
        _selectedTeam = null;
        _advanced = false;
      }),
      onGoTo: (a) => setState(() {
        _applyAssignment(a);
        _advanced = false;
      }),
      margin: margin ?? const EdgeInsets.fromLTRB(16, 4, 16, 4),
    );
  }

  void _applyInitialSelections({bool force = false}) {
    if ((force || _selectedMatch == null) && _matches.isNotEmpty) {
      if (widget.initialMatchKey != null && widget.initialMatchKey!.isNotEmpty) {
        final match = _matches.where((m) => m.matchKey.toLowerCase() == widget.initialMatchKey!.toLowerCase()).firstOrNull;
        if (match != null) _selectedMatch = match;
      } else if (widget.initialMatchNumber != null) {
        final match = _matches.where((m) => m.matchNumber == widget.initialMatchNumber).firstOrNull;
        if (match != null) _selectedMatch = match;
      }
    }
    if ((force || _selectedTeam == null) && _teams.isNotEmpty) {
      if (widget.initialTargetTeamNumber != null) {
        final team = _teams.where((t) => t.teamNumber == widget.initialTargetTeamNumber).firstOrNull;
        if (team != null) _selectedTeam = team;
      }
    }
  }

  List<MatchModel> get _availableMatches {
    if (_selectedTeam == null || (_selectedTeam != null && _selectedMatch != null)) {
      return _matches;
    }
    final anyMatchHasTeams = _matches.any((m) => m.redTeams.isNotEmpty || m.blueTeams.isNotEmpty);
    final byTeam = _matches.where((m) => m.hasTeam(_selectedTeam!.teamNumber)).toList();
    if (byTeam.isNotEmpty || anyMatchHasTeams) {
      return byTeam;
    }
    return _matches;
  }

  List<TeamModel> get _availableTeams {
    if (_selectedMatch == null || (_selectedTeam != null && _selectedMatch != null)) {
      return _teams;
    }
    final teamNums = _selectedMatch!.getTeamNumbers();
    if (teamNums.isEmpty) return _teams;

    final filtered = _teams.where((t) => teamNums.contains(t.teamNumber)).toList();
    final existingNums = filtered.map((t) => t.teamNumber).toSet();
    for (final num in teamNums) {
      if (!existingNums.contains(num)) {
        filtered.add(TeamModel(
          eventKey: _eventKey ?? '',
          teamKey: 'frc$num',
          teamNumber: num,
        ));
      }
    }
    filtered.sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
    return filtered;
  }

  void _onTeamSelected(TeamModel? team) {
    setState(() {
      final wasBothSelected = _selectedTeam != null && _selectedMatch != null;
      _selectedTeam = team;
      if (team == null) return;
      if (wasBothSelected) {
        _selectedMatch = null;
      } else if (_selectedMatch != null) {
        final matchHasRoster = _selectedMatch!.redTeams.isNotEmpty || _selectedMatch!.blueTeams.isNotEmpty;
        if (matchHasRoster && !_selectedMatch!.hasTeam(team.teamNumber)) {
          _selectedMatch = null;
        }
      }
    });
    _scheduleDraftSave();
  }

  void _onMatchSelected(MatchModel? match) {
    setState(() {
      final wasBothSelected = _selectedTeam != null && _selectedMatch != null;
      _selectedMatch = match;
      if (match == null) return;
      if (wasBothSelected) {
        _selectedTeam = null;
      } else if (_selectedTeam != null) {
        final matchHasRoster = match.redTeams.isNotEmpty || match.blueTeams.isNotEmpty;
        if (matchHasRoster && !match.hasTeam(_selectedTeam!.teamNumber)) {
          _selectedTeam = null;
        }
      }
    });
    _scheduleDraftSave();
  }

  String _getFieldPhase(ScoutingFieldModel field) {
    if (field.phase != null && field.phase!.isNotEmpty) {
      final p = field.phase!.toLowerCase().trim();
      if (p == 'postmatch' || p == 'post-match' || p == 'post match' || p == 'post') {
        return 'postmatch';
      }
      if (p == 'general') {
        return 'teleop';
      }
      return p;
    }
    final id = field.id.toLowerCase();
    if (id.startsWith('auto')) return 'auto';
    if (id.startsWith('teleop')) return 'teleop';
    if (id.startsWith('endgame')) return 'endgame';
    if (id.startsWith('post')) return 'postmatch';
    return 'teleop';
  }

  double _calculateFieldPoints(ScoutingFieldModel field, dynamic value) {
    if (value == null || value == '') return 0.0;
    final t = field.type.toLowerCase();
    if (t == 'checkbox' || t == 'boolean' || t == 'toggle') {
      if (value == true || value == 'true') {
        return field.pointsPer ?? 0.0;
      }
      return 0.0;
    }
    if (t == 'select' || t == 'dropdown' || t == 'radio' || t == 'choice') {
      final valStr = value.toString();
      for (final opt in field.options) {
        if (opt.value == valStr) {
          return opt.points;
        }
      }
      return 0.0;
    }
    if (t == 'counter' || t == 'number' || t == 'stepper' || t == 'slider' || t == 'range' || t == 'rating' || t == 'stars') {
      final numVal = double.tryParse(value.toString()) ?? 0.0;
      final factor = field.pointsPer ?? 0.0;
      return numVal * factor;
    }
    return 0.0;
  }

  Map<String, double> _calculatePoints() {
    final totals = <String, double>{
      'auto': 0.0,
      'teleop': 0.0,
      'endgame': 0.0,
      'total': 0.0,
    };
    if (_config == null) return totals;

    for (final field in _config!.fields) {
      final val = _formData[field.id];
      final pts = _calculateFieldPoints(field, val);
      totals['total'] = (totals['total'] ?? 0.0) + pts;
      final phase = _getFieldPhase(field);
      if (phase == 'auto') {
        totals['auto'] = (totals['auto'] ?? 0.0) + pts;
      } else if (phase == 'teleop') {
        totals['teleop'] = (totals['teleop'] ?? 0.0) + pts;
      } else if (phase == 'endgame') {
        totals['endgame'] = (totals['endgame'] ?? 0.0) + pts;
      }
    }
    return totals;
  }

  void _resetFormData(ScoutingConfigModel config) {
    for (var field in config.fields) {
      final t = field.type.toLowerCase();
      if (t == 'section' || t == 'header' || t == 'divider') continue;

      if (t == 'counter' || t == 'number' || t == 'stepper') {
        _formData[field.id] = field.defaultValue ?? field.min ?? 0;
      } else if (t == 'slider' || t == 'range') {
        _formData[field.id] = field.defaultValue ?? field.min ?? 0;
      } else if (t == 'rating' || t == 'stars') {
        _formData[field.id] = field.defaultValue ?? field.min ?? 1;
      } else if (t == 'boolean' || t == 'toggle' || t == 'checkbox') {
        _formData[field.id] = field.defaultValue == true || field.defaultValue == 'true';
      } else if ((t == 'select' || t == 'dropdown' || t == 'radio' || t == 'choice') && field.options.isNotEmpty) {
        _formData[field.id] = field.defaultValue?.toString() ?? field.options.first.value;
      } else if (t == 'multiselect' || t == 'multi-select') {
        _formData[field.id] = field.defaultValue is List ? field.defaultValue : [];
      } else {
        _formData[field.id] = field.defaultValue?.toString() ?? '';
      }
    }
  }

  /// Runs the pre-submit review when it is turned on. True means go ahead
  /// (confirmed, or review is off); false means the scout went back to edit.
  Future<bool> _confirmReview({String? submitLabel}) async {
    if (!widget.apiService.reviewBeforeSubmit) return true;
    if (_isReviewing) return false;
    _isReviewing = true;
    final confirmed = await _showSubmitReview(submitLabel: submitLabel);
    _isReviewing = false;
    return confirmed && mounted;
  }

  /// Pre-submit overview: team, match, point totals and every field grouped by phase.
  Future<bool> _showSubmitReview({String? submitLabel}) {
    final points = _calculatePoints();
    String pts(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    const phaseTitles = {'auto': 'Auto', 'teleop': 'Teleop', 'endgame': 'Endgame', 'postmatch': 'Post-Match'};
    return showSubmitReview(
      context,
      title: context.tr('review.match_title', 'Review Match Entry'),
      chips: [
        SubmitReviewChip(context.tr('review.team', 'Team'), '${_selectedTeam!.teamNumber}'),
        SubmitReviewChip(context.tr('review.match', 'Match'), _selectedMatch!.displayLabel),
        if ((points['total'] ?? 0) > 0) ...[
          SubmitReviewChip(context.tr('review.auto', 'Auto'), pts(points['auto'] ?? 0)),
          SubmitReviewChip(context.tr('review.teleop', 'Teleop'), pts(points['teleop'] ?? 0)),
          SubmitReviewChip(context.tr('review.endgame', 'Endgame'), pts(points['endgame'] ?? 0)),
          SubmitReviewChip(context.tr('review.total_points', 'Total'), '${pts(points['total'] ?? 0)} pts'),
        ],
      ],
      sections: buildReviewSections(
        _config,
        _formData,
        groupOf: _getFieldPhase,
        groupTitle: (phase) => context.tr('review.phase.$phase', phaseTitles[phase] ?? phase),
      ),
      submitLabel: submitLabel,
    );
  }

  bool _validateSelection() {
    if (_selectedTeam == null || _selectedMatch == null) {
      final title = context.tr('scout.selection_required_title');
      String message = '';
      if (_selectedTeam == null && _selectedMatch == null) {
        message = context.tr('scout.select_team_and_match_msg');
      } else if (_selectedTeam == null) {
        message = context.tr('scout.select_team_msg');
      } else {
        message = context.tr('scout.select_match_msg');
      }

      showDialog(
        context: context,
        builder: (ctx) {
          final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
          final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
          final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

          return AlertDialog(
            backgroundColor: surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 28.0),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: TextStyle(fontSize: 14.0, color: secondaryTextColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  context.tr('qr.close'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                ),
              ),
            ],
          );
        },
      );
      return false;
    }
    return true;
  }

  void _submitData() async {
    if (!_validateSelection()) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Selection Incomplete',
        message: 'Please select a Match and Team before saving.',
      );
      return;
    }

    // Check required fields across all phases and auto-switch tab if missing
    for (final field in _config?.fields ?? <ScoutingFieldModel>[]) {
      final t = field.type.toLowerCase();
      if (t == 'text' || t == 'static_text' || t == 'label' || t == 'info' || t == 'section' || t == 'header' || t == 'divider') {
        continue;
      }
      if (field.required) {
        final val = _formData[field.id];
        if (val == null || val == '' || (val is List && val.isEmpty)) {
          final phase = _getFieldPhase(field);
          setState(() => _activeTab = phase);
          ObsidianFeedback.showWarning(
            context,
            title: 'Missing Required Field',
            message: 'Please complete "${field.label}" before saving.',
          );
          return;
        }
      }
    }

    if (!_formKey.currentState!.validate()) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Validation Error',
        message: 'Please complete all required fields.',
      );
      return;
    }
    _formKey.currentState!.save();

    if (!await _confirmReview() || !mounted) return;

    setState(() => _isSubmitting = true);

    final data = <String, dynamic>{
      'eventKey': _eventKey ?? '',
      'matchKey': _selectedMatch!.matchKey,
      'matchNumber': _selectedMatch!.matchNumber,
      'targetTeamNumber': _selectedTeam!.teamNumber,
      ..._formData,
    };

    final response = await widget.apiService.submitMatchScouting(data);

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (response.success) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'direct_upload',
        status: 'synced',
        payload: data,
        scoutedBy: widget.apiService.currentAccountUsername,
        scoutedById: widget.apiService.currentAccountId,
      ));
      ObsidianFeedback.showSuccess(
        context,
        title: 'Match Scouting Saved',
        message: 'Match scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
        statusCode: response.statusCode ?? 200,
      );
      final completedId = _assignmentIdForSelection();
      if (completedId != null) {
        widget.apiService.updateAssignmentStatus(completedId, 'COMPLETED');
      }
      _resetForm();
      _advanceAfterSave(data, completedId);
    } else if (response.isOffline) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'offline_cached',
        status: 'pending',
        payload: data,
        scoutedBy: widget.apiService.currentAccountUsername,
        scoutedById: widget.apiService.currentAccountId,
      ));
      ObsidianFeedback.showWarning(
        context,
        title: 'Saved on This Device Only',
        message: 'Not on the server yet. It will upload automatically when the connection returns.',
      );
      final completedId = _assignmentIdForSelection();
      if (completedId != null) {
        widget.apiService.updateAssignmentStatus(completedId, 'COMPLETED');
      }
      _resetForm();
      _advanceAfterSave(data, completedId);
    } else {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'match',
        action: 'direct_upload',
        status: 'failed',
        payload: data,
        scoutedBy: widget.apiService.currentAccountUsername,
        scoutedById: widget.apiService.currentAccountId,
      ));
      ObsidianFeedback.showError(
        context,
        title: 'Save Failed',
        message: response.message != null && response.message!.isNotEmpty
            ? response.message!
            : 'Failed to submit match scouting data.',
        statusCode: response.statusCode,
        isOffline: response.isOffline,
      );
    }
  }

  Future<void> _confirmAndResetForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

        final titleText = ctx.tr('scout.clear_form');
        final displayTitle = (titleText == 'scout.clear_form' || titleText == 'scout.clear') ? 'Clear form' : titleText;
        final msgText = ctx.tr('scout.confirm_clear');
        final displayMsg = (msgText == 'scout.confirm_clear') ? 'Are you sure you want to clear the form? All entered data will be reset.' : msgText;

        return AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 28.0),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  displayTitle,
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ),
            ],
          ),
          content: Text(
            displayMsg,
            style: TextStyle(fontSize: 14.0, color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                ctx.tr('events.cancel'),
                style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                ctx.tr('graphs.clear_all'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _resetForm();
    }
  }

  void _resetForm() {
    ScoutingDraftService.clearDraft('match');
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _activeTab = 'auto';
        _availableDraft = null;
      });
    }
  }

  Future<void> _generateBarcode() async {
    if (!_validateSelection()) return;

    _formKey.currentState?.save();

    if (!await _confirmReview(submitLabel: context.tr('review.show_qr', 'Show QR Code')) || !mounted) return;

    final payload = {
      'event_key': _eventKey ?? '',
      'team_number': _selectedTeam!.teamNumber,
      'match_number': _selectedMatch!.matchNumber,
      'comp_level': _selectedMatch!.compLevel,
      'data': _formData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
      type: 'match',
      action: 'qr_generated',
      status: 'pending',
      scoutedBy: widget.apiService.currentAccountUsername,
      scoutedById: widget.apiService.currentAccountId,
      payload: {
        'eventKey': _eventKey ?? '',
        'targetTeamNumber': _selectedTeam!.teamNumber,
        'matchKey': _selectedMatch!.matchKey,
        'matchNumber': _selectedMatch!.matchNumber,
        'compLevel': _selectedMatch!.compLevel,
        ..._formData,
      },
    ));

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: context.tr('nav.match_scout'),
      targetTeamNumber: _selectedTeam!.teamNumber,
      matchKey: _selectedMatch!.displayLabel,
    );
  }

  void _handleGamepadAction(GamepadActionEvent event) {
    if (!mounted || !widget.isVisible) return;
    final binding = event.binding;

    // Phase check: only process if binding is global or targets the active period
    if (binding.phase != 'global' && binding.phase.toLowerCase() != _activeTab.toLowerCase()) {
      return;
    }

    switch (binding.actionType) {
      case GamepadActionType.increment:
        if (binding.targetFieldId != null) {
          final fieldId = binding.targetFieldId!;
          final field = _config?.fields.where((f) => f.id == fieldId).firstOrNull;
          if (field != null) {
            final minVal = field.min ?? 0;
            final maxVal = (field.max != null && field.max! > minVal) ? field.max! : 999999;
            final step = (binding.stepValue > 0) ? binding.stepValue.toInt() : (field.step ?? 1);
            final currentVal = (_formData[fieldId] is num) ? (_formData[fieldId] as num).toInt() : minVal;
            final newVal = (currentVal + step).clamp(minVal, maxVal);
            setState(() {
              _formData[fieldId] = newVal;
            });
            _scheduleDraftSave();
          }
        }
        break;

      case GamepadActionType.decrement:
        if (binding.targetFieldId != null) {
          final fieldId = binding.targetFieldId!;
          final field = _config?.fields.where((f) => f.id == fieldId).firstOrNull;
          if (field != null) {
            final minVal = field.min ?? 0;
            final maxVal = (field.max != null && field.max! > minVal) ? field.max! : 999999;
            final step = (binding.stepValue > 0) ? binding.stepValue.toInt() : (field.step ?? 1);
            final currentVal = (_formData[fieldId] is num) ? (_formData[fieldId] as num).toInt() : minVal;
            final newVal = (currentVal - step).clamp(minVal, maxVal);
            setState(() {
              _formData[fieldId] = newVal;
            });
            _scheduleDraftSave();
          }
        }
        break;

      case GamepadActionType.toggle:
        if (binding.targetFieldId != null) {
          final fieldId = binding.targetFieldId!;
          final currentVal = _formData[fieldId];
          final boolVal = (currentVal == true || currentVal == 1 || currentVal == 'true');
          setState(() {
            _formData[fieldId] = !boolVal;
          });
          _scheduleDraftSave();
        }
        break;

      case GamepadActionType.cycleOption:
        if (binding.targetFieldId != null) {
          final fieldId = binding.targetFieldId!;
          final field = _config?.fields.where((f) => f.id == fieldId).firstOrNull;
          if (field != null && field.options.isNotEmpty) {
            final currentVal = _formData[fieldId]?.toString() ?? '';
            final currentIndex = field.options.indexWhere((o) => o.value == currentVal);
            final nextIndex = (currentIndex + 1) % field.options.length;
            setState(() {
              _formData[fieldId] = field.options[nextIndex].value;
            });
            _scheduleDraftSave();
          }
        }
        break;

      case GamepadActionType.switchTab:
        final tabs = ['auto', 'teleop', 'endgame', 'postmatch'];
        if (binding.targetValue == 'next') {
          final idx = tabs.indexOf(_activeTab);
          final nextIdx = (idx + 1) % tabs.length;
          setState(() => _activeTab = tabs[nextIdx]);
        } else if (binding.targetValue == 'prev') {
          final idx = tabs.indexOf(_activeTab);
          final prevIdx = (idx - 1 + tabs.length) % tabs.length;
          setState(() => _activeTab = tabs[prevIdx]);
        } else if (binding.targetValue != null && tabs.contains(binding.targetValue)) {
          setState(() => _activeTab = binding.targetValue!);
        }
        break;

      case GamepadActionType.submit:
        // A second Submit press while the review sheet is open confirms it.
        if (_isReviewing) {
          Navigator.of(context).pop(true);
        } else {
          _submitData();
        }
        break;

      case GamepadActionType.barcode:
        _generateBarcode();
        break;

      case GamepadActionType.clearForm:
        _resetForm();
        break;
    }
  }

  GamepadBinding? _findGlobalActionBinding(GamepadActionType actionType, {String? targetValue}) {
    final activeProfile = GamepadService.instance.activeProfile;
    if (activeProfile == null || !activeProfile.enabled || !activeProfile.showTooltips) return null;
    return activeProfile.bindings.where((b) {
      if (b.actionType != actionType) return false;
      if (targetValue != null && b.targetValue != targetValue) return false;
      return true;
    }).firstOrNull;
  }

  Widget _buildGamepadBadge(String inputKey, {Color? color, String? labelPrefix}) {
    final activeProfile = GamepadService.instance.activeProfile;
    final badge = GamepadService.getShortBadgeLabel(inputKey, controllerType: activeProfile?.controllerType ?? 'xbox');
    final text = labelPrefix != null ? '$labelPrefix$badge' : badge;

    return Container(
      margin: const EdgeInsets.only(left: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      decoration: BoxDecoration(
        color: (color ?? ObsidianUITheme.primaryAccent).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: (color ?? ObsidianUITheme.primaryAccent).withValues(alpha: 0.6),
          width: 1.0,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: color ?? ObsidianUITheme.primaryAccent,
        ),
      ),
    );
  }

  Widget _buildTabRow() {
    final autoLabel = context.tr('phase.auto');
    final teleopLabel = context.tr('phase.teleop');
    final endgameLabel = context.tr('phase.endgame');
    final postmatchLabel = context.tr('prescout-scout.post_match');

    final tabs = [
      {'key': 'auto', 'label': autoLabel == 'phase.auto' ? 'Auto' : autoLabel},
      {'key': 'teleop', 'label': teleopLabel == 'phase.teleop' ? 'Teleop' : teleopLabel},
      {'key': 'endgame', 'label': endgameLabel == 'phase.endgame' ? 'Endgame' : endgameLabel},
      {'key': 'postmatch', 'label': (postmatchLabel == 'prescout-scout.post_match' || postmatchLabel == 'prescout_scout.post_match') ? 'Post Match' : postmatchLabel},
    ];

    final activeProfile = GamepadService.instance.activeProfile;
    final showTooltips = activeProfile != null && activeProfile.enabled && activeProfile.showTooltips;
    GamepadBinding? prevTabBinding;
    GamepadBinding? nextTabBinding;

    if (showTooltips) {
      for (final b in activeProfile.bindings) {
        if (b.actionType == GamepadActionType.switchTab) {
          if (b.targetValue == 'prev') prevTabBinding = b;
          if (b.targetValue == 'next') nextTabBinding = b;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _activeTab == tab['key'];
          final isFirst = tab['key'] == 'auto';
          final isLast = tab['key'] == 'postmatch';

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _activeTab = tab['key']!);
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.25)
                        : ObsidianUITheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? ObsidianUITheme.primaryAccent
                          : ObsidianUITheme.getBorderColor(context),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFirst && prevTabBinding != null)
                        _buildGamepadBadge(prevTabBinding.inputKey, color: ObsidianUITheme.getSecondaryTextColor(context)),
                      Flexible(
                        child: Text(
                          tab['label']!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? ObsidianUITheme.primaryAccent
                                : ObsidianUITheme.getPrimaryTextColor(context),
                          ),
                        ),
                      ),
                      if (isLast && nextTabBinding != null)
                        _buildGamepadBadge(nextTabBinding.inputKey, color: ObsidianUITheme.getSecondaryTextColor(context)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPointsPreview(Map<String, double> points) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final previewLabel = context.tr('prescout-scout.points_preview');
    final displayPreviewTitle = (previewLabel == 'prescout-scout.points_preview' || previewLabel == 'prescout_scout.points_preview') ? 'Points Preview' : previewLabel;
    String formatPt(double val) => val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                displayPreviewTitle.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                  color: ObsidianUITheme.primaryAccent,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(Icons.analytics_outlined, size: 16.0, color: ObsidianUITheme.primaryAccent),
            ],
          ),
          const SizedBox(height: 10.0),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem('Auto', formatPt(points['auto'] ?? 0.0), ObsidianUITheme.primaryAccent, primaryTextColor, secondaryTextColor),
              ),
              Expanded(
                child: _buildMetricItem('Teleop', formatPt(points['teleop'] ?? 0.0), ObsidianUITheme.secondaryAccent, primaryTextColor, secondaryTextColor),
              ),
              Expanded(
                child: _buildMetricItem('Endgame', formatPt(points['endgame'] ?? 0.0), ObsidianUITheme.successGreen, primaryTextColor, secondaryTextColor),
              ),
              Expanded(
                child: _buildMetricItem('Total', formatPt(points['total'] ?? 0.0), Colors.amberAccent, primaryTextColor, secondaryTextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color accentColor, Color textColor, Color subtextColor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w500, color: subtextColor),
        ),
        const SizedBox(height: 4.0),
        Text(
          value,
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: accentColor),
        ),
      ],
    );
  }

  String _getBindingSummary(GamepadBinding b) {
    switch (b.actionType) {
      case GamepadActionType.increment:
        final f = _config?.fields.where((fld) => fld.id == b.targetFieldId).firstOrNull;
        return '[+] ${f?.label ?? b.targetFieldId ?? 'Increment'}';
      case GamepadActionType.decrement:
        final f = _config?.fields.where((fld) => fld.id == b.targetFieldId).firstOrNull;
        return '[-] ${f?.label ?? b.targetFieldId ?? 'Decrement'}';
      case GamepadActionType.toggle:
        final f = _config?.fields.where((fld) => fld.id == b.targetFieldId).firstOrNull;
        return 'Toggle ${f?.label ?? b.targetFieldId ?? 'Checkbox'}';
      case GamepadActionType.cycleOption:
        final f = _config?.fields.where((fld) => fld.id == b.targetFieldId).firstOrNull;
        return 'Cycle ${f?.label ?? b.targetFieldId ?? 'Options'}';
      case GamepadActionType.switchTab:
        return 'Switch Period (${b.targetValue ?? 'next'})';
      case GamepadActionType.submit:
        return 'Save Entry';
      case GamepadActionType.barcode:
        return 'Generate QR Code';
      case GamepadActionType.clearForm:
        return 'Clear Form';
    }
  }

  Widget _buildGamepadCheatSheetButton() {
    final activeProfile = GamepadService.instance.activeProfile;
    if (activeProfile == null || !activeProfile.enabled) {
      return const SizedBox.shrink();
    }

    final activeBindings = activeProfile.bindings.where((b) =>
        b.phase == 'global' || b.phase.toLowerCase() == _activeTab.toLowerCase()).toList();

    final buffer = StringBuffer();
    buffer.writeln('🎮 Controller Keybinds (${activeProfile.name})');
    buffer.writeln('Active Period: ${_activeTab.toUpperCase()}');
    buffer.writeln('------------------------');
    if (activeBindings.isEmpty) {
      buffer.writeln('No bindings configured for this period.');
    } else {
      for (final b in activeBindings) {
        final keyBadge = GamepadService.getShortBadgeLabel(b.inputKey, controllerType: activeProfile.controllerType);
        final actionName = _getBindingSummary(b);
        buffer.writeln('• $keyBadge: $actionName');
      }
    }
    buffer.write('\n(Tap or hover to view active mappings)');

    final isControllerConnected = GamepadService.instance.connectedDevices.isNotEmpty;

    return Tooltip(
      message: buffer.toString(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace'),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: () => _showGamepadCheatSheetModal(context, activeProfile),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isControllerConnected
                  ? ObsidianUITheme.successGreen.withValues(alpha: 0.6)
                  : ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_esports_rounded,
                size: 14,
                color: isControllerConnected ? ObsidianUITheme.successGreen : ObsidianUITheme.primaryAccent,
              ),
              const SizedBox(width: 4),
              Text(
                'Keybinds',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: ObsidianUITheme.getPrimaryTextColor(context),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isControllerConnected ? ObsidianUITheme.successGreen : ObsidianUITheme.warningOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGamepadCheatSheetModal(BuildContext context, GamepadProfile activeProfile) {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.sports_esports_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Controller & Keybind Cheat Sheet',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        Text(
                          'Active Profile: ${activeProfile.name} (${activeProfile.controllerType.toUpperCase()})',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    _buildCheatSheetPhaseSection('GLOBAL ACTIONS', 'global', activeProfile, ObsidianUITheme.primaryAccent),
                    _buildCheatSheetPhaseSection('AUTONOMOUS PERIOD', 'auto', activeProfile, ObsidianUITheme.primaryAccent),
                    _buildCheatSheetPhaseSection('TELEOPERATED PERIOD', 'teleop', activeProfile, ObsidianUITheme.secondaryAccent),
                    _buildCheatSheetPhaseSection('ENDGAME PERIOD', 'endgame', activeProfile, ObsidianUITheme.successGreen),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheatSheetPhaseSection(String title, String phase, GamepadProfile profile, Color accentColor) {
    final bindings = profile.bindings.where((b) => b.phase.toLowerCase() == phase).toList();
    if (bindings.isEmpty) return const SizedBox.shrink();

    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 0.8),
          ),
          const SizedBox(height: 6),
          ...bindings.map((b) {
            final keyBadge = GamepadService.getShortBadgeLabel(b.inputKey, controllerType: profile.controllerType);
            final summary = _getBindingSummary(b);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      keyBadge,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(fontSize: 13, color: primaryTextColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    b.triggerMode == GamepadTriggerMode.scaledTrigger
                        ? 'Analog Trigger'
                        : (b.triggerMode == GamepadTriggerMode.continuousHold ? 'Hold' : 'Tap'),
                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActiveTabFields(List<ScoutingFieldModel> allFields, {bool isDesktop = false}) {
    final activeFields = allFields.where((f) {
      final t = f.type.toLowerCase();
      return _getFieldPhase(f) == _activeTab && t != 'section' && t != 'header' && t != 'divider';
    }).toList();
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    String sectionTitle;
    Color accentColor;
    switch (_activeTab) {
      case 'auto':
        sectionTitle = 'AUTONOMOUS PERIOD';
        accentColor = ObsidianUITheme.primaryAccent;
        break;
      case 'teleop':
        sectionTitle = 'TELEOPERATED PERIOD';
        accentColor = ObsidianUITheme.secondaryAccent;
        break;
      case 'endgame':
        sectionTitle = 'ENDGAME PERIOD';
        accentColor = ObsidianUITheme.successGreen;
        break;
      default:
        sectionTitle = 'POST-MATCH';
        accentColor = Colors.white70;
        break;
    }

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sectionTitle,
                style: TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                  letterSpacing: 1.0,
                ),
              ),
              _buildGamepadCheatSheetButton(),
            ],
          ),
          const SizedBox(height: 12.0),
          if (activeFields.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text(
                  'No fields configured for this phase.',
                  style: TextStyle(fontSize: 13.0, color: secondaryTextColor),
                ),
              ),
            )
          else if (isDesktop)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final cols = constraints.maxWidth > 700 ? 2 : 1;
                final spacing = 12.0;
                final itemWidth = cols > 1 ? (constraints.maxWidth - spacing) / 2 : constraints.maxWidth;

                return Wrap(
                  spacing: spacing,
                  runSpacing: 4.0,
                  children: activeFields.map((field) {
                    final t = field.type.toLowerCase();
                    final isFullWidth = t == 'textarea' || t == 'notes' || t == 'image' || t == 'image_upload' || t == 'photo';
                    return SizedBox(
                      width: isFullWidth ? constraints.maxWidth : itemWidth,
                      child: DynamicFieldWidget(
                        field: field,
                        currentValue: _formData[field.id],
                        currentPhase: _activeTab,
                        onChanged: (val) => _onFieldChanged(field.id, val),
                      ),
                    );
                  }).toList(),
                );
              },
            )
          else
            ...activeFields.map((field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: DynamicFieldWidget(
                    field: field,
                    currentValue: _formData[field.id],
                    currentPhase: _activeTab,
                    onChanged: (val) => _onFieldChanged(field.id, val),
                  ),
                )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
      );
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final fields = _config?.fields ?? [];
    final points = _calculatePoints();

    final Widget content = isDesktop
        ? SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SyncStatusBanner(apiService: widget.apiService, margin: const EdgeInsets.only(bottom: 8)),
                  if (_availableDraft != null)
                    DraftRestoreBanner(
                      draft: _availableDraft!,
                      onRestore: () => _restoreDraft(_availableDraft!),
                      onDiscard: _discardDraft,
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                  _buildNextAssignmentChip(margin: const EdgeInsets.only(bottom: 8)),
              // Team & Match Selector Card
              ObsidianGlassCard(
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TeamModel>(
                        isExpanded: true,
                        initialValue: _availableTeams.contains(_selectedTeam) ? _selectedTeam : null,
                        dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                        style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                        decoration: InputDecoration(
                          labelText: context.tr('scout.select_team'),
                          labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                          prefixIcon: Icon(Icons.group_outlined, color: ObsidianUITheme.primaryAccent),
                          suffixIcon: _selectedTeam != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18.0),
                                  color: ObsidianUITheme.getSecondaryTextColor(context),
                                  onPressed: () => _onTeamSelected(null),
                                  tooltip: 'Clear Team',
                                )
                              : null,
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                        ),
                        items: _availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: _onTeamSelected,
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: DropdownButtonFormField<MatchModel>(
                        isExpanded: true,
                        initialValue: _availableMatches.contains(_selectedMatch) ? _selectedMatch : null,
                        dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                        style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                        decoration: InputDecoration(
                          labelText: context.tr('scout.select_match'),
                          labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                          prefixIcon: Icon(Icons.sports_esports_outlined, color: ObsidianUITheme.primaryAccent),
                          suffixIcon: _selectedMatch != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18.0),
                                  color: ObsidianUITheme.getSecondaryTextColor(context),
                                  onPressed: () => _onMatchSelected(null),
                                  tooltip: 'Clear Match',
                                )
                              : null,
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                        ),
                        items: _availableMatches.map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: _onMatchSelected,
                      ),
                    ),
                  ],
                ),
              ),

              _buildPredictionCard(margin: const EdgeInsets.only(top: 10.0)),

              const SizedBox(height: 10.0),

              if (_selectedTeam == null || _selectedMatch == null)
                ObsidianGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 36.0),
                          const SizedBox(height: 12.0),
                          Builder(
                            builder: (ctx) {
                              final rawText = ctx.tr('scout.select_a_team_and_match_to_sta');
                              final msg = (rawText == 'scout.select_a_team_and_match_to_sta')
                                  ? 'Select a team and match to start scouting.'
                                  : rawText;
                              return Text(
                                msg,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: ObsidianUITheme.getSecondaryTextColor(ctx),
                                  height: 1.4,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column (320px sidebar): Points summary + Action buttons
                    SizedBox(
                      width: 320.0,
                      child: Column(
                        children: [
                          _buildPointsPreview(points),
                          const SizedBox(height: 10.0),
                          Builder(
                            builder: (context) {
                              final qrBinding = _findGlobalActionBinding(GamepadActionType.barcode);
                              return Tooltip(
                                message: qrBinding != null
                                    ? 'Generate QR Code (${GamepadService.getShortBadgeLabel(qrBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                                    : 'Generate QR Code',
                                child: ObsidianGlassCard(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    _generateBarcode();
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.secondaryAccent, size: 20.0),
                                        const SizedBox(width: 8.0),
                                        Text(
                                          context.tr('qr.button_label').toUpperCase(),
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0, color: ObsidianUITheme.getPrimaryTextColor(context)),
                                        ),
                                        if (qrBinding != null) ...[
                                          const SizedBox(width: 4.0),
                                          _buildGamepadBadge(qrBinding.inputKey, color: ObsidianUITheme.secondaryAccent),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10.0),
                          Builder(
                            builder: (context) {
                              final isOnline = widget.apiService.isOnline;
                              final primaryColor = ObsidianUITheme.getPrimaryTextColor(context);
                              final submitBinding = _findGlobalActionBinding(GamepadActionType.submit);
                              return Tooltip(
                                message: submitBinding != null
                                    ? 'Save Entry (${GamepadService.getShortBadgeLabel(submitBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                                    : 'Save Entry',
                                child: ObsidianGlassCard(
                                  onTap: _isSubmitting
                                      ? null
                                      : () {
                                          HapticFeedback.mediumImpact();
                                          _submitData();
                                        },
                                  child: Center(
                                    child: _isSubmitting
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                isOnline ? Icons.send_rounded : Icons.save_rounded,
                                                color: isOnline ? ObsidianUITheme.primaryAccent : ObsidianUITheme.warningOrange,
                                                size: 18.0,
                                              ),
                                              const SizedBox(width: 8.0),
                                              Text(
                                                isOnline ? context.tr('scout.save_entry').toUpperCase() : '${context.tr('scout.save_entry')} (OFFLINE)'.toUpperCase(),
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0, color: primaryColor),
                                              ),
                                              if (submitBinding != null) ...[
                                                const SizedBox(width: 4.0),
                                                _buildGamepadBadge(submitBinding.inputKey, color: ObsidianUITheme.primaryAccent),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10.0),
                          Builder(
                            builder: (context) {
                              final clearBinding = _findGlobalActionBinding(GamepadActionType.clearForm);
                              return Tooltip(
                                message: clearBinding != null
                                    ? 'Clear Form (${GamepadService.getShortBadgeLabel(clearBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                                    : 'Clear Form',
                                child: ObsidianGlassCard(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    _confirmAndResetForm();
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.refresh_rounded, size: 16.0, color: ObsidianUITheme.getSecondaryTextColor(context)),
                                        const SizedBox(width: 6.0),
                                        Text(
                                          'CLEAR FORM',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.0,
                                            color: ObsidianUITheme.getSecondaryTextColor(context),
                                          ),
                                        ),
                                        if (clearBinding != null) ...[
                                          const SizedBox(width: 4.0),
                                          _buildGamepadBadge(clearBinding.inputKey, color: ObsidianUITheme.getSecondaryTextColor(context)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 14.0),

                    // Right Column (Expanded): Tabs & Form Fields
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTabRow(),
                          _buildActiveTabFields(fields, isDesktop: true),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      )
    : SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SyncStatusBanner(apiService: widget.apiService),
              if (_availableDraft != null)
                DraftRestoreBanner(
                  draft: _availableDraft!,
                  onRestore: () => _restoreDraft(_availableDraft!),
                  onDiscard: _discardDraft,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                ),
              _buildNextAssignmentChip(),
            // Team & Match Dropdowns Card
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('dashboard.event_context').toUpperCase(),
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<TeamModel>(
                    isExpanded: true,
                    initialValue: _availableTeams.contains(_selectedTeam) ? _selectedTeam : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_team'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: Icon(Icons.group_outlined, color: ObsidianUITheme.primaryAccent),
                      suffixIcon: _selectedTeam != null
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18.0),
                              color: ObsidianUITheme.getSecondaryTextColor(context),
                              onPressed: () => _onTeamSelected(null),
                              tooltip: 'Clear Team',
                            )
                          : null,
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _availableTeams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: _onTeamSelected,
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<MatchModel>(
                    isExpanded: true,
                    initialValue: _availableMatches.contains(_selectedMatch) ? _selectedMatch : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_match'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: Icon(Icons.sports_esports_outlined, color: ObsidianUITheme.primaryAccent),
                      suffixIcon: _selectedMatch != null
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18.0),
                              color: ObsidianUITheme.getSecondaryTextColor(context),
                              onPressed: () => _onMatchSelected(null),
                              tooltip: 'Clear Match',
                            )
                          : null,
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _availableMatches.map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: _onMatchSelected,
                  ),
                ],
              ),
            ),

            _buildPredictionCard(),

            // Tab Row & Scouting Form (Only rendered when team and match are selected)
            if (_selectedTeam == null || _selectedMatch == null)
              ObsidianGlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 36.0),
                        const SizedBox(height: 12.0),
                        Builder(
                          builder: (ctx) {
                            final rawText = ctx.tr('scout.select_a_team_and_match_to_sta');
                            final msg = (rawText == 'scout.select_a_team_and_match_to_sta')
                                ? 'Select a team and match to start scouting.'
                                : rawText;
                            return Text(
                              msg,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: ObsidianUITheme.getSecondaryTextColor(ctx),
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              // Tab Row (Auto, Teleop, Endgame, Post Match)
              _buildTabRow(),

              // Active Tab Fields Card
              _buildActiveTabFields(fields),

              // Points Preview Card
              _buildPointsPreview(points),

              // Generate QR / JAB Code Button Card
              Builder(
                builder: (context) {
                  final qrBinding = _findGlobalActionBinding(GamepadActionType.barcode);
                  return Tooltip(
                    message: qrBinding != null
                        ? 'Generate QR Code (${GamepadService.getShortBadgeLabel(qrBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                        : 'Generate QR Code',
                    child: ObsidianGlassCard(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _generateBarcode();
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.secondaryAccent),
                            const SizedBox(width: 10.0),
                            Text(
                              context.tr('qr.button_label').toUpperCase(),
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0, color: ObsidianUITheme.getPrimaryTextColor(context)),
                            ),
                            if (qrBinding != null) ...[
                              const SizedBox(width: 6.0),
                              _buildGamepadBadge(qrBinding.inputKey, color: ObsidianUITheme.secondaryAccent),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Submit Button
              Builder(
                builder: (context) {
                  final isOnline = widget.apiService.isOnline;
                  final primaryColor = ObsidianUITheme.getPrimaryTextColor(context);
                  final submitBinding = _findGlobalActionBinding(GamepadActionType.submit);
                  return Tooltip(
                    message: submitBinding != null
                        ? 'Save Entry (${GamepadService.getShortBadgeLabel(submitBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                        : 'Save Entry',
                    child: ObsidianGlassCard(
                      onTap: _isSubmitting
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _submitData();
                            },
                      child: Center(
                        child: _isSubmitting
                            ? CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isOnline ? Icons.send_rounded : Icons.save_rounded,
                                    color: isOnline ? ObsidianUITheme.primaryAccent : ObsidianUITheme.warningOrange,
                                  ),
                                  const SizedBox(width: 10.0),
                                  Text(
                                    isOnline ? context.tr('scout.save_entry').toUpperCase() : '${context.tr('scout.save_entry')} (OFFLINE)'.toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.0,
                                      color: primaryColor,
                                    ),
                                  ),
                                  if (submitBinding != null) ...[
                                    const SizedBox(width: 6.0),
                                    _buildGamepadBadge(submitBinding.inputKey, color: ObsidianUITheme.primaryAccent),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),

              // Clear Form Button
              Builder(
                builder: (context) {
                  final clearBinding = _findGlobalActionBinding(GamepadActionType.clearForm);
                  return Tooltip(
                    message: clearBinding != null
                        ? 'Clear Form (${GamepadService.getShortBadgeLabel(clearBinding.inputKey, controllerType: GamepadService.instance.activeProfile?.controllerType ?? 'xbox')})'
                        : 'Clear Form',
                    child: ObsidianGlassCard(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _confirmAndResetForm();
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded, size: 18.0, color: ObsidianUITheme.getSecondaryTextColor(context)),
                            const SizedBox(width: 8.0),
                            Builder(
                              builder: (ctx) {
                                final clearLabel = ctx.tr('scout.clear_form');
                                final displayClear = (clearLabel == 'scout.clear_form' || clearLabel == 'scout.clear') ? 'Clear form' : clearLabel;
                                return Text(
                                  displayClear.toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.0,
                                    color: ObsidianUITheme.getSecondaryTextColor(ctx),
                                  ),
                                );
                              },
                            ),
                            if (clearBinding != null) ...[
                              const SizedBox(width: 6.0),
                              _buildGamepadBadge(clearBinding.inputKey, color: ObsidianUITheme.getSecondaryTextColor(context)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );

    return PopScope(
      canPop: !_isFormDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handlePopAttempt();
        if (shouldPop && context.mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(result);
          }
        }
      },
      child: content,
    );
  }
}
