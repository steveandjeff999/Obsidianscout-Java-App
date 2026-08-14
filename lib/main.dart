import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'theme/obsidian_ui_theme.dart';
import 'widgets/obsidian_glass_app_bar.dart';
import 'widgets/obsidian_bottom_nav.dart';
import 'widgets/obsidian_drawer.dart';
import 'widgets/obsidian_banner_widget.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/match_scout_screen.dart';
import 'screens/pit_scout_screen.dart';
import 'screens/qual_scout_screen.dart';
import 'screens/graphs_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/alliance_selection_screen.dart';
import 'screens/teams_list_screen.dart';
import 'screens/match_list_screen.dart';
import 'services/api_service.dart';
import 'services/fcm_helper.dart';
import 'services/notification_websocket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  await apiService.init();
  runApp(ObsidianscoutApp(apiService: apiService));
}

class ObsidianscoutApp extends StatelessWidget {
  final ApiService apiService;

  const ObsidianscoutApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([apiService.themeNotifier, apiService.localeNotifier]),
      builder: (context, child) {
        return MaterialApp(
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

class MainShell extends StatefulWidget {
  final ApiService apiService;

  const MainShell({super.key, required this.apiService});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late bool _isAuthenticated;
  late bool _isOnline;
  int _currentIndex = 0;
  StreamSubscription<bool>? _onlineSub;

  String? _pendingChatChannel;
  NotificationWebSocketService? _wsNotificationService;
  bool _isBarsVisible = true;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = widget.apiService.isLoggedIn;
    _isOnline = widget.apiService.isOnline;
    _onlineSub = widget.apiService.onOnlineStatusChanged.listen((online) {
      if (mounted) {
        setState(() => _isOnline = online);
      }
    });

    if (_isAuthenticated) {
      _bootstrapFcm();
      _bootstrapWsNotifications();
    }
  }

  void _bootstrapFcm() {
    FcmHelper.initializeDynamicFcm(widget.apiService, (groupName) {
      if (mounted) {
        setState(() {
          _pendingChatChannel = groupName;
          _currentIndex = 6;
        });
      }
    });
  }

  void _bootstrapWsNotifications() {
    _wsNotificationService = NotificationWebSocketService(
      apiService: widget.apiService,
      onNotificationReceived: (groupName, title, body, sender) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            backgroundColor: ObsidianUITheme.getSurfaceColor(context),
            content: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13)),
                      Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.cyanAccent,
              onPressed: () {
                setState(() {
                  _pendingChatChannel = groupName;
                  _currentIndex = 6;
                });
              },
            ),
          ),
        );
      },
    )..connect();
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _wsNotificationService?.dispose();
    super.dispose();
  }

  final List<String> _titleKeys = [
    'nav.dashboard',
    'nav.match_scout',
    'nav.pit_scout',
    'nav.qual_scout',
    'nav.graphs',
    'nav.settings_cache',
    'nav.team_chat',
    'nav.alliance_selection',
    'nav.teams',
    'nav.matches',
  ];
  final List<String> _subtitleKeys = [
    'subtitle.dashboard',
    'subtitle.match_scout',
    'subtitle.pit_scout',
    'subtitle.qual_scout',
    'subtitle.graphs',
    'subtitle.settings',
    'subtitle.chat',
    'subtitle.alliance_selection',
    'subtitle.teams',
    'subtitle.matches',
  ];

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => QrScannerScreen(apiService: widget.apiService),
      ),
    );
  }

  Future<void> _handleLogout() async {
    _wsNotificationService?.dispose();
    _wsNotificationService = null;
    await FcmHelper.unregisterOnLogout(widget.apiService);
    await widget.apiService.logout();
    if (mounted) {
      setState(() {
        _isAuthenticated = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return LoginScreen(
        apiService: widget.apiService,
        onLoginSuccess: () {
          setState(() {
            _isAuthenticated = true;
          });
          _bootstrapFcm();
        },
      );
    }

    final screens = [
      DashboardScreen(
        apiService: widget.apiService,
        onNavigateMatch: () => setState(() => _currentIndex = 1),
        onNavigatePit: () => setState(() => _currentIndex = 2),
        onNavigateAnalytics: () => setState(() => _currentIndex = 4),
        onNavigateQrScanner: _openQrScanner,
        onNavigateAlliance: () => setState(() => _currentIndex = 7),
        isVisible: _currentIndex == 0,
        isBarsVisible: _isBarsVisible,
      ),
      MatchScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 1, isBarsVisible: _isBarsVisible),
      PitScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 2, isBarsVisible: _isBarsVisible),
      QualScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 3, isBarsVisible: _isBarsVisible),
      GraphsScreen(apiService: widget.apiService, isVisible: _currentIndex == 4, isBarsVisible: _isBarsVisible),
      SettingsScreen(apiService: widget.apiService, onLogout: _handleLogout, isVisible: _currentIndex == 5, isBarsVisible: _isBarsVisible),
      ChatScreen(
        apiService: widget.apiService,
        initialChannel: _pendingChatChannel,
        isVisible: _currentIndex == 6,
        isBarsVisible: _isBarsVisible,
      ),
      AllianceSelectionScreen(apiService: widget.apiService, isVisible: _currentIndex == 7, isBarsVisible: _isBarsVisible),
      TeamsListScreen(apiService: widget.apiService, isVisible: _currentIndex == 8, isBarsVisible: _isBarsVisible),
      MatchListScreen(apiService: widget.apiService, isVisible: _currentIndex == 9, isBarsVisible: _isBarsVisible),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90.0),
        child: AnimatedOpacity(
          opacity: _isBarsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: AnimatedSlide(
            offset: _isBarsVisible ? Offset.zero : const Offset(0, -0.8),
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child: ObsidianGlassAppBar(
              title: context.tr(_titleKeys[_currentIndex]),
              subtitle: context.tr(_subtitleKeys[_currentIndex]),
              isOnline: _isOnline,
              actions: [
                IconButton(
                  icon: Icon(
                    widget.apiService.themeMode == ThemeMode.light
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: widget.apiService.themeMode == ThemeMode.light
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFFFB703),
                  ),
                  tooltip: widget.apiService.themeMode == ThemeMode.light
                      ? 'Switch to Dark Mode'
                      : 'Switch to Light Mode',
                  onPressed: () {
                    final nextMode = widget.apiService.themeMode == ThemeMode.light
                        ? ThemeMode.dark
                        : ThemeMode.light;
                    widget.apiService.setThemeMode(nextMode);
                  },
                ),
                Builder(
                  builder: (ctx) => IconButton(
                    icon: Icon(
                      Icons.menu_rounded,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF0F172A),
                    ),
                    tooltip: 'Navigation Menu',
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.cyanAccent
                        : const Color(0xFF0284C7),
                  ),
                  tooltip: 'QR & Barcode Scanner',
                  onPressed: _openQrScanner,
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: ObsidianNavigationDrawer(
        apiService: widget.apiService,
        currentIndex: _currentIndex,
        onSelectScreen: (index) => setState(() {
          _currentIndex = index;
          _isBarsVisible = true;
        }),
        onOpenQrScanner: _openQrScanner,
        onLogout: _handleLogout,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1600.0),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                height: _isBarsVisible ? 95.0 : 16.0,
              ),
              ObsidianBannerWidget(
                apiService: widget.apiService,
                isBarsVisible: _isBarsVisible,
              ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: screens,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedOpacity(
        opacity: _isBarsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: AnimatedSlide(
          offset: _isBarsVisible ? Offset.zero : const Offset(0, 0.8),
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600.0),
                child: ObsidianBottomNav(
                  currentIndex: _currentIndex,
                  onTap: (index) => setState(() {
                    _currentIndex = index;
                    _isBarsVisible = true;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
