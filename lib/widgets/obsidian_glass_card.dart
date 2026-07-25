import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianGlassCard extends StatelessWidget {
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

    Widget cardContent = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: isDark ? 16 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              color: cardBgColor,
              border: Border.all(
                color: borderColor,
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
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: cardContent,
      );
    }
    return cardContent;
  }
}
