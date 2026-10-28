import 'dart:async';
import 'package:flutter/material.dart';
import '../services/scouting_draft_service.dart';
import '../widgets/draft_restore_banner.dart';
import '../widgets/submit_review_sheet.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../services/api_service.dart';
import '../services/scout_history_service.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/sync_status_banner.dart';
import '../models/assignment_models.dart';
import '../services/assignment_advance_service.dart';
import '../widgets/next_assignment_chip.dart';

class PitScoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final int? initialTargetTeamNumber;
  final String? sourceAssignmentId;

  const PitScoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.initialTargetTeamNumber,
    this.sourceAssignmentId,
  });

  @override
  State<PitScoutScreen> createState() => _PitScoutScreenState();
}

class _PitScoutScreenState extends State<PitScoutScreen> with WidgetsBindingObserver {
  // Form draft persistence & accidental back protection
  Timer? _draftSaveTimer;
  ScoutingDraft? _availableDraft;
  final _formKey = GlobalKey<FormState>();
  ScoutingConfigModel? _config;
  List<TeamModel> _teams = [];
  TeamModel? _selectedTeam;
  String? _eventKey;

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isReviewing = false;
  final Map<String, dynamic> _formData = {};

  // Assignment auto-advance: after a save, jump to the scout's next pit assignment.
  List<ScoutingAssignment> _assignments = [];
  NextAssignment? _nextAssignment;
  bool _advanced = false;
  bool _autoAdvance = true;
  bool _initialAdvanceDone = false;
  final Set<String> _doneIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPitData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftSaveTimer?.cancel();
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

  void _onTeamSelected(TeamModel? team) {
    setState(() => _selectedTeam = team);
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
      formType: 'pit',
      data: _formData,
      teamNumber: _selectedTeam?.teamNumber,
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
      for (final entry in draft.data.entries) {
        _formData[entry.key] = entry.value;
      }
      _availableDraft = null;
    });
    ObsidianFeedback.showSuccess(
      context,
      title: 'Draft Restored',
      message: 'Restored pit scouting draft for ${draft.contextDescription()}',
    );
  }

  void _discardDraft() async {
    await ScoutingDraftService.clearDraft('pit');
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
                'Discard Pit Scouting Progress?',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
            ),
          ],
        ),
        content: Text(
          'You have unsaved pit scouting data for ${_selectedTeam != null ? 'Team ${_selectedTeam!.teamNumber}' : 'this team'}.\n\nWould you like to keep scouting, save your progress as a draft, or discard?',
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
      await ScoutingDraftService.clearDraft('pit');
      _resetForm();
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant PitScoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasNewInitialParams = widget.initialTargetTeamNumber != oldWidget.initialTargetTeamNumber ||
        widget.sourceAssignmentId != oldWidget.sourceAssignmentId;

    if (hasNewInitialParams) {
      _applyInitialSelections(force: true);
    }

    if (widget.isVisible && !oldWidget.isVisible) {
      _loadPitData();
    }
  }

  void _loadPitData() async {
    // 1. Instant Cache Hydration (0ms! Zero spinner when data exists locally)
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    final cachedConfig = await widget.apiService.getCachedPitConfig();
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);

    if (mounted && (cachedConfig != null || cachedTeams.isNotEmpty)) {
      setState(() {
        _eventKey = cachedEventKey;
        _config = cachedConfig;
        _teams = cachedTeams;
        _isLoading = false;
        if (cachedConfig != null && _formData.isEmpty) {
          _resetFormData(cachedConfig);
        }
        _applyInitialSelections();
      });
      _initAssignments();
    }

    final savedDraft = await ScoutingDraftService.loadDraft('pit');
    if (mounted && savedDraft != null) {
      setState(() {
        _availableDraft = savedDraft;
      });
    }

    // If offline, stop immediately - don't wait for network timeouts
    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation
    try {
      final eventKeyFuture = widget.apiService.fetchCurrentEventKey();
      final configFuture = widget.apiService.fetchPitConfig();

      final eventKey = await eventKeyFuture;
      final config = await configFuture;
      final teams = await widget.apiService.fetchTeams(eventKey);

      if (!mounted) return;

      setState(() {
        _eventKey = eventKey;
        _config = config ?? _config;
        if (teams.isNotEmpty) _teams = teams;
        if (_selectedTeam != null && !_teams.contains(_selectedTeam)) {
          _selectedTeam = null;
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
      final next = AssignmentAdvanceService.next(list, type: 'PIT', afterTeam: _selectedTeam?.teamNumber);
      setState(() {
        _assignments = list;
        _autoAdvance = enabled;
        _nextAssignment = next;
        _advanced = false;
        if (!_initialAdvanceDone && enabled && widget.initialTargetTeamNumber == null && _selectedTeam == null && next?.assignment != null) {
          _applyAssignment(next!.assignment!);
          _advanced = true;
        }
        if (_teams.isNotEmpty) _initialAdvanceDone = true;
      });
    } catch (_) {}
  }

  /// Selects an assignment's team. Call inside setState.
  void _applyAssignment(ScoutingAssignment a) {
    final teamNumber = a.targetTeamNumber;
    if (teamNumber == null) return;
    final team = _teams.where((t) => t.teamNumber == teamNumber).firstOrNull;
    if (team != null) _selectedTeam = team;
  }

  String? _assignmentIdForSelection() {
    final team = _selectedTeam;
    if (team == null) return null;
    final hit = _assignments
        .where((a) => a.assignmentType.toUpperCase() == 'PIT' && a.targetTeamNumber == team.teamNumber)
        .firstOrNull;
    if (hit != null) return hit.id;
    final sourceId = widget.sourceAssignmentId;
    return (sourceId != null && sourceId.isNotEmpty && widget.initialTargetTeamNumber == team.teamNumber) ? sourceId : null;
  }

  Future<void> _advanceAfterSave(int teamNumber, String? completedId) async {
    if (completedId != null) _doneIds.add(completedId);
    try {
      final list = await widget.apiService.getCachedMyAssignments(_eventKey);
      if (!mounted) return;
      final source = list.isNotEmpty ? list : _assignments;
      final next = AssignmentAdvanceService.next(
        source,
        type: 'PIT',
        afterTeam: teamNumber,
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

  Widget _buildNextAssignmentChip({EdgeInsetsGeometry? margin}) {
    final currentId = _assignmentIdForSelection();
    final current = currentId == null || _doneIds.contains(currentId)
        ? null
        : _assignments.where((a) => a.id == currentId && AssignmentAdvanceService.isOpen(a)).firstOrNull;
    final ahead = AssignmentAdvanceService.next(
      _assignments,
      type: 'PIT',
      afterTeam: _selectedTeam?.teamNumber,
      justCompletedIds: {..._doneIds, if (current != null) current.id},
      noWrap: true,
    );
    // Nothing after the selection: point at the earliest open one instead (or report none left).
    final fallback = ahead?.assignment == null
        ? AssignmentAdvanceService.next(_assignments, type: 'PIT', matches: const [], justCompletedIds: {..._doneIds, if (current != null) current.id})
        : null;
    final upNext = current != null ? ahead?.assignment : (ahead?.assignment ?? fallback?.assignment);
    final earlierOpen = current != null && ahead?.assignment == null ? (ahead?.remaining ?? 0) : 0;
    return NextAssignmentChip(
      hasAssignments: _assignments.any((a) => a.assignmentType.toUpperCase() == 'PIT'),
      current: current,
      upNext: upNext,
      earlierOpen: earlierOpen,
      skippedPast: _advanced ? (_nextAssignment?.skippedPast ?? 0) : 0,
      autoAdvance: _autoAdvance,
      onToggleAutoAdvance: _setAutoAdvance,
      onChange: () => setState(() {
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

  /// When the selected team is a group pit assignment, names the group and who else is in it.
  Widget _buildPitGroupBanner({EdgeInsetsGeometry? margin}) {
    final team = _selectedTeam;
    final asgn = team == null
        ? null
        : _assignments.where((a) => a.isGroupPit && a.targetTeamNumber == team.teamNumber).firstOrNull;
    if (asgn == null) return const SizedBox.shrink();

    final me = widget.apiService.currentUser?.username.toLowerCase();
    final others = asgn.scoutGroupMembers.where((m) => m.toLowerCase() != me).toList();
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, size: 18, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              others.isEmpty
                  ? 'Group: ${asgn.scoutGroup!.trim()}. Only one of you needs to submit.'
                  : 'Group: ${asgn.scoutGroup!.trim()} with ${others.join(', ')}. Only one of you needs to submit.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
            ),
          ),
        ],
      ),
    );
  }

  void _applyInitialSelections({bool force = false}) {
    if ((force || _selectedTeam == null) && _teams.isNotEmpty && widget.initialTargetTeamNumber != null) {
      final team = _teams.where((t) => t.teamNumber == widget.initialTargetTeamNumber).firstOrNull;
      if (team != null) _selectedTeam = team;
    }
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

  Future<void> _confirmAndResetForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final surfaceColor = ObsidianUITheme.getSurfaceColor(ctx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

        final titleText = ctx.tr('pit_scout.clear_form');
        final displayTitle = (titleText == 'pit_scout.clear_form' || titleText == 'pit_scout.clear') ? 'Clear form' : titleText;
        final msgText = ctx.tr('pit_scout.confirm_clear');
        final displayMsg = (msgText == 'pit_scout.confirm_clear') ? 'Are you sure you want to clear the form? All entered data will be reset.' : msgText;

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
    ScoutingDraftService.clearDraft('pit');
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _selectedTeam = null;
        _availableDraft = null;
      });
    }
  }

  bool _validateSelection() {
    if (_selectedTeam == null) {
      final title = context.tr('scout.selection_required_title');
      final message = context.tr('scout.select_team_msg');

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

  /// Runs the pre-submit review when it is turned on. True means go ahead
  /// (confirmed, or review is off); false means the scout went back to edit.
  Future<bool> _confirmReview({String? submitLabel}) async {
    if (!widget.apiService.reviewBeforeSubmit) return true;
    if (_isReviewing) return false;
    _isReviewing = true;
    final confirmed = await showSubmitReview(
      context,
      title: context.tr('review.pit_title', 'Review Pit Entry'),
      chips: [SubmitReviewChip(context.tr('review.team', 'Team'), '${_selectedTeam!.teamNumber}')],
      sections: buildReviewSections(_config, _formData),
      submitLabel: submitLabel,
    );
    _isReviewing = false;
    return confirmed && mounted;
  }

  void _submitPitData() async {
    if (!_validateSelection()) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Team Incomplete',
        message: 'Please select a Team before saving.',
      );
      return;
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

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      ..._formData,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await widget.apiService.submitPitScouting(payload);

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (response.success) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'direct_upload',
        status: 'synced',
        payload: payload,
        scoutedBy: widget.apiService.currentAccountUsername,
        scoutedById: widget.apiService.currentAccountId,
      ));
      ObsidianFeedback.showSuccess(
        context,
        title: 'Pit Scouting Saved',
        message: 'Pit scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
        statusCode: response.statusCode ?? 200,
      );
      final completedId = _assignmentIdForSelection();
      if (completedId != null) {
        widget.apiService.updateAssignmentStatus(completedId, 'COMPLETED');
      }
      ScoutingDraftService.clearDraft('pit');
      _availableDraft = null;
      _resetForm();
      _advanceAfterSave(payload['targetTeamNumber'] as int, completedId);
    } else if (response.isOffline) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'offline_cached',
        status: 'pending',
        payload: payload,
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
      ScoutingDraftService.clearDraft('pit');
      _availableDraft = null;
      _resetForm();
      _advanceAfterSave(payload['targetTeamNumber'] as int, completedId);
    } else {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'direct_upload',
        status: 'failed',
        payload: payload,
        scoutedBy: widget.apiService.currentAccountUsername,
        scoutedById: widget.apiService.currentAccountId,
      ));
      ObsidianFeedback.showError(
        context,
        title: 'Save Failed',
        message: response.message != null && response.message!.isNotEmpty
            ? response.message!
            : 'Failed to submit pit scouting data.',
        statusCode: response.statusCode,
        isOffline: response.isOffline,
      );
    }
  }

  Future<void> _generateBarcode() async {
    if (!_validateSelection()) return;

    _formKey.currentState?.save();

    if (!await _confirmReview(submitLabel: context.tr('review.show_qr', 'Show QR Code')) || !mounted) return;

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      'type': 'pit-scout',
      ..._formData,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
      type: 'pit',
      action: 'qr_generated',
      status: 'pending',
      payload: payload,
      scoutedBy: widget.apiService.currentAccountUsername,
      scoutedById: widget.apiService.currentAccountId,
    ));

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: context.tr('nav.pit_scout'),
      targetTeamNumber: _selectedTeam!.teamNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.secondaryAccent),
      );
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final fields = (_config?.fields ?? []).where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

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
              _buildPitGroupBanner(margin: const EdgeInsets.only(bottom: 8)),
              ObsidianGlassCard(
                child: DropdownButtonFormField<TeamModel>(
                  isExpanded: true,
                  initialValue: _teams.contains(_selectedTeam) ? _selectedTeam : null,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  decoration: InputDecoration(
                    labelText: context.tr('scout.select_team'),
                    labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                    prefixIcon: Icon(Icons.build_circle_outlined, color: ObsidianUITheme.secondaryAccent),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: _onTeamSelected,
                ),
              ),

              const SizedBox(height: 10.0),

              if (_selectedTeam == null)
                ObsidianGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, color: ObsidianUITheme.secondaryAccent, size: 36.0),
                          const SizedBox(height: 12.0),
                          Text(
                            'Select a team above to start entering pit scouting data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: ObsidianUITheme.getSecondaryTextColor(context),
                              height: 1.4,
                            ),
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
                    // Left Column (300px): Actions & QR
                    SizedBox(
                      width: 300.0,
                      child: Column(
                        children: [
                          ObsidianGlassCard(
                            onTap: _generateBarcode,
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10.0),
                          Builder(
                            builder: (context) {
                              final isOnline = widget.apiService.isOnline;
                              final primaryColor = ObsidianUITheme.getPrimaryTextColor(context);
                              return ObsidianGlassCard(
                                onTap: _isSubmitting ? null : _submitPitData,
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
                                              isOnline ? Icons.save_rounded : Icons.save_rounded,
                                              color: isOnline ? ObsidianUITheme.primaryAccent : ObsidianUITheme.warningOrange,
                                              size: 18.0,
                                            ),
                                            const SizedBox(width: 8.0),
                                            Text(
                                              isOnline ? context.tr('scout.save_entry').toUpperCase() : '${context.tr('scout.save_entry')} (OFFLINE)'.toUpperCase(),
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0, color: primaryColor),
                                            ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10.0),
                          ObsidianGlassCard(
                            onTap: _confirmAndResetForm,
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
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 14.0),

                    // Right Column (Expanded): Multi-column Form Fields
                    Expanded(
                      child: ObsidianGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('subtitle.pit_scout').toUpperCase(),
                              style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context), letterSpacing: 1.0),
                            ),
                            const SizedBox(height: 12.0),
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final cols = constraints.maxWidth > 700 ? 2 : 1;
                                final spacing = 12.0;
                                final itemWidth = cols > 1 ? (constraints.maxWidth - spacing) / 2 : constraints.maxWidth;

                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: 4.0,
                                  children: fields.map((field) {
                                    final t = field.type.toLowerCase();
                                    final isFullWidth = t == 'textarea' || t == 'notes' || t == 'image' || t == 'image_upload' || t == 'photo';
                                    return SizedBox(
                                      width: isFullWidth ? constraints.maxWidth : itemWidth,
                                      child: DynamicFieldWidget(
                                        field: field,
                                        currentValue: _formData[field.id],
                                        onChanged: (val) => _onFieldChanged(field.id, val),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
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
      )
    : SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Form(
        key: _formKey,
        child: Column(
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
            _buildPitGroupBanner(),
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('nav.pit_scout').toUpperCase(),
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<TeamModel>(
                    isExpanded: true,
                    initialValue: _teams.contains(_selectedTeam) ? _selectedTeam : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_team'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: Icon(Icons.build_circle_outlined, color: ObsidianUITheme.secondaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: _onTeamSelected,
                  ),
                ],
              ),
            ),
            if (_selectedTeam == null)
              ObsidianGlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, color: ObsidianUITheme.secondaryAccent, size: 36.0),
                        const SizedBox(height: 12.0),
                        Builder(
                          builder: (ctx) {
                            final rawText = ctx.tr('pit_scout.form_blocked');
                            final msg = (rawText == 'pit_scout.form_blocked' || rawText == 'scout.select_team_msg')
                                ? 'Select a team to start pit scouting.'
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
              if (fields.isNotEmpty)
                ObsidianGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('subtitle.pit_scout').toUpperCase(),
                        style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context), letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 12.0),
                      ...fields.map((field) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: DynamicFieldWidget(
                              field: field,
                              currentValue: _formData[field.id],
                              onChanged: (val) => _onFieldChanged(field.id, val),
                            ),
                          )),
                    ],
                  ),
                ),
              ObsidianGlassCard(
                onTap: _generateBarcode,
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
                    ],
                  ),
                ),
              ),
              Builder(
                builder: (context) {
                  final isOnline = widget.apiService.isOnline;
                  final primaryColor = ObsidianUITheme.getPrimaryTextColor(context);
                  return ObsidianGlassCard(
                    onTap: _isSubmitting ? null : _submitPitData,
                    child: Center(
                      child: _isSubmitting
                          ? CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isOnline ? Icons.save_rounded : Icons.save_rounded,
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
                              ],
                            ),
                    ),
                  );
                },
              ),

              // Clear Form Button
              ObsidianGlassCard(
                onTap: _confirmAndResetForm,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, size: 18.0, color: ObsidianUITheme.getSecondaryTextColor(context)),
                      const SizedBox(width: 8.0),
                      Builder(
                        builder: (ctx) {
                          final clearLabel = ctx.tr('pit_scout.clear_form');
                          final displayClear = (clearLabel == 'pit_scout.clear_form' || clearLabel == 'pit_scout.clear') ? 'Clear form' : clearLabel;
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
                    ],
                  ),
                ),
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
