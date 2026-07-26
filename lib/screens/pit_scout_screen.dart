import 'package:flutter/material.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../widgets/obsidian_barcode_modal.dart';

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

  void _submitPitData() async {
    if (_selectedTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Team for Pit Inspection'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSubmitting = true);

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      ..._formData,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final success = await widget.apiService.submitPitScouting(payload);

    setState(() => _isSubmitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Pit inspection saved to server!' : 'Saved offline to queue',
          ),
          backgroundColor: success ? ObsidianUITheme.successGreen : ObsidianUITheme.warningOrange,
        ),
      );
    }
  }

  void _generateBarcode() {
    if (_selectedTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Team for Pit Inspection'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    _formKey.currentState?.save();

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      'type': 'pit-scout',
      ..._formData,
      'timestamp': DateTime.now().toIso8601String(),
    };

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: 'Pit Scouting',
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

    final fields = _config?.fields ?? [];

    return SingleChildScrollView(
      padding: EdgeInsets.only(top: widget.isBarsVisible ? 100.0 : 16.0, bottom: widget.isBarsVisible ? 120.0 : 20.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            ObsidianGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PIT INSPECTION TEAM',
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.secondaryAccent, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<TeamModel>(
                    isExpanded: true,
                    initialValue: _selectedTeam,
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      labelText: 'Select Team',
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
                      'ROBOT SPECIFICATIONS & FEATURES',
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
                      'GENERATE QR / JAB CODE',
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
                final faintColor = ObsidianUITheme.getFaintTextColor(context);
                return Opacity(
                  opacity: isOnline ? 1.0 : 0.45,
                  child: ObsidianGlassCard(
                    onTap: (_isSubmitting || !isOnline) ? null : _submitPitData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isOnline ? Icons.save_rounded : Icons.cloud_off_rounded,
                                  color: isOnline ? primaryColor : faintColor,
                                ),
                                const SizedBox(width: 10.0),
                                Text(
                                  isOnline ? 'SAVE PIT INSPECTION' : 'DIRECT UPLOAD (OFFLINE - USE QR CODE ABOVE)',
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
