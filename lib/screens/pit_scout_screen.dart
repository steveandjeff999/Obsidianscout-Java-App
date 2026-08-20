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

class PitScoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const PitScoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<PitScoutScreen> createState() => _PitScoutScreenState();
}

class _PitScoutScreenState extends State<PitScoutScreen> {
  final _formKey = GlobalKey<FormState>();
  ScoutingConfigModel? _config;
  List<TeamModel> _teams = [];
  TeamModel? _selectedTeam;
  String? _eventKey;

  bool _isLoading = true;
  bool _isSubmitting = false;
  final Map<String, dynamic> _formData = {};

  @override
  void initState() {
    super.initState();
    _loadPitData();
  }

  @override
  void didUpdateWidget(covariant PitScoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadPitData();
    }
  }

  void _loadPitData() async {
    final eventKey = await widget.apiService.fetchCurrentEventKey();
    final config = await widget.apiService.fetchPitConfig(); // Dedicated /api/pit-config
    final teams = await widget.apiService.fetchTeams(eventKey);

    setState(() {
      _eventKey = eventKey;
      _config = config;
      _teams = teams;
      if (_selectedTeam != null && !_teams.contains(_selectedTeam)) {
        _selectedTeam = null;
      }
      _isLoading = false;

      if (config != null) {
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
    });
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

    setState(() => _isSubmitting = true);

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      ..._formData,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await widget.apiService.submitPitScouting(payload);

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Pit Scouting Saved',
          message: 'Pit scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
          statusCode: response.statusCode ?? 200,
        );
      } else if (response.isOffline) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Device offline. Saved to offline cache and will sync when online.',
        );
      } else {
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
  }

  void _generateBarcode() {
    if (!_validateSelection()) return;

    _formKey.currentState?.save();

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      'type': 'pit-scout',
      ..._formData,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

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
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.secondaryAccent),
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
                    context.tr('nav.pit_scout').toUpperCase(),
                    style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0),
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
                      prefixIcon: const Icon(Icons.build_circle_outlined, color: ObsidianUITheme.secondaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (team) => setState(() => _selectedTeam = team),
                  ),
                ],
              ),
            ),
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
                    const Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.secondaryAccent),
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
          ],
        ),
      ),
    );
  }
}
