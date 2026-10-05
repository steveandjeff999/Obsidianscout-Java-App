import 'package:flutter/material.dart';
import '../../theme/obsidian_ui_theme.dart';

class CanvasToolbar extends StatelessWidget {
  final String activeTool; // 'pen' | 'eraser'
  final String currentColor; // hex string e.g. '#ffffff'
  final double strokeWidth;
  final bool canUndo;
  final bool canRedo;
  final bool isFullscreen;
  final String saveStatus; // 'saving' | 'saved' | 'error' | 'idle'
  final ValueChanged<String> onToolChanged;
  final ValueChanged<String> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExport;

  static const List<Map<String, String>> colorSwatches = [
    {'hex': '#ffffff', 'label': 'White'},
    {'hex': '#000000', 'label': 'Black'},
    {'hex': '#22c55e', 'label': 'Green'},
    {'hex': '#eab308', 'label': 'Yellow'},
    {'hex': '#f97316', 'label': 'Orange'},
  ];

  const CanvasToolbar({
    super.key,
    required this.activeTool,
    required this.currentColor,
    required this.strokeWidth,
    required this.canUndo,
    required this.canRedo,
    required this.isFullscreen,
    required this.saveStatus,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onToggleFullscreen,
    required this.onExport,
  });

  Color _parseColor(String hex) {
    String clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      clean = 'FF$clean';
    }
    final val = int.tryParse(clean, radix: 16);
    return val != null ? Color(val) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE60F172A), // Dark translucent pill
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tool Toggles: Pen / Eraser
            _buildToolButton(
              icon: Icons.edit_rounded,
              label: 'Pen',
              isActive: activeTool == 'pen',
              onTap: () => onToolChanged('pen'),
              accentColor: primaryAccent,
            ),
            const SizedBox(width: 4),
            _buildToolButton(
              icon: Icons.auto_fix_normal_rounded,
              label: 'Eraser',
              isActive: activeTool == 'eraser',
              onTap: () => onToolChanged('eraser'),
              accentColor: primaryAccent,
            ),

            _buildDivider(),

            // Color Swatches
            Row(
              mainAxisSize: MainAxisSize.min,
              children: colorSwatches.map((swatch) {
                final hex = swatch['hex']!;
                final color = _parseColor(hex);
                final isSelected = activeTool == 'pen' && currentColor.toLowerCase() == hex.toLowerCase();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      onColorChanged(hex);
                      if (activeTool != 'pen') onToolChanged('pen');
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isSelected ? 24 : 20,
                      height: isSelected ? 24 : 20,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.35),
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            _buildDivider(),

            // Stroke Width Slider + Circle Preview
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SIZE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  height: 24,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: primaryAccent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: strokeWidth.clamp(2.0, 48.0),
                      min: 2,
                      max: 48,
                      onChanged: onStrokeWidthChanged,
                    ),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Container(
                    width: (strokeWidth * 0.45).clamp(3.0, 18.0),
                    height: (strokeWidth * 0.45).clamp(3.0, 18.0),
                    decoration: BoxDecoration(
                      color: activeTool == 'eraser' ? const Color(0xFFCBD5E1) : _parseColor(currentColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),

            _buildDivider(),

            // Canvas Action Buttons (Undo, Redo, Clear, Fullscreen, Export)
            _buildIconButton(
              icon: Icons.undo_rounded,
              tooltip: 'Undo',
              enabled: canUndo,
              onTap: canUndo ? onUndo : null,
            ),
            _buildIconButton(
              icon: Icons.redo_rounded,
              tooltip: 'Redo',
              enabled: canRedo,
              onTap: canRedo ? onRedo : null,
            ),
            _buildIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Clear Canvas',
              enabled: true,
              onTap: onClear,
            ),
            _buildIconButton(
              icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
              enabled: true,
              onTap: onToggleFullscreen,
            ),
            _buildIconButton(
              icon: Icons.download_rounded,
              tooltip: 'Export Plan as PNG',
              enabled: true,
              onTap: onExport,
            ),

            const SizedBox(width: 4),

            // Save Status Badge
            _buildSaveBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.white.withValues(alpha: 0.3) : Colors.transparent,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : const Color(0xFFCBD5E1)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : const Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? const Color(0xFFCBD5E1) : Colors.white24,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildSaveBadge() {
    Color badgeColor = const Color(0xFF94A3B8);
    Color badgeBg = Colors.white.withValues(alpha: 0.08);
    IconData badgeIcon = Icons.cloud_done_rounded;
    String badgeText = 'Saved';

    if (saveStatus == 'saving') {
      badgeColor = const Color(0xFFFACC15);
      badgeBg = const Color(0x20FACC15);
      badgeIcon = Icons.sync_rounded;
      badgeText = 'Saving...';
    } else if (saveStatus == 'error') {
      badgeColor = const Color(0xFFEF4444);
      badgeBg = const Color(0x20EF4444);
      badgeIcon = Icons.warning_amber_rounded;
      badgeText = 'Failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
