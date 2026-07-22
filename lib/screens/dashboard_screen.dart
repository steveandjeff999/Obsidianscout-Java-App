import 'package:flutter/material.dart';
import '../widgets/obsidian_glass_card.dart';
import '../theme/obsidian_ui_theme.dart';

class DashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateMatch;
  final VoidCallback onNavigatePit;
  final VoidCallback onNavigateAnalytics;
  final VoidCallback onNavigateQrScanner;

  const DashboardScreen({
    super.key,
    required this.onNavigateMatch,
    required this.onNavigatePit,
    required this.onNavigateAnalytics,
    required this.onNavigateQrScanner,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 100.0, bottom: 120.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Banner Card
          ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: ObsidianUITheme.primaryAccent,
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Obsidianscout Portal',
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Connected to Local Server',
                          style: TextStyle(
                            fontSize: 12.0,
                            color: ObsidianUITheme.successGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                const Text(
                  'Scout matches in real-time, inspect team pits, scan offline barcodes, and view instant performance analytics.',
                  style: TextStyle(fontSize: 14.0, color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(left: 20.0, top: 12.0, bottom: 4.0),
            child: Text(
              'QUICK ACTIONS',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 1.0,
              ),
            ),
          ),

          // Action Grid
          Row(
            children: [
              Expanded(
                child: ObsidianGlassCard(
                  onTap: onNavigateMatch,
                  margin: const EdgeInsets.only(left: 16.0, right: 8.0, top: 8.0, bottom: 8.0),
                  child: const Column(
                    children: [
                      Icon(Icons.sports_esports_rounded, size: 36.0, color: ObsidianUITheme.primaryAccent),
                      SizedBox(height: 12.0),
                      Text('Match Scout', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 4.0),
                      Text('Record Match Data', style: TextStyle(fontSize: 11.0, color: Colors.white54)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ObsidianGlassCard(
                  onTap: onNavigatePit,
                  margin: const EdgeInsets.only(left: 8.0, right: 16.0, top: 8.0, bottom: 8.0),
                  child: const Column(
                    children: [
                      Icon(Icons.build_circle_rounded, size: 36.0, color: ObsidianUITheme.secondaryAccent),
                      SizedBox(height: 12.0),
                      Text('Pit Scout', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 4.0),
                      Text('Inspect Robots', style: TextStyle(fontSize: 11.0, color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // QR Scanner Quick Action Card
          ObsidianGlassCard(
            onTap: onNavigateQrScanner,
            child: const Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 32.0, color: ObsidianUITheme.primaryAccent),
                SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QR & Barcode Scanner',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: Colors.white),
                      ),
                      SizedBox(height: 2.0),
                      Text(
                        'Scan offline barcodes, manage queue, & upload to server',
                        style: TextStyle(fontSize: 12.0, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: Colors.white38),
              ],
            ),
          ),

          ObsidianGlassCard(
            onTap: onNavigateAnalytics,
            child: const Row(
              children: [
                Icon(Icons.insights_rounded, size: 32.0, color: ObsidianUITheme.successGreen),
                SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team Analytics & Rankings',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: Colors.white),
                      ),
                      SizedBox(height: 2.0),
                      Text(
                        'View charts, alliance predictions, and live ranks',
                        style: TextStyle(fontSize: 12.0, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: Colors.white38),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
