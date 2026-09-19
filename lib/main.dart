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
import 'screens/predictor_screen.dart';
import 'screens/event_predictor_screen.dart';
import 'screens/users_screen.dart';
import 'screens/cluster_management_screen.dart';
import 'screens/error_reports_screen.dart';
import 'services/api_service.dart';
import 'services/auth_storage_service.dart';
import 'services/biometric_auth_service.dart';
import 'services/fcm_helper.dart';
import 'services/notification_websocket_service.dart';
import 'widgets/obsidian_glass_card.dart';
import 'models/desktop_tab_model.dart';
import 'widgets/obsidian_desktop_tab_bar.dart';

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
      listenable: Listenable.merge([apiService.themeNotifier, apiService.localeNotifier, apiService.uiModeNotifier, apiService.desktopTabsNotifier]),
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

  final List<DesktopTab> _desktopTabs = [
    DesktopTab(id: 'tab_0', screenIndex: 0),
  ];
  final Map<String, GlobalKey<NavigatorState>> _tabNavigatorKeys = {};
  String _activeTabId = 'tab_0';
  int _tabCounter = 1;

  GlobalKey<NavigatorState> _getTabNavigatorKey(String tabId) {
    return _tabNavigatorKeys.putIfAbsent(tabId, () => GlobalKey<NavigatorState>());
  }

  DesktopTab get _activeTab => _desktopTabs.firstWhere(
        (t) => t.id == _activeTabId,
        orElse: () => _desktopTabs.isNotEmpty ? _desktopTabs.first : DesktopTab(id: 'tab_0', screenIndex: 0),
      );

  int get _activeScreenIndex => _activeTab.screenIndex;

  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<int>? _serverErrorSub;
  StreamSubscription<String>? _sessionRevokedSub;

  String? _pendingChatChannel;
  NotificationWebSocketService? _wsNotificationService;
  bool _isBarsVisible = true;

  bool _isCheckingLaunchLock = true;
  bool _isLaunchLocked = false;
  bool _isUnlocking = false;

  void _openNewTab([int initialIndex = 0]) {
    final pageId = _getPageIdForIndex(initialIndex);
    if (!widget.apiService.hasPageAccess(pageId)) {
      initialIndex = 0;
    }
    final newId = 'tab_${_tabCounter++}';
    final newTab = DesktopTab(id: newId, screenIndex: initialIndex);
    setState(() {
      _desktopTabs.add(newTab);
      _activeTabId = newId;
      _currentIndex = initialIndex;
    });
  }

  void _switchTab(String id) {
    if (_activeTabId == id) return;
    final tab = _desktopTabs.firstWhere((t) => t.id == id, orElse: () => _desktopTabs.first);
    setState(() {
      _activeTabId = tab.id;
      _currentIndex = tab.screenIndex;
    });
  }

  void _closeTab(String id) {
    if (_desktopTabs.length <= 1) return;
    final index = _desktopTabs.indexWhere((t) => t.id == id);
    if (index == -1) return;

    setState(() {
      if (_activeTabId == id) {
        if (index > 0) {
          _activeTabId = _desktopTabs[index - 1].id;
          _currentIndex = _desktopTabs[index - 1].screenIndex;
        } else {
          _activeTabId = _desktopTabs[index + 1].id;
          _currentIndex = _desktopTabs[index + 1].screenIndex;
        }
      }
      _desktopTabs.removeAt(index);
      _tabNavigatorKeys.remove(id);
    });
  }

  void _duplicateTab(String id) {
    final index = _desktopTabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final original = _desktopTabs[index];
    final newId = 'tab_${_tabCounter++}';
    final duplicate = DesktopTab(
      id: newId,
      screenIndex: original.screenIndex,
      customTitle: original.customTitle,
      customIcon: original.customIcon,
      pendingChatChannel: original.pendingChatChannel,
    );
    setState(() {
      _desktopTabs.insert(index + 1, duplicate);
      _activeTabId = newId;
      _currentIndex = duplicate.screenIndex;
    });
  }

  void _closeOtherTabs(String id) {
    final target = _desktopTabs.firstWhere((t) => t.id == id, orElse: () => _desktopTabs.first);
    setState(() {
      _desktopTabs.removeWhere((t) => t.id != target.id);
      _tabNavigatorKeys.removeWhere((key, _) => key != target.id);
      _activeTabId = target.id;
      _currentIndex = target.screenIndex;
    });
  }

  void _cycleTab(bool forward) {
    if (_desktopTabs.length <= 1) return;
    final currentIndex = _desktopTabs.indexWhere((t) => t.id == _activeTabId);
    if (currentIndex == -1) return;
    final nextIndex = forward
        ? (currentIndex + 1) % _desktopTabs.length
        : (currentIndex - 1 + _desktopTabs.length) % _desktopTabs.length;
    _switchTab(_desktopTabs[nextIndex].id);
  }

  void _switchToTabNumber(int tabNumber) {
    if (tabNumber < 1 || tabNumber > _desktopTabs.length) return;
    _switchTab(_desktopTabs[tabNumber - 1].id);
  }

  void _switchToLastTab() {
    if (_desktopTabs.isEmpty) return;
    _switchTab(_desktopTabs.last.id);
  }

  IconData _getScreenIcon(int index) {
    switch (index) {
      case 0:
        return Icons.dashboard_rounded;
      case 1:
        return Icons.sports_esports_rounded;
      case 2:
        return Icons.build_circle_rounded;
      case 3:
        return Icons.rate_review_rounded;
      case 4:
        return Icons.bar_chart_rounded;
      case 5:
        return Icons.settings_suggest_rounded;
      case 6:
        return Icons.chat_bubble_outline_rounded;
      case 7:
        return Icons.stars_rounded;
      case 8:
        return Icons.groups_rounded;
      case 9:
        return Icons.event_note_rounded;
      case 10:
        return Icons.tune_rounded;
      case 11:
        return Icons.history_edu_rounded;
      case 12:
        return Icons.dataset_rounded;
      case 13:
        return Icons.table_chart_rounded;
      case 14:
        return Icons.engineering_rounded;
      case 15:
        return Icons.insights_rounded;
      case 16:
        return Icons.fact_check_rounded;
      case 17:
        return Icons.history_rounded;
      case 18:
        return Icons.auto_graph_rounded;
      case 19:
        return Icons.contact_support_rounded;
      case 20:
        return Icons.auto_awesome_rounded;
      case 21:
        return Icons.leaderboard_rounded;
      case 22:
        return Icons.manage_accounts_rounded;
      case 23:
        return Icons.hub_rounded;
      case 24:
        return Icons.bug_report_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }

  String _getScreenDisplayName(int index) {
    switch (index) {
      case 0:
        return context.tr('nav.dashboard', 'Dashboard');
      case 1:
        return context.tr('nav.scout', context.tr('nav.match_scout', 'Match Scout'));
      case 2:
        return context.tr('nav.pit-scout', context.tr('nav.pit_scout', 'Pit Scout'));
      case 3:
        return context.tr('nav.qual-scout', context.tr('nav.qual_scout', 'Qual Scout'));
      case 4:
        return context.tr('nav.graphs', 'Graphs');
      case 5:
        return context.tr('nav.settings', context.tr('nav.settings_cache', 'Settings'));
      case 6:
        return context.tr('nav.team_chat', context.tr('nav.chat', 'Team Chat'));
      case 7:
        return context.tr('nav.alliance-selection', context.tr('nav.alliance_selection', 'Alliance Selection'));
      case 8:
        return context.tr('nav.teams', 'Teams');
      case 9:
        return context.tr('nav.matches', 'Matches');
      case 10:
        return context.tr('nav.config_editor', 'Config Editor');
      case 11:
        return context.tr('nav.prescout', 'Prescout');
      case 12:
        return context.tr('nav.all-data', context.tr('nav.all_data', 'All Data'));
      case 13:
        return context.tr('nav.match-data', context.tr('nav.match_data', 'Match Data'));
      case 14:
        return context.tr('nav.pit-data', context.tr('nav.pit_data', 'Pit Data'));
      case 15:
        return context.tr('nav.qual-data', context.tr('nav.qual_data', 'Qual Data'));
      case 16:
        return context.tr('nav.data-validation', context.tr('nav.data_validation', 'Data Validation'));
      case 17:
        return context.tr('nav.scout-history', context.tr('nav.scout_history', 'Scout History'));
      case 18:
        return context.tr('nav.custom_analytics', context.tr('nav.analytics', 'Analytics'));
      case 19:
        return context.tr('nav.contact', 'Contact');
      case 20:
        return context.tr('nav.predictor', 'Predictor');
      case 21:
        return context.tr('nav.event-predictor', context.tr('nav.event_predictor', 'Event Predictor'));
      case 22:
        return context.tr('nav.users', 'Users');
      case 23:
        return context.tr('nav.cluster-management', context.tr('nav.cluster_management', 'Cluster'));
      case 24:
        return context.tr('nav.error-reports', context.tr('nav.error_reports', 'Error Reports'));
      default:
        return 'Dashboard';
    }
  }

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

    _checkLaunchLock();

    widget.apiService.permissionsNotifier.addListener(_onPermissionsChanged);
  }

  Future<void> _checkLaunchLock() async {
    final available = await BiometricAuthService.isAvailable();
    final enrolled = await AuthStorageService.isEnrolled();
    final requireOnLaunch = await AuthStorageService.isRequireOnLaunch();

    if (available && enrolled && requireOnLaunch) {
      if (mounted) {
        setState(() {
          _isLaunchLocked = true;
          _isCheckingLaunchLock = false;
        });
        _triggerLaunchBiometricUnlock();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLaunchLocked = false;
        _isCheckingLaunchLock = false;
      });
      if (_isAuthenticated) {
        _bootstrapFcm();
        _bootstrapWsNotifications();
      }
    }
  }

  Future<void> _triggerLaunchBiometricUnlock() async {
    if (_isUnlocking) return;
    setState(() => _isUnlocking = true);

    try {
      final authenticated = await BiometricAuthService.authenticate(
        reason: 'Unlock ObsidianScout with your passkey or biometrics',
      );
      if (authenticated) {
        // User unlocked via biometrics.
        // If session is already active (keep-me-logged-in), let them in without fetching new keys!
        if (widget.apiService.isLoggedIn) {
          if (mounted) {
            setState(() {
              _isLaunchLocked = false;
              _isAuthenticated = true;
            });
            _bootstrapFcm();
            _bootstrapWsNotifications();
          }
          return;
        }

        // If not currently logged in, re-authenticate using stored credentials
        final success = await widget.apiService.silentLogin();
        if (success && mounted) {
          setState(() {
            _isLaunchLocked = false;
            _isAuthenticated = true;
          });
          _bootstrapFcm();
          _bootstrapWsNotifications();
          return;
        } else if (mounted) {
          setState(() {
            _isLaunchLocked = false;
            _isAuthenticated = false;
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isUnlocking = false);
      }
    }
  }

  void _onPermissionsChanged() {
    if (!mounted) return;
    for (final tab in _desktopTabs) {
      final pageId = _getPageIdForIndex(tab.screenIndex);
      if (!widget.apiService.hasPageAccess(pageId)) {
        tab.screenIndex = 0;
      }
    }
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
    'nav.predictor',
    'nav.event_predictor',
    'nav.users',
    'nav.cluster_management',
    'nav.error_reports',
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
    'subtitle.predictor',
    'subtitle.event_predictor',
    'subtitle.users',
    'subtitle.cluster_management',
    'subtitle.error_reports',
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
      case 20:
        return 'predictor';
      case 21:
        return 'event-predictor';
      case 22:
        return 'users';
      case 23:
        return 'cluster-management';
      case 24:
        return 'error-reports';
      default:
        return 'dashboard';
    }
  }

  void _navigateScreen(int index) {
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final isDesktopTabs = isDesktop && widget.apiService.desktopTabsEnabled;

    if (isDesktopTabs) {
      if (_activeTab.screenIndex == index) return;
    } else {
      if (_currentIndex == index) return;
    }

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
      if (isDesktopTabs) {
        final tabNav = _tabNavigatorKeys[_activeTab.id]?.currentState;
        if (tabNav != null && tabNav.canPop()) {
          tabNav.popUntil((route) => route.isFirst);
        }
        if (_activeTab.history.isEmpty || _activeTab.history.last != _activeTab.screenIndex) {
          _activeTab.history.add(_activeTab.screenIndex);
        }
        _activeTab.screenIndex = index;
      } else {
        if (_screenHistory.isEmpty || _screenHistory.last != _currentIndex) {
          _screenHistory.add(_currentIndex);
        }
      }
      _currentIndex = index;
      _isBarsVisible = true;
    });
  }

  void _handleBackPress() {
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final isDesktopTabs = isDesktop && widget.apiService.desktopTabsEnabled;

    // 1. If drawer is open, close it
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }

    if (isDesktopTabs) {
      final tabNav = _tabNavigatorKeys[_activeTab.id]?.currentState;
      if (tabNav != null && tabNav.canPop()) {
        tabNav.pop();
        return;
      }
      while (_activeTab.history.isNotEmpty) {
        final prevIndex = _activeTab.history.removeLast();
        final pageId = _getPageIdForIndex(prevIndex);
        if (prevIndex != _activeTab.screenIndex && widget.apiService.hasPageAccess(pageId)) {
          setState(() {
            _activeTab.screenIndex = prevIndex;
            _currentIndex = prevIndex;
            _isBarsVisible = true;
          });
          return;
        }
      }
      if (_activeTab.screenIndex != 0) {
        setState(() {
          _activeTab.screenIndex = 0;
          _currentIndex = 0;
          _isBarsVisible = true;
        });
        return;
      }
    } else {
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

  List<Widget> _buildScreens({required int screenIndex, required bool isTabActive, String? chatChannel}) {
    return [
      DashboardScreen(
        apiService: widget.apiService,
        onNavigateMatch: () => _navigateScreen(1),
        onNavigatePit: () => _navigateScreen(2),
        onNavigateAnalytics: () => _navigateScreen(4),
        onNavigateQrScanner: _openQrScanner,
        onNavigateAlliance: () => _navigateScreen(7),
        onNavigatePrescout: () => _navigateScreen(11),
        onNavigateHistory: () => _navigateScreen(17),
        isVisible: isTabActive && screenIndex == 0,
        isBarsVisible: _isBarsVisible,
      ),
      MatchScoutScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 1, isBarsVisible: _isBarsVisible),
      PitScoutScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 2, isBarsVisible: _isBarsVisible),
      QualScoutScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 3, isBarsVisible: _isBarsVisible),
      GraphsScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 4, isBarsVisible: _isBarsVisible),
      SettingsScreen(
        apiService: widget.apiService,
        onLogout: _handleLogout,
        onNavigateConfigEditor: () => _navigateScreen(10),
        onNavigateUsers: () => _navigateScreen(22),
        onNavigateErrorReports: () => _navigateScreen(24),
        isVisible: isTabActive && screenIndex == 5,
        isBarsVisible: _isBarsVisible,
      ),
      ChatScreen(
        apiService: widget.apiService,
        initialChannel: chatChannel ?? _pendingChatChannel,
        isVisible: isTabActive && screenIndex == 6,
        isBarsVisible: _isBarsVisible,
      ),
      AllianceSelectionScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 7, isBarsVisible: _isBarsVisible),
      TeamsListScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 8, isBarsVisible: _isBarsVisible),
      MatchListScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 9, isBarsVisible: _isBarsVisible),
      ConfigEditorScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 10, isBarsVisible: _isBarsVisible),
      PrescoutScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 11, isBarsVisible: _isBarsVisible),
      AllDataScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 12, isBarsVisible: _isBarsVisible),
      MatchDataScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 13, isBarsVisible: _isBarsVisible),
      PitDataScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 14, isBarsVisible: _isBarsVisible),
      QualDataScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 15, isBarsVisible: _isBarsVisible),
      DataValidationScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 16, isBarsVisible: _isBarsVisible),
      ScoutHistoryScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 17, isBarsVisible: _isBarsVisible),
      CustomAnalyticsScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 18, isBarsVisible: _isBarsVisible),
      ContactScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 19, isBarsVisible: _isBarsVisible),
      PredictorScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 20, isBarsVisible: _isBarsVisible),
      EventPredictorScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 21, isBarsVisible: _isBarsVisible),
      UsersScreen(apiService: widget.apiService, isVisible: isTabActive && screenIndex == 22, isBarsVisible: _isBarsVisible),
      ClusterManagementScreen(
        apiService: widget.apiService,
        isVisible: isTabActive && screenIndex == 23,
        isBarsVisible: _isBarsVisible,
        onNavigateErrorReports: () => _navigateScreen(24),
      ),
      ErrorReportsScreen(
        apiService: widget.apiService,
        isVisible: isTabActive && screenIndex == 24,
        isBarsVisible: _isBarsVisible,
        onNavigateCluster: () => _navigateScreen(23),
      ),
    ];
  }

  Widget _buildDesktopTabbedContent() {
    final activeIndex = _desktopTabs.indexWhere((t) => t.id == _activeTabId);
    final safeActiveIndex = activeIndex >= 0 ? activeIndex : 0;

    return IndexedStack(
      index: safeActiveIndex,
      children: [
        for (final tab in _desktopTabs)
          Navigator(
            key: _getTabNavigatorKey(tab.id),
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                builder: (context) => ObsidianAnimatedIndexedStack(
                  key: ValueKey('tab_stack_${tab.id}'),
                  index: tab.screenIndex,
                  children: _buildScreens(
                    screenIndex: tab.screenIndex,
                    isTabActive: tab.id == _activeTabId,
                    chatChannel: tab.pendingChatChannel,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingLaunchLock) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SizedBox.shrink(),
      );
    }

    if (_isLaunchLocked) {
      return _buildLaunchLockScreen();
    }

    if (!_isAuthenticated) {
      return LoginScreen(
        apiService: widget.apiService,
        onLoginSuccess: () {
          setState(() {
            _isAuthenticated = true;
          });
          _bootstrapFcm();
          _bootstrapWsNotifications();
        },
      );
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final isDesktopTabs = isDesktop && widget.apiService.desktopTabsEnabled;

    final mainIndexedStack = ObsidianAnimatedIndexedStack(
      key: const ValueKey('obsidian_main_indexed_stack'),
      index: _currentIndex,
      children: _buildScreens(screenIndex: _currentIndex, isTabActive: true),
    );

    final Map<ShortcutActivator, VoidCallback> shortcutBindings = isDesktopTabs
        ? <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => _openNewTab(0),
            const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeTab(_activeTabId),
            const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _cycleTab(true),
            const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () => _cycleTab(false),
            const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _switchToTabNumber(1),
            const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _switchToTabNumber(2),
            const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _switchToTabNumber(3),
            const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _switchToTabNumber(4),
            const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _switchToTabNumber(5),
            const SingleActivator(LogicalKeyboardKey.digit6, control: true): () => _switchToTabNumber(6),
            const SingleActivator(LogicalKeyboardKey.digit7, control: true): () => _switchToTabNumber(7),
            const SingleActivator(LogicalKeyboardKey.digit8, control: true): () => _switchToTabNumber(8),
            const SingleActivator(LogicalKeyboardKey.digit9, control: true): _switchToLastTab,
            const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): () {
              final next = widget.apiService.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
              widget.apiService.setThemeMode(next);
            },
            const SingleActivator(LogicalKeyboardKey.keyQ, control: true): _openQrScanner,
          }
        : <ShortcutActivator, VoidCallback>{
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
          };

    return CallbackShortcuts(
      bindings: shortcutBindings,
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
            extendBodyBehindAppBar: !isDesktop,
            extendBody: !isDesktop,
            appBar: isDesktop
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(90.0),
                    child: AnimatedOpacity(
                      opacity: _isBarsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: !_isBarsVisible,
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
                  ),
            drawer: isDesktop
                ? null
                : ObsidianNavigationDrawer(
                    apiService: widget.apiService,
                    currentIndex: _currentIndex,
                    onSelectScreen: _navigateScreen,
                    onOpenQrScanner: _openQrScanner,
                    onLogout: _handleLogout,
                  ),
            body: isDesktop
                ? (isDesktopTabs
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ObsidianDesktopSidebar(
                            apiService: widget.apiService,
                            currentIndex: _activeScreenIndex,
                            onSelectScreen: _navigateScreen,
                            onOpenQrScanner: _openQrScanner,
                            onLogout: _handleLogout,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ObsidianDesktopTabBar(
                                  tabs: _desktopTabs,
                                  activeTabId: _activeTabId,
                                  onSelectTab: _switchTab,
                                  onCloseTab: _closeTab,
                                  onNewTab: () => _openNewTab(0),
                                  onDuplicateTab: _duplicateTab,
                                  onCloseOtherTabs: _closeOtherTabs,
                                  apiService: widget.apiService,
                                  isOnline: _isOnline,
                                  onOpenQrScanner: _openQrScanner,
                                  getScreenTitle: _getScreenDisplayName,
                                  getScreenIcon: _getScreenIcon,
                                ),
                                ObsidianBannerWidget(
                                  apiService: widget.apiService,
                                  isBarsVisible: true,
                                ),
                                Expanded(
                                  child: _buildDesktopTabbedContent(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
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
                                  child: mainIndexedStack,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ))
                : Center(
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
                            child: mainIndexedStack,
                          ),
                        ],
                      ),
                    ),
                  ),
            bottomNavigationBar: isDesktop
                ? null
                : AnimatedOpacity(
                    opacity: _isBarsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_isBarsVisible,
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
          ),
        ),
      ),
    );
  }

  Widget _buildLaunchLockScreen() {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/obsidian-512.png',
                      width: 80.0,
                      height: 80.0,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.shield_outlined,
                        size: 80.0,
                        color: ObsidianUITheme.primaryAccent,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Text(
                      context.tr('app.title'),
                      style: TextStyle(
                        fontSize: 32.0,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      'ObsidianScout is Locked',
                      style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: secondaryTextColor),
                    ),
                    const SizedBox(height: 32.0),
                    ObsidianGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.fingerprint_rounded,
                                size: 48.0,
                                color: ObsidianUITheme.primaryAccent,
                              ),
                            ),
                            const SizedBox(height: 16.0),
                            Text(
                              'Passkey Authentication Required',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8.0),
                            Text(
                              'Scan your biometric or passkey to unlock the application.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.0,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 24.0),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ObsidianUITheme.primaryAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ),
                                onPressed: _isUnlocking ? null : _triggerLaunchBiometricUnlock,
                                icon: _isUnlocking
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.lock_open_rounded, color: Colors.white),
                                label: Text(
                                  _isUnlocking ? 'Unlocking...' : 'Unlock with Passkey',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15.0,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12.0),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isLaunchLocked = false;
                                    _isAuthenticated = false;
                                  });
                                },
                                icon: Icon(Icons.password_rounded, color: primaryTextColor),
                                label: Text(
                                  'Use Password Instead',
                                  style: TextStyle(
                                    color: primaryTextColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.0,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

