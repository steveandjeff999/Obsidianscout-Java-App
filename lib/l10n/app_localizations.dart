import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  Map<String, String> _localizedStrings = {};

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Future<bool> load() async {
    try {
      final jsonString = await rootBundle
          .loadString('assets/i18n/${locale.languageCode}.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);

      _localizedStrings = jsonMap.map((key, value) {
        return MapEntry(key, value.toString());
      });
      return true;
    } catch (e) {
      debugPrint('Error loading language asset for ${locale.languageCode}: $e');
      _localizedStrings = {};
      return false;
    }
  }

  String translate(String key, [Map<String, String>? args]) {
    String translation = _localizedStrings[key] ?? key;
    if (args != null && args.isNotEmpty) {
      args.forEach((placeholder, value) {
        translation = translation.replaceAll('{$placeholder}', value);
      });
    }
    return translation;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'es', 'he', 'tr'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  String tr(String key, [dynamic argsOrFallback]) {
    final loc = AppLocalizations.of(this);
    if (argsOrFallback is Map<String, String>) {
      return loc?.translate(key, argsOrFallback) ?? key;
    }
    final translated = loc?.translate(key);
    if (translated == null || translated == key) {
      if (argsOrFallback is String) return argsOrFallback;
    }
    return translated ?? (argsOrFallback is String ? argsOrFallback : key);
  }
}
