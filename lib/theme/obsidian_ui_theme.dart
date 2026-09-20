import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/config_models.dart';
import 'obsidian_page_transitions.dart';

class ObsidianUITheme {
  // Brand default colors (Dark)
  static const Color defaultBackground = Color(0xFF0A0C10);
  static const Color defaultSurface = Color(0xFF121620);

  // Brand default colors (Light)
  static const Color defaultBackgroundLight = Color(0xFFF4F6FB);
  static const Color defaultSurfaceLight = Color(0xFFFFFFFF);

  static const Color defaultPrimaryAccent = Color(0xFF5B6CFF); // Electric Blue/Violet
  static const Color defaultSecondaryAccent = Color(0xFF9D4EDD); // Glowing Purple
  static const Color successGreen = Color(0xFF00E676);
  static const Color warningOrange = Color(0xFFFF9100);
  static const Color errorRed = Color(0xFFFF1744);

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

  static ThemePresetModel? get activeCustomTheme => _customThemeEnabled ? _customTheme : null;
  static bool get isCustomThemeActive => _customThemeEnabled && _customTheme != null;

  // Dynamic Accents (Context-free fallback)
  static Color get primaryAccent {
    if (_customThemeEnabled && _customTheme != null) {
      final parsed = parseHex(_customTheme!.darkAccent);
      if (parsed != null) return parsed;
    }
    return defaultPrimaryAccent;
  }

  static Color get secondaryAccent {
    if (_customThemeEnabled && _customTheme != null) {
      final parsed = parseHex(_customTheme!.darkAccent2);
      if (parsed != null) return parsed;
    }
    return defaultSecondaryAccent;
  }

  static Color get tertiaryAccent {
    if (_customThemeEnabled && _customTheme != null) {
      final parsed = parseHex(_customTheme!.darkAccent3);
      if (parsed != null) return parsed;
    }
    return const Color(0xFF6AA2FF);
  }

  static double get buttonRadius {
    if (_customThemeEnabled && _customTheme != null) {
      return parseRadius(_customTheme!.btnRadius, fallback: 12.0);
    }
    return 12.0;
  }

  static double getButtonRadius(BuildContext context, {double fallback = 12.0}) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final rStr = isDark(context)
          ? (custom.darkRadius.isNotEmpty ? custom.darkRadius : custom.btnRadius)
          : (custom.lightRadius.isNotEmpty ? custom.lightRadius : custom.btnRadius);
      return parseRadius(rStr, fallback: fallback);
    }
    return fallback;
  }

  // Glassmorphism translucent fills & borders (Dark Mode)
  static const Color glassSurface = Color(0x18FFFFFF);
  static const Color glassSurfaceHover = Color(0x28FFFFFF);
  static const Color glassBorderLight = Color(0x33FFFFFF);
  static const Color glassBorderDark = Color(0x0DFFFFFF);
  static const Color glassInputBackground = Color(0x10FFFFFF);

  // Glassmorphism translucent fills & borders (Light Mode)
  static const Color glassSurfaceLightMode = Color(0xE6FFFFFF);
  static const Color glassBorderLightMode = Color(0x1F000000);
  static const Color glassInputBackgroundLightMode = Color(0x0D000000);

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

  static ThemeData get darkTheme {
    final custom = activeCustomTheme;
    final accent = (custom != null ? parseHex(custom.darkAccent) : null) ?? defaultPrimaryAccent;
    final accent2 = (custom != null ? parseHex(custom.darkAccent2) : null) ?? defaultSecondaryAccent;
    final accent3 = (custom != null ? parseHex(custom.darkAccent3) : null) ?? const Color(0xFF6AA2FF);
    final bgSolid = (custom != null ? parseHex(custom.darkBg) : null) ?? defaultBackground;
    final ink = (custom != null ? parseHex(custom.darkInk) : null) ?? Colors.white;
    final muted = (custom != null ? parseHex(custom.darkMuted) : null) ?? Colors.white70;
    final radiusStr = custom != null
        ? (custom.darkRadius.isNotEmpty ? custom.darkRadius : custom.btnRadius)
        : '12px';
    final radius = parseRadius(radiusStr, fallback: 12.0);
    final cardRadius = custom != null
        ? (parseRadius(radiusStr, fallback: 20.0) >= 999.0
            ? 20.0
            : parseRadius(radiusStr, fallback: 20.0).clamp(0.0, 24.0))
        : 20.0;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgSolid,
      primaryColor: accent,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent2,
        tertiary: accent3,
        surface: defaultSurface,
        error: errorRed,
        onSurface: ink,
        onPrimary: Colors.white,
      ),
      fontFamily: 'Roboto',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassInputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: BorderSide(color: accent, width: 2.0),
        ),
      ),
      cardTheme: CardThemeData(
        color: defaultSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: accent.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: accent.withValues(alpha: 0.2),
        circularTrackColor: accent.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius.clamp(2.0, 6.0))),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.white12,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: bgSolid,
        scrimColor: Colors.black54,
        shape: const RoundedRectangleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSolid,
        indicatorColor: accent.withValues(alpha: 0.2),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32.0,
          fontWeight: FontWeight.bold,
          color: ink,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 16.0,
          color: muted,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          color: muted.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final custom = activeCustomTheme;
    final accent = (custom != null ? parseHex(custom.lightAccent) : null) ?? defaultPrimaryAccent;
    final accent2 = (custom != null ? parseHex(custom.lightAccent2) : null) ?? defaultSecondaryAccent;
    final accent3 = (custom != null ? parseHex(custom.lightAccent3) : null) ?? const Color(0xFF255A9C);
    final bgSolid = (custom != null ? parseHex(custom.lightBg) : null) ?? defaultBackgroundLight;
    final ink = (custom != null ? parseHex(custom.lightInk) : null) ?? const Color(0xFF0F172A);
    final muted = (custom != null ? parseHex(custom.lightMuted) : null) ?? const Color(0xFF334155);
    final radiusStr = custom != null
        ? (custom.lightRadius.isNotEmpty ? custom.lightRadius : custom.btnRadius)
        : '12px';
    final radius = parseRadius(radiusStr, fallback: 12.0);
    final cardRadius = custom != null
        ? (parseRadius(radiusStr, fallback: 20.0) >= 999.0
            ? 20.0
            : parseRadius(radiusStr, fallback: 20.0).clamp(0.0, 24.0))
        : 20.0;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgSolid,
      primaryColor: accent,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: accent2,
        tertiary: accent3,
        surface: defaultSurfaceLight,
        error: errorRed,
        onSurface: ink,
        onPrimary: Colors.white,
      ),
      fontFamily: 'Roboto',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassInputBackgroundLightMode,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: const BorderSide(color: Color(0x1F000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: const BorderSide(color: Color(0x1F000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.clamp(4.0, 16.0)),
          borderSide: BorderSide(color: accent, width: 2.0),
        ),
      ),
      cardTheme: CardThemeData(
        color: defaultSurfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: accent.withValues(alpha: 0.12),
        labelStyle: TextStyle(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: accent.withValues(alpha: 0.2),
        circularTrackColor: accent.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius.clamp(2.0, 6.0))),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: const Color(0x1F000000),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: bgSolid,
        scrimColor: Colors.black54,
        shape: const RoundedRectangleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSolid,
        indicatorColor: accent.withValues(alpha: 0.15),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32.0,
          fontWeight: FontWeight.bold,
          color: ink,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 16.0,
          color: muted,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          color: muted.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color getPrimaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final hex = isDark(context) ? custom.darkAccent : custom.lightAccent;
      final parsed = parseHex(hex);
      if (parsed != null) return parsed;
    }
    return defaultPrimaryAccent;
  }

  static Color getSecondaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final hex = isDark(context) ? custom.darkAccent2 : custom.lightAccent2;
      final parsed = parseHex(hex);
      if (parsed != null) return parsed;
    }
    return defaultSecondaryAccent;
  }

  static Color getTertiaryAccent(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final hex = isDark(context) ? custom.darkAccent3 : custom.lightAccent3;
      final parsed = parseHex(hex);
      if (parsed != null) return parsed;
    }
    return isDark(context) ? const Color(0xFF6AA2FF) : const Color(0xFF255A9C);
  }

  static Color getGlassSurfaceColor(BuildContext context) {
    return isDark(context) ? glassSurface : glassSurfaceLightMode;
  }

  static Color getGlassBorderColor(BuildContext context) {
    return isDark(context) ? glassBorderLight : glassBorderLightMode;
  }

  static Color getPrimaryTextColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final hex = isDark(context) ? custom.darkInk : custom.lightInk;
      final parsed = parseHex(hex);
      if (parsed != null) return parsed;
    }
    return isDark(context) ? Colors.white : const Color(0xFF0F172A);
  }

  static Color getSecondaryTextColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final hex = isDark(context) ? custom.darkMuted : custom.lightMuted;
      final parsed = parseHex(hex);
      if (parsed != null) return parsed;
    }
    return isDark(context) ? Colors.white70 : const Color(0xFF334155);
  }

  static Color getTertiaryTextColor(BuildContext context) {
    return isDark(context) ? Colors.white54 : const Color(0xFF64748B);
  }

  static Color getFaintTextColor(BuildContext context) {
    return isDark(context) ? Colors.white38 : const Color(0xFF94A3B8);
  }

  static Color getBorderColor(BuildContext context) {
    return isDark(context) ? Colors.white12 : const Color(0x1F000000);
  }

  static Color getInputFillColor(BuildContext context) {
    return isDark(context) ? glassInputBackground : glassInputBackgroundLightMode;
  }

  static Color getSurfaceColor(BuildContext context) {
    return isDark(context) ? defaultSurface : defaultSurfaceLight;
  }

  static Color getBackgroundColor(BuildContext context) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final bgStr = isDark(context) ? custom.darkBg : custom.lightBg;
      final parsed = parseHex(bgStr);
      if (parsed != null) return parsed;
    }
    return isDark(context) ? defaultBackground : defaultBackgroundLight;
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
    return BoxDecoration(color: isDark(context) ? defaultBackground : defaultBackgroundLight);
  }

  static double getCardBorderRadius(BuildContext context, {double defaultRadius = 24.0}) {
    final custom = activeCustomTheme;
    if (custom != null) {
      final rStr = isDark(context)
          ? (custom.darkRadius.isNotEmpty ? custom.darkRadius : custom.btnRadius)
          : (custom.lightRadius.isNotEmpty ? custom.lightRadius : custom.btnRadius);
      final parsed = parseRadius(rStr, fallback: defaultRadius);
      if (parsed >= 999.0) {
        return defaultRadius.clamp(0.0, 24.0);
      }
      return parsed.clamp(0.0, 24.0);
    }
    return defaultRadius.clamp(0.0, 24.0);
  }
}


