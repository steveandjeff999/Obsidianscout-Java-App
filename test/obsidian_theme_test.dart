import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/theme/obsidian_tokens.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';

void main() {
  tearDown(() => ObsidianUITheme.setCustomTheme(null));

  test('site tokens drive light and dark themes', () {
    final light = ObsidianUITheme.lightTheme;
    final dark = ObsidianUITheme.darkTheme;
    expect(light.scaffoldBackgroundColor, ObsidianTokens.light.bg);
    expect(dark.scaffoldBackgroundColor, ObsidianTokens.dark.bg);
    expect(light.colorScheme.primary, ObsidianTokens.light.accent);
    expect(dark.colorScheme.primary, ObsidianTokens.dark.accent);
    expect(light.extension<ObsidianTokens>(), isNotNull);
    expect(light.textTheme.headlineMedium!.fontFamily, ObsidianTokens.fontSerif);
    expect(light.textTheme.bodyMedium!.fontFamily, ObsidianTokens.fontSans);
  });

  test('site corner radii by default', () {
    expect(ObsidianUITheme.containerRadius(dark: true), ObsidianTokens.radius);
    expect(ObsidianUITheme.controlRadius(dark: false), ObsidianTokens.radiusSm);
    expect(ObsidianUITheme.pillRadius(dark: false), ObsidianTokens.radiusPill);
  });

  test('Default preset with shipped values uses the site look, 999px is ignored', () {
    final preset = ThemePresetModel.fromJson({
      'name': 'Default',
      'darkBg': '#09090b',
      'lightBg': '#ffffff',
      'darkAccent': '#3ccfc0',
      'lightAccent': '#0b8f88',
      'btnRadius': '999px',
    });
    ObsidianUITheme.setCustomTheme(preset);
    expect(ObsidianUITheme.activeCustomTheme, isNull);
    expect(ObsidianUITheme.lightTheme.scaffoldBackgroundColor, ObsidianTokens.light.bg);
    expect(ObsidianUITheme.controlRadius(dark: true), ObsidianTokens.radiusSm);
  });

  test('a named preset keeps its colors and corners', () {
    final preset = ThemePresetModel.fromJson({
      'name': 'Mine',
      'darkAccent': '#ff0000',
      'btnRadius': '12px',
    });
    ObsidianUITheme.setCustomTheme(preset);
    expect(ObsidianUITheme.darkTheme.colorScheme.primary, const Color(0xFFFF0000));
    expect(ObsidianUITheme.controlRadius(dark: true), 12.0);
    expect(ObsidianUITheme.containerRadius(dark: true), 12.0);
  });
}
