import 'package:flutter/material.dart';
import 'theme/obsidian_ui_theme.dart';
import 'widgets/obsidian_glass_app_bar.dart';
import 'widgets/obsidian_bottom_nav.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/match_scout_screen.dart';
import 'screens/pit_scout_screen.dart';
import 'screens/qual_scout_screen.dart';
import 'screens/analytics_screen.dart';
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
  bool _isAuthenticated = false;
  int _currentIndex = 0;

  final List<String> _titles = ['Dashboard', 'Match Scout', 'Pit Scout', 'Qual Scout', 'Analytics'];
  final List<String> _subtitles = ['Overview', 'Match Form', 'Pit Inspection', 'Qualitative Form', 'Server Metrics'];

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
        onNavigateMatch: () => setState(() => _currentIndex = 1),
        onNavigatePit: () => setState(() => _currentIndex = 2),
        onNavigateAnalytics: () => setState(() => _currentIndex = 4),
      ),
      MatchScoutScreen(apiService: widget.apiService),
      PitScoutScreen(apiService: widget.apiService),
      QualScoutScreen(apiService: widget.apiService),
      AnalyticsScreen(apiService: widget.apiService),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: ObsidianGlassAppBar(
        title: _titles[_currentIndex],
        subtitle: _subtitles[_currentIndex],
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () {
              setState(() {
                _isAuthenticated = false;
              });
            },
          ),
        ],
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
