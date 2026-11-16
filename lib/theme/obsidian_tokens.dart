import 'package:flutter/material.dart';

/// Design tokens mirrored from the website (css/base/variables.css and design.css).
/// Warm greys in light mode, neutral greys in dark mode, one violet accent.
@immutable
class ObsidianTokens extends ThemeExtension<ObsidianTokens> {
  final Color ink;
  final Color muted;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color accent;
  final Color accent2;
  final Color accent3;
  final Color border;
  final Color borderSubtle;
  final Color success;
  final Color warning;
  final Color danger;

  const ObsidianTokens({
    required this.ink,
    required this.muted,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.border,
    required this.borderSubtle,
    required this.success,
    required this.warning,
    required this.danger,
  });

  // Radii: containers, controls, chips/badges.
  static const double radius = 6.0;
  static const double radiusSm = 4.0;
  static const double radiusPill = 5.0;

  // Motion (--transition-fast / --transition-smooth).
  static const Curve curve = Cubic(0.16, 1, 0.3, 1);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration smooth = Duration(milliseconds: 250);

  // Font families.
  static const String fontSans = 'IBM Plex Sans';
  static const String fontSerif = 'Newsreader';
  static const String fontMono = 'IBM Plex Mono';
  static const List<String> fontFallback = ['Roboto', 'Noto Sans', 'Noto Sans Hebrew', 'Segoe UI'];

  static const ObsidianTokens light = ObsidianTokens(
    ink: Color(0xFF1B1A17),
    muted: Color(0xFF6E6B64),
    bg: Color(0xFFF5F4F0),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F6F2),
    surface3: Color(0xFFEFEDE7),
    accent: Color(0xFF5B4EC7),
    accent2: Color(0xFF7065A2),
    accent3: Color(0xFF7D71DC),
    border: Color(0xFFE2DFD8),
    borderSubtle: Color(0xFFECEBE5),
    success: Color(0xFF1F9D6B),
    warning: Color(0xFFD9890B),
    danger: Color(0xFFD23F3F),
  );

  static const ObsidianTokens dark = ObsidianTokens(
    ink: Color(0xFFECECF1),
    muted: Color(0xFF9B9BA6),
    bg: Color(0xFF0E0E11),
    surface: Color(0xFF16161A),
    surface2: Color(0xFF1C1C21),
    surface3: Color(0xFF25252B),
    accent: Color(0xFF8B7CF6),
    accent2: Color(0xFFA39BD6),
    accent3: Color(0xFFB3A8FA),
    // rgba(255,255,255,.085) and .05 over the dark surface
    border: Color(0xFF2A2A2E),
    borderSubtle: Color(0xFF212125),
    success: Color(0xFF3FC28F),
    warning: Color(0xFFF2B23A),
    danger: Color(0xFFF07171),
  );

  static ObsidianTokens of(BuildContext context) =>
      Theme.of(context).extension<ObsidianTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// Fixed-width numerals for team numbers, scores and counters.
  static TextStyle mono({TextStyle? base, double? size, FontWeight weight = FontWeight.w400}) {
    return (base ?? const TextStyle()).copyWith(
      fontFamily: fontMono,
      fontFamilyFallback: fontFallback,
      fontSize: size ?? base?.fontSize,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Serif style for page and section titles.
  static TextStyle serif({TextStyle? base, double? size, FontWeight weight = FontWeight.w500}) {
    return (base ?? const TextStyle()).copyWith(
      fontFamily: fontSerif,
      fontFamilyFallback: const ['Georgia', 'Times New Roman', 'serif'],
      fontSize: size ?? base?.fontSize,
      fontWeight: weight,
      letterSpacing: -0.012 * (size ?? base?.fontSize ?? 16),
    );
  }

  @override
  ObsidianTokens copyWith({
    Color? ink,
    Color? muted,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? accent,
    Color? accent2,
    Color? accent3,
    Color? border,
    Color? borderSubtle,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return ObsidianTokens(
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accent3: accent3 ?? this.accent3,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  ObsidianTokens lerp(ThemeExtension<ObsidianTokens>? other, double t) {
    if (other is! ObsidianTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ObsidianTokens(
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      accent3: l(accent3, other.accent3),
      border: l(border, other.border),
      borderSubtle: l(borderSubtle, other.borderSubtle),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
    );
  }
}
