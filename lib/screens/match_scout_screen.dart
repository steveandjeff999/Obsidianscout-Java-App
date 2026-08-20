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

  String _activeTab = 'auto'; // 'auto', 'teleop', 'endgame', 'postmatch'

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
          return opt.points ?? 0.0;
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

    setState(() => _isSubmitting = true);

    final data = <String, dynamic>{
      'eventKey': _eventKey ?? '',
      'matchKey': _selectedMatch!.matchKey,
      'matchNumber': _selectedMatch!.matchNumber,
      'targetTeamNumber': _selectedTeam!.teamNumber,
      ..._formData,
    };

    final response = await widget.apiService.submitMatchScouting(data);

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Match Scouting Saved',
          message: 'Match scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
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
              : 'Failed to submit match scouting data.',
          statusCode: response.statusCode,
          isOffline: response.isOffline,
        );
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
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _activeTab = 'auto';
      });
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _activeTab == tab['key'];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: InkWell(
                onTap: () => setState(() => _activeTab = tab['key']!),
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
                  child: Text(
                    tab['label']!,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? ObsidianUITheme.primaryAccent
                          : ObsidianUITheme.getPrimaryTextColor(context),
                    ),
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
                style: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                  color: ObsidianUITheme.primaryAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Icon(Icons.analytics_outlined, size: 16.0, color: ObsidianUITheme.primaryAccent),
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

  Widget _buildActiveTabFields(List<ScoutingFieldModel> allFields) {
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
          Text(
            sectionTitle,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
              color: accentColor,
              letterSpacing: 1.0,
            ),
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
          else
            ...activeFields.map((field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: DynamicFieldWidget(
                    field: field,
                    currentValue: _formData[field.id],
                    onChanged: (val) => setState(() => _formData[field.id] = val),
                  ),
                )),
        ],
      ),
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
    final points = _calculatePoints();

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
                    value: _teams.contains(_selectedTeam) ? _selectedTeam : null,
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
                    value: _matches.contains(_selectedMatch) ? _selectedMatch : null,
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

            // Tab Row & Scouting Form (Only rendered when team and match are selected)
            if (_selectedTeam == null || _selectedMatch == null)
              ObsidianGlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 36.0),
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
                  return ObsidianGlassCard(
                    onTap: _isSubmitting ? null : _submitData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
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
