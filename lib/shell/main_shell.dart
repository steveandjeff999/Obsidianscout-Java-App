import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/desktop_tab_model.dart';
import '../screens/login_screen.dart';
import '../screens/match_list_screen.dart';
import '../screens/qr_scanner_screen.dart';
import '../screens/team_details_screen.dart';
import '../services/account_manager_service.dart';
import '../services/api_service.dart';
import '../services/app_update_service.dart';
import '../services/auth_storage_service.dart';
import '../services/battery_tracker_sync.dart';
import '../services/biometric_auth_service.dart';
import '../services/fcm_helper.dart';
import '../services/home_widget_service.dart';
import '../services/match_checklist_sync.dart';
import '../services/notification_websocket_service.dart';
import '../theme/obsidian_page_transitions.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/slack_banner_overlay.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/obsidian_account_switcher.dart';
import '../widgets/obsidian_banner_widget.dart';
import '../widgets/obsidian_bottom_nav.dart';
import '../widgets/obsidian_desktop_app_bar.dart';
import '../widgets/obsidian_desktop_sidebar.dart';
import '../widgets/obsidian_desktop_tab_bar.dart';
import '../widgets/obsidian_drawer.dart';
import '../widgets/obsidian_glass_app_bar.dart';
import 'launch_lock_screen.dart';
import 'shell_screen_registry.dart';

class MainShell extends StatefulWidget {
  final ApiService apiService;

  const MainShell({super.key, required this.apiService});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
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

  MatchScoutParams? _pendingMatchParams;
  PitScoutParams? _pendingPitParams;
  QualScoutParams? _pendingQualParams;

  void _navigateToMatchScout({
    String? matchKey,
    int? matchNumber,
    int? targetTeamNumber,
    String? sourceAssignmentId,
  }) {
    setState(() {
      _pendingMatchParams = MatchScoutParams(
        matchKey: matchKey,
        matchNumber: matchNumber,
        targetTeamNumber: targetTeamNumber,
        sourceAssignmentId: sourceAssignmentId,
      );
    });
    _navigateScreen(1);
  }

  void _navigateToPitScout({
    int? targetTeamNumber,
    String? sourceAssignmentId,
  }) {
    setState(() {
      _pendingPitParams = PitScoutParams(
        targetTeamNumber: targetTeamNumber,
        sourceAssignmentId: sourceAssignmentId,
      );
    });
    _navigateScreen(2);
  }

  void _navigateToQualScout({
    String? matchKey,
    int? matchNumber,
    String? allianceColor,
    int? targetTeamNumber,
    String? sourceAssignmentId,
  }) {
    setState(() {
      _pendingQualParams = QualScoutParams(
        matchKey: matchKey,
        matchNumber: matchNumber,
        allianceColor: allianceColor,
        targetTeamNumber: targetTeamNumber,
        sourceAssignmentId: sourceAssignmentId,
      );
    });
    _navigateScreen(3);
  }

  GlobalKey<NavigatorState> _getTabNavigatorKey(String tabId) {
    return _tabNavigatorKeys.putIfAbsent(tabId, () => GlobalKey<NavigatorState>());
  }

  DesktopTab get _activeTab => _desktopTabs.firstWhere(
        (t) => t.id == _activeTabId,
        orElse: () => _desktopTabs.isNotEmpty ? _desktopTabs.first : DesktopTab(id: 'tab_0', screenIndex: 0),
      );

  int get _activeScreenIndex => _activeTab.screenIndex;

  /// Screens that keep the display awake (match, pit, qual scout and prescouting).
  static const Set<int> _keepAwakeScreenIndices = {1, 2, 3, 11};

  /// Ctrl+K bumps this so the desktop sidebar focuses its page search.
  final ValueNotifier<int> _sidebarSearchRequests = ValueNotifier<int>(0);

  /// Ctrl+K: focus the sidebar search on desktop, open the drawer (which has the search box) on mobile.
  void _openPageSearch() {
    if (ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode)) {
      _sidebarSearchRequests.value++;
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }
  bool _wakelockEnabled = false;

  /// Keeps the screen on while a scouting screen is the visible page, so the phone
  /// doesn't dim or lock mid-match. Only calls the plugin when the wanted state changes.
  void _syncScoutingWakelock() {
    final isDesktopTabs = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode) &&
        widget.apiService.desktopTabsEnabled;
    final visibleIndex = isDesktopTabs ? _activeScreenIndex : _currentIndex;
    final shouldEnable = widget.apiService.keepScreenOnWhileScouting &&
        _isAuthenticated &&
        !_isLaunchLocked &&
        !_isAddingAccount &&
        _keepAwakeScreenIndices.contains(visibleIndex);
    if (shouldEnable == _wakelockEnabled) return;
    _wakelockEnabled = shouldEnable;
    WakelockPlus.toggle(enable: shouldEnable).catchError((Object e) {
      debugPrint('[MainShell] Wakelock toggle failed: $e');
    });
  }

  void _onKeepScreenOnChanged() {
    if (mounted) setState(() {});
  }

  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<int>? _serverErrorSub;
  StreamSubscription<String>? _sessionRevokedSub;
  StreamSubscription<WidgetLaunch>? _widgetLaunchSub;

  /// A home-screen widget tap waiting for sign-in or unlock.
  WidgetLaunch? _pendingWidgetLaunch;

  String? _pendingChatChannel;
  NotificationWebSocketService? _wsNotificationService;
  bool _isBarsVisible = true;

  bool _isCheckingLaunchLock = true;
  bool _isLaunchLocked = false;
  bool _isUnlocking = false;

  /// Bumped when the signed-in account changes so every page is rebuilt for the new account.
  int _accountGeneration = 0;
  /// Showing the login screen to add (or sign back in to) another account.
  bool _isAddingAccount = false;
  SavedAccount? _addAccountPrefill;
  bool _isSwitchingAccount = false;

  void _openNewTab([int initialIndex = 0]) {
    final pageId = ShellScreenRegistry.getPageIdForIndex(initialIndex);
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
    _checkForAppUpdate();

    widget.apiService.permissionsNotifier.addListener(_onPermissionsChanged);
    widget.apiService.keepScreenOnWhileScoutingNotifier.addListener(_onKeepScreenOnChanged);

    WidgetsBinding.instance.addObserver(this);
    _pendingWidgetLaunch = HomeWidgetService.instance.takeInitialLaunch();
    _widgetLaunchSub = HomeWidgetService.instance.launches.listen((launch) {
      if (!mounted) return;
      setState(() => _pendingWidgetLaunch = launch);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leave the home-screen widgets current when the user goes back to the home screen.
    if (state == AppLifecycleState.paused) HomeWidgetService.instance.requestRefresh();
  }

  /// Team details for a Rankings widget row, from the event's cached team list.
  Future<void> _openTeamDetails(int teamNumber) async {
    final api = widget.apiService;
    final eventKey = api.currentSettings?.eventKey ?? await api.getCachedEventKey();
    final teams = await api.getCachedTeams(eventKey);
    final team = teams.where((t) => t.teamNumber == teamNumber).firstOrNull;
    if (team == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => TeamDetailsScreen(team: team, apiService: api, eventKey: eventKey)),
    );
  }

  /// Opens what a tapped home-screen widget points at, once the user is signed in and unlocked.
  /// Page access is checked by [_navigateScreen] / [_openQrScanner] like any other navigation.
  void _openWidgetLaunch(WidgetLaunch launch) {
    final p = launch.params;
    int? indexOf(String pageId) {
      for (var i = 0; i < ShellScreenRegistry.screenCount; i++) {
        if (ShellScreenRegistry.getPageIdForIndex(i) == pageId) return i;
      }
      return null;
    }

    switch (launch.action) {
      case 'page':
        final pageId = p['page'] ?? '';
        final group = p['group']?.trim();
        if (pageId == 'chat' && group != null && group.isNotEmpty) {
          setState(() {
            _pendingChatChannel = group;
            _activeTab.pendingChatChannel = group;
          });
        }
        // Row taps: Match Schedule opens just that match, Rankings opens that team's details.
        final matchKey = p['matchKey']?.trim();
        if (pageId == 'matches' && matchKey != null && matchKey.isNotEmpty && widget.apiService.hasPageAccess('matches')) {
          MatchListScreen.focusRequest.value = matchKey;
        }
        final index = indexOf(pageId);
        if (index != null) _navigateScreen(index);
        final team = int.tryParse(p['team'] ?? '');
        if (team != null && widget.apiService.hasPageAccess(pageId)) unawaited(_openTeamDetails(team));
      case 'chat':
        final group = p['group']?.trim();
        if (group != null && group.isNotEmpty) {
          setState(() {
            _pendingChatChannel = group;
            _activeTab.pendingChatChannel = group;
          });
        }
        final index = indexOf('chat');
        if (index != null) _navigateScreen(index);
      case 'scout':
        final number = int.tryParse(p['number'] ?? '');
        final team = int.tryParse(p['team'] ?? '');
        switch ((p['type'] ?? 'MATCH').toUpperCase()) {
          case 'PIT':
            _navigateToPitScout(targetTeamNumber: team, sourceAssignmentId: p['id']);
          case 'QUALITATIVE':
            _navigateToQualScout(
              matchKey: p['matchKey'],
              matchNumber: number,
              allianceColor: p['alliance'],
              targetTeamNumber: team,
              sourceAssignmentId: p['id'],
            );
          default:
            _navigateToMatchScout(matchKey: p['matchKey'], matchNumber: number, targetTeamNumber: team, sourceAssignmentId: p['id']);
        }
      case 'scan':
        _openQrScanner();
    }
  }

  /// Offers a newer GitHub release to installs that came from GitHub rather than a store.
  Future<void> _checkForAppUpdate() async {
    final update = await AppUpdateService.instance.checkOnLaunch();
    if (update == null) return;
    // Don't cover the unlock screen.
    while (mounted && (_isCheckingLaunchLock || _isLaunchLocked)) {
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    await AppUpdateDialog.show(context, update);
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
    // Match Checklist edits made offline save in the background, even before the screen is opened.
    if (widget.apiService.nonScoutingToolsEnabled) {
      unawaited(MatchChecklistSync.of(widget.apiService).resumeDrafts());
      unawaited(BatteryTrackerSync.of(widget.apiService).resumeDrafts());
    }
    for (final tab in _desktopTabs) {
      final pageId = ShellScreenRegistry.getPageIdForIndex(tab.screenIndex);
      if (!widget.apiService.hasPageAccess(pageId)) {
        tab.screenIndex = 0;
      }
    }
    final currentPageId = ShellScreenRegistry.getPageIdForIndex(_currentIndex);
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
      onSlackNotification: SlackBannerOverlay.show,
    )..connect();
  }

  @override
  void dispose() {
    widget.apiService.permissionsNotifier.removeListener(_onPermissionsChanged);
    widget.apiService.keepScreenOnWhileScoutingNotifier.removeListener(_onKeepScreenOnChanged);
    if (_wakelockEnabled) WakelockPlus.disable();
    _sidebarSearchRequests.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchSub?.cancel();
    _onlineSub?.cancel();
    _serverErrorSub?.cancel();
    _sessionRevokedSub?.cancel();
    _wsNotificationService?.dispose();
    super.dispose();
  }

  void _navigateScreen(int index) {
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final isDesktopTabs = isDesktop && widget.apiService.desktopTabsEnabled;

    if (isDesktopTabs) {
      if (_activeTab.screenIndex == index) return;
    } else {
      if (_currentIndex == index) return;
    }

    final pageId = ShellScreenRegistry.getPageIdForIndex(index);
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
        final pageId = ShellScreenRegistry.getPageIdForIndex(prevIndex);
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
        final pageId = ShellScreenRegistry.getPageIdForIndex(prevIndex);
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

  // ── Accounts ─────────────────────────────────────────────────────────────

  Future<void> _openAccountSwitcher() async {
    if (_isSwitchingAccount) return;
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) _scaffoldKey.currentState!.closeDrawer();
    final action = await showObsidianAccountSwitcher(
      context: context,
      apiService: widget.apiService,
      alignLeft: isDesktop,
    );
    if (action == null || !mounted) return;
    switch (action.type) {
      case AccountMenuActionType.switchTo:
        await _switchAccount(action.account!);
      case AccountMenuActionType.addAccount:
        await _startAddAccount();
      case AccountMenuActionType.signOut:
        await _signOutCurrentAccount();
      case AccountMenuActionType.signOutAll:
        await widget.apiService.removeOtherSavedAccounts(fcmToken: FcmHelper.currentFcmToken);
        await _handleLogout();
    }
  }

  void _showAccountMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFB91C1C) : ObsidianUITheme.getSurfaceColor(context),
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showUnsyncedChangesMessage(int pending) {
    _showAccountMessage(
      context.tr(
        'accounts.unsynced',
        '{count} unsynced change(s) must upload before you change accounts. Reconnect and try again.',
      ).replaceAll('{count}', '$pending'),
      isError: true,
    );
  }

  Future<void> _switchAccount(SavedAccount account) async {
    setState(() => _isSwitchingAccount = true);
    _wsNotificationService?.dispose();
    _wsNotificationService = null;
    final result = await widget.apiService.switchToAccount(account);
    if (!mounted) return;
    setState(() => _isSwitchingAccount = false);
    switch (result) {
      case AccountSwitchResult.switched:
        _onAccountChanged();
        _showAccountMessage(context.tr('accounts.switched', 'Switched to {name}').replaceAll('{name}', account.username));
      case AccountSwitchResult.needsSignIn:
        _bootstrapWsNotifications();
        await _startAddAccount(prefill: account);
      case AccountSwitchResult.unsyncedChanges:
        _bootstrapWsNotifications();
        _showUnsyncedChangesMessage(widget.apiService.outboxCount.value);
    }
  }

  Future<void> _startAddAccount({SavedAccount? prefill}) async {
    final pending = await widget.apiService.beginAddAccount();
    if (!mounted) return;
    if (pending > 0) {
      _showUnsyncedChangesMessage(pending);
      return;
    }
    _wsNotificationService?.dispose();
    _wsNotificationService = null;
    setState(() {
      _isAddingAccount = true;
      _addAccountPrefill = prefill;
    });
  }

  Future<void> _cancelAddAccount() async {
    await widget.apiService.cancelAddAccount();
    if (!mounted) return;
    setState(() {
      _isAddingAccount = false;
      _addAccountPrefill = null;
    });
    _bootstrapWsNotifications();
  }

  /// Signs out of the current account and moves to the next signed-in one, if any.
  Future<void> _signOutCurrentAccount() async {
    final next = widget.apiService.otherSavedAccounts.where(widget.apiService.hasActiveSession).firstOrNull;
    await _handleLogout();
    if (next == null || !mounted) return;
    final result = await widget.apiService.switchToAccount(next);
    if (!mounted || result != AccountSwitchResult.switched) return;
    setState(() => _isAuthenticated = true);
    _onAccountChanged();
  }

  /// A different account is now signed in: start its pages, tabs and notifications fresh.
  void _onAccountChanged() {
    _wsNotificationService?.dispose();
    _wsNotificationService = null;
    setState(() {
      _isAddingAccount = false;
      _addAccountPrefill = null;
      _accountGeneration++;
      _currentIndex = 0;
      _screenHistory.clear();
      _pendingChatChannel = null;
      _pendingMatchParams = null;
      _pendingPitParams = null;
      _pendingQualParams = null;
      _desktopTabs
        ..clear()
        ..add(DesktopTab(id: 'tab_${_tabCounter++}', screenIndex: 0));
      _activeTabId = _desktopTabs.first.id;
      _tabNavigatorKeys.clear();
    });
    _bootstrapFcm();
    _bootstrapWsNotifications();
    HomeWidgetService.instance.requestRefresh();
  }

  Widget _buildScreenByIndex(int screenIndex, {required bool isTabActive, String? chatChannel}) {
    return ShellScreenRegistry.buildScreenByIndex(
      screenIndex: screenIndex,
      apiService: widget.apiService,
      isTabActive: isTabActive,
      currentIndex: _currentIndex,
      isBarsVisible: _isBarsVisible,
      chatChannel: chatChannel,
      pendingChatChannel: _pendingChatChannel,
      pendingMatchParams: _pendingMatchParams,
      pendingPitParams: _pendingPitParams,
      pendingQualParams: _pendingQualParams,
      onNavigateScreen: _navigateScreen,
      onOpenQrScanner: _openQrScanner,
      onLogout: _handleLogout,
      onNavigateToMatchScout: _navigateToMatchScout,
      onNavigateToPitScout: _navigateToPitScout,
      onNavigateToQualScout: _navigateToQualScout,
    );
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
                  itemCount: ShellScreenRegistry.screenCount,
                  itemBuilder: (ctx, idx) => _buildScreenByIndex(
                    idx,
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
    _syncScoutingWakelock();

    if (_isCheckingLaunchLock) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SizedBox.shrink(),
      );
    }

    if (_isLaunchLocked) {
      return LaunchLockScreen(
        isUnlocking: _isUnlocking,
        onUnlock: _triggerLaunchBiometricUnlock,
        onUsePassword: () {
          setState(() {
            _isLaunchLocked = false;
            _isAuthenticated = false;
          });
        },
        onBackPress: _handleBackPress,
      );
    }

    if (_isAddingAccount) {
      return LoginScreen(
        key: ValueKey('add_account_${_addAccountPrefill?.id ?? 'new'}'),
        apiService: widget.apiService,
        addAccountMode: true,
        prefillAccount: _addAccountPrefill,
        onCancel: _cancelAddAccount,
        onLoginSuccess: () {
          setState(() => _isAuthenticated = true);
          _onAccountChanged();
        },
      );
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
          HomeWidgetService.instance.requestRefresh();
        },
      );
    }

    final widgetLaunch = _pendingWidgetLaunch;
    if (widgetLaunch != null) {
      _pendingWidgetLaunch = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openWidgetLaunch(widgetLaunch);
      });
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final isDesktopTabs = isDesktop && widget.apiService.desktopTabsEnabled;

    final mainIndexedStack = ObsidianAnimatedIndexedStack(
      key: const ValueKey('obsidian_main_indexed_stack'),
      index: _currentIndex,
      itemCount: ShellScreenRegistry.screenCount,
      itemBuilder: (ctx, idx) => _buildScreenByIndex(
        idx,
        isTabActive: true,
      ),
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
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openPageSearch,
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
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openPageSearch,
          };

    final shell = CallbackShortcuts(
      bindings: shortcutBindings,
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBackPress();
          },
          child: Container(
            decoration: ObsidianUITheme.getBackgroundDecoration(context),
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: Colors.transparent,
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
                              title: context.tr(ShellScreenRegistry.getTitleKey(_currentIndex)),
                              subtitle: context.tr(ShellScreenRegistry.getSubtitleKey(_currentIndex)),
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
                      onOpenAccounts: _openAccountSwitcher,
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
                              onOpenAccounts: _openAccountSwitcher,
                              searchRequests: _sidebarSearchRequests,
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
                                    getScreenTitle: (idx) => ShellScreenRegistry.getScreenDisplayName(context, idx),
                                    getScreenIcon: ShellScreenRegistry.getScreenIcon,
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
                              onOpenAccounts: _openAccountSwitcher,
                              searchRequests: _sidebarSearchRequests,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ObsidianDesktopAppBar(
                                    title: context.tr(ShellScreenRegistry.getTitleKey(_currentIndex)),
                                    subtitle: context.tr(ShellScreenRegistry.getSubtitleKey(_currentIndex)),
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
      ),
    );

    // Keyed by account so a switch rebuilds every page with the new account's data.
    return KeyedSubtree(
      key: ValueKey('account_$_accountGeneration'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          shell,
          if (_isSwitchingAccount)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
