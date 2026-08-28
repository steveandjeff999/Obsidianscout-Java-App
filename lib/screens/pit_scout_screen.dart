import 'package:flutter/material.dart';
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
      });
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
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
    if (_config != null) {
      setState(() {
        _formData.clear();
        _resetFormData(_config!);
        _selectedTeam = null;
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

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (response.success) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'pit',
        action: 'direct_upload',
        status: 'synced',
        payload: payload,
      ));
      ObsidianFeedback.showSuccess(
        context,
        title: 'Pit Scouting Saved',
        message: 'Pit scouting data saved successfully (HTTP ${response.statusCode ?? 200})',
        statusCode: response.statusCode ?? 200,
      );
      _resetForm();
    } else if (response.isOffline) {
      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: 'pit',
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
        type: 'pit',
        action: 'direct_upload',
        status: 'failed',
        payload: payload,
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

    ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
      type: 'pit',
      action: 'qr_generated',
      status: 'pending',
      payload: payload,
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
      return const Center(
        child: CircularProgressIndicator(color: ObsidianUITheme.secondaryAccent),
      );
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final fields = (_config?.fields ?? []).where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

    if (isDesktop) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ObsidianGlassCard(
                child: DropdownButtonFormField<TeamModel>(
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
                          const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.secondaryAccent, size: 36.0),
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
                                  const Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.secondaryAccent, size: 20.0),
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
                                      ? const SizedBox(
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
                                        onChanged: (val) => setState(() => _formData[field.id] = val),
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
      );
    }

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
            if (_selectedTeam == null)
              ObsidianGlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.secondaryAccent, size: 36.0),
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
  }
}
