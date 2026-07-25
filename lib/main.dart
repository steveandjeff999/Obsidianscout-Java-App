import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'theme/obsidian_ui_theme.dart';
import 'widgets/obsidian_glass_app_bar.dart';
import 'widgets/obsidian_bottom_nav.dart';
import 'widgets/obsidian_drawer.dart';
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: apiService.themeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp(
          title: 'ObsidianScout',
          debugShowCheckedModeBanner: false,
          theme: ObsidianUITheme.lightTheme,
          darkTheme: ObsidianUITheme.darkTheme,
          themeMode: currentThemeMode,
          home: MainShell(apiService: apiService),
        );
      },
    );
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
            backgroundColor: ObsidianUITheme.surface,
            content: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                      Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

  final List<String> _titles = [
    'Dashboard',
    'Match Scout',
    'Pit Scout',
    'Qual Scout',
    'Graphs',
    'Settings & Cache',
    'Team Chat',
    'Alliance Selection',
  ];
  final List<String> _subtitles = [
    'Overview',
    'Match Form',
    'Pit Inspection',
    'Qualitative Form',
    'Data Visualization',
    'Cache Manager & Config',
    'Channels & Messages',
    'Playoff Pick Lists & Alliances',
  ];

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => QrScannerScreen(apiService: widget.apiService),
      ),
    );
  }

  Future<void> _handleLogout() async {
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
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90.0),
        child: AnimatedSlide(
          offset: _isBarsVisible ? Offset.zero : const Offset(0, -1.2),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          child: ObsidianGlassAppBar(
            title: _titles[_currentIndex],
            subtitle: _subtitles[_currentIndex],
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
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) {
            if (notification.direction == ScrollDirection.reverse) {
              if (_isBarsVisible) {
                setState(() => _isBarsVisible = false);
              }
            } else if (notification.direction == ScrollDirection.forward) {
              if (!_isBarsVisible) {
                setState(() => _isBarsVisible = true);
              }
            }
          }
          return false;
        },
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1600.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: IndexedStack(
              index: _currentIndex,
              children: screens,
            ),
          ),
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        offset: _isBarsVisible ? Offset.zero : const Offset(0, 1.5),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
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
    );
  }
}
