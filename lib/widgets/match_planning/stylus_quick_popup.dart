import 'package:flutter/material.dart';
import '../../theme/obsidian_ui_theme.dart';
import 'canvas_toolbar.dart';

/// Floating quick-picker widget (Samsung Notes style)
/// Appears near the stylus tip when the S Pen / stylus barrel button is clicked.
class StylusQuickPopup extends StatelessWidget {
  final Offset position;
  final Size canvasSize;
  final String activeTool;
  final String currentColor;
  final double strokeWidth;
  final ValueChanged<String> onToolChanged;
  final ValueChanged<String> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onClose;

  const StylusQuickPopup({
    super.key,
    required this.position,
    required this.canvasSize,
    required this.activeTool,
    required this.currentColor,
    required this.strokeWidth,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onClose,
  });

  Color _parseColor(String hex) {
    String clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) clean = 'FF$clean';
    final val = int.tryParse(clean, radix: 16);
    return val != null ? Color(val) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    const popupWidth = 230.0;
    const popupHeight = 160.0;

    // Calculate clamped position inside the canvas area with slight offset
    double left = position.dx + 16.0;
    double top = position.dy - 30.0;

    if (left + popupWidth > canvasSize.width) {
      left = (canvasSize.width - popupWidth - 10.0).clamp(10.0, double.infinity);
    }
    if (left < 10.0) left = 10.0;

    if (top + popupHeight > canvasSize.height) {
      top = (canvasSize.height - popupHeight - 10.0).clamp(10.0, double.infinity);
    }
    if (top < 10.0) top = 10.0;

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: popupWidth,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xF20F172A), // Dark slate translucent
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 24,
                spreadRadius: 2,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.edit_road_rounded, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Text(
                        'QUICK TOOLS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tool Toggle Row (Pen / Eraser)
              Row(
                children: [
                  Expanded(
                    child: _buildToolToggle(
                      label: 'Pen',
                      icon: Icons.edit_rounded,
                      isActive: activeTool == 'pen',
                      onTap: () => onToolChanged('pen'),
                      accentColor: primaryAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildToolToggle(
                      label: 'Eraser',
                      icon: Icons.auto_fix_normal_rounded,
                      isActive: activeTool == 'eraser',
                      onTap: () => onToolChanged('eraser'),
                      accentColor: primaryAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Color Swatches
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: CanvasToolbar.colorSwatches.map((swatch) {
                  final hex = swatch['hex']!;
                  final color = _parseColor(hex);
                  final isSelected = activeTool == 'pen' && currentColor.toLowerCase() == hex.toLowerCase();

                  return InkWell(
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
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              // Stroke Size Slider & Preview
              Row(
                children: [
                  const Text(
                    'SIZE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                          activeTrackColor: primaryAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: strokeWidth,
                          min: 2,
                          max: 32,
                          divisions: 15,
                          onChanged: onStrokeWidthChanged,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Container(
                      width: (strokeWidth * 0.55).clamp(3.0, 14.0),
                      height: (strokeWidth * 0.55).clamp(3.0, 14.0),
                      decoration: BoxDecoration(
                        color: activeTool == 'eraser' ? const Color(0xFFCBD5E1) : _parseColor(currentColor),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolToggle({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? accentColor : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.white38 : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: isActive ? Colors.white : const Color(0xFFCBD5E1)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : const Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
