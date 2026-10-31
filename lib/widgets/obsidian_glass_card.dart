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
    this.padding = const EdgeInsets.all(16.0),
    this.margin = const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
    this.borderRadius = 12.0,
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
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.03);

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

    final effectiveRadius = (widget.borderRadius == 24.0 || widget.borderRadius == 12.0)
        ? ObsidianUITheme.getCardBorderRadius(context)
        : (widget.borderRadius >= 999.0 ? 12.0 : widget.borderRadius.clamp(0.0, 20.0));

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
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: content,
      );
    }

    // Interactive card: Clean tactile press feedback
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.99 : 1.0,
        duration: const Duration(milliseconds: 80),
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
                  ? ObsidianUITheme.getPrimaryAccent(context).withValues(alpha: 0.7)
                  : borderColor,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _isPressed ? 1 : 3,
                offset: _isPressed ? const Offset(0, 0.5) : const Offset(0, 1),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}
