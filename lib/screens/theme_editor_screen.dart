import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

class ThemeEditorScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onBack;

  const ThemeEditorScreen({
    super.key,
    required this.apiService,
    this.onBack,
  });

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<ThemePresetModel> _themes = [];
  String _activeThemeName = 'Default';
  int _selectedPresetIndex = 0;

  // Active form state for selected preset
  late TextEditingController _lightAccentCtrl;
  late TextEditingController _lightAccent2Ctrl;
  late TextEditingController _lightAccent3Ctrl;
  late TextEditingController _lightInkCtrl;
  late TextEditingController _lightMutedCtrl;
  late TextEditingController _lightBgCtrl;
  String _lightRadius = '999px';
  String _lightBgMode = 'solid'; // solid, gradient, preset
  String _lightBgSolid = '#ffffff';
  String _lightBgGrad1 = '#ffffff';
  String _lightBgGrad2 = '#f4f4f5';
  double _lightBgAngle = 135.0;

  late TextEditingController _darkAccentCtrl;
  late TextEditingController _darkAccent2Ctrl;
  late TextEditingController _darkAccent3Ctrl;
  late TextEditingController _darkInkCtrl;
  late TextEditingController _darkMutedCtrl;
  late TextEditingController _darkBgCtrl;
  String _darkRadius = '999px';
  String _darkBgMode = 'solid'; // solid, gradient, preset
  String _darkBgSolid = '#09090b';
  String _darkBgGrad1 = '#09090b';
  String _darkBgGrad2 = '#18181b';
  double _darkBgAngle = 135.0;

  bool _previewIsDark = true;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadSettings();
  }

  void _initControllers() {
    _lightAccentCtrl = TextEditingController(text: '#0b8f88');
    _lightAccent2Ctrl = TextEditingController(text: '#f28b35');
    _lightAccent3Ctrl = TextEditingController(text: '#255a9c');
    _lightInkCtrl = TextEditingController(text: '#1d1a17');
    _lightMutedCtrl = TextEditingController(text: '#5f5b55');
    _lightBgCtrl = TextEditingController(text: '#ffffff');

    _darkAccentCtrl = TextEditingController(text: '#3ccfc0');
    _darkAccent2Ctrl = TextEditingController(text: '#f2a353');
    _darkAccent3Ctrl = TextEditingController(text: '#6aa2ff');
    _darkInkCtrl = TextEditingController(text: '#f4f2ed');
    _darkMutedCtrl = TextEditingController(text: '#c3bfb8');
    _darkBgCtrl = TextEditingController(text: '#09090b');
  }

  @override
  void dispose() {
    _lightAccentCtrl.dispose();
    _lightAccent2Ctrl.dispose();
    _lightAccent3Ctrl.dispose();
    _lightInkCtrl.dispose();
    _lightMutedCtrl.dispose();
    _lightBgCtrl.dispose();

    _darkAccentCtrl.dispose();
    _darkAccent2Ctrl.dispose();
    _darkAccent3Ctrl.dispose();
    _darkInkCtrl.dispose();
    _darkMutedCtrl.dispose();
    _darkBgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = widget.apiService.currentSettings ?? await widget.apiService.fetchSettings();
    if (!mounted) return;

    if (settings != null) {
      _themes = List<ThemePresetModel>.from(settings.themes);
      _activeThemeName = settings.activeThemeName;

      if (_themes.isEmpty) {
        final legacyTheme = settings.theme ?? const ThemePresetModel();
        _themes.add(legacyTheme.copyWith(name: 'Default'));
        _activeThemeName = 'Default';
      }

      _selectedPresetIndex = _themes.indexWhere((t) => t.name == _activeThemeName);
      if (_selectedPresetIndex == -1) _selectedPresetIndex = 0;
    } else {
      _themes = [const ThemePresetModel(name: 'Default')];
      _activeThemeName = 'Default';
      _selectedPresetIndex = 0;
    }

    _populateFormFromPreset(_themes[_selectedPresetIndex]);
    setState(() => _isLoading = false);
  }

  void _populateFormFromPreset(ThemePresetModel preset) {
    _lightAccentCtrl.text = preset.lightAccent.isNotEmpty ? preset.lightAccent : '#0b8f88';
    _lightAccent2Ctrl.text = preset.lightAccent2.isNotEmpty ? preset.lightAccent2 : '#f28b35';
    _lightAccent3Ctrl.text = preset.lightAccent3.isNotEmpty ? preset.lightAccent3 : '#255a9c';
    _lightInkCtrl.text = preset.lightInk.isNotEmpty ? preset.lightInk : '#1d1a17';
    _lightMutedCtrl.text = preset.lightMuted.isNotEmpty ? preset.lightMuted : '#5f5b55';
    _lightRadius = preset.btnRadius.isNotEmpty ? preset.btnRadius : '999px';
    _parseAndPopulateBg(isDark: false, bgValue: preset.lightBg);

    _darkAccentCtrl.text = preset.darkAccent.isNotEmpty ? preset.darkAccent : '#3ccfc0';
    _darkAccent2Ctrl.text = preset.darkAccent2.isNotEmpty ? preset.darkAccent2 : '#f2a353';
    _darkAccent3Ctrl.text = preset.darkAccent3.isNotEmpty ? preset.darkAccent3 : '#6aa2ff';
    _darkInkCtrl.text = preset.darkInk.isNotEmpty ? preset.darkInk : '#f4f2ed';
    _darkMutedCtrl.text = preset.darkMuted.isNotEmpty ? preset.darkMuted : '#c3bfb8';
    _darkRadius = preset.btnRadius.isNotEmpty ? preset.btnRadius : '999px';
    _parseAndPopulateBg(isDark: true, bgValue: preset.darkBg);
  }

  void _parseAndPopulateBg({required bool isDark, required String bgValue}) {
    final clean = bgValue.trim();
    if (isDark) {
      _darkBgCtrl.text = clean.isNotEmpty ? clean : '#09090b';
      if (clean.contains('gradient')) {
        _darkBgMode = 'gradient';
        final match = RegExp(r'linear-gradient\((\d+)deg,\s*(#[a-fA-F0-9]{3,8})\s*(?:\d+%)?,\s*(#[a-fA-F0-9]{3,8})').firstMatch(clean);
        if (match != null) {
          _darkBgAngle = double.tryParse(match.group(1) ?? '135') ?? 135.0;
          _darkBgGrad1 = match.group(2) ?? '#09090b';
          _darkBgGrad2 = match.group(3) ?? '#18181b';
        }
      } else {
        _darkBgMode = 'solid';
        _darkBgSolid = clean.isNotEmpty ? clean : '#09090b';
      }
    } else {
      _lightBgCtrl.text = clean.isNotEmpty ? clean : '#ffffff';
      if (clean.contains('gradient')) {
        _lightBgMode = 'gradient';
        final match = RegExp(r'linear-gradient\((\d+)deg,\s*(#[a-fA-F0-9]{3,8})\s*(?:\d+%)?,\s*(#[a-fA-F0-9]{3,8})').firstMatch(clean);
        if (match != null) {
          _lightBgAngle = double.tryParse(match.group(1) ?? '135') ?? 135.0;
          _lightBgGrad1 = match.group(2) ?? '#ffffff';
          _lightBgGrad2 = match.group(3) ?? '#f4f4f5';
        }
      } else {
        _lightBgMode = 'solid';
        _lightBgSolid = clean.isNotEmpty ? clean : '#ffffff';
      }
    }
  }

  void _generateBgValue({required bool isDark}) {
    if (isDark) {
      if (_darkBgMode == 'solid') {
        _darkBgCtrl.text = _darkBgSolid;
      } else if (_darkBgMode == 'gradient') {
        _darkBgCtrl.text = 'linear-gradient(${_darkBgAngle.round()}deg, $_darkBgGrad1 0%, $_darkBgGrad2 100%)';
      }
    } else {
      if (_lightBgMode == 'solid') {
        _lightBgCtrl.text = _lightBgSolid;
      } else if (_lightBgMode == 'gradient') {
        _lightBgCtrl.text = 'linear-gradient(${_lightBgAngle.round()}deg, $_lightBgGrad1 0%, $_lightBgGrad2 100%)';
      }
    }
  }

  void _saveCurrentPresetFromForm() {
    if (_selectedPresetIndex < 0 || _selectedPresetIndex >= _themes.length) return;
    _generateBgValue(isDark: false);
    _generateBgValue(isDark: true);

    _themes[_selectedPresetIndex] = _themes[_selectedPresetIndex].copyWith(
      lightAccent: _lightAccentCtrl.text.trim(),
      lightAccent2: _lightAccent2Ctrl.text.trim(),
      lightAccent3: _lightAccent3Ctrl.text.trim(),
      lightInk: _lightInkCtrl.text.trim(),
      lightMuted: _lightMutedCtrl.text.trim(),
      lightBg: _lightBgCtrl.text.trim(),
      btnRadius: _lightRadius,
      darkAccent: _darkAccentCtrl.text.trim(),
      darkAccent2: _darkAccent2Ctrl.text.trim(),
      darkAccent3: _darkAccent3Ctrl.text.trim(),
      darkInk: _darkInkCtrl.text.trim(),
      darkMuted: _darkMutedCtrl.text.trim(),
      darkBg: _darkBgCtrl.text.trim(),
    );
  }

  Future<void> _handleSaveAll() async {
    setState(() => _isSaving = true);
    _saveCurrentPresetFromForm();

    final res = await widget.apiService.saveThemes(
      themes: _themes,
      activeThemeName: _activeThemeName,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res.isSuccess) {
      ObsidianFeedback.showSuccess(
        context,
        message: 'Theme settings saved and applied successfully!',
      );
    } else {
      ObsidianFeedback.showError(
        context,
        message: res.message ?? 'Failed to save theme settings.',
      );
    }
  }

  Future<void> _handleCreatePreset() async {
    _saveCurrentPresetFromForm();
    final nameCtrl = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New Theme Preset', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx)),
          decoration: InputDecoration(
            hintText: 'Enter preset name (e.g. Cyber Neon)',
            hintStyle: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(ctx)),
            filled: true,
            fillColor: ObsidianUITheme.getInputFillColor(ctx),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.getPrimaryAccent(ctx),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = nameCtrl.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    final cleaned = result.trim();

    if (_themes.any((t) => t.name.toLowerCase() == cleaned.toLowerCase())) {
      if (mounted) {
        ObsidianFeedback.showError(
          context,
          message: 'A preset with that name already exists.',
        );
      }
      return;
    }

    final cloned = _themes[_selectedPresetIndex].copyWith(name: cleaned);
    setState(() {
      _themes.add(cloned);
      _selectedPresetIndex = _themes.length - 1;
      _activeThemeName = cleaned;
      _populateFormFromPreset(_themes[_selectedPresetIndex]);
    });

    await _handleSaveAll();
  }

  Future<void> _handleRenamePreset() async {
    if (_selectedPresetIndex < 0 || _selectedPresetIndex >= _themes.length) return;
    final current = _themes[_selectedPresetIndex];
    final nameCtrl = TextEditingController(text: current.name);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rename Preset', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx)),
          decoration: InputDecoration(
            hintText: 'Enter new preset name',
            filled: true,
            fillColor: ObsidianUITheme.getInputFillColor(ctx),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.getPrimaryAccent(ctx),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = nameCtrl.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == current.name) return;
    final cleaned = result.trim();

    if (_themes.any((t) => t.name.toLowerCase() == cleaned.toLowerCase())) {
      if (mounted) {
        ObsidianFeedback.showError(
          context,
          message: 'A preset with that name already exists.',
        );
      }
      return;
    }

    setState(() {
      final oldName = current.name;
      _themes[_selectedPresetIndex] = current.copyWith(name: cleaned);
      if (_activeThemeName == oldName) {
        _activeThemeName = cleaned;
      }
    });

    await _handleSaveAll();
  }

  Future<void> _handleDeletePreset() async {
    if (_themes.length <= 1) {
      ObsidianFeedback.showError(
        context,
        message: 'You must keep at least one theme preset.',
      );
      return;
    }

    final current = _themes[_selectedPresetIndex];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Preset', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
        content: Text('Are you sure you want to delete preset "${current.name}"?',
            style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _themes.removeAt(_selectedPresetIndex);
      if (_activeThemeName == current.name) {
        _activeThemeName = _themes.first.name;
      }
      _selectedPresetIndex = 0;
      _populateFormFromPreset(_themes[0]);
    });

    await _handleSaveAll();
  }

  void _handleResetPreset() {
    setState(() {
      _lightAccentCtrl.text = '#0b8f88';
      _lightAccent2Ctrl.text = '#f28b35';
      _lightAccent3Ctrl.text = '#255a9c';
      _lightInkCtrl.text = '#1d1a17';
      _lightMutedCtrl.text = '#5f5b55';
      _lightRadius = '999px';
      _lightBgMode = 'solid';
      _lightBgSolid = '#ffffff';
      _lightBgCtrl.text = '#ffffff';

      _darkAccentCtrl.text = '#3ccfc0';
      _darkAccent2Ctrl.text = '#f2a353';
      _darkAccent3Ctrl.text = '#6aa2ff';
      _darkInkCtrl.text = '#f4f2ed';
      _darkMutedCtrl.text = '#c3bfb8';
      _darkRadius = '999px';
      _darkBgMode = 'solid';
      _darkBgSolid = '#09090b';
      _darkBgCtrl.text = '#09090b';
    });

    ObsidianFeedback.showSuccess(
      context,
      message: 'Preset form reset to defaults. Click "Save Theme Settings" to persist.',
    );
  }

  Future<void> _pickColor({
    required String title,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) async {
    final initialColor = ObsidianUITheme.parseHex(controller.text) ?? Colors.blue;
    Color tempColor = initialColor;
    final textEditCtrl = TextEditingController(text: controller.text);

    final selected = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final surface = ObsidianUITheme.getSurfaceColor(ctx);
          final textPrimary = ObsidianUITheme.getPrimaryTextColor(ctx);

          final popularSwatches = [
            const Color(0xFF5B6CFF),
            const Color(0xFF0B8F88),
            const Color(0xFF3CCFC0),
            const Color(0xFF3B82F6),
            const Color(0xFF38BDF8),
            const Color(0xFF9D4EDD),
            const Color(0xFFA855F7),
            const Color(0xFFF28B35),
            const Color(0xFFF2A353),
            const Color(0xFFFF9100),
            const Color(0xFFEF4444),
            const Color(0xFF10B981),
            const Color(0xFFF43F5E),
            const Color(0xFF09090B),
            const Color(0xFF18181B),
            const Color(0xFFFFFFFF),
            const Color(0xFFF4F4F5),
            const Color(0xFF71717A),
          ];

          return AlertDialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title, style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Color swatch preview header
                  Container(
                    height: 50,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: tempColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Palette Swatches', style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: popularSwatches.map((color) {
                      final isSelected = color.toARGB32() == tempColor.toARGB32();
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            tempColor = color;
                            textEditCtrl.text = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white24,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Hex Code', style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textEditCtrl,
                    style: TextStyle(color: textPrimary, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '#5B6CFF',
                      filled: true,
                      fillColor: ObsidianUITheme.getInputFillColor(ctx),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) {
                      final parsed = ObsidianUITheme.parseHex(val);
                      if (parsed != null) {
                        setDialogState(() => tempColor = parsed);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.getPrimaryAccent(ctx),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, tempColor),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (selected != null) {
      final hex = '#${(selected.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      controller.text = hex;
      onChanged(hex);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    final isAdmin = widget.apiService.isAdmin;

    return Scaffold(
      backgroundColor: ObsidianUITheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryTextColor),
          onPressed: widget.onBack ?? () => Navigator.maybePop(context),
        ),
        title: Text(
          'Team Theme Customizer',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !isAdmin
              ? _buildAdminLockedView(primaryTextColor, secondaryTextColor)
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Notice
                      Text(
                        'Create and configure custom visual styles for your team. You can save multiple presets and toggle them dynamically.',
                        style: TextStyle(color: secondaryTextColor, fontSize: 13.5),
                      ),
                      const SizedBox(height: 16),

                      // Preset Manager Card
                      _buildPresetManagerCard(surfaceColor, primaryTextColor, secondaryTextColor, tertiaryTextColor, primaryAccent),

                      const SizedBox(height: 20),

                      // Mode Config Cards (Light & Dark)
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          if (constraints.maxWidth > 800) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildModeConfigCard(isDarkModeConfig: false)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildModeConfigCard(isDarkModeConfig: true)),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _buildModeConfigCard(isDarkModeConfig: false),
                              const SizedBox(height: 16),
                              _buildModeConfigCard(isDarkModeConfig: true),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Live Visual Mockup Preview Sandbox
                      _buildVisualPreviewSandbox(surfaceColor, primaryTextColor, secondaryTextColor),

                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isSaving ? null : _handleSaveAll,
                              icon: _isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save_rounded),
                              label: Text(_isSaving ? 'Saving...' : 'Save Theme Settings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryTextColor,
                              side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _handleResetPreset,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset Defaults'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAdminLockedView(Color primaryText, Color secondaryText) {
    return Center(
      child: ObsidianGlassCard(
        margin: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: ObsidianUITheme.warningOrange, size: 48),
            const SizedBox(height: 16),
            Text('Admin Only', style: TextStyle(color: primaryText, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'You need admin access to customize the team theme settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetManagerCard(Color surface, Color primaryText, Color secondaryText, Color tertiaryText, Color primaryAccent) {
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, color: primaryAccent, size: 20),
              const SizedBox(width: 8),
              Text('Theme Presets', style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Select Preset', style: TextStyle(color: secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ObsidianUITheme.getInputFillColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedPresetIndex,
                isExpanded: true,
                dropdownColor: surface,
                style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 14),
                items: List.generate(_themes.length, (index) {
                  return DropdownMenuItem<int>(
                    value: index,
                    child: Text(_themes[index].name),
                  );
                }),
                onChanged: (val) {
                  if (val != null) {
                    _saveCurrentPresetFromForm();
                    setState(() {
                      _selectedPresetIndex = val;
                      _activeThemeName = _themes[val].name;
                      _populateFormFromPreset(_themes[val]);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryAccent.withValues(alpha: 0.2),
                  foregroundColor: primaryAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _handleCreatePreset,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Preset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryText,
                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _handleRenamePreset,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Rename', style: TextStyle(fontSize: 13)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ObsidianUITheme.errorRed,
                  side: BorderSide(color: ObsidianUITheme.errorRed.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _handleDeletePreset,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Active Preset: $_activeThemeName',
              style: TextStyle(color: primaryAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeConfigCard({required bool isDarkModeConfig}) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);

    final title = isDarkModeConfig ? 'Dark Mode' : 'Light Mode';
    final dotColor = isDarkModeConfig ? const Color(0xFF09090B) : const Color(0xFFFFFFFF);

    final accentCtrl = isDarkModeConfig ? _darkAccentCtrl : _lightAccentCtrl;
    final accent2Ctrl = isDarkModeConfig ? _darkAccent2Ctrl : _lightAccent2Ctrl;
    final accent3Ctrl = isDarkModeConfig ? _darkAccent3Ctrl : _lightAccent3Ctrl;
    final inkCtrl = isDarkModeConfig ? _darkInkCtrl : _lightInkCtrl;
    final mutedCtrl = isDarkModeConfig ? _darkMutedCtrl : _lightMutedCtrl;
    final radiusVal = isDarkModeConfig ? _darkRadius : _lightRadius;

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38),
                ),
              ),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),

          _buildColorPickerRow('Primary Accent', accentCtrl, (val) {}),
          const SizedBox(height: 12),
          _buildColorPickerRow('Secondary Accent', accent2Ctrl, (val) {}),
          const SizedBox(height: 12),
          _buildColorPickerRow('Tertiary Accent', accent3Ctrl, (val) {}),
          const SizedBox(height: 12),
          _buildColorPickerRow('Text Color (Ink)', inkCtrl, (val) {}),
          const SizedBox(height: 12),
          _buildColorPickerRow('Muted Text Color', mutedCtrl, (val) {}),
          const SizedBox(height: 16),

          // Background Creator section
          _buildBackgroundCreatorSection(isDarkModeConfig: isDarkModeConfig),

          const SizedBox(height: 16),

          // Button radius selector
          Text('Button Style (Radius)', style: TextStyle(color: secondaryText, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ObsidianUITheme.getInputFillColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: radiusVal,
                isExpanded: true,
                dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: '0px', child: Text('Square (0px)')),
                  DropdownMenuItem(value: '6px', child: Text('Subtle Rounded (6px)')),
                  DropdownMenuItem(value: '12px', child: Text('Standard Rounded (12px)')),
                  DropdownMenuItem(value: '999px', child: Text('Fully Rounded / Pill (999px)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _lightRadius = val;
                      _darkRadius = val;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(String label, TextEditingController controller, ValueChanged<String> onChanged) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final currentColor = ObsidianUITheme.parseHex(controller.text) ?? Colors.transparent;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: primaryText, fontSize: 13, fontWeight: FontWeight.w500)),
        GestureDetector(
          onTap: () => _pickColor(title: label, controller: controller, onChanged: onChanged),
          child: Container(
            width: 54,
            height: 32,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white30, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundCreatorSection({required bool isDarkModeConfig}) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);

    final mode = isDarkModeConfig ? _darkBgMode : _lightBgMode;
    final bgCtrl = isDarkModeConfig ? _darkBgCtrl : _lightBgCtrl;

    final solidPresets = isDarkModeConfig
        ? [
            {'val': '#09090b', 'title': 'True Obsidian'},
            {'val': 'linear-gradient(135deg, #09090b 0%, #18181b 100%)', 'title': 'Onyx Depth'},
            {'val': 'linear-gradient(135deg, #1f1c2c 0%, #928dab 100%)', 'title': 'Deep Space'},
            {'val': 'linear-gradient(135deg, #141e30 0%, #243b55 100%)', 'title': 'Midnight Slate'},
          ]
        : [
            {'val': '#ffffff', 'title': 'Pure White'},
            {'val': 'linear-gradient(135deg, #ffffff 0%, #f4f4f5 100%)', 'title': 'Clean Slate'},
            {'val': 'linear-gradient(135deg, #fce38a 0%, #f38181 100%)', 'title': 'Sunset Glow'},
            {'val': 'linear-gradient(135deg, #a8ff78 0%, #78ffd6 100%)', 'title': 'Ocean Calm'},
          ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Background Creator', style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),

          // Mode buttons (Solid, Gradient, Preset)
          Row(
            children: ['solid', 'gradient', 'preset'].map((m) {
              final isSelected = mode == m;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isDarkModeConfig) {
                          _darkBgMode = m;
                        } else {
                          _lightBgMode = m;
                        }
                        _generateBgValue(isDark: isDarkModeConfig);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? primaryAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSelected ? primaryAccent : Colors.white12),
                      ),
                      child: Text(
                        m[0].toUpperCase() + m.substring(1),
                        style: TextStyle(
                          color: isSelected ? Colors.white : secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Solid Editor
          if (mode == 'solid') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Solid Background', style: TextStyle(color: primaryText, fontSize: 13)),
                GestureDetector(
                  onTap: () {
                    final tempCtrl = TextEditingController(text: isDarkModeConfig ? _darkBgSolid : _lightBgSolid);
                    _pickColor(
                      title: 'Solid Background Color',
                      controller: tempCtrl,
                      onChanged: (val) {
                        setState(() {
                          if (isDarkModeConfig) {
                            _darkBgSolid = val;
                          } else {
                            _lightBgSolid = val;
                          }
                          _generateBgValue(isDark: isDarkModeConfig);
                        });
                      },
                    );
                  },
                  child: Container(
                    width: 50,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.parseHex(isDarkModeConfig ? _darkBgSolid : _lightBgSolid) ?? Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Gradient Editor
          if (mode == 'gradient') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Color 1', style: TextStyle(color: primaryText, fontSize: 13)),
                GestureDetector(
                  onTap: () {
                    final tempCtrl = TextEditingController(text: isDarkModeConfig ? _darkBgGrad1 : _lightBgGrad1);
                    _pickColor(
                      title: 'Gradient Color 1',
                      controller: tempCtrl,
                      onChanged: (val) {
                        setState(() {
                          if (isDarkModeConfig) {
                            _darkBgGrad1 = val;
                          } else {
                            _lightBgGrad1 = val;
                          }
                          _generateBgValue(isDark: isDarkModeConfig);
                        });
                      },
                    );
                  },
                  child: Container(
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.parseHex(isDarkModeConfig ? _darkBgGrad1 : _lightBgGrad1) ?? Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Color 2', style: TextStyle(color: primaryText, fontSize: 13)),
                GestureDetector(
                  onTap: () {
                    final tempCtrl = TextEditingController(text: isDarkModeConfig ? _darkBgGrad2 : _lightBgGrad2);
                    _pickColor(
                      title: 'Gradient Color 2',
                      controller: tempCtrl,
                      onChanged: (val) {
                        setState(() {
                          if (isDarkModeConfig) {
                            _darkBgGrad2 = val;
                          } else {
                            _lightBgGrad2 = val;
                          }
                          _generateBgValue(isDark: isDarkModeConfig);
                        });
                      },
                    );
                  },
                  child: Container(
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.parseHex(isDarkModeConfig ? _darkBgGrad2 : _lightBgGrad2) ?? Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Angle', style: TextStyle(color: secondaryText, fontSize: 12)),
                Text('${(isDarkModeConfig ? _darkBgAngle : _lightBgAngle).round()}°',
                    style: TextStyle(color: primaryText, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: isDarkModeConfig ? _darkBgAngle : _lightBgAngle,
              min: 0,
              max: 360,
              activeColor: primaryAccent,
              onChanged: (val) {
                setState(() {
                  if (isDarkModeConfig) {
                    _darkBgAngle = val;
                  } else {
                    _lightBgAngle = val;
                  }
                  _generateBgValue(isDark: isDarkModeConfig);
                });
              },
            ),
          ],

          // Preset Swatches
          if (mode == 'preset') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: solidPresets.map((preset) {
                final val = preset['val']!;
                final isSelected = bgCtrl.text == val;
                final grad = ObsidianUITheme.parseGradient(val);
                final solid = ObsidianUITheme.parseHex(val);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      bgCtrl.text = val;
                    });
                  },
                  child: Container(
                    width: 65,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: grad,
                      color: solid,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? primaryAccent : Colors.white24,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              bgCtrl.text,
              style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualPreviewSandbox(Color surface, Color primaryText, Color secondaryText) {
    final accent = ObsidianUITheme.parseHex(_previewIsDark ? _darkAccentCtrl.text : _lightAccentCtrl.text) ?? Colors.teal;
    final accent2 = ObsidianUITheme.parseHex(_previewIsDark ? _darkAccent2Ctrl.text : _lightAccent2Ctrl.text) ?? Colors.orange;
    final accent3 = ObsidianUITheme.parseHex(_previewIsDark ? _darkAccent3Ctrl.text : _lightAccent3Ctrl.text) ?? Colors.blue;
    final ink = ObsidianUITheme.parseHex(_previewIsDark ? _darkInkCtrl.text : _lightInkCtrl.text) ?? (_previewIsDark ? Colors.white : Colors.black);
    final muted = ObsidianUITheme.parseHex(_previewIsDark ? _darkMutedCtrl.text : _lightMutedCtrl.text) ?? (_previewIsDark ? Colors.white60 : Colors.black54);
    final bgStr = _previewIsDark ? _darkBgCtrl.text : _lightBgCtrl.text;
    final radius = ObsidianUITheme.parseRadius(_previewIsDark ? _darkRadius : _lightRadius, fallback: 999.0);

    final bgGrad = ObsidianUITheme.parseGradient(bgStr);
    final bgSolid = ObsidianUITheme.parseHex(bgStr) ?? (_previewIsDark ? const Color(0xFF09090B) : const Color(0xFFFFFFFF));

    final borderRadius = BorderRadius.circular(radius > 40 ? 40 : radius);

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Visual Theme Preview', style: TextStyle(color: primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryText,
                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => setState(() => _previewIsDark = !_previewIsDark),
                icon: Icon(_previewIsDark ? Icons.light_mode : Icons.dark_mode, size: 16),
                label: Text(_previewIsDark ? 'Preview Light' : 'Preview Dark', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Live mockup sandbox showing buttons, tabs, shapes, text, and backgrounds below.',
              style: TextStyle(color: secondaryText, fontSize: 13)),
          const SizedBox(height: 16),

          // Sandbox container
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: bgGrad,
              color: bgGrad == null ? bgSolid : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Component Mockup Sandbox', style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // Tabs
                Wrap(
                  spacing: 10,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: borderRadius,
                      ),
                      child: const Text('Active Tab', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: borderRadius,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text('Inactive Tab', style: TextStyle(color: ink, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Buttons
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: borderRadius,
                      ),
                      child: const Text('Primary Button', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: accent2,
                        borderRadius: borderRadius,
                      ),
                      child: const Text('Secondary Button', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: borderRadius,
                        border: Border.all(color: accent3, width: 2),
                      ),
                      child: Text('Outline Button', style: TextStyle(color: accent3, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Typography preview
                Text(
                  'Body text content matches preset choice.',
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Muted secondary labels and descriptive text display here.',
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
