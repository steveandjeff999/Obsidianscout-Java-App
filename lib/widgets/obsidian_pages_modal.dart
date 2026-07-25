import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianPagesModal extends StatelessWidget {
  final int currentIndex;
  final Function(int) onSelectScreen;
  final VoidCallback onOpenQrScanner;

  const ObsidianPagesModal({
    super.key,
    required this.currentIndex,
    required this.onSelectScreen,
    required this.onOpenQrScanner,
  });

  static void show(BuildContext context, {
    required int currentIndex,
    required Function(int) onSelectScreen,
    required VoidCallback onOpenQrScanner,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ObsidianPagesModal(
        currentIndex: currentIndex,
        onSelectScreen: onSelectScreen,
        onOpenQrScanner: onOpenQrScanner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPages = [
      {
        'index': 0,
        'icon': Icons.dashboard_rounded,
        'name': 'Dashboard',
        'desc': 'Overview, event status, quick actions, & stats summary',
        'tag': 'Main',
        'color': ObsidianUITheme.primaryAccent,
      },
      {
        'index': 1,
        'icon': Icons.sports_esports_rounded,
        'name': 'Match Scouting',
        'desc': 'Score autonomous, teleop, endgame, and driver notes',
        'tag': 'Form',
        'color': Colors.amberAccent,
      },
      {
        'index': 2,
        'icon': Icons.build_circle_rounded,
        'name': 'Pit Scouting',
        'desc': 'Robot dimensions, drivetrain specs, intake, & photos',
        'tag': 'Form',
        'color': Colors.cyanAccent,
      },
      {
        'index': 3,
        'icon': Icons.rate_review_rounded,
        'name': 'Qualitative Scouting',
        'desc': 'Driver agility ratings, defense impact, & notes',
        'tag': 'Form',
        'color': Colors.lightGreenAccent,
      },
      {
        'index': 4,
        'icon': Icons.bar_chart_rounded,
        'name': 'Graphs & Analytics',
        'desc': 'Data visualizations, team comparisons, & rankings',
        'tag': 'Analytics',
        'color': ObsidianUITheme.secondaryAccent,
      },
      {
        'index': 5,
        'icon': Icons.settings_suggest_rounded,
        'name': 'Settings & Cache',
        'desc': 'Manage offline storage, server IP, & account sync',
        'tag': 'System',
        'color': Colors.orangeAccent,
      },
      {
        'index': 6,
        'icon': Icons.chat_bubble_outline_rounded,
        'name': 'Team Chat',
        'desc': 'Real-time team messaging, channels, & mentions',
        'tag': 'Social',
        'color': Colors.deepPurpleAccent,
      },
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      decoration: BoxDecoration(
        color: const Color(0xF00C0F14),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        border: Border.all(color: ObsidianUITheme.glassBorderLight, width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Handle Bar
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.widgets_rounded, color: ObsidianUITheme.primaryAccent, size: 26),
                        SizedBox(width: 10),
                        Text(
                          'All App Pages Directory',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Select any page to navigate instantly',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),

                // List of Pages
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      ...allPages.map((page) {
                        final idx = page['index'] as int;
                        final isSelected = idx == currentIndex;
                        final color = page['color'] as Color;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16.0),
                            color: isSelected ? color.withValues(alpha: 0.15) : const Color(0x15FFFFFF),
                            border: Border.all(
                              color: isSelected ? color : Colors.white10,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                            leading: Container(
                              padding: const EdgeInsets.all(10.0),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Icon(page['icon'] as IconData, color: color, size: 22.0),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    page['name'] as String,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 15.0,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    page['tag'] as String,
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                page['desc'] as String,
                                style: const TextStyle(color: Colors.white54, fontSize: 12.0),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: ObsidianUITheme.primaryAccent, size: 20)
                                : const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                            onTap: () {
                              Navigator.of(context).pop();
                              onSelectScreen(idx);
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 8),

                      // Tool: QR Scanner
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16.0),
                          color: Colors.cyanAccent.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1.0),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          leading: Container(
                            padding: const EdgeInsets.all(10.0),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent, size: 22.0),
                          ),
                          title: const Text(
                            'QR & Barcode Scanner',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.0),
                          ),
                          subtitle: const Text(
                            'Multi-code camera scanner & clipboard payload sync',
                            style: TextStyle(color: Colors.white54, fontSize: 12.0),
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded, color: Colors.cyanAccent, size: 20),
                          onTap: () {
                            Navigator.of(context).pop();
                            onOpenQrScanner();
                          },
                        ),
                      ),
                    ],
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
