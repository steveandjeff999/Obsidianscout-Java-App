import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/config_models.dart';
import 'obsidian_page_transitions.dart';
import 'obsidian_tokens.dart';

/// App theme. Colors, type and corners mirror the website design layer
/// (see [ObsidianTokens]). A server theme preset still overrides the tokens,
/// except the "Default" preset, which means "use the site's own look".
class ObsidianUITheme {
  // Brand default colors (Dark)
  static const Color defaultBackground = Color(0xFF0E0E11);
  static const Color defaultSurface = Color(0xFF16161A);

  // Brand default colors (Light)
  static const Color defaultBackgroundLight = Color(0xFFF5F4F0);
  static const Color defaultSurfaceLight = Color(0xFFFFFFFF);

  static const Color defaultPrimaryAccent = Color(0xFF8B7CF6); // violet (dark)
  static const Color defaultSecondaryAccent = Color(0xFFA39BD6);
  static const Color successGreen = Color(0xFF1F9D6B);
  static const Color warningOrange = Color(0xFFD9890B);
  static const Color errorRed = Color(0xFFD23F3F);

  // Fallback / legacy constants
  static const Color background = defaultBackground;
  static const Color surface = defaultSurface;
  static const Color backgroundLight = defaultBackgroundLight;
  static const Color surfaceLight = defaultSurfaceLight;

  // Active custom theme state
  static ThemePresetModel? _customTheme;
  static bool _customThemeEnabled = true;

  static void setCustomTheme(ThemePresetModel? theme, {bool enabled = true}) {
    _customTheme = theme;
    _customThemeEnabled = enabled;
  }

  static bool _isDefaultPreset(ThemePresetModel t) => t.name == 'Default' || t.name.isEmpty;

  /// Values that older "Default" presets shipped with (old app and site defaults).
  /// A Default preset holding only these means "never chose a color".
  static const Set<String> _shippedDefaultHex = {
    '', '09090b', '000000', '0a0c10', 'ffffff', 'f8fafc', 'f4f6fb', 'f6f8fa', 'f4f4f5', '18181b',
    '111116', '0e1014', '0b8f88', 'f28b35', '255a9c', '1d1a17', '5f5b55', '3ccfc0', 'f2a353',
    '6aa2ff', 'f4f2ed', 'c3bfb8', '388bfd', '38bdf8', '0f172a', '334155',
    // current site tokens
    '0e0e11', '16161a', 'f5f4f0', '5b4ec7', '8b7cf6',
  };

  static bool _isShippedDefault(String hex) =>
      _shippedDefaultHex.contains(hex.trim().replaceAll('#', '').toLowerCase());

  /// True when the Default preset carries only shipped defaults (the site's check, widened
  /// to the colors older presets stored), so the site-style tokens apply.
  static bool _isExplicitDefault(ThemePresetModel t) {
    if (!_isDefaultPreset(t)) return false;
    final colors = [
      t.darkBg, t.lightBg, t.darkCard, t.lightCard,
      t.darkAccent, t.lightAccent, t.darkAccent2, t.lightAccent2,
      t.darkAccent3, t.lightAccent3, t.darkInk, t.lightInk, t.darkMuted, t.lightMuted,
    ];
    return colors.every(_isShippedDefault);
  }

  /// The preset whose colors apply, or null when the site's own look should be used.
  static ThemePresetModel? get activeCustomTheme {
    if (!_customThemeEnabled || _customTheme == null) return null;
    return _isExplicitDefault(_customTheme!) ? null : _customTheme;
  }

  static bool get isCustomThemeActive => activeCustomTheme != null;

  static bool get isCustomThemeActiveAndNonDefault => activeCustomTheme != null;

  static Color deriveDarkCardSurface(Color bg, {Color? accent}) {
    Color elevated = Color.alphaBlend(Colors.white.withValues(alpha: 0.05), bg);
    if (accent != null) {
      elevated = Color.alphaBlend(accent.withValues(alpha: 0.03), elevated);
    }
    return elevated;
  }

  // Dynamic Accents (Context-free fallback)
  static Color get primaryAccent {
    final c = activeCustomTheme;
    if (c != null) {
      final parsed = parseHex(c.darkAccent);
      if (parsed != null) return parsed;
    }
    return defaultPrimaryAccent;
  }

  static Color get secondaryAccent {
    final c = activeCustomTheme;
    if (c != null) {
      final parsed = parseHex(c.darkAccent2);
      if (parsed != null) return parsed;
    }
    return defaultSecondaryAccent;
  }

  static Color get tertiaryAccent {
    final c = activeCustomTheme;
    if (c != null) {
      final parsed = parseHex(c.darkAccent3);
      if (parsed != null) return parsed;
    }
    return ObsidianTokens.dark.accent3;
  }

  // ---- Corners -------------------------------------------------------------
  // Site: containers 6, controls 4, chips 5. A preset's corner setting overrides them
  // (see js/layout/theme.js); the Default preset ignores the old 999px "pill" default.

  /// Radius string a preset asks for in the given mode, or null for the site's own corners.
  static String? _presetRadius({required bool dark}) {
    if (!_customThemeEnabled || _customTheme == null) return null;
    final t = _customTheme!;
    var r = dark
        ? (t.darkRadius.isNotEmpty ? t.darkRadius : t.btnRadius)
        : (t.lightRadius.isNotEmpty ? t.lightRadius : t.btnRadius);
    if (r.trim().isEmpty) return null;
    if (_isDefaultPreset(t) && parseRadius(r, fallback: 0) >= 999) return null;
    return r;
  }

  /// Button / control radius.
  static double controlRadius({required bool dark}) {
    final r = _presetRadius(dark: dark);
    if (r == null) return ObsidianTokens.radiusSm;
    return parseRadius(r, fallback: ObsidianTokens.radiusSm);
  }

  /// Card / dialog / sheet radius.
  static double containerRadius({required bool dark}) {
    final r = _presetRadius(dark: dark);
    if (r == null) return ObsidianTokens.radius;
    final v = parseRadius(r, fallback: ObsidianTokens.radius);
    return v >= 999 ? 12.0 : v.clamp(0.0, 16.0).toDouble();
  }

  /// Input / small-control radius.
  static double smallRadius({required bool dark}) {
    final r = _presetRadius(dark: dark);
    if (r == null) return ObsidianTokens.radiusSm;
    return (containerRadius(dark: dark) * 0.6).roundToDouble();
  }

  /// Chip / badge radius.
  static double pillRadius({required bool dark}) {
    final r = _presetRadius(dark: dark);
    if (r != null && parseRadius(r, fallback: 0) >= 999) return 999.0;
    return ObsidianTokens.radiusPill;
  }

  static double get buttonRadius => controlRadius(dark: true);

  static double getButtonRadius(BuildContext context, {double fallback = ObsidianTokens.radiusSm}) {
    return _presetRadius(dark: isDark(context)) == null
        ? fallback
        : controlRadius(dark: isDark(context));
  }

  // Surfaces & borders (kept under the old "glass" names for existing call sites).
  static const Color glassSurface = Color(0xFF16161A);
  static const Color glassSurfaceHover = Color(0xFF1C1C21);
  static const Color glassBorderLight = Color(0xFF2A2A2E);
  static const Color glassBorderDark = Color(0xFF212125);
  static const Color glassInputBackground = Color(0xFF1C1C21);

  static const Color glassSurfaceLightMode = Color(0xFFFFFFFF);
  static const Color glassBorderLightMode = Color(0xFFE2DFD8);
  static const Color glassInputBackgroundLightMode = Color(0xFFF7F6F2);

  static const PageTransitionsTheme _pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: SamsungSlideTransitionsBuilder(),
      TargetPlatform.iOS: SamsungSlideTransitionsBuilder(),
      TargetPlatform.fuchsia: SamsungSlideTransitionsBuilder(),
      TargetPlatform.windows: WindowsSlideUpTransitionsBuilder(),
      TargetPlatform.macOS: WindowsSlideUpTransitionsBuilder(),
      TargetPlatform.linux: WindowsSlideUpTransitionsBuilder(),
    },
  );

  /// Color hex parser supporting #RGB, #RRGGBB, #AARRGGBB
  static Color? parseHex(String? hexString) {
    if (hexString == null) return null;
    final clean = hexString.trim().replaceAll('#', '');
    if (clean.isEmpty) return null;
    if (clean.length == 6) {
      final val = int.tryParse('FF$clean', radix: 16);
      return val != null ? Color(val) : null;
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      return val != null ? Color(val) : null;
    } else if (clean.length == 3) {
      final val = int.tryParse('FF${clean[0]}${clean[0]}${clean[1]}${clean[1]}${clean[2]}${clean[2]}', radix: 16);
      return val != null ? Color(val) : null;
    }
    return null;
  }

  /// Parses button radius string ("0px", "6px", "8px", "12px", "999px") to double
  static double parseRadius(String? radiusStr, {double fallback = 24.0}) {
    if (radiusStr == null || radiusStr.trim().isEmpty) return fallback;
    final clean = radiusStr.replaceAll('px', '').trim();
    final parsed = double.tryParse(clean);
    if (parsed != null) {
      if (parsed >= 999) return 999.0;
      return parsed;
    }
    return fallback;
  }

  /// Parses linear-gradient or solid background string
  static Gradient? parseGradient(String? bgStr) {
    if (bgStr == null || !bgStr.contains('gradient')) return null;
    try {
      double degrees = 135.0;
      final degMatch = RegExp(r'(\d+)deg').firstMatch(bgStr);
      if (degMatch != null) {
        degrees = double.tryParse(degMatch.group(1)!) ?? 135.0;
      }
      final colorMatches = RegExp(r'#(?:[0-9a-fA-F]{3,8})').allMatches(bgStr);
      final colors = colorMatches.map((m) => parseHex(m.group(0))!).whereType<Color>().toList();
      if (colors.length >= 2) {
        final rad = (degrees - 90) * (math.pi / 180);
        return LinearGradient(
          begin: Alignment(-math.cos(rad), -math.sin(rad)),
          end: Alignment(math.cos(rad), math.sin(rad)),
          colors: colors,
        );
      }
    } catch (_) {}
    return null;
  }

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static TextTheme _textTheme(ObsidianTokens t, Color ink, Color muted) {
    TextStyle serif(double size, FontWeight w) => TextStyle(
          fontFamily: ObsidianTokens.fontSerif,
          fontFamilyFallback: const ['Georgia', 'Times New Roman', 'serif'],
          fontSize: size,
          fontWeight: w,
          color: ink,
          letterSpacing: -0.012 * size,
          height: 1.15,
        );
    TextStyle sans(double size, FontWeight w, Color c, {double ls = 0, double? h}) => TextStyle(
          fontFamily: ObsidianTokens.fontSans,
          fontFamilyFallback: ObsidianTokens.fontFallback,
          fontSize: size,
          fontWeight: w,
          color: c,
          letterSpacing: ls,
          height: h,
        );
    return TextTheme(
      displayLarge: serif(48, FontWeight.w500),
      displayMedium: serif(40, FontWeight.w500),
      displaySmall: serif(34, FontWeight.w500),
      headlineLarge: serif(32, FontWeight.w500),
      headlineMedium: serif(26, FontWeight.w500),
      headlineSmall: serif(22, FontWeight.w500),
      titleLarge: sans(18, FontWeight.w600, ink, ls: -0.09),
      titleMedium: sans(16, FontWeight.w600, ink, ls: -0.08),
      titleSmall: sans(14, FontWeight.w600, ink, ls: -0.07),
      bodyLarge: sans(16, FontWeight.w400, ink, h: 1.5),
      bodyMedium: sans(15, FontWeight.w400, ink, h: 1.5),
      bodySmall: sans(13, FontWeight.w400, muted, h: 1.45),
      labelLarge: sans(14, FontWeight.w500, ink),
      labelMedium: sans(13, FontWeight.w500, muted),
      labelSmall: sans(12, FontWeight.w500, muted),
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = dark ? ObsidianTokens.dark : ObsidianTokens.light;
    final custom = activeCustomTheme;

    Color pick(String? hex, Color fallback) => (custom != null ? parseHex(hex) : null) ?? fallback;

    final accent = pick(dark ? custom?.darkAccent : custom?.lightAccent, tokens.accent);
    final accent2 = pick(dark ? custom?.darkAccent2 : custom?.lightAccent2, tokens.accent2);
    final accent3 = pick(dark ? custom?.darkAccent3 : custom?.lightAccent3, tokens.accent3);
    final bgSolid = pick(dark ? custom?.darkBg : custom?.lightBg, tokens.bg);
    final ink = pick(dark ? custom?.darkInk : custom?.lightInk, tokens.ink);
    final muted = pick(dark ? custom?.darkMuted : custom?.lightMuted, tokens.muted);

    final surfaceColor = () {
      if (custom != null) {
        final hex = dark ? custom.darkCard : custom.lightCard;
        final parsed = parseHex(hex);
        if (parsed != null) return parsed;
        if (dark) return deriveDarkCardSurface(bgSolid, accent: accent);
      }
      return tokens.surface;
    }();

    final borderColor = custom != null && dark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.085), surfaceColor)
        : tokens.border;
    final borderSubtle = custom != null && dark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.05), surfaceColor)
        : tokens.borderSubtle;

    final radius = controlRadius(dark: dark);
    final smallR = smallRadius(dark: dark);
    final cardR = containerRadius(dark: dark);
    final pillR = pillRadius(dark: dark);
    final textTheme = _textTheme(tokens, ink, muted);

    final effective = tokens.copyWith(
      ink: ink,
      muted: muted,
      bg: bgSolid,
      surface: surfaceColor,
      accent: accent,
      accent2: accent2,
      accent3: accent3,
      border: borderColor,
      borderSubtle: borderSubtle,
    );

    RoundedRectangleBorder shape(double r, {BorderSide side = BorderSide.none}) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);
    OutlineInputBorder inputBorder(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallR),
          borderSide: BorderSide(color: c, width: w),
        );
    final containerSide = BorderSide(color: borderColor);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgSolid,
      primaryColor: accent,
      pageTransitionsTheme: _pageTransitionsTheme,
      extensions: [effective],
      fontFamily: ObsidianTokens.fontSans,
      fontFamilyFallback: ObsidianTokens.fontFallback,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: accent,
        onPrimary: Colors.white,
        secondary: accent2,
        tertiary: accent3,
        surface: surfaceColor,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: bgSolid,
        surfaceContainerLow: tokens.surface2,
        surfaceContainer: tokens.surface2,
        surfaceContainerHigh: tokens.surface3,
        surfaceContainerHighest: tokens.surface3,
        outline: borderColor,
        outlineVariant: borderSubtle,
        error: tokens.danger,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bgSolid,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: ObsidianTokens.serif(base: TextStyle(color: ink), size: 20, weight: FontWeight.w600),
        shape: Border(bottom: BorderSide(color: borderColor)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: shape(radius),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: shape(radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          foregroundColor: ink,
          side: BorderSide(color: borderColor),
          shape: shape(radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: shape(radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? tokens.surface2 : tokens.surface,
        border: inputBorder(borderColor, 1),
        enabledBorder: inputBorder(borderColor, 1),
        focusedBorder: inputBorder(accent, 1.5),
        errorBorder: inputBorder(tokens.danger, 1),
        focusedErrorBorder: inputBorder(tokens.danger, 1.5),
        labelStyle: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.8)),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: shape(cardR, side: containerSide),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape(cardR, side: containerSide),
        titleTextStyle: ObsidianTokens.serif(base: TextStyle(color: ink), size: 22, weight: FontWeight.w600),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(cardR)),
          side: containerSide,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: shape(cardR, side: containerSide),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? tokens.surface3 : tokens.ink,
        contentTextStyle: TextStyle(color: dark ? tokens.ink : Colors.white),
        shape: shape(cardR),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surface2,
        labelStyle: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500),
        shape: shape(pillR, side: BorderSide(color: borderColor)),
        side: BorderSide(color: borderColor),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: shape(cardR),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: tokens.surface3,
        circularTrackColor: tokens.surface3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: shape(radius.clamp(2.0, 6.0).toDouble()),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: borderColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: bgSolid,
        scrimColor: Colors.black54,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSolid,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.12),
        indicatorShape: shape(cardR),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: bgSolid,
        indicatorColor: accent.withValues(alpha: 0.12),
        indicatorShape: shape(cardR),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? tokens.surface3 : tokens.ink,
          borderRadius: BorderRadius.circular(smallR),
        ),
        textStyle: TextStyle(color: dark ? tokens.ink : Colors.white, fontSize: 12),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(tokens.surface2),
        headingTextStyle: TextStyle(
          fontFamily: ObsidianTokens.fontSans,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: muted,
        ),
        dataTextStyle: TextStyle(
          fontFamily: ObsidianTokens.fontSans,
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          color: ink,
        ),
        dividerThickness: 1,
        horizontalMargin: 16,
        columnSpacing: 20,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: ObsidianTokens.fontSans,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: ObsidianTokens.fontSans,
          fontSize: 13,
          color: muted,
        ),
        shape: shape(smallR),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: surfaceColor,
        collapsedBackgroundColor: surfaceColor,
        iconColor: muted,
        collapsedIconColor: muted,
        textColor: ink,
        collapsedTextColor: ink,
        shape: shape(cardR, side: containerSide),
        collapsedShape: shape(cardR, side: containerSide),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : tokens.surface2,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : muted,
          ),
          side: WidgetStateProperty.all(BorderSide(color: borderColor)),
          shape: WidgetStateProperty.all(shape(smallR)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(muted.withValues(alpha: 0.3)),
        radius: const Radius.circular(3),
        thickness: WidgetStateProperty.all(6),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: tokens.surface3,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.14),
      ),
    );
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static ObsidianTokens _tokens(BuildContext context) =>
      isDark(context) ? ObsidianTokens.dark : ObsidianTokens.light;

  static Color getPrimaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkAccent : custom.lightAccent);
      if (parsed != null) return parsed;
    }
    return _tokens(context).accent;
  }

  static Color getSecondaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkAccent2 : custom.lightAccent2);
      if (parsed != null) return parsed;
    }
    return _tokens(context).accent2;
  }

  static Color getTertiaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkAccent3 : custom.lightAccent3);
      if (parsed != null) return parsed;
    }
    return _tokens(context).accent3;
  }

  // Semantic status colors that follow light / dark mode.
  static Color success(BuildContext context) => _tokens(context).success;
  static Color warning(BuildContext context) => _tokens(context).warning;
  static Color danger(BuildContext context) => _tokens(context).danger;

  static Color getGlassSurfaceColor(BuildContext context) => getSurfaceColor(context);

  static Color getGlassBorderColor(BuildContext context) => getBorderColor(context);

  static Color getPrimaryTextColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkInk : custom.lightInk);
      if (parsed != null) return parsed;
    }
    return _tokens(context).ink;
  }

  static Color getSecondaryTextColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkMuted : custom.lightMuted);
      if (parsed != null) return parsed;
    }
    return _tokens(context).muted;
  }

  static Color getTertiaryTextColor(BuildContext context) =>
      getSecondaryTextColor(context).withValues(alpha: 0.8);

  static Color getFaintTextColor(BuildContext context) =>
      getSecondaryTextColor(context).withValues(alpha: 0.55);

  static Color getBorderColor(BuildContext context) {
    if (isDark(context) && isCustomThemeActiveAndNonDefault) {
      return Color.alphaBlend(Colors.white.withValues(alpha: 0.085), getSurfaceColor(context));
    }
    return _tokens(context).border;
  }

  static Color getInputFillColor(BuildContext context) {
    final t = _tokens(context);
    return isDark(context) ? t.surface2 : t.surface;
  }

  static Color getSurfaceColor(BuildContext context) {
    final dark = isDark(context);
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(dark ? custom.darkCard : custom.lightCard);
      if (parsed != null) return parsed;
      if (dark) {
        return deriveDarkCardSurface(getBackgroundColor(context), accent: getPrimaryAccent(context));
      }
    }
    return _tokens(context).surface;
  }

  static Color getElevatedSurfaceColor(BuildContext context) {
    if (isDark(context)) {
      return Color.alphaBlend(Colors.white.withValues(alpha: 0.04), getSurfaceColor(context));
    }
    return _tokens(context).surface;
  }

  static BorderSide getTooltipBorder(BuildContext context) {
    return BorderSide(color: getBorderColor(context), width: 1.0);
  }

  static Color getBackgroundColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final parsed = parseHex(isDark(context) ? custom.darkBg : custom.lightBg);
      if (parsed != null) return parsed;
    }
    return _tokens(context).bg;
  }

  static Decoration getBackgroundDecoration(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final bgStr = isDark(context) ? custom.darkBg : custom.lightBg;
      final grad = parseGradient(bgStr);
      if (grad != null) {
        return BoxDecoration(gradient: grad);
      }
      final solid = parseHex(bgStr);
      if (solid != null) {
        return BoxDecoration(color: solid);
      }
    }
    return BoxDecoration(color: _tokens(context).bg);
  }

  /// Card corner radius. [defaultRadius] is only used when a screen wants to override the
  /// site's container radius; most callers should omit it.
  static double getCardBorderRadius(BuildContext context, {double? defaultRadius}) {
    final dark = isDark(context);
    if (_presetRadius(dark: dark) != null) return containerRadius(dark: dark);
    return (defaultRadius ?? ObsidianTokens.radius).clamp(0.0, 16.0).toDouble();
  }

  static TextStyle tabularFigures({TextStyle? style}) {
    return (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
