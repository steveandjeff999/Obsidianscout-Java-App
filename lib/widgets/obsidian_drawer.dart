import 'dart:ui';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianNavigationDrawer extends StatelessWidget {
  final ApiService apiService;
  final int currentIndex;
  final Function(int) onSelectScreen;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onLogout;

  const ObsidianNavigationDrawer({
    super.key,
    required this.apiService,
    required this.currentIndex,
    required this.onSelectScreen,
    required this.onOpenQrScanner,
    required this.onLogout,
  });

  int _getHue(String text) {
    var hue = 0;
    for (var i = 0; i < text.length; i++) {
      hue = (hue + text.codeUnitAt(i) * 37) % 360;
    }
    return hue;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final drawerBg = isDark ? const Color(0xF70C0F14) : const Color(0xF9F8FAFC);
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final headerTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final sectionLabelColor = isDark ? Colors.white38 : Colors.black45;

    final user = apiService.currentUser;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (apiService.savedUsername.isNotEmpty ? apiService.savedUsername : 'Scout Operator');
    final roleLabel = user?.roleDisplayLabel ?? (apiService.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');
    final program = apiService.currentProgram;
    final initials = username.isNotEmpty
        ? (username.length >= 2 ? username.substring(0, 2).toUpperCase() : username.toUpperCase())
        : 'OS';
    final avatarHue = _getHue(username).toDouble();
    final avatarBgColor = HSLColor.fromAHSL(1.0, avatarHue, 0.65, 0.45).toColor();

    // Define navigation sections matching the website structure
    final sections = [
      {
        'titleKey': null, // Top-level standalone item
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
            'action': onOpenQrScanner,
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

    return Drawer(
      backgroundColor: drawerBg,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Column(
              children: [
                // Drawer Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20.0, 56.0, 20.0, 20.0),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      // User Avatar with deterministic color or profile picture
                      if (user?.profilePicture != null && user!.profilePicture!.isNotEmpty)
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: NetworkImage(user.profilePicture!),
                          backgroundColor: avatarBgColor,
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarBgColor,
                            boxShadow: [
                              BoxShadow(
                                color: avatarBgColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              program.isNotEmpty ? 'ObsidianScout $program' : 'ObsidianScout',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: headerTextColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: ObsidianUITheme.primaryAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Menu Items List
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                    children: [
                      ...sections.expand((section) {
                        final rawItems = section['items'] as List<Map<String, dynamic>>;
                        // Filter items by team custom role access
                        final visibleItems = rawItems.where((item) {
                          final pageId = item['pageId'] as String;
                          return apiService.hasPageAccess(pageId);
                        }).toList();

                        if (visibleItems.isEmpty) return <Widget>[];

                        final titleKey = section['titleKey'] as String?;

                        return [
                          if (titleKey != null) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(color: borderColor),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 12.0, bottom: 6.0, top: 4.0),
                              child: Text(
                                context.tr(titleKey).toUpperCase(),
                                style: TextStyle(
                                  color: sectionLabelColor,
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                          ...visibleItems.map((item) {
                            final isAction = item['isAction'] == true;
                            final idx = item['index'] as int?;
                            final isSelected = !isAction && idx == currentIndex;
                            final unselectedItemColor =
                                isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155);
                            final unselectedIconColor = isDark ? Colors.white70 : const Color(0xFF64748B);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Material(
                                color: isSelected
                                    ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.0),
                                  side: isSelected
                                      ? BorderSide(
                                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
                                          width: 1.2,
                                        )
                                      : BorderSide.none,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                dense: true,
                                leading: Icon(
                                  item['icon'] as IconData,
                                  color: isSelected ? ObsidianUITheme.primaryAccent : unselectedIconColor,
                                  size: 22.0,
                                ),
                                title: Text(
                                  context.tr(item['labelKey'] as String),
                                  style: TextStyle(
                                    color: isSelected
                                        ? (isDark ? Colors.white : ObsidianUITheme.primaryAccent)
                                        : unselectedItemColor,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  context.tr(item['subKey'] as String),
                                  style: TextStyle(color: sectionLabelColor, fontSize: 11.0),
                                ),
                                trailing: isSelected
                                    ? Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: ObsidianUITheme.primaryAccent,
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  if (isAction) {
                                    final action = item['action'] as VoidCallback?;
                                    action?.call();
                                  } else if (idx != null) {
                                    onSelectScreen(idx);
                                  }
                                },
                              ),
                            ),
                          );
                          }),
                        ];
                      }),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: borderColor),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                        child: Text(
                          'PREFERENCES',
                          style: TextStyle(
                            color: sectionLabelColor,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          apiService.themeMode == ThemeMode.light
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: apiService.themeMode == ThemeMode.light
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFFFB703),
                          size: 22,
                        ),
                        title: Text(
                          apiService.themeMode == ThemeMode.light ? 'Light Mode Active' : 'Dark Mode Active',
                          style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155),
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          apiService.themeMode == ThemeMode.light ? 'Toggle dark mode' : 'Toggle light mode',
                          style: TextStyle(color: sectionLabelColor, fontSize: 11),
                        ),
                        trailing: Switch.adaptive(
                          value: apiService.themeMode == ThemeMode.light,
                          activeThumbColor: const Color(0xFF4F46E5),
                          onChanged: (value) {
                            apiService.setThemeMode(value ? ThemeMode.light : ThemeMode.dark);
                          },
                        ),
                        onTap: () {
                          final nextMode = apiService.themeMode == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          apiService.setThemeMode(nextMode);
                        },
                      ),
                    ],
                  ),
                ),

                // Footer Sign Out & Server info
                Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.logout_rounded, color: ObsidianUITheme.errorRed),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(color: ObsidianUITheme.errorRed, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    trailing: Text(
                      'ObsidianScout Mobile',
                      style: TextStyle(color: sectionLabelColor, fontSize: 10),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
