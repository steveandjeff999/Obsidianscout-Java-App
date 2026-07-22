import 'dart:async';
import 'package:flutter/material.dart';
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
import 'screens/qr_scanner_screen.dart';
import 'services/api_service.dart';

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
    return MaterialApp(
      title: 'Obsidianscout App',
      debugShowCheckedModeBanner: false,
      theme: ObsidianUITheme.darkTheme,
      home: MainShell(apiService: apiService),
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
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    super.dispose();
  }

  final List<String> _titles = ['Dashboard', 'Match Scout', 'Pit Scout', 'Qual Scout', 'Graphs', 'Settings & Cache'];
  final List<String> _subtitles = [
    'Overview',
    'Match Form',
    'Pit Inspection',
    'Qualitative Form',
    'Data Visualization',
    'Cache Manager & Config',
  ];

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => QrScannerScreen(apiService: widget.apiService),
      ),
    );
  }

  Future<void> _handleLogout() async {
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
      ),
      MatchScoutScreen(apiService: widget.apiService),
      PitScoutScreen(apiService: widget.apiService),
      QualScoutScreen(apiService: widget.apiService),
      GraphsScreen(apiService: widget.apiService),
      SettingsScreen(apiService: widget.apiService, onLogout: _handleLogout),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: ObsidianGlassAppBar(
        title: _titles[_currentIndex],
        subtitle: _subtitles[_currentIndex],
        isOnline: _isOnline,
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              tooltip: 'Navigation Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent),
            tooltip: 'QR & Barcode Scanner',
            onPressed: _openQrScanner,
          ),
        ],
      ),
      drawer: ObsidianNavigationDrawer(
        apiService: widget.apiService,
        currentIndex: _currentIndex,
        onSelectScreen: (index) => setState(() => _currentIndex = index),
        onOpenQrScanner: _openQrScanner,
        onLogout: _handleLogout,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900.0),
          decoration: const BoxDecoration(
            color: ObsidianUITheme.background,
          ),
          child: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600.0),
            child: ObsidianBottomNav(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
            ),
          ),
        ),
      ),
    );
  }
}
