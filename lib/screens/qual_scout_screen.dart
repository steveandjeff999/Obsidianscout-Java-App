import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';

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

  TeamModel? _selectedTeam;
  MatchModel? _selectedMatch;

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
    final eventKey = await widget.apiService.fetchCurrentEventKey();
    var config = await widget.apiService.fetchQualConfig();
    final teams = await widget.apiService.fetchTeams(eventKey);
    final matches = await widget.apiService.fetchMatches(eventKey);

    if (config == null || config.fields.isEmpty) {
      config = ScoutingConfigModel(
        title: 'Qualitative Scouting',
        fields: [
          ScoutingFieldModel(
            id: 'driver_skill',
            label: 'Driver Skill (1-5)',
            type: 'counter',
            min: 1,
            max: 5,
            step: 1,
          ),
          ScoutingFieldModel(
            id: 'defense_rating',
            label: 'Defense Rating (1-5)',
            type: 'counter',
            min: 1,
            max: 5,
            step: 1,
          ),
          ScoutingFieldModel(
            id: 'speed_rating',
            label: 'Speed & Agility (1-5)',
            type: 'counter',
            min: 1,
            max: 5,
            step: 1,
          ),
          ScoutingFieldModel(
            id: 'robot_durability',
            label: 'Robot Durability',
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

    setState(() {
      _eventKey = eventKey;
      _config = config;
      _teams = teams;
      _matches = matches;
      if (_selectedTeam != null && !_teams.contains(_selectedTeam)) {
        _selectedTeam = null;
      }
      if (_selectedMatch != null && !_matches.contains(_selectedMatch)) {
        _selectedMatch = null;
      }
      _isLoading = false;

      if (config != null) {
        _resetFormData(config);
      }
    });
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

  void _resetForm() {
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _selectedTeam = null;
        _selectedMatch = null;
      });
    }
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
  }

  void _submitQualData() async {
    if (!_validateSelection()) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Selection Incomplete',
        message: 'Please select a Match and Team before saving.',
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

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Qual Scouting Saved',
          message: 'Qualitative scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
          statusCode: response.statusCode ?? 200,
        );
        _resetForm();
      } else if (response.isOffline) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Device offline. Saved to offline cache and will sync when online.',
        );
        _resetForm();
      } else {
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
    }
  }

  void _generateBarcode() {
    if (!_validateSelection()) return;

    _formKey.currentState?.save();

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      'matchKey': _selectedMatch!.matchKey,
      'matchNumber': _selectedMatch!.matchNumber,
      'type': 'qualitative-scouting',
      ..._formData,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: context.tr('nav.qual_scout'),
      targetTeamNumber: _selectedTeam!.teamNumber,
      matchKey: _selectedMatch!.displayLabel,
    );
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
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('nav.qual_scout').toUpperCase(),
                    style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.warningOrange, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
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
                    onChanged: (match) => setState(() => _selectedMatch = match),
                  ),
                ],
              ),
            ),
            if (_selectedTeam == null || _selectedMatch == null)
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
                            final rawText = ctx.tr('qual-scout.select_a_team_and_match_to_sta');
                            final msg = (rawText == 'qual-scout.select_a_team_and_match_to_sta' || rawText == 'scout.select_a_team_and_match_to_sta')
                                ? 'Select a team and match to start qualitative scouting.'
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
                ),
              ObsidianGlassCard(
                onTap: _generateBarcode,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.warningOrange),
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
                    onTap: _isSubmitting ? null : _submitQualData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
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
}
