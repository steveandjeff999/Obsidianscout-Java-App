import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianDesktopAppBar extends StatefulWidget {
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
  State<ObsidianDesktopAppBar> createState() => _ObsidianDesktopAppBarState();
}

class _ObsidianDesktopAppBarState extends State<ObsidianDesktopAppBar> {
  @override
  void initState() {
    super.initState();
    widget.apiService.settingsNotifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.apiService.settingsNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final bgColor = isDark
        ? ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.85)
        : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.95);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    final eventKey = widget.apiService.currentSettings?.eventKey ?? '';

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
                Flexible(
                  child: Text(
                    'ObsidianScout',
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Icon(Icons.chevron_right_rounded, size: 16.0, color: secondaryTextColor.withValues(alpha: 0.5)),
                ),
                Flexible(
                  child: Text(
                    widget.title,
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
                color: primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color: primaryAccent.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available_rounded, size: 12.0, color: primaryAccent),
                  const SizedBox(width: 4.0),
                  Text(
                    eventKey.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      color: primaryAccent,
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
                  width: 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 6.0),
                Text(
                  widget.isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: widget.isOnline ? ObsidianUITheme.successGreen : Colors.redAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Custom Actions
          if (widget.actions != null) ...widget.actions!,

          // QR Scanner Button
          if (widget.apiService.hasPageAccess('qr-scanner') && widget.onOpenQrScanner != null)
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                size: 19.0,
                color: isDark ? Colors.cyanAccent : const Color(0xFF0284C7),
              ),
              tooltip: 'QR & Barcode Scanner',
              onPressed: widget.onOpenQrScanner,
              constraints: const BoxConstraints(minWidth: 34.0, minHeight: 34.0),
              padding: EdgeInsets.zero,
            ),

          // Theme Switcher Button
          IconButton(
            icon: Icon(
              widget.apiService.themeMode == ThemeMode.light
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              size: 19.0,
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
            constraints: const BoxConstraints(minWidth: 34.0, minHeight: 34.0),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
