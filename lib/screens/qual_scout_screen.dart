import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../services/scout_history_service.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';

enum QualScoutScope { singleTeam, redAlliance, blueAlliance, bothAlliances }

class QualScoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const QualScoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<QualScoutScreen> createState() => _QualScoutScreenState();
}

class _QualScoutScreenState extends State<QualScoutScreen> {
  final _formKey = GlobalKey<FormState>();
  ScoutingConfigModel? _config;
  List<TeamModel> _teams = [];
  List<MatchModel> _matches = [];
  String? _eventKey;

  QualScoutScope _scope = QualScoutScope.singleTeam;
  TeamModel? _selectedTeam;
  MatchModel? _selectedMatch;
  final Map<int, Map<String, dynamic>> _teamFormData = {};

  bool _isLoading = true;
  bool _isSubmitting = false;
  final Map<String, dynamic> _formData = {};

  @override
  void initState() {
    super.initState();
    _loadQualData();
  }

  @override
  void didUpdateWidget(covariant QualScoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadQualData();
    }
  }

  void _loadQualData() async {
    // 1. Instant Cache Hydration (0ms! Zero spinner when data exists locally)
    final cachedEventKey = await widget.apiService.getCachedEventKey();
    var cachedConfig = await widget.apiService.getCachedQualConfig();
    final cachedTeams = await widget.apiService.getCachedTeams(cachedEventKey);
    final cachedMatches = await widget.apiService.getCachedMatches(cachedEventKey);

    if (cachedConfig == null || cachedConfig.fields.isEmpty) {
      cachedConfig = _buildFallbackQualConfig();
    }

    if (mounted && (cachedConfig.fields.isNotEmpty || cachedTeams.isNotEmpty || cachedMatches.isNotEmpty)) {
      setState(() {
        _eventKey = cachedEventKey;
        _config = cachedConfig;
        _teams = cachedTeams;
        _matches = cachedMatches;
        _isLoading = false;
        if (_formData.isEmpty) {
          _resetFormData(cachedConfig!);
        }
      });
    }

    // If offline, stop immediately
    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    // 2. Background Revalidation
    try {
      final eventKeyFuture = widget.apiService.fetchCurrentEventKey();
      final configFuture = widget.apiService.fetchQualConfig();

      final eventKey = await eventKeyFuture;
      ScoutingConfigModel? config = await configFuture;

      final results = await Future.wait([
        widget.apiService.fetchTeams(eventKey),
        widget.apiService.fetchMatches(eventKey),
      ]);

      final teams = results[0] as List<TeamModel>;
      final matches = results[1] as List<MatchModel>;

      if (config == null || config.fields.isEmpty) {
        config = _config ?? _buildFallbackQualConfig();
      }

      if (!mounted) return;

      setState(() {
        _eventKey = eventKey;
        _config = config ?? _config;
        if (teams.isNotEmpty) _teams = teams;
        if (matches.isNotEmpty) _matches = matches;
        if (_selectedTeam != null && !_teams.contains(_selectedTeam)) {
          _selectedTeam = null;
        }
        if (_selectedMatch != null && !_matches.contains(_selectedMatch)) {
          _selectedMatch = null;
        }
        _isLoading = false;

        if (_config != null && _formData.isEmpty) {
          _resetFormData(_config!);
        }
      });
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  ScoutingConfigModel _buildFallbackQualConfig() {
    return ScoutingConfigModel(
      title: 'FRC Qualitative Scouting',
      fields: [
        ScoutingFieldModel(
          id: 'driver_skill',
          label: 'Driver Skill & Field Awareness',
          type: 'rating',
          min: 1,
          max: 5,
          defaultValue: 3,
        ),
        ScoutingFieldModel(
          id: 'defense_rating',
          label: 'Defense Rating / Resistance',
          type: 'rating',
          min: 1,
          max: 5,
          defaultValue: 1,
        ),
        ScoutingFieldModel(
          id: 'robot_speed',
          label: 'Robot Speed & Agility',
          type: 'select',
          options: [
            ScoutingOptionModel(label: 'Very Fast', value: 'very_fast'),
            ScoutingOptionModel(label: 'Moderate / Normal', value: 'moderate'),
            ScoutingOptionModel(label: 'Slow / Struggling', value: 'slow'),
          ],
        ),
        ScoutingFieldModel(
          id: 'intake_consistency',
          label: 'Intake & Feed Reliability',
          type: 'select',
          options: [
            ScoutingOptionModel(label: 'Flawless', value: 'flawless'),
            ScoutingOptionModel(label: 'Consistent', value: 'consistent'),
            ScoutingOptionModel(label: 'Prone to Jams', value: 'jams'),
          ],
        ),
        ScoutingFieldModel(
          id: 'robustness',
          label: 'Mechanical Robustness',
          type: 'select',
          options: [
            ScoutingOptionModel(label: 'Sturdy / Solid', value: 'sturdy'),
            ScoutingOptionModel(label: 'Average', value: 'average'),
            ScoutingOptionModel(label: 'Fragile / Breakdowns', value: 'fragile'),
          ],
        ),
        ScoutingFieldModel(
          id: 'qualitative_notes',
          label: 'Qualitative Notes / Strategy Comments',
          type: 'text',
        ),
      ],
    );
  }

  void _resetFormData(ScoutingConfigModel config) {
    for (var field in config.fields) {
      final t = field.type.toLowerCase();
      if (t == 'section' || t == 'header' || t == 'divider') continue;

      if (t == 'counter' || t == 'number' || t == 'stepper') {
        _formData[field.id] = field.defaultValue ?? field.min ?? 1;
      } else if (t == 'slider' || t == 'range') {
        _formData[field.id] = field.defaultValue ?? field.min ?? 1;
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

        final titleText = ctx.tr('qual_scout.clear_form');
        final displayTitle = (titleText == 'qual_scout.clear_form' || titleText == 'qual_scout.clear') ? 'Clear Form' : titleText;
        final msgText = ctx.tr('qual_scout.confirm_clear');
        final displayMsg = (msgText == 'qual_scout.confirm_clear') ? 'Are you sure you want to clear the form? All entered data will be reset.' : msgText;

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

  String _tr(String key, String fallback) {
    try {
      final val = context.tr(key);
      return (val == key || val.isEmpty) ? fallback : val;
    } catch (_) {
      return fallback;
    }
  }

  String _getScopeLabel(QualScoutScope scope) {
    switch (scope) {
      case QualScoutScope.singleTeam:
        return 'Single Team';
      case QualScoutScope.redAlliance:
        return 'Red Alliance';
      case QualScoutScope.blueAlliance:
        return 'Blue Alliance';
      case QualScoutScope.bothAlliances:
        return 'Both Alliances';
    }
  }

  String _getScopeCode(QualScoutScope scope) {
    switch (scope) {
      case QualScoutScope.singleTeam:
        return 'team';
      case QualScoutScope.redAlliance:
        return 'red';
      case QualScoutScope.blueAlliance:
        return 'blue';
      case QualScoutScope.bothAlliances:
        return 'both';
    }
  }

  List<TeamModel> _getAllianceTeamsForMatch(MatchModel? match, QualScoutScope scope) {
    if (match == null) return [];
    final teams = <TeamModel>[];

    int? parseNum(String key) {
      final cleaned = key.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
      return int.tryParse(cleaned);
    }

    TeamModel resolveTeam(String key, int num) {
      return _teams.firstWhere(
        (t) => t.teamNumber == num,
        orElse: () => TeamModel(eventKey: _eventKey ?? '', teamKey: key, teamNumber: num),
      );
    }

    if (scope == QualScoutScope.redAlliance || scope == QualScoutScope.bothAlliances) {
      for (final key in match.redTeams) {
        final num = parseNum(key);
        if (num != null && !teams.any((t) => t.teamNumber == num)) {
          teams.add(resolveTeam(key, num));
        }
      }
    }

    if (scope == QualScoutScope.blueAlliance || scope == QualScoutScope.bothAlliances) {
      for (final key in match.blueTeams) {
        final num = parseNum(key);
        if (num != null && !teams.any((t) => t.teamNumber == num)) {
          teams.add(resolveTeam(key, num));
        }
      }
    }

    return teams;
  }

  bool _isRedAllianceTeam(TeamModel team) {
    if (_scope == QualScoutScope.redAlliance) return true;
    if (_scope == QualScoutScope.blueAlliance) return false;
    if (_selectedMatch != null) {
      for (final k in _selectedMatch!.redTeams) {
        final cleaned = k.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
        if (int.tryParse(cleaned) == team.teamNumber) return true;
      }
    }
    return false;
  }

  String _getTeamPositionBadge(TeamModel team) {
    if (_selectedMatch != null) {
      for (int i = 0; i < _selectedMatch!.redTeams.length; i++) {
        final cleaned = _selectedMatch!.redTeams[i].replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
        if (int.tryParse(cleaned) == team.teamNumber) return 'Red ${i + 1}';
      }
      for (int i = 0; i < _selectedMatch!.blueTeams.length; i++) {
        final cleaned = _selectedMatch!.blueTeams[i].replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
        if (int.tryParse(cleaned) == team.teamNumber) return 'Blue ${i + 1}';
      }
    }
    return _scope == QualScoutScope.redAlliance ? 'Red' : 'Blue';
  }

  void _resetForm() {
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _selectedTeam = null;
        _selectedMatch = null;
        _teamFormData.clear();
      });
    }
  }

  bool _validateSelection() {
    if (_scope == QualScoutScope.singleTeam) {
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
                    style: const TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                  ),
                ),
              ],
            );
          },
        );
        return false;
      }
      return true;
    } else {
      if (_selectedMatch == null) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Match Required',
          message: 'Please select a match to scout the alliance.',
        );
        return false;
      }
      final allianceTeams = _getAllianceTeamsForMatch(_selectedMatch, _scope);
      if (allianceTeams.isEmpty) {
        ObsidianFeedback.showWarning(
          context,
          title: 'No Teams Found',
          message: 'No teams found for the selected match and alliance.',
        );
        return false;
      }
      return true;
    }
  }

  void _submitQualData() async {
    if (!_validateSelection()) return;

    if (_scope == QualScoutScope.singleTeam) {
      if (!_formKey.currentState!.validate()) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Validation Error',
          message: 'Please complete all required fields.',
        );
        return;
      }
      _formKey.currentState!.save();

      setState(() => _isSubmitting = true);

      final payload = {
        'eventKey': _eventKey ?? '',
        'targetTeamNumber': _selectedTeam!.teamNumber,
        'matchKey': _selectedMatch!.matchKey,
        'matchNumber': _selectedMatch!.matchNumber,
        ..._formData,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await widget.apiService.submitQualScouting(payload);

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      if (response.success) {
        ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
          type: 'qual',
          action: 'direct_upload',
          status: 'synced',
          payload: payload,
        ));
        ObsidianFeedback.showSuccess(
          context,
          title: 'Qual Scouting Saved',
          message: 'Qualitative scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
          statusCode: response.statusCode ?? 200,
        );
        _resetForm();
      } else if (response.isOffline) {
        ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
          type: 'qual',
          action: 'offline_cached',
          status: 'pending',
          payload: payload,
        ));
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Device offline. Saved to offline cache and will sync when online.',
        );
        _resetForm();
      } else {
        ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
          type: 'qual',
          action: 'direct_upload',
          status: 'failed',
          payload: payload,
        ));
        ObsidianFeedback.showError(
          context,
          title: 'Save Failed',
          message: response.message != null && response.message!.isNotEmpty
              ? response.message!
              : 'Failed to submit qualitative scouting data.',
          statusCode: response.statusCode,
          isOffline: response.isOffline,
        );
      }
    } else {
      // Alliance submission
      _formKey.currentState?.save();

      final allianceTeams = _getAllianceTeamsForMatch(_selectedMatch, _scope);
      setState(() => _isSubmitting = true);

      final payloads = <Map<String, dynamic>>[];
      for (final t in allianceTeams) {
        final teamData = _teamFormData[t.teamNumber] ?? {};
        payloads.add({
          'eventKey': _eventKey ?? '',
          'targetTeamNumber': t.teamNumber,
          'matchKey': _selectedMatch!.matchKey,
          'matchNumber': _selectedMatch!.matchNumber,
          ...teamData,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
      }

      final response = await widget.apiService.submitBatchQualScouting(payloads);
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (response.success) {
        for (final p in payloads) {
          ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
            type: 'qual',
            action: 'direct_upload',
            status: 'synced',
            payload: p,
          ));
        }
        final scopeLabel = _getScopeLabel(_scope);
        ObsidianFeedback.showSuccess(
          context,
          title: 'Alliance Saved',
          message: 'Saved qualitative scouting data for $scopeLabel (${allianceTeams.length} teams).',
          statusCode: response.statusCode ?? 200,
        );
        _resetForm();
      } else if (response.isOffline) {
        for (final p in payloads) {
          ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
            type: 'qual',
            action: 'offline_cached',
            status: 'pending',
            payload: p,
          ));
        }
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Device offline. Saved ${allianceTeams.length} team entries to offline cache.',
        );
        _resetForm();
      } else {
        for (final p in payloads) {
          ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
            type: 'qual',
            action: 'direct_upload',
            status: 'failed',
            payload: p,
          ));
        }
        ObsidianFeedback.showError(
          context,
          title: 'Save Failed',
          message: response.message != null && response.message!.isNotEmpty
              ? response.message!
              : 'Failed to submit alliance qualitative scouting data.',
          statusCode: response.statusCode,
          isOffline: response.isOffline,
        );
      }
    }
  }

  void _generateBarcode() {
    if (!_validateSelection()) return;

    if (_scope == QualScoutScope.singleTeam) {
      final payload = {
        'eventKey': _eventKey ?? '',
        'targetTeamNumber': _selectedTeam!.teamNumber,
        'matchKey': _selectedMatch!.matchKey,
        'matchNumber': _selectedMatch!.matchNumber,
        ..._formData,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'type': 'qual-scout',
      };

      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'qual',
        action: 'qr_generated',
        status: 'pending',
        payload: payload,
      ));

      ObsidianBarcodeModal.show(
        context,
        payload: payload,
        typeLabel: context.tr('nav.qual_scout'),
        targetTeamNumber: _selectedTeam!.teamNumber,
        matchKey: _selectedMatch!.displayLabel,
      );
    } else {
      final allianceTeams = _getAllianceTeamsForMatch(_selectedMatch, _scope);
      final payloads = <Map<String, dynamic>>[];
      for (final t in allianceTeams) {
        final teamData = _teamFormData[t.teamNumber] ?? {};
        payloads.add({
          'eventKey': _eventKey ?? '',
          'targetTeamNumber': t.teamNumber,
          'matchKey': _selectedMatch!.matchKey,
          'matchNumber': _selectedMatch!.matchNumber,
          'type': 'qual-scout',
          ...teamData,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
      }

      final allianceBundle = {
        'type': 'qual-alliance',
        'scope': _getScopeCode(_scope),
        'matchKey': _selectedMatch!.matchKey,
        'matchNumber': _selectedMatch!.matchNumber,
        'eventKey': _eventKey ?? '',
        'entries': payloads,
      };

      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'qual',
        action: 'qr_generated',
        status: 'pending',
        payload: allianceBundle,
      ));

      final allTeamNumbers = allianceTeams.map((t) => t.teamNumber).join(', ');

      ObsidianBarcodeModal.show(
        context,
        payload: allianceBundle,
        typeLabel: 'Qual Alliance (${_getScopeLabel(_scope)})',
        targetTeamNumber: allianceTeams.isNotEmpty ? allianceTeams.first.teamNumber : 0,
        teamLabel: allTeamNumbers,
        matchKey: _selectedMatch!.displayLabel,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.warningOrange),
      );
    }

    final fields = (_config?.fields ?? []).where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Scope Selector Card
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('qual_scout.scouting_scope', 'Scouting Target').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: ObsidianUITheme.warningOrange,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10.0),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      _buildScopeChip(QualScoutScope.singleTeam, _tr('qual_scout.scope_single_team', 'Single Team'), Icons.person_outline),
                      _buildScopeChip(QualScoutScope.redAlliance, _tr('qual_scout.scope_red_alliance', 'Red Alliance'), Icons.shield_outlined, color: ObsidianUITheme.errorRed),
                      _buildScopeChip(QualScoutScope.blueAlliance, _tr('qual_scout.scope_blue_alliance', 'Blue Alliance'), Icons.shield_outlined, color: ObsidianUITheme.primaryAccent),
                      _buildScopeChip(QualScoutScope.bothAlliances, _tr('qual_scout.scope_both_alliances', 'Both Alliances'), Icons.all_inclusive_rounded, color: const Color(0xFF9C27B0)),
                    ],
                  ),
                ],
              ),
            ),

            // Selection Card
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_scope == QualScoutScope.singleTeam ? context.tr('nav.qual_scout') : _getScopeLabel(_scope)).toUpperCase(),
                    style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.warningOrange, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
                  if (_scope == QualScoutScope.singleTeam) ...[
                    DropdownButtonFormField<TeamModel>(
                      isExpanded: true,
                      value: _teams.contains(_selectedTeam) ? _selectedTeam : null,
                      dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                      style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                      decoration: InputDecoration(
                        labelText: context.tr('scout.select_team'),
                        labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                        prefixIcon: const Icon(Icons.group_outlined, color: ObsidianUITheme.warningOrange),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                      ),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (team) => setState(() => _selectedTeam = team),
                    ),
                    const SizedBox(height: 12.0),
                  ],
                  DropdownButtonFormField<MatchModel>(
                    isExpanded: true,
                    value: _matches.contains(_selectedMatch) ? _selectedMatch : null,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_match'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: const Icon(Icons.rate_review_outlined, color: ObsidianUITheme.warningOrange),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _matches.map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (match) {
                      setState(() {
                        _selectedMatch = match;
                      });
                    },
                  ),
                ],
              ),
            ),
            if ((_scope == QualScoutScope.singleTeam && (_selectedTeam == null || _selectedMatch == null)) ||
                (_scope != QualScoutScope.singleTeam && _selectedMatch == null))
              ObsidianGlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.warningOrange, size: 36.0),
                        const SizedBox(height: 12.0),
                        Builder(
                          builder: (ctx) {
                            final msg = _scope == QualScoutScope.singleTeam
                                ? 'Select a team and match to start qualitative scouting.'
                                : _tr('qual_scout.select_match_to_load_alliance', 'Select a match to start qualitative alliance scouting.');
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
              if (fields.isNotEmpty) ...[
                if (_scope == QualScoutScope.singleTeam)
                  ObsidianGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('subtitle.qual_scout').toUpperCase(),
                          style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context), letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 12.0),
                        ...fields.map((field) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: DynamicFieldWidget(
                                field: field,
                                currentValue: _formData[field.id],
                                onChanged: (val) => setState(() => _formData[field.id] = val),
                              ),
                            )),
                      ],
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final allianceTeams = _getAllianceTeamsForMatch(_selectedMatch, _scope);
                      if (allianceTeams.isEmpty) {
                        return ObsidianGlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Center(
                              child: Text(
                                _tr('qual_scout.no_teams_in_match', 'No teams found in this match for selected alliance.'),
                                style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                              ),
                            ),
                          ),
                        );
                      }
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.maxWidth;
                          final int crossAxisCount;
                          if (availableWidth >= 960) {
                            crossAxisCount = 3;
                          } else if (availableWidth >= 620) {
                            crossAxisCount = 2;
                          } else {
                            crossAxisCount = 1;
                          }

                          const double spacing = 12.0;
                          final double cardWidth = crossAxisCount == 1
                              ? availableWidth
                              : (availableWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            alignment: WrapAlignment.start,
                            children: allianceTeams.map((team) {
                              final isRed = _isRedAllianceTeam(team);
                              final accentColor = isRed ? ObsidianUITheme.errorRed : ObsidianUITheme.primaryAccent;
                              final posBadge = _getTeamPositionBadge(team);
                              final teamData = _teamFormData.putIfAbsent(team.teamNumber, () => <String, dynamic>{});

                              return SizedBox(
                                width: cardWidth,
                                child: ObsidianGlassCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                        decoration: BoxDecoration(
                                          color: accentColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10.0),
                                          border: Border.all(color: accentColor.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                              decoration: BoxDecoration(
                                                color: accentColor,
                                                borderRadius: BorderRadius.circular(6.0),
                                              ),
                                              child: Text(
                                                posBadge,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                                              ),
                                            ),
                                            const SizedBox(width: 10.0),
                                            Expanded(
                                              child: Text(
                                                'Team ${team.teamNumber}${(team.nickname != null && team.nickname!.isNotEmpty) ? ' (${team.nickname})' : ''}',
                                                style: TextStyle(
                                                  fontSize: 15.0,
                                                  fontWeight: FontWeight.bold,
                                                  color: ObsidianUITheme.getPrimaryTextColor(context),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 14.0),
                                      ...fields.map((field) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                                            child: DynamicFieldWidget(
                                              field: field,
                                              currentValue: teamData[field.id],
                                              onChanged: (val) => setState(() => teamData[field.id] = val),
                                            ),
                                          )),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  ),
              ],
              ObsidianGlassCard(
                onTap: _generateBarcode,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.warningOrange),
                      const SizedBox(width: 10.0),
                      Text(
                        _scope == QualScoutScope.singleTeam
                            ? context.tr('qr.button_label').toUpperCase()
                            : 'GENERATE ALLIANCE QR',
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
                  String saveText;
                  if (_scope == QualScoutScope.singleTeam) {
                    final base = _tr('scout.save_entry', 'Save Entry');
                    saveText = isOnline ? base.toUpperCase() : '$base (OFFLINE)'.toUpperCase();
                  } else if (_scope == QualScoutScope.redAlliance) {
                    final base = _tr('qual_scout.save_red_alliance', 'Save Red Alliance (3 Teams)');
                    saveText = isOnline ? base.toUpperCase() : '$base (OFFLINE)'.toUpperCase();
                  } else if (_scope == QualScoutScope.blueAlliance) {
                    final base = _tr('qual_scout.save_blue_alliance', 'Save Blue Alliance (3 Teams)');
                    saveText = isOnline ? base.toUpperCase() : '$base (OFFLINE)'.toUpperCase();
                  } else {
                    final base = _tr('qual_scout.save_both_alliances', 'Save Both Alliances (6 Teams)');
                    saveText = isOnline ? base.toUpperCase() : '$base (OFFLINE)'.toUpperCase();
                  }

                  return ObsidianGlassCard(
                    onTap: _isSubmitting ? null : _submitQualData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.save_rounded,
                                  color: isOnline ? ObsidianUITheme.primaryAccent : ObsidianUITheme.warningOrange,
                                ),
                                const SizedBox(width: 10.0),
                                Text(
                                  saveText,
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
                          final clearLabel = ctx.tr('qual_scout.clear_form');
                          final displayClear = (clearLabel == 'qual_scout.clear_form' || clearLabel == 'qual_scout.clear') ? 'Clear Form' : clearLabel;
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
  }

  Widget _buildScopeChip(QualScoutScope scope, String label, IconData icon, {Color? color}) {
    final isSelected = _scope == scope;
    final themeColor = color ?? ObsidianUITheme.warningOrange;

    return InkWell(
      onTap: () {
        if (_scope == scope) return;
        setState(() {
          _scope = scope;
        });
      },
      borderRadius: BorderRadius.circular(20.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isSelected ? themeColor.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: isSelected ? themeColor : ObsidianUITheme.getBorderColor(context),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.0,
              color: isSelected ? themeColor : ObsidianUITheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 6.0),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? ObsidianUITheme.getPrimaryTextColor(context) : ObsidianUITheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
