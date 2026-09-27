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
    final cardBgColor = ObsidianUITheme.getSurfaceColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.04);

    final content = Material(
      color: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
        child: IconTheme.merge(
          data: IconThemeData(color: ObsidianUITheme.getPrimaryTextColor(context)),
          child: widget.child,
        ),
      ),
    );

    final effectiveRadius = widget.borderRadius == 24.0
        ? ObsidianUITheme.getCardBorderRadius(context)
        : (widget.borderRadius >= 999.0 ? 24.0 : widget.borderRadius.clamp(0.0, 28.0));

    // Static card optimization (no onTap): Render pure container without animation overhead
    if (widget.onTap == null) {
      return Container(
        margin: widget.margin,
        width: double.infinity,
        padding: widget.padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(effectiveRadius),
          color: cardBgColor,
          border: Border.all(
            color: borderColor,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: content,
      );
    }

    // Interactive card: Smooth press feedback
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          margin: widget.margin,
          width: double.infinity,
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(effectiveRadius),
            color: cardBgColor,
            border: Border.all(
              color: _isPressed
                  ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.6)
                  : borderColor,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _isPressed ? 2 : 6,
                offset: _isPressed ? const Offset(0, 1) : const Offset(0, 2),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}
