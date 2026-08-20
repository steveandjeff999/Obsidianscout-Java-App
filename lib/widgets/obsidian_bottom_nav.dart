import 'dart:ui';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianBottomNav extends StatelessWidget {
  final ApiService? apiService;
  final int currentIndex;
  final Function(int) onTap;

  const ObsidianBottomNav({
    super.key,
    this.apiService,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final navBg = isDark ? const Color(0x24121620) : const Color(0xECFFFFFF);
    final borderColor = ObsidianUITheme.getGlassBorderColor(context);
    final shadowColor = isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.1);
    final inactiveItemColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    final allNavItems = [
      {'pageId': 'dashboard', 'targetIndex': 0, 'icon': Icons.dashboard_rounded, 'labelKey': 'nav.dashboard'},
      {'pageId': 'scout', 'targetIndex': 1, 'icon': Icons.sports_esports_rounded, 'labelKey': 'nav.scout'},
      {'pageId': 'alliance-selection', 'targetIndex': 7, 'icon': Icons.stars_rounded, 'labelKey': 'nav.alliances'},
      {'pageId': 'chat', 'targetIndex': 6, 'icon': Icons.chat_bubble_outline_rounded, 'labelKey': 'nav.team_chat'},
      {'pageId': 'graphs', 'targetIndex': 4, 'icon': Icons.bar_chart_rounded, 'labelKey': 'nav.graphs'},
      {'pageId': 'settings', 'targetIndex': 5, 'icon': Icons.settings_suggest_rounded, 'labelKey': 'nav.settings'},
    ];

    final navItems = allNavItems.where((item) {
      final pageId = item['pageId'] as String;
      return apiService?.hasPageAccess(pageId) ?? true;
    }).toList();

    return Container(
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
      height: 64.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: isDark ? 20 : 12,
            offset: const Offset(0, 6),
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
              color: navBg,
              border: Border.all(
                color: borderColor,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(navItems.length, (index) {
                final targetIndex = navItems[index]['targetIndex'] as int;
                final isSelected = targetIndex == currentIndex;
                return _ObsidianNavItem(
                  targetIndex: targetIndex,
                  isSelected: isSelected,
                  icon: navItems[index]['icon'] as IconData,
                  labelKey: navItems[index]['labelKey'] as String,
                  inactiveItemColor: inactiveItemColor,
                  onTap: onTap,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _ObsidianNavItem extends StatefulWidget {
  final int targetIndex;
  final bool isSelected;
  final IconData icon;
  final String labelKey;
  final Color inactiveItemColor;
  final Function(int) onTap;

  const _ObsidianNavItem({
    required this.targetIndex,
    required this.isSelected,
    required this.icon,
    required this.labelKey,
    required this.inactiveItemColor,
    required this.onTap,
  });

  @override
  State<_ObsidianNavItem> createState() => _ObsidianNavItemState();
}

class _ObsidianNavItemState extends State<_ObsidianNavItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap(widget.targetIndex);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.88 : (widget.isSelected ? 1.05 : 1.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: widget.isSelected
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
                widget.icon,
                color: widget.isSelected ? Colors.white : widget.inactiveItemColor,
                size: 20.0,
              ),
              if (widget.isSelected) ...[
                const SizedBox(width: 6.0),
                Text(
                  context.tr(widget.labelKey),
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
      ),
    );
  }
}
