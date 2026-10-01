import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../models/gamepad_models.dart';
import '../services/api_service.dart';
import '../services/gamepad_service.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';

class GamepadSettingsScreen extends StatefulWidget {
  final ApiService apiService;

  const GamepadSettingsScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<GamepadSettingsScreen> createState() => _GamepadSettingsScreenState();
}

class _GamepadSettingsScreenState extends State<GamepadSettingsScreen> {
  final GamepadService _gamepadService = GamepadService.instance;
  ScoutingConfigModel? _scoutingConfig;
  bool _showLiveTester = false;
  String _selectedPhaseFilter = 'all'; // 'all', 'auto', 'teleop', 'endgame', 'global'

  @override
  void initState() {
    super.initState();
    _gamepadService.addListener(_onGamepadStateChanged);
    _gamepadService.attachApiService(widget.apiService);
    _loadScoutingConfig();
    _gamepadService.refreshConnectedDevices();
    _gamepadService.syncWithServer(forceRefresh: true);
  }

  @override
  void dispose() {
    _gamepadService.removeListener(_onGamepadStateChanged);
    super.dispose();
  }

  void _onGamepadStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAll() async {
    final synced = await _gamepadService.syncWithServer(forceRefresh: true);
    await _gamepadService.refreshConnectedDevices();
    await _loadScoutingConfig();
    if (mounted) {
      if (synced) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Updated from Server',
          message: '${_gamepadService.profiles.length} controller profile(s) synced from server.',
        );
      } else {
        ObsidianFeedback.showWarning(
          context,
          title: 'Sync Incomplete',
          message: 'Server is offline or unreachable. Loaded local profile cache.',
        );
      }
    }
  }

  Future<void> _saveActiveProfile() async {
    final profile = _gamepadService.activeProfile;
    if (profile == null) return;
    final ok = await _gamepadService.saveActiveProfileToServer();
    if (mounted) {
      if (ok) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Profile Saved',
          message: 'Controller profile "${profile.name}" saved to server database.',
        );
      } else {
        ObsidianFeedback.showError(
          context,
          title: 'Save Failed',
          message: 'Could not reach server. Profile was NOT saved to the server.',
        );
      }
    }
  }

  Widget _buildPhaseFilterChip(String key, String label, Color? accentColor) {
    final isSelected = _selectedPhaseFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: (accentColor ?? ObsidianUITheme.primaryAccent).withValues(alpha: 0.3),
      backgroundColor: ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
      side: BorderSide(
        color: isSelected
            ? (accentColor ?? ObsidianUITheme.primaryAccent)
            : ObsidianUITheme.getBorderColor(context),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? (accentColor ?? ObsidianUITheme.primaryAccent)
            : ObsidianUITheme.getSecondaryTextColor(context),
      ),
      onSelected: (selected) {
        if (selected) setState(() => _selectedPhaseFilter = key);
      },
    );
  }

  Future<void> _loadScoutingConfig() async {
    try {
      final config = await widget.apiService.getCachedMatchConfig() ??
          await widget.apiService.fetchMatchConfig();
      if (mounted) {
        setState(() {
          _scoutingConfig = config;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final activeProfile = _gamepadService.activeProfile;
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return Scaffold(
      backgroundColor: ObsidianUITheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Gamepad & Controller Setup',
          style: TextStyle(
            color: ObsidianUITheme.getPrimaryTextColor(context),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Save Profile Changes',
            onPressed: _saveActiveProfile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Profiles & Controllers',
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: ObsidianUITheme.primaryAccent,
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Controller Hardware Status Card
              _buildDeviceStatusCard(context),
              const SizedBox(height: 16.0),

              // 2. Profile Management & Import/Export
              if (activeProfile != null) ...[
                _buildProfileManagementCard(context, activeProfile),
                const SizedBox(height: 16.0),

                // 3. Live Input HUD / Tester (Collapsible)
                _buildLiveTesterCard(context, activeProfile),
                const SizedBox(height: 16.0),

                // 4. Mappings List Header & Add Button
                _buildMappingsSection(context, activeProfile),
              ],
              const SizedBox(height: 48.0),
            ],
          ),
        ),
      ),
      floatingActionButton: (activeProfile != null && activeProfile.enabled)
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditBindingModal(context, activeProfile, null),
              backgroundColor: ObsidianUITheme.primaryAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Mapping', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  // ==========================================
  // DEVICE STATUS & HARDWARE DETECTION
  // ==========================================

  Widget _buildDeviceStatusCard(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final devices = _gamepadService.connectedDevices;
    final activeProfile = _gamepadService.activeProfile;
    final isEnabled = activeProfile?.enabled ?? false;
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (devices.isNotEmpty && isEnabled)
                        ? ObsidianUITheme.successGreen.withValues(alpha: 0.15)
                        : ObsidianUITheme.warningOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.sports_esports_rounded,
                    color: (devices.isNotEmpty && isEnabled)
                        ? ObsidianUITheme.successGreen
                        : ObsidianUITheme.warningOrange,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hardware Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        devices.isEmpty
                            ? 'No physical controller detected (Keyboard/Bluetooth ready)'
                            : '${devices.length} controller(s) connected: ${devices.map((d) => d.name).join(', ')}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeTrackColor: ObsidianUITheme.primaryAccent,
                  activeThumbColor: Colors.white,
                  onChanged: (val) {
                    if (activeProfile != null) {
                      _gamepadService.saveProfile(activeProfile.copyWith(enabled: val));
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 24),

            // Controller Button Style / Type Selector (Xbox vs PS4 vs Generic)
            if (activeProfile != null) ...[
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Button Icon Style',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                          Text(
                            'Select A/B/X/Y (Xbox) or ✕/○/□/△ (PS4/PS5)',
                            style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'xbox',
                          label: Text('Xbox'),
                          icon: Icon(Icons.videogame_asset_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'playstation',
                          label: Text('PS4 / PS5'),
                          icon: Icon(Icons.gamepad_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'keyboard',
                          label: Text('Keyboard'),
                          icon: Icon(Icons.keyboard_outlined, size: 16),
                        ),
                      ],
                      selected: {activeProfile.controllerType},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          _gamepadService.saveProfile(
                            activeProfile.copyWith(controllerType: selection.first),
                          );
                        }
                      },
                      style: ButtonStyle(
                        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Button Icon Style',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select A/B/X/Y (Xbox), ✕/○/□/△ (PS4/PS5), or Keyboard',
                      style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'xbox',
                            label: Text('Xbox'),
                            icon: Icon(Icons.videogame_asset_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: 'playstation',
                            label: Text('PS4 / PS5'),
                            icon: Icon(Icons.gamepad_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: 'keyboard',
                            label: Text('Keyboard'),
                            icon: Icon(Icons.keyboard_outlined, size: 16),
                          ),
                        ],
                        selected: {activeProfile.controllerType},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            _gamepadService.saveProfile(
                              activeProfile.copyWith(controllerType: selection.first),
                            );
                          }
                        },
                        style: ButtonStyle(
                          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              // Tooltip Badges on Scouting Form Toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show Tooltips on Scouting Form',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        Text(
                          'Displays button badges like [RT] or [A] next to form counters',
                          style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: activeProfile.showTooltips,
                    activeTrackColor: ObsidianUITheme.primaryAccent,
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      _gamepadService.saveProfile(activeProfile.copyWith(showTooltips: val));
                    },
                  ),
                ],
              ),
              const Divider(height: 24),

              // Controller Rumble & Haptics Toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Controller Rumble & Haptics',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        Text(
                          'Vibrates controller on button taps, rapid fire, and actions',
                          style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: activeProfile.hapticEnabled,
                    activeTrackColor: ObsidianUITheme.primaryAccent,
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      _gamepadService.saveProfile(activeProfile.copyWith(hapticEnabled: val));
                    },
                  ),
                ],
              ),

              if (activeProfile.hapticEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
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
                              Icon(Icons.vibration_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                              const SizedBox(width: 8),
                              Text(
                                'Rumble Strength',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryTextColor,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${(activeProfile.hapticStrength * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: ObsidianUITheme.primaryAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: ObsidianUITheme.primaryAccent,
                                thumbColor: ObsidianUITheme.primaryAccent,
                              ),
                              child: Slider(
                                value: activeProfile.hapticStrength,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                onChanged: (val) {
                                  _gamepadService.saveProfile(
                                    activeProfile.copyWith(hapticStrength: (val * 100).round() / 100.0),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final success = await _gamepadService.testRumble();
                              if (context.mounted) {
                                if (success) {
                                  ObsidianFeedback.showSuccess(
                                    context,
                                    title: 'Rumble Test',
                                    message: 'Vibration signal sent to controller.',
                                  );
                                } else {
                                  ObsidianFeedback.showWarning(
                                    context,
                                    title: 'No Controller Detected',
                                    message: 'Connect a supported controller to test rumble.',
                                  );
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.6)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Test', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PROFILE MANAGEMENT & IMPORT/EXPORT CARD
  // ==========================================

  Widget _buildProfileManagementCard(BuildContext context, GamepadProfile activeProfile) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: ObsidianUITheme.primaryAccent, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Controller Profiles (${_gamepadService.profiles.length})',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _saveActiveProfile,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.sync_rounded, size: 20),
                  tooltip: 'Sync Profiles from Server',
                  onPressed: _refreshAll,
                  visualDensity: VisualDensity.compact,
                ),
                TextButton.icon(
                  onPressed: () => _showNewProfileDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Profile'),
                  style: TextButton.styleFrom(
                    foregroundColor: ObsidianUITheme.primaryAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Profile List Items
            ..._gamepadService.profiles.map((p) {
              final isActive = p.id == activeProfile.id;
              final icon = p.controllerType == 'playstation'
                  ? Icons.gamepad_outlined
                  : (p.controllerType == 'keyboard' ? Icons.keyboard_outlined : Icons.videogame_asset_outlined);
              final typeLabel = p.controllerType == 'playstation'
                  ? 'PS4 / PS5'
                  : (p.controllerType == 'keyboard' ? 'Keyboard' : 'Xbox');

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.12)
                      : surfaceColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? ObsidianUITheme.primaryAccent
                        : ObsidianUITheme.getBorderColor(context),
                    width: isActive ? 1.5 : 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Icon(
                    icon,
                    color: isActive ? ObsidianUITheme.primaryAccent : secondaryTextColor,
                    size: 22,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                            color: isActive ? ObsidianUITheme.primaryAccent : primaryTextColor,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.successGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ObsidianUITheme.successGreen.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: ObsidianUITheme.successGreen,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        '$typeLabel • ${p.bindings.length} bindings',
                        style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isActive)
                        TextButton(
                          onPressed: () => _gamepadService.setActiveProfile(p),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Use', style: TextStyle(fontSize: 12)),
                        ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, size: 18, color: secondaryTextColor),
                        color: surfaceColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (val) => _handleProfileMenuAction(val, p),
                        itemBuilder: (ctx) => [
                          if (!isActive)
                            const PopupMenuItem(
                              value: 'set_active',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Set as Active'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Duplicate'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                Icon(Icons.file_upload_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Export JSON'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'reset_default',
                            child: Row(
                              children: [
                                Icon(Icons.restore_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Reset Bindings'),
                              ],
                            ),
                          ),
                          if (_gamepadService.profiles.length > 1)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    if (!isActive) _gamepadService.setActiveProfile(p);
                  },
                ),
                ),
              );
            }),

            const SizedBox(height: 6),

            // AUTO-GENERATE SMART LAYOUT BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleAutoGenerateLayout(context, activeProfile),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text(
                  'Auto-Generate Smart Layout',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianUITheme.primaryAccent,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // EXPORT & IMPORT BUTTONS BAR
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showExportDialog(context, activeProfile),
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Export Config'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ObsidianUITheme.primaryAccent,
                      side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showImportDialog(context),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Import Config'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      foregroundColor: ObsidianUITheme.primaryAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5)),
                      ),
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

  // ==========================================
  // LIVE CONTROLLER TESTER & TRIGGER GAUGES
  // ==========================================

  Widget _buildLiveTesterCard(BuildContext context, GamepadProfile activeProfile) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final livePressed = _gamepadService.liveInputPressed;
    final liveValues = _gamepadService.liveInputValues;

    final ltValue = (liveValues['trigger_l'] ?? liveValues['l2'] ?? 0.0).abs();
    final rtValue = (liveValues['trigger_r'] ?? liveValues['r2'] ?? 0.0).abs();

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _showLiveTester = !_showLiveTester),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    _showLiveTester ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: ObsidianUITheme.secondaryAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Controller Input HUD',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showLiveTester ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: secondaryTextColor,
                  ),
                ],
              ),
            ),
            if (_showLiveTester) ...[
              const SizedBox(height: 12),
              Text(
                'Press any button or pull analog triggers on your controller to test hardware response in real-time.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
              const SizedBox(height: 12),

              // Analog Triggers Bars
              Row(
                children: [
                  Expanded(
                    child: _buildTriggerGauge(
                      label: activeProfile.controllerType == 'playstation' ? 'L2 Trigger' : 'LT Trigger',
                      value: ltValue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTriggerGauge(
                      label: activeProfile.controllerType == 'playstation' ? 'R2 Trigger' : 'RT Trigger',
                      value: rtValue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Active pressed buttons chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'button_a',
                  'button_b',
                  'button_x',
                  'button_y',
                  'shoulder_l',
                  'shoulder_r',
                  'dpad_up',
                  'dpad_down',
                  'dpad_left',
                  'dpad_right',
                  'thumb_l',
                  'thumb_r',
                  'button_start',
                  'button_back',
                ].map((key) {
                  final isPressed = livePressed[key] ?? false;
                  final label = GamepadService.getShortBadgeLabel(key, controllerType: activeProfile.controllerType);
                  final name = GamepadService.getButtonDisplayName(key, controllerType: activeProfile.controllerType);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPressed
                          ? ObsidianUITheme.primaryAccent
                          : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPressed
                            ? ObsidianUITheme.primaryAccent
                            : ObsidianUITheme.getBorderColor(context),
                      ),
                      boxShadow: isPressed
                          ? [
                              BoxShadow(
                                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      '$label ($name)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isPressed ? FontWeight.bold : FontWeight.normal,
                        color: isPressed ? Colors.white : secondaryTextColor,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTriggerGauge({required String label, required double value}) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final percent = (value * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
              Text('$percent%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                value > 0.15 ? ObsidianUITheme.primaryAccent : Colors.grey,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MAPPINGS LIST SECTION
  // ==========================================

  Widget _buildMappingsSection(BuildContext context, GamepadProfile activeProfile) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final bindings = activeProfile.bindings;

    final autoCount = bindings.where((b) => b.phase.toLowerCase() == 'auto').length;
    final teleopCount = bindings.where((b) => b.phase.toLowerCase() == 'teleop').length;
    final endgameCount = bindings.where((b) => b.phase.toLowerCase() == 'endgame').length;
    final globalCount = bindings.where((b) => b.phase.toLowerCase() == 'global').length;

    final filteredBindings = _selectedPhaseFilter == 'all'
        ? bindings
        : bindings.where((b) => b.phase.toLowerCase() == _selectedPhaseFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Configured Mappings (${bindings.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddEditBindingModal(context, activeProfile, null),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('Add Mapping'),
              style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.primaryAccent),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Phase Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildPhaseFilterChip('all', 'All (${bindings.length})', null),
              const SizedBox(width: 6),
              _buildPhaseFilterChip('auto', 'Auto ($autoCount)', ObsidianUITheme.primaryAccent),
              const SizedBox(width: 6),
              _buildPhaseFilterChip('teleop', 'Teleop ($teleopCount)', ObsidianUITheme.secondaryAccent),
              const SizedBox(width: 6),
              _buildPhaseFilterChip('endgame', 'Endgame ($endgameCount)', ObsidianUITheme.successGreen),
              const SizedBox(width: 6),
              _buildPhaseFilterChip('global', 'Global ($globalCount)', Colors.amber),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (filteredBindings.isEmpty)
          ObsidianGlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.gamepad_outlined, size: 40, color: secondaryTextColor),
                    const SizedBox(height: 10),
                    Text(
                      _selectedPhaseFilter == 'all'
                          ? 'No buttons mapped yet'
                          : 'No mappings for ${_selectedPhaseFilter.toUpperCase()} period',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Add Mapping" above or auto-generate smart bindings for this period.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...filteredBindings.map((binding) => _buildBindingTile(context, activeProfile, binding)),
      ],
    );
  }

  Widget _buildBindingTile(BuildContext context, GamepadProfile activeProfile, GamepadBinding binding) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final buttonLabel = GamepadService.getButtonDisplayName(
      binding.inputKey,
      controllerType: activeProfile.controllerType,
    );
    final shortBadge = GamepadService.getShortBadgeLabel(
      binding.inputKey,
      controllerType: activeProfile.controllerType,
    );

    // Conflict detection: Same key in the same or global phase
    final conflictingBindings = activeProfile.bindings.where((b) {
      if (b.id == binding.id) return false;
      if (b.inputKey != binding.inputKey) return false;
      return b.phase.toLowerCase() == binding.phase.toLowerCase() ||
          b.phase.toLowerCase() == 'global' ||
          binding.phase.toLowerCase() == 'global';
    }).toList();
    final hasConflict = conflictingBindings.isNotEmpty;

    String actionDesc = '';
    String fieldName = binding.targetFieldId ?? '';
    if (_scoutingConfig != null && binding.targetFieldId != null) {
      final matchField = _scoutingConfig!.fields
          .where((f) => f.id == binding.targetFieldId)
          .firstOrNull;
      if (matchField != null) {
        fieldName = matchField.label;
      }
    }

    switch (binding.actionType) {
      case GamepadActionType.increment:
        actionDesc = '+${binding.stepValue.toInt()} to "$fieldName"';
        break;
      case GamepadActionType.decrement:
        actionDesc = '-${binding.stepValue.toInt()} to "$fieldName"';
        break;
      case GamepadActionType.toggle:
        actionDesc = 'Toggle "$fieldName"';
        break;
      case GamepadActionType.cycleOption:
        actionDesc = 'Cycle options for "$fieldName"';
        break;
      case GamepadActionType.switchTab:
        actionDesc = binding.targetValue == 'next'
            ? 'Switch to Next Tab'
            : binding.targetValue == 'prev'
                ? 'Switch to Previous Tab'
                : 'Switch to "${binding.targetValue?.toUpperCase()}" Tab';
        break;
      case GamepadActionType.submit:
        actionDesc = 'Submit / Save Match Data';
        break;
      case GamepadActionType.barcode:
        actionDesc = 'Generate QR / Barcode';
        break;
      case GamepadActionType.clearForm:
        actionDesc = 'Reset / Clear Form';
        break;
    }

    String modeDesc = '';
    Color modeColor = Colors.grey;
    switch (binding.triggerMode) {
      case GamepadTriggerMode.singlePress:
        modeDesc = 'Single Tap';
        modeColor = Colors.blueAccent;
        break;
      case GamepadTriggerMode.continuousHold:
        modeDesc = 'Hold (${binding.repeatFrequencyHz.toStringAsFixed(1)} Hz)';
        modeColor = ObsidianUITheme.warningOrange;
        break;
      case GamepadTriggerMode.scaledTrigger:
        modeDesc = 'Analog Trigger (${binding.triggerMinHz.toInt()}-${binding.triggerMaxHz.toInt()} Hz)';
        modeColor = ObsidianUITheme.secondaryAccent;
        break;
    }

    Color phaseColor;
    String phaseLabel;
    switch (binding.phase.toLowerCase()) {
      case 'auto':
        phaseColor = ObsidianUITheme.primaryAccent;
        phaseLabel = 'AUTO';
        break;
      case 'teleop':
        phaseColor = ObsidianUITheme.secondaryAccent;
        phaseLabel = 'TELEOP';
        break;
      case 'endgame':
        phaseColor = ObsidianUITheme.successGreen;
        phaseLabel = 'ENDGAME';
        break;
      case 'postmatch':
        phaseColor = Colors.grey;
        phaseLabel = 'POST';
        break;
      default:
        phaseColor = Colors.amber;
        phaseLabel = 'GLOBAL';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ObsidianGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Row(
            children: [
              // Controller Button Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hasConflict
                      ? Colors.redAccent.withValues(alpha: 0.25)
                      : ObsidianUITheme.primaryAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasConflict
                        ? Colors.redAccent
                        : ObsidianUITheme.primaryAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  shortBadge,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: hasConflict ? Colors.redAccent : ObsidianUITheme.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Action Description, Period, & Mode
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actionDesc,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          buttonLabel,
                          style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                        ),
                        // Period Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: phaseColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: phaseColor.withValues(alpha: 0.5), width: 0.8),
                          ),
                          child: Text(
                            phaseLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: phaseColor,
                            ),
                          ),
                        ),
                        // Execution Mode Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: modeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            modeDesc,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: modeColor,
                            ),
                          ),
                        ),
                        // Conflict Warning
                        if (hasConflict)
                          Tooltip(
                            message: 'Duplicate: This button is also assigned to another action in this period (${conflictingBindings.map((c) => c.actionType.name).join(', ')})',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.warning_amber_rounded, size: 10, color: Colors.redAccent),
                                  SizedBox(width: 3),
                                  Text(
                                    'CONFLICT',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                    ),
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

              // Edit & Delete actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: secondaryTextColor,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 18,
                    onPressed: () => _showAddEditBindingModal(context, activeProfile, binding),
                    tooltip: 'Edit Binding',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    splashRadius: 18,
                    onPressed: () => _deleteBinding(activeProfile, binding),
                    tooltip: 'Delete Binding',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ADD / EDIT BINDING MODAL DIALOG
  // ==========================================

  void _showAddEditBindingModal(
    BuildContext context,
    GamepadProfile activeProfile,
    GamepadBinding? existingBinding,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddEditBindingSheet(
        apiService: widget.apiService,
        activeProfile: activeProfile,
        scoutingConfig: _scoutingConfig,
        existingBinding: existingBinding,
        onSave: (newBinding) {
          final updatedList = List<GamepadBinding>.from(activeProfile.bindings);
          final index = updatedList.indexWhere((b) => b.id == newBinding.id);
          if (index >= 0) {
            updatedList[index] = newBinding;
          } else {
            updatedList.add(newBinding);
          }
          _gamepadService.saveProfile(activeProfile.copyWith(bindings: updatedList));
        },
      ),
    );
  }

  void _deleteBinding(GamepadProfile activeProfile, GamepadBinding binding) {
    final updatedList = activeProfile.bindings.where((b) => b.id != binding.id).toList();
    _gamepadService.saveProfile(activeProfile.copyWith(bindings: updatedList));
  }

  // ==========================================
  // IMPORT & EXPORT HANDLERS
  // ==========================================

  void _showExportDialog(BuildContext context, GamepadProfile activeProfile) {
    final jsonStr = _gamepadService.exportProfileToJson(activeProfile);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.file_upload_outlined, color: ObsidianUITheme.primaryAccent),
            const SizedBox(width: 8),
            Text('Export Controller Profile', style: TextStyle(color: primaryTextColor, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exporting "${activeProfile.name}" with ${activeProfile.bindings.length} configured mappings.',
                style: TextStyle(fontSize: 13, color: ObsidianUITheme.getSecondaryTextColor(context)),
              ),
              const SizedBox(height: 12),
              Container(
                height: 140,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    jsonStr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy to Clipboard'),
            onPressed: () async {
              await _gamepadService.copyProfileToClipboard(activeProfile);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ObsidianFeedback.showSuccess(
                  ctx,
                  title: 'Copied to Clipboard',
                  message: 'Controller layout JSON copied successfully.',
                );
              }
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: const Text('Save File (.json)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final res = await _gamepadService.exportProfileToFile(activeProfile);
              if (mounted) {
                if (res.success) {
                  ObsidianFeedback.showSuccess(
                    this.context,
                    title: 'Profile Exported',
                    message: res.savedPath != null
                        ? 'Saved to: ${res.savedPath}'
                        : 'Profile JSON downloaded successfully.',
                  );
                } else {
                  ObsidianFeedback.showError(
                    this.context,
                    title: 'Export Failed',
                    message: res.message ?? 'Could not export file.',
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final textController = TextEditingController();
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.file_download_outlined, color: ObsidianUITheme.primaryAccent),
            const SizedBox(width: 8),
            Text('Import Controller Profile', style: TextStyle(color: primaryTextColor, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste profile JSON below or import directly from clipboard.',
                style: TextStyle(fontSize: 13, color: ObsidianUITheme.getSecondaryTextColor(context)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 7,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: InputDecoration(
                  hintText: '{\n  "name": "My Custom Layout",\n  "bindings": [...]\n}',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.paste_rounded, size: 16),
            label: const Text('Paste Clipboard'),
            onPressed: () async {
              final profile = await _gamepadService.importProfileFromClipboard();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                if (profile != null) {
                  ObsidianFeedback.showSuccess(
                    context,
                    title: 'Import Successful',
                    message: 'Imported "${profile.name}" with ${profile.bindings.length} bindings.',
                  );
                } else {
                  ObsidianFeedback.showError(
                    context,
                    title: 'Import Error',
                    message: 'Clipboard does not contain valid GamepadProfile JSON.',
                  );
                }
              }
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              final profile = await _gamepadService.importProfileFromJson(raw);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                if (profile != null) {
                  ObsidianFeedback.showSuccess(
                    context,
                    title: 'Import Successful',
                    message: 'Imported "${profile.name}" with ${profile.bindings.length} bindings.',
                  );
                } else {
                  ObsidianFeedback.showError(
                    context,
                    title: 'Import Error',
                    message: 'Invalid JSON format for GamepadProfile.',
                  );
                }
              }
            },
            child: const Text('Import JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAutoGenerateLayout(BuildContext context, GamepadProfile activeProfile) async {
    ScoutingConfigModel? config = _scoutingConfig;
    if (config == null || config.fields.isEmpty) {
      try {
        config = await widget.apiService.getCachedMatchConfig() ??
            await widget.apiService.fetchMatchConfig();
      } catch (_) {}
    }

    if (config == null || config.fields.isEmpty) {
      config = ScoutingConfigModel(
        version: 1,
        title: 'FRC Match Scouting',
        fields: [
          ScoutingFieldModel(id: 'auto_notes', label: 'Auto Notes', type: 'counter', phase: 'auto'),
          ScoutingFieldModel(id: 'teleop_notes', label: 'Teleop Notes', type: 'counter', phase: 'teleop'),
          ScoutingFieldModel(id: 'trap', label: 'Trap', type: 'counter', phase: 'endgame'),
          ScoutingFieldModel(id: 'climb', label: 'Climb Successful', type: 'toggle', phase: 'endgame'),
        ],
      );
    }

    final smartProfile = GamepadProfile.autoGenerateForConfig(
      config,
      controllerType: activeProfile.controllerType,
      profileName: 'Smart ${activeProfile.controllerType == 'playstation' ? 'PS4' : 'Xbox'} Layout',
    );

    await _gamepadService.saveProfile(smartProfile);
    await _gamepadService.setActiveProfile(smartProfile);

    if (context.mounted) {
      ObsidianFeedback.showSuccess(
        context,
        title: 'Smart Layout Generated!',
        message: 'Auto-mapped ${smartProfile.bindings.length} buttons and triggers to match form elements ergonomically.',
      );
    }
  }

  void _showNewProfileDialog(BuildContext context) {
    final nameController = TextEditingController(text: 'Custom Layout');
    String chosenType = 'xbox';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Controller Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: chosenType,
                decoration: const InputDecoration(
                  labelText: 'Controller Style',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'xbox', child: Text('Xbox Controller')),
                  DropdownMenuItem(value: 'playstation', child: Text('PlayStation 4 / 5')),
                  DropdownMenuItem(value: 'keyboard', child: Text('Keyboard / Bluetooth')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => chosenType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ObsidianUITheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final base = chosenType == 'playstation'
                    ? GamepadProfile.defaultPlayStation()
                    : (chosenType == 'keyboard' ? GamepadProfile.defaultKeyboard() : GamepadProfile.defaultXbox());
                final newProf = base.copyWith(
                  id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  controllerType: chosenType,
                );
                _gamepadService.saveProfile(newProf);
                _gamepadService.setActiveProfile(newProf);
                Navigator.of(ctx).pop();
                ObsidianFeedback.showSuccess(context, title: 'Profile Created', message: name);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleProfileMenuAction(String action, GamepadProfile targetProfile) {
    if (action == 'set_active') {
      _gamepadService.setActiveProfile(targetProfile);
      ObsidianFeedback.showSuccess(context, title: 'Active Profile Set', message: targetProfile.name);
    } else if (action == 'auto_generate') {
      _handleAutoGenerateLayout(context, targetProfile);
    } else if (action == 'export') {
      _showExportDialog(context, targetProfile);
    } else if (action == 'rename') {
      final nameController = TextEditingController(text: targetProfile.name);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rename Profile'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ObsidianUITheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  _gamepadService.saveProfile(targetProfile.copyWith(name: newName));
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else if (action == 'duplicate') {
      final dup = targetProfile.copyWith(
        id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
        name: '${targetProfile.name} (Copy)',
      );
      _gamepadService.setActiveProfile(dup);
      ObsidianFeedback.showSuccess(context, title: 'Profile Duplicated', message: dup.name);
    } else if (action == 'reset_default') {
      final def = targetProfile.controllerType == 'playstation'
          ? GamepadProfile.defaultPlayStation()
          : (targetProfile.controllerType == 'keyboard' ? GamepadProfile.defaultKeyboard() : GamepadProfile.defaultXbox());
      _gamepadService.saveProfile(def.copyWith(id: targetProfile.id, name: targetProfile.name));
      ObsidianFeedback.showSuccess(context, title: 'Layout Reset', message: 'Reset bindings to default layout.');
    } else if (action == 'delete') {
      _gamepadService.deleteProfile(targetProfile.id);
      ObsidianFeedback.showSuccess(context, title: 'Profile Deleted', message: targetProfile.name);
    }
  }
}

// ==========================================
// ADD / EDIT BINDING BOTTOM SHEET
// ==========================================

class _AddEditBindingSheet extends StatefulWidget {
  final ApiService apiService;
  final GamepadProfile activeProfile;
  final ScoutingConfigModel? scoutingConfig;
  final GamepadBinding? existingBinding;
  final ValueChanged<GamepadBinding> onSave;

  const _AddEditBindingSheet({
    required this.apiService,
    required this.activeProfile,
    required this.scoutingConfig,
    required this.existingBinding,
    required this.onSave,
  });

  @override
  State<_AddEditBindingSheet> createState() => _AddEditBindingSheetState();
}

class _AddEditBindingSheetState extends State<_AddEditBindingSheet> {
  final GamepadService _gamepadService = GamepadService.instance;

  late String _inputKey;
  late GamepadActionType _actionType;
  String? _targetFieldId;
  String? _targetValue;
  late String _phase; // 'global', 'auto', 'teleop', 'endgame', 'postmatch'
  late GamepadTriggerMode _triggerMode;
  late double _repeatFrequencyHz;
  late double _triggerMinHz;
  late double _triggerMaxHz;
  late double _triggerThreshold;
  late double _stepValue;

  bool _isListening = false;

  bool _isSystemAction(GamepadActionType actionType) {
    return actionType == GamepadActionType.switchTab ||
        actionType == GamepadActionType.submit ||
        actionType == GamepadActionType.barcode ||
        actionType == GamepadActionType.clearForm;
  }

  String _resolveInitialPhase(String? fieldId) {
    if (fieldId == null) return 'global';
    final field = widget.scoutingConfig?.fields.where((f) => f.id == fieldId).firstOrNull;
    if (field?.phase != null && field!.phase!.isNotEmpty) {
      final p = field.phase!.toLowerCase().trim();
      if (p == 'general') return 'teleop';
      return p;
    }
    final lower = fieldId.toLowerCase();
    if (lower.startsWith('auto')) return 'auto';
    if (lower.startsWith('teleop')) return 'teleop';
    if (lower.startsWith('endgame')) return 'endgame';
    if (lower.startsWith('post')) return 'postmatch';
    return 'global';
  }

  @override
  void initState() {
    super.initState();
    final b = widget.existingBinding;
    _inputKey = b?.inputKey ?? 'button_a';
    _actionType = b?.actionType ?? GamepadActionType.increment;
    _targetFieldId = b?.targetFieldId ?? _defaultFieldId(_actionType);
    _targetValue = b?.targetValue;
    _phase = b?.phase ?? (_isSystemAction(_actionType) ? 'global' : _resolveInitialPhase(_targetFieldId));
    _triggerMode = b?.triggerMode ?? GamepadTriggerMode.singlePress;
    _repeatFrequencyHz = b?.repeatFrequencyHz ?? 6.0;
    _triggerMinHz = b?.triggerMinHz ?? 2.0;
    _triggerMaxHz = b?.triggerMaxHz ?? 16.0;
    _triggerThreshold = b?.triggerThreshold ?? 0.15;
    _stepValue = b?.stepValue ?? 1.0;

    // Ensure non-triggers or non-repeatable actions cannot have scaledTrigger / continuousHold mode
    final isRepeatable = _actionType == GamepadActionType.increment || _actionType == GamepadActionType.decrement;
    if (!isRepeatable) {
      _triggerMode = GamepadTriggerMode.singlePress;
    } else if (!GamepadBinding.isKeyTrigger(_inputKey) && _triggerMode == GamepadTriggerMode.scaledTrigger) {
      _triggerMode = GamepadTriggerMode.singlePress;
    }
  }

  String? _defaultFieldId(GamepadActionType actionType) {
    final fields = widget.scoutingConfig?.fields ?? [];
    final matching = _getMatchingFields(actionType, fields);
    return matching.firstOrNull?.id;
  }

  List<ScoutingFieldModel> _getMatchingFields(
    GamepadActionType actionType,
    List<ScoutingFieldModel> allFields,
  ) {
    switch (actionType) {
      case GamepadActionType.increment:
      case GamepadActionType.decrement:
        return allFields.where((f) {
          final t = f.type.toLowerCase();
          return t == 'counter' ||
              t == 'number' ||
              t == 'stepper' ||
              t == 'slider' ||
              t == 'range' ||
              t == 'rating';
        }).toList();
      case GamepadActionType.toggle:
        return allFields.where((f) {
          final t = f.type.toLowerCase();
          return t == 'toggle' || t == 'boolean' || t == 'checkbox';
        }).toList();
      case GamepadActionType.cycleOption:
        return allFields.where((f) {
          final t = f.type.toLowerCase();
          return t == 'select' ||
              t == 'dropdown' ||
              t == 'radio' ||
              t == 'choice' ||
              t == 'multiselect';
        }).toList();
      default:
        return [];
    }
  }

  String _getFieldCategoryLabel(GamepadActionType actionType) {
    switch (actionType) {
      case GamepadActionType.increment:
      case GamepadActionType.decrement:
        return 'Target Counter / Stepper Field';
      case GamepadActionType.toggle:
        return 'Target Toggle / Checkbox Field';
      case GamepadActionType.cycleOption:
        return 'Target Dropdown / Choice Field';
      default:
        return 'Target Field';
    }
  }

  String _getEmptyFieldWarning(GamepadActionType actionType) {
    switch (actionType) {
      case GamepadActionType.increment:
      case GamepadActionType.decrement:
        return 'No counter, stepper, or numeric fields found in active match form.';
      case GamepadActionType.toggle:
        return 'No toggle, boolean, or checkbox fields found in active match form.';
      case GamepadActionType.cycleOption:
        return 'No dropdown, radio, or multi-choice fields found in active match form.';
      default:
        return 'No matching fields found for this action.';
    }
  }

  void _startListeningForInput() {
    setState(() => _isListening = true);
    _gamepadService.startListeningForBinding((key, displayName, isAnalog) {
      if (mounted) {
        setState(() {
          _inputKey = key;
          _isListening = false;
          final isTrigger = GamepadBinding.isKeyTrigger(key);
          final isRepeatable = _actionType == GamepadActionType.increment || _actionType == GamepadActionType.decrement;

          if (!isRepeatable) {
            _triggerMode = GamepadTriggerMode.singlePress;
          } else if (isTrigger) {
            if (_triggerMode == GamepadTriggerMode.singlePress) {
              _triggerMode = GamepadTriggerMode.scaledTrigger;
            }
          } else {
            // Pressure scaling is only allowed on triggers
            if (_triggerMode == GamepadTriggerMode.scaledTrigger) {
              _triggerMode = GamepadTriggerMode.singlePress;
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    if (_isListening) {
      _gamepadService.cancelListeningForBinding();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final buttonDisplayName = GamepadService.getButtonDisplayName(
      _inputKey,
      controllerType: widget.activeProfile.controllerType,
    );
    final shortBadge = GamepadService.getShortBadgeLabel(
      _inputKey,
      controllerType: widget.activeProfile.controllerType,
    );
    final isTrigger = GamepadBinding.isKeyTrigger(_inputKey);
    final isRepeatable = _actionType == GamepadActionType.increment || _actionType == GamepadActionType.decrement;

    if (!isRepeatable && _triggerMode != GamepadTriggerMode.singlePress) {
      _triggerMode = GamepadTriggerMode.singlePress;
    } else if (!isTrigger && _triggerMode == GamepadTriggerMode.scaledTrigger) {
      _triggerMode = GamepadTriggerMode.singlePress;
    }

    final fields = widget.scoutingConfig?.fields ?? [];

    // Duplicate & Conflict checks
    final conflictingKeyBinding = widget.activeProfile.bindings.where((b) {
      if (b.id == widget.existingBinding?.id) return false;
      if (b.inputKey != _inputKey) return false;
      return b.phase.toLowerCase() == _phase.toLowerCase() ||
          b.phase.toLowerCase() == 'global' ||
          _phase.toLowerCase() == 'global';
    }).firstOrNull;

    final duplicateFieldBinding = (_targetFieldId != null)
        ? widget.activeProfile.bindings.where((b) {
            if (b.id == widget.existingBinding?.id) return false;
            if (b.targetFieldId != _targetFieldId || b.actionType != _actionType) return false;
            return b.phase.toLowerCase() == _phase.toLowerCase() ||
                b.phase.toLowerCase() == 'global' ||
                _phase.toLowerCase() == 'global';
          }).firstOrNull
        : null;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              widget.existingBinding == null ? 'Add Controller / Key Binding' : 'Edit Controller / Key Binding',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
            const SizedBox(height: 16),

            // Conflict Warning Banner
            if (conflictingKeyBinding != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Button Conflict Warning',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.redAccent),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '"$buttonDisplayName" is already bound to "${conflictingKeyBinding.actionType.name}" in the ${conflictingKeyBinding.phase.toUpperCase()} period. Both actions may trigger.',
                            style: TextStyle(fontSize: 11.5, color: ObsidianUITheme.getPrimaryTextColor(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Duplicate Field Action Banner
            if (duplicateFieldBinding != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Existing Field Action Mapping',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.amber),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'This field already has a "${duplicateFieldBinding.actionType.name}" binding on ${GamepadService.getButtonDisplayName(duplicateFieldBinding.inputKey, controllerType: widget.activeProfile.controllerType)} (${duplicateFieldBinding.phase.toUpperCase()}).',
                            style: TextStyle(fontSize: 11.5, color: ObsidianUITheme.getPrimaryTextColor(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 1. INPUT CAPTURE BUTTON
            InkWell(
              onTap: _startListeningForInput,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _isListening
                      ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)
                      : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isListening
                        ? ObsidianUITheme.primaryAccent
                        : ObsidianUITheme.getBorderColor(context),
                    width: _isListening ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        shortBadge,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ObsidianUITheme.primaryAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isListening ? 'PRESS ANY CONTROLLER BUTTON OR KEYBOARD KEY...' : buttonDisplayName,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: _isListening ? ObsidianUITheme.primaryAccent : primaryTextColor,
                            ),
                          ),
                          Text(
                            _isListening
                                ? 'Listening for input on Controller / Keyboard...'
                                : 'Tap to re-record button, trigger, or key',
                            style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isListening ? Icons.sensors_rounded : Icons.touch_app_outlined,
                      color: ObsidianUITheme.primaryAccent,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. PERIOD / PHASE SELECTOR
            Text(
              'Active Period / Phase',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: primaryTextColor),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _phase,
              dropdownColor: surfaceColor,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'global', child: Text('Global (Active in All Periods)')),
                DropdownMenuItem(value: 'auto', child: Text('Autonomous Period Only')),
                DropdownMenuItem(value: 'teleop', child: Text('Teleoperated Period Only')),
                DropdownMenuItem(value: 'endgame', child: Text('Endgame Period Only')),
                DropdownMenuItem(value: 'postmatch', child: Text('Post-Match Period Only')),
              ],
              onChanged: _isSystemAction(_actionType)
                  ? null
                  : (val) {
                      if (val != null) setState(() => _phase = val);
                    },
            ),
            if (_isSystemAction(_actionType))
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'System actions (save, QR code, tab switching) apply globally across all periods.',
                  style: TextStyle(fontSize: 11, color: secondaryTextColor, fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 14),

            // 3. ACTION TYPE SELECTOR
            Text(
              'Target Action',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: primaryTextColor),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<GamepadActionType>(
              initialValue: _actionType,
              dropdownColor: surfaceColor,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: GamepadActionType.increment, child: Text('+ Increment Field Count')),
                DropdownMenuItem(value: GamepadActionType.decrement, child: Text('- Decrement Field Count')),
                DropdownMenuItem(value: GamepadActionType.toggle, child: Text('Toggle Checkbox / Boolean')),
                DropdownMenuItem(value: GamepadActionType.cycleOption, child: Text('Cycle Dropdown / Radio Options')),
                DropdownMenuItem(value: GamepadActionType.switchTab, child: Text('Switch Scouting Tab (Auto/Teleop/Endgame)')),
                DropdownMenuItem(value: GamepadActionType.submit, child: Text('Save / Submit Match Data')),
                DropdownMenuItem(value: GamepadActionType.barcode, child: Text('Generate Barcode / QR')),
                DropdownMenuItem(value: GamepadActionType.clearForm, child: Text('Reset / Clear Form')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _actionType = val;
                    final matching = _getMatchingFields(val, fields);
                    if (!matching.any((f) => f.id == _targetFieldId)) {
                      _targetFieldId = matching.firstOrNull?.id;
                    }
                    if (_isSystemAction(val)) {
                      _phase = 'global';
                    } else if (_targetFieldId != null) {
                      _phase = _resolveInitialPhase(_targetFieldId);
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            // 4. TARGET FIELD / TAB DROPDOWN (Strictly filtered by action type)
            if (_actionType == GamepadActionType.increment ||
                _actionType == GamepadActionType.decrement ||
                _actionType == GamepadActionType.toggle ||
                _actionType == GamepadActionType.cycleOption) ...[
              () {
                final matchingFields = _getMatchingFields(_actionType, fields);
                final isCurrentValid = matchingFields.any((f) => f.id == _targetFieldId);
                final selectedValue = isCurrentValid
                    ? _targetFieldId
                    : (matchingFields.isNotEmpty ? matchingFields.first.id : null);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getFieldCategoryLabel(_actionType),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    if (matchingFields.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getEmptyFieldWarning(_actionType),
                                style: const TextStyle(fontSize: 12, color: Colors.amber),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey('${_actionType.name}_${matchingFields.length}'),
                        initialValue: selectedValue,
                        dropdownColor: surfaceColor,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'Select a form field',
                        ),
                        items: matchingFields
                            .map((f) => DropdownMenuItem(
                                  value: f.id,
                                  child: Text('${f.label} (${f.id})', overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _targetFieldId = val;
                            if (val != null) {
                              _phase = _resolveInitialPhase(val);
                            }
                          });
                        },
                      ),
                  ],
                );
              }(),
              const SizedBox(height: 14),
            ] else if (_actionType == GamepadActionType.switchTab) ...[
              Text(
                'Target Tab',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: primaryTextColor),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _targetValue ?? 'next',
                dropdownColor: surfaceColor,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'next', child: Text('Next Tab (Cycle Forward)')),
                  DropdownMenuItem(value: 'prev', child: Text('Previous Tab (Cycle Backward)')),
                  DropdownMenuItem(value: 'auto', child: Text('Auto Phase')),
                  DropdownMenuItem(value: 'teleop', child: Text('Teleop Phase')),
                  DropdownMenuItem(value: 'endgame', child: Text('Endgame Phase')),
                  DropdownMenuItem(value: 'postmatch', child: Text('Post-Match Phase')),
                ],
                onChanged: (val) => setState(() => _targetValue = val),
              ),
              const SizedBox(height: 14),
            ],

            // 5. TRIGGER BEHAVIOR MODE (Disabled for non-repeatable actions)
            Text(
              'Input Execution Mode',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: primaryTextColor),
            ),
            const SizedBox(height: 6),

            if (!isRepeatable) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Single Press Only (Hold-to-repeat is disabled for ${_actionType.name})',
                        style: TextStyle(fontSize: 12, color: primaryTextColor, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              SegmentedButton<GamepadTriggerMode>(
                segments: [
                  const ButtonSegment(
                    value: GamepadTriggerMode.singlePress,
                    label: Text('1 Click'),
                    icon: Icon(Icons.touch_app_rounded, size: 16),
                  ),
                  const ButtonSegment(
                    value: GamepadTriggerMode.continuousHold,
                    label: Text('Hold Repeat'),
                    icon: Icon(Icons.repeat_rounded, size: 16),
                  ),
                  if (isTrigger)
                    const ButtonSegment(
                      value: GamepadTriggerMode.scaledTrigger,
                      label: Text('Trigger Scale'),
                      icon: Icon(Icons.speed_rounded, size: 16),
                    ),
                ],
                selected: {_triggerMode},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) setState(() => _triggerMode = selection.first);
                },
                style: ButtonStyle(
                  textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!isTrigger) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: secondaryTextColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Variable speed scaling is available exclusively on analog triggers (LT / RT / L2 / R2).',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Continuous Hold Parameters
              if (_triggerMode == GamepadTriggerMode.continuousHold) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Repeat Frequency', style: TextStyle(fontSize: 13, color: primaryTextColor)),
                    Text(
                      '${_repeatFrequencyHz.toStringAsFixed(1)} actions/sec (${(1000 / _repeatFrequencyHz).round()}ms)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                    ),
                  ],
                ),
                Slider(
                  value: _repeatFrequencyHz,
                  min: 1.0,
                  max: 25.0,
                  divisions: 24,
                  activeColor: ObsidianUITheme.primaryAccent,
                  label: '${_repeatFrequencyHz.toStringAsFixed(1)} Hz',
                  onChanged: (val) => setState(() => _repeatFrequencyHz = val),
                ),
                const SizedBox(height: 10),
              ],

              // Scaled Trigger Parameters
              if (_triggerMode == GamepadTriggerMode.scaledTrigger) ...[
                Text(
                  'Trigger Scaling: Pulling lightly increments slowly, pulling fully increments rapidly.',
                  style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Light Pull Speed (Min)', style: TextStyle(fontSize: 12.5, color: primaryTextColor)),
                    Text('${_triggerMinHz.toInt()} Hz', style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                  ],
                ),
                Slider(
                  value: _triggerMinHz,
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  activeColor: ObsidianUITheme.primaryAccent,
                  onChanged: (val) => setState(() => _triggerMinHz = val),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Full Pull Speed (Max)', style: TextStyle(fontSize: 12.5, color: primaryTextColor)),
                    Text('${_triggerMaxHz.toInt()} Hz', style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent)),
                  ],
                ),
                Slider(
                  value: _triggerMaxHz,
                  min: 10.0,
                  max: 30.0,
                  divisions: 20,
                  activeColor: ObsidianUITheme.primaryAccent,
                  onChanged: (val) => setState(() => _triggerMaxHz = val),
                ),
                const SizedBox(height: 10),
              ],
            ],

            // Save / Cancel Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final binding = GamepadBinding(
                        id: widget.existingBinding?.id ?? 'b_${DateTime.now().millisecondsSinceEpoch}',
                        inputKey: _inputKey,
                        actionType: _actionType,
                        targetFieldId: _targetFieldId,
                        targetValue: _targetValue,
                        phase: _phase,
                        triggerMode: _triggerMode,
                        repeatFrequencyHz: _repeatFrequencyHz,
                        triggerMinHz: _triggerMinHz,
                        triggerMaxHz: _triggerMaxHz,
                        triggerThreshold: _triggerThreshold,
                        stepValue: _stepValue,
                      );
                      widget.onSave(binding);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Mapping', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
