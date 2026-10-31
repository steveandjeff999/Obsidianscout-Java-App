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
  Size get preferredSize => const Size.fromHeight(80.0);

  @override
  Widget build(BuildContext context) {
    final bgColor = ObsidianUITheme.getSurfaceColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final titleColor = ObsidianUITheme.getPrimaryTextColor(context);

    final statusColor = isOnline
        ? ObsidianUITheme.successGreen
        : ObsidianUITheme.warningOrange;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6.0,
        left: 16.0,
        right: 16.0,
        bottom: 10.0,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: borderColor,
            width: 1.0,
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
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: ObsidianUITheme.getSecondaryTextColor(context),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    if (subtitle.isNotEmpty) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 9.0,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    letterSpacing: -0.3,
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
    );
  }
}
