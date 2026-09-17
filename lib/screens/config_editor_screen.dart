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
  final String initialKind; // "game", "pit", "qual", "api", "permissions"
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
  late String _activeMainTab; // "config", "api", "permissions"
  late String _activeKind; // "game", "pit", "qual"
  bool _isRawMode = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _rawJsonError;

  ScoutingConfigModel _currentConfig = ScoutingConfigModel();
  final TextEditingController _rawJsonController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();

  // API Settings & Permissions State
  AppSettingsModel _currentSettings = AppSettingsModel();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _eventCodeController = TextEditingController();
  final TextEditingController _timezoneController = TextEditingController();
  final TextEditingController _tbaKeyController = TextEditingController();
  final TextEditingController _firstUsernameController = TextEditingController();
  final TextEditingController _firstKeyController = TextEditingController();
  final TextEditingController _statboticsUrlController = TextEditingController();

  String _preferredSource = 'tba';
  bool _useStatboticsEpa = false;
  bool _useTbaOpr = false;
  bool _chatEnabled = true;
  bool _registrationLocked = false;
  List<String> _scoutPages = [];
  List<String> _analyticsPages = [];
  List<String> _adminPages = [];

  bool _obscureTbaKey = true;
  bool _obscureFirstKey = true;
  bool _isTestingTba = false;
  bool _isTestingFirst = false;
  bool _isTestingStatbotics = false;
  bool _isSavingSettings = false;
  bool _isSavingPermissions = false;

  List<DefaultConfigPresetModel> _presets = [];
  String? _selectedPresetName;

  static const List<Map<String, String>> configurablePages = [
    {'id': 'dashboard', 'label': 'Dashboard'},
    {'id': 'scout', 'label': 'Scout'},
    {'id': 'pit-scout', 'label': 'Pit Scout'},
    {'id': 'qual-scout', 'label': 'Qual Scout'},
    {'id': 'prescout', 'label': 'Pre-Scout'},
    {'id': 'qr-scanner', 'label': 'QR Scanner'},
    {'id': 'scout-history', 'label': 'Scout History'},
    {'id': 'all-data', 'label': 'All Data'},
    {'id': 'match-data', 'label': 'Match Data'},
    {'id': 'qual-data', 'label': 'Qual Data'},
    {'id': 'pit-data', 'label': 'Pit Data'},
    {'id': 'analytics', 'label': 'Analytics'},
    {'id': 'custom-analytics', 'label': 'Custom Analytics'},
    {'id': 'data-validation', 'label': 'Data Validation'},
    {'id': 'graphs', 'label': 'Graphs'},
    {'id': 'events', 'label': 'Events'},
    {'id': 'teams', 'label': 'Teams'},
    {'id': 'rankings', 'label': 'Rankings'},
    {'id': 'qual-rankings', 'label': 'Qual Rankings'},
    {'id': 'matches', 'label': 'Matches'},
    {'id': 'predictor', 'label': 'Predictor'},
    {'id': 'event-predictor', 'label': 'Event Predictor'},
    {'id': 'alliances', 'label': 'Alliances'},
    {'id': 'alliance-selection', 'label': 'Alliance Selection'},
    {'id': 'chat', 'label': 'Chat'},
    {'id': 'backup', 'label': 'Data Sharing'},
    {'id': 'docs', 'label': 'Docs'},
    {'id': 'contact', 'label': 'Contact'},
    {'id': 'admin-settings', 'label': 'Admin Settings'},
    {'id': 'users', 'label': 'Users'},
    {'id': 'banners', 'label': 'Banners'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialKind == 'api') {
      _activeMainTab = 'api';
      _activeKind = 'game';
    } else if (widget.initialKind == 'permissions') {
      _activeMainTab = 'permissions';
      _activeKind = 'game';
    } else {
      _activeMainTab = 'config';
      _activeKind = (widget.initialKind == 'pit' || widget.initialKind == 'qual') ? widget.initialKind : 'game';
    }
    _loadCurrentTabData();
  }

  @override
  void didUpdateWidget(covariant ConfigEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadCurrentTabData();
    }
  }

  @override
  void dispose() {
    _rawJsonController.dispose();
    _titleController.dispose();
    _versionController.dispose();
    _yearController.dispose();
    _eventCodeController.dispose();
    _timezoneController.dispose();
    _tbaKeyController.dispose();
    _firstUsernameController.dispose();
    _firstKeyController.dispose();
    _statboticsUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentTabData() async {
    if (_activeMainTab == 'api' || _activeMainTab == 'permissions') {
      await _loadSettingsData();
    } else {
      await _loadConfigForKind(_activeKind);
    }
  }

  Future<void> _loadSettingsData() async {
    setState(() {
      _isLoading = true;
      _rawJsonError = null;
    });

    final settings = await widget.apiService.fetchSettings();
    if (mounted) {
      if (settings != null) {
        _currentSettings = settings;
      }
      _yearController.text = _currentSettings.year.toString();
      _eventCodeController.text = _currentSettings.eventCode;
      _timezoneController.text = _currentSettings.timezone;
      _preferredSource = _currentSettings.preferredSource.isNotEmpty ? _currentSettings.preferredSource : 'tba';
      _useStatboticsEpa = _currentSettings.useStatboticsEpa;
      _useTbaOpr = _currentSettings.useTbaOpr;
      _chatEnabled = _currentSettings.chatEnabled;
      _registrationLocked = _currentSettings.registrationLocked;
      _scoutPages = List<String>.from(_currentSettings.scoutPages);
      _analyticsPages = List<String>.from(_currentSettings.analyticsPages);
      _adminPages = List<String>.from(_currentSettings.adminPages);
      _tbaKeyController.text = _currentSettings.apiKeys.tbaKey;
      _firstUsernameController.text = _currentSettings.apiKeys.firstUsername;
      _firstKeyController.text = _currentSettings.apiKeys.firstKey;
      _statboticsUrlController.text = _currentSettings.statboticsBaseUrl;

      setState(() {
        _isLoading = false;
      });
    }
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
      // Normalize general/empty phases to teleop, preserve all sections
      final normalizedFields = config.fields.map((f) {
        if (f.phase != null && f.phase!.toLowerCase() == 'general') {
          return f.copyWith(phase: 'teleop');
        }
        return f;
      }).toList();
      final normalizedConfig = config.copyWith(fields: normalizedFields);

      setState(() {
        _currentConfig = normalizedConfig;
        _titleController.text = normalizedConfig.title;
        _versionController.text = normalizedConfig.version.toString();
        _rawJsonController.text = const JsonEncoder.withIndent('  ').convert(normalizedConfig.toJson());
        _isLoading = false;
      });
      _loadPresets();
    }
  }

  Future<void> _loadPresets() async {
    final list = await widget.apiService.fetchDefaultPresets(_activeKind);
    if (mounted) {
      setState(() {
        _presets = list;
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
      // Normalize general/empty phases to teleop, preserve all sections
      final normalizedFields = model.fields.map((f) {
        if (f.phase != null && f.phase!.toLowerCase() == 'general') {
          return f.copyWith(phase: 'teleop');
        }
        return f;
      }).toList();
      final normalizedConfig = model.copyWith(fields: normalizedFields);

      setState(() {
        _currentConfig = normalizedConfig;
        _titleController.text = normalizedConfig.title;
        _versionController.text = normalizedConfig.version.toString();
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

  Future<void> _handleTestTba() async {
    final isFtc = widget.apiService.currentProgram == 'FTC';
    final apiTarget = isFtc ? 'ftcscout' : 'tba';
    final label = isFtc ? 'FTC Scout API' : 'The Blue Alliance';

    setState(() => _isTestingTba = true);
    final response = await widget.apiService.testApiKey(
      api: apiTarget,
      tbaKey: _tbaKeyController.text.trim(),
    );

    if (mounted) {
      setState(() => _isTestingTba = false);
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: '$label Connection Successful',
          message: response.message ?? '$label credentials tested successfully!',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: '$label Connection Failed',
          message: response.message ?? 'Failed to connect to $label.',
        );
      }
    }
  }

  Future<void> _handleTestFirst() async {
    final isFtc = widget.apiService.currentProgram == 'FTC';
    final label = isFtc ? 'FIRST FTC API' : 'FIRST API';

    setState(() => _isTestingFirst = true);
    final response = await widget.apiService.testApiKey(
      api: 'first',
      firstUsername: _firstUsernameController.text.trim(),
      firstKey: _firstKeyController.text.trim(),
    );

    if (mounted) {
      setState(() => _isTestingFirst = false);
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: '$label Connection Successful',
          message: response.message ?? '$label credentials verified successfully!',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: '$label Connection Failed',
          message: response.message ?? 'Failed to authenticate with $label.',
        );
      }
    }
  }

  Future<void> _handleTestStatbotics() async {
    setState(() => _isTestingStatbotics = true);
    final response = await widget.apiService.testApiKey(
      api: 'statbotics',
      statboticsBaseUrl: _statboticsUrlController.text.trim().isNotEmpty
          ? _statboticsUrlController.text.trim()
          : 'https://api.statbotics.io',
    );

    if (mounted) {
      setState(() => _isTestingStatbotics = false);
      if (response.success) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Statbotics API Successful',
          message: response.message ?? 'Statbotics API reachable and verified!',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: 'Statbotics API Failed',
          message: response.message ?? 'Failed to reach Statbotics API.',
        );
      }
    }
  }

  Future<void> _handleSaveSettings() async {
    setState(() => _isSavingSettings = true);

    final updated = _currentSettings.copyWith(
      year: int.tryParse(_yearController.text.trim()) ?? _currentSettings.year,
      eventCode: _eventCodeController.text.trim(),
      timezone: _timezoneController.text.trim().isNotEmpty ? _timezoneController.text.trim() : 'America/New_York',
      preferredSource: _preferredSource,
      useStatboticsEpa: _useStatboticsEpa,
      useTbaOpr: _useTbaOpr,
      chatEnabled: _chatEnabled,
      registrationLocked: _registrationLocked,
      apiKeys: _currentSettings.apiKeys.copyWith(
        tbaKey: _tbaKeyController.text.trim(),
        firstUsername: _firstUsernameController.text.trim(),
        firstKey: _firstKeyController.text.trim(),
      ),
      statboticsBaseUrl: _statboticsUrlController.text.trim().isNotEmpty
          ? _statboticsUrlController.text.trim()
          : 'https://api.statbotics.io',
    );

    final response = await widget.apiService.updateSettings(updated);

    if (mounted) {
      setState(() => _isSavingSettings = false);
      if (response.success) {
        _currentSettings = response.data ?? updated;
        ObsidianFeedback.showSuccess(
          context,
          title: 'API Settings Saved',
          message: 'Season, event code, and API keys updated successfully.',
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
          message: response.message ?? 'Failed to save API settings.',
          statusCode: response.statusCode,
          isOffline: response.isOffline,
        );
      }
    }
  }

  Future<void> _handleSavePermissions() async {
    setState(() => _isSavingPermissions = true);

    final updated = _currentSettings.copyWith(
      chatEnabled: _chatEnabled,
      registrationLocked: _registrationLocked,
      scoutPages: _scoutPages,
      analyticsPages: _analyticsPages,
      adminPages: _adminPages,
    );

    final response = await widget.apiService.updateSettings(updated);

    if (mounted) {
      setState(() => _isSavingPermissions = false);
      if (response.success) {
        _currentSettings = response.data ?? updated;
        ObsidianFeedback.showSuccess(
          context,
          title: 'Permissions Saved',
          message: 'Role page access and permissions updated successfully.',
          statusCode: response.statusCode ?? 200,
        );
      } else if (response.isOffline) {
        _currentSettings = updated;
        ObsidianFeedback.showWarning(
          context,
          title: 'Saved to Offline Cache',
          message: 'Saved to offline cache. Will synchronize when online.',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: 'Save Failed',
          message: response.message ?? 'Failed to save permissions.',
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

  bool get _supportsPoints => _activeKind == 'game';
  bool get _supportsPhases => _activeKind == 'game';

  String _canonicalizeFieldType(String? rawType) {
    if (rawType == null || rawType.isEmpty) return 'text';
    final t = rawType.toLowerCase().trim();
    if (t == 'counter') return 'counter';
    if (t == 'number' || t == 'int' || t == 'integer' || t == 'float') return 'number';
    if (t == 'rating' || t == 'stars' || t == 'star') return 'rating';
    if (t == 'checkbox' || t == 'toggle' || t == 'bool' || t == 'boolean') return 'checkbox';
    if (t == 'select' || t == 'dropdown' || t == 'choice') return 'select';
    if (t == 'section' || t == 'section_header' || t == 'header') return 'section';
    if (t == 'textarea' || t == 'notes' || t == 'note' || t == 'paragraph') return 'textarea';
    if (t == 'text' || t == 'static' || t == 'label') return 'text';
    if (t == 'image' || t == 'photo' || t == 'image_upload') return 'image';
    return t;
  }

  String _slugify(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '');
    final words = cleaned.trim().split(RegExp(r'[\s_-]+'));
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join();
    return first + rest;
  }

  String _ensureUniqueSlug(String base) {
    if (base.isEmpty) return '';
    final existing = _currentConfig.fields.map((f) => f.id).toSet();
    var candidate = base;
    var counter = 2;
    while (existing.contains(candidate)) {
      candidate = '$base$counter';
      counter++;
    }
    return candidate;
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
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text('Delete Field', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
        content: Text('Are you sure you want to delete "$fieldName"?', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('events.cancel'), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx))),
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

  void _addField() {
    final baseId = _ensureUniqueSlug(_supportsPoints ? 'newField' : 'newNote');
    final newField = _supportsPoints
        ? ScoutingFieldModel(
            id: baseId,
            label: 'New Field',
            type: 'counter',
            phase: _supportsPhases ? 'teleop' : null,
            required: false,
            min: 0,
            max: null,
            step: 1,
            pointsPer: 0.0,
          )
        : ScoutingFieldModel(
            id: baseId,
            label: 'New Note',
            type: 'textarea',
            phase: _supportsPhases ? 'teleop' : null,
            required: false,
          );
    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields)..add(newField);
    setState(() {
      _currentConfig = _currentConfig.copyWith(fields: fields);
    });
    _syncVisualToRaw();
  }

  void _addSectionHeader() {
    final baseId = _ensureUniqueSlug(_supportsPhases ? 'sec_teleop' : 'sec_header');
    final newSection = ScoutingFieldModel(
      id: baseId,
      label: 'New Section',
      type: 'section',
      phase: _supportsPhases ? 'teleop' : null,
      required: false,
    );
    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields)..add(newSection);
    setState(() {
      _currentConfig = _currentConfig.copyWith(fields: fields);
    });
    _syncVisualToRaw();
  }

  void _showInspectSchemaDialog(BuildContext context, int version, String? rawJson) {
    final verticalScrollCtrl = ScrollController();
    final horizontalScrollCtrl = ScrollController();

    String formatted = rawJson ?? '{}';
    try {
      formatted = const JsonEncoder.withIndent('  ').convert(jsonDecode(formatted));
    } catch (_) {}

    showDialog(
      context: context,
      builder: (dCtx) {
        final isDark = ObsidianUITheme.isDark(dCtx);
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(dCtx);

        return AlertDialog(
          backgroundColor: ObsidianUITheme.getSurfaceColor(dCtx),
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
            height: MediaQuery.of(dCtx).size.height * 0.65,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ObsidianUITheme.getBorderColor(dCtx)),
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
                ScaffoldMessenger.of(dCtx).showSnackBar(
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
        );
      },
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
        final isDark = ObsidianUITheme.isDark(ctx);
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: ObsidianUITheme.getBorderColor(modalCtx)),
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
                        color: ObsidianUITheme.getTertiaryTextColor(modalCtx),
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
                      builder: (fbCtx, snapshot) {
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
                            itemBuilder: (itemCtx, idx) {
                              final rev = revisions[idx];
                              final isLatest = idx == 0;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.getSurfaceColor(itemCtx),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isLatest ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(itemCtx),
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
                                            Expanded(
                                              child: Text(
                                                rev.title,
                                                style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 14),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
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
                                            side: BorderSide(color: ObsidianUITheme.getBorderColor(itemCtx)),
                                          ),
                                          icon: const Icon(Icons.code_rounded, size: 14),
                                          label: const Text('Inspect Schema', style: TextStyle(fontSize: 11)),
                                          onPressed: () async {
                                            final detail = await widget.apiService.fetchConfigRevisionDetail(rev.id);
                                            if (detail != null && itemCtx.mounted) {
                                              _showInspectSchemaDialog(itemCtx, detail.version, detail.configJson);
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
        final isDark = ObsidianUITheme.isDark(ctx);
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(ctx);
        final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(ctx);
        final borderColor = ObsidianUITheme.getBorderColor(ctx);

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
                builder: (fbCtx, snapshot) {
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
                            color: ObsidianUITheme.getTertiaryTextColor(modalCtx),
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
                          _buildMetricCard('Records', '${status.entryCount}', Colors.cyanAccent, modalCtx),
                          const SizedBox(width: 8),
                          _buildMetricCard('Legacy Keys', '${status.unmatchedDataKeys.length}', ObsidianUITheme.warningOrange, modalCtx),
                          const SizedBox(width: 8),
                          _buildMetricCard('New Fields', '${status.newConfigKeys.length}', ObsidianUITheme.primaryAccent, modalCtx),
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
                                      color: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                          color: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                                  dropdownColor: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                                dropdownColor: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                      color: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                      color: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                      color: ObsidianUITheme.getSurfaceColor(modalCtx),
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
                                    if (ctx.mounted) {
                                      Navigator.of(ctx).pop();
                                    }
                                    if (!mounted) return;
                                    ObsidianFeedback.showSuccess(
                                      context,
                                      title: 'Migration Succeeded',
                                      message: 'Successfully migrated ${response.data!.migratedCount} records for ${_getKindLabel(_activeKind)} (HTTP ${response.statusCode ?? 200})',
                                      statusCode: response.statusCode,
                                    );
                                  } else {
                                    if (!mounted) return;
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
            Text(
              label,
              style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
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
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        title: Text('Import Config JSON', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste your scouting configuration JSON below:', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: importCtrl,
              maxLines: 8,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: ObsidianUITheme.getPrimaryTextColor(ctx)),
              decoration: InputDecoration(
                hintText: '{\n  "version": 1,\n  "title": "ObsidianScout",\n  "fields": [...]\n}',
                hintStyle: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(ctx))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('events.cancel'), style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx))),
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
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Config JSON imported successfully!'), backgroundColor: ObsidianUITheme.primaryAccent),
                );
              } catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(
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
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

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
                        'Admin Settings & Form Editor',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Customize forms, API keys, and user role page permissions',
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Top-Level Navigation Tabs (Scouting configs, API keys, Permissions)
          Row(
            children: [
              _buildTopLevelTab('config', 'Scouting configs', Icons.format_list_bulleted_rounded),
              const SizedBox(width: 6),
              _buildTopLevelTab('api', 'API keys', Icons.api_rounded),
              const SizedBox(width: 6),
              _buildTopLevelTab('permissions', 'Permissions', Icons.security_rounded),
            ],
          ),
          const SizedBox(height: 14),

          if (_activeMainTab == 'config') ...[
            // Sub-tabs for Form Kinds (Game, Pit, Qualitative)
            Row(
              children: [
                _buildKindTab('game', 'Game form', _activeKind == 'game'),
                const SizedBox(width: 6),
                _buildKindTab('pit', 'Pit form', _activeKind == 'pit'),
                const SizedBox(width: 6),
                _buildKindTab('qual', 'Qualitative form', _activeKind == 'qual'),
              ],
            ),
            const SizedBox(height: 10),

            // Mode Toggle (Visual Editor vs Raw JSON)
            _buildEditorModeSwitcher(),
            const SizedBox(height: 14),
          ],

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
              ),
            )
          else if (_activeMainTab == 'api')
            _buildApiSettingsEditor()
          else if (_activeMainTab == 'permissions')
            _buildPermissionsEditor()
          else if (_isRawMode)
            _buildRawEditor()
          else
            _buildVisualEditor(),

          if (_activeMainTab == 'config') ...[
            const SizedBox(height: 14),
            _buildBottomActionBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildTopLevelTab(String tabId, String label, IconData icon) {
    final isActive = _activeMainTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_activeMainTab != tabId) {
            setState(() => _activeMainTab = tabId);
            _loadCurrentTabData();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.25) : ObsidianUITheme.getSurfaceColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getBorderColor(context),
              width: isActive ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isActive ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getSecondaryTextColor(context)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? ObsidianUITheme.primaryAccent : ObsidianUITheme.getPrimaryTextColor(context),
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2) : ObsidianUITheme.getSurfaceColor(context),
            borderRadius: BorderRadius.circular(10),
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
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorModeSwitcher() {
    final isDark = ObsidianUITheme.isDark(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Container(
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
                    Text('Visual Editor', style: TextStyle(color: !_isRawMode ? Colors.white : secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 13)),
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
    );
  }

  Widget _buildVisualEditor() {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    final fields = _currentConfig.fields;
    final hasManualSections = fields.any((f) => _canonicalizeFieldType(f.type) == 'section');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Notice banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Build your scouting form visually. Create fields, labels, ratings, and reorder elements using simple forms.',
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Metadata Card (Title & Version)
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _titleController,
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Config Title',
                        hintText: 'e.g. Season 2026',
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
                    child: TextFormField(
                      controller: _versionController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Config Version',
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
            ],
          ),
        ),

        // Qualitative Only Settings Card
        if (_activeKind == 'qual') ...[
          const SizedBox(height: 12),
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: Text('Enable Robot Role Collection', style: TextStyle(color: primaryTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
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
                Text(
                  'When enabled, scouters can select one or more roles (Cycling, Stealing, Scoring, Feeding, Defending, N/C) for the robot on the qualitative scouting form.',
                  style: TextStyle(color: secondaryTextColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),

        // Form Fields Header and Add Buttons
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Form Fields (${fields.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.title_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                  label: const Text('+ Add Section Header', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: _addSectionHeader,
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  label: const Text('+ Add Field', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: _addField,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (fields.isEmpty)
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
                Text("Tap '+ Add Field' or '+ Add Section Header' above to start building your form.", style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context), fontSize: 11.5)),
              ],
            ),
          )
        else if (hasManualSections || !_supportsPhases)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int index = 0; index < fields.length; index++) ...[
                _buildFieldCard(fields[index], index),
                if (index < fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._buildPhaseGroupedCards('auto', 'Auto'),
              ..._buildPhaseGroupedCards('teleop', 'Teleop'),
              ..._buildPhaseGroupedCards('endgame', 'Endgame'),
              ..._buildPhaseGroupedCards('postmatch', 'Post Match'),
            ],
          ),
      ],
    );
  }

  List<Widget> _buildPhaseGroupedCards(String phaseKey, String phaseTitle) {
    final fields = _currentConfig.fields;
    final groupFields = fields.where((f) {
      final p = (f.phase ?? '').toLowerCase().trim();
      if (phaseKey == 'teleop') {
        return p == 'teleop' || p.isEmpty || p == 'general';
      }
      return p == phaseKey;
    }).toList();

    if (groupFields.isEmpty) return [];

    return [
      Container(
        margin: const EdgeInsets.only(top: 14, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: ObsidianUITheme.primaryAccent, width: 3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.layers_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
            const SizedBox(width: 8),
            Text(phaseTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ObsidianUITheme.primaryAccent)),
          ],
        ),
      ),
      for (final f in groupFields) ...[
        _buildFieldCard(f, fields.indexOf(f)),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _buildFieldCard(ScoutingFieldModel field, int index) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final canonicalType = _canonicalizeFieldType(field.type);
    final isSection = canonicalType == 'section';

    Color badgeColor;
    switch (canonicalType) {
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
      case 'section':
        badgeColor = ObsidianUITheme.primaryAccent;
        break;
      default:
        badgeColor = Colors.blueGrey;
    }

    final displayTitle = field.label.isNotEmpty
        ? field.label
        : (isSection ? 'Section ${index + 1}' : 'Field ${index + 1}');

    return Container(
      decoration: BoxDecoration(
        color: isSection
            ? (isDark ? const Color(0xFF1E2640) : const Color(0xFFEEF2FF))
            : ObsidianUITheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSection ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.5) : borderColor,
          width: isSection ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Row(
            children: [
              Expanded(
                child: Text(
                  displayTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isSection ? ObsidianUITheme.primaryAccent : primaryTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isSection ? 'section header' : canonicalType,
                  style: TextStyle(color: isDark ? badgeColor : ObsidianUITheme.primaryAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: index > 0 ? primaryTextColor : ObsidianUITheme.getTertiaryTextColor(context),
                onPressed: index > 0 ? () => _moveField(index, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: index < _currentConfig.fields.length - 1 ? primaryTextColor : ObsidianUITheme.getTertiaryTextColor(context),
                onPressed: index < _currentConfig.fields.length - 1 ? () => _moveField(index, 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: ObsidianUITheme.errorRed),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _deleteField(index),
              ),
            ],
          ),
          Divider(color: borderColor, height: 16),

          // Label and ID Inputs
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: field.label,
                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: isSection ? 'Section Title' : 'Field Label',
                    hintText: isSection ? 'e.g. Autonomous, Teleop, Endgame' : 'e.g. Teleop Cycles',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                  ),
                  onChanged: (val) {
                    final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                    final oldId = field.id;
                    String newId = oldId;
                    if (oldId.isEmpty || oldId.startsWith('newField') || oldId.startsWith('newNote') || oldId.startsWith('sec_') || oldId.startsWith('field_')) {
                      newId = _slugify(val);
                    }
                    fields[index] = field.copyWith(label: val, id: newId);
                    setState(() {
                      _currentConfig = _currentConfig.copyWith(fields: fields);
                    });
                    _syncVisualToRaw();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('field_id_${field.id}_$index'),
                  initialValue: field.id,
                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Field ID / Slug',
                    hintText: isSection ? 'e.g. sec_teleop' : 'e.g. teleopCycles',
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

          // Type & Phase Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: canonicalType,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 11),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'counter', child: Text('COUNTER (+ / -)')),
                    DropdownMenuItem(value: 'number', child: Text('NUMBER')),
                    DropdownMenuItem(value: 'rating', child: Text('RATING (1-5)')),
                    DropdownMenuItem(value: 'checkbox', child: Text('CHECKBOX / TOGGLE')),
                    DropdownMenuItem(value: 'select', child: Text('DROPDOWN (SELECT)')),
                    DropdownMenuItem(value: 'section', child: Text('SECTION HEADER')),
                    DropdownMenuItem(value: 'text', child: Text('TEXT (STATIC DISPLAY)')),
                    DropdownMenuItem(value: 'textarea', child: Text('TEXTAREA (INPUT)')),
                    DropdownMenuItem(value: 'image', child: Text('IMAGE (PHOTO UPLOAD)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                      var updated = field.copyWith(type: val);
                      if (val == 'text' || val == 'section') {
                        updated = updated.copyWith(required: false);
                      }
                      if (val == 'rating') {
                        updated = updated.copyWith(min: 1, max: 5, step: 1);
                      } else if (val == 'counter') {
                        updated = updated.copyWith(min: 0, step: 1, clearMax: true);
                      } else if (val == 'number') {
                        updated = updated.copyWith(min: 0, max: 10, step: 1);
                      }
                      if (val != 'counter') {
                        updated = updated.copyWith(clearDoubleStep: true);
                      }
                      if (val == 'section' || val == 'text' || val == 'image') {
                        updated = updated.copyWith(
                          clearMin: true,
                          clearMax: true,
                          clearStep: true,
                          clearDoubleStep: true,
                          clearPointsPer: true,
                          options: [],
                        );
                      }
                      if (val == 'select' && updated.options.isEmpty) {
                        updated = updated.copyWith(options: [
                          ScoutingOptionModel(label: 'Option 1', value: 'opt1', points: 0.0),
                          ScoutingOptionModel(label: 'Option 2', value: 'opt2', points: 0.0),
                        ]);
                      } else if (val != 'select') {
                        updated = updated.copyWith(options: []);
                      }
                      fields[index] = updated;
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                      });
                      _syncVisualToRaw();
                    }
                  },
                ),
              ),
              if (_supportsPhases) ...[
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
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(fields: fields);
                      });
                      _syncVisualToRaw();
                    },
                  ),
                ),
              ],
            ],
          ),

          // Required Checkbox (Hidden for text and section)
          if (canonicalType != 'text' && canonicalType != 'section') ...[
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
                Text('Is Required', style: TextStyle(color: primaryTextColor, fontSize: 12.5)),
              ],
            ),
          ],

          // Numeric Bounds Row (Min, Max, Step, Double Step, Points per action)
          if (canonicalType == 'number' || canonicalType == 'counter' || canonicalType == 'rating') ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Min
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Min', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                      const SizedBox(height: 4),
                      TextFormField(
                        initialValue: field.min?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: primaryTextColor, fontSize: 12),
                        decoration: InputDecoration(
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Max with "No limit"
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Max', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                            if (canonicalType == 'counter' || canonicalType == 'number') ...[
                              const SizedBox(width: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: field.max == null,
                                    activeColor: ObsidianUITheme.primaryAccent,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (checked) {
                                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                                      if (checked == true) {
                                        fields[index] = field.copyWith(clearMax: true);
                                      } else {
                                        fields[index] = field.copyWith(max: 10);
                                      }
                                      setState(() {
                                        _currentConfig = _currentConfig.copyWith(fields: fields);
                                      });
                                      _syncVisualToRaw();
                                    },
                                  ),
                                  Text('No limit', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: ValueKey('max_${field.id}_${field.max}'),
                        enabled: field.max != null || canonicalType == 'rating',
                        initialValue: field.max?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: primaryTextColor, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: field.max == null ? 'No limit' : '',
                          isDense: true,
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor.withValues(alpha: 0.3))),
                        ),
                        onChanged: (val) {
                          final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                          final numVal = int.tryParse(val);
                          fields[index] = field.copyWith(max: numVal, clearMax: numVal == null);
                          _currentConfig = _currentConfig.copyWith(fields: fields);
                          _syncVisualToRaw();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Step
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Step', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                      const SizedBox(height: 4),
                      TextFormField(
                        initialValue: field.step?.toString() ?? '1',
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: primaryTextColor, fontSize: 12),
                        decoration: InputDecoration(
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
                    ],
                  ),
                ),
              ],
            ),

            // Double Step (Counter only, with Enable checkbox)
            if (canonicalType == 'counter') ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Double Step', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                              const SizedBox(width: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: field.doubleStep != null,
                                    activeColor: ObsidianUITheme.primaryAccent,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (checked) {
                                      final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                                      if (checked == true) {
                                        fields[index] = field.copyWith(doubleStep: 5);
                                      } else {
                                        fields[index] = field.copyWith(clearDoubleStep: true);
                                      }
                                      setState(() {
                                        _currentConfig = _currentConfig.copyWith(fields: fields);
                                      });
                                      _syncVisualToRaw();
                                    },
                                  ),
                                  Text('Enable', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          key: ValueKey('doubleStep_${field.id}_${field.doubleStep}'),
                          enabled: field.doubleStep != null,
                          initialValue: field.doubleStep?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: primaryTextColor, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: field.doubleStep == null ? 'Disabled' : 'e.g. 5',
                            isDense: true,
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                            disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor.withValues(alpha: 0.3))),
                          ),
                          onChanged: (val) {
                            final fields = List<ScoutingFieldModel>.from(_currentConfig.fields);
                            final numVal = int.tryParse(val);
                            fields[index] = field.copyWith(doubleStep: numVal, clearDoubleStep: numVal == null);
                            _currentConfig = _currentConfig.copyWith(fields: fields);
                            _syncVisualToRaw();
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_supportsPoints) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Points per action', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                          const SizedBox(height: 4),
                          TextFormField(
                            initialValue: field.pointsPer?.toString() ?? '',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: primaryTextColor, fontSize: 12),
                            decoration: InputDecoration(
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
                      ),
                    ),
                  ],
                ],
              ),
            ] else if (_supportsPoints) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Points per action', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: field.pointsPer?.toString() ?? '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: primaryTextColor, fontSize: 12),
                    decoration: InputDecoration(
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
              ),
            ],
          ] else if (_supportsPoints && canonicalType == 'checkbox') ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Points per action', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                const SizedBox(height: 4),
                TextFormField(
                  initialValue: field.pointsPer?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: primaryTextColor, fontSize: 12),
                  decoration: InputDecoration(
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
            ),
          ],

          // Options Builder for Select type
          if (canonicalType == 'select') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _supportsPoints ? 'Options (Label | Value | Points)' : 'Options (Label | Value)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor),
                ),
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
                          final autoVal = (opt.value.isEmpty || opt.value.startsWith('opt_')) ? _slugify(val) : opt.value;
                          opts[optIdx] = opt.copyWith(label: val, value: autoVal);
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
                        key: ValueKey('opt_val_${opt.value}_$optIdx'),
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
      ),
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
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              if (isNarrow) {
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
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
                          _isSaving ? 'Saving...' : 'Save config',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _isSaving ? null : _handleSave,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.transform_rounded, size: 16, color: Colors.cyanAccent),
                            label: const Text(
                              'Data Migration',
                              style: TextStyle(color: Colors.cyanAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            onPressed: _showMigrationModal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.history_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                            label: const Text(
                              'Schema History',
                              style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            onPressed: _showHistoryModal,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
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
                        _isSaving ? 'Saving...' : 'Save config',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      onPressed: _isSaving ? null : _handleSave,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.transform_rounded, size: 16, color: Colors.cyanAccent),
                    label: const Text('Data Migration', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    onPressed: _showMigrationModal,
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.history_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                    label: const Text('Schema History', style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    onPressed: _showHistoryModal,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

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
          const SizedBox(height: 10),

          // Default Presets Dropdown & Reset to Default Button
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedPresetName,
                  isExpanded: true,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 12),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                  ),
                  hint: const Text('-- Reset to Active Default --', style: TextStyle(fontSize: 12)),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('-- Reset to Active Default --', style: TextStyle(fontSize: 12)),
                    ),
                    for (final p in _presets)
                      DropdownMenuItem<String>(
                        value: p.name,
                        child: Text('${p.name}${p.isDefault ? " (Default)" : ""}', style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedPresetName = (val != null && val.isNotEmpty) ? val : null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.warningOrange,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final presetName = _selectedPresetName;
                  final label = (presetName != null && presetName.isNotEmpty) ? "preset '$presetName'" : 'active program default';
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: ObsidianUITheme.getSurfaceColor(c),
                      title: Text('Reset to Default?', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(c))),
                      content: Text('Are you sure you want to reset ${_getKindLabel(_activeKind)} to $label? Any unsaved changes will be overwritten.', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(c))),
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
                    ApiResponse<ScoutingConfigModel> response;
                    if (presetName != null && presetName.isNotEmpty) {
                      response = await widget.apiService.applyDefaultPreset(_activeKind, presetName);
                    } else {
                      response = await widget.apiService.resetConfigToDefault(_activeKind);
                    }
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
                        title: 'Config Reset',
                        message: 'Reset ${_getKindLabel(_activeKind)} to $label successfully.',
                      );
                    } else {
                      _loadConfigForKind(_activeKind);
                      ObsidianFeedback.showApiResponse(context, response, actionName: 'Reset Configuration');
                    }
                  }
                },
                child: const Text(
                  'Reset to Default',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApiSettingsEditor() {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final isFtc = widget.apiService.currentProgram == 'FTC';

    final enteredYear = _yearController.text.trim().isNotEmpty ? _yearController.text.trim() : '2026';
    final enteredCode = _eventCodeController.text.trim();
    final computedEventKey = enteredCode.isNotEmpty ? '$enteredYear$enteredCode' : '$enteredYear(event_code)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.api_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set season, event code, and API keys. When both TBA and FIRST keys are set, sync merges teams and matches (e.g. QM 4 and Qualification 4 dedupe to one row).',
                  style: TextStyle(color: primaryTextColor, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Season & Event Details Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 8),
                  Text('Event & Season Configuration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
              ),
              Divider(color: borderColor, height: 20),

              // Season Year
              TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Season Year',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  hintText: 'e.g. 2026',
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (isFtc) ...[
                const SizedBox(height: 4),
                Text(
                  'The season year is typically the year the season started in (e.g. the 2025-2026 season DECODE presented by RTX is season 2025 in the API).',
                  style: TextStyle(color: secondaryTextColor, fontSize: 11),
                ),
              ],
              const SizedBox(height: 14),

              // Event Code
              TextField(
                controller: _eventCodeController,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Event Code',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  hintText: 'e.g. okok or 2026nytr',
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              Text(
                'Event key is year + code (e.g. $enteredYear + ${enteredCode.isNotEmpty ? enteredCode : 'okok'} -> $computedEventKey).',
                style: TextStyle(color: secondaryTextColor, fontSize: 11),
              ),
              const SizedBox(height: 14),

              // Timezone
              TextField(
                controller: _timezoneController,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Timezone',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  hintText: 'e.g. America/New_York',
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
              ),
              const SizedBox(height: 14),

              // Preferred Source Dropdown
              DropdownButtonFormField<String>(
                initialValue: _preferredSource,
                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Preferred Source',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'tba',
                    child: Text(isFtc ? 'FTC Scout' : 'The Blue Alliance'),
                  ),
                  DropdownMenuItem(
                    value: 'first',
                    child: Text(isFtc ? 'FIRST FTC API' : 'FIRST API'),
                  ),
                  DropdownMenuItem(
                    value: 'both',
                    child: Text(isFtc ? 'Both (FTC Scout + FIRST)' : 'Both (TBA + FIRST)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _preferredSource = val);
                  }
                },
              ),
              const SizedBox(height: 14),

              // Optional Stats
              Text('Optional Stats', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
              const SizedBox(height: 6),
              if (!isFtc) ...[
                CheckboxListTile(
                  title: Text('Use Statbotics EPA', style: TextStyle(color: primaryTextColor, fontSize: 13)),
                  subtitle: Text('Pull expected points added (EPA) metrics for FRC teams', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                  value: _useStatboticsEpa,
                  activeColor: ObsidianUITheme.primaryAccent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) => setState(() => _useStatboticsEpa = val ?? false),
                ),
              ],
              CheckboxListTile(
                title: Text(isFtc ? 'Use FTC Scout OPR' : 'Use TBA OPR', style: TextStyle(color: primaryTextColor, fontSize: 13)),
                subtitle: Text('Pull offensive power rating (OPR) from match results', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                value: _useTbaOpr,
                activeColor: ObsidianUITheme.primaryAccent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) => setState(() => _useTbaOpr = val ?? false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // TBA / FTC Scout Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_rounded, size: 18, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Text(isFtc ? 'FTC Scout' : 'The Blue Alliance (TBA)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
              ),
              Divider(color: borderColor, height: 20),

              if (!isFtc) ...[
                TextField(
                  controller: _tbaKeyController,
                  obscureText: _obscureTbaKey,
                  style: TextStyle(color: primaryTextColor, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'TBA Key',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                    hintText: 'Enter TBA Read Key',
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureTbaKey ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: secondaryTextColor),
                      onPressed: () => setState(() => _obscureTbaKey = !_obscureTbaKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.getSurfaceColor(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    'FTC Scout is a public API that provides event, team, match, and OPR data. No API key required.',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isTestingTba
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent))
                      : const Icon(Icons.wifi_protected_setup_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                  label: Text(
                    isFtc ? 'Test FTC Scout API' : 'Test Connection',
                    style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _isTestingTba ? null : _handleTestTba,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // FIRST API Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded, size: 18, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Text(isFtc ? 'FIRST FTC API' : 'FIRST API', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
              ),
              Divider(color: borderColor, height: 20),

              TextField(
                controller: _firstUsernameController,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'FIRST Username',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _firstKeyController,
                obscureText: _obscureFirstKey,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'FIRST Key',
                  labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureFirstKey ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: secondaryTextColor),
                    onPressed: () => setState(() => _obscureFirstKey = !_obscureFirstKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isTestingFirst
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent))
                      : const Icon(Icons.security_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                  label: Text(
                    isFtc ? 'Test FIRST FTC API' : 'Test FIRST API',
                    style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _isTestingFirst ? null : _handleTestFirst,
                ),
              ),
            ],
          ),
        ),

        // Statbotics Card (FRC Only)
        if (!isFtc) ...[
          const SizedBox(height: 14),
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_rounded, size: 18, color: Colors.lightGreenAccent),
                    const SizedBox(width: 8),
                    Text('Statbotics', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                  ],
                ),
                Divider(color: borderColor, height: 20),

                TextField(
                  controller: _statboticsUrlController,
                  style: TextStyle(color: primaryTextColor, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Statbotics Base URL',
                    labelStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                    hintText: 'https://api.statbotics.io',
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isTestingStatbotics
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent))
                        : const Icon(Icons.speed_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                    label: const Text(
                      'Test Statbotics API',
                      style: TextStyle(color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isTestingStatbotics ? null : _handleTestStatbotics,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.primaryAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSavingSettings
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 20),
            label: Text(
              _isSavingSettings ? 'Saving...' : 'Save API settings',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isSavingSettings ? null : _handleSaveSettings,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsEditor() {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Intro Notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.security_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configure which pages each user role (Scout, Analytics, Admin) can access across the mobile app, desktop app, and website. Permissions are saved and cached locally to apply seamlessly when offline.',
                  style: TextStyle(color: primaryTextColor, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // General Permissions Card
        ObsidianGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 8),
                  Text('General Permissions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                ],
              ),
              Divider(color: borderColor, height: 20),

              CheckboxListTile(
                title: Text('Enable Team Chat', style: TextStyle(color: primaryTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('Allow team members to use chat messaging', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                value: _chatEnabled,
                activeColor: ObsidianUITheme.primaryAccent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) => setState(() => _chatEnabled = val ?? true),
              ),
              CheckboxListTile(
                title: Text('Lock new user registration via create account page', style: TextStyle(color: primaryTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('Prevent uninvited users from self-registering', style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                value: _registrationLocked,
                activeColor: ObsidianUITheme.primaryAccent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) => setState(() => _registrationLocked = val ?? false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3 Role Cards (Scout, Analytics, Admin)
        _buildRolePermissionsCard('Scout Role Access', _scoutPages, 'scout'),
        const SizedBox(height: 14),
        _buildRolePermissionsCard('Analytics Role Access', _analyticsPages, 'analytics'),
        const SizedBox(height: 14),
        _buildRolePermissionsCard('Admin Role Access', _adminPages, 'admin'),
        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.primaryAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSavingPermissions
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 20),
            label: Text(
              _isSavingPermissions ? 'Saving...' : 'Save permissions',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isSavingPermissions ? null : _handleSavePermissions,
          ),
        ),
      ],
    );
  }

  Widget _buildRolePermissionsCard(String title, List<String> rolePages, String roleKey) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                roleKey == 'scout' ? Icons.person_rounded : (roleKey == 'analytics' ? Icons.query_stats_rounded : Icons.admin_panel_settings_rounded),
                size: 18,
                color: ObsidianUITheme.primaryAccent,
              ),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
            ],
          ),
          Divider(color: borderColor, height: 20),

          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: configurablePages.map((page) {
              final pageId = page['id']!;
              final pageLabel = page['label']!;

              bool isDisabled = false;
              bool isChecked = false;

              if (roleKey == 'scout' || roleKey == 'analytics') {
                isDisabled = pageId == 'dashboard' || ['admin-settings', 'users', 'banners'].contains(pageId);
                isChecked = pageId == 'dashboard' ? true : (rolePages.contains(pageId) && !isDisabled);
              } else {
                // Admin
                isDisabled = pageId == 'dashboard' || pageId == 'admin-settings';
                isChecked = isDisabled ? true : rolePages.contains(pageId);
              }

              return SizedBox(
                width: 210,
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: ObsidianUITheme.primaryAccent,
                  title: Text(
                    pageLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDisabled ? secondaryTextColor.withValues(alpha: 0.6) : primaryTextColor,
                    ),
                  ),
                  value: isChecked,
                  onChanged: isDisabled
                      ? null
                      : (val) {
                          setState(() {
                            if (val == true) {
                              if (!rolePages.contains(pageId)) rolePages.add(pageId);
                            } else {
                              rolePages.remove(pageId);
                            }
                          });
                        },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
