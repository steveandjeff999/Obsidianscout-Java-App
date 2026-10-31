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
    final navBg = ObsidianUITheme.getSurfaceColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final inactiveItemColor = ObsidianUITheme.getSecondaryTextColor(context);

    final allNavItems = [
      {'pageId': 'dashboard', 'targetIndex': 0, 'icon': Icons.dashboard_outlined, 'activeIcon': Icons.dashboard_rounded, 'labelKey': 'nav.dashboard'},
      {'pageId': 'scout', 'targetIndex': 1, 'icon': Icons.sports_esports_outlined, 'activeIcon': Icons.sports_esports_rounded, 'labelKey': 'nav.scout'},
      {'pageId': 'alliance-selection', 'targetIndex': 7, 'icon': Icons.stars_outlined, 'activeIcon': Icons.stars_rounded, 'labelKey': 'nav.alliances'},
      {'pageId': 'chat', 'targetIndex': 6, 'icon': Icons.chat_bubble_outline_rounded, 'activeIcon': Icons.chat_bubble_rounded, 'labelKey': 'nav.team_chat'},
      {'pageId': 'graphs', 'targetIndex': 4, 'icon': Icons.bar_chart_outlined, 'activeIcon': Icons.bar_chart_rounded, 'labelKey': 'nav.graphs'},
      {'pageId': 'settings', 'targetIndex': 5, 'icon': Icons.settings_outlined, 'activeIcon': Icons.settings_rounded, 'labelKey': 'nav.settings'},
    ];

    final navItems = allNavItems.where((item) {
      final pageId = item['pageId'] as String;
      return apiService?.hasPageAccess(pageId) ?? true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(
          top: BorderSide(
            color: borderColor,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final targetIndex = navItems[index]['targetIndex'] as int;
              final isSelected = targetIndex == currentIndex;
              return Expanded(
                child: _ObsidianNavItem(
                  targetIndex: targetIndex,
                  isSelected: isSelected,
                  icon: (isSelected ? navItems[index]['activeIcon'] : navItems[index]['icon']) as IconData,
                  labelKey: navItems[index]['labelKey'] as String,
                  inactiveItemColor: inactiveItemColor,
                  onTap: onTap,
                ),
              );
            }),
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
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap(widget.targetIndex);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _isPressed ? 0.65 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? primaryAccent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Icon(
                widget.icon,
                color: widget.isSelected ? primaryAccent : widget.inactiveItemColor,
                size: 20.0,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              context.tr(widget.labelKey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isSelected ? primaryAccent : widget.inactiveItemColor,
                fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
