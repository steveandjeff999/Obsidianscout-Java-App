import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const ObsidianBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final navItems = [
      {'targetIndex': 0, 'icon': Icons.dashboard_rounded, 'label': 'Dashboard'},
      {'targetIndex': 1, 'icon': Icons.sports_esports_rounded, 'label': 'Match'},
      {'targetIndex': 4, 'icon': Icons.bar_chart_rounded, 'label': 'Graphs'},
      {'targetIndex': 5, 'icon': Icons.settings_suggest_rounded, 'label': 'Settings'},
    ];

    return Container(
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
      height: 64.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32.0),
              color: const Color(0x24121620),
              border: Border.all(
                color: ObsidianUITheme.glassBorderLight,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(navItems.length, (index) {
                final targetIndex = navItems[index]['targetIndex'] as int;
                final isSelected = targetIndex == currentIndex;
                return GestureDetector(
                  onTap: () => onTap(targetIndex),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: isSelected
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(20.0),
                            gradient: const LinearGradient(
                              colors: [
                                ObsidianUITheme.primaryAccent,
                                ObsidianUITheme.secondaryAccent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          )
                        : const BoxDecoration(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          navItems[index]['icon'] as IconData,
                          color: isSelected ? Colors.white : Colors.white54,
                          size: 20.0,
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6.0),
                          Text(
                            navItems[index]['label'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
