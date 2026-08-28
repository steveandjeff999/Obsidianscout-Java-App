import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianDesktopAppBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isOnline;
  final ApiService apiService;
  final VoidCallback? onOpenQrScanner;
  final List<Widget>? actions;

  const ObsidianDesktopAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isOnline,
    required this.apiService,
    this.onOpenQrScanner,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final bgColor = isDark ? const Color(0xDE0E1118) : const Color(0xF2F8FAFC);
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final eventKey = apiService.currentSettings?.eventKey ?? '';

    return Container(
      width: double.infinity,
      height: 52.0,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          // Breadcrumb Title
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ObsidianScout',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w500,
                    color: secondaryTextColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Icon(Icons.chevron_right_rounded, size: 16.0, color: secondaryTextColor.withValues(alpha: 0.5)),
                ),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8.0),

          // Event Badge (if set)
          if (eventKey.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
              decoration: BoxDecoration(
                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available_rounded, size: 12.0, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 4.0),
                  Text(
                    eventKey.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      color: ObsidianUITheme.primaryAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Online / Offline Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
            margin: const EdgeInsets.only(right: 8.0),
            decoration: BoxDecoration(
              color: isOnline ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: isOnline ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 6.0),
                Text(
                  isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Custom Actions
          if (actions != null) ...actions!,

          // QR Scanner Button
          if (apiService.hasPageAccess('qr-scanner') && onOpenQrScanner != null)
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                size: 19.0,
                color: isDark ? Colors.cyanAccent : const Color(0xFF0284C7),
              ),
              tooltip: 'QR & Barcode Scanner',
              onPressed: onOpenQrScanner,
              constraints: const BoxConstraints(minWidth: 34.0, minHeight: 34.0),
              padding: EdgeInsets.zero,
            ),

          // Theme Switcher Button
          IconButton(
            icon: Icon(
              apiService.themeMode == ThemeMode.light
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              size: 19.0,
              color: apiService.themeMode == ThemeMode.light
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFFFFB703),
            ),
            tooltip: apiService.themeMode == ThemeMode.light
                ? 'Switch to Dark Mode'
                : 'Switch to Light Mode',
            onPressed: () {
              final nextMode = apiService.themeMode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
              apiService.setThemeMode(nextMode);
            },
            constraints: const BoxConstraints(minWidth: 34.0, minHeight: 34.0),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
