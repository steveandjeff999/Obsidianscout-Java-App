import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/app_update_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_glass_card.dart';

enum _UpdateStage { ready, downloading, installing, needsPermission, failed }

/// Tells the user a newer GitHub release is out and, on Update, downloads it and opens the installer.
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;

  const AppUpdateDialog({super.key, required this.update});

  static Future<void> show(BuildContext context, AppUpdateInfo update) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppUpdateDialog(update: update),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateStage _stage = _UpdateStage.ready;
  int _received = 0;
  int _total = 0;
  String? _packagePath;
  String? _error;

  bool get _busy => _stage == _UpdateStage.downloading || _stage == _UpdateStage.installing;
  bool get _isWindows =>
      widget.update.source == AppInstallSource.githubMsix || widget.update.source == AppInstallSource.githubPortable;

  Future<void> _update() async {
    final service = AppUpdateService.instance;
    try {
      if (_packagePath == null) {
        setState(() {
          _stage = _UpdateStage.downloading;
          _received = 0;
          _total = widget.update.size;
          _error = null;
        });
        _packagePath = await service.download(widget.update, onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        });
      }
      if (!mounted) return;
      setState(() => _stage = _UpdateStage.installing);
      final result = await service.install(widget.update, _packagePath!);
      if (!mounted) return;
      switch (result.status) {
        case AppUpdateInstallStatus.started:
          // Android shows its installer over the app; Windows closes the app itself.
          if (!_isWindows) Navigator.of(context, rootNavigator: true).pop();
        case AppUpdateInstallStatus.needsPermission:
          setState(() => _stage = _UpdateStage.needsPermission);
        case AppUpdateInstallStatus.failed:
          setState(() {
            _stage = _UpdateStage.failed;
            _error = result.message;
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.failed;
        _error = e.toString();
      });
    }
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final accent = ObsidianUITheme.primaryAccent;
    final update = widget.update;

    final String message;
    switch (_stage) {
      case _UpdateStage.ready:
        message = context.tr(
          'app_update.available_message',
          'Version ${update.version} is available. You have ${AppUpdateService.installedVersion}.',
        );
      case _UpdateStage.downloading:
        message = context.tr('app_update.downloading', 'Downloading update...');
      case _UpdateStage.installing:
        message = _isWindows
            ? context.tr('app_update.installing_windows', 'Opening the installer. ObsidianScout will close so it can update.')
            : context.tr('app_update.installing', 'Opening the installer...');
      case _UpdateStage.needsPermission:
        message = context.tr(
          'app_update.needs_permission',
          'Allow ObsidianScout to install apps in the settings screen that opened, then come back and tap Install.',
        );
      case _UpdateStage.failed:
        message = context.tr('app_update.failed', 'The update could not be installed.');
    }

    final progress = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ObsidianGlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt_rounded, color: accent, size: 24.0),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Text(
                        context.tr('app_update.title', 'Update available'),
                        style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryTextColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                Text(message, style: TextStyle(fontSize: 13.5, color: secondaryTextColor, height: 1.4)),
                if (_stage == _UpdateStage.downloading) ...[
                  const SizedBox(height: 16.0),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6.0),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8.0,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    _total > 0 ? '${_mb(_received)} / ${_mb(_total)} MB' : '${_mb(_received)} MB',
                    style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                    textAlign: TextAlign.right,
                  ),
                ],
                if (_stage == _UpdateStage.installing) ...[
                  const SizedBox(height: 16.0),
                  Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
                    ),
                  ),
                ],
                if (_stage == _UpdateStage.failed && _error != null) ...[
                  const SizedBox(height: 12.0),
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.errorRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: ObsidianUITheme.errorRed.withValues(alpha: 0.4)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: ObsidianUITheme.errorRed, fontSize: 12.5)),
                  ),
                ],
                const SizedBox(height: 16.0),
                Divider(color: borderColor),
                const SizedBox(height: 8.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                      style: TextButton.styleFrom(foregroundColor: secondaryTextColor),
                      child: Text(context.tr('app_update.later', 'Later')),
                    ),
                    const SizedBox(width: 8.0),
                    FilledButton.icon(
                      onPressed: _busy ? null : _update,
                      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                      icon: Icon(
                        _stage == _UpdateStage.failed ? Icons.refresh_rounded : Icons.download_rounded,
                        size: 18.0,
                      ),
                      label: Text(switch (_stage) {
                        _UpdateStage.failed => context.tr('app_update.retry', 'Try again'),
                        _UpdateStage.needsPermission => context.tr('app_update.install', 'Install'),
                        _ => context.tr('app_update.update', 'Update'),
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
