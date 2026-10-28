import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/slack_models.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_feedback.dart';

/// Popup banners for Slack messages, stacked at the top of the screen (top-right on wide windows).
///
/// At most three show at once; older ones fold into a "+N more" chip, and mentions are the last to fold. A banner
/// closes after 10 seconds unless the user was mentioned. The same message can arrive over the notification
/// socket and FCM; [show] ignores ids it has already shown.
class SlackBannerOverlay {
  SlackBannerOverlay._();

  static const int _maxVisible = 3;
  static const Duration _autoDismiss = Duration(seconds: 10);

  static final ValueNotifier<List<SlackBanner>> _visible = ValueNotifier(const []);
  static final ValueNotifier<int> _hidden = ValueNotifier(0);
  static final LinkedHashSet<String> _seen = LinkedHashSet();
  static OverlayEntry? _entry;

  static void show(SlackBanner banner) {
    if (banner.id.isNotEmpty) {
      if (_seen.contains(banner.id)) return;
      _seen.add(banner.id);
      while (_seen.length > 200) {
        _seen.remove(_seen.first);
      }
    }
    if (!_ensureEntry()) return;

    final next = [banner, ..._visible.value];
    var excess = next.length - _maxVisible;
    if (excess > 0) {
      // Oldest first, plain messages before mentions.
      final order = [
        ...next.reversed.where((b) => !b.mentioned),
        ...next.reversed.where((b) => b.mentioned),
      ];
      for (final b in order) {
        if (excess <= 0) break;
        next.remove(b);
        _hidden.value++;
        excess--;
      }
    }
    _visible.value = next;
  }

  static void dismiss(SlackBanner banner) {
    _visible.value = _visible.value.where((b) => !identical(b, banner)).toList();
    _removeEntryIfEmpty();
  }

  static void dismissAll() {
    _visible.value = const [];
    _hidden.value = 0;
    _removeEntryIfEmpty();
  }

  static void _removeEntryIfEmpty() {
    if (_visible.value.isEmpty) {
      _hidden.value = 0;
      _entry?.remove();
      _entry = null;
    }
  }

  static bool _ensureEntry() {
    if (_entry != null) return true;
    final overlay = ObsidianFeedback.navigatorKey.currentState?.overlay;
    if (overlay == null) return false;
    _entry = OverlayEntry(builder: (_) => const _SlackBannerStack());
    overlay.insert(_entry!);
    return true;
  }

  static Future<void> open(SlackBanner banner) async {
    final uri = banner.safeUri;
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

class _SlackBannerStack extends StatelessWidget {
  const _SlackBannerStack();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 700;
    return Positioned(
      top: media.padding.top + 10,
      right: 12,
      left: wide ? null : 12,
      width: wide ? 380 : null,
      child: Material(
        type: MaterialType.transparency,
        child: ValueListenableBuilder<List<SlackBanner>>(
          valueListenable: SlackBannerOverlay._visible,
          builder: (context, banners, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in banners)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SlackBannerCard(key: ObjectKey(b), banner: b),
                ),
              ValueListenableBuilder<int>(
                valueListenable: SlackBannerOverlay._hidden,
                builder: (context, hidden, _) => hidden <= 0
                    ? const SizedBox.shrink()
                    : ActionChip(
                        label: Text(context.tr('slack.banner_more', '+{n} more Slack messages · Dismiss all').replaceAll('{n}', '$hidden'),
                            style: const TextStyle(fontSize: 12)),
                        onPressed: SlackBannerOverlay.dismissAll,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlackBannerCard extends StatefulWidget {
  final SlackBanner banner;

  const _SlackBannerCard({super.key, required this.banner});

  @override
  State<_SlackBannerCard> createState() => _SlackBannerCardState();
}

class _SlackBannerCardState extends State<_SlackBannerCard> with SingleTickerProviderStateMixin {
  static const Color _slackAubergine = Color(0xFF4A154B);
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.banner.mentioned) {
      _timer = Timer(SlackBannerOverlay._autoDismiss, _close);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    SlackBannerOverlay.dismiss(widget.banner);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    final accent = b.mentioned ? ObsidianUITheme.primaryAccent : const Color(0xFFE01E5A);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
        child: Dismissible(
          key: ObjectKey(b),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => SlackBannerOverlay.dismiss(b),
          child: Semantics(
            liveRegion: true,
            label: '${b.channel}, ${b.author}: ${b.text}',
            // Flutter only rounds borders whose sides share a colour, so the accent stripe is its own box.
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: ObsidianUITheme.getSurfaceColor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.all(6),
                              decoration:
                                  BoxDecoration(color: _slackAubergine.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.tag_rounded, size: 16, color: accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(b.channel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primary)),
                                      Text(b.author, style: TextStyle(fontSize: 12, color: secondary)),
                                      if (b.mentioned)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration:
                                              BoxDecoration(color: ObsidianUITheme.primaryAccent, borderRadius: BorderRadius.circular(6)),
                                          child: Text(context.tr('slack.banner_mentioned', 'Mentioned').toUpperCase(),
                                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(b.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: primary, height: 1.3)),
                                  if (b.safeUri != null)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 30),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        SlackBannerOverlay.open(b);
                                        _close();
                                      },
                                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                      label: Text(context.tr('slack.banner_open', 'Open in Slack'), style: const TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('slack.banner_dismiss', 'Dismiss'),
                              icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                              onPressed: _close,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
