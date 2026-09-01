import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_user_avatar.dart';

class ObsidianDesktopSidebar extends StatefulWidget {
  final ApiService apiService;
  final int currentIndex;
  final Function(int) onSelectScreen;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onLogout;
  final bool isCollapsed;
  final ValueChanged<bool>? onToggleCollapse;

  const ObsidianDesktopSidebar({
    super.key,
    required this.apiService,
    required this.currentIndex,
    required this.onSelectScreen,
    required this.onOpenQrScanner,
    required this.onLogout,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<ObsidianDesktopSidebar> createState() => _ObsidianDesktopSidebarState();
}

class _ObsidianDesktopSidebarState extends State<ObsidianDesktopSidebar> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.isCollapsed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final sidebarBg = isDark ? const Color(0xF20A0D14) : const Color(0xF8F1F5F9);
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final headerTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final sectionLabelColor = isDark ? Colors.white38 : Colors.black45;

    final user = widget.apiService.currentUser;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (widget.apiService.savedUsername.isNotEmpty ? widget.apiService.savedUsername : 'Scout Operator');
    final roleLabel = user?.roleDisplayLabel ?? (widget.apiService.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');
    final program = widget.apiService.currentProgram;

    final sections = [
      {
        'titleKey': null,
        'items': [
          {
            'pageId': 'dashboard',
            'index': 0,
            'icon': Icons.dashboard_rounded,
            'labelKey': 'nav.dashboard',
            'subKey': 'subtitle.dashboard',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.scouting',
        'items': [
          {
            'pageId': 'scout',
            'index': 1,
            'icon': Icons.sports_esports_rounded,
            'labelKey': 'nav.match_scout',
            'subKey': 'subtitle.match_scout',
          },
          {
            'pageId': 'pit-scout',
            'index': 2,
            'icon': Icons.build_circle_rounded,
            'labelKey': 'nav.pit_scout',
            'subKey': 'subtitle.pit_scout',
          },
          {
            'pageId': 'qual-scout',
            'index': 3,
            'icon': Icons.rate_review_rounded,
            'labelKey': 'nav.qual_scout',
            'subKey': 'subtitle.qual_scout',
          },
          {
            'pageId': 'prescout',
            'index': 11,
            'icon': Icons.history_edu_rounded,
            'labelKey': 'nav.prescout',
            'subKey': 'subtitle.prescout',
          },
          {
            'pageId': 'qr-scanner',
            'isAction': true,
            'action': widget.onOpenQrScanner,
            'icon': Icons.qr_code_scanner_rounded,
            'labelKey': 'scanner.title',
            'subKey': 'scanner.scan_qr',
          },
          {
            'pageId': 'scout-history',
            'index': 17,
            'icon': Icons.history_rounded,
            'labelKey': 'nav.scout_history',
            'subKey': 'subtitle.scout_history',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.data',
        'items': [
          {
            'pageId': 'graphs',
            'index': 4,
            'icon': Icons.bar_chart_rounded,
            'labelKey': 'nav.graphs',
            'subKey': 'subtitle.graphs',
          },
          {
            'pageId': 'custom-analytics',
            'index': 18,
            'icon': Icons.auto_graph_rounded,
            'labelKey': 'nav.custom_analytics',
            'subKey': 'subtitle.custom_analytics',
          },
          {
            'pageId': 'all-data',
            'index': 12,
            'icon': Icons.dataset_rounded,
            'labelKey': 'nav.all-data',
            'subKey': 'subtitle.all-data',
          },
          {
            'pageId': 'match-data',
            'index': 13,
            'icon': Icons.table_chart_rounded,
            'labelKey': 'nav.match-data',
            'subKey': 'subtitle.match-data',
          },
          {
            'pageId': 'pit-data',
            'index': 14,
            'icon': Icons.engineering_rounded,
            'labelKey': 'nav.pit-data',
            'subKey': 'subtitle.pit-data',
          },
          {
            'pageId': 'qual-data',
            'index': 15,
            'icon': Icons.insights_rounded,
            'labelKey': 'nav.qual-data',
            'subKey': 'subtitle.qual-data',
          },
          {
            'pageId': 'data-validation',
            'index': 16,
            'icon': Icons.fact_check_rounded,
            'labelKey': 'nav.data-validation',
            'subKey': 'subtitle.data-validation',
          },
          {
            'pageId': 'teams',
            'index': 8,
            'icon': Icons.groups_rounded,
            'labelKey': 'nav.teams',
            'subKey': 'subtitle.teams',
          },
          {
            'pageId': 'matches',
            'index': 9,
            'icon': Icons.event_note_rounded,
            'labelKey': 'nav.matches',
            'subKey': 'subtitle.matches',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.strategy',
        'items': [
          {
            'pageId': 'alliance-selection',
            'index': 7,
            'icon': Icons.stars_rounded,
            'labelKey': 'nav.alliance_selection',
            'subKey': 'subtitle.alliance_selection',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.admin',
        'items': [
          {
            'pageId': 'chat',
            'index': 6,
            'icon': Icons.chat_bubble_outline_rounded,
            'labelKey': 'nav.team_chat',
            'subKey': 'subtitle.chat',
          },
          {
            'pageId': 'admin-settings',
            'index': 10,
            'icon': Icons.tune_rounded,
            'labelKey': 'nav.config_editor',
            'subKey': 'subtitle.config_editor',
          },
          {
            'pageId': 'settings',
            'index': 5,
            'icon': Icons.settings_suggest_rounded,
            'labelKey': 'nav.settings_cache',
            'subKey': 'subtitle.settings',
          },
          {
            'pageId': 'contact',
            'index': 19,
            'icon': Icons.contact_support_rounded,
            'labelKey': 'nav.contact',
            'subKey': 'subtitle.contact',
          },
        ],
      },
    ];

    final width = _collapsed ? 72.0 : 240.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Column(
        children: [
          // Header: Brand & Collapse Toggle
          Container(
            height: 60.0,
            padding: EdgeInsets.symmetric(horizontal: _collapsed ? 12.0 : 16.0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: _collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                if (!_collapsed)
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: ObsidianUITheme.primaryAccent,
                            size: 18.0,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            program.isNotEmpty ? 'Obsidian $program' : 'ObsidianScout',
                            style: TextStyle(
                              fontSize: 14.0,
                              fontWeight: FontWeight.bold,
                              color: headerTextColor,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    _collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                    color: headerTextColor.withValues(alpha: 0.7),
                    size: 20.0,
                  ),
                  tooltip: _collapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // User Profile Compact Card
          if (!_collapsed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              margin: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  ObsidianUserAvatar(
                    profilePicture: user?.profilePicture,
                    username: username,
                    size: 32,
                    serverUrl: widget.apiService.currentServerUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: headerTextColor,
                          ),
                        ),
                        Text(
                          roleLabel,
                          style: const TextStyle(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w600,
                            color: ObsidianUITheme.primaryAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Tooltip(
                message: '$username ($roleLabel)',
                child: ObsidianUserAvatar(
                  profilePicture: user?.profilePicture,
                  username: username,
                  size: 36,
                  serverUrl: widget.apiService.currentServerUrl,
                ),
              ),
            ),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              children: [
                ...sections.expand((section) {
                  final rawItems = section['items'] as List<Map<String, dynamic>>;
                  final visibleItems = rawItems.where((item) {
                    final pageId = item['pageId'] as String;
                    return widget.apiService.hasPageAccess(pageId);
                  }).toList();

                  if (visibleItems.isEmpty) return <Widget>[];
                  final titleKey = section['titleKey'] as String?;

                  return [
                    if (titleKey != null && !_collapsed)
                      Padding(
                        padding: const EdgeInsets.only(left: 10.0, top: 12.0, bottom: 4.0),
                        child: Text(
                          context.tr(titleKey).toUpperCase(),
                          style: TextStyle(
                            color: sectionLabelColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                    else if (titleKey != null && _collapsed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Divider(color: borderColor, height: 1),
                      ),
                    ...visibleItems.map((item) {
                      final isAction = item['isAction'] == true;
                      final idx = item['index'] as int?;
                      final isSelected = !isAction && idx == widget.currentIndex;
                      final label = context.tr(item['labelKey'] as String);

                      final unselectedItemColor =
                          isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF334155);
                      final unselectedIconColor = isDark ? Colors.white60 : const Color(0xFF64748B);

                      if (_collapsed) {
                        return Tooltip(
                          message: label,
                          preferBelow: false,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Material(
                              color: isSelected
                                  ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10.0),
                              child: InkWell(
                                onTap: () {
                                  if (isAction) {
                                    final action = item['action'] as VoidCallback?;
                                    action?.call();
                                  } else if (idx != null) {
                                    widget.onSelectScreen(idx);
                                  }
                                },
                                borderRadius: BorderRadius.circular(10.0),
                                child: Container(
                                  height: 40.0,
                                  alignment: Alignment.center,
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          borderRadius: BorderRadius.circular(10.0),
                                          border: Border.all(
                                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
                                            width: 1.0,
                                          ),
                                        )
                                      : null,
                                  child: Icon(
                                    item['icon'] as IconData,
                                    size: 20.0,
                                    color: isSelected ? ObsidianUITheme.primaryAccent : unselectedIconColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Material(
                          color: isSelected
                              ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10.0),
                          child: InkWell(
                            onTap: () {
                              if (isAction) {
                                final action = item['action'] as VoidCallback?;
                                action?.call();
                              } else if (idx != null) {
                                widget.onSelectScreen(idx);
                              }
                            },
                            borderRadius: BorderRadius.circular(10.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
                              decoration: isSelected
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(10.0),
                                      border: Border.all(
                                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                                        width: 1.0,
                                      ),
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 18.0,
                                    color: isSelected ? ObsidianUITheme.primaryAccent : unselectedIconColor,
                                  ),
                                  const SizedBox(width: 10.0),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? (isDark ? Colors.white : ObsidianUITheme.primaryAccent)
                                            : unselectedItemColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: ObsidianUITheme.primaryAccent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ];
                }),
              ],
            ),
          ),

          // Footer: Quick Theme toggle & Logout
          Container(
            padding: EdgeInsets.symmetric(horizontal: _collapsed ? 6.0 : 10.0, vertical: 8.0),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: _collapsed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.apiService.themeMode == ThemeMode.light
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 18.0,
                          color: widget.apiService.themeMode == ThemeMode.light
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFFFB703),
                        ),
                        tooltip: widget.apiService.themeMode == ThemeMode.light
                            ? 'Switch to Dark Mode'
                            : 'Switch to Light Mode',
                        onPressed: () {
                          final nextMode = widget.apiService.themeMode == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          widget.apiService.setThemeMode(nextMode);
                        },
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 4.0),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18.0, color: ObsidianUITheme.errorRed),
                        tooltip: 'Sign Out',
                        onPressed: widget.onLogout,
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.apiService.themeMode == ThemeMode.light
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 18.0,
                          color: widget.apiService.themeMode == ThemeMode.light
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFFFB703),
                        ),
                        tooltip: widget.apiService.themeMode == ThemeMode.light
                            ? 'Switch to Dark Mode'
                            : 'Switch to Light Mode',
                        onPressed: () {
                          final nextMode = widget.apiService.themeMode == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          widget.apiService.setThemeMode(nextMode);
                        },
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                      Expanded(
                        child: Text(
                          'ObsidianScout PC',
                          style: TextStyle(fontSize: 10.5, color: sectionLabelColor),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18.0, color: ObsidianUITheme.errorRed),
                        tooltip: 'Sign Out',
                        onPressed: widget.onLogout,
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
