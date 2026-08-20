import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/dynamic_field_widget.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

enum PrescoutMode {
  dashboard,
  match,
  pit,
  qual,
}

class PrescoutScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const PrescoutScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<PrescoutScreen> createState() => _PrescoutScreenState();
}

class _PrescoutScreenState extends State<PrescoutScreen> {
  PrescoutMode _currentMode = PrescoutMode.dashboard;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Settings & Configs
  String _eventCode = 'prescout';
  String _timezone = 'UTC';
  ScoutingConfigModel? _matchConfig;
  ScoutingConfigModel? _pitConfig;
  ScoutingConfigModel? _qualConfig;

  // Cache entries
  List<dynamic> _matchEntries = [];
  List<dynamic> _pitEntries = [];
  List<dynamic> _qualEntries = [];

  // Form State Controllers
  final TextEditingController _eventCodeController = TextEditingController();
  final TextEditingController _teamNumberController = TextEditingController();
  final TextEditingController _matchNumberController = TextEditingController();

  // Match Scouting Phase Tab
  String _activeTab = 'auto'; // 'auto', 'teleop', 'endgame', 'postmatch'

  // Dynamic Form Field Values
  final Map<String, dynamic> _formData = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant PrescoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _eventCodeController.dispose();
    _teamNumberController.dispose();
    _matchNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final settings = widget.apiService.currentSettings;
    final defaultEvent = await widget.apiService.fetchCurrentEventKey();

    final matchConfig = await widget.apiService.fetchMatchConfig();
    final pitConfig = await widget.apiService.fetchPitConfig();
    final qualConfig = await widget.apiService.fetchQualConfig();

    final matchEntries = await widget.apiService.fetchPrescoutScoutingEntries();
    final pitEntries = await widget.apiService.fetchPrescoutPitScoutingEntries();
    final qualEntries = await widget.apiService.fetchPrescoutQualScoutingEntries();

    if (mounted) {
      setState(() {
        _eventCode = (defaultEvent != null && defaultEvent.isNotEmpty) ? defaultEvent : 'prescout';
        _timezone = settings?.timezone ?? 'UTC';
        _eventCodeController.text = _eventCode;
        _matchConfig = matchConfig;
        _pitConfig = pitConfig;
        _qualConfig = qualConfig;
        _matchEntries = matchEntries;
        _pitEntries = pitEntries;
        _qualEntries = qualEntries;
        _isLoading = false;
      });
    }
  }

  int _getNextMatchNumber(int teamNum, String eventKey, List<dynamic> entries) {
    if (teamNum <= 0) return 1;
    final cleanEvent = eventKey.trim().toLowerCase();
    int maxMatch = 0;

    for (final e in entries) {
      if (e is Map<String, dynamic>) {
        final eTeam = num.tryParse(e['targetTeamNumber']?.toString() ?? '') ?? 0;
        final eEvent = (e['eventKey']?.toString() ?? '').toLowerCase();
        if (eTeam == teamNum && (cleanEvent.isEmpty || eEvent == cleanEvent)) {
          final mNum = num.tryParse(e['matchNumber']?.toString() ?? '') ?? 0;
          if (mNum > maxMatch) maxMatch = mNum.toInt();
        }
      }
    }
    return maxMatch + 1;
  }

  void _switchMode(PrescoutMode mode) {
    setState(() {
      _currentMode = mode;
      _formData.clear();
      _teamNumberController.clear();
      _matchNumberController.clear();
      _activeTab = 'auto';

      ScoutingConfigModel? activeConfig;
      if (mode == PrescoutMode.match) activeConfig = _matchConfig;
      if (mode == PrescoutMode.pit) activeConfig = _pitConfig;
      if (mode == PrescoutMode.qual) activeConfig = _qualConfig;

      if (activeConfig != null) {
        _resetFormData(activeConfig);
      }
    });
  }

  void _onTeamNumberChanged(String val) {
    final teamNum = int.tryParse(val.trim()) ?? 0;
    final eventKey = _eventCodeController.text.trim().toLowerCase();

    if (_currentMode == PrescoutMode.match) {
      if (teamNum > 0) {
        final nextMatch = _getNextMatchNumber(teamNum, eventKey, _matchEntries);
        _matchNumberController.text = nextMatch.toString();
        _loadCachedEntryIfAny(teamNum, nextMatch, eventKey);
      }
    } else if (_currentMode == PrescoutMode.qual) {
      if (teamNum > 0) {
        final nextMatch = _getNextMatchNumber(teamNum, eventKey, _qualEntries);
        _matchNumberController.text = nextMatch.toString();
        _loadCachedEntryIfAny(teamNum, nextMatch, eventKey);
      }
    } else if (_currentMode == PrescoutMode.pit) {
      if (teamNum > 0) {
        _loadCachedEntryIfAny(teamNum, null, eventKey);
      }
    }
    setState(() {});
  }

  void _loadCachedEntryIfAny(int teamNum, int? matchNum, String eventKey) {
    Map<String, dynamic>? foundEntry;

    if (_currentMode == PrescoutMode.match) {
      final targetKey = '${eventKey}_qm$matchNum';
      for (final e in _matchEntries) {
        if (e is Map<String, dynamic>) {
          if (e['targetTeamNumber'] == teamNum && (e['eventKey'] == eventKey || e['matchKey'] == targetKey)) {
            foundEntry = e['data'] is Map<String, dynamic> ? e['data'] as Map<String, dynamic> : e;
            break;
          }
        }
      }
    } else if (_currentMode == PrescoutMode.qual) {
      final targetKey = '${eventKey}_qm$matchNum';
      for (final e in _qualEntries) {
        if (e is Map<String, dynamic>) {
          if (e['targetTeamNumber'] == teamNum && (e['eventKey'] == eventKey || e['matchKey'] == targetKey)) {
            foundEntry = e['data'] is Map<String, dynamic> ? e['data'] as Map<String, dynamic> : e;
            break;
          }
        }
      }
    } else if (_currentMode == PrescoutMode.pit) {
      for (final e in _pitEntries) {
        if (e is Map<String, dynamic>) {
          if (e['targetTeamNumber'] == teamNum && e['eventKey'] == eventKey) {
            foundEntry = e['data'] is Map<String, dynamic> ? e['data'] as Map<String, dynamic> : e;
            break;
          }
        }
      }
    }

    if (foundEntry != null) {
      for (final entry in foundEntry.entries) {
        if (_formData.containsKey(entry.key)) {
          _formData[entry.key] = entry.value;
        }
      }
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
    if (_matchConfig == null) return totals;

    for (final field in _matchConfig!.fields) {
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

  Map<String, dynamic>? _buildPayload() {
    final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
    if (teamNum <= 0) {
      ObsidianFeedback.showWarning(
        context,
        title: 'Team Number Required',
        message: 'Please enter a valid team number before saving.',
      );
      return null;
    }

    final eventKey = _eventCodeController.text.trim().isNotEmpty
        ? _eventCodeController.text.trim().toLowerCase()
        : 'prescout';

    final payload = Map<String, dynamic>.from(_formData);
    payload['eventKey'] = eventKey;
    payload['targetTeamNumber'] = teamNum;

    if (_currentMode == PrescoutMode.match) {
      final matchNum = int.tryParse(_matchNumberController.text.trim()) ??
          _getNextMatchNumber(teamNum, eventKey, _matchEntries);
      payload['matchNumber'] = matchNum;
      payload['matchKey'] = '${eventKey}_qm$matchNum';
      payload['type'] = 'prescout-scout';
    } else if (_currentMode == PrescoutMode.qual) {
      final matchNum = int.tryParse(_matchNumberController.text.trim()) ??
          _getNextMatchNumber(teamNum, eventKey, _qualEntries);
      payload['matchNumber'] = matchNum;
      payload['matchKey'] = '${eventKey}_qm$matchNum';
      payload['type'] = 'prescout-qual';
    } else if (_currentMode == PrescoutMode.pit) {
      payload['type'] = 'prescout-pit';
    }

    return payload;
  }

  Future<void> _handleSubmit({bool isOffline = false}) async {
    final payload = _buildPayload();
    if (payload == null) return;

    setState(() => _isSubmitting = true);

    try {
      if (isOffline) {
        if (_currentMode == PrescoutMode.match) {
          _matchEntries.add({
            'eventKey': payload['eventKey'],
            'targetTeamNumber': payload['targetTeamNumber'],
            'matchNumber': payload['matchNumber'],
            'matchKey': payload['matchKey'],
            'data': payload,
          });
        } else if (_currentMode == PrescoutMode.pit) {
          _pitEntries.add({
            'eventKey': payload['eventKey'],
            'targetTeamNumber': payload['targetTeamNumber'],
            'data': payload,
          });
        } else if (_currentMode == PrescoutMode.qual) {
          _qualEntries.add({
            'eventKey': payload['eventKey'],
            'targetTeamNumber': payload['targetTeamNumber'],
            'matchNumber': payload['matchNumber'],
            'matchKey': payload['matchKey'],
            'data': payload,
          });
        }

        if (mounted) {
          ObsidianFeedback.showWarning(
            context,
            title: 'Saved to Offline Cache',
            message: 'Prescout entry for Team ${payload['targetTeamNumber']} saved locally and will sync when online.',
          );
        }
      } else {
        if (_currentMode == PrescoutMode.match) {
          final res = await widget.apiService.submitPrescoutMatchScouting(payload);
          if (res.success) {
            _matchEntries.add({
              'eventKey': payload['eventKey'],
              'targetTeamNumber': payload['targetTeamNumber'],
              'matchNumber': payload['matchNumber'],
              'matchKey': payload['matchKey'],
              'data': payload,
            });
            if (mounted) {
              ObsidianFeedback.showSuccess(
                context,
                title: 'Match Prescout Saved',
                message: 'Prescout entry saved for Team ${payload['targetTeamNumber']} (Match #${payload['matchNumber']}) (HTTP ${res.statusCode ?? 200})',
                statusCode: res.statusCode ?? 200,
              );
            }
          } else if (res.isOffline) {
            if (mounted) {
              ObsidianFeedback.showWarning(
                context,
                title: 'Saved to Offline Cache',
                message: 'Device offline. Prescout entry saved to offline cache and will sync when online.',
              );
            }
          } else {
            if (mounted) {
              ObsidianFeedback.showError(
                context,
                title: 'Save Failed',
                message: res.message != null && res.message!.isNotEmpty
                    ? res.message!
                    : 'Failed to submit match prescout data.',
                statusCode: res.statusCode,
                isOffline: res.isOffline,
              );
            }
          }
        } else if (_currentMode == PrescoutMode.pit) {
          final res = await widget.apiService.submitPrescoutPitScouting(payload);
          if (res.success) {
            _pitEntries.add({
              'eventKey': payload['eventKey'],
              'targetTeamNumber': payload['targetTeamNumber'],
              'data': payload,
            });
            if (mounted) {
              ObsidianFeedback.showSuccess(
                context,
                title: 'Pit Prescout Saved',
                message: 'Pit prescout entry saved for Team ${payload['targetTeamNumber']} (HTTP ${res.statusCode ?? 200})',
                statusCode: res.statusCode ?? 200,
              );
            }
          } else if (res.isOffline) {
            if (mounted) {
              ObsidianFeedback.showWarning(
                context,
                title: 'Saved to Offline Cache',
                message: 'Device offline. Pit prescout entry saved to offline cache and will sync when online.',
              );
            }
          } else {
            if (mounted) {
              ObsidianFeedback.showError(
                context,
                title: 'Save Failed',
                message: res.message != null && res.message!.isNotEmpty
                    ? res.message!
                    : 'Failed to submit pit prescout data.',
                statusCode: res.statusCode,
                isOffline: res.isOffline,
              );
            }
          }
        } else if (_currentMode == PrescoutMode.qual) {
          final res = await widget.apiService.submitPrescoutQualScouting(payload);
          if (res.success) {
            _qualEntries.add({
              'eventKey': payload['eventKey'],
              'targetTeamNumber': payload['targetTeamNumber'],
              'matchNumber': payload['matchNumber'],
              'matchKey': payload['matchKey'],
              'data': payload,
            });
            if (mounted) {
              ObsidianFeedback.showSuccess(
                context,
                title: 'Qual Prescout Saved',
                message: 'Qual prescout entry saved for Team ${payload['targetTeamNumber']} (Match #${payload['matchNumber']}) (HTTP ${res.statusCode ?? 200})',
                statusCode: res.statusCode ?? 200,
              );
            }
          } else if (res.isOffline) {
            if (mounted) {
              ObsidianFeedback.showWarning(
                context,
                title: 'Saved to Offline Cache',
                message: 'Device offline. Qualitative prescout entry saved to offline cache and will sync when online.',
              );
            }
          } else {
            if (mounted) {
              ObsidianFeedback.showError(
                context,
                title: 'Save Failed',
                message: res.message != null && res.message!.isNotEmpty
                    ? res.message!
                    : 'Failed to submit qualitative prescout data.',
                statusCode: res.statusCode,
                isOffline: res.isOffline,
              );
            }
          }
        }
      }

      // Auto-advance and clear for rapid match entry
      if (_currentMode == PrescoutMode.match || _currentMode == PrescoutMode.qual) {
        final currentMatch = int.tryParse(_matchNumberController.text.trim()) ?? 1;
        _matchNumberController.text = (currentMatch + 1).toString();
      }

      ScoutingConfigModel? activeConfig;
      if (_currentMode == PrescoutMode.match) activeConfig = _matchConfig;
      if (_currentMode == PrescoutMode.pit) activeConfig = _pitConfig;
      if (_currentMode == PrescoutMode.qual) activeConfig = _qualConfig;

      if (activeConfig != null) {
        _resetFormData(activeConfig);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _handleExportJson() {
    final payload = _buildPayload();
    if (payload == null) return;

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    Clipboard.setData(ClipboardData(text: jsonStr));

    ObsidianFeedback.showSuccess(
      context,
      title: 'JSON Exported',
      message: 'Prescout JSON for Team ${payload['targetTeamNumber']} copied to clipboard.',
    );
  }

  void _handleGenerateQr() {
    final payload = _buildPayload();
    if (payload == null) return;

    String typeLabel = 'Match Prescouting';
    String? matchKey = payload['matchKey']?.toString();
    if (_currentMode == PrescoutMode.pit) {
      typeLabel = 'Pit Prescouting';
      matchKey = null;
    } else if (_currentMode == PrescoutMode.qual) {
      typeLabel = 'Qualitative Prescouting';
    }

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: typeLabel,
      targetTeamNumber: payload['targetTeamNumber'] is int ? payload['targetTeamNumber'] as int : int.tryParse(payload['targetTeamNumber'].toString()) ?? 0,
      matchKey: matchKey,
    );
  }

  Future<void> _handleClearForm() async {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.warningOrange, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('scout.clear_form'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
            ),
          ],
        ),
        content: Text(
          context.tr('scout.confirm_clear'),
          style: TextStyle(color: secondaryTextColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: tertiaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.errorRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('scout.clear_form'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ScoutingConfigModel? activeConfig;
      if (_currentMode == PrescoutMode.match) activeConfig = _matchConfig;
      if (_currentMode == PrescoutMode.pit) activeConfig = _pitConfig;
      if (_currentMode == PrescoutMode.qual) activeConfig = _qualConfig;

      if (activeConfig != null) {
        setState(() {
          _resetFormData(activeConfig!);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16.0, 4.0, 16.0, widget.isBarsVisible ? 110.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentMode == PrescoutMode.dashboard) ...[
            _buildDashboardHub(context),
          ] else ...[
            _buildFormHeader(context),
            const SizedBox(height: 14),
            if (_currentMode == PrescoutMode.match) _buildMatchForm(context),
            if (_currentMode == PrescoutMode.pit) _buildPitForm(context),
            if (_currentMode == PrescoutMode.qual) _buildQualForm(context),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardHub(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Prescouting Dashboard Header Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.history_edu_rounded, color: ObsidianUITheme.primaryAccent, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('prescout.prescouting_dashboard'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Prescout other events and teams to feed predictive analytics',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('prescout.select_a_scouting_category_to_'),
                style: TextStyle(fontSize: 13.5, color: secondaryTextColor, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            'SCOUTING CATEGORIES',
            style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w700, color: tertiaryTextColor, letterSpacing: 1.0),
          ),
        ),

        // 1. Match Prescout Card
        ObsidianGlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sports_esports_rounded, color: Colors.amberAccent, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('prescout.match_prescout'),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_matchEntries.length} entries saved',
                          style: TextStyle(fontSize: 11.5, color: tertiaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('prescout.scout_match_play_for_teams_at_'),
                style: TextStyle(fontSize: 13, color: secondaryTextColor, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _switchMode(PrescoutMode.match),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  label: Text(
                    context.tr('prescout.start_match_prescout'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Pit Prescout Card
        ObsidianGlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.build_circle_rounded, color: Colors.cyanAccent, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('prescout.pit_prescout'),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_pitEntries.length} entries saved',
                          style: TextStyle(fontSize: 11.5, color: tertiaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('prescout.record_robot_dimensions_subsys'),
                style: TextStyle(fontSize: 13, color: secondaryTextColor, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _switchMode(PrescoutMode.pit),
                  icon: const Icon(Icons.build_rounded, color: Colors.white),
                  label: Text(
                    context.tr('prescout.start_pit_prescout'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Qual Prescout Card
        ObsidianGlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.lightGreenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.rate_review_rounded, color: Colors.lightGreenAccent, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('prescout.qual_prescout'),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_qualEntries.length} entries saved',
                          style: TextStyle(fontSize: 11.5, color: tertiaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('prescout.add_notes_on_driver_skill_robo'),
                style: TextStyle(fontSize: 13, color: secondaryTextColor, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _switchMode(PrescoutMode.qual),
                  icon: const Icon(Icons.rate_review_rounded, color: Colors.white),
                  label: Text(
                    context.tr('prescout.start_qual_prescout'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormHeader(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    String title = '';
    Color accentColor = ObsidianUITheme.primaryAccent;
    IconData modeIcon = Icons.history_edu_rounded;

    if (_currentMode == PrescoutMode.match) {
      title = context.tr('prescout-scout.match_prescouting');
      accentColor = Colors.amberAccent;
      modeIcon = Icons.sports_esports_rounded;
    } else if (_currentMode == PrescoutMode.pit) {
      title = context.tr('prescout-pit.pit_prescouting');
      accentColor = Colors.cyanAccent;
      modeIcon = Icons.build_circle_rounded;
    } else if (_currentMode == PrescoutMode.qual) {
      title = context.tr('prescout-qual.qualitative_prescouting');
      accentColor = Colors.lightGreenAccent;
      modeIcon = Icons.rate_review_rounded;
    }

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: ObsidianUITheme.primaryAccent,
                tooltip: 'Back to Prescout Dashboard',
                onPressed: () => _switchMode(PrescoutMode.dashboard),
              ),
              const SizedBox(width: 6),
              Icon(modeIcon, color: accentColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Inputs Row: Event Code, Team Number, Match Number (if match/qual), Timezone
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Event Code
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _eventCodeController,
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                  decoration: InputDecoration(
                    labelText: context.tr('prescout-pit.event_code'),
                    labelStyle: TextStyle(fontSize: 12, color: secondaryTextColor),
                    hintText: 'e.g. 2024micmp',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  ),
                  onChanged: (val) {
                    final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
                    if (teamNum > 0) {
                      _onTeamNumberChanged(_teamNumberController.text);
                    }
                  },
                ),
              ),

              // Team Number
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _teamNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                  decoration: InputDecoration(
                    labelText: 'Team #',
                    labelStyle: TextStyle(fontSize: 12, color: secondaryTextColor),
                    hintText: 'e.g. 254',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  ),
                  onChanged: _onTeamNumberChanged,
                ),
              ),

              // Match Number (if match or qual)
              if (_currentMode == PrescoutMode.match || _currentMode == PrescoutMode.qual)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _matchNumberController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: 14, color: primaryTextColor),
                    decoration: InputDecoration(
                      labelText: 'Match #',
                      labelStyle: TextStyle(fontSize: 12, color: secondaryTextColor),
                      hintText: 'Auto',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    ),
                    onChanged: (val) {
                      final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
                      final matchNum = int.tryParse(val.trim());
                      if (teamNum > 0 && matchNum != null) {
                        _loadCachedEntryIfAny(teamNum, matchNum, _eventCodeController.text.trim().toLowerCase());
                        setState(() {});
                      }
                    },
                  ),
                ),

              // Timezone Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 6),
                    Text(
                      _timezone,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatchForm(BuildContext context) {
    final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (teamNum <= 0) {
      return ObsidianGlassCard(
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enter a team number to start scouting. Match number is automatically generated on save.',
                style: TextStyle(fontSize: 13.5, color: secondaryTextColor),
              ),
            ),
          ],
        ),
      );
    }

    final fields = _matchConfig?.fields ?? [];
    final currentPhaseFields = fields.where((f) {
      final t = f.type.toLowerCase();
      if (t == 'section' || t == 'header' || t == 'divider') return false;
      return _getFieldPhase(f) == _activeTab;
    }).toList();

    final postmatchLabel = context.tr('prescout-scout.post_match');
    final tabs = [
      {'key': 'auto', 'label': context.tr('phase.auto')},
      {'key': 'teleop', 'label': context.tr('phase.teleop')},
      {'key': 'endgame', 'label': context.tr('phase.endgame')},
      {'key': 'postmatch', 'label': (postmatchLabel.contains('prescout-scout') || postmatchLabel.contains('prescout_scout')) ? 'Post Match' : postmatchLabel},
    ];

    final points = _calculatePoints();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase Tab Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: tabs.map((tab) {
              final isSelected = _activeTab == tab['key'];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(tab['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _activeTab = tab['key']!);
                  },
                  selectedColor: ObsidianUITheme.primaryAccent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : primaryTextColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Form Fields Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentPhaseFields.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Text('No fields configured for this phase.', style: TextStyle(color: secondaryTextColor)),
                  ),
                )
              else
                ...currentPhaseFields.map((field) {
                  return DynamicFieldWidget(
                    field: field,
                    currentValue: _formData[field.id],
                    onChanged: (val) {
                      setState(() {
                        _formData[field.id] = val;
                      });
                    },
                  );
                }),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Live Points Preview Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('prescout-scout.points_preview'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('prescout-scout.auto_teleop_endgame_and_total_'),
                style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPointMetric('Auto', points['auto'] ?? 0.0, Colors.blueAccent),
                  _buildPointMetric('Teleop', points['teleop'] ?? 0.0, Colors.greenAccent),
                  _buildPointMetric('Endgame', points['endgame'] ?? 0.0, Colors.purpleAccent),
                  _buildPointMetric('Total', points['total'] ?? 0.0, ObsidianUITheme.primaryAccent, isTotal: true),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Action Buttons Row
        _buildActionButtonsRow(context),
      ],
    );
  }

  Widget _buildPitForm(BuildContext context) {
    final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (teamNum <= 0) {
      return ObsidianGlassCard(
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.cyanAccent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enter a team number to start pit prescouting.',
                style: TextStyle(fontSize: 13.5, color: secondaryTextColor),
              ),
            ),
          ],
        ),
      );
    }

    final fields = _pitConfig?.fields ?? [];
    final activeFields = fields.where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: activeFields.map((field) {
              return DynamicFieldWidget(
                field: field,
                currentValue: _formData[field.id],
                onChanged: (val) {
                  setState(() {
                    _formData[field.id] = val;
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        _buildActionButtonsRow(context),
      ],
    );
  }

  Widget _buildQualForm(BuildContext context) {
    final teamNum = int.tryParse(_teamNumberController.text.trim()) ?? 0;
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    if (teamNum <= 0) {
      return ObsidianGlassCard(
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.lightGreenAccent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enter a team number to start scouting. Match number is automatically generated on save.',
                style: TextStyle(fontSize: 13.5, color: secondaryTextColor),
              ),
            ),
          ],
        ),
      );
    }

    final fields = _qualConfig?.fields ?? [];
    final activeFields = fields.where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: activeFields.map((field) {
              return DynamicFieldWidget(
                field: field,
                currentValue: _formData[field.id],
                onChanged: (val) {
                  setState(() {
                    _formData[field.id] = val;
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        _buildActionButtonsRow(context),
      ],
    );
  }

  Widget _buildPointMetric(String label, double value, Color color, {bool isTotal = false}) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final valStr = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, fontWeight: isTotal ? FontWeight.bold : FontWeight.w500, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          valStr,
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtonsRow(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSubmitting ? null : () => _handleSubmit(isOffline: false),
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                label: Text(
                  _isSubmitting ? 'Saving...' : context.tr('scout.save_entry'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: ObsidianUITheme.primaryAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSubmitting ? null : () => _handleSubmit(isOffline: true),
                icon: const Icon(Icons.save_alt_rounded, color: ObsidianUITheme.primaryAccent),
                label: Text(
                  context.tr('scout.save_offline'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handleExportJson,
                icon: const Icon(Icons.download_rounded, size: 18, color: ObsidianUITheme.secondaryAccent),
                label: Text(
                  context.tr('pit-scout.export_json'),
                  style: const TextStyle(fontSize: 12, color: ObsidianUITheme.secondaryAccent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handleGenerateQr,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18, color: Colors.cyanAccent),
                label: Text(
                  context.tr('pit-scout.generate_qr'),
                  style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handleClearForm,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: ObsidianUITheme.errorRed),
                label: Text(
                  context.tr('scout.clear_form'),
                  style: const TextStyle(fontSize: 12, color: ObsidianUITheme.errorRed),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
