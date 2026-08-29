import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/l10n/app_localizations.dart';
import 'package:obsidianscout_app/main.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/theme/obsidian_responsive.dart';
import 'package:obsidianscout_app/widgets/obsidian_desktop_sidebar.dart';
import 'package:obsidianscout_app/widgets/obsidian_desktop_app_bar.dart';
import 'package:obsidianscout_app/widgets/dynamic_field_widget.dart';
import 'package:obsidianscout_app/widgets/obsidian_bottom_nav.dart';

class _MockResponsiveApiService extends ApiService {
  bool _mockLoggedIn = true;
  String _mode = 'auto';

  @override
  bool get isLoggedIn => _mockLoggedIn;

  @override
  String get uiMode => _mode;

  void setMockUiMode(String mode) {
    _mode = mode;
    uiModeNotifier.value = mode;
  }

  @override
  bool hasPageAccess(String pageId) => true;

  @override
  Future<String?> fetchCurrentEventKey() async => '2026test';

  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'Test Config',
        fields: [
          ScoutingFieldModel(id: 'teleop_speaker', label: 'Speaker Notes', type: 'counter', phase: 'teleop'),
        ],
      );

  @override
  Future<List<TeamModel>> fetchTeams(String? eventKey) async => [
        TeamModel(eventKey: '2026test', teamKey: 'frc254', teamNumber: 254, name: 'The Cheesy Poofs'),
      ];

  @override
  Future<List<MatchModel>> fetchMatches(String? eventKey) async => [
        MatchModel(matchKey: '2026test_qm1', eventKey: '2026test', matchNumber: 1, compLevel: 'qm', label: 'Quals 1'),
      ];
}

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations() : super(const Locale('en'));

  @override
  String translate(String key, [Map<String, String>? args]) {
    final map = {
      'nav.dashboard': 'Dashboard',
      'subtitle.dashboard': 'Event Overview',
      'nav.match_scout': 'Match Scout',
      'subtitle.match_scout': 'Field Match Scoring',
      'nav.pit_scout': 'Pit Scout',
      'subtitle.pit_scout': 'Robot Inspection',
      'nav.graphs': 'Analytics',
      'subtitle.graphs': 'Metrics & Graphs',
      'nav.settings_cache': 'Settings & Cache',
      'subtitle.settings': 'Preferences',
      'app.title': 'ObsidianScout',
      'dashboard.notice': 'Realtime offline-first scouting system.',
      'dashboard.event_context': 'Event Context',
      'scout.select_team': 'Select Team',
      'scout.select_match': 'Select Match',
      'scout.save_entry': 'Save Entry',
      'scout.select_a_team_and_match_to_sta': 'Select a team and match to start scouting.',
      'qr.button_label': 'Generate QR Code',
    };
    return map[key] ?? key;
  }
}

class _TestAppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async => _TestAppLocalizations();

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

void main() {
  Widget createTestApp(Widget home) {
    return MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: home,
    );
  }

  group('ObsidianResponsive Unit Tests', () {
    testWidgets('Respects overrideMode desktop vs mobile', (tester) async {
      await tester.pumpWidget(createTestApp(
        Builder(
          builder: (context) {
            expect(ObsidianResponsive.isDesktop(context, overrideMode: 'desktop'), isTrue);
            expect(ObsidianResponsive.isDesktop(context, overrideMode: 'mobile'), isFalse);
            expect(ObsidianResponsive.isMobile(context, overrideMode: 'desktop'), isFalse);
            expect(ObsidianResponsive.isMobile(context, overrideMode: 'mobile'), isTrue);
            return const SizedBox();
          },
        ),
      ));
    });
  });

  group('Dual-Mode MainShell Widget Tests', () {
    testWidgets('MainShell renders Mobile layout when mode is mobile', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockResponsiveApiService();
      mockApi.setMockUiMode('mobile');

      await tester.pumpWidget(createTestApp(MainShell(apiService: mockApi)));
      await tester.pumpAndSettle();

      // Mobile layout should have ObsidianBottomNav and NOT have ObsidianDesktopSidebar
      expect(find.byType(ObsidianBottomNav), findsOneWidget);
      expect(find.byType(ObsidianDesktopSidebar), findsNothing);
    });

    testWidgets('MainShell renders PC Desktop layout when mode is desktop', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockResponsiveApiService();
      mockApi.setMockUiMode('desktop');

      await tester.pumpWidget(createTestApp(MainShell(apiService: mockApi)));
      await tester.pumpAndSettle();

      // Desktop layout should have ObsidianDesktopSidebar and ObsidianDesktopAppBar, and NO bottom navigation bar
      expect(find.byType(ObsidianDesktopSidebar), findsOneWidget);
      expect(find.byType(ObsidianDesktopAppBar), findsOneWidget);
      expect(find.byType(ObsidianBottomNav), findsNothing);
    });
    testWidgets('Screen rotation does not unmount active screens and preserves state', (tester) async {
      // Start in Portrait mobile size
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockResponsiveApiService();
      mockApi.setMockUiMode('auto');

      await tester.pumpWidget(createTestApp(MainShell(apiService: mockApi)));
      await tester.pumpAndSettle();

      expect(find.byType(ObsidianBottomNav), findsOneWidget);

      // Rotate to Landscape (width >= 840.0)
      tester.view.physicalSize = const Size(850, 400);
      await tester.pumpAndSettle();

      // Verify layout adjusted to desktop without throwing any unmount errors
      expect(find.byType(ObsidianDesktopSidebar), findsOneWidget);

      // Rotate back to Portrait
      tester.view.physicalSize = const Size(400, 850);
      await tester.pumpAndSettle();

      expect(find.byType(ObsidianBottomNav), findsOneWidget);
    });
  });

  group('DynamicFieldWidget Desktop vs Mobile Rendering', () {
    testWidgets('Renders compact stepper on Desktop and touch stepper on Mobile', (tester) async {
      final field = ScoutingFieldModel(id: 'notes', label: 'Speaker Notes', type: 'counter');
      num currentVal = 3;

      // Mobile Test
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestApp(
        Scaffold(
          body: DynamicFieldWidget(
            field: field,
            currentValue: currentVal,
            onChanged: (val) => currentVal = val,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Speaker Notes'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Desktop Test
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpWidget(createTestApp(
        Scaffold(
          body: DynamicFieldWidget(
            field: field,
            currentValue: currentVal,
            onChanged: (val) => currentVal = val,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Speaker Notes'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}
