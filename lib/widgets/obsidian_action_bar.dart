import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';

/// What the action bar tells the user about their edits.
enum ObsidianSaveState { clean, dirty, saving, saved, failed, live }

/// A Save bar pinned to the bottom of a config / assignment page or sheet, so the Save
/// button is always on screen and the page says plainly whether edits are saved.
///
/// Dirty tracking is snapshot based: pass [isDirty] (usually `() => _snapshot() != _savedSnapshot`)
/// and the bar re-checks it while visible, so no field needs its own onChanged wiring.
/// When [isSaving] goes from true to false the bar shows "All changes saved" if [isDirty]
/// now returns false, or "Not saved" if the edits are still outstanding.
///
/// [isLive] is for editors that sync every change on their own (live config collaboration):
/// the bar then reads "Changes sync automatically" and never shows unsaved changes.
class ObsidianActionBar extends StatefulWidget {
  final Widget primary;
  final List<Widget> secondary;
  final bool isSaving;
  final bool Function()? isDirty;
  final bool isLive;
  final String? liveText;

  /// Lift the bar above the mobile shell's bottom navigation. Off for sheets, dialogs and pushed routes.
  final bool reserveBottomNav;
  final bool isBarsVisible;
  final String? uiMode;

  const ObsidianActionBar({
    super.key,
    required this.primary,
    this.secondary = const [],
    this.isSaving = false,
    this.isDirty,
    this.isLive = false,
    this.liveText,
    this.reserveBottomNav = false,
    this.isBarsVisible = true,
    this.uiMode,
  });

  @override
  State<ObsidianActionBar> createState() => _ObsidianActionBarState();
}

class _ObsidianActionBarState extends State<ObsidianActionBar> {
  static const _pollInterval = Duration(milliseconds: 600);
  static const _savedHold = Duration(seconds: 4);

  Timer? _poll;
  Timer? _savedTimer;
  bool _dirty = false;
  ObsidianSaveState? _outcome; // saved / failed, shown briefly after a save finishes

  @override
  void initState() {
    super.initState();
    _dirty = _checkDirty();
    if (widget.isDirty != null) {
      _poll = Timer.periodic(_pollInterval, (_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(covariant ObsidianActionBar old) {
    super.didUpdateWidget(old);
    if (old.isSaving && !widget.isSaving) {
      final stillDirty = _checkDirty();
      _dirty = stillDirty;
      _outcome = stillDirty ? ObsidianSaveState.failed : ObsidianSaveState.saved;
      _savedTimer?.cancel();
      if (!stillDirty) {
        _savedTimer = Timer(_savedHold, () {
          if (mounted) setState(() => _outcome = null);
        });
      }
    } else if (!widget.isSaving) {
      _dirty = _checkDirty();
    }
    if (widget.isDirty == null) {
      _poll?.cancel();
      _poll = null;
    } else {
      _poll ??= Timer.periodic(_pollInterval, (_) => _refresh());
    }
  }

  bool _checkDirty() {
    if (widget.isLive || widget.isDirty == null) return false;
    try {
      return widget.isDirty!();
    } catch (_) {
      return false;
    }
  }

  void _refresh() {
    if (!mounted || widget.isSaving) return;
    final next = _checkDirty();
    if (next != _dirty) {
      setState(() {
        _dirty = next;
        // A new edit replaces any "saved" / "failed" note; reverting to the saved values clears "failed".
        if (next && _outcome == ObsidianSaveState.saved) _outcome = null;
        if (!next && _outcome == ObsidianSaveState.failed) _outcome = null;
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _savedTimer?.cancel();
    super.dispose();
  }

  ObsidianSaveState get _state {
    if (widget.isSaving) return ObsidianSaveState.saving;
    if (_outcome != null) return _outcome!;
    if (widget.isLive) return ObsidianSaveState.live;
    return _dirty ? ObsidianSaveState.dirty : ObsidianSaveState.clean;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final isDark = ObsidianUITheme.isDark(context);
    final surface = ObsidianUITheme.getSurfaceColor(context);
    final border = ObsidianUITheme.getBorderColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final ink = ObsidianUITheme.getPrimaryTextColor(context);

    final (Color dot, Color text, String label) = switch (state) {
      ObsidianSaveState.clean => (muted, muted, context.tr('action_bar.not_auto_saved', 'Changes are not saved automatically')),
      ObsidianSaveState.dirty => (ObsidianUITheme.warningOrange, ink, context.tr('action_bar.unsaved', 'Unsaved changes')),
      ObsidianSaveState.saving => (ObsidianUITheme.primaryAccent, muted, context.tr('action_bar.saving', 'Saving...')),
      ObsidianSaveState.saved => (ObsidianUITheme.successGreen, ObsidianUITheme.successGreen, context.tr('action_bar.saved', 'All changes saved')),
      ObsidianSaveState.failed => (ObsidianUITheme.errorRed, ObsidianUITheme.errorRed, context.tr('action_bar.failed', 'Not saved - your changes are still unsaved')),
      ObsidianSaveState.live => (ObsidianUITheme.successGreen, muted, widget.liveText ?? context.tr('action_bar.live', 'Changes sync automatically')),
    };
    final edgeColor = switch (state) {
      ObsidianSaveState.dirty => ObsidianUITheme.warningOrange,
      ObsidianSaveState.failed => ObsidianUITheme.errorRed,
      _ => border,
    };

    final media = MediaQuery.of(context);
    final onMobileShell = widget.reserveBottomNav && ObsidianResponsive.isMobile(context, overrideMode: widget.uiMode);
    final bottomGap = onMobileShell
        ? media.padding.bottom + (widget.isBarsVisible ? 70 : 8)
        : (widget.reserveBottomNav ? 8.0 : media.padding.bottom + 8);

    final status = Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottomGap),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: edgeColor, width: state == ObsidianSaveState.dirty || state == ObsidianSaveState.failed ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: (state == ObsidianSaveState.dirty ? ObsidianUITheme.warningOrange : Colors.black)
                  .withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 520;
            if (narrow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final w in widget.secondary) ...[w, const SizedBox(width: 8)],
                      Expanded(child: widget.primary),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 12),
                for (final w in widget.secondary) ...[w, const SizedBox(width: 8)],
                widget.primary,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Page body with an [ObsidianActionBar] pinned underneath it: the body scrolls, the bar never does.
class ObsidianActionBarLayout extends StatelessWidget {
  final Widget body;
  final Widget? bar;

  const ObsidianActionBarLayout({super.key, required this.body, this.bar});

  @override
  Widget build(BuildContext context) {
    if (bar == null) return body;
    return Column(
      children: [
        Expanded(child: body),
        bar!,
      ],
    );
  }
}

/// Bottom-sheet body with its Save row pinned below the scrolling content.
/// Use inside sheets opened with `isScrollControlled: true`.
class ObsidianSheetWithFooter extends StatelessWidget {
  final Widget body;
  final Widget footer;

  const ObsidianSheetWithFooter({super.key, required this.body, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: body),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
          ),
          child: footer,
        ),
      ],
    );
  }
}
