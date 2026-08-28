import 'package:flutter/material.dart';

enum ObsidianUiDensity {
  touch,
  compact,
}

class ObsidianResponsive {
  static const double kDesktopBreakpoint = 840.0;
  static const double kLargeDesktopBreakpoint = 1200.0;
  static const double kSidebarExpandedWidth = 240.0;
  static const double kSidebarCollapsedWidth = 72.0;

  /// Determines if the current environment should render the PC Desktop layout.
  /// If [overrideMode] is 'mobile', always returns false.
  /// If [overrideMode] is 'desktop', always returns true.
  /// If [overrideMode] is 'auto' (or null), checks if window width >= kDesktopBreakpoint.
  static bool isDesktop(BuildContext context, {String? overrideMode}) {
    if (overrideMode == 'mobile') return false;
    if (overrideMode == 'desktop') return true;
    final width = MediaQuery.sizeOf(context).width;
    return width >= kDesktopBreakpoint;
  }

  /// Determines if the current environment should render the Mobile Touch layout.
  static bool isMobile(BuildContext context, {String? overrideMode}) {
    return !isDesktop(context, overrideMode: overrideMode);
  }

  /// Determines if the window is wide enough for multi-column large desktop grids.
  static bool isLargeDesktop(BuildContext context, {String? overrideMode}) {
    if (overrideMode == 'mobile') return false;
    final width = MediaQuery.sizeOf(context).width;
    return width >= kLargeDesktopBreakpoint;
  }

  /// Returns the appropriate content padding.
  static EdgeInsets screenPadding(BuildContext context, {String? overrideMode, bool isBarsVisible = true}) {
    final desktop = isDesktop(context, overrideMode: overrideMode);
    if (desktop) {
      return const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0);
    }
    return EdgeInsets.only(
      left: 12.0,
      right: 12.0,
      top: 4.0,
      bottom: isBarsVisible ? 120.0 : 20.0,
    );
  }

  /// Number of columns for form grids.
  static int formColumns(BuildContext context, {String? overrideMode}) {
    if (isLargeDesktop(context, overrideMode: overrideMode)) return 3;
    if (isDesktop(context, overrideMode: overrideMode)) return 2;
    return 1;
  }

  /// Number of columns for card grids.
  static int cardColumns(BuildContext context, {String? overrideMode}) {
    if (isLargeDesktop(context, overrideMode: overrideMode)) return 4;
    if (isDesktop(context, overrideMode: overrideMode)) return 3;
    return 1;
  }
}
