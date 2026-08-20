import 'dart:async';
import 'package:flutter/material.dart';
import '../models/api_response.dart';
import '../theme/obsidian_ui_theme.dart';

/// Centralized feedback top banner & snackbar utility for server operations.
class ObsidianFeedback {
  /// Global keys to guarantee overlays and messengers display anywhere in the app
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static OverlayEntry? _currentOverlayEntry;

  /// Clear any active feedback banner
  static void dismiss() {
    _currentOverlayEntry?.remove();
    _currentOverlayEntry = null;
  }

  /// Displays feedback based on an ApiResponse with HTTP status code and server messages.
  static void showApiResponse(
    BuildContext? context,
    ApiResponse response, {
    String? actionName,
    String? successMessage,
    String? errorMessage,
    Duration duration = const Duration(seconds: 4),
  }) {
    final title = actionName != null ? actionName : (response.success ? 'Success' : 'Operation Failed');

    if (response.success) {
      final codeStr = response.statusCode != null ? ' (HTTP ${response.statusCode})' : '';
      final msg = successMessage ??
          (response.message != null && response.message!.isNotEmpty
              ? '${response.message}$codeStr'
              : 'Completed successfully$codeStr');

      showSuccess(
        context,
        title: title,
        message: msg,
        statusCode: response.statusCode,
        duration: duration,
      );
    } else {
      String msg;
      if (response.isOffline) {
        msg = errorMessage ?? 'Device is offline or server is unreachable.';
      } else if (response.statusCode != null) {
        final detail = response.message != null && response.message!.isNotEmpty
            ? ': ${response.message}'
            : '';
        msg = errorMessage ?? 'HTTP ${response.statusCode}$detail';
      } else {
        msg = errorMessage ?? (response.message ?? 'Unknown error occurred.');
      }

      showError(
        context,
        title: title,
        message: msg,
        statusCode: response.statusCode,
        isOffline: response.isOffline,
        duration: duration,
      );
    }
  }

  /// Displays a success feedback top banner
  static void showSuccess(
    BuildContext? context, {
    required String message,
    String? title,
    int? statusCode,
    Duration duration = const Duration(seconds: 4),
  }) {
    _showFeedback(
      context,
      type: _FeedbackType.success,
      title: title,
      message: message,
      statusCode: statusCode,
      duration: duration,
    );
  }

  /// Displays an error feedback top banner with HTTP response code
  static void showError(
    BuildContext? context, {
    required String message,
    String? title,
    int? statusCode,
    bool isOffline = false,
    Duration duration = const Duration(seconds: 5),
  }) {
    _showFeedback(
      context,
      type: isOffline ? _FeedbackType.warning : _FeedbackType.error,
      title: title ?? (statusCode != null ? 'Server Error (HTTP $statusCode)' : (isOffline ? 'Connection Offline' : 'Error')),
      message: message,
      statusCode: statusCode,
      duration: duration,
    );
  }

  /// Displays a warning / offline feedback top banner
  static void showWarning(
    BuildContext? context, {
    required String message,
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    _showFeedback(
      context,
      type: _FeedbackType.warning,
      title: title,
      message: message,
      duration: duration,
    );
  }

  static void _showFeedback(
    BuildContext? context, {
    required _FeedbackType type,
    String? title,
    required String message,
    int? statusCode,
    required Duration duration,
  }) {
    // 1. Try to display top floating Overlay banner first
    OverlayState? overlay;
    if (context != null) {
      overlay = Overlay.maybeOf(context);
    }
    overlay ??= navigatorKey.currentState?.overlay;

    if (overlay != null) {
      _showTopBannerOverlay(
        overlay: overlay,
        type: type,
        title: title,
        message: message,
        statusCode: statusCode,
        duration: duration,
      );
      return;
    }

    // 2. Fallback to ScaffoldMessenger if Overlay is unavailable
    final messenger = (context != null ? ScaffoldMessenger.maybeOf(context) : null) ??
        messengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    Color accentColor;
    IconData icon;
    String defaultTitle;

    switch (type) {
      case _FeedbackType.success:
        accentColor = ObsidianUITheme.successGreen;
        icon = Icons.check_circle_rounded;
        defaultTitle = statusCode != null ? 'Success (HTTP $statusCode)' : 'Success';
        break;
      case _FeedbackType.warning:
        accentColor = ObsidianUITheme.warningOrange;
        icon = Icons.cloud_off_rounded;
        defaultTitle = 'Offline / Notice';
        break;
      case _FeedbackType.error:
      default:
        accentColor = ObsidianUITheme.errorRed;
        icon = Icons.error_outline_rounded;
        defaultTitle = statusCode != null ? 'Failed (HTTP $statusCode)' : 'Failed';
        break;
    }

    final displayTitle = title ?? defaultTitle;

    messenger.showSnackBar(
      SnackBar(
        elevation: 10,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        duration: duration,
        backgroundColor: const Color(0xFF161B26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.0),
          side: BorderSide(color: accentColor.withValues(alpha: 0.8), width: 1.6),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7.0),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showTopBannerOverlay({
    required OverlayState overlay,
    required _FeedbackType type,
    String? title,
    required String message,
    int? statusCode,
    required Duration duration,
  }) {
    _currentOverlayEntry?.remove();
    _currentOverlayEntry = null;

    Color accentColor;
    IconData icon;
    String defaultTitle;

    switch (type) {
      case _FeedbackType.success:
        accentColor = ObsidianUITheme.successGreen;
        icon = Icons.check_circle_rounded;
        defaultTitle = statusCode != null ? 'Success (HTTP $statusCode)' : 'Success';
        break;
      case _FeedbackType.warning:
        accentColor = ObsidianUITheme.warningOrange;
        icon = Icons.cloud_off_rounded;
        defaultTitle = 'Offline / Notice';
        break;
      case _FeedbackType.error:
      default:
        accentColor = ObsidianUITheme.errorRed;
        icon = Icons.error_outline_rounded;
        defaultTitle = statusCode != null ? 'Failed (HTTP $statusCode)' : 'Failed';
        break;
    }

    final displayTitle = title ?? defaultTitle;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final topPadding = MediaQuery.of(context).padding.top;
        return _TopBannerWidget(
          accentColor: accentColor,
          icon: icon,
          title: displayTitle,
          message: message,
          topPadding: topPadding,
          duration: duration,
          onDismiss: () {
            if (_currentOverlayEntry == entry) {
              _currentOverlayEntry?.remove();
              _currentOverlayEntry = null;
            }
          },
        );
      },
    );

    _currentOverlayEntry = entry;
    overlay.insert(entry);
  }
}

class _TopBannerWidget extends StatefulWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String message;
  final double topPadding;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.message,
    required this.topPadding,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();

    _autoDismissTimer = Timer(widget.duration, () {
      if (mounted) {
        _handleDismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() async {
    _autoDismissTimer?.cancel();
    if (mounted) {
      await _controller.reverse();
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.topPadding > 0 ? widget.topPadding + 10.0 : 40.0,
      left: 16.0,
      right: 16.0,
      child: Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650.0),
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: GestureDetector(
                  onTap: _handleDismiss,
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta != null && details.primaryDelta! < -4) {
                      _handleDismiss();
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B26),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.85),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 18.0,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: 0.25),
                          blurRadius: 14.0,
                          spreadRadius: 1.0,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(widget.icon, color: widget.accentColor, size: 24.0),
                        ),
                        const SizedBox(width: 14.0),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 3.0),
                              Text(
                                widget.message,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18.0),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _handleDismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FeedbackType {
  success,
  warning,
  error,
}
