import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'services/api_service.dart';
import 'shell/main_shell.dart';
import 'theme/obsidian_ui_theme.dart';
import 'widgets/obsidian_feedback.dart';

class ObsidianscoutApp extends StatelessWidget {
  final ApiService apiService;

  const ObsidianscoutApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        apiService.themeNotifier,
        apiService.useServerCustomThemeNotifier,
        apiService.customThemeNotifier,
        apiService.localeNotifier,
        apiService.uiModeNotifier,
        apiService.desktopTabsNotifier,
      ]),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: ObsidianFeedback.navigatorKey,
          scaffoldMessengerKey: ObsidianFeedback.messengerKey,
          title: 'ObsidianScout',
          debugShowCheckedModeBanner: false,
          theme: ObsidianUITheme.lightTheme,
          darkTheme: ObsidianUITheme.darkTheme,
          themeMode: apiService.themeMode,
          locale: apiService.currentLocale,
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
            Locale('he'),
            Locale('tr'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: const ObsidianBouncingScrollBehavior(),
          home: MainShell(apiService: apiService),
        );
      },
    );
  }
}

class ObsidianBouncingScrollBehavior extends MaterialScrollBehavior {
  const ObsidianBouncingScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
