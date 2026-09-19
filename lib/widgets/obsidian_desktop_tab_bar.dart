import 'package:flutter/material.dart';
import '../models/desktop_tab_model.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianDesktopTabBar extends StatefulWidget {
  final List<DesktopTab> tabs;
  final String activeTabId;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onNewTab;
  final ValueChanged<String>? onDuplicateTab;
  final ValueChanged<String>? onCloseOtherTabs;
  final ApiService apiService;
  final bool isOnline;
  final VoidCallback? onOpenQrScanner;
  final String Function(int index) getScreenTitle;
  final IconData Function(int index) getScreenIcon;

  const ObsidianDesktopTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    this.onDuplicateTab,
    this.onCloseOtherTabs,
    required this.apiService,
    required this.isOnline,
    this.onOpenQrScanner,
    required this.getScreenTitle,
    required this.getScreenIcon,
  });

  @override
  State<ObsidianDesktopTabBar> createState() => _ObsidianDesktopTabBarState();
}

class _ObsidianDesktopTabBarState extends State<ObsidianDesktopTabBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final barBg = isDark
        ? ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.65)
        : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.85);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    final tabRadius = ObsidianUITheme.getButtonRadius(context, fallback: 8.0).clamp(4.0, 14.0);
    final eventKey = widget.apiService.currentSettings?.eventKey ?? '';

    return Container(
      width: double.infinity,
      height: 42.0,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          // Scrollable Tabs Area
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thickness: 2.0,
              radius: const Radius.circular(2.0),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.tabs.length + 1,
                itemBuilder: (context, index) {
                  if (index == widget.tabs.length) {
                    return _buildNewTabButton(context, isDark);
                  }
                  final tab = widget.tabs[index];
                  final isActive = tab.id == widget.activeTabId;
                  final title = tab.customTitle ?? widget.getScreenTitle(tab.screenIndex);
                  final icon = tab.customIcon ?? widget.getScreenIcon(tab.screenIndex);

                  return _buildTabItem(
                    context: context,
                    tab: tab,
                    title: title,
                    icon: icon,
                    isActive: isActive,
                    isDark: isDark,
                    canClose: widget.tabs.length > 1,
                    tabRadius: tabRadius,
                    primaryAccent: primaryAccent,
                  );
                },
              ),
            ),
          ),

          // Event Badge (if set)
          if (eventKey.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(tabRadius > 6.0 ? 6.0 : tabRadius),
                  border: Border.all(
                    color: primaryAccent.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_rounded, size: 11.0, color: primaryAccent),
                    const SizedBox(width: 4.0),
                    Text(
                      eventKey.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: primaryAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Online / Offline Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
            margin: const EdgeInsets.only(right: 6.0),
            decoration: BoxDecoration(
              color: widget.isOnline ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: widget.isOnline ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5.5,
                  height: 5.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 5.0),
                Text(
                  widget.isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: widget.isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // QR Scanner Button
          if (widget.apiService.hasPageAccess('qr-scanner') && widget.onOpenQrScanner != null)
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                size: 17.0,
                color: isDark ? Colors.cyanAccent : const Color(0xFF0284C7),
              ),
              tooltip: 'QR & Barcode Scanner (Ctrl+Q)',
              onPressed: widget.onOpenQrScanner,
              constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
              padding: EdgeInsets.zero,
            ),

          // Theme Switcher Button
          IconButton(
            icon: Icon(
              widget.apiService.themeMode == ThemeMode.light
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              size: 17.0,
              color: widget.apiService.themeMode == ThemeMode.light
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFFFFB703),
            ),
            tooltip: widget.apiService.themeMode == ThemeMode.light
                ? 'Switch to Dark Mode (Ctrl+T)'
                : 'Switch to Light Mode (Ctrl+T)',
            onPressed: () {
              final nextMode = widget.apiService.themeMode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
              widget.apiService.setThemeMode(nextMode);
            },
            constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
            padding: const EdgeInsets.only(right: 6.0),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required BuildContext context,
    required DesktopTab tab,
    required String title,
    required IconData icon,
    required bool isActive,
    required bool isDark,
    required bool canClose,
    required double tabRadius,
    required Color primaryAccent,
  }) {
    final activeBg = isDark ? ObsidianUITheme.getSurfaceColor(context) : Colors.white;
    final inactiveBg = isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04);
    final activeBorderColor = primaryAccent;
    final titleText = title.isNotEmpty && !title.startsWith('nav.') ? title : 'Tab ${widget.tabs.indexOf(tab) + 1}';
    final tabBorderColor = isActive
        ? ObsidianUITheme.getBorderColor(context)
        : (isDark ? Colors.white10 : Colors.black12);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelectTab(tab.id),
      onTertiaryTapUp: (_) {
        if (canClose) {
          widget.onCloseTab(tab.id);
        }
      },
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, tab);
      },
      child: Tooltip(
        message: '$titleText (Middle-click to close)',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          width: 175.0,
          margin: const EdgeInsets.only(top: 4.0, bottom: 0.0, right: 3.0),
          decoration: BoxDecoration(
            color: isActive ? activeBg : inactiveBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(tabRadius)),
            border: Border.all(
              color: tabBorderColor,
              width: 0.8,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular((tabRadius - 1).clamp(0.0, 32.0))),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelectTab(tab.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 15.0,
                              color: isActive
                                  ? primaryAccent
                                  : (isDark ? ObsidianUITheme.getSecondaryTextColor(context) : Colors.black45),
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: Text(
                                titleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                  color: isActive
                                      ? ObsidianUITheme.getPrimaryTextColor(context)
                                      : ObsidianUITheme.getSecondaryTextColor(context),
                                ),
                              ),
                            ),
                            if (canClose)
                              InkWell(
                                onTap: () => widget.onCloseTab(tab.id),
                                borderRadius: BorderRadius.circular(4.0),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13.5,
                                    color: isActive
                                        ? ObsidianUITheme.getSecondaryTextColor(context)
                                        : ObsidianUITheme.getFaintTextColor(context),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 4.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (isActive)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 2.5,
                    child: Container(color: activeBorderColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewTabButton(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: Tooltip(
        message: 'Open New Tab (Ctrl+T)',
        child: InkWell(
          onTap: widget.onNewTab,
          borderRadius: BorderRadius.circular(6.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 16.0,
              color: ObsidianUITheme.getSecondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, DesktopTab tab) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final canClose = widget.tabs.length > 1;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'duplicate',
          height: 36.0,
          child: Row(
            children: const [
              Icon(Icons.control_point_duplicate_rounded, size: 16.0),
              SizedBox(width: 8.0),
              Text('Duplicate Tab', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        if (canClose)
          PopupMenuItem(
            value: 'close',
            height: 36.0,
            child: Row(
              children: const [
                Icon(Icons.close_rounded, size: 16.0),
                SizedBox(width: 8.0),
                Text('Close Tab', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        if (widget.tabs.length > 1)
          PopupMenuItem(
            value: 'close_others',
            height: 36.0,
            child: Row(
              children: const [
                Icon(Icons.clear_all_rounded, size: 16.0),
                SizedBox(width: 8.0),
                Text('Close Other Tabs', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'new_tab',
          height: 36.0,
          child: Row(
            children: const [
              Icon(Icons.add_rounded, size: 16.0),
              SizedBox(width: 8.0),
              Text('New Tab', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'close') {
        widget.onCloseTab(tab.id);
      } else if (value == 'duplicate') {
        widget.onDuplicateTab?.call(tab.id);
      } else if (value == 'close_others') {
        widget.onCloseOtherTabs?.call(tab.id);
      } else if (value == 'new_tab') {
        widget.onNewTab();
      }
    });
  }
}
