import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/api_response.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

class ConfigEditorScreen extends StatefulWidget {
  final ApiService apiService;
  final String initialKind; // "game", "pit", "qual"
  final bool isVisible;
  final bool isBarsVisible;

  const ConfigEditorScreen({
    super.key,
    required this.apiService,
    this.initialKind = 'game',
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> with SingleTickerProviderStateMixin {
  late String _activeKind; // "game", "pit", "qual"
  bool _isRawMode = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _rawJsonError;

  ScoutingConfigModel _currentConfig = ScoutingConfigModel();
  final TextEditingController _rawJsonController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();

  List<DefaultConfigPresetModel> _presets = [];
  bool _isLoadingPresets = false;

  @override
  void initState() {
    super.initState();
    _activeKind = widget.initialKind;
    _loadConfigForKind(_activeKind);
  }

  @override
  void didUpdateWidget(covariant ConfigEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadConfigForKind(_activeKind);
    }
  }

  @override
  void dispose() {
    _rawJsonController.dispose();
    _titleController.dispose();
    _versionController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigForKind(String kind) async {
    setState(() {
      _isLoading = true;
      _rawJsonError = null;
    });

    ScoutingConfigModel? config;
    if (kind == 'pit') {
      config = await widget.apiService.fetchPitConfig();
    } else if (kind == 'qual') {
      config = await widget.apiService.fetchQualConfig();
    } else {
      config = await widget.apiService.fetchMatchConfig();
    }

    if (config == null) {
      final defaultTitle = kind == 'pit'
          ? 'ObsidianScout Pit Scouting'
          : (kind == 'qual' ? 'ObsidianScout Qualitative Scouting' : 'ObsidianScout');
      config = ScoutingConfigModel(title: defaultTitle, version: 1, fields: []);
    }

    if (mounted) {
      final sanitizedFields = config!.fields.where((f) => f.type.toLowerCase() != 'section').toList();
      final sanitizedConfig = config.copyWith(fields: sanitizedFields);
      setState(() {
        _currentConfig = sanitizedConfig;
        _titleController.text = sanitizedConfig.title;
        _versionController.text = sanitizedConfig.version.toString();
        _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(sanitizedConfig.toJson());
        _isLoading = false;
      });
      _loadPresets();
    }
  }

  Future<void> _loadPresets() async {
    setState(() => _isLoadingPresets = true);
    final list = await widget.apiService.fetchDefaultPresets(_activeKind);
    if (mounted) {
      setState(() {
        _presets = list;
        _isLoadingPresets = false;
      });
    }
  }

  void _syncVisualToRaw() {
    final updated = _currentConfig.copyWith(
      title: _titleController.text.trim(),
      version: int.tryParse(_versionController.text.trim()) ?? _currentConfig.version,
    );
    _currentConfig = updated;
    _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(updated.toJson());
    setState(() => _rawJsonError = null);
  }

  bool _syncRawToVisual() {
    try {
      final text = _rawJsonController.text.trim();
      final Map<String, dynamic> decoded = jsonDecode(text);
      final model = ScoutingConfigModel.fromJson(decoded);
      final sanitizedFields = model.fields.where((f) => f.type.toLowerCase() != 'section').toList();
      final sanitizedConfig = model.copyWith(fields: sanitizedFields);
      setState(() {
        _currentConfig = sanitizedConfig;
        _titleController.text = sanitizedConfig.title;
        _versionController.text = sanitizedConfig.version.toString();
        _rawJsonError = null;
      });
      return true;
    } catch (e) {
      setState(() {
        _rawJsonError = 'Invalid JSON syntax: ${e.toString()}';
      });
      return false;
    }
  }

  Future<void> _handleSave() async {
    if (_isRawMode) {
      if (!_syncRawToVisual()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot save: $_rawJsonError'),
            backgroundColor: ObsidianUITheme.errorRed,
          ),
        );
        return;
      }
    } else {
      _syncVisualToRaw();
    }

    setState(() => _isSaving = true);
    final rawJson = _rawJsonController.text.trim();

    ApiResponse<void> response;
    if (_activeKind == 'pit') {
      response = await widget.apiService.savePitConfig(rawJson);
    } else if (_activeKind == 'qual') {
      response = await widget.apiService.saveQualConfig(rawJson);
    } else {
      response = await widget.apiService.saveMatchConfig(rawJson);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: '${_getKindLabel(_activeKind)} Saved',
          message: '${_getKindLabel(_activeKind)} saved successfully (HTTP ${response.statusCode ?? 200})',
          statusCode: response.statusCode ?? 200,
        );
      } else if (response.isOffline) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Saved to offline cache. Will synchronize when online.',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: 'Save Failed',
          message: response.message != null && response.message!.isNotEmpty
              ? response.message!
              : 'Failed to save ${_getKindLabel(_activeKind)} configuration.',
          statusCode: response.statusCode,
          isOffline: response.isOffline,
        );
      }
    }
  }

  String _getKindLabel(String kind) {
    switch (kind) {
      case 'pit':
        return 'Pit Form';
      case 'qual':
        return 'Qualitative Form';
      default:
        return 'Match Form';
    }
  }

  bool get _supportsPoints => _activeKind != 'qual';
  bool get _supportsPhases => _activeKind == 'game';

  String _slugify(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
    final words = cleaned.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join();
    return first + rest;
  }

  void _moveField(int index, int delta) {
    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= fields.length) return;

    final item = fields.removeAt(index);
    fields.insert(targetIndex, item);

    setState(() {
      _currentConfig = _currentConfig.copyWith(fields: fields);
    });
    _syncVisualToRaw();
  }

  void _deleteField(int index) {
    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
    final fieldName = fields[index].label.isNotEmpty ? fields[index].label : 'Field #${index + 1}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        title: Text('Delete Field', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context))),
        content: Text('Are you sure you want to delete "$fieldName"?', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () {
              Navigator.of(ctx).pop();
              fields.removeAt(index);
              setState(() {
                _currentConfig = _currentConfig.copyWith(fields: fields);
              });
              _syncVisualToRaw();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddFieldDialog() {
    final labelCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    String selectedType = 'counter';
    String selectedPhase = 'teleop';
    bool isRequired = false;
    int? minVal = 0;
    int? maxVal = 10;
    int? stepVal = 1;
    int? doubleStepVal;
    double? pointsVal;
    bool autoId = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = ObsidianUITheme.isDark(context);
            final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
            final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
            final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

            return Material(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Add Custom Field', style: TextStyle(color: primaryTextColor, fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(icon: Icon(Icons.close_rounded, color: secondaryTextColor), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Label Input
                      TextField(
                        controller: labelCtrl,
                        style: TextStyle(color: primaryTextColor),
                        decoration: InputDecoration(
                          labelText: 'Field Label (e.g. Speaker Cycles)',
                          labelStyle: TextStyle(color: secondaryTextColor),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                        ),
                        onChanged: (val) {
                          if (autoId) {
                            idCtrl.text = _slugify(val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Field Slug / ID Input
                      TextField(
                        controller: idCtrl,
                        style: TextStyle(color: primaryTextColor),
                        decoration: InputDecoration(
                          labelText: 'Field ID / Slug (e.g. speakerCycles)',
                          labelStyle: TextStyle(color: secondaryTextColor),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                        ),
                        onChanged: (val) => autoId = false,
                      ),
                      const SizedBox(height: 12),

                      // Type & Phase Row (or Type only if !_supportsPhases)
                      if (_supportsPhases)
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: selectedType,
                                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                                style: TextStyle(color: primaryTextColor),
                                decoration: InputDecoration(
                                  labelText: 'Type',
                                  labelStyle: TextStyle(color: secondaryTextColor),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'counter', child: Text('COUNTER')),
                                  DropdownMenuItem(value: 'number', child: Text('NUMBER')),
                                  DropdownMenuItem(value: 'rating', child: Text('RATING')),
                                  DropdownMenuItem(value: 'checkbox', child: Text('CHECKBOX')),
                                  DropdownMenuItem(value: 'select', child: Text('SELECT')),
                                  DropdownMenuItem(value: 'text', child: Text('TEXT (STATIC)')),
                                  DropdownMenuItem(value: 'textarea', child: Text('TEXTAREA (INPUT)')),
                                  DropdownMenuItem(value: 'image', child: Text('IMAGE (PHOTO UPLOAD)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      selectedType = val;
                                      if (val == 'text') {
                                        isRequired = false;
                                      } else if (val == 'rating') {
                                        minVal = 1;
                                        maxVal = 5;
                                      } else if (val == 'counter') {
                                        minVal = 0;
                                        maxVal = 30;
                                        stepVal = 1;
                                      } else if (val == 'number') {
                                        minVal = 0;
                                        maxVal = 100;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: const ['auto', 'teleop', 'endgame', 'postmatch'].contains(selectedPhase.toLowerCase())
                                    ? selectedPhase.toLowerCase()
                                    : 'teleop',
                                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                                style: TextStyle(color: primaryTextColor),
                                decoration: InputDecoration(
                                  labelText: 'Phase',
                                  labelStyle: TextStyle(color: secondaryTextColor),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                                  DropdownMenuItem(value: 'teleop', child: Text('Teleop')),
                                  DropdownMenuItem(value: 'endgame', child: Text('Endgame')),
                                  DropdownMenuItem(value: 'postmatch', child: Text('Post Match')),
                                ],
                                onChanged: (val) => setModalState(() => selectedPhase = val ?? 'teleop'),
                              ),
                            ),
                          ],
                        )
                      else
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: selectedType,
                          dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                          style: TextStyle(color: primaryTextColor),
                          decoration: InputDecoration(
                            labelText: 'Type',
                            labelStyle: TextStyle(color: secondaryTextColor),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'counter', child: Text('COUNTER')),
                            DropdownMenuItem(value: 'number', child: Text('NUMBER')),
                            DropdownMenuItem(value: 'rating', child: Text('RATING')),
                            DropdownMenuItem(value: 'checkbox', child: Text('CHECKBOX')),
                            DropdownMenuItem(value: 'select', child: Text('SELECT')),
                            DropdownMenuItem(value: 'text', child: Text('TEXT (STATIC)')),
                            DropdownMenuItem(value: 'textarea', child: Text('TEXTAREA (INPUT)')),
                            DropdownMenuItem(value: 'image', child: Text('IMAGE (PHOTO UPLOAD)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedType = val;
                                if (val == 'text') {
                                  isRequired = false;
                                } else if (val == 'rating') {
                                  minVal = 1;
                                  maxVal = 5;
                                } else if (val == 'counter') {
                                  minVal = 0;
                                  maxVal = 30;
                                  stepVal = 1;
                                } else if (val == 'number') {
                                  minVal = 0;
                                  maxVal = 100;
                                }
                              });
                            }
                          },
                        ),
                    if (selectedType != 'text') ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: Text('Required Field', style: TextStyle(color: primaryTextColor, fontSize: 14)),
                        value: isRequired,
                        activeThumbColor: ObsidianUITheme.primaryAccent,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setModalState(() => isRequired = val),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ObsidianUITheme.primaryAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: const Text('Add Field to Form', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        onPressed: () {
                          final label = labelCtrl.text.trim();
                          final id = idCtrl.text.trim().isNotEmpty ? idCtrl.text.trim() : _slugify(label);

                          if (label.isEmpty || id.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter field label and ID')),
                            );
                            return;
                          }

                          List<ScoutingOptionModel> defaultOpts = [];
                          if (selectedType == 'select') {
                            defaultOpts = [
                              ScoutingOptionModel(label: 'Option 1', value: 'opt1', points: 0.0),
                              ScoutingOptionModel(label: 'Option 2', value: 'opt2', points: 0.0),
                            ];
                          }

                          final newField = ScoutingFieldModel(
                            id: id,
                            label: label,
                            type: selectedType,
                            phase: _supportsPhases
                                ? (selectedPhase.isNotEmpty ? (selectedPhase.toLowerCase() == 'general' ? 'teleop' : selectedPhase) : 'teleop')
                                : null,
                            required: selectedType == 'text' ? false : isRequired,
                            min: minVal,
                            max: maxVal,
                            step: stepVal,
                            doubleStep: doubleStepVal,
                            pointsPer: pointsVal,
                            options: defaultOpts,
                          );

                          final fields = List<ScoutingFieldModel>.from(_currentConfig.fields)..add(newField);
                          setState(() {
                            _currentConfig = _currentConfig.copyWith(fields: fields);
                          });
                          _syncVisualToRaw();
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  }

  void _showPresetsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(context);
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_stories_rounded, color: ObsidianUITheme.primaryAccent),
                      const SizedBox(width: 10),
                      Text('Presets & Default Schemas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: ObsidianUITheme.getTertiaryTextColor(context),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Apply an official competition preset or reset the ${_getKindLabel(_activeKind)} to factory defaults.',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              const SizedBox(height: 16),

              // Reset to Default button
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: ObsidianUITheme.warningOrange, width: 1),
                ),
                leading: const Icon(Icons.restart_alt_rounded, color: ObsidianUITheme.warningOrange),
                title: Text('Reset to Official Program Default', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 14)),
                subtitle: Text('Restores default ${_activeKind.toUpperCase()} form preset', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(ctx).pop();
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                      title: Text('Reset Form?', style: TextStyle(color: primaryTextColor)),
                      content: Text('Are you sure you want to reset ${_getKindLabel(_activeKind)} to official default? Unsaved changes will be replaced.', style: TextStyle(color: secondaryTextColor)),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.warningOrange),
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('Reset', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    setState(() => _isLoading = true);
                    final response = await widget.apiService.resetConfigToDefault(_activeKind);
                    if (!mounted) return;
                    if (response.success && response.data != null) {
                      final updated = response.data!;
                      setState(() {
                        _currentConfig = updated;
                        _titleController.text = updated.title;
                        _versionController.text = updated.version.toString();
                        _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(updated.toJson());
                        _isLoading = false;
                      });
                      ObsidianFeedback.showSuccess(
                        context,
                        title: 'Reset Completed',
                        message: 'Reset ${_getKindLabel(_activeKind)} to default successfully (HTTP ${response.statusCode ?? 200})',
                        statusCode: response.statusCode,
                      );
                    } else {
                      _loadConfigForKind(_activeKind);
                      ObsidianFeedback.showApiResponse(
                        context,
                        response,
                        actionName: 'Reset Configuration',
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),

              if (_isLoadingPresets)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)))
              else if (_presets.isNotEmpty) ...[
                Text('Available Season Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _presets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, idx) {
                      final p = _presets[idx];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                        ),
                        leading: const Icon(Icons.bookmark_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                        title: Text(p.name, style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text('${p.program} • ${p.configType} ${p.isDefault ? " (Default)" : ""}', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: ObsidianUITheme.primaryAccent),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                              title: Text('Apply Preset?', style: TextStyle(color: primaryTextColor)),
                              content: Text('Are you sure you want to apply preset "${p.name}" to ${_getKindLabel(_activeKind)}? Unsaved changes will be replaced.', style: TextStyle(color: secondaryTextColor)),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                                  onPressed: () => Navigator.of(c).pop(true),
                                  child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            setState(() => _isLoading = true);
                            final response = await widget.apiService.applyDefaultPreset(_activeKind, p.name);
                            if (!mounted) return;
                            if (response.success && response.data != null) {
                              final updated = response.data!;
                              setState(() {
                                _currentConfig = updated;
                                _titleController.text = updated.title;
                                _versionController.text = updated.version.toString();
                                _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(updated.toJson());
                                _isLoading = false;
                              });
                              ObsidianFeedback.showSuccess(
                                context,
                                title: 'Preset Applied',
                                message: "Applied preset '${p.name}' successfully (HTTP ${response.statusCode ?? 200})",
                                statusCode: response.statusCode,
                              );
                            } else {
                              _loadConfigForKind(_activeKind);
                              ObsidianFeedback.showApiResponse(
                                context,
                                response,
                                actionName: "Apply Preset '${p.name}'",
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showInspectSchemaDialog(BuildContext context, int version, String? rawJson) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final isDark = ObsidianUITheme.isDark(context);
    final verticalScrollCtrl = ScrollController();
    final horizontalScrollCtrl = ScrollController();

    String formatted = rawJson ?? '{}';
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(jsonDecode(formatted));
    } catch (_) {}

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.code_rounded, color: ObsidianUITheme.primaryAccent, size: 22),
            const SizedBox(width: 8),
            Text('Revision v$version Schema', style: TextStyle(color: primaryTextColor, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.65,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
            ),
            child: Scrollbar(
              controller: verticalScrollCtrl,
              thumbVisibility: true,
              interactive: true,
              child: SingleChildScrollView(
                controller: verticalScrollCtrl,
                child: Scrollbar(
                  controller: horizontalScrollCtrl,
                  thumbVisibility: true,
                  interactive: true,
                  notificationPredicate: (notif) => notif.depth == 1,
                  child: SingleChildScrollView(
                    controller: horizontalScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      formatted,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: formatted));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Schema JSON copied to clipboard!'), duration: Duration(seconds: 2)),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showHistoryModal() {
    final historyScrollCtrl = ScrollController();
    final historyFuture = widget.apiService.fetchConfigHistory(_activeKind);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(context);
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                          const SizedBox(width: 10),
                          Text('Schema Revisions History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: ObsidianUITheme.getTertiaryTextColor(context),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inspect historical form schemas and restore past versions for ${_getKindLabel(_activeKind)}.',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: FutureBuilder<List<ConfigRevisionModel>>(
                      future: historyFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
                        }
                        final revisions = snapshot.data ?? [];
                        if (revisions.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_stories_outlined, size: 48, color: ObsidianUITheme.primaryAccent),
                                const SizedBox(height: 12),
                                Text('No Historical Snapshots Recorded Yet', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('Revisions are saved automatically whenever you update the form.', textAlign: TextAlign.center, style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                              ],
                            ),
                          );
                        }

                        return Scrollbar(
                          controller: historyScrollCtrl,
                          thumbVisibility: true,
                          interactive: true,
                          child: ListView.separated(
                            controller: historyScrollCtrl,
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            itemCount: revisions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (c, idx) {
                              final rev = revisions[idx];
                              final isLatest = idx == 0;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.getSurfaceColor(context),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isLatest ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context),
                                    width: isLatest ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text('v${rev.version}', style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(rev.title, style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 14)),
                                          ],
                                        ),
                                        if (isLatest)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                            child: const Text('ACTIVE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Saved by ${rev.savedByUsername ?? "admin"} • ${rev.fieldCount} fields • ${rev.createdAt ?? "Unknown date"}',
                                      style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                    ),
                                    if (rev.changeSummary != null && rev.changeSummary!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Summary: ${rev.changeSummary}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: primaryTextColor)),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                                          ),
                                          icon: const Icon(Icons.code_rounded, size: 14),
                                          label: const Text('Inspect Schema', style: TextStyle(fontSize: 11)),
                                          onPressed: () async {
                                            final detail = await widget.apiService.fetchConfigRevisionDetail(rev.id);
                                            if (detail != null && mounted) {
                                              _showInspectSchemaDialog(context, detail.version, detail.configJson);
                                            }
                                          },
                                        ),
                                        if (!isLatest) ...[
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: ObsidianUITheme.primaryAccent,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            icon: const Icon(Icons.restore_rounded, size: 14, color: Colors.white),
                                            label: const Text('Restore', style: TextStyle(fontSize: 11, color: Colors.white)),
                                            onPressed: () async {
                                              Navigator.of(ctx).pop();
                                              setState(() => _isLoading = true);
                                              final response = await widget.apiService.restoreConfigRevision(rev.id, _activeKind);
                                              if (!mounted) return;
                                              if (response.success && response.data != null) {
                                                final restored = response.data!;
                                                setState(() {
                                                  _currentConfig = restored;
                                                  _titleController.text = restored.title;
                                                  _versionController.text = restored.version.toString();
                                                  _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(restored.toJson());
                                                  _isLoading = false;
                                                });
                                                ObsidianFeedback.showSuccess(
                                                  context,
                                                  title: 'Revision Restored',
                                                  message: 'Restored revision v${rev.version} successfully (HTTP ${response.statusCode ?? 200})',
                                                  statusCode: response.statusCode,
                                                );
                                              } else {
                                                _loadConfigForKind(_activeKind);
                                                ObsidianFeedback.showApiResponse(
                                                  context,
                                                  response,
                                                  actionName: 'Restore Revision v${rev.version}',
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMigrationModal() {
    final migrationScrollCtrl = ScrollController();
    final statusFuture = widget.apiService.fetchConfigMigrationStatus(_activeKind);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = ObsidianUITheme.isDark(context);
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
        final borderColor = ObsidianUITheme.getBorderColor(context);

        final Map<String, String> keyActions = {};
        final Map<String, String> keyTargets = {};
        final Map<String, dynamic> defaultVals = {};
        ConfigMigrationPreviewModel? previewData;
        int previewIndex = 0;
        bool isMigrating = false;
        bool isLoadingPreview = false;
        bool initialPreviewRequested = false;
        bool defaultsInitialized = false;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            void fetchPreview(ConfigSchemaStatusModel status) async {
              setModalState(() => isLoadingPreview = true);
              final mappings = status.dataKeys.map((k) {
                return {
                  'oldKey': k,
                  'newKey': keyActions[k] == 'map' ? (keyTargets[k] ?? k) : null,
                  'action': keyActions[k] ?? 'map',
                };
              }).toList();

              final prev = await widget.apiService.previewConfigMigration(_activeKind, mappings, defaultVals);
              setModalState(() {
                previewData = prev;
                previewIndex = 0;
                isLoadingPreview = false;
              });
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.90,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: borderColor),
              ),
              child: FutureBuilder<ConfigSchemaStatusModel?>(
                future: statusFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent));
                  }
                  final status = snapshot.data;
                  if (status == null) {
                    return Center(
                      child: Text('Failed to load migration status from server.', style: TextStyle(color: ObsidianUITheme.errorRed)),
                    );
                  }

                  // Initialize defaults once
                  if (!defaultsInitialized) {
                    defaultsInitialized = true;
                    for (final k in status.dataKeys) {
                      keyActions.putIfAbsent(k, () => status.unmatchedDataKeys.contains(k) ? 'keep' : 'map');
                      keyTargets.putIfAbsent(k, () => k);
                    }
                  }

                  // Auto-load initial preview once status is loaded
                  if (!initialPreviewRequested) {
                    initialPreviewRequested = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      fetchPreview(status);
                    });
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.transform_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                              const SizedBox(width: 10),
                              Text('Config Data Migration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: ObsidianUITheme.getTertiaryTextColor(context),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      Text(
                        'Migrate stored scouting records into your new form configuration format.',
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 12),

                      // Metrics Overview Grid
                      Row(
                        children: [
                          _buildMetricCard('Records', '${status.entryCount}', Colors.cyanAccent, context),
                          const SizedBox(width: 8),
                          _buildMetricCard('Legacy Keys', '${status.unmatchedDataKeys.length}', ObsidianUITheme.warningOrange, context),
                          const SizedBox(width: 8),
                          _buildMetricCard('New Fields', '${status.newConfigKeys.length}', ObsidianUITheme.primaryAccent, context),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Expanded(
                        child: Scrollbar(
                          controller: migrationScrollCtrl,
                          thumbVisibility: true,
                          interactive: true,
                          child: SingleChildScrollView(
                            controller: migrationScrollCtrl,
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.only(right: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Key Mapping Section
                                Text('Field Key Mappings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor)),
                                const SizedBox(height: 6),
                                if (status.dataKeys.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ObsidianUITheme.getSurfaceColor(context),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Text('No existing stored records found for ${_getKindLabel(_activeKind)}.', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: status.dataKeys.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (c, idx) {
                                      final k = status.dataKeys[idx];
                                      final isUnmatched = status.unmatchedDataKeys.contains(k);
                                      final action = keyActions[k] ?? 'map';
                                      final target = keyTargets[k] ?? k;

                                      return Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: ObsidianUITheme.getSurfaceColor(context),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isUnmatched ? ObsidianUITheme.warningOrange.withValues(alpha: 0.5) : borderColor),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    k,
                                                    style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: isUnmatched ? ObsidianUITheme.warningOrange : primaryTextColor),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                DropdownButton<String>(
                                                  value: action,
                                                  isDense: true,
                                                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                                                  style: TextStyle(fontSize: 12, color: primaryTextColor),
                                                  items: const [
                                                    DropdownMenuItem(value: 'map', child: Text('Map to Field')),
                                                    DropdownMenuItem(value: 'keep', child: Text('Keep as-is')),
                                                    DropdownMenuItem(value: 'delete', child: Text('Delete')),
                                                  ],
                                                  onChanged: (val) {
                                                    if (val != null) {
                                                      setModalState(() => keyActions[k] = val);
                                                      fetchPreview(status);
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                            if (action == 'map') ...[
                                              const SizedBox(height: 6),
                                              DropdownButtonFormField<String>(
                                                initialValue: status.configFields.any((f) => f.id == target) ? target : (status.configFields.isNotEmpty ? status.configFields.first.id : ''),
                                                isDense: true,
                                                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                                                style: TextStyle(fontSize: 12, color: primaryTextColor),
                                                decoration: InputDecoration(
                                                  labelText: 'Target Config Field',
                                                  isDense: true,
                                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                                ),
                                                items: status.configFields.map((f) {
                                                  return DropdownMenuItem(value: f.id, child: Text('${f.label} (${f.id})'));
                                                }).toList(),
                                                onChanged: (val) {
                                                  if (val != null) {
                                                    setModalState(() => keyTargets[k] = val);
                                                    fetchPreview(status);
                                                  }
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),

                                // New Fields Backfill Section
                                if (status.newConfigKeys.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text('New Fields Default Backfill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor)),
                                  const SizedBox(height: 6),
                                  ...status.newConfigKeys.map((nk) {
                                    final field = status.configFields.firstWhere((f) => f.id == nk, orElse: () => ScoutingFieldModel(id: nk, label: nk, type: 'text'));
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TextFormField(
                                        style: TextStyle(fontSize: 12, color: primaryTextColor),
                                        decoration: InputDecoration(
                                          labelText: '${field.label} ($nk) default value',
                                          isDense: true,
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                        ),
                                        onChanged: (val) {
                                          defaultVals[nk] = val;
                                        },
                                      ),
                                    );
                                  }),
                                ],

                                // Transformation Preview Section
                                const SizedBox(height: 18),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.visibility_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                                        const SizedBox(width: 6),
                                        Text('Transformation Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor)),
                                      ],
                                    ),
                                    TextButton.icon(
                                      icon: isLoadingPreview
                                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.refresh_rounded, size: 15),
                                      label: Text(isLoadingPreview ? 'Updating...' : 'Update Preview', style: const TextStyle(fontSize: 12)),
                                      onPressed: isLoadingPreview ? null : () => fetchPreview(status),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                if (isLoadingPreview)
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: ObsidianUITheme.getSurfaceColor(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent)),
                                        const SizedBox(width: 12),
                                        Text('Generating live preview...', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                                      ],
                                    ),
                                  )
                                else if (previewData != null && previewData!.samples.isNotEmpty) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Sample ${previewIndex + 1} of ${previewData!.samples.length}',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ObsidianUITheme.primaryAccent),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                                            onPressed: previewIndex > 0 ? () => setModalState(() => previewIndex--) : null,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                                            onPressed: previewIndex < previewData!.samples.length - 1 ? () => setModalState(() => previewIndex++) : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0A0F1D) : const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('Migrated Schema Output', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          const JsonEncoder.withIndent('  ').convert(previewData!.samples[previewIndex].after),
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.greenAccent, height: 1.35),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (status.entryCount == 0)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: ObsidianUITheme.getSurfaceColor(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'No scouting records exist for ${_getKindLabel(_activeKind)}. Future records will be saved automatically with the current schema.',
                                            style: TextStyle(color: secondaryTextColor, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: ObsidianUITheme.getSurfaceColor(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('No preview sample available.', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                        TextButton(
                                          onPressed: () => fetchPreview(status),
                                          child: const Text('Generate Sample'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Execute Migration Button
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ObsidianUITheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: isMigrating
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.bolt_rounded, color: Colors.white),
                          label: Text(isMigrating ? 'Migrating Records...' : 'Execute Data Migration', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          onPressed: isMigrating
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  setModalState(() => isMigrating = true);

                                  final mappings = status.dataKeys.map((k) {
                                    return {
                                      'oldKey': k,
                                      'newKey': keyActions[k] == 'map' ? keyTargets[k] : null,
                                      'action': keyActions[k] ?? 'map',
                                    };
                                  }).toList();

                                  final response = await widget.apiService.applyConfigMigration(_activeKind, mappings, defaultVals);
                                  setModalState(() => isMigrating = false);

                                  if (response.success && response.data != null && response.data!.success) {
                                    Navigator.of(ctx).pop();
                                    ObsidianFeedback.showSuccess(
                                      context,
                                      title: 'Migration Succeeded',
                                      message: 'Successfully migrated ${response.data!.migratedCount} records for ${_getKindLabel(_activeKind)} (HTTP ${response.statusCode ?? 200})',
                                      statusCode: response.statusCode,
                                    );
                                  } else {
                                    ObsidianFeedback.showError(
                                      context,
                                      title: 'Migration Failed',
                                      message: response.message != null && response.message!.isNotEmpty
                                          ? response.message!
                                          : 'Migration encountered an error on the server.',
                                      statusCode: response.statusCode,
                                      isOffline: response.isOffline,
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: ObsidianUITheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
          ],
        ),
      ),
    );
  }

  void _handleExport() {
    _syncVisualToRaw();
    Clipboard.setData(ClipboardData(text: _rawJsonController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${_getKindLabel(_activeKind)} JSON copied to clipboard!'),
          ],
        ),
        backgroundColor: ObsidianUITheme.secondaryAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleImport() {
    final importCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        title: Text('Import Config JSON', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste your scouting configuration JSON below:', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: importCtrl,
              maxLines: 8,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: ObsidianUITheme.getPrimaryTextColor(context)),
              decoration: InputDecoration(
                hintText: '{\n  "version": 1,\n  "title": "ObsidianScout",\n  "fields": [...]\n}',
                hintStyle: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('events.cancel'), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () {
              try {
                final text = importCtrl.text.trim();
                final Map<String, dynamic> decoded = jsonDecode(text);
                final model = ScoutingConfigModel.fromJson(decoded);
                setState(() {
                  _currentConfig = model;
                  _titleController.text = model.title;
                  _versionController.text = model.version.toString();
                  _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(model.toJson());
                });
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Config JSON imported successfully!'), backgroundColor: ObsidianUITheme.primaryAccent),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invalid JSON: $e'), backgroundColor: ObsidianUITheme.errorRed),
                );
              }
            },
            child: const Text('Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16.0, 4.0, 16.0, widget.isBarsVisible ? 32.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Card
            ObsidianGlassCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.tune_rounded, color: ObsidianUITheme.primaryAccent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scouting Form Editor',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Customize match, pit, and qualitative forms',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Form Kind Selector Pills
            Row(
              children: [
                _buildKindTab('game', 'Match', _activeKind == 'game'),
                const SizedBox(width: 8),
                _buildKindTab('pit', 'Pit', _activeKind == 'pit'),
                const SizedBox(width: 8),
                _buildKindTab('qual', 'Qualitative', _activeKind == 'qual'),
              ],
            ),
            const SizedBox(height: 12),

            // Editor Mode Switcher (Visual vs Raw JSON)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_isRawMode) {
                          if (_syncRawToVisual()) {
                            setState(() => _isRawMode = false);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Fix syntax error before switching: $_rawJsonError'), backgroundColor: ObsidianUITheme.errorRed),
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isRawMode ? ObsidianUITheme.primaryAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.widgets_rounded, size: 16, color: !_isRawMode ? Colors.white : secondaryTextColor),
                            const SizedBox(width: 6),
                            Text('Visual Form Editor', style: TextStyle(color: !_isRawMode ? Colors.white : secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_isRawMode) {
                          _syncVisualToRaw();
                          setState(() => _isRawMode = true);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isRawMode ? ObsidianUITheme.primaryAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.code_rounded, size: 16, color: _isRawMode ? Colors.white : secondaryTextColor),
                            const SizedBox(width: 6),
                            Text('Raw JSON', style: TextStyle(color: _isRawMode ? Colors.white : secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                ),
              )
            else if (_isRawMode)
              _buildRawEditor()
            else
              _buildVisualEditor(),

            const SizedBox(height: 14),

            // Bottom Actions & Toolbar
            _buildBottomActionBar(),
          ],
        ),
      );
  }

  Widget _buildKindTab(String kind, String label, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_activeKind != kind) {
            setState(() => _activeKind = kind);
            _loadConfigForKind(kind);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.25) : ObsidianUITheme.getSurfaceColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context),
              width: isActive ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context),
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisualEditor() {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metadata Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 8),
                  Text('Form Metadata', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
              ),
              Divider(color: borderColor, height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _titleController,
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Config Title',
                        labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                      ),
                      onChanged: (_) => _syncVisualToRaw(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _versionController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Version',
                        labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                      ),
                      onChanged: (_) => _syncVisualToRaw(),
                    ),
                  ),
                ],
              ),

              // Robot Role Collection for Qualitative Form
              if (_activeKind == 'qual') ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  title: Text('Enable Robot Role Collection', style: TextStyle(color: primaryTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('Scouters can pick roles (Cycling, Feeding, Defending, etc.)', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                  value: _currentConfig.enableRobotRoleCollection,
                  activeThumbColor: ObsidianUITheme.primaryAccent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setState(() {
                      _currentConfig = _currentConfig.copyWith(enableRobotRoleCollection: val);
                    });
                    _syncVisualToRaw();
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Fields Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Form Fields (${_currentConfig.fields.length})',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: ObsidianUITheme.primaryAccent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text('Add Field', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _showAddFieldDialog,
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_currentConfig.fields.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ObsidianUITheme.getSurfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.format_list_bulleted_rounded, size: 36, color: ObsidianUITheme.getTertiaryTextColor(context)),
                const SizedBox(height: 8),
                Text('No fields configured yet.', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                const SizedBox(height: 4),
                Text("Tap '+ Add Field' above to start building your form.", style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 11.5)),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int index = 0; index < _currentConfig.fields.length; index++) ...[
                _buildFieldCard(_currentConfig.fields[index], index),
                if (index < _currentConfig.fields.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildFieldCard(ScoutingFieldModel field, int index) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    Color badgeColor;
    switch (field.type) {
      case 'counter':
      case 'number':
        badgeColor = Colors.cyanAccent;
        break;
      case 'rating':
        badgeColor = Colors.amberAccent;
        break;
      case 'checkbox':
        badgeColor = Colors.greenAccent;
        break;
      case 'select':
        badgeColor = Colors.purpleAccent;
        break;
      default:
        badgeColor = ObsidianUITheme.primaryAccent;
    }

    return Material(
      color: ObsidianUITheme.getSurfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: ObsidianUITheme.getBorderColor(context),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              field.type.toUpperCase(),
              style: TextStyle(color: isDark ? badgeColor : ObsidianUITheme.primaryAccent, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            field.label.isNotEmpty ? field.label : 'Field ${index + 1}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
          ),
          subtitle: Text(
            'ID: ${field.id}${_supportsPhases && field.phase != null && field.phase!.isNotEmpty ? " • ${field.phase!.toUpperCase()}" : ""}${field.required ? " • Required" : ""}',
            style: TextStyle(fontSize: 11, color: secondaryTextColor),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                color: index > 0 ? primaryTextColor : ObsidianUITheme.getTertiaryTextColor(context),
                onPressed: index > 0 ? () => _moveField(index, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                color: index < _currentConfig.fields.length - 1 ? primaryTextColor : ObsidianUITheme.getTertiaryTextColor(context),
                onPressed: index < _currentConfig.fields.length - 1 ? () => _moveField(index, 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: ObsidianUITheme.errorRed),
                onPressed: () => _deleteField(index),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _buildFieldEditor(field, index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldEditor(ScoutingFieldModel field, int index) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: borderColor, height: 12),
        const SizedBox(height: 6),

        // Label and ID
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: field.label,
                style: TextStyle(color: primaryTextColor, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Field Label',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
                onChanged: (val) {
                  final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                  fields[index] = field.copyWith(label: val);
                  _currentConfig = _currentConfig.copyWith(fields: fields);
                  _syncVisualToRaw();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: field.id,
                style: TextStyle(color: primaryTextColor, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Field ID / Key',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
                onChanged: (val) {
                  final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                  fields[index] = field.copyWith(id: val);
                  _currentConfig = _currentConfig.copyWith(fields: fields);
                  _syncVisualToRaw();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Phase, Type & Required Row (or Type only if !_supportsPhases)
        if (_supportsPhases)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: const ['counter', 'number', 'rating', 'checkbox', 'select', 'text', 'textarea'].contains(field.type.toLowerCase())
                      ? field.type.toLowerCase()
                      : 'text',
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'counter', child: Text('COUNTER')),
                    DropdownMenuItem(value: 'number', child: Text('NUMBER')),
                    DropdownMenuItem(value: 'rating', child: Text('RATING')),
                    DropdownMenuItem(value: 'checkbox', child: Text('CHECKBOX')),
                    DropdownMenuItem(value: 'select', child: Text('SELECT')),
                    DropdownMenuItem(value: 'text', child: Text('TEXT (STATIC)')),
                    DropdownMenuItem(value: 'textarea', child: Text('TEXTAREA (INPUT)')),
                    DropdownMenuItem(value: 'image', child: Text('IMAGE (PHOTO UPLOAD)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                      fields[index] = field.copyWith(
                        type: val,
                        required: val == 'text' ? false : field.required,
                      );
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                      });
                      _syncVisualToRaw();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: const ['auto', 'teleop', 'endgame', 'postmatch'].contains(field.phase?.toLowerCase() ?? '')
                      ? (field.phase?.toLowerCase() ?? 'teleop')
                      : 'teleop',
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Phase',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'teleop', child: Text('Teleop')),
                    DropdownMenuItem(value: 'endgame', child: Text('Endgame')),
                    DropdownMenuItem(value: 'postmatch', child: Text('Post Match')),
                  ],
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    final newPhase = (val == null || val.isEmpty || val.toLowerCase() == 'general') ? 'teleop' : val;
                    fields[index] = field.copyWith(phase: newPhase);
                    _currentConfig = _currentConfig.copyWith(fields: fields);
                    _syncVisualToRaw();
                  },
                ),
              ),
            ],
          )
        else
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: const ['counter', 'number', 'rating', 'checkbox', 'select', 'text', 'textarea'].contains(field.type.toLowerCase())
                ? field.type.toLowerCase()
                : 'text',
            dropdownColor: ObsidianUITheme.getSurfaceColor(context),
            style: TextStyle(color: primaryTextColor, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Type',
              labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
              isDense: true,
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            items: const [
              DropdownMenuItem(value: 'counter', child: Text('COUNTER')),
              DropdownMenuItem(value: 'number', child: Text('NUMBER')),
              DropdownMenuItem(value: 'rating', child: Text('RATING')),
              DropdownMenuItem(value: 'checkbox', child: Text('CHECKBOX')),
              DropdownMenuItem(value: 'select', child: Text('SELECT')),
              DropdownMenuItem(value: 'text', child: Text('TEXT (STATIC)')),
              DropdownMenuItem(value: 'textarea', child: Text('TEXTAREA (INPUT)')),
              DropdownMenuItem(value: 'image', child: Text('IMAGE (PHOTO UPLOAD)')),
            ],
            onChanged: (val) {
              if (val != null) {
                final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                fields[index] = field.copyWith(
                  type: val,
                  required: val == 'text' ? false : field.required,
                );
                setState(() {
                  _currentConfig = _currentConfig.copyWith(fields: fields);
                });
                _syncVisualToRaw();
              }
            },
          ),

          if (field.type != 'text') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: field.required,
                  activeColor: ObsidianUITheme.primaryAccent,
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    fields[index] = field.copyWith(required: val ?? false);
                    setState(() {
                      _currentConfig = _currentConfig.copyWith(fields: fields);
                    });
                    _syncVisualToRaw();
                  },
                ),
                Text('Required Field', style: TextStyle(color: primaryTextColor, fontSize: 12)),
              ],
            ),
          ],


        // Numeric bounds for Counter / Number / Rating
        if (field.type == 'number' || field.type == 'counter' || field.type == 'rating') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: field.min?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Min',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    final numVal = int.tryParse(val);
                    fields[index] = field.copyWith(min: numVal, clearMin: numVal == null);
                    _currentConfig = _currentConfig.copyWith(fields: fields);
                    _syncVisualToRaw();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: field.max?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Max (Blank=No limit)',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    final numVal = int.tryParse(val);
                    fields[index] = field.copyWith(max: numVal, clearMax: numVal == null);
                    _currentConfig = _currentConfig.copyWith(fields: fields);
                    _syncVisualToRaw();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: field.step?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Step',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    final numVal = int.tryParse(val);
                    fields[index] = field.copyWith(step: numVal, clearStep: numVal == null);
                    _currentConfig = _currentConfig.copyWith(fields: fields);
                    _syncVisualToRaw();
                  },
                ),
              ),
            ],
          ),

          // Double step for counter (fixed label to e.g. 5)
          if (field.type == 'counter') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: field.doubleStep?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: primaryTextColor, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Double Step (e.g. 5)',
                      labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                      isDense: true,
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    ),
                    onChanged: (val) {
                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                      final numVal = int.tryParse(val);
                      fields[index] = field.copyWith(doubleStep: numVal, clearDoubleStep: numVal == null);
                      _currentConfig = _currentConfig.copyWith(fields: fields);
                      _syncVisualToRaw();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],

        // Points per action
        if (_supportsPoints && (field.type == 'counter' || field.type == 'number' || field.type == 'rating' || field.type == 'checkbox')) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: field.pointsPer?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: primaryTextColor, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Scoring Points per action (pointsPer)',
              labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
              hintText: 'e.g. 3.0',
              isDense: true,
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            onChanged: (val) {
              final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
              final dblVal = double.tryParse(val);
              fields[index] = field.copyWith(pointsPer: dblVal, clearPointsPer: dblVal == null);
              _currentConfig = _currentConfig.copyWith(fields: fields);
              _syncVisualToRaw();
            },
          ),
        ],

        // Options Builder for Select type
        if (field.type == 'select') ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dropdown Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor)),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Option', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  final opts = List<ScoutingOptionModel>.from(field.options)
                    ..add(ScoutingOptionModel(
                      label: 'Option ${field.options.length + 1}',
                      value: 'opt_${field.options.length + 1}',
                      points: 0.0,
                    ));
                  final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                  fields[index] = field.copyWith(options: opts);
                  setState(() {
                    _currentConfig = _currentConfig.copyWith(fields: fields);
                  });
                  _syncVisualToRaw();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: field.options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (ctx, optIdx) {
              final opt = field.options[optIdx];
              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: opt.label,
                      style: TextStyle(color: primaryTextColor, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Label',
                        isDense: true,
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                      ),
                      onChanged: (val) {
                        final opts = List<ScoutingOptionModel>.from(field.options);
                        opts[optIdx] = opt.copyWith(label: val);
                        final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                        fields[index] = field.copyWith(options: opts);
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                        _syncVisualToRaw();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: opt.value,
                      style: TextStyle(color: primaryTextColor, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Value',
                        isDense: true,
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                      ),
                      onChanged: (val) {
                        final opts = List<ScoutingOptionModel>.from(field.options);
                        opts[optIdx] = opt.copyWith(value: val);
                        final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                        fields[index] = field.copyWith(options: opts);
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                        _syncVisualToRaw();
                      },
                    ),
                  ),
                  if (_supportsPoints) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        initialValue: opt.points.toString(),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: primaryTextColor, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Pts',
                          isDense: true,
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                        ),
                        onChanged: (val) {
                          final opts = List<ScoutingOptionModel>.from(field.options);
                          opts[optIdx] = opt.copyWith(points: double.tryParse(val) ?? 0.0);
                          final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                          fields[index] = field.copyWith(options: opts);
                          _currentConfig = _currentConfig.copyWith(fields: fields);
                          _syncVisualToRaw();
                        },
                      ),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: ObsidianUITheme.errorRed),
                    onPressed: () {
                      final opts = List<ScoutingOptionModel>.from(field.options)..removeAt(optIdx);
                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                      fields[index] = field.copyWith(options: opts);
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                      });
                      _syncVisualToRaw();
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRawEditor() {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rawJsonError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: ObsidianUITheme.errorRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ObsidianUITheme.errorRed),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: ObsidianUITheme.errorRed, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_rawJsonError!, style: const TextStyle(color: ObsidianUITheme.errorRed, fontSize: 12)),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('JSON Schema Editor', style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13)),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.format_align_left_rounded, size: 16),
              label: const Text('Format / Prettify', style: TextStyle(fontSize: 12)),
              onPressed: () {
                try {
                  final decoded = jsonDecode(_rawJsonController.text);
                  _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(decoded);
                  setState(() => _rawJsonError = null);
                } catch (e) {
                  setState(() => _rawJsonError = 'Cannot format invalid JSON: $e');
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
          ),
          child: TextField(
            controller: _rawJsonController,
            maxLines: 22,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.4,
              color: primaryTextColor,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(16),
              border: InputBorder.none,
            ),
            onChanged: (_) {
              if (_rawJsonError != null) {
                try {
                  jsonDecode(_rawJsonController.text);
                  setState(() => _rawJsonError = null);
                } catch (_) {}
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return ObsidianGlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_rounded, color: Colors.white, size: 20),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Configuration',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _isSaving ? null : _handleSave,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.auto_stories_rounded, color: ObsidianUITheme.primaryAccent, size: 18),
                label: const Text('Presets', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _showPresetsModal,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // History & Migration Tools Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                  label: const Text('Schema History', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _showHistoryModal,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.transform_rounded, size: 16, color: Colors.cyanAccent),
                  label: const Text('Data Migration', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _showMigrationModal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Export & Import Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 15, color: ObsidianUITheme.secondaryAccent),
                  label: const Text('Export JSON', style: TextStyle(color: ObsidianUITheme.secondaryAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                  onPressed: _handleExport,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(Icons.file_upload_outlined, size: 15, color: ObsidianUITheme.getSecondaryTextColor(context)),
                  label: Text('Import JSON', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
                  onPressed: _handleImport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
