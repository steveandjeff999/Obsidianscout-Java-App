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

  const PitScoutScreen({super.key, required this.apiService});

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
      padding: const EdgeInsets.only(top: 100.0, bottom: 120.0),
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
                    dropdownColor: ObsidianUITheme.surface,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Select Team',
                      labelStyle: TextStyle(color: Colors.white60),
                      prefixIcon: Icon(Icons.build_circle_outlined, color: ObsidianUITheme.secondaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
                    const Text(
                      'ROBOT SPECIFICATIONS & FEATURES',
                      style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.0),
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
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: ObsidianUITheme.secondaryAccent),
                    SizedBox(width: 10.0),
                    Text(
                      'GENERATE QR / JAB CODE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            ObsidianGlassCard(
              onTap: _isSubmitting ? null : _submitPitData,
              child: Center(
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_rounded, color: Colors.white),
                          SizedBox(width: 10.0),
                          Text(
                            'SAVE PIT INSPECTION',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
