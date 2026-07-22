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
    final menuItems = [
      {'index': 0, 'icon': Icons.dashboard_rounded, 'label': 'Dashboard', 'subtitle': 'Overview & Stats'},
      {'index': 1, 'icon': Icons.sports_esports_rounded, 'label': 'Match Scouting', 'subtitle': 'Live Game Data'},
      {'index': 2, 'icon': Icons.build_circle_rounded, 'label': 'Pit Scouting', 'subtitle': 'Robot Inspection'},
      {'index': 3, 'icon': Icons.rate_review_rounded, 'label': 'Qual Scouting', 'subtitle': 'Driver Performance'},
      {'index': 4, 'icon': Icons.bar_chart_rounded, 'label': 'Graphs & Analytics', 'subtitle': 'Visual Insights'},
      {'index': 5, 'icon': Icons.settings_suggest_rounded, 'label': 'Settings & Cache', 'subtitle': 'Cache Manager & Config'},
    ];

    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            color: const Color(0xF70C0F14),
            child: Column(
              children: [
                // Drawer Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20.0, 56.0, 20.0, 20.0),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white10)),
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
                            const Text(
                              'ObsidianScout',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
                      const Padding(
                        padding: EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                        child: Text(
                          'APPLICATION NAVIGATION',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ...menuItems.map((item) {
                        final idx = item['index'] as int;
                        final isSelected = idx == currentIndex;
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
                              color: isSelected ? ObsidianUITheme.primaryAccent : Colors.white70,
                              size: 22.0,
                            ),
                            title: Text(
                              item['label'] as String,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 14.0,
                              ),
                            ),
                            subtitle: Text(
                              item['subtitle'] as String,
                              style: const TextStyle(color: Colors.white38, fontSize: 11.0),
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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: Colors.white12),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 12.0, bottom: 8.0),
                        child: Text(
                          'TOOLS & UTILITIES',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent, size: 22),
                        title: Text('QR & Barcode Scanner', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
                        subtitle: const Text('Camera / Clipboard Import', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenQrScanner();
                        },
                      ),
                    ],
                  ),
                ),

                // Footer Sign Out
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white10)),
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
