import 'package:flutter/material.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/dynamic_field_widget.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';
import '../widgets/obsidian_barcode_modal.dart';

class MatchScoutScreen extends StatefulWidget {
  final ApiService apiService;

  const MatchScoutScreen({super.key, required this.apiService});

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

  void _submitData() async {
    if (_selectedTeam == null || _selectedMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both a Team and a Match'),
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
      'matchKey': _selectedMatch!.matchKey,
      'matchNumber': _selectedMatch!.matchNumber,
      ..._formData,
    };

    final success = await widget.apiService.submitMatchScouting(payload);

    setState(() => _isSubmitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Match scouting entry saved!' : 'Saved locally (Offline mode)',
          ),
          backgroundColor: success ? ObsidianUITheme.successGreen : ObsidianUITheme.warningOrange,
        ),
      );
    }
  }

  void _generateBarcode() {
    if (_selectedTeam == null || _selectedMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both a Team and a Match'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    _formKey.currentState?.save();

    final payload = {
      'eventKey': _eventKey ?? '',
      'targetTeamNumber': _selectedTeam!.teamNumber,
      'matchKey': _selectedMatch!.matchKey,
      'matchNumber': _selectedMatch!.matchNumber,
      'type': 'match-scout',
      ..._formData,
    };

    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: 'Match Scouting',
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
      padding: const EdgeInsets.only(top: 100.0, bottom: 120.0),
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
                  const Text(
                    'EVENT SELECTION',
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
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
                      prefixIcon: Icon(Icons.group_outlined, color: ObsidianUITheme.primaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (team) => setState(() => _selectedTeam = team),
                  ),
                  const SizedBox(height: 12.0),
                  DropdownButtonFormField<MatchModel>(
                    isExpanded: true,
                    initialValue: _selectedMatch,
                    dropdownColor: ObsidianUITheme.surface,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Select Match',
                      labelStyle: TextStyle(color: Colors.white60),
                      prefixIcon: Icon(Icons.sports_esports_outlined, color: ObsidianUITheme.primaryAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
                    const Text(
                      'SCOUTING DETAILS',
                      style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.0),
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

            // Submit Button
            Builder(
              builder: (context) {
                final isOnline = widget.apiService.isOnline;
                return Opacity(
                  opacity: isOnline ? 1.0 : 0.45,
                  child: ObsidianGlassCard(
                    onTap: (_isSubmitting || !isOnline) ? null : _submitData,
                    child: Center(
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isOnline ? Icons.send_rounded : Icons.cloud_off_rounded,
                                  color: isOnline ? Colors.white : Colors.white54,
                                ),
                                const SizedBox(width: 10.0),
                                Text(
                                  isOnline ? 'SUBMIT MATCH DATA' : 'DIRECT UPLOAD (OFFLINE - USE QR CODE ABOVE)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.0,
                                    color: isOnline ? Colors.white : Colors.white54,
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
