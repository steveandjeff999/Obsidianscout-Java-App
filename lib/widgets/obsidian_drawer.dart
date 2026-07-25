import 'dart:ui';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final drawerBg = isDark ? const Color(0xF70C0F14) : const Color(0xF9F8FAFC);
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final headerTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final sectionLabelColor = isDark ? Colors.white38 : Colors.black45;

    final menuItems = [
      {'index': 0, 'icon': Icons.dashboard_rounded, 'label': 'Dashboard', 'subtitle': 'Overview & Stats'},
      {'index': 1, 'icon': Icons.sports_esports_rounded, 'label': 'Match Scouting', 'subtitle': 'Live Game Data'},
      {'index': 2, 'icon': Icons.build_circle_rounded, 'label': 'Pit Scouting', 'subtitle': 'Robot Inspection'},
      {'index': 3, 'icon': Icons.rate_review_rounded, 'label': 'Qual Scouting', 'subtitle': 'Driver Performance'},
      {'index': 4, 'icon': Icons.bar_chart_rounded, 'label': 'Graphs & Analytics', 'subtitle': 'Visual Insights'},
      {'index': 7, 'icon': Icons.stars_rounded, 'label': 'Alliance Selection', 'subtitle': 'Playoff Pick Lists & Alliances'},
      {'index': 6, 'icon': Icons.chat_bubble_outline_rounded, 'label': 'Team Chat', 'subtitle': 'Channels & Messages'},
      {'index': 5, 'icon': Icons.settings_suggest_rounded, 'label': 'Settings & Cache', 'subtitle': 'Cache Manager & Config'},
    ];

    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            color: drawerBg,
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
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [ObsidianUITheme.primaryAccent, ObsidianUITheme.secondaryAccent],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ObsidianScout',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: headerTextColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              apiService.savedUsername.isNotEmpty ? apiService.savedUsername : 'Scout Operator',
                              style: const TextStyle(fontSize: 12, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.w600),
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
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                        child: Text(
                          'APPLICATION NAVIGATION',
                          style: TextStyle(
                            color: sectionLabelColor,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ...menuItems.map((item) {
                        final idx = item['index'] as int;
                        final isSelected = idx == currentIndex;
                        final unselectedItemColor = isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155);
                        final unselectedIconColor = isDark ? Colors.white70 : const Color(0xFF64748B);

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14.0),
                            color: isSelected ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.2) : Colors.transparent,
                            border: isSelected
                                ? Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5), width: 1.2)
                                : null,
                          ),
                          child: ListTile(
                            leading: Icon(
                              item['icon'] as IconData,
                              color: isSelected ? ObsidianUITheme.primaryAccent : unselectedIconColor,
                              size: 22.0,
                            ),
                            title: Text(
                              item['label'] as String,
                              style: TextStyle(
                                color: isSelected ? (isDark ? Colors.white : ObsidianUITheme.primaryAccent) : unselectedItemColor,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 14.0,
                              ),
                            ),
                            subtitle: Text(
                              item['subtitle'] as String,
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
                              onSelectScreen(idx);
                            },
                          ),
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: borderColor),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                        child: Text(
                          'TOOLS & UTILITIES',
                          style: TextStyle(
                            color: sectionLabelColor,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: isDark ? Colors.cyanAccent : const Color(0xFF0284C7),
                          size: 22,
                        ),
                        title: Text(
                          'QR & Barcode Scanner',
                          style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155),
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Camera / Clipboard Import',
                          style: TextStyle(color: sectionLabelColor, fontSize: 11),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenQrScanner();
                        },
                      ),
                      ListTile(
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
                            fontSize: 14,
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

                // Footer Sign Out
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.logout_rounded, color: ObsidianUITheme.errorRed),
                    title: const Text('Sign Out', style: TextStyle(color: ObsidianUITheme.errorRed, fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
