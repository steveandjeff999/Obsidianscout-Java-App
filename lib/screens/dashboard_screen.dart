import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../theme/obsidian_ui_theme.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatelessWidget {
  final ApiService? apiService;
  final VoidCallback onNavigateMatch;
  final VoidCallback onNavigatePit;
  final VoidCallback onNavigateAnalytics;
  final VoidCallback onNavigateQrScanner;
  final VoidCallback? onNavigateAlliance;
  final bool isVisible;
  final bool isBarsVisible;

  const DashboardScreen({
    super.key,
    this.apiService,
    required this.onNavigateMatch,
    required this.onNavigatePit,
    required this.onNavigateAnalytics,
    required this.onNavigateQrScanner,
    this.onNavigateAlliance,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isConnected = apiService?.isLoggedIn ?? true;
    final String statusText = isConnected ? context.tr('connection.online') : context.tr('connection.offline');
    final Color statusColor = isConnected ? ObsidianUITheme.successGreen : Colors.redAccent;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(top: 4.0, bottom: isBarsVisible ? 120.0 : 20.0),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('app.title'),
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12.0,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Text(
                  context.tr('dashboard.notice'),
                  style: TextStyle(fontSize: 14.0, color: secondaryTextColor, height: 1.4),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 20.0, top: 12.0, bottom: 4.0),
            child: Text(
              'QUICK ACTIONS',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                color: tertiaryTextColor,
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
                  child: Column(
                    children: [
                      const Icon(Icons.sports_esports_rounded, size: 36.0, color: ObsidianUITheme.primaryAccent),
                      const SizedBox(height: 12.0),
                      Text(context.tr('nav.match_scout'), style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
                      const SizedBox(height: 4.0),
                      Text(context.tr('subtitle.match_scout'), style: TextStyle(fontSize: 11.0, color: tertiaryTextColor)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ObsidianGlassCard(
                  onTap: onNavigatePit,
                  margin: const EdgeInsets.only(left: 8.0, right: 16.0, top: 8.0, bottom: 8.0),
                  child: Column(
                    children: [
                      const Icon(Icons.build_circle_rounded, size: 36.0, color: ObsidianUITheme.secondaryAccent),
                      const SizedBox(height: 12.0),
                      Text(context.tr('nav.pit_scout'), style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
                      const SizedBox(height: 4.0),
                      Text(context.tr('subtitle.pit_scout'), style: TextStyle(fontSize: 11.0, color: tertiaryTextColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // QR Scanner Quick Action Card
          ObsidianGlassCard(
            onTap: onNavigateQrScanner,
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner_rounded, size: 32.0, color: ObsidianUITheme.primaryAccent),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('scanner.title'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        context.tr('scanner.scan_qr'),
                        style: TextStyle(fontSize: 12.0, color: tertiaryTextColor),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
              ],
            ),
          ),

          ObsidianGlassCard(
            onTap: onNavigateAnalytics,
            child: Row(
              children: [
                const Icon(Icons.insights_rounded, size: 32.0, color: ObsidianUITheme.successGreen),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('nav.graphs'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        context.tr('subtitle.graphs'),
                        style: TextStyle(fontSize: 12.0, color: tertiaryTextColor),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
              ],
            ),
          ),

          ObsidianGlassCard(
            onTap: onNavigateAlliance,
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, size: 32.0, color: Colors.amberAccent),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('nav.alliance_selection'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        context.tr('subtitle.alliance_selection'),
                        style: TextStyle(fontSize: 12.0, color: tertiaryTextColor),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
