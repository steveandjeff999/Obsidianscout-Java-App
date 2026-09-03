import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/obsidian_glass_card.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatelessWidget {
  final ApiService? apiService;
  final VoidCallback onNavigateMatch;
  final VoidCallback onNavigatePit;
  final VoidCallback onNavigateAnalytics;
  final VoidCallback onNavigateQrScanner;
  final VoidCallback? onNavigateAlliance;
  final VoidCallback? onNavigatePrescout;
  final VoidCallback? onNavigateHistory;
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
    this.onNavigatePrescout,
    this.onNavigateHistory,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: apiService?.uiMode);
    final bool isConnected = apiService?.isLoggedIn ?? true;
    final String statusText = isConnected ? context.tr('connection.online') : context.tr('connection.offline');
    final Color statusColor = isConnected ? ObsidianUITheme.successGreen : Colors.redAccent;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);

    if (isDesktop) {
      return _buildDesktopDashboard(context, primaryTextColor, secondaryTextColor, tertiaryTextColor, statusColor, statusText);
    }

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
                    Image.asset(
                      'assets/images/obsidian-512.png',
                      width: 40.0,
                      height: 40.0,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
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

          // Quick Actions Section
          Builder(
            builder: (context) {
              final canScout = apiService?.hasPageAccess('scout') ?? true;
              final canPitScout = apiService?.hasPageAccess('pit-scout') ?? true;
              final canQr = apiService?.hasPageAccess('qr-scanner') ?? true;
              final canAnalytics = apiService?.hasPageAccess('graphs') ?? true;
              final canAlliance = (apiService?.hasPageAccess('alliance-selection') ?? true) && onNavigateAlliance != null;
              final canPrescout = (apiService?.hasPageAccess('prescout') ?? true) && onNavigatePrescout != null;

              final hasAnyActions = canScout || canPitScout || canQr || canAnalytics || canAlliance || canPrescout;
              if (!hasAnyActions) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  // Scouting Cards
                  if (canScout && canPitScout)
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
                    )
                  else if (canScout)
                    ObsidianGlassCard(
                      onTap: onNavigateMatch,
                      child: Row(
                        children: [
                          const Icon(Icons.sports_esports_rounded, size: 32.0, color: ObsidianUITheme.primaryAccent),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.tr('nav.match_scout'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor)),
                                const SizedBox(height: 2.0),
                                Text(context.tr('subtitle.match_scout'), style: TextStyle(fontSize: 12.0, color: tertiaryTextColor)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
                        ],
                      ),
                    )
                  else if (canPitScout)
                    ObsidianGlassCard(
                      onTap: onNavigatePit,
                      child: Row(
                        children: [
                          const Icon(Icons.build_circle_rounded, size: 32.0, color: ObsidianUITheme.secondaryAccent),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.tr('nav.pit_scout'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor)),
                                const SizedBox(height: 2.0),
                                Text(context.tr('subtitle.pit_scout'), style: TextStyle(fontSize: 12.0, color: tertiaryTextColor)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
                        ],
                      ),
                    ),

                  // QR Scanner Quick Action Card
                  if (canQr)
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

                  if (canAnalytics)
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

                  if (canAlliance)
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

                  if (canPrescout)
                    ObsidianGlassCard(
                      onTap: onNavigatePrescout,
                      child: Row(
                        children: [
                          const Icon(Icons.history_edu_rounded, size: 32.0, color: Colors.cyanAccent),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('nav.prescout'),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  context.tr('subtitle.prescout'),
                                  style: TextStyle(fontSize: 12.0, color: tertiaryTextColor),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16.0, color: faintTextColor),
                        ],
                      ),
                    ),

                  if (onNavigateHistory != null)
                    ObsidianGlassCard(
                      onTap: onNavigateHistory,
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 32.0, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('nav.scout_history'),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  context.tr('subtitle.scout_history'),
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
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDashboard(
    BuildContext context,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color tertiaryTextColor,
    Color statusColor,
    String statusText,
  ) {
    final eventKey = apiService?.currentSettings?.eventKey ?? '';
    final program = apiService?.currentProgram ?? 'FRC';
    final user = apiService?.currentUser;
    final roleLabel = user?.roleDisplayLabel ?? (apiService?.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');

    final canScout = apiService?.hasPageAccess('scout') ?? true;
    final canPitScout = apiService?.hasPageAccess('pit-scout') ?? true;
    final canQr = apiService?.hasPageAccess('qr-scanner') ?? true;
    final canAnalytics = apiService?.hasPageAccess('graphs') ?? true;
    final canAlliance = (apiService?.hasPageAccess('alliance-selection') ?? true) && onNavigateAlliance != null;
    final canPrescout = (apiService?.hasPageAccess('prescout') ?? true) && onNavigatePrescout != null;
    final canHistory = onNavigateHistory != null;

    final actions = [
      if (canScout)
        _DesktopActionItem(
          icon: Icons.sports_esports_rounded,
          title: context.tr('nav.match_scout'),
          subtitle: context.tr('subtitle.match_scout'),
          accentColor: ObsidianUITheme.primaryAccent,
          onTap: onNavigateMatch,
        ),
      if (canPitScout)
        _DesktopActionItem(
          icon: Icons.build_circle_rounded,
          title: context.tr('nav.pit_scout'),
          subtitle: context.tr('subtitle.pit_scout'),
          accentColor: ObsidianUITheme.secondaryAccent,
          onTap: onNavigatePit,
        ),
      if (canAnalytics)
        _DesktopActionItem(
          icon: Icons.insights_rounded,
          title: context.tr('nav.graphs'),
          subtitle: context.tr('subtitle.graphs'),
          accentColor: ObsidianUITheme.successGreen,
          onTap: onNavigateAnalytics,
        ),
      if (canQr)
        _DesktopActionItem(
          icon: Icons.qr_code_scanner_rounded,
          title: context.tr('scanner.title'),
          subtitle: context.tr('scanner.scan_qr'),
          accentColor: Colors.cyanAccent,
          onTap: onNavigateQrScanner,
        ),
      if (canAlliance)
        _DesktopActionItem(
          icon: Icons.stars_rounded,
          title: context.tr('nav.alliance_selection'),
          subtitle: context.tr('subtitle.alliance_selection'),
          accentColor: Colors.amberAccent,
          onTap: onNavigateAlliance!,
        ),
      if (canPrescout)
        _DesktopActionItem(
          icon: Icons.history_edu_rounded,
          title: context.tr('nav.prescout'),
          subtitle: context.tr('subtitle.prescout'),
          accentColor: const Color(0xFF60A5FA),
          onTap: onNavigatePrescout!,
        ),
      if (canHistory)
        _DesktopActionItem(
          icon: Icons.history_rounded,
          title: context.tr('nav.scout_history'),
          subtitle: context.tr('subtitle.scout_history'),
          accentColor: const Color(0xFF38BDF8),
          onTap: onNavigateHistory!,
        ),
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Desktop Status & Overview Card
          ObsidianGlassCard(
            margin: const EdgeInsets.only(bottom: 16.0),
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/obsidian-512.png',
                  width: 48.0,
                  height: 48.0,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.shield_rounded,
                    color: ObsidianUITheme.primaryAccent,
                    size: 28.0,
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10.0,
                        runSpacing: 6.0,
                        children: [
                          Text(
                            program.isNotEmpty ? 'ObsidianScout $program' : 'ObsidianScout',
                            style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6.0),
                              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
                                const SizedBox(width: 4),
                                Text(statusText, style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: statusColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        eventKey.isNotEmpty
                            ? 'Active Competition: ${eventKey.toUpperCase()}  •  User Role: $roleLabel'
                            : 'Logged in as ${user?.username ?? "Operator"}  •  $roleLabel',
                        style: TextStyle(fontSize: 13.0, color: secondaryTextColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick Actions Grid (Multi-column on PC)
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Text(
              'QUICK ACTIONS',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: tertiaryTextColor, letterSpacing: 1.0),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1100 ? 4 : (constraints.maxWidth > 700 ? 3 : 2);
              final spacing = 10.0;
              final itemWidth = (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: actions.map((act) {
                  return SizedBox(
                    width: itemWidth,
                    child: ObsidianGlassCard(
                      onTap: act.onTap,
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: act.accentColor.withValues(alpha: 0.18),
                            ),
                            child: Icon(act.icon, color: act.accentColor, size: 20.0),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  act.title,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: primaryTextColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  act.subtitle,
                                  style: TextStyle(fontSize: 11.0, color: tertiaryTextColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12.0, color: tertiaryTextColor.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 18.0),

          // Operational Notice & System Notes
          ObsidianGlassCard(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 18.0),
                    const SizedBox(width: 8.0),
                    Text(
                      'STATION GUIDELINES & SYNC STATUS',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: primaryTextColor, letterSpacing: 0.8),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Text(
                  context.tr('dashboard.notice'),
                  style: TextStyle(fontSize: 13.0, color: secondaryTextColor, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopActionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _DesktopActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });
}

