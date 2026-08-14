import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../widgets/obsidian_barcode_modal.dart';

class MatchScoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const MatchScoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<MatchScoutScreen> createState() => _MatchScoutScreenState();
}

class _MatchScoutScreenState extends State<MatchScoutScreen> {
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
    _loadPageData();
  }

  @override
  void didUpdateWidget(covariant MatchScoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadPageData();
    }
  }

  void _loadPageData() async {
    final eventKey = await widget.apiService.fetchCurrentEventKey();
    final config = await widget.apiService.fetchMatchConfig();
    final teams = await widget.apiService.fetchTeams(eventKey);
    final matches = await widget.apiService.fetchMatches(eventKey);

    setState(() {
      _eventKey = eventKey;
      _config = config;
      _teams = teams;
      _matches = matches;
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

  void _submitData() async {
    if (!_validateSelection()) return;

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSubmitting = true);

    final payload = {
      'event_key': _eventKey ?? '',
      'team_number': _selectedTeam!.teamNumber,
      'match_number': _selectedMatch!.matchNumber,
      'comp_level': _selectedMatch!.compLevel,
      'data': _formData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final success = await widget.apiService.submitMatchScouting(payload);

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('dashboard.sync_complete')),
            backgroundColor: ObsidianUITheme.successGreen,
          ),
        );
        if (_config != null) {
          setState(() {
            _formData.clear();
            for (var f in _config!.fields) {
              final t = f.type.toLowerCase();
              if (t == 'section' || t == 'header' || t == 'divider') continue;
              if (t == 'counter' || t == 'number' || t == 'stepper') {
                _formData[f.id] = f.defaultValue ?? f.min ?? 0;
              } else if (t == 'boolean' || t == 'toggle' || t == 'checkbox') {
                _formData[f.id] = f.defaultValue == true || f.defaultValue == 'true';
              } else {
                _formData[f.id] = f.defaultValue?.toString() ?? '';
              }
            }
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('connection.offline')),
            backgroundColor: ObsidianUITheme.warningOrange,
          ),
        );
      }
    }
  }

  void _generateBarcode() {
    if (!_validateSelection()) return;

    _formKey.currentState?.save();

    final payload = {
      'event_key': _eventKey ?? '',
      'team_number': _selectedTeam!.teamNumber,
      'match_number': _selectedMatch!.matchNumber,
      'comp_level': _selectedMatch!.compLevel,
      'data': _formData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: context.tr('nav.match_scout'),
      targetTeamNumber: _selectedTeam!.teamNumber,
      matchKey: _selectedMatch!.displayLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
      );
    }

    final fields = _config?.fields ?? [];
    final autoFields = fields.where((f) => f.phase?.toLowerCase() == 'auto').toList();
    final teleopFields = fields.where((f) => f.phase?.toLowerCase() == 'teleop').toList();
    final endgameFields = fields.where((f) => f.phase?.toLowerCase() == 'endgame').toList();
    final generalFields = fields.where((f) => f.phase == null || (f.phase!.toLowerCase() != 'auto' && f.phase!.toLowerCase() != 'teleop' && f.phase!.toLowerCase() != 'endgame')).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Team & Match Dropdowns Card
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('dashboard.event_context').toUpperCase(),
                    style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<TeamModel>(
                    isExpanded: true,
                    initialValue: _selectedTeam,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_team'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: const Icon(Icons.group_outlined, color: ObsidianUITheme.primaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (team) => setState(() => _selectedTeam = team),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<MatchModel>(
                    isExpanded: true,
                    initialValue: _selectedMatch,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: context.tr('scout.select_match'),
                      labelStyle: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context)),
                      prefixIcon: const Icon(Icons.sports_esports_outlined, color: ObsidianUITheme.primaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                    ),
                    items: _matches.map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (match) => setState(() => _selectedMatch = match),
                  ),
                ],
              ),
            ),

            // Autonomous Phase
            if (autoFields.isNotEmpty)
              ObsidianGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AUTONOMOUS PERIOD',
                      style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12.0),
                    ...autoFields.map((field) => Padding(
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

            // Teleoperated Phase
            if (teleopFields.isNotEmpty)
              ObsidianGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TELEOPERATED PERIOD',
                      style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12.0),
                    ...teleopFields.map((field) => Padding(
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

            // Endgame Phase
            if (endgameFields.isNotEmpty)
              ObsidianGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ENDGAME PERIOD',
                      style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.successGreen, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12.0),
                    ...endgameFields.map((field) => Padding(
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

            // General Fields
            if (generalFields.isNotEmpty)
              ObsidianGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('scout.title').toUpperCase(),
                      style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 12.0),
                    ...generalFields.map((field) => Padding(
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

            // Generate QR / JAB Code Button Card
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

            // Submit Button
            Builder(
              builder: (context) {
                final isOnline = widget.apiService.isOnline;
                final primaryColor = ObsidianUITheme.getPrimaryTextColor(context);
                final faintColor = ObsidianUITheme.getFaintTextColor(context);
                return Opacity(
                  opacity: isOnline ? 1.0 : 0.45,
                  child: ObsidianGlassCard(
                    onTap: (_isSubmitting || !isOnline) ? null : _submitData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isOnline ? Icons.send_rounded : Icons.cloud_off_rounded,
                                  color: isOnline ? primaryColor : faintColor,
                                ),
                                const SizedBox(width: 10.0),
                                Text(
                                  isOnline ? context.tr('scout.save_entry').toUpperCase() : context.tr('connection.offline').toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.0,
                                    color: isOnline ? primaryColor : faintColor,
                                  ),
                                ),
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
    );
  }
}
