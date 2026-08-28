import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'theme/obsidian_ui_theme.dart';
import 'theme/obsidian_page_transitions.dart';
import 'theme/obsidian_responsive.dart';
import 'widgets/obsidian_glass_app_bar.dart';
import 'widgets/obsidian_bottom_nav.dart';
import 'widgets/obsidian_drawer.dart';
import 'widgets/obsidian_desktop_sidebar.dart';
import 'widgets/obsidian_desktop_app_bar.dart';
import 'widgets/obsidian_banner_widget.dart';
import 'widgets/obsidian_feedback.dart';
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
import 'screens/config_editor_screen.dart';
import 'screens/prescout_screen.dart';
import 'screens/all_data_screen.dart';
import 'screens/match_data_screen.dart';
import 'screens/pit_data_screen.dart';
import 'screens/qual_data_screen.dart';
import 'screens/data_validation_screen.dart';
import 'screens/scout_history_screen.dart';
import 'screens/custom_analytics_screen.dart';
import 'screens/contact_screen.dart';
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
      listenable: Listenable.merge([apiService.themeNotifier, apiService.localeNotifier, apiService.uiModeNotifier]),
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

class MainShell extends StatefulWidget {
  final ApiService apiService;

  const MainShell({super.key, required this.apiService});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<int> _screenHistory = [];
  DateTime? _lastBackPressTime;

  late bool _isAuthenticated;
  late bool _isOnline;
  int _currentIndex = 0;
  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<int>? _serverErrorSub;
  StreamSubscription<String>? _sessionRevokedSub;

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
    _serverErrorSub = widget.apiService.onServerError.listen((statusCode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB91C1C),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Server error ($statusCode). Something went wrong — please try again.',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    });

    _sessionRevokedSub = widget.apiService.onSessionRevoked.listen((reason) {
      if (!mounted) return;
      _wsNotificationService?.dispose();
      _wsNotificationService = null;
      setState(() {
        _isAuthenticated = false;
        _currentIndex = 0;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB91C1C),
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reason.isNotEmpty ? reason : 'Your session was revoked. Please log in again.',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    });

    if (_isAuthenticated) {
      _bootstrapFcm();
      _bootstrapWsNotifications();
    }

    widget.apiService.permissionsNotifier.addListener(_onPermissionsChanged);
  }

  void _onPermissionsChanged() {
    if (!mounted) return;
    final currentPageId = _getPageIdForIndex(_currentIndex);
    if (!widget.apiService.hasPageAccess(currentPageId)) {
      setState(() {
        _currentIndex = 0;
      });
    } else {
      setState(() {});
    }
  }

  void _bootstrapFcm() {
    FcmHelper.initializeDynamicFcm(widget.apiService, (groupName) {
      if (mounted) {
        setState(() {
          _pendingChatChannel = groupName;
          _navigateScreen(6);
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
                  _navigateScreen(6);
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
    widget.apiService.permissionsNotifier.removeListener(_onPermissionsChanged);
    _onlineSub?.cancel();
    _serverErrorSub?.cancel();
    _sessionRevokedSub?.cancel();
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
    'nav.config_editor',
    'nav.prescout',
    'nav.all_data',
    'nav.match_data',
    'nav.pit_data',
    'nav.qual_data',
    'nav.data_validation',
    'nav.scout_history',
    'nav.custom_analytics',
    'nav.contact',
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
    'subtitle.config_editor',
    'subtitle.prescout',
    'subtitle.all_data',
    'subtitle.match_data',
    'subtitle.pit_data',
    'subtitle.qual_data',
    'subtitle.data_validation',
    'subtitle.scout_history',
    'subtitle.custom_analytics',
    'subtitle.contact',
  ];

  String _getPageIdForIndex(int index) {
    switch (index) {
      case 0:
        return 'dashboard';
      case 1:
        return 'scout';
      case 2:
        return 'pit-scout';
      case 3:
        return 'qual-scout';
      case 4:
        return 'graphs';
      case 5:
        return 'settings';
      case 6:
        return 'chat';
      case 7:
        return 'alliance-selection';
      case 8:
        return 'teams';
      case 9:
        return 'matches';
      case 10:
        return 'admin-settings';
      case 11:
        return 'prescout';
      case 12:
        return 'all-data';
      case 13:
        return 'match-data';
      case 14:
        return 'pit-data';
      case 15:
        return 'qual-data';
      case 16:
        return 'data-validation';
      case 17:
        return 'scout-history';
      case 18:
        return 'custom-analytics';
      case 19:
        return 'contact';
      default:
        return 'dashboard';
    }
  }

  void _navigateScreen(int index) {
    if (_currentIndex == index) return;
    final pageId = _getPageIdForIndex(index);
    if (!widget.apiService.hasPageAccess(pageId)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB91C1C),
          content: Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You do not have access to this page',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    setState(() {
      if (_screenHistory.isEmpty || _screenHistory.last != _currentIndex) {
        _screenHistory.add(_currentIndex);
      }
      _currentIndex = index;
      _isBarsVisible = true;
    });
  }

  void _handleBackPress() {
    // 1. If drawer is open, close it
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }

    // 2. If there is screen navigation history, pop to previous screen
    while (_screenHistory.isNotEmpty) {
      final prevIndex = _screenHistory.removeLast();
      final pageId = _getPageIdForIndex(prevIndex);
      if (prevIndex != _currentIndex && widget.apiService.hasPageAccess(pageId)) {
        setState(() {
          _currentIndex = prevIndex;
          _isBarsVisible = true;
        });
        return;
      }
    }

    // 3. If currently not on Dashboard and history was exhausted, go back to Dashboard
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _isBarsVisible = true;
      });
      return;
    }

    // 4. On Dashboard (root screen): require double back press within 2 seconds to exit
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: ObsidianUITheme.getSurfaceColor(context),
          content: Row(
            children: [
              const Icon(Icons.arrow_back_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('app.press_back_again_to_exit'),
                  style: TextStyle(
                    color: ObsidianUITheme.getPrimaryTextColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      SystemNavigator.pop();
    }
  }

  void _openQrScanner() {
    if (!widget.apiService.hasPageAccess('qr-scanner')) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB91C1C),
          content: Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You do not have access to QR Scanner',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

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
        onNavigateMatch: () => _navigateScreen(1),
        onNavigatePit: () => _navigateScreen(2),
        onNavigateAnalytics: () => _navigateScreen(4),
        onNavigateQrScanner: _openQrScanner,
        onNavigateAlliance: () => _navigateScreen(7),
        onNavigatePrescout: () => _navigateScreen(11),
        onNavigateHistory: () => _navigateScreen(17),
        isVisible: _currentIndex == 0,
        isBarsVisible: _isBarsVisible,
      ),
      MatchScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 1, isBarsVisible: _isBarsVisible),
      PitScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 2, isBarsVisible: _isBarsVisible),
      QualScoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 3, isBarsVisible: _isBarsVisible),
      GraphsScreen(apiService: widget.apiService, isVisible: _currentIndex == 4, isBarsVisible: _isBarsVisible),
      SettingsScreen(
        apiService: widget.apiService,
        onLogout: _handleLogout,
        onNavigateConfigEditor: () => _navigateScreen(10),
        isVisible: _currentIndex == 5,
        isBarsVisible: _isBarsVisible,
      ),
      ChatScreen(
        apiService: widget.apiService,
        initialChannel: _pendingChatChannel,
        isVisible: _currentIndex == 6,
        isBarsVisible: _isBarsVisible,
      ),
      AllianceSelectionScreen(apiService: widget.apiService, isVisible: _currentIndex == 7, isBarsVisible: _isBarsVisible),
      TeamsListScreen(apiService: widget.apiService, isVisible: _currentIndex == 8, isBarsVisible: _isBarsVisible),
      MatchListScreen(apiService: widget.apiService, isVisible: _currentIndex == 9, isBarsVisible: _isBarsVisible),
      ConfigEditorScreen(apiService: widget.apiService, isVisible: _currentIndex == 10, isBarsVisible: _isBarsVisible),
      PrescoutScreen(apiService: widget.apiService, isVisible: _currentIndex == 11, isBarsVisible: _isBarsVisible),
      AllDataScreen(apiService: widget.apiService, isVisible: _currentIndex == 12, isBarsVisible: _isBarsVisible),
      MatchDataScreen(apiService: widget.apiService, isVisible: _currentIndex == 13, isBarsVisible: _isBarsVisible),
      PitDataScreen(apiService: widget.apiService, isVisible: _currentIndex == 14, isBarsVisible: _isBarsVisible),
      QualDataScreen(apiService: widget.apiService, isVisible: _currentIndex == 15, isBarsVisible: _isBarsVisible),
      DataValidationScreen(apiService: widget.apiService, isVisible: _currentIndex == 16, isBarsVisible: _isBarsVisible),
      ScoutHistoryScreen(apiService: widget.apiService, isVisible: _currentIndex == 17, isBarsVisible: _isBarsVisible),
      CustomAnalyticsScreen(apiService: widget.apiService, isVisible: _currentIndex == 18, isBarsVisible: _isBarsVisible),
      ContactScreen(apiService: widget.apiService, isVisible: _currentIndex == 19, isBarsVisible: _isBarsVisible),
    ];

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    if (isDesktop) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _navigateScreen(0),
          const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _navigateScreen(1),
          const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _navigateScreen(2),
          const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _navigateScreen(4),
          const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _navigateScreen(18),
          const SingleActivator(LogicalKeyboardKey.digit6, control: true): () => _navigateScreen(12),
          const SingleActivator(LogicalKeyboardKey.digit7, control: true): () => _navigateScreen(8),
          const SingleActivator(LogicalKeyboardKey.digit8, control: true): () => _navigateScreen(9),
          const SingleActivator(LogicalKeyboardKey.digit9, control: true): () => _navigateScreen(5),
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            final next = widget.apiService.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            widget.apiService.setThemeMode(next);
          },
          const SingleActivator(LogicalKeyboardKey.keyQ, control: true): _openQrScanner,
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _handleBackPress();
            },
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ObsidianDesktopSidebar(
                    apiService: widget.apiService,
                    currentIndex: _currentIndex,
                    onSelectScreen: _navigateScreen,
                    onOpenQrScanner: _openQrScanner,
                    onLogout: _handleLogout,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ObsidianDesktopAppBar(
                          title: context.tr(_titleKeys[_currentIndex]),
                          subtitle: context.tr(_subtitleKeys[_currentIndex]),
                          isOnline: _isOnline,
                          apiService: widget.apiService,
                          onOpenQrScanner: _openQrScanner,
                        ),
                        ObsidianBannerWidget(
                          apiService: widget.apiService,
                          isBarsVisible: true,
                        ),
                        Expanded(
                          child: ObsidianAnimatedIndexedStack(
                            index: _currentIndex,
                            children: screens,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        key: _scaffoldKey,
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
                if (widget.apiService.hasPageAccess('qr-scanner'))
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
        onSelectScreen: _navigateScreen,
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
              const SizedBox(height: 95.0),
              ObsidianBannerWidget(
                apiService: widget.apiService,
                isBarsVisible: _isBarsVisible,
              ),
              Expanded(
                child: ObsidianAnimatedIndexedStack(
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
                  apiService: widget.apiService,
                  currentIndex: _currentIndex,
                  onTap: _navigateScreen,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
