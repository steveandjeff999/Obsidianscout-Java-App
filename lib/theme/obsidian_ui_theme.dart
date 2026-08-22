import 'package:flutter/material.dart';
import 'obsidian_page_transitions.dart';

class ObsidianUITheme {
  // Brand colors (Dark)
  static const Color background = Color(0xFF0A0C10);
  static const Color surface = Color(0xFF121620);

  // Brand colors (Light)
  static const Color backgroundLight = Color(0xFFF4F6FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  static const Color primaryAccent = Color(0xFF5B6CFF); // Electric Blue/Violet
  static const Color secondaryAccent = Color(0xFF9D4EDD); // Glowing Purple
  static const Color successGreen = Color(0xFF00E676);
  static const Color warningOrange = Color(0xFFFF9100);
  static const Color errorRed = Color(0xFFFF1744);

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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryAccent,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: surface,
        error: errorRed,
        onSurface: Colors.white,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16.0,
          color: Colors.white70,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          color: Colors.white60,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundLight,
      primaryColor: primaryAccent,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: surfaceLight,
        error: errorRed,
        onSurface: Color(0xFF0F172A),
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32.0,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
        titleLarge: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        bodyLarge: TextStyle(
          fontSize: 16.0,
          color: Color(0xFF334155),
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color getGlassSurfaceColor(BuildContext context) {
    return isDark(context) ? glassSurface : glassSurfaceLightMode;
  }

  static Color getGlassBorderColor(BuildContext context) {
    return isDark(context) ? glassBorderLight : glassBorderLightMode;
  }

  static Color getPrimaryTextColor(BuildContext context) {
    return isDark(context) ? Colors.white : const Color(0xFF0F172A);
  }

  static Color getSecondaryTextColor(BuildContext context) {
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
    return isDark(context) ? surface : surfaceLight;
  }
}

