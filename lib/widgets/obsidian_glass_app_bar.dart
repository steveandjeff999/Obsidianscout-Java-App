import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final bool isOnline;
  final List<Widget>? actions;

  const ObsidianGlassAppBar({
    super.key,
    required this.title,
    this.subtitle = "",
    this.isOnline = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(90.0);

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final bgColor = isDark ? const Color(0x15000000) : const Color(0x99FFFFFF);
    final borderColor = ObsidianUITheme.getGlassBorderColor(context);
    final titleColor = ObsidianUITheme.getPrimaryTextColor(context);

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8.0,
            left: 20.0,
            right: 20.0,
            bottom: 12.0,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: borderColor,
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (subtitle.isNotEmpty)
                          Flexible(
                            child: Text(
                              subtitle.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: ObsidianUITheme.primaryAccent,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isOnline ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.orangeAccent : Colors.orange),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: isOnline ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.orangeAccent : Colors.orange),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'ONLINE' : 'OFFLINE MODE',
                                style: TextStyle(
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.bold,
                                  color: isOnline ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.orangeAccent : Colors.orange),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22.0,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, children: actions!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
