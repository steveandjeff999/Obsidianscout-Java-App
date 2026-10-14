import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

/// Shown at the top of every scouting screen: how many submissions are saved on this
/// device only and haven't reached the server yet. Hidden when everything is uploaded.
class SyncStatusBanner extends StatefulWidget {
  final ApiService apiService;
  final EdgeInsetsGeometry margin;

  const SyncStatusBanner({
    super.key,
    required this.apiService,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  StreamSubscription<bool>? _onlineSub;
  Timer? _allClearTimer;
  int _lastCount = 0;
  bool _showAllClear = false;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.apiService.outboxCount.value;
    widget.apiService.outboxCount.addListener(_onCountChanged);
    widget.apiService.outboxSyncing.addListener(_rebuild);
    _onlineSub = widget.apiService.onOnlineStatusChanged.listen((_) => _rebuild());
  }

  @override
  void dispose() {
    widget.apiService.outboxCount.removeListener(_onCountChanged);
    widget.apiService.outboxSyncing.removeListener(_rebuild);
    _onlineSub?.cancel();
    _allClearTimer?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onCountChanged() {
    final count = widget.apiService.outboxCount.value;
    if (_lastCount > 0 && count == 0) {
      _showAllClear = true;
      _allClearTimer?.cancel();
      _allClearTimer = Timer(const Duration(seconds: 5), () {
        _showAllClear = false;
        _rebuild();
      });
    }
    _lastCount = count;
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.apiService;
    final count = api.outboxCount.value;
    final syncing = api.outboxSyncing.value;
    final online = api.isOnline;

    if (count == 0) {
      if (!_showAllClear) return const SizedBox.shrink();
      return _shell(
        context,
        color: ObsidianUITheme.successGreen,
        icon: FontAwesomeIcons.circleCheck,
        message: 'All saved entries are on the server.',
      );
    }

    final noun = count == 1 ? 'entry is' : 'entries are';
    if (syncing) {
      return _shell(
        context,
        color: ObsidianUITheme.primaryAccent,
        icon: FontAwesomeIcons.arrowsRotate,
        message: 'Uploading $count saved ${count == 1 ? 'entry' : 'entries'} to the server...',
      );
    }
    if (!online) {
      return _shell(
        context,
        color: ObsidianUITheme.errorRed,
        icon: FontAwesomeIcons.mobileScreenButton,
        message: 'Offline. $count $noun saved on this device only. They upload automatically when the connection returns.',
      );
    }
    return _shell(
      context,
      color: ObsidianUITheme.warningOrange,
      icon: FontAwesomeIcons.mobileScreenButton,
      message: '$count $noun saved on this device only and not on the server yet.',
      action: TextButton.icon(
        onPressed: () => api.syncOutbox(),
        icon: const FaIcon(FontAwesomeIcons.cloudArrowUp, size: 14),
        label: const Text('Sync now'),
        style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.warningOrange),
      ),
    );
  }

  Widget _shell(
    BuildContext context, {
    required Color color,
    required FaIconData icon,
    required String message,
    Widget? action,
  }) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: widget.margin,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            FaIcon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ObsidianUITheme.getPrimaryTextColor(context),
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }
}
