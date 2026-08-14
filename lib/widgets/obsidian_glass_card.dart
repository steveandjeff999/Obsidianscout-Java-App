import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final VoidCallback? onTap;

  const ObsidianGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20.0),
    this.margin = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
    this.borderRadius = 24.0,
    this.onTap,
  });

  @override
  State<ObsidianGlassCard> createState() => _ObsidianGlassCardState();
}

class _ObsidianGlassCardState extends State<ObsidianGlassCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final cardBgColor = ObsidianUITheme.getGlassSurfaceColor(context);
    final borderColor = ObsidianUITheme.getGlassBorderColor(context);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.06);

    final gradientColors = isDark
        ? const [Color(0x22FFFFFF), Color(0x06FFFFFF)]
        : const [Color(0xFFFFFFFF), Color(0xF0F8FAFC)];

    Widget cardContent = AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [
            BoxShadow(
              color: _isPressed ? shadowColor.withValues(alpha: 0.15) : shadowColor,
              blurRadius: _isPressed ? 8 : (isDark ? 16 : 12),
              offset: _isPressed ? const Offset(0, 2) : const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                color: cardBgColor,
                border: Border.all(
                  color: _isPressed ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.6) : borderColor,
                  width: 1.2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                  child: IconTheme.merge(
                    data: IconThemeData(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap!();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: cardContent,
      );
    }
    return cardContent;
  }
}
