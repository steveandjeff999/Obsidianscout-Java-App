import 'package:flutter/material.dart';

class ObsidianUITheme {
  // Brand colors
  static const Color background = Color(0xFF0A0C10);
  static const Color surface = Color(0xFF121620);
  static const Color primaryAccent = Color(0xFF5B6CFF); // Electric Blue/Violet
  static const Color secondaryAccent = Color(0xFF9D4EDD); // Glowing Purple
  static const Color successGreen = Color(0xFF00E676);
  static const Color warningOrange = Color(0xFFFF9100);
  static const Color errorRed = Color(0xFFFF1744);

  // Glassmorphism translucent fills & borders
  static const Color glassSurface = Color(0x18FFFFFF);
  static const Color glassSurfaceHover = Color(0x28FFFFFF);
  static const Color glassBorderLight = Color(0x33FFFFFF);
  static const Color glassBorderDark = Color(0x0DFFFFFF);
  static const Color glassInputBackground = Color(0x10FFFFFF);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primaryAccent,
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
}
