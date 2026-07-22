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
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8.0,
            left: 20.0,
            right: 20.0,
            bottom: 12.0,
          ),
          decoration: const BoxDecoration(
            color: Color(0x15000000),
            border: Border(
              bottom: BorderSide(
                color: ObsidianUITheme.glassBorderLight,
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: ObsidianUITheme.primaryAccent,
                            letterSpacing: 1.2,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 6,
                              color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'ONLINE' : 'OFFLINE MODE',
                              style: TextStyle(
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                                color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
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
                    style: const TextStyle(
                      fontSize: 26.0,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              if (actions != null) Row(children: actions!),
            ],
          ),
        ),
      ),
    );
  }
}
