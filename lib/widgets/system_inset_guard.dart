import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/obsidian_ui_theme.dart';

/// Keeps every route, dialog and sheet clear of the system navigation bar.
///
/// Android draws apps edge-to-edge, so the app sits under the nav bar. The bar's size is not
/// fixed: 3-button and 2-button bars are tall, gesture nav is a thin handle, landscape puts the
/// bar on a side, and immersive mode hides it. This reads the live inset from [MediaQuery]
/// (it updates on rotation, nav mode changes and when the keyboard opens) and pads by exactly that
/// much, then zeroes it for everything below so nothing pads twice.
///
/// The top (status bar) is left alone: the shell's app bar draws behind it on purpose and pads itself.
class SystemInsetGuard extends StatelessWidget {
  final Widget child;

  const SystemInsetGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // `padding` (not `viewPadding`) already drops to 0 at the bottom while the keyboard is up,
    // so the keyboard's own inset keeps working unchanged for text fields.
    final inset = EdgeInsets.only(
      left: media.padding.left,
      right: media.padding.right,
      bottom: media.padding.bottom,
    );
    if (inset == EdgeInsets.zero) return child;

    return ColoredBox(
      // Same color as the bottom nav, so the strip under it reads as part of the bar.
      color: ObsidianUITheme.getSurfaceColor(context),
      child: Padding(
        padding: inset,
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(left: 0, right: 0, bottom: 0),
            viewPadding: EdgeInsets.fromLTRB(
              math.max(0, media.viewPadding.left - inset.left),
              media.viewPadding.top,
              math.max(0, media.viewPadding.right - inset.right),
              math.max(0, media.viewPadding.bottom - inset.bottom),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
