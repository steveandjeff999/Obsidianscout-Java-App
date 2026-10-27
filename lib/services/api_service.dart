import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'net/net_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_response.dart';
import '../models/cluster_models.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../models/chat_models.dart';
import '../models/validation_models.dart';
import '../models/custom_analytics_models.dart';
import '../models/predictor_models.dart';
import '../models/error_report_models.dart';
import '../models/assignment_models.dart';
import '../models/graph_models.dart';
import '../models/match_planning_models.dart';
import '../models/gamepad_models.dart';
import '../models/share_models.dart';
import '../models/pick_list_models.dart';
import '../models/match_pick_models.dart';
import '../theme/obsidian_ui_theme.dart';
import '../data/local_store.dart';
import 'auth_storage_service.dart';
import 'entry_sync.dart' as entry_sync;
import 'local_analytics.dart' as local_analytics;
import 'net/link_quality.dart';
import 'scout_history_service.dart';

class ApiService {
  static const String keyServerUrl = "obsidianscout_server_url";
  static const String keySessionCookie = "obsidianscout_session_cookie";
  static const String keyKeepMeLoggedIn = "obsidianscout_keep_me_logged_in";
  static const String keySavedUsername = "obsidianscout_saved_username";
  static const String keyThemeMode = "obsidianscout_theme_mode";
  static const String keyUseServerCustomTheme = "obsidianscout_use_server_custom_theme";
  static const String keyUiMode = "obsidianscout_ui_mode";
  static const String keyDesktopTabs = "obsidianscout_desktop_tabs_enabled";
  static const String keyLocale = "obsidianscout_locale";
  static const String keyRequestTimeoutSeconds = "obsidianscout_request_timeout_seconds";
  static const String keyDeviceId = "obsidianscout_device_id";
  static const int defaultRequestTimeoutSeconds = 6;
  static const String defaultUrl = "https://kotlin.obsidianscout.com";

  String _currentServerUrl = defaultUrl;
  String? _sessionCookie;
  String? _deviceId;
  int _authEpoch = 0;
  bool _keepMeLoggedIn = false;
  String _savedUsername = '';
  int _requestTimeoutSeconds = defaultRequestTimeoutSeconds;
  Timer? _syncTimer;

  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  bool isCacheFresh(String key, {Duration maxAge = const Duration(seconds: 30)}) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < maxAge;
  }

  void markCacheFresh(String key) {
    _cacheTimestamps[key] = DateTime.now();
  }

  T? getFromMemoryCache<T>(String key) {
    final val = _memoryCache[key];
    if (val is T) return val;
    return null;
  }

  void setMemoryCache<T>(String key, T value) {
    _memoryCache[key] = value;
    markCacheFresh(key);
  }

  void invalidateMemoryCache([String? prefix]) {
    if (prefix == null) {
      _memoryCache.clear();
      _cacheTimestamps.clear();
    } else {
      _memoryCache.removeWhere((k, _) => k.startsWith(prefix));
      _cacheTimestamps.removeWhere((k, _) => k.startsWith(prefix));
    }
  }

  UserModel? _currentUser;
  AppSettingsModel? _currentSettings;
  final ValueNotifier<int> permissionsNotifier = ValueNotifier<int>(0);
  /// Bumped after each background sync and whenever the user saves something that changes what the
  /// home-screen widgets show (a scouting entry, an assignment status), so they refresh right away.
  final ValueNotifier<int> dataSyncedNotifier = ValueNotifier<int>(0);
  /// Fires whenever [_currentSettings] is updated from the server.
  /// Use this to reactively refresh UI that depends on [currentSettings].
  final ValueNotifier<AppSettingsModel?> settingsNotifier = ValueNotifier<AppSettingsModel?>(null);

  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  final ValueNotifier<bool> useServerCustomThemeNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<ThemePresetModel?> customThemeNotifier = ValueNotifier<ThemePresetModel?>(null);
  final ValueNotifier<String> uiModeNotifier = ValueNotifier<String>('auto'); // 'auto', 'mobile', 'desktop'
  final ValueNotifier<bool> desktopTabsNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(const Locale('en'));
  final ValueNotifier<int> timeoutNotifier = ValueNotifier<int>(defaultRequestTimeoutSeconds);

  bool _isOnline = true;
  bool _handlingRevocation = false;
  Timer? _healthCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final StreamController<bool> _onlineStreamController = StreamController<bool>.broadcast();
  final StreamController<int> _serverErrorController = StreamController<int>.broadcast();
  final StreamController<String> _sessionRevokedController = StreamController<String>.broadcast();

  String get serverUrl => _currentServerUrl;
  String get currentServerUrl => _currentServerUrl;
  bool get isLoggedIn => _sessionCookie != null && _sessionCookie!.isNotEmpty;
  bool get keepMeLoggedIn => _keepMeLoggedIn;
  String get savedUsername => _savedUsername;
  UserModel? get currentUser => _currentUser;
  String? _sessionPassword;
  String? get sessionPassword => _sessionPassword;

  @visibleForTesting
  void setSessionPasswordForTesting(String? password) {
    _sessionPassword = password;
  }

  @visibleForTesting
  void setSessionCookieForTesting(String? cookie) {
    _sessionCookie = cookie;
  }

  /// Returns the account username if authenticated, else null
  String? get currentAccountUsername {
    if (!isLoggedIn) return null;
    if (_currentUser != null && _currentUser!.username.isNotEmpty) {
      return _currentUser!.username;
    }
    if (_savedUsername.isNotEmpty) {
      return _savedUsername;
    }
    return null;
  }

  /// Returns the account ID if authenticated, else null
  String? get currentAccountId {
    if (!isLoggedIn) return null;
    return _currentUser?.id;
  }
  AppSettingsModel? get currentSettings => _currentSettings;
  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? (currentUserRole.toUpperCase() == 'SUPERADMIN');
  bool get isAdmin => _currentUser?.isAdmin ?? (currentUserRole.toUpperCase() == 'ADMIN' || isSuperAdmin);
  String get currentUserRole => _currentUser?.role ?? 'SCOUT';
  String get currentProgram => _currentUser?.program ?? _currentSettings?.program ?? 'FRC';
  bool get isOnline => _isOnline;
  Stream<bool> get onOnlineStatusChanged => _onlineStreamController.stream;
  Stream<int> get onServerError => _serverErrorController.stream;
  Stream<String> get onSessionRevoked => _sessionRevokedController.stream;
  ThemeMode get themeMode => themeNotifier.value;
  bool get useServerCustomTheme => useServerCustomThemeNotifier.value;
  ThemePresetModel? get currentCustomTheme => customThemeNotifier.value;
  String get uiMode => uiModeNotifier.value;
  bool get desktopTabsEnabled => desktopTabsNotifier.value;
  Locale get currentLocale => localeNotifier.value;
  int get requestTimeoutSeconds => _requestTimeoutSeconds;
  Duration get requestTimeout => Duration(seconds: _requestTimeoutSeconds);
  Duration get heavyRequestTimeout => Duration(seconds: (_requestTimeoutSeconds * 2).clamp(8, 60));

  Future<void> setThemeMode(ThemeMode mode) async {
    themeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyThemeMode, mode.name);
  }

  Future<void> setUseServerCustomTheme(bool enabled) async {
    useServerCustomThemeNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyUseServerCustomTheme, enabled);
    _syncObsidianTheme();
  }

  void _syncObsidianTheme() {
    if (_currentSettings != null) {
      ThemePresetModel? active;
      if (_currentSettings!.theme != null) {
        active = _currentSettings!.theme;
      } else if (_currentSettings!.themes.isNotEmpty) {
        active = _currentSettings!.themes.firstWhere(
          (t) => t.name == _currentSettings!.activeThemeName,
          orElse: () => _currentSettings!.themes.first,
        );
      }
      customThemeNotifier.value = active;
      ObsidianUITheme.setCustomTheme(active, enabled: useServerCustomThemeNotifier.value);
    } else {
      customThemeNotifier.value = null;
      ObsidianUITheme.setCustomTheme(null, enabled: useServerCustomThemeNotifier.value);
    }
  }

  Future<void> setUiMode(String mode) async {
    uiModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUiMode, mode);
  }

  Future<void> setDesktopTabsEnabled(bool enabled) async {
    desktopTabsNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyDesktopTabs, enabled);
  }

  Future<void> setLocale(Locale locale) async {
    localeNotifier.value = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLocale, locale.languageCode);
  }

  Future<void> setRequestTimeoutSeconds(int seconds) async {
    _requestTimeoutSeconds = seconds.clamp(2, 60);
    timeoutNotifier.value = _requestTimeoutSeconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyRequestTimeoutSeconds, _requestTimeoutSeconds);
  }

  @visibleForTesting
  void setCachedUserForTesting(UserModel? user) {
    _currentUser = user;
    permissionsNotifier.value++;
  }

  @visibleForTesting
  void setCachedSettingsForTesting(AppSettingsModel? settings) {
    _currentSettings = settings;
    _syncObsidianTheme();
    permissionsNotifier.value++;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentServerUrl = prefs.getString(keyServerUrl) ?? defaultUrl;
    _keepMeLoggedIn = prefs.getBool(keyKeepMeLoggedIn) ?? false;
    _savedUsername = prefs.getString(keySavedUsername) ?? '';

    _deviceId = prefs.getString(keyDeviceId);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateUuidV4();
      await prefs.setString(keyDeviceId, _deviceId!);
    }

    final savedThemeStr = prefs.getString(keyThemeMode) ?? 'dark';
    if (savedThemeStr == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedThemeStr == 'system') {
      themeNotifier.value = ThemeMode.system;
    } else {
      themeNotifier.value = ThemeMode.dark;
    }

    final savedLocaleStr = prefs.getString(keyLocale);
    if (savedLocaleStr != null && ['en', 'es', 'he', 'tr'].contains(savedLocaleStr)) {
      localeNotifier.value = Locale(savedLocaleStr);
    } else {
      localeNotifier.value = const Locale('en');
    }

    final savedUseServerCustomTheme = prefs.getBool(keyUseServerCustomTheme) ?? true;
    useServerCustomThemeNotifier.value = savedUseServerCustomTheme;

    final savedUiMode = prefs.getString(keyUiMode) ?? 'auto';
    uiModeNotifier.value = savedUiMode;

    final savedDesktopTabs = prefs.getBool(keyDesktopTabs) ?? true;
    desktopTabsNotifier.value = savedDesktopTabs;

    _requestTimeoutSeconds = prefs.getInt(keyRequestTimeoutSeconds) ?? defaultRequestTimeoutSeconds;
    timeoutNotifier.value = _requestTimeoutSeconds;

    // Restore cached user and settings
    final cachedUser = await _getCache("cache_auth_me");
    if (cachedUser != null && cachedUser.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cachedUser);
        final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : jsonMap;
        _currentUser = UserModel.fromJson(userObj);
      } catch (_) {}
    }

    final cachedSettings = await _getCache("cache_settings");
    if (cachedSettings != null && cachedSettings.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cachedSettings);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
      } catch (_) {}
    }
    _syncObsidianTheme();
    permissionsNotifier.value++;

    _configureNetwork();
    await LinkQuality.instance.load();
    _initConnectivityMonitor();

    ScoutHistoryService.currentAccountProvider = () => currentAccountUsername;
    ScoutHistoryService.currentAccountIdProvider = () => currentAccountId;
    unawaited(ScoutHistoryService.purgeExpiredEntries());

    if (_keepMeLoggedIn) {
      final savedCookie = prefs.getString(keySessionCookie);
      if (savedCookie != null && savedCookie.isNotEmpty) {
        _sessionCookie = savedCookie;
        // Non-blocking verification in background: allows immediate UI mount without startup freezing
        unawaited(_verifySessionAsync(prefs));
      }
    }

    if (isLoggedIn) {
      unawaited(fetchCurrentUser());
      unawaited(fetchSettings());
    }

    _startBackgroundSync();
  }

  /// Request timeout, ETag storage and slow-link handling for every request this service makes.
  void _configureNetwork() {
    final net = http.NetClient.instance;
    net.connectTimeout = () => requestTimeout;
    net.readEtag = (url) async {
      final raw = await _getCache('cache_etag:$url');
      if (raw == null || raw.isEmpty) return null;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return (etag: decoded['etag'] as String, body: decoded['body'] as String);
      } catch (_) {
        return null;
      }
    };
    net.writeEtag = (url, record) => _setCache('cache_etag:$url', jsonEncode({'etag': record.etag, 'body': record.body}));
    // Going slow or fast changes how often the background sync runs.
    LinkQuality.instance.lowBandwidth.removeListener(_onLinkQualityChanged);
    LinkQuality.instance.lowBandwidth.addListener(_onLinkQualityChanged);
  }

  void _onLinkQualityChanged() {
    if (isLoggedIn) _startBackgroundSync();
  }

  Future<void> _verifySessionAsync(SharedPreferences prefs) async {
    try {
      final isValid = await _verifySession();
      if (!isValid && _keepMeLoggedIn) {
        _sessionCookie = null;
        await prefs.remove(keySessionCookie);
        _sessionRevokedController.add('Session expired or invalidated.');
      }
    } catch (_) {}
  }

  bool _isSyncing = false;

  void _initConnectivityMonitor() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _updateOnlineState(false);
      } else {
        checkServerHealth();
      }
    });

    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      checkServerHealth();
    });
    checkServerHealth();
  }

  /// Consecutive failed health checks. One lost probe on a congested event network doesn't mean the server is gone,
  /// so an online device goes offline only after the quick re-check fails too.
  int _healthFailures = 0;
  Timer? _healthRecheckTimer;

  Future<bool> checkServerHealth() async {
    var online = false;
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/auth/status'), headers: _headers);
      online = response.statusCode == 200 || response.statusCode == 401;
    } catch (_) {}
    if (online) {
      _healthFailures = 0;
      _healthRecheckTimer?.cancel();
      _updateOnlineState(true);
      return true;
    }
    _healthFailures++;
    if (_isOnline && _healthFailures < 2) {
      _healthRecheckTimer?.cancel();
      _healthRecheckTimer = Timer(const Duration(seconds: 5), checkServerHealth);
      return false;
    }
    _updateOnlineState(false);
    return false;
  }

  void _updateOnlineState(bool newState) {
    if (_isOnline != newState) {
      _isOnline = newState;
      _onlineStreamController.add(_isOnline);
      if (_isOnline) {
        // The outbox goes first, ahead of the full refresh's user/settings fetches.
        if (outboxCount.value > 0) _scheduleOutboxRetry(soon: true);
        flushPendingMatchPicks();
        syncAllServerDataInBackground();
      }
    }
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    // Stagger initial sync to allow UI mounting to complete first
    Timer(const Duration(seconds: 2), () {
      if (isLoggedIn && _isOnline) {
        syncAllServerDataInBackground();
      }
    });
    if (outboxCount.value > 0) _scheduleOutboxRetry();
    final interval = LinkQuality.instance.isLowBandwidth ? lowBandwidthSyncInterval : normalSyncInterval;
    _syncTimer = Timer.periodic(interval, (_) {
      syncAllServerDataInBackground();
    });
  }

  static const Duration normalSyncInterval = Duration(seconds: 120);

  /// Outer deadline for a request whose caller wants a bound on top of NetClient's own (which only fails a request
  /// once it stops making progress): [normal] on a good link, and on a slow one long enough for a fresh connection
  /// (several 1-3 s round trips) plus the transfer.
  static Duration _deadline(Duration normal) {
    if (!LinkQuality.instance.isLowBandwidth) return normal;
    final slow = normal * 5;
    return slow < const Duration(seconds: 60) ? const Duration(seconds: 60) : slow;
  }
  static const Duration lowBandwidthSyncInterval = Duration(minutes: 10);

  /// On a slow link, configs, the team list, banners and the field image info are checked this often instead of
  /// every cycle. On a normal link they're checked every cycle; the ETag makes an unchanged one a tiny 304.
  static const Duration lowBandwidthStaticInterval = Duration(minutes: 30);
  DateTime? _lastStaticRefresh;

  bool get _staticRefreshDue =>
      !LinkQuality.instance.isLowBandwidth ||
      _lastStaticRefresh == null ||
      DateTime.now().difference(_lastStaticRefresh!) > lowBandwidthStaticInterval;

  Future<void> syncAllServerDataInBackground() async {
    if (!isLoggedIn || !_isOnline || _isSyncing) return;
    _isSyncing = true;
    try {
      await Future.wait([
        fetchCurrentUser().catchError((_) => null),
        fetchSettings().catchError((_) => null),
      ]);
      await syncOutbox().catchError((_) => 0);
      final eventKey = _currentSettings?.eventKey;
      final lowBandwidth = LinkQuality.instance.isLowBandwidth;
      final refreshStatic = _staticRefreshDue;
      // The request scheduler already orders these (assignments and the schedule first, bulk last) and, on a
      // slow link, runs bulk downloads one at a time.
      await Future.wait([
        if (refreshStatic) fetchMatchConfig().catchError((_) => null),
        if (refreshStatic) fetchPitConfig().catchError((_) => null),
        if (refreshStatic) fetchQualConfig().catchError((_) => null),
        if (refreshStatic) fetchTeams(eventKey).catchError((_) => <TeamModel>[]),
        fetchMatches(eventKey).catchError((_) => <MatchModel>[]),
        if (refreshStatic) fetchBanners().catchError((_) => <Map<String, dynamic>>[]),
        fetchMyAssignments(eventKey).catchError((_) => <ScoutingAssignment>[]),
        if (isAdmin) fetchAllAssignments(eventKey).catchError((_) => <ScoutingAssignment>[]),
      ]);
      if (refreshStatic) _lastStaticRefresh = DateTime.now();
      // Secondary background data. Entries come through the delta sync; prescout lists are derived from them.
      await Future.wait([
        fetchScoutingEntries().catchError((_) => <dynamic>[]),
        fetchPrescoutScoutingEntries().catchError((_) => <dynamic>[]),
        fetchPrescoutPitScoutingEntries().catchError((_) => <dynamic>[]),
        fetchPrescoutQualScoutingEntries().catchError((_) => <dynamic>[]),
        // Computed on the device on a slow link instead of downloaded.
        if (!lowBandwidth) fetchAnalyticsWidgets().catchError((_) => <AnalyticsWidgetModel>[]),
        syncPendingMatchPlans().catchError((_) => 0),
        fetchFieldImageBytes(_currentSettings?.year ?? DateTime.now().year).catchError((_) => null),
      ]);
    } catch (_) {
    } finally {
      _isSyncing = false;
      dataSyncedNotifier.value++;
    }
  }

  /// Large cached responses live in [LocalStore] (SQLite on device), not SharedPreferences.
  final LocalStore _store = LocalStore.instance;

  Future<void> _setCache(String key, String rawJson) async {
    _memoryCache.remove(key);
    try {
      await _store.setString(key, rawJson);
    } catch (_) {}
  }

  Future<String?> _getCache(String key) async {
    try {
      return await _store.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Decodes a cached JSON string; large documents are decoded off the UI thread.
  Future<dynamic> _decodeCached(String raw) => LocalStore.decodeJson(raw);

  // Instant Stale-While-Revalidate Synchronous & Async Cache Accessors
  Future<String?> getCachedEventKey() async {
    if (_currentSettings != null && _currentSettings!.eventKey.isNotEmpty) {
      return _currentSettings!.eventKey;
    }
    final cachedSettings = await getCachedSettings();
    return cachedSettings?.eventKey;
  }

  Future<AppSettingsModel?> getCachedSettings() async {
    if (_currentSettings != null) return _currentSettings;
    final inMem = getFromMemoryCache<AppSettingsModel>("cache_settings");
    if (inMem != null) {
      _currentSettings = inMem;
      return inMem;
    }
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = await _decodeCached(cached);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        if (_currentSettings != null) {
          setMemoryCache("cache_settings", _currentSettings);
        }
        return _currentSettings;
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedMatchConfig() async {
    final inMem = getFromMemoryCache<ScoutingConfigModel>("cache_config");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        final config = ScoutingConfigModel.fromJson(await _decodeCached(cached));
        setMemoryCache("cache_config", config);
        return config;
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedPitConfig() async {
    final inMem = getFromMemoryCache<ScoutingConfigModel>("cache_pit_config");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_pit_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        final config = ScoutingConfigModel.fromJson(await _decodeCached(cached));
        setMemoryCache("cache_pit_config", config);
        return config;
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedQualConfig() async {
    final inMem = getFromMemoryCache<ScoutingConfigModel>("cache_qual_config");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_qual_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        final config = ScoutingConfigModel.fromJson(await _decodeCached(cached));
        setMemoryCache("cache_qual_config", config);
        return config;
      } catch (_) {}
    }
    return null;
  }

  Future<List<TeamModel>> getCachedTeams(String? eventKey) async {
    final memKey = "mem_teams_${eventKey ?? 'all'}";
    final inMem = getFromMemoryCache<List<TeamModel>>(memKey);
    if (inMem != null && inMem.isNotEmpty) return inMem;

    final candidateKeys = [
      if (eventKey != null && eventKey.isNotEmpty) "cache_teams_$eventKey",
      "cache_teams_all",
      "cache_teams_",
      "cache_teams_current",
    ];
    for (final key in candidateKeys) {
      final cached = await _getCache(key);
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = await _decodeCached(cached);
          final List list = decoded is List
              ? decoded
              : (decoded is Map && decoded['teams'] is List ? decoded['teams'] as List : []);
          if (list.isNotEmpty) {
            final Map<int, TeamModel> teamMap = {};
            for (var item in list) {
              final t = TeamModel.fromJson(item as Map<String, dynamic>);
              teamMap[t.teamNumber] = t;
            }
            if (teamMap.isNotEmpty) {
              final res = teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
              setMemoryCache(memKey, res);
              setMemoryCache("mem_teams_all", res);
              return res;
            }
          }
        } catch (_) {}
      }
    }
    return [];
  }

  Future<List<MatchModel>> getCachedMatches(String? eventKey) async {
    final memKey = "mem_matches_${eventKey ?? 'all'}";
    final inMem = getFromMemoryCache<List<MatchModel>>(memKey);
    if (inMem != null && inMem.isNotEmpty) return inMem;

    final candidateKeys = [
      if (eventKey != null && eventKey.isNotEmpty) "cache_matches_$eventKey",
      "cache_matches_all",
      "cache_matches_",
      "cache_matches_current",
    ];
    for (final key in candidateKeys) {
      final cached = await _getCache(key);
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = await _decodeCached(cached);
          final List list = decoded is List
              ? decoded
              : (decoded is Map && decoded['matches'] is List ? decoded['matches'] as List : []);
          if (list.isNotEmpty) {
            final Map<String, MatchModel> matchMap = {};
            for (var item in list) {
              final m = MatchModel.fromJson(item as Map<String, dynamic>);
              if (m.matchKey.isNotEmpty) {
                matchMap[m.matchKey] = m;
              }
            }
            if (matchMap.isNotEmpty) {
              final res = matchMap.values.toList()..sort(MatchModel.compareMatches);
              setMemoryCache(memKey, res);
              setMemoryCache("mem_matches_all", res);
              return res;
            }
          }
        } catch (_) {}
      }
    }
    return [];
  }

  Future<List<dynamic>> getCachedScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPitScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_pit_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_pit_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_pit_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedQualScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_qual_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_qual_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_qual_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_prescout_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_prescout_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_prescout_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutPitScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_prescout_pit_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_prescout_pit_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_prescout_pit_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutQualScoutingEntries() async {
    final inMem = getFromMemoryCache<List<dynamic>>("cache_prescout_qual_scouting");
    if (inMem != null) return inMem;
    final cached = await _getCache("cache_prescout_qual_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List ? decoded['entries'] as List : []);
        setMemoryCache("cache_prescout_qual_scouting", list);
        return list;
      } catch (_) {}
    }
    return [];
  }

  Future<List<EventModel>> getCachedEvents({int? year}) async {
    final targetYear = year ?? _currentSettings?.year ?? DateTime.now().year;
    final memKey = "cache_events_$targetYear";
    final inMem = getFromMemoryCache<List<EventModel>>(memKey);
    if (inMem != null && inMem.isNotEmpty) return inMem;

    final cached = await _getCache(memKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        final res = list.map((item) => EventModel.fromJson(item as Map<String, dynamic>)).toList();
        setMemoryCache(memKey, res);
        return res;
      } catch (_) {}
    }
    return [];
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // version 4
    values[8] = (values[8] & 0x3f) | 0x80; // variant
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  String _getDeviceName() {
    if (kIsWeb) return 'ObsidianScout Web App';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ObsidianScout Android App';
      case TargetPlatform.iOS:
        return 'ObsidianScout iOS App';
      case TargetPlatform.windows:
        return 'ObsidianScout Windows App';
      case TargetPlatform.macOS:
        return 'ObsidianScout macOS App';
      case TargetPlatform.linux:
        return 'ObsidianScout Linux App';
      default:
        return 'ObsidianScout App';
    }
  }

  Future<bool> _verifySession() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_currentServerUrl/api/auth/status'),
            headers: _headers,
          );
      if (response.statusCode == 200) {
        _updateCookiesFromResponse(response);
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['loggedIn'] == true) {
            return true;
          }
        } catch (_) {}
        return false;
      }
      return false;
    } catch (_) {
      // If offline / local network check fails, trust stored session if keepMeLoggedIn is true
      return true;
    }
  }

  Future<void> setServerUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.isNotEmpty && !cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    _currentServerUrl = cleanUrl.endsWith('/') ? cleanUrl.substring(0, cleanUrl.length - 1) : cleanUrl;
    _outboxBatchSupported = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyServerUrl, _currentServerUrl);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Mobile-App': 'true',
        if (_deviceId != null && _deviceId!.isNotEmpty) 'X-Device-Id': _deviceId!,
        'X-Device-Name': _getDeviceName(),
        ...?_sessionCookie == null ? null : {'Cookie': _sessionCookie!},
      };

  /// Headers for the live config-editing WebSocket; the session cookie authenticates it.
  Map<String, String> get webSocketHeaders => Map<String, String>.of(_headers)..remove('Content-Type');

  void _handleUnauthorized([
    String reason = 'Your session has expired. Please log in again.',
    int? epoch,
    String? requestCookie,
  ]) {
    if (_handlingRevocation || !isLoggedIn) return;
    // Guard against race conditions from old in-flight requests made before latest login
    if (epoch != null && epoch != _authEpoch) return;
    if (requestCookie != null && _sessionCookie != null && requestCookie != _sessionCookie) return;

    _handlingRevocation = true;
    _syncTimer?.cancel();
    _sessionCookie = null;
    _currentUser = null;
    _keepMeLoggedIn = false;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(keySessionCookie);
      prefs.setBool(keyKeepMeLoggedIn, false);
    });
    _store.remove("cache_auth_me").catchError((_) {});
    permissionsNotifier.value++;
    _sessionRevokedController.add(reason);
  }

  void _checkResponse(http.Response response, {int? epoch, String? requestCookie}) {
    if (response.statusCode == 401) {
      String reason = 'Your session has expired or was revoked. Please log in again.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String && (body['error'] as String).isNotEmpty) {
          reason = body['error'] as String;
        }
      } catch (_) {}
      _handleUnauthorized(reason, epoch, requestCookie);
    } else if (response.statusCode >= 500) {
      _serverErrorController.add(response.statusCode);
    }
  }

  void _checkResponseForServerError(http.Response response, {int? epoch, String? requestCookie}) {
    _checkResponse(response, epoch: epoch, requestCookie: requestCookie);
  }

  void _updateCookiesFromResponse(http.Response response) {
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) return;

    final Map<String, String> cookieMap = {};

    // Preserve existing cookies
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      for (var pair in _sessionCookie!.split(';')) {
        final kv = pair.trim().split('=');
        if (kv.length >= 2) {
          cookieMap[kv[0].trim()] = kv.sublist(1).join('=').trim();
        }
      }
    }

    // Parse Set-Cookie response header(s)
    final cookieParts = rawSetCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'));
    for (var part in cookieParts) {
      final firstPair = part.split(';').first.trim();
      final kv = firstPair.split('=');
      if (kv.length >= 2) {
        final name = kv[0].trim();
        final value = kv.sublist(1).join('=').trim();
        if (value.isEmpty || value == 'deleted') {
          cookieMap.remove(name);
        } else {
          cookieMap[name] = value;
        }
      }
    }

    if (cookieMap.isNotEmpty) {
      _sessionCookie = cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    } else {
      _sessionCookie = null;
    }
  }

  Future<bool> login(
    String username,
    String password, {
    int teamNumber = 0,
    String program = "FRC",
    bool keepMeLoggedIn = false,
  }) async {
    lastLoginError = null;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'username': username,
          'teamNumber': teamNumber,
          'program': program,
          'password': password,
          'keepMeLoggedIn': keepMeLoggedIn,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              if (decoded['error'] != null && decoded['error'].toString().isNotEmpty) {
                return false;
              }
              if (decoded['success'] == false || decoded['loggedIn'] == false) {
                return false;
              }
            }
          } catch (_) {
            // Non-JSON response (e.g. HTML redirect/error page)
            if (_sessionCookie == null || _sessionCookie!.isEmpty) {
              return false;
            }
          }
        }

        _authEpoch++;
        _handlingRevocation = false;
        _updateCookiesFromResponse(response);
        _keepMeLoggedIn = keepMeLoggedIn;
        _savedUsername = username;
        _sessionPassword = password;
        await AuthStorageService.clearBiometricIfDifferentAccount(
          newUsername: username,
          newTeamNumber: teamNumber,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(keyKeepMeLoggedIn, keepMeLoggedIn);
        await prefs.setString(keySavedUsername, username);
        if (keepMeLoggedIn && _sessionCookie != null) {
          await prefs.setString(keySessionCookie, _sessionCookie!);
        } else {
          await prefs.remove(keySessionCookie);
        }
        _startBackgroundSync();
        try {
          await Future.wait([
            fetchCurrentUser().catchError((_) => null),
            fetchSettings().catchError((_) => null),
          ]).timeout(const Duration(seconds: 3));
        } catch (_) {}
        return true;
      }
      lastLoginError = _extractServerError(response);
      return false;
    } catch (e) {
      return false;
    }
  }

  /// The server's error message from the most recent failed [login] (for example the
  /// "Too many failed attempts" rate-limit message), or null for network failures.
  String? lastLoginError;

  String? _extractServerError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final message = decoded['error'] ?? decoded['message'];
        if (message != null && message.toString().trim().isNotEmpty) return message.toString();
      }
    } catch (_) {}
    if (response.statusCode == 429) return 'Too many failed attempts. Please wait 60 seconds.';
    return null;
  }

  Future<ApiResponse<void>> register(
    String username,
    String password, {
    required int teamNumber,
    String program = "FRC",
    String? email,
    String role = "SCOUT",
    bool keepMeLoggedIn = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/auth/register'),
        headers: _headers,
        body: jsonEncode({
          'username': username,
          'teamNumber': teamNumber,
          'program': program,
          'password': password,
          'role': role,
          'email': (email != null && email.trim().isNotEmpty) ? email.trim() : null,
          'keepMeLoggedIn': keepMeLoggedIn,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 302) {
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['error'] != null && decoded['error'].toString().isNotEmpty) {
              return ApiResponse.error(message: decoded['error'].toString(), statusCode: response.statusCode);
            }
          } catch (_) {}
        }

        _authEpoch++;
        _handlingRevocation = false;
        _updateCookiesFromResponse(response);
        _keepMeLoggedIn = keepMeLoggedIn;
        _savedUsername = username;
        _sessionPassword = password;
        await AuthStorageService.clearBiometricIfDifferentAccount(
          newUsername: username,
          newTeamNumber: teamNumber,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(keyKeepMeLoggedIn, keepMeLoggedIn);
        await prefs.setString(keySavedUsername, username);
        if (keepMeLoggedIn && _sessionCookie != null) {
          await prefs.setString(keySessionCookie, _sessionCookie!);
        } else {
          await prefs.remove(keySessionCookie);
        }
        _startBackgroundSync();
        unawaited(fetchCurrentUser().catchError((_) => null));
        unawaited(fetchSettings().catchError((_) => null));
        return const ApiResponse.success(null);
      }
      return ApiResponse.fromHttpResponse(
        response,
        defaultErrorMessage: 'Registration failed. Please check your information and try again.',
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<void> logout() async {
    _handlingRevocation = false;
    _syncTimer?.cancel();
    _outboxRetryTimer?.cancel();
    try {
      await http.post(
        Uri.parse('$_currentServerUrl/api/auth/logout'),
        headers: _headers,
      );
    } catch (_) {}
    _sessionCookie = null;
    _sessionPassword = null;
    _keepMeLoggedIn = false;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySessionCookie);
    await _store.remove("cache_auth_me");
    await prefs.setBool(keyKeepMeLoggedIn, false);
    await AuthStorageService.clearCredentials();
    permissionsNotifier.value++;
  }

  /// Attempts silent authentication using stored secure credentials (biometric gate completed).
  /// 1. Verifies existing session/JWT.
  /// 2. If expired or invalid, re-authenticates with stored password and updates JWT.
  Future<bool> silentLogin() async {
    final creds = await AuthStorageService.loadCredentials();
    if (creds == null) return false;

    // Ensure server URL matches
    if (creds.serverUrl.isNotEmpty && creds.serverUrl != _currentServerUrl) {
      await setServerUrl(creds.serverUrl);
    }

    // Attempt verify session first if we have a cookie
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      final valid = await _verifySession();
      if (valid) {
        _sessionPassword = creds.password;
        _handlingRevocation = false;
        _startBackgroundSync();
        try {
          await Future.wait([fetchCurrentUser(), fetchSettings()]).timeout(const Duration(seconds: 3));
        } catch (_) {}
        return true;
      }
    }

    // If session verification failed or no session, re-login with stored password
    final success = await login(
      creds.username,
      creds.password,
      teamNumber: creds.teamNumber,
      program: creds.program,
      keepMeLoggedIn: true,
    );

    if (success) {
      _sessionPassword = creds.password;
      // Update stored session cookie
      if (_sessionCookie != null) {
        await AuthStorageService.updateJwt(_sessionCookie!);
      }
      return true;
    }

    return false;
  }

  /// Enrolls the user in biometric authentication by saving credentials to secure storage.
  Future<void> enrollBiometric({
    required String username,
    required String password,
    required int teamNumber,
    required String program,
  }) async {
    _sessionPassword = password;
    await AuthStorageService.saveCredentials(
      username: username,
      password: password,
      teamNumber: teamNumber,
      program: program,
      serverUrl: _currentServerUrl,
      jwt: _sessionCookie ?? '',
    );
    await AuthStorageService.setEnrolled(true);
  }

  /// Verifies whether the provided password matches the exact sign-in password.
  /// First checks against the active in-memory session password.
  /// Then verifies against the authentication server to ensure credentials are valid.
  Future<bool> verifyPassword(String password) async {
    // 1. If we have the session password in memory, it MUST match exactly.
    if (_sessionPassword != null && _sessionPassword != password) {
      return false;
    }

    // 2. Identify username for verification
    final username = _savedUsername.isNotEmpty
        ? _savedUsername
        : (_currentUser?.username ?? '');
    if (username.isEmpty || _currentServerUrl.isEmpty) {
      return _sessionPassword != null && _sessionPassword == password;
    }

    // 3. Verify with server
    try {
      final teamNum = _currentUser?.teamNumber ?? 0;
      final program = _currentUser?.program ?? 'FRC';
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'username': username,
          'teamNumber': teamNum,
          'program': program,
          'password': password,
          'keepMeLoggedIn': _keepMeLoggedIn,
        }),
      ).timeout(_deadline(const Duration(seconds: 15)));

      if (response.statusCode == 200 || response.statusCode == 302) {
        _sessionPassword = password;
        _updateCookiesFromResponse(response);
        return true;
      }
      return false;
    } catch (_) {
      // If server is unreachable or offline, allow only if exact session password matches
      if (_sessionPassword != null) {
        return _sessionPassword == password;
      }
      return false;
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> forgotPassword({
    String? email,
    String? username,
    int? teamNumber,
    bool isApp = true,
  }) async {
    try {
      final Map<String, dynamic> body = {'isApp': isApp};
      if (email != null && email.trim().isNotEmpty) {
        body['email'] = email.trim();
      } else {
        if (username != null && username.trim().isNotEmpty) {
          body['username'] = username.trim();
        }
        if (teamNumber != null) {
          body['teamNumber'] = teamNumber;
        }
      }

      final response = await http
          .post(
            Uri.parse('$_currentServerUrl/api/auth/forgot-password'),
            headers: _headers,
            body: jsonEncode(body),
          );

      return ApiResponse.fromHttpResponse(
        response,
        parser: (json) => (json is Map<String, dynamic>) ? json : <String, dynamic>{},
        defaultErrorMessage: 'Failed to request password reset',
      );
    } catch (e) {
      return ApiResponse.error(
        message: e.toString(),
        isOffline: true,
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> verifyResetToken(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_currentServerUrl/api/auth/verify-reset-token?token=${Uri.encodeComponent(token)}'),
            headers: _headers,
          );

      return ApiResponse.fromHttpResponse(
        response,
        parser: (json) => (json is Map<String, dynamic>) ? json : <String, dynamic>{},
        defaultErrorMessage: 'Invalid or expired reset token',
      );
    } catch (e) {
      return ApiResponse.error(
        message: e.toString(),
        isOffline: true,
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> resetPassword({
    required String token,
    String? userId,
    String? newUsername,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_currentServerUrl/api/auth/reset-password'),
            headers: _headers,
            body: jsonEncode({
              'token': token,
              if (userId != null && userId.isNotEmpty) 'userId': userId,
              if (newUsername != null && newUsername.isNotEmpty) 'newUsername': newUsername,
              'newPassword': newPassword,
            }),
          );

      return ApiResponse.fromHttpResponse(
        response,
        parser: (json) => (json is Map<String, dynamic>) ? json : <String, dynamic>{},
        defaultErrorMessage: 'Failed to reset credentials',
      );
    } catch (e) {
      return ApiResponse.error(
        message: e.toString(),
        isOffline: true,
      );
    }
  }

  // Non-Scouting Tools

  /// Pages shown only when the user turns on Non-Scouting Tools.
  static const List<String> nonScoutingToolPages = ['match-checklist', 'battery-tracker'];

  bool get nonScoutingToolsEnabled => _currentUser?.nonScoutingToolsEnabled ?? false;

  /// Saves the Non-Scouting Tools preference to the user's account (it follows them across devices).
  Future<ApiResponse<UserModel>> setNonScoutingToolsEnabled(bool enabled) async {
    if (!_isOnline) {
      return ApiResponse.error(message: 'offline');
    }
    try {
      final response = await http
          .put(
            Uri.parse('$_currentServerUrl/api/user'),
            headers: _headers,
            body: jsonEncode({'nonScoutingToolsEnabled': enabled}),
          );
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final current = _currentUser;
        final updated = decoded is Map<String, dynamic> && decoded['id'] != null
            ? UserModel.fromJson({...?current?.toJson(), ...decoded})
            : UserModel.fromJson({...?current?.toJson(), 'nonScoutingToolsEnabled': enabled});
        _currentUser = updated;
        await _setCache('cache_auth_me', jsonEncode({'user': updated.toJson()}));
        permissionsNotifier.value++;
        return ApiResponse.success(updated, statusCode: response.statusCode);
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update setting');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Match Checklist (drive-team pre-match / on-the-field checklists, edited live)

  /// WebSocket URL for a live checklist document: the team template, or one match's checklist.
  Uri matchChecklistCollabUri({String? eventKey, String? matchKey}) {
    final server = Uri.parse(_currentServerUrl);
    return Uri(
      scheme: server.scheme == 'https' ? 'wss' : 'ws',
      host: server.host,
      port: server.hasPort ? server.port : null,
      path: '/api/match-checklist/collab',
      queryParameters: eventKey == null ? {'template': '1'} : {'eventKey': eventKey, 'matchKey': matchKey ?? ''},
    );
  }

  Map<String, dynamic> _decodeChecklistDoc(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Loads a checklist document, cached for offline use. Null when nothing could be loaded.
  Future<Map<String, dynamic>?> _fetchChecklistDoc(Uri uri, String cacheKey) async {
    final cached = await _getCache(cacheKey);
    if (!_isOnline) return cached == null ? null : _decodeChecklistDoc(cached);
    try {
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final dataJson = decoded['dataJson']?.toString() ?? '{}';
          await _setCache(cacheKey, dataJson);
          return _decodeChecklistDoc(dataJson);
        }
      }
    } catch (_) {}
    return cached == null ? null : _decodeChecklistDoc(cached);
  }

  Future<bool> _putChecklistDoc(Uri uri, Map<String, dynamic> body, String cacheKey, String dataJson) async {
    try {
      final response = await http.put(uri, headers: _headers, body: jsonEncode(body));
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _setCache(cacheKey, dataJson);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> fetchMatchChecklistTemplate() => _fetchChecklistDoc(
        Uri.parse('$_currentServerUrl/api/match-checklist/template'),
        'cache_match_checklist_template',
      );

  Future<bool> saveMatchChecklistTemplate(Map<String, dynamic> doc) {
    final dataJson = jsonEncode(doc);
    return _putChecklistDoc(
      Uri.parse('$_currentServerUrl/api/match-checklist/template'),
      {'dataJson': dataJson},
      'cache_match_checklist_template',
      dataJson,
    );
  }

  Future<Map<String, dynamic>?> fetchMatchChecklist(String eventKey, String matchKey) => _fetchChecklistDoc(
        Uri.parse('$_currentServerUrl/api/match-checklist').replace(queryParameters: {'eventKey': eventKey, 'matchKey': matchKey}),
        'cache_match_checklist_${eventKey}_$matchKey',
      );

  Future<bool> saveMatchChecklist(String eventKey, String matchKey, Map<String, dynamic> doc) {
    final dataJson = jsonEncode(doc);
    return _putChecklistDoc(
      Uri.parse('$_currentServerUrl/api/match-checklist'),
      {'eventKey': eventKey, 'matchKey': matchKey, 'dataJson': dataJson},
      'cache_match_checklist_${eventKey}_$matchKey',
      dataJson,
    );
  }

  // Battery Tracker (drive-team battery inventory + per-event rotation plan, edited live)

  /// WebSocket URL for a live battery document: the team's inventory, or one event's rotation plan.
  Uri batteryTrackerCollabUri({String? eventKey}) {
    final server = Uri.parse(_currentServerUrl);
    return Uri(
      scheme: server.scheme == 'https' ? 'wss' : 'ws',
      host: server.host,
      port: server.hasPort ? server.port : null,
      path: '/api/battery-tracker/collab',
      queryParameters: eventKey == null || eventKey.isEmpty ? {'inventory': '1'} : {'eventKey': eventKey},
    );
  }

  Future<Map<String, dynamic>?> fetchBatteryInventory() => _fetchChecklistDoc(
        Uri.parse('$_currentServerUrl/api/battery-tracker/inventory'),
        'cache_battery_inventory',
      );

  Future<bool> saveBatteryInventory(Map<String, dynamic> doc) {
    final dataJson = jsonEncode(doc);
    return _putChecklistDoc(
      Uri.parse('$_currentServerUrl/api/battery-tracker/inventory'),
      {'dataJson': dataJson},
      'cache_battery_inventory',
      dataJson,
    );
  }

  Future<Map<String, dynamic>?> fetchBatteryPlan(String eventKey) => _fetchChecklistDoc(
        Uri.parse('$_currentServerUrl/api/battery-tracker/event').replace(queryParameters: {'eventKey': eventKey}),
        'cache_battery_plan_$eventKey',
      );

  Future<bool> saveBatteryPlan(String eventKey, Map<String, dynamic> doc) {
    final dataJson = jsonEncode(doc);
    return _putChecklistDoc(
      Uri.parse('$_currentServerUrl/api/battery-tracker/event'),
      {'eventKey': eventKey, 'dataJson': dataJson},
      'cache_battery_plan_$eventKey',
      dataJson,
    );
  }

  // Match predictions game (scouts pick each match's winner; Admin Settings turns it on)

  static const String matchPredictionsPage = 'match-predictions';
  static const String _pendingPicksKey = 'pending_match_predictions';

  bool get matchPredictionsEnabled => _currentSettings?.matchPredictionsEnabled == true;

  /// Picks made offline, keyed by match key: {eventKey, matchKey, predictedWinner}.
  Future<Map<String, Map<String, dynamic>>> _readPendingPicks() async {
    final raw = await _getCache(_pendingPicksKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePendingPicks(Map<String, Map<String, dynamic>> picks) =>
      _setCache(_pendingPicksKey, jsonEncode(picks));

  /// The scout's picks for an event, with each match's lock state and result, keyed by match key.
  /// Falls back to the last copy on this device when offline; picks waiting to upload are layered on top.
  /// Null when the server says predictions are off.
  Future<Map<String, MatchPickStatus>?> fetchMatchPicks(String eventKey) async {
    final cacheKey = 'cache_match_picks_$eventKey';
    Map<String, MatchPickStatus> parse(String body) {
      final decoded = jsonDecode(body);
      final list = decoded is Map && decoded['matches'] is List ? decoded['matches'] as List : const [];
      return {
        for (final m in list.whereType<Map>())
          m['matchKey'].toString(): MatchPickStatus.fromJson(Map<String, dynamic>.from(m)),
      };
    }

    Map<String, MatchPickStatus>? picks;
    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/match-predictions').replace(queryParameters: {'eventKey': eventKey}),
                headers: _headers)
            .timeout(_deadline(const Duration(seconds: 12)));
        _checkResponse(response);
        if (response.statusCode == 403) return null;
        if (response.statusCode == 200) {
          picks = parse(response.body);
          await _setCache(cacheKey, response.body);
        }
      } catch (_) {}
    }
    if (picks == null) {
      final cached = await _getCache(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          picks = parse(cached);
        } catch (_) {}
      }
    }
    picks ??= {};
    final pending = await _readPendingPicks();
    for (final p in pending.values) {
      final key = p['matchKey']?.toString() ?? '';
      if (key.isEmpty || (p['eventKey']?.toString() ?? '') != eventKey) continue;
      final current = picks[key] ?? MatchPickStatus(matchKey: key);
      if (current.locked) continue;
      picks[key] = current.withPick(p['predictedWinner']?.toString(), pendingSync: true);
    }
    return picks;
  }

  Future<void> _updateCachedPick(String eventKey, String matchKey, String winner) async {
    final cacheKey = 'cache_match_picks_$eventKey';
    final cached = await _getCache(cacheKey);
    Map<String, dynamic> doc;
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        doc = decoded is Map<String, dynamic> ? decoded : {'matches': <dynamic>[]};
      } catch (_) {
        doc = {'matches': <dynamic>[]};
      }
    } else {
      doc = {'matches': <dynamic>[]};
    }
    final list = (doc['matches'] is List ? doc['matches'] as List : <dynamic>[]).toList();
    final idx = list.indexWhere((m) => m is Map && m['matchKey']?.toString() == matchKey);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final winnerVal = winner.isEmpty ? null : winner;
    if (idx >= 0) {
      final existing = Map<String, dynamic>.from(list[idx] as Map);
      existing['predictedWinner'] = winnerVal;
      existing['updatedAt'] = winnerVal == null ? null : nowIso;
      list[idx] = existing;
    } else {
      list.add({
        'matchKey': matchKey,
        'predictedWinner': winnerVal,
        'result': null,
        'locked': false,
        'updatedAt': winnerVal == null ? null : nowIso,
      });
    }
    doc['matches'] = list;
    await _setCache(cacheKey, jsonEncode(doc));
  }

  /// Saves a pick ("red", "blue", or "" to clear). Offline, it waits on this device and uploads later.
  Future<MatchPickSaveResult> saveMatchPick(String eventKey, String matchKey, String winner) async {
    Future<MatchPickSaveResult> queue() async {
      final pending = await _readPendingPicks();
      pending[matchKey] = {'eventKey': eventKey, 'matchKey': matchKey, 'predictedWinner': winner};
      await _writePendingPicks(pending);
      return MatchPickSaveResult.queued;
    }

    if (!_isOnline) return queue();
    try {
      final response = await http
          .put(
            Uri.parse('$_currentServerUrl/api/match-predictions'),
            headers: _headers,
            body: jsonEncode({'eventKey': eventKey, 'matchKey': matchKey, 'predictedWinner': winner}),
          )
          .timeout(_deadline(const Duration(seconds: 12)));
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateCachedPick(eventKey, matchKey, winner);
        final pending = await _readPendingPicks();
        if (pending.remove(matchKey) != null) await _writePendingPicks(pending);
        return MatchPickSaveResult.saved;
      }
      if (response.statusCode == 409) return MatchPickSaveResult.locked;
      if (response.statusCode >= 500) return await queue();
      return MatchPickSaveResult.failed;
    } catch (_) {
      return queue();
    }
  }

  bool _flushingPicks = false;

  /// Uploads picks saved offline. One the server refuses (result already in, predictions off) is dropped.
  Future<void> flushPendingMatchPicks() async {
    if (_flushingPicks || !_isOnline) return;
    _flushingPicks = true;
    try {
      final pending = await _readPendingPicks();
      if (pending.isEmpty) return;
      for (final entry in pending.entries.toList()) {
        try {
          final response = await http
              .put(Uri.parse('$_currentServerUrl/api/match-predictions'), headers: _headers, body: jsonEncode(entry.value))
              .timeout(_deadline(const Duration(seconds: 12)));
          if (response.statusCode == 401) {
            _checkResponse(response);
            break;
          }
          if (response.statusCode >= 500) break;
          final eventKey = entry.value['eventKey']?.toString() ?? '';
          final matchKey = entry.value['matchKey']?.toString() ?? '';
          final winner = entry.value['predictedWinner']?.toString() ?? '';
          if (response.statusCode >= 200 && response.statusCode < 300 && eventKey.isNotEmpty && matchKey.isNotEmpty) {
            await _updateCachedPick(eventKey, matchKey, winner);
          }
          pending.remove(entry.key);
        } catch (_) {
          break;
        }
      }
      await _writePendingPicks(pending);
    } finally {
      _flushingPicks = false;
    }
  }

  /// Scouts ranked by pick accuracy for one event ([eventKey]) or a whole season ([year]).
  Future<PickLeaderboard?> fetchPickLeaderboard({String? eventKey, int? year}) async {
    final params = <String, String>{
      if (eventKey != null && eventKey.isNotEmpty) 'eventKey': eventKey,
      if ((eventKey == null || eventKey.isEmpty) && year != null) 'year': '$year',
    };
    final cacheKey = 'cache_pick_leaderboard_${params['eventKey'] ?? 'y${params['year'] ?? ''}'}';
    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/match-predictions/leaderboard').replace(queryParameters: params),
                headers: _headers)
            .timeout(_deadline(const Duration(seconds: 15)));
        _checkResponse(response);
        if (response.statusCode == 200) {
          await _setCache(cacheKey, response.body);
          return PickLeaderboard.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        }
        if (response.statusCode == 403) return null;
      } catch (_) {}
    }
    final cached = await _getCache(cacheKey);
    if (cached == null || cached.isEmpty) return null;
    try {
      return PickLeaderboard.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<PickLeaderboardOptions> fetchPickLeaderboardOptions() async {
    const cacheKey = 'cache_pick_leaderboard_options';
    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/match-predictions/leaderboard/options'), headers: _headers)
            .timeout(_deadline(const Duration(seconds: 12)));
        _checkResponse(response);
        if (response.statusCode == 200) {
          await _setCache(cacheKey, response.body);
          return PickLeaderboardOptions.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    final cached = await _getCache(cacheKey);
    if (cached == null || cached.isEmpty) return const PickLeaderboardOptions();
    try {
      return PickLeaderboardOptions.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return const PickLeaderboardOptions();
    }
  }

  /// Every filled-out checklist for an event, keyed by match key (for per-match progress).
  Future<Map<String, Map<String, dynamic>>> fetchMatchChecklistsForEvent(String eventKey) async {
    final cacheKey = 'cache_match_checklists_$eventKey';
    Map<String, Map<String, dynamic>> parse(String raw) {
      final out = <String, Map<String, dynamic>>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final row in decoded) {
            if (row is Map && row['matchKey'] != null) {
              out[row['matchKey'].toString()] = _decodeChecklistDoc(row['dataJson']?.toString());
            }
          }
        }
      } catch (_) {}
      return out;
    }

    final cached = await _getCache(cacheKey);
    if (!_isOnline) return cached == null ? {} : parse(cached);
    try {
      final uri = Uri.parse('$_currentServerUrl/api/match-checklist/event').replace(queryParameters: {'eventKey': eventKey});
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        return parse(response.body);
      }
    } catch (_) {}
    return cached == null ? {} : parse(cached);
  }

  // User Profile & Settings
  Future<UserModel?> fetchCurrentUser() async {
    final cached = await _getCache("cache_auth_me");
    if (cached != null && cached.isNotEmpty && _currentUser == null) {
      try {
        final jsonMap = await _decodeCached(cached);
        if (jsonMap is Map) {
          final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : (jsonMap is Map<String, dynamic> ? jsonMap : <String, dynamic>{});
          if (userObj.isNotEmpty) {
            _currentUser = UserModel.fromJson(userObj);
          }
        }
      } catch (_) {}
    }

    if (!_isOnline) return _currentUser;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/auth/me'), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        try {
          final jsonMap = jsonDecode(response.body);
          if (jsonMap is Map) {
            await _setCache("cache_auth_me", response.body);
            final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : (jsonMap is Map<String, dynamic> ? jsonMap : <String, dynamic>{});
            if (userObj.isNotEmpty) {
              _currentUser = UserModel.fromJson(userObj);
              permissionsNotifier.value++;
              return _currentUser;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    return _currentUser;
  }

  Future<AppSettingsModel?> fetchSettings() async {
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty && _currentSettings == null) {
      try {
        final jsonMap = await _decodeCached(cached);
        if (jsonMap is Map<String, dynamic>) {
          _currentSettings = AppSettingsModel.fromJson(jsonMap);
          _syncObsidianTheme();
        }
      } catch (_) {}
    }

    if (!_isOnline) return _currentSettings;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        try {
          final jsonMap = jsonDecode(response.body);
          if (jsonMap is Map<String, dynamic>) {
            await _setCache("cache_settings", response.body);
            final previous = _currentSettings;
            _currentSettings = AppSettingsModel.fromJson(jsonMap);
            _syncObsidianTheme();
            permissionsNotifier.value++;
            if (previous == null ||
                previous.year != _currentSettings!.year ||
                previous.eventKey != _currentSettings!.eventKey ||
                previous.eventCode != _currentSettings!.eventCode) {
              settingsNotifier.value = _currentSettings;
            }
            return _currentSettings;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return _currentSettings;
  }


  Future<ApiResponse<AppSettingsModel>> updateSettings(AppSettingsModel settings) async {
    final payload = settings.toJson();
    final jsonStr = jsonEncode(payload);
    await _setCache("cache_settings", jsonStr);
    _currentSettings = settings;
    _syncObsidianTheme();
    permissionsNotifier.value++;
    settingsNotifier.value = settings; // optimistic update for badge/UI

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }

    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/settings'),
        headers: _headers,
        body: jsonStr,
      );
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _setCache("cache_settings", response.body);
        final jsonMap = jsonDecode(response.body);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        _syncObsidianTheme();
        permissionsNotifier.value++;
        settingsNotifier.value = _currentSettings; // confirmed update
        return ApiResponse.success(
          _currentSettings!,
          statusCode: response.statusCode,
          message: 'API settings saved successfully',
        );
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update settings');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<AppSettingsModel>> saveThemes({
    required List<ThemePresetModel> themes,
    required String activeThemeName,
  }) async {
    final current = _currentSettings ?? AppSettingsModel();
    final activePreset = themes.firstWhere(
      (t) => t.name == activeThemeName,
      orElse: () => themes.isNotEmpty ? themes.first : const ThemePresetModel(),
    );
    final updated = current.copyWith(
      themes: themes,
      activeThemeName: activeThemeName,
      theme: activePreset,
    );
    final res = await updateSettings(updated);
    if (res.isSuccess) {
      _syncObsidianTheme();
    }
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> testApiKey({
    required String api,
    String? tbaKey,
    String? firstUsername,
    String? firstKey,
    String? statboticsBaseUrl,
    String? match13BaseUrl,
    String? match13Key,
  }) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot test API while offline');
    }

    try {
      final Map<String, dynamic> body = {'api': api};
      if (tbaKey != null) body['tbaKey'] = tbaKey;
      if (firstUsername != null) body['firstUsername'] = firstUsername;
      if (firstKey != null) body['firstKey'] = firstKey;
      if (statboticsBaseUrl != null) body['statboticsBaseUrl'] = statboticsBaseUrl;
      if (match13BaseUrl != null) body['match13BaseUrl'] = match13BaseUrl;
      if (match13Key != null) body['match13Key'] = match13Key;

      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/settings/test-api'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final isSuccess = decoded['success'] == true;
          final msg = decoded['message']?.toString() ?? (isSuccess ? 'API test succeeded' : 'API test failed');
          if (isSuccess) {
            return ApiResponse.success(decoded, statusCode: response.statusCode, message: msg);
          } else {
            return ApiResponse.error(statusCode: response.statusCode, message: msg);
          }
        }
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'API test failed');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<List<UserModel>>> getAdminUsers({
    String? q,
    int? teamNumber,
    String? program,
    String? role,
    int limit = 50,
    int offset = 0,
    String? sortBy,
    String? sortDir,
  }) async {
    if (!_isOnline) {
      final cached = await _getCache("cache_admin_users");
      if (cached != null && cached.isNotEmpty) {
        try {
          final List decoded = await _decodeCached(cached);
          final users = decoded.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
          return ApiResponse.success(users);
        } catch (_) {}
      }
      return const ApiResponse.error(isOffline: true, message: 'Offline and no cached users');
    }

    try {
      final params = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
      if (teamNumber != null) params['teamNumber'] = teamNumber.toString();
      if (program != null && program.trim().isNotEmpty) params['program'] = program.trim();
      if (role != null && role.trim().isNotEmpty) params['role'] = role.trim();
      if (sortBy != null && sortBy.trim().isNotEmpty) params['sortBy'] = sortBy.trim();
      if (sortDir != null && sortDir.trim().isNotEmpty) params['sortDir'] = sortDir.trim();

      final uri = Uri.parse('$_currentServerUrl/api/admin/users').replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = decoded is List
            ? decoded
            : (decoded is Map<String, dynamic>
                ? (decoded['users'] as List? ?? decoded['data'] as List? ?? [])
                : []);
        final users = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => UserModel.fromJson(e))
            .toList();
        if (offset == 0 && (q == null || q.isEmpty) && teamNumber == null && (role == null || role.isEmpty)) {
          await _setCache("cache_admin_users", jsonEncode(users.map((u) => u.toJson()).toList()));
        }
        return ApiResponse.success(users, statusCode: response.statusCode);
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to fetch users');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<List<UserModel>> fetchTeamMembers({int? teamNumber, String? program}) async {
    final activeTeam = teamNumber ?? _currentUser?.teamNumber ?? 0;
    final activeProgram = program ?? currentProgram;
    final cacheKey = "cache_team_members_${activeTeam}_$activeProgram";

    if (!_isOnline) {
      final cached = await _getCache(cacheKey) ?? await _getCache("cache_admin_users");
      if (cached != null && cached.isNotEmpty) {
        try {
          final List decoded = await _decodeCached(cached);
          return decoded.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      return [];
    }

    try {
      // 1. Try getAdminUsers if admin
      final adminRes = await getAdminUsers(
        teamNumber: activeTeam > 0 ? activeTeam : null,
        program: activeProgram.isNotEmpty ? activeProgram : null,
        limit: 200,
      );
      if (adminRes.data != null && adminRes.data!.isNotEmpty) {
        var list = adminRes.data!;
        if (activeTeam > 0) {
          list = list.where((u) => u.teamNumber == activeTeam || u.teamNumber == 0).toList();
        }
        if (activeProgram.isNotEmpty) {
          list = list
              .where((u) => u.program.isEmpty || u.program.toUpperCase() == activeProgram.toUpperCase())
              .toList();
        }
        if (list.isNotEmpty) {
          await _setCache(cacheKey, jsonEncode(list.map((u) => u.toJson()).toList()));
          return list;
        }
      }

      // 2. Fallback to /api/team-members
      final uri = Uri.parse('$_currentServerUrl/api/team-members');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = decoded is List
            ? decoded
            : (decoded is Map<String, dynamic>
                ? (decoded['members'] as List? ?? decoded['users'] as List? ?? [])
                : []);
        final users = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => UserModel.fromJson({
                  ...e,
                  'teamNumber': activeTeam,
                  'program': activeProgram,
                }))
            .toList();
        if (users.isNotEmpty) {
          await _setCache(cacheKey, jsonEncode(users.map((u) => u.toJson()).toList()));
          return users;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] fetchTeamMembers error: $e');
    }

    // Return cached if network attempts failed
    final cached = await _getCache(cacheKey) ?? await _getCache("cache_admin_users");
    if (cached != null && cached.isNotEmpty) {
      try {
        final List decoded = await _decodeCached(cached);
        return decoded.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    return [];
  }

  Future<ApiResponse<UserModel>> createAdminUser({
    required String username,
    required int teamNumber,
    required String password,
    String? email,
    String? program,
    required String role,
  }) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot create user while offline');
    }

    try {
      final body = <String, dynamic>{
        'username': username.trim(),
        'teamNumber': teamNumber,
        'password': password,
        'role': role.toUpperCase(),
      };
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
      if (program != null && program.trim().isNotEmpty) body['program'] = program.trim();

      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/admin/users'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final user = UserModel.fromJson(decoded as Map<String, dynamic>);
        return ApiResponse.success(user, statusCode: response.statusCode, message: 'User created successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to create user');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<UserModel>> updateAdminUser(
    String userId, {
    String? username,
    String? password,
    String? role,
    String? email,
    String? profilePicture,
    bool clearProfilePicture = false,
  }) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot update user while offline');
    }

    try {
      final body = <String, dynamic>{};
      if (username != null && username.trim().isNotEmpty) body['username'] = username.trim();
      if (password != null && password.isNotEmpty) body['password'] = password;
      if (role != null && role.isNotEmpty) body['role'] = role.toUpperCase();
      if (email != null) body['email'] = email.trim();
      if (clearProfilePicture) {
        body['clearProfilePicture'] = true;
      } else if (profilePicture != null) {
        body['profilePicture'] = profilePicture;
      }

      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/admin/users/$userId'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final user = UserModel.fromJson(decoded as Map<String, dynamic>);
        if (user.id == _currentUser?.id) {
          _currentUser = user;
          await _setCache("cache_auth_me", response.body);
          permissionsNotifier.value++;
        }
        return ApiResponse.success(user, statusCode: response.statusCode, message: 'User updated successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update user');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<bool>> deleteAdminUser(String userId) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot delete user while offline');
    }

    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/admin/users/$userId'),
        headers: _headers,
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(true, statusCode: response.statusCode, message: 'User deleted successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to delete user');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  bool hasPageAccess(String pageId) {
    // Non-scouting tools are a personal opt-in (Settings > Non-Scouting Tools), not role pages.
    if (nonScoutingToolPages.contains(pageId)) {
      return _currentUser?.nonScoutingToolsEnabled ?? false;
    }
    // Match predictions are a team switch (Admin Settings), open to every role while it's on.
    if (pageId == matchPredictionsPage || pageId == 'prediction-leaderboard') {
      return matchPredictionsEnabled;
    }

    final role = (_currentUser?.role ?? 'SCOUT').toUpperCase();

    // SuperAdmin has full access to all pages unconditionally
    if (role == 'SUPERADMIN') {
      return true;
    }

    // SuperAdmin only pages
    if (superAdminOnlyPages.contains(pageId)) {
      return false;
    }

    // Admin only base pages (only ADMIN or SUPERADMIN can access)
    final isAdminPage = adminOnlyBasePages.contains(pageId);
    if (role != 'ADMIN' && isAdminPage) {
      return false;
    }

    // Admins always get these, matching the web (assignments is a bypass page for admins there, and the
    // server always adds admin-settings to adminPages). The app's 'scout-assignments' is the web's 'assignments'.
    if (role == 'ADMIN' &&
        (pageId == 'admin-settings' || pageId == 'scout-assignments' || pageId == 'assignments')) {
      return true;
    }

    // Chat toggle check (if chat is disabled for the team, deny SCOUT, ANALYTICS, ADMIN)
    if (pageId == 'chat' && _currentSettings != null && !_currentSettings!.chatEnabled) {
      return false;
    }

    // Bypass pages
    if (bypassPages.contains(pageId)) {
      return true;
    }

    // Resolve aliases and related identifiers across App and Web
    final candidatePages = <String>{pageId};
    if (pageId == 'config-editor') {
      candidatePages.addAll(['admin-settings', 'default-configs']);
    } else if (pageId == 'admin-settings' || pageId == 'default-configs') {
      candidatePages.add('config-editor');
    }

    if (pageId == 'alliance-selection') {
      candidatePages.add('alliances');
    } else if (pageId == 'alliances') {
      candidatePages.add('alliance-selection');
    }

    if (pageId == 'graphs') {
      candidatePages.add('analytics');
    } else if (pageId == 'analytics') {
      candidatePages.add('graphs');
    }

    if (pageId == 'scout') {
      candidatePages.add('match-scout');
    } else if (pageId == 'match-scout') {
      candidatePages.add('scout');
    }

    if (pageId == 'prescout') {
      candidatePages.addAll(['prescout-scout', 'prescout-pit', 'prescout-qual']);
    } else if (pageId.startsWith('prescout-')) {
      candidatePages.add('prescout');
    }

    if (pageId == 'scout-history') {
      candidatePages.addAll(['history', 'scouting-history', 'cache-manager']);
    } else if (pageId == 'history' || pageId == 'scouting-history' || pageId == 'cache-manager') {
      candidatePages.addAll(['scout-history', 'history', 'cache-manager']);
    }

    if (pageId == 'match-data') {
      candidatePages.add('all-data');
    }

    if (pageId == 'match-planning') {
      candidatePages.addAll(['match-planner', 'matchplanning', 'planning']);
    } else if (pageId == 'match-planner' || pageId == 'matchplanning' || pageId == 'planning') {
      candidatePages.add('match-planning');
    }

    // Dynamic role permissions from team settings (offline cached or live)
    final settings = _currentSettings;
    List<String> allowedPages;
    if (role == 'ADMIN') {
      allowedPages = settings?.adminPages ?? defaultAdminPages;
    } else if (role == 'ANALYTICS') {
      allowedPages = settings?.analyticsPages ?? defaultAnalyticsPages;
    } else {
      allowedPages = settings?.scoutPages ?? defaultScoutPages;
    }

    return candidatePages.any((candidate) => allowedPages.contains(candidate));
  }

  // Settings & Event resolution
  Future<String?> fetchCurrentEventKey() async {
    if (_currentSettings != null && _currentSettings!.eventKey.isNotEmpty) {
      return _currentSettings!.eventKey;
    }
    final cached = await _getCache("cache_settings");
    String? cachedEventKey;
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = await _decodeCached(cached);
        final settings = jsonMap['settings'] ?? jsonMap;
        cachedEventKey = settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
        if (cachedEventKey != null && cachedEventKey.isNotEmpty) {
          return cachedEventKey;
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedEventKey;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_settings", response.body);
        final jsonMap = jsonDecode(response.body);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        final settings = jsonMap['settings'] ?? jsonMap;
        return settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
      }
    } catch (_) {}
    return cachedEventKey;
  }

  Future<List<Map<String, dynamic>>> fetchBanners() async {
    final cached = await _getCache("cache_banners");
    List<Map<String, dynamic>> cachedList = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        cachedList = list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/banners'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_banners", response.body);
        final List list = jsonDecode(response.body);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return cachedList;
  }

  // Config Fetching
  Future<ScoutingConfigModel?> fetchMatchConfig() async {
    final cached = await _getCache("cache_config");
    ScoutingConfigModel? cachedModel;
    if (cached != null && cached.isNotEmpty) {
      try {
        cachedModel = ScoutingConfigModel.fromJson(await _decodeCached(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}

    return cachedModel;
  }

  Future<ScoutingConfigModel?> fetchPitConfig() async {
    final cached = await _getCache("cache_pit_config");
    ScoutingConfigModel? cachedModel;
    if (cached != null && cached.isNotEmpty) {
      try {
        cachedModel = ScoutingConfigModel.fromJson(await _decodeCached(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/pit-config'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_pit_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}

    return cachedModel;
  }

  Future<ScoutingConfigModel?> fetchQualConfig() async {
    final cached = await _getCache("cache_qual_config");
    ScoutingConfigModel? cachedModel;
    if (cached != null && cached.isNotEmpty) {
      try {
        cachedModel = ScoutingConfigModel.fromJson(await _decodeCached(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/qual-config'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_qual_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}

    return cachedModel;
  }

  // Config Saving & Preset Management
  Future<ApiResponse<void>> saveMatchConfig(String rawJson) async {
    await _setCache("cache_config", rawJson);
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/config'),
        headers: _headers,
        body: jsonEncode({'configJson': rawJson}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to save match config');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<void>> savePitConfig(String rawJson) async {
    await _setCache("cache_pit_config", rawJson);
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/pit-config'),
        headers: _headers,
        body: jsonEncode({'configJson': rawJson}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to save pit config');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<void>> saveQualConfig(String rawJson) async {
    await _setCache("cache_qual_config", rawJson);
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/qual-config'),
        headers: _headers,
        body: jsonEncode({'configJson': rawJson}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to save qual config');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<String?> fetchRawConfigJson(String configKind) async {
    final cacheKey = configKind == 'pit'
        ? 'cache_pit_config'
        : (configKind == 'qual' ? 'cache_qual_config' : 'cache_config');
    final apiPath = configKind == 'pit'
        ? '/api/pit-config'
        : (configKind == 'qual' ? '/api/qual-config' : '/api/config');

    if (_isOnline) {
      try {
        final response = await http.get(Uri.parse('$_currentServerUrl$apiPath'), headers: _headers);
        if (response.statusCode == 200) {
          await _setCache(cacheKey, response.body);
          return response.body;
        }
      } catch (_) {}
    }
    return await _getCache(cacheKey);
  }

  Future<List<DefaultConfigPresetModel>> fetchDefaultPresets(String configType) async {
    final typeParam = configType == 'game' ? 'match' : (configType == 'qual' ? 'qualitative' : configType);
    if (!_isOnline) return [];
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config/defaults?type=$typeParam'), headers: _headers);
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => DefaultConfigPresetModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<ApiResponse<ScoutingConfigModel>> applyDefaultPreset(String configType, String presetName) async {
    final typeParam = configType == 'game' ? 'match' : (configType == 'qual' ? 'qualitative' : configType);
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/config/apply-default'),
        headers: _headers,
        body: jsonEncode({
          'configType': typeParam,
          'presetName': presetName,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final cacheKey = configType == 'pit'
            ? 'cache_pit_config'
            : (configType == 'qual' || configType == 'qualitative' ? 'cache_qual_config' : 'cache_config');
        await _setCache(cacheKey, response.body);
        return ApiResponse.success(
          ScoutingConfigModel.fromJson(jsonDecode(response.body)),
          statusCode: response.statusCode,
          message: 'Preset applied successfully',
        );
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to apply preset');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<ScoutingConfigModel>> resetConfigToDefault(String configType) async {
    final typeParam = configType == 'game' ? 'match' : (configType == 'qual' ? 'qualitative' : configType);
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/config/reset'),
        headers: _headers,
        body: jsonEncode({
          'configType': typeParam,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final cacheKey = configType == 'pit'
            ? 'cache_pit_config'
            : (configType == 'qual' || configType == 'qualitative' ? 'cache_qual_config' : 'cache_config');
        await _setCache(cacheKey, response.body);
        return ApiResponse.success(
          ScoutingConfigModel.fromJson(jsonDecode(response.body)),
          statusCode: response.statusCode,
          message: 'Config reset to default',
        );
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to reset config');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Schema History API
  Future<List<ConfigRevisionModel>> fetchConfigHistory(String configKind) async {
    final kindParam = configKind == 'pit' ? 'pit' : (configKind == 'qual' || configKind == 'qualitative' ? 'qual' : 'game');
    if (!_isOnline) return [];
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config-history?kind=$kindParam'), headers: _headers);
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => ConfigRevisionModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<ConfigRevisionModel?> fetchConfigRevisionDetail(String revisionId) async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config-history/$revisionId'), headers: _headers);
      if (response.statusCode == 200) {
        return ConfigRevisionModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ApiResponse<ScoutingConfigModel>> restoreConfigRevision(String revisionId, String configKind) async {
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/config-history/$revisionId/restore'),
        headers: _headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final configJson = data['config'] != null ? jsonEncode(data['config']) : null;
        if (configJson != null) {
          final cacheKey = configKind == 'pit'
              ? 'cache_pit_config'
              : (configKind == 'qual' || configKind == 'qualitative' ? 'cache_qual_config' : 'cache_config');
          await _setCache(cacheKey, configJson);
          return ApiResponse.success(
            ScoutingConfigModel.fromJson(data['config']),
            statusCode: response.statusCode,
            message: 'Revision restored successfully',
          );
        }
        return ApiResponse.success(null, statusCode: response.statusCode);
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to restore revision');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Config Migration API
  Future<ConfigSchemaStatusModel?> fetchConfigMigrationStatus(String configKind) async {
    final kindParam = configKind == 'pit' ? 'pit' : (configKind == 'qual' || configKind == 'qualitative' ? 'qual' : 'game');
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config-migration/status?kind=$kindParam'), headers: _headers);
      if (response.statusCode == 200) {
        return ConfigSchemaStatusModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ConfigMigrationPreviewModel?> previewConfigMigration(
    String configKind,
    List<Map<String, dynamic>> mappings,
    Map<String, dynamic> defaultValues,
  ) async {
    final kindParam = configKind == 'pit' ? 'pit' : (configKind == 'qual' || configKind == 'qualitative' ? 'qual' : 'game');
    if (!_isOnline) return null;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/config-migration/preview'),
        headers: _headers,
        body: jsonEncode({
          'configKind': kindParam,
          'mappings': mappings,
          'defaultValues': defaultValues,
        }),
      );
      if (response.statusCode == 200) {
        return ConfigMigrationPreviewModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ApiResponse<ConfigMigrationResultModel>> applyConfigMigration(
    String configKind,
    List<Map<String, dynamic>> mappings,
    Map<String, dynamic> defaultValues,
  ) async {
    final kindParam = configKind == 'pit' ? 'pit' : (configKind == 'qual' || configKind == 'qualitative' ? 'qual' : 'game');
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/config-migration/apply'),
        headers: _headers,
        body: jsonEncode({
          'configKind': kindParam,
          'mappings': mappings,
          'defaultValues': defaultValues,
        }),
      );
      return ApiResponse.fromHttpResponse(
        response,
        parser: (json) => ConfigMigrationResultModel.fromJson(json),
        defaultErrorMessage: 'Migration failed on server',
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Dropdown Data Fetching
  Future<List<TeamModel>> fetchTeams(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_teams_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";
    final cachedList = await getCachedTeams(effectiveKey);

    if (cachedList.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedList;
    }

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/teams?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/teams';
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        await _setCache("cache_teams_all", response.body);
        if (effectiveKey.isNotEmpty) {
          await _setCache("cache_teams_$effectiveKey", response.body);
        }
        final decoded = jsonDecode(response.body);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['teams'] is List ? decoded['teams'] as List : []);
        final Map<int, TeamModel> teamMap = {};
        for (var item in list) {
          final t = TeamModel.fromJson(item as Map<String, dynamic>);
          teamMap[t.teamNumber] = t;
        }
        if (teamMap.isNotEmpty) {
          final res = teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
          setMemoryCache("mem_teams_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}", res);
          setMemoryCache("mem_teams_all", res);
          return res;
        }
      }
    } catch (_) {}

    return cachedList;
  }

  Future<List<MatchModel>> fetchMatches(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_matches_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";
    final cachedList = await getCachedMatches(effectiveKey);

    if (cachedList.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedList;
    }

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/matches?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/matches';
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        await _setCache("cache_matches_all", response.body);
        if (effectiveKey.isNotEmpty) {
          await _setCache("cache_matches_$effectiveKey", response.body);
        }
        final decoded = jsonDecode(response.body);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['matches'] is List ? decoded['matches'] as List : []);
        final Map<String, MatchModel> matchMap = {};
        for (var item in list) {
          final m = MatchModel.fromJson(item as Map<String, dynamic>);
          if (m.matchKey.isNotEmpty) {
            matchMap[m.matchKey] = m;
          }
        }
        if (matchMap.isNotEmpty) {
          final sorted = matchMap.values.toList()..sort(MatchModel.compareMatches);
          setMemoryCache("mem_matches_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}", sorted);
          setMemoryCache("mem_matches_all", sorted);
          return sorted;
        }
      }
    } catch (_) {}

    return cachedList..sort(MatchModel.compareMatches);
  }

  Future<MatchPredictionResponse?> fetchMatchPrediction(
    String matchKey, {
    String? eventKey,
    bool usePrescout = false,
  }) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_predict_${matchKey}_${effectiveKey}_$usePrescout";

    final cached = await _getCache(cacheKey);
    MatchPredictionResponse? cachedPrediction;
    if (cached != null && cached.isNotEmpty) {
      try {
        cachedPrediction = MatchPredictionResponse.fromJson(await _decodeCached(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedPrediction;

    try {
      final queryParams = <String, String>{
        'matchKey': matchKey,
        if (effectiveKey.isNotEmpty) 'eventKey': effectiveKey,
        if (usePrescout) 'usePrescout': 'true',
      };
      final uri = Uri.parse('$_currentServerUrl/api/matches/predict').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return MatchPredictionResponse.fromJson(decoded);
        }
      }
    } catch (_) {}

    return cachedPrediction;
  }

  Future<MatchPredictionResponse?> getCachedMatchPrediction({
    required String eventKey,
    required String matchKey,
    bool usePrescout = false,
  }) async {
    final effectiveKey = eventKey.isNotEmpty
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_predict_${matchKey}_${effectiveKey}_$usePrescout";

    final cached = await _getCache(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        if (decoded is Map<String, dynamic>) {
          return MatchPredictionResponse.fromJson(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<StatsHistoryModel?> fetchStatsHistory(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_stats_history_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";
    final cached = await getCachedStatsHistory(effectiveKey);

    if (!_isOnline) return cached;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/stats/history?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/stats/history';
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        if (effectiveKey.isNotEmpty) {
          await _setCache("cache_stats_history_$effectiveKey", response.body);
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return StatsHistoryModel.fromJson(decoded);
        }
      }
    } catch (_) {}

    return cached;
  }

  Future<StatsHistoryModel?> getCachedStatsHistory(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_stats_history_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";

    final cached = await _getCache(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        if (decoded is Map<String, dynamic>) {
          return StatsHistoryModel.fromJson(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<MatchPredictionResponse>> fetchEventPredictions(
    String eventKey, {
    bool usePrescout = false,
  }) async {
    final effectiveKey = eventKey.isNotEmpty
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (effectiveKey.isEmpty) return [];

    final cacheKey = "cache_predict_all_${effectiveKey}_$usePrescout";

    final cached = await _getCache(cacheKey);
    List<MatchPredictionResponse> cachedPredictions = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        if (decoded is List) {
          cachedPredictions = decoded
              .map((item) => MatchPredictionResponse.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedPredictions;

    try {
      final queryParams = <String, String>{
        'eventKey': effectiveKey,
        if (usePrescout) 'usePrescout': 'true',
      };
      final uri = Uri.parse('$_currentServerUrl/api/matches/predict-all').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .map((item) => MatchPredictionResponse.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    return cachedPredictions;
  }

  Future<List<MatchPredictionResponse>> getCachedEventPredictions(
    String eventKey, {
    bool usePrescout = false,
  }) async {
    final effectiveKey = eventKey.isNotEmpty
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (effectiveKey.isEmpty) return [];

    final cacheKey = "cache_predict_all_${effectiveKey}_$usePrescout";

    final cached = await _getCache(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        if (decoded is List) {
          return decoded
              .map((item) => MatchPredictionResponse.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<MatchPlanModel?> fetchMatchPlan(String eventKey, String matchKey) async {
    final effectiveEventKey = eventKey.isNotEmpty
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (effectiveEventKey.isEmpty || matchKey.isEmpty) return null;

    final cacheKey = "cache_match_plan_${effectiveEventKey}_$matchKey";
    final cached = await _getCache(cacheKey);
    MatchPlanModel? cachedPlan;
    if (cached != null && cached.isNotEmpty) {
      cachedPlan = MatchPlanModel.fromJsonString(cached);
    }

    if (!_isOnline) return cachedPlan;

    try {
      final uri = Uri.parse('$_currentServerUrl/api/match-planning').replace(
        queryParameters: {
          'eventKey': effectiveEventKey,
          'matchKey': matchKey,
        },
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final planJson = decoded['planJson']?.toString() ?? '{}';
          final updatedAt = (decoded['updatedAt'] as num?)?.toInt() ?? 0;
          await _setCache(cacheKey, planJson);
          return MatchPlanModel.fromJsonString(planJson, updatedAt: updatedAt);
        }
      }
    } catch (_) {}

    return cachedPlan;
  }

  static const String keyPendingMatchPlans = "cache_pending_match_plans";

  Future<int?> saveMatchPlan(String eventKey, String matchKey, String planJson) async {
    final effectiveEventKey = eventKey.isNotEmpty
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (effectiveEventKey.isEmpty || matchKey.isEmpty) return null;

    final cacheKey = "cache_match_plan_${effectiveEventKey}_$matchKey";
    await _setCache(cacheKey, planJson);

    final itemKey = "${effectiveEventKey}_$matchKey";

    if (!_isOnline) {
      await _queuePendingMatchPlan(itemKey, effectiveEventKey, matchKey, planJson);
      return DateTime.now().millisecondsSinceEpoch;
    }

    try {
      final uri = Uri.parse('$_currentServerUrl/api/match-planning');
      final payload = jsonEncode({
        'eventKey': effectiveEventKey,
        'matchKey': matchKey,
        'planJson': planJson,
      });
      final response = await http.post(uri, headers: _headers, body: payload);
      if (response.statusCode == 200) {
        await _dequeuePendingMatchPlan(itemKey);
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return (decoded['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        }
        return DateTime.now().millisecondsSinceEpoch;
      } else {
        await _queuePendingMatchPlan(itemKey, effectiveEventKey, matchKey, planJson);
      }
    } catch (_) {
      await _queuePendingMatchPlan(itemKey, effectiveEventKey, matchKey, planJson);
      return DateTime.now().millisecondsSinceEpoch;
    }

    return null;
  }

  Future<void> _queuePendingMatchPlan(String itemKey, String eventKey, String matchKey, String planJson) async {
    try {
      final raw = (await _store.getString(keyPendingMatchPlans)) ?? '{}';
      final Map<String, dynamic> map = jsonDecode(raw) is Map ? Map<String, dynamic>.from(jsonDecode(raw) as Map) : {};
      map[itemKey] = {
        'eventKey': eventKey,
        'matchKey': matchKey,
        'planJson': planJson,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _store.setString(keyPendingMatchPlans, jsonEncode(map));
    } catch (e) {
      debugPrint('[ApiService] Error queuing pending match plan: $e');
    }
  }

  Future<void> _dequeuePendingMatchPlan(String itemKey) async {
    try {
      final raw = (await _store.getString(keyPendingMatchPlans));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.containsKey(itemKey)) {
          final map = Map<String, dynamic>.from(decoded);
          map.remove(itemKey);
          await _store.setString(keyPendingMatchPlans, jsonEncode(map));
        }
      }
    } catch (_) {}
  }

  Future<int> syncPendingMatchPlans() async {
    if (!_isOnline) return 0;

    try {
      final raw = (await _store.getString(keyPendingMatchPlans));
      if (raw == null || raw.isEmpty || raw == '{}') return 0;

      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded.isEmpty) return 0;

      int syncedCount = 0;
      final remaining = Map<String, dynamic>.from(decoded);

      for (final entry in decoded.entries) {
        final item = entry.value;
        if (item is Map) {
          final eventKey = item['eventKey']?.toString() ?? '';
          final matchKey = item['matchKey']?.toString() ?? '';
          final planJson = item['planJson']?.toString() ?? '';

          if (eventKey.isNotEmpty && matchKey.isNotEmpty && planJson.isNotEmpty) {
            try {
              final uri = Uri.parse('$_currentServerUrl/api/match-planning');
              final payload = jsonEncode({
                'eventKey': eventKey,
                'matchKey': matchKey,
                'planJson': planJson,
              });
              final response = await http.post(uri, headers: _headers, body: payload);
              if (response.statusCode == 200) {
                syncedCount++;
                remaining.remove(entry.key);
                final cacheKey = "cache_match_plan_${eventKey}_$matchKey";
                await _setCache(cacheKey, planJson);
              }
            } catch (_) {
              // Network error or server busy; keep in pending queue for next sync
            }
          } else {
            remaining.remove(entry.key);
          }
        }
      }

      await _store.setString(keyPendingMatchPlans, jsonEncode(remaining));
      if (syncedCount > 0) {
        debugPrint('[ApiService] Successfully synchronized $syncedCount offline match plan(s) with server');
      }
      return syncedCount;
    } catch (e) {
      debugPrint('[ApiService] syncPendingMatchPlans error: $e');
      return 0;
    }
  }

  Future<FieldImageInfoModel?> fetchFieldImageInfo(int year) async {
    final cacheKey = "cache_field_image_info_$year";
    final cached = await _getCache(cacheKey);
    FieldImageInfoModel? cachedInfo;
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = await _decodeCached(cached);
        if (decoded is Map<String, dynamic>) {
          cachedInfo = FieldImageInfoModel.fromJson(decoded);
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedInfo;
    // On a slow link, ask again only with the other static data.
    if (cachedInfo != null && !_staticRefreshDue) return cachedInfo;

    try {
      final uri = Uri.parse('$_currentServerUrl/api/field-images').replace(
        queryParameters: {'year': year.toString()},
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return FieldImageInfoModel.fromJson(decoded);
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> cacheFieldImageBytes(int year, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      final cacheKey = "cache_field_image_bytes_$year";
      await _setCache(cacheKey, base64Encode(bytes));
    } catch (e) {
      debugPrint('[ApiService] cacheFieldImageBytes error: $e');
    }
  }

  Future<Uint8List?> fetchFieldImageBytes(int year) async {
    final cacheKey = "cache_field_image_bytes_$year";
    final cachedBase64 = await _getCache(cacheKey);
    Uint8List? cachedBytes;
    if (cachedBase64 != null && cachedBase64.isNotEmpty) {
      try {
        cachedBytes = base64Decode(cachedBase64);
      } catch (_) {}
    }

    if (!_isOnline) return cachedBytes;

    try {
      final info = await fetchFieldImageInfo(year);
      if (info != null && info.imagePath.isNotEmpty) {
        // The image path carries its version (?v=lastModified); only download a version we don't have.
        final versionKey = "cache_field_image_bytes_${year}_version";
        if (cachedBytes != null && cachedBytes.isNotEmpty && await _getCache(versionKey) == info.imagePath) {
          return cachedBytes;
        }
        final fullUrl = info.imagePath.startsWith('http')
            ? info.imagePath
            : '$_currentServerUrl${info.imagePath}';
        final response = await http.get(Uri.parse(fullUrl), headers: _headers);
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await cacheFieldImageBytes(year, response.bodyBytes);
          await _setCache(versionKey, info.imagePath);
          return response.bodyBytes;
        }
      }
      if (cachedBytes != null && cachedBytes.isNotEmpty) return cachedBytes;

      final serverCandidates = [
        '$_currentServerUrl/assets/images/field-images/$year/rebuilt.png',
        '$_currentServerUrl/assets/images/field-images/$year/reefscape.png',
        '$_currentServerUrl/assets/images/field-images/$year/crescendo.png',
        '$_currentServerUrl/assets/images/field-images/$year/field.png',
      ];

      for (final url in serverCandidates) {
        try {
          final res = await http.get(Uri.parse(url), headers: _headers).timeout(_deadline(const Duration(seconds: 15)));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            await cacheFieldImageBytes(year, res.bodyBytes);
            return res.bodyBytes;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return cachedBytes;
  }

  static const Map<String, String> _entryCacheKeys = {
    'match': 'cache_scouting',
    'pit': 'cache_pit_scouting',
    'qual': 'cache_qual_scouting',
  };

  /// Server URL that answered `/api/sync/entries` with "not found" (an older server); full downloads are used there.
  String? _entrySyncUnsupportedFor;
  final Map<String, Future<List<dynamic>?>> _entrySyncInflight = {};

  bool get _entrySyncSupported => _entrySyncUnsupportedFor != _currentServerUrl;

  /// Brings one stored entry list (every visible entry, prescout included, like `?includePrescout=true&all=true`)
  /// up to date with only what changed since the last sync. Returns null when the full download should be used.
  Future<List<dynamic>?> _syncEntries(String kind, {bool force = false}) {
    if (!_entrySyncSupported) return Future.value(null);
    final key = '$kind|$force';
    return _entrySyncInflight[key] ??= _runEntrySync(kind, force).whenComplete(() => _entrySyncInflight.remove(key));
  }

  Future<List<dynamic>?> _runEntrySync(String kind, bool force) async {
    final cacheKey = _entryCacheKeys[kind]!;
    final cursorKey = 'cache_entrysync_cursor_$kind';
    final current = await _getCachedEntryList(cacheKey);

    String? cursor;
    if (!force && current.isNotEmpty) {
      try {
        final raw = await _getCache(cursorKey);
        final stored = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
        // A cursor is only good for the server and team that issued it.
        if (stored != null && stored['server'] == _currentServerUrl && stored['team'] == _currentUser?.teamNumber) {
          cursor = stored['cursor'] as String?;
        }
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('$_currentServerUrl/api/sync/entries').replace(queryParameters: {
        'kind': kind,
        'format': 'compact',
        if (cursor != null) 'cursor': cursor,
      });
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 404) {
        _entrySyncUnsupportedFor = _currentServerUrl;
        return null;
      }
      if (response.statusCode != 200) return null;
      final decoded = await _decodeCached(response.body);
      if (decoded is! Map<String, dynamic> || decoded['cursor'] is! String) {
        _entrySyncUnsupportedFor = _currentServerUrl;
        return null;
      }
      final merged = entry_sync.mergeDelta(current, decoded);
      if (!merged.consistent && !force) {
        debugPrint('[EntrySync] $kind: merged count differs from the server; downloading the full list.');
        return await _runEntrySync(kind, true);
      }
      await _setCache(cacheKey, jsonEncode(merged.entries));
      setMemoryCache(cacheKey, merged.entries);
      await _setCache(cursorKey, jsonEncode({'server': _currentServerUrl, 'team': _currentUser?.teamNumber, 'cursor': decoded['cursor']}));
      return merged.entries;
    } catch (e) {
      debugPrint('[EntrySync] $kind sync failed: $e');
      return null;
    }
  }

  Future<List<dynamic>> _getCachedEntryList(String cacheKey) async {
    final inMem = getFromMemoryCache<List<dynamic>>(cacheKey);
    if (inMem != null) return inMem;
    final cached = await _getCache(cacheKey);
    if (cached == null || cached.isEmpty) return const [];
    try {
      final decoded = await _decodeCached(cached);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
    } catch (_) {}
    return const [];
  }

  Future<List<dynamic>> fetchScoutingEntries() async {
    const cacheKey = "cache_scouting";
    final cachedEntries = await getCachedScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    final synced = await _syncEntries('match');
    if (synced != null) return synced;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/scouting?includePrescout=true&all=true'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPitScoutingEntries() async {
    const cacheKey = "cache_pit_scouting";
    final cachedEntries = await getCachedPitScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    final synced = await _syncEntries('pit');
    if (synced != null) return synced;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/pit-scouting?includePrescout=true&all=true'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchQualScoutingEntries() async {
    const cacheKey = "cache_qual_scouting";
    final cachedEntries = await getCachedQualScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    final synced = await _syncEntries('qual');
    if (synced != null) return synced;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/qual-scouting?includePrescout=true&all=true'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutScoutingEntries() async {
    const cacheKey = "cache_prescout_scouting";
    final cachedEntries = await getCachedPrescoutScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    // Derived from the delta-synced full list instead of downloaded again.
    if (_entrySyncSupported) {
      final all = await fetchScoutingEntries();
      if (_entrySyncSupported) {
        final list = entry_sync.resolveEntries(all.where((e) => e is Map && e['isPrescout'] == true).toList(), 'match', _currentUser?.teamNumber);
        await _setCache(cacheKey, jsonEncode(list));
        setMemoryCache(cacheKey, list);
        return list;
      }
    }

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/scouting'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutPitScoutingEntries() async {
    const cacheKey = "cache_prescout_pit_scouting";
    final cachedEntries = await getCachedPrescoutPitScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    // Derived from the delta-synced full list instead of downloaded again.
    if (_entrySyncSupported) {
      final all = await fetchPitScoutingEntries();
      if (_entrySyncSupported) {
        final list = entry_sync.resolveEntries(all.where((e) => e is Map && e['isPrescout'] == true).toList(), 'pit', _currentUser?.teamNumber);
        await _setCache(cacheKey, jsonEncode(list));
        setMemoryCache(cacheKey, list);
        return list;
      }
    }

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/pit-scouting'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutQualScoutingEntries() async {
    const cacheKey = "cache_prescout_qual_scouting";
    final cachedEntries = await getCachedPrescoutQualScoutingEntries();
    if (cachedEntries.isNotEmpty && isCacheFresh(cacheKey)) {
      return cachedEntries;
    }

    if (!_isOnline) return cachedEntries;

    // Derived from the delta-synced full list instead of downloaded again.
    if (_entrySyncSupported) {
      final all = await fetchQualScoutingEntries();
      if (_entrySyncSupported) {
        final list = entry_sync.resolveEntries(all.where((e) => e is Map && e['isPrescout'] == true).toList(), 'qual', _currentUser?.teamNumber);
        await _setCache(cacheKey, jsonEncode(list));
        setMemoryCache(cacheKey, list);
        return list;
      }
    }

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/qual-scouting'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map && decoded['entries'] is List) list = decoded['entries'] as List;
        setMemoryCache(cacheKey, list);
        return list;
      }
    } catch (_) {}

    return cachedEntries;
  }

  // Data Submissions
  Future<ApiResponse<void>> submitMatchScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'match', cacheKey: 'cache_scouting', entries: [data], defaultErrorMessage: 'Failed to submit match scouting');

  Future<ApiResponse<void>> submitPrescoutMatchScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'prescout_match', cacheKey: 'cache_prescout_scouting', entries: [data], defaultErrorMessage: 'Failed to submit match prescout');

  Future<ApiResponse<void>> submitPitScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'pit', cacheKey: 'cache_pit_scouting', entries: [data], defaultErrorMessage: 'Failed to submit pit scouting');

  Future<ApiResponse<void>> submitPrescoutPitScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'prescout_pit', cacheKey: 'cache_prescout_pit_scouting', entries: [data], defaultErrorMessage: 'Failed to submit pit prescout');

  Future<ApiResponse<void>> submitQualScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'qual', cacheKey: 'cache_qual_scouting', entries: [data], defaultErrorMessage: 'Failed to submit qualitative scouting');

  Future<ApiResponse<void>> submitBatchQualScouting(List<Map<String, dynamic>> entries) =>
      _submitEntry(kind: 'qual_batch', cacheKey: 'cache_qual_scouting', entries: entries, defaultErrorMessage: 'Failed to submit batch qualitative scouting');

  // ── Outbox: submissions saved on this device until the server has them ──

  static const Map<String, String> _outboxEndpoints = {
    'match': '/api/scouting',
    'prescout_match': '/api/prescout/scouting',
    'pit': '/api/pit-scouting',
    'prescout_pit': '/api/prescout/pit-scouting',
    'qual': '/api/qual-scouting',
    'qual_batch': '/api/qual-scouting/batch',
    'prescout_qual': '/api/prescout/qual-scouting',
  };

  /// Scout-history type for each outbox kind, used to flip history rows to `synced`.
  static const Map<String, String> _outboxHistoryTypes = {
    'match': 'match',
    'prescout_match': 'prescout-match',
    'pit': 'pit',
    'prescout_pit': 'prescout-pit',
    'qual': 'qual',
    'qual_batch': 'qual',
    'prescout_qual': 'prescout-qual',
  };

  /// Number of submissions saved on this device that haven't reached the server yet.
  ValueNotifier<int> get outboxCount => _store.outboxCount;

  bool _outboxSyncing = false;
  final ValueNotifier<bool> outboxSyncing = ValueNotifier<bool>(false);

  /// Saves the entry locally, then tries to upload it. Anything that can't be uploaded right
  /// now (offline, timeout, server error) goes into the outbox and uploads automatically later.
  Future<ApiResponse<void>> _submitEntry({
    required String kind,
    required String cacheKey,
    required List<Map<String, dynamic>> entries,
    required String defaultErrorMessage,
  }) async {
    try {
      final cached = await _getCache(cacheKey);
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = await _decodeCached(cached);
        if (decoded is List) list = decoded;
      }
      list.addAll(entries);
      await _setCache(cacheKey, jsonEncode(list));
    } catch (_) {}

    // The outbox id doubles as the upload's clientId, so a retry after a lost response isn't stored twice.
    final itemId = _generateUuidV4();
    final body = kind == 'qual_batch'
        ? <String, dynamic>{'entries': entries}
        : <String, dynamic>{'data': entries.first, 'clientId': itemId};

    // In the outbox before the upload starts, so closing the app mid-request on a bad link loses nothing.
    final outboxId = await _enqueueOutbox(kind, body, entries.first['eventKey']?.toString(), 'Uploading', id: itemId);

    ApiResponse<void> queued(String reason) {
      _scheduleOutboxRetry();
      return ApiResponse.error(isOffline: true, message: reason);
    }

    if (!_isOnline) {
      return queued('Saved on this device only. It will upload automatically when the connection returns.');
    }
    if (LinkQuality.instance.isLowBandwidth && outboxId != null) {
      // Don't hold the scout on a spinner for a slow upload; the outbox sends it in the background.
      _scheduleOutboxRetry(soon: true);
      return const ApiResponse.error(isOffline: true, message: 'Slow connection: saved on this device and uploading in the background.');
    }
    try {
      final response = await http
          .post(Uri.parse('$_currentServerUrl${_outboxEndpoints[kind]}'), headers: _headers, body: jsonEncode(body));
      if (response.statusCode >= 500 || response.statusCode == 408 || response.statusCode == 429) {
        if (outboxId != null) await _store.recordOutboxFailure(outboxId, 'HTTP ${response.statusCode}');
        return queued('Server error (${response.statusCode}): saved on this device and will retry automatically.');
      }
      // Uploaded or refused for good: either way it no longer belongs in the outbox.
      if (outboxId != null) await _store.removeFromOutbox(outboxId);
      if (kind == 'qual_batch' && (response.statusCode < 200 || response.statusCode >= 300)) {
        // Older servers without the batch endpoint: send each entry on its own.
        var anyQueued = false;
        for (final entry in entries) {
          final single = await submitQualScouting(entry);
          if (single.isOffline) anyQueued = true;
        }
        return anyQueued
            ? const ApiResponse.error(isOffline: true, message: 'Some entries were saved on this device and will upload automatically.')
            : const ApiResponse.success(null, statusCode: 200);
      }
      // The server just completed any matching assignment; the widgets should move on now.
      if (response.statusCode >= 200 && response.statusCode < 300) dataSyncedNotifier.value++;
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: defaultErrorMessage);
    } catch (e) {
      if (outboxId == null) {
        // Couldn't write the outbox before the upload; try once more now.
        await _enqueueOutbox(kind, body, entries.first['eventKey']?.toString(), e.toString(), id: itemId);
      } else {
        await _store.recordOutboxFailure(outboxId, e.toString()).catchError((_) {});
      }
      return queued('Connection error: saved on this device and will upload automatically.');
    }
  }

  /// Returns the new item's id, or null when it couldn't be stored.
  Future<String?> _enqueueOutbox(String kind, Map<String, dynamic> body, String? eventKey, String reason, {String? id}) async {
    try {
      id ??= _generateUuidV4();
      await _store.enqueue(OutboxItem(
        id: id,
        kind: kind,
        eventKey: eventKey,
        payload: body,
        createdAt: DateTime.now(),
        lastError: reason,
      ));
      return id;
    } catch (e) {
      debugPrint('[ApiService] Failed to queue offline submission: $e');
      return null;
    }
  }

  /// Retries the outbox on its own timer, so saved entries don't wait for the next full sync (10 minutes on a slow
  /// link). Backs off from 15 s to 5 minutes while uploads keep failing; stops once the outbox is empty.
  Timer? _outboxRetryTimer;
  int _outboxRetryStep = 0;
  static const List<int> _outboxRetrySeconds = [15, 30, 60, 120, 300];

  void _scheduleOutboxRetry({bool soon = false}) {
    if (_outboxRetryTimer?.isActive == true && !soon) return;
    _outboxRetryTimer?.cancel();
    final delay = soon
        ? const Duration(seconds: 2)
        : Duration(seconds: _outboxRetrySeconds[min(_outboxRetryStep, _outboxRetrySeconds.length - 1)]);
    _outboxRetryTimer = Timer(delay, () async {
      if (_isOnline && isLoggedIn) await syncOutbox().catchError((_) => 0);
      if (outboxCount.value == 0) {
        _outboxRetryStep = 0;
        return;
      }
      _outboxRetryStep++;
      _scheduleOutboxRetry();
    });
  }

  /// Uploads everything in the outbox, oldest first. Stops at the first connection problem
  /// so items stay in order; entries the server rejects (4xx) are dropped from the outbox and
  /// their history rows marked `failed` so the scout can review them.
  /// Returns how many items were uploaded.
  Future<int> syncOutbox() async {
    if (_outboxSyncing || !_isOnline || !isLoggedIn) return 0;
    _outboxSyncing = true;
    outboxSyncing.value = true;
    var uploaded = 0;
    try {
      final items = await _store.outbox();
      var next = 0;
      while (next < items.length && _isOnline) {
        if (_outboxBatchSupported) {
          final chunk = _nextOutboxChunk(items, next);
          final sent = await _uploadOutboxBatch(chunk);
          if (sent == null) {
            // Server without the batch endpoint: upload one by one from here on.
            _outboxBatchSupported = false;
            continue;
          }
          uploaded += sent.uploaded;
          if (sent.stop) break;
          next += chunk.length;
        } else {
          final outcome = await _uploadOutboxItem(items[next]);
          if (outcome == _OutboxOutcome.uploaded) uploaded++;
          if (outcome == _OutboxOutcome.retryLater) break;
          next++;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] syncOutbox error: $e');
    } finally {
      _outboxSyncing = false;
      outboxSyncing.value = false;
    }
    if (uploaded > 0) {
      _outboxRetryStep = 0;
      invalidateMemoryCache('cache_');
      debugPrint('[ApiService] Uploaded $uploaded saved submission(s) from the outbox');
    }
    return uploaded;
  }

  /// False once the server answered `/api/sync/outbox` with 404/405 (an older server); reset on server change.
  bool _outboxBatchSupported = true;

  /// One batch request carries at most this many items and roughly this much JSON, so a dropped connection on a slow
  /// link costs one modest request rather than the whole outbox (pit entries with photos can be hundreds of KB each).
  static const int _outboxBatchMaxItems = 25;
  static const int _outboxBatchMaxChars = 256 * 1024;

  /// Statuses that mean "try this again later" rather than "the server will never take it".
  static bool _isRetryableStatus(int code) => code == 401 || code == 403 || code == 408 || code == 429 || code >= 500;

  /// The item's payload with its outbox id as `clientId`, so the server recognises a retry of an upload whose
  /// response was lost and doesn't store a second copy.
  static Map<String, dynamic> _outboxPayload(OutboxItem item) {
    if (item.kind == 'assignment_status' || item.kind == 'qual_batch' || item.payload['clientId'] != null) return item.payload;
    return {...item.payload, 'clientId': item.id};
  }

  List<OutboxItem> _nextOutboxChunk(List<OutboxItem> items, int start) {
    final chunk = <OutboxItem>[];
    var chars = 0;
    for (var i = start; i < items.length && chunk.length < _outboxBatchMaxItems; i++) {
      final size = jsonEncode(items[i].payload).length;
      if (chunk.isNotEmpty && chars + size > _outboxBatchMaxChars) break;
      chunk.add(items[i]);
      chars += size;
    }
    return chunk;
  }

  /// Uploads [chunk] in one request. Returns null when the server has no batch endpoint.
  Future<({int uploaded, bool stop})?> _uploadOutboxBatch(List<OutboxItem> chunk) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_currentServerUrl/api/sync/outbox'),
        headers: _headers,
        body: jsonEncode({
          'items': [
            for (final item in chunk) {'id': item.id, 'kind': item.kind, 'payload': _outboxPayload(item)},
          ],
        }),
      );
    } catch (e) {
      await _store.recordOutboxFailure(chunk.first.id, e.toString());
      return (uploaded: 0, stop: true);
    }
    if (response.statusCode == 404 || response.statusCode == 405) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _store.recordOutboxFailure(chunk.first.id, 'HTTP ${response.statusCode}');
      return (uploaded: 0, stop: true);
    }

    final List results;
    try {
      results = (jsonDecode(response.body) as Map)['results'] as List;
    } catch (_) {
      return null;
    }
    final byId = {for (final item in chunk) item.id: item};
    var uploaded = 0;
    for (final raw in results.whereType<Map>()) {
      final item = byId[raw['id']?.toString()];
      if (item == null) continue;
      final status = (raw['status'] as num?)?.toInt() ?? 500;
      if (status >= 200 && status < 300) {
        await _store.removeFromOutbox(item.id);
        await _markOutboxHistory(item, 'synced');
        uploaded++;
      } else if (_isRetryableStatus(status)) {
        // The server stops at the first retryable failure, so this and everything after it stay queued in order.
        await _store.recordOutboxFailure(item.id, 'HTTP $status${raw['error'] != null ? ': ${raw['error']}' : ''}');
        return (uploaded: uploaded, stop: true);
      } else {
        // The server will never accept this as-is (e.g. 400/404/409/422).
        await _store.removeFromOutbox(item.id);
        await _markOutboxHistory(item, 'failed');
      }
    }
    return (uploaded: uploaded, stop: false);
  }

  /// One item on its own route, for servers without `/api/sync/outbox`.
  Future<_OutboxOutcome> _uploadOutboxItem(OutboxItem item) async {
    try {
      final http.Response response;
      if (item.kind == 'assignment_status') {
        final id = Uri.encodeComponent(item.payload['id'].toString());
        response = await http.post(Uri.parse('$_currentServerUrl/api/assignments/$id/status'),
            headers: _headers, body: jsonEncode({'status': item.payload['status']}));
      } else {
        final endpoint = _outboxEndpoints[item.kind];
        if (endpoint == null) {
          await _store.removeFromOutbox(item.id);
          return _OutboxOutcome.dropped;
        }
        response = await http.post(Uri.parse('$_currentServerUrl$endpoint'),
            headers: _headers, body: jsonEncode(_outboxPayload(item)));
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _store.removeFromOutbox(item.id);
        await _markOutboxHistory(item, 'synced');
        return _OutboxOutcome.uploaded;
      } else if (_isRetryableStatus(response.statusCode)) {
        await _store.recordOutboxFailure(item.id, 'HTTP ${response.statusCode}');
        return _OutboxOutcome.retryLater;
      } else {
        // The server will never accept this as-is (e.g. 400/404/409/422).
        await _store.removeFromOutbox(item.id);
        await _markOutboxHistory(item, 'failed');
        return _OutboxOutcome.dropped;
      }
    } catch (e) {
      await _store.recordOutboxFailure(item.id, e.toString());
      return _OutboxOutcome.retryLater;
    }
  }

  Future<void> _markOutboxHistory(OutboxItem item, String status) async {
    final type = _outboxHistoryTypes[item.kind];
    if (type == null) return;
    final List<Map<String, dynamic>> payloads = item.kind == 'qual_batch'
        ? ((item.payload['entries'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [if (item.payload['data'] is Map) Map<String, dynamic>.from(item.payload['data'] as Map)];
    for (final payload in payloads) {
      await ScoutHistoryService.markMatchingStatus(type, payload, status);
    }
  }

  /// Drops outbox items for an entry that was uploaded another way (e.g. Scout History's sync button).
  Future<void> removeOutboxEntriesMatching(String historyType, Map<String, dynamic> payload) async {
    final items = await _store.outbox();
    for (final item in items) {
      if (_outboxHistoryTypes[item.kind] != historyType) continue;
      final data = item.payload['data'];
      if (data is Map && ScoutHistoryService.samePayloadTarget(Map<String, dynamic>.from(data), payload)) {
        await _store.removeFromOutbox(item.id);
      }
    }
  }

  Future<ApiResponse<void>> submitPrescoutQualScouting(Map<String, dynamic> data) =>
      _submitEntry(kind: 'prescout_qual', cacheKey: 'cache_prescout_qual_scouting', entries: [data], defaultErrorMessage: 'Failed to submit qualitative prescout');

  Future<ApiResponse<void>> submitScannedItem(String type, Map<String, dynamic> data) async {
    String endpoint;
    final lowerType = type.toLowerCase().replaceAll('_', '-');
    if (lowerType == 'scout' || lowerType == 'match-scout' || lowerType == 'match-scouting' || lowerType == 'match') {
      endpoint = '/api/scouting';
    } else if (lowerType == 'pit-scout' || lowerType == 'pit-scouting' || lowerType == 'pit') {
      endpoint = '/api/pit-scouting';
    } else if (lowerType == 'qual-scout' || lowerType == 'qualitative-scouting' || lowerType == 'qual-scouting' || lowerType == 'qual') {
      endpoint = '/api/qual-scouting';
    } else if (lowerType == 'prescout-scout' || lowerType == 'prescout-match') {
      endpoint = '/api/prescout/scouting';
    } else if (lowerType == 'prescout-pit') {
      endpoint = '/api/prescout/pit-scouting';
    } else if (lowerType == 'prescout-qual') {
      endpoint = '/api/prescout/qual-scouting';
    } else {
      endpoint = '/api/scouting';
    }

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    }

    try {
      final innerData = data.containsKey('data') && data['data'] is Map<String, dynamic>
          ? data['data']
          : data;

      final response = await http.post(
        Uri.parse('$_currentServerUrl$endpoint'),
        headers: _headers,
        body: jsonEncode({'data': innerData}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to upload scanned item');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<void>> deleteScoutingEntry(String id, {String type = 'match'}) async {
    String cleanId = id;
    for (final prefix in ['match-', 'pit-', 'qual-', 'qualitative-']) {
      if (cleanId.toLowerCase().startsWith(prefix)) {
        cleanId = cleanId.substring(prefix.length);
        break;
      }
    }
    final lower = type.toLowerCase();
    final endpoint = (lower == 'pit' || id.toLowerCase().startsWith('pit-'))
        ? '/api/pit-scouting/$cleanId'
        : (lower == 'qual' || lower == 'qualitative' || id.toLowerCase().startsWith('qual-') || id.toLowerCase().startsWith('qualitative-'))
            ? '/api/qual-scouting/$cleanId'
            : '/api/scouting/$cleanId';

    // Remove from the stored list optimistically, so the data pages update without downloading it again.
    final isPit = lower == 'pit' || id.toLowerCase().startsWith('pit-');
    await _patchCachedEntries(_entryCacheKeyFor(type, id), (list) {
      final removed = list.whereType<Map>().where((e) => e['id']?.toString() == cleanId).toList();
      final kept = list.where((e) => !(e is Map && e['id']?.toString() == cleanId)).toList();
      for (final r in removed) {
        _clearResolvedDiscrepancy(kept, r, isPit: isPit);
      }
      return kept;
    });

    if (!_isOnline) {
      return const ApiResponse.success(null, message: 'Removed from local cache (offline).');
    }

    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl$endpoint'),
        headers: _headers,
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to delete scouting entry');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Stored entry list for an entry of [type] (or an id carrying a `pit-`/`qual-` prefix).
  static String _entryCacheKeyFor(String type, String id) {
    final lower = type.toLowerCase();
    final lowerId = id.toLowerCase();
    if (lower == 'pit' || lowerId.startsWith('pit-')) return 'cache_pit_scouting';
    if (lower == 'qual' || lower == 'qualitative' || lowerId.startsWith('qual-') || lowerId.startsWith('qualitative-')) {
      return 'cache_qual_scouting';
    }
    return 'cache_scouting';
  }

  /// Applies a change made on this device to a stored entry list (memory and disk), so the data pages can show it
  /// at once instead of downloading every entry again: on a bad connection that download takes minutes. The next
  /// delta sync brings the server's own copy of the change.
  Future<void> _patchCachedEntries(String cacheKey, List<dynamic> Function(List<dynamic> entries) change) async {
    try {
      final current = await _getCachedEntryList(cacheKey);
      final updated = change(List<dynamic>.of(current));
      await _setCache(cacheKey, jsonEncode(updated));
      setMemoryCache(cacheKey, updated);
    } catch (e) {
      debugPrint('[ApiService] Could not update stored entries ($cacheKey): $e');
    }
  }

  /// Entries the server counts as one submission slot: same team in the same match (same event for pit).
  static String _discrepancyGroup(Map entry, {required bool isPit}) {
    final team = entry['targetTeamNumber']?.toString() ?? '';
    final prescout = entry['isPrescout'] == true ? 'p' : '';
    if (isPit) return '$prescout|${entry['eventKey'] ?? ''}|$team';
    return '$prescout|${entry['eventKey'] ?? ''}|${entry['matchKey'] ?? entry['matchNumber'] ?? ''}|$team';
  }

  /// After [removed] is gone, an entry left alone in its group no longer disagrees with anything. Other groups keep
  /// their flags: the delta sync only re-sends entries that changed, so a flag cleared here would stay cleared.
  static void _clearResolvedDiscrepancy(List<dynamic> entries, Map removed, {required bool isPit}) {
    final group = _discrepancyGroup(removed, isPit: isPit);
    final same = entries.whereType<Map>().where((e) => _discrepancyGroup(e, isPit: isPit) == group).toList();
    if (same.length > 1) return;
    for (final e in same) {
      e['hasDiscrepancy'] = false;
      e.remove('conflictingTeams');
    }
  }

  Future<ApiResponse<void>> updateScoutingEntry(String id, Map<String, dynamic> data, {String type = 'match'}) async {
    String cleanId = id;
    for (final prefix in ['match-', 'pit-', 'qual-', 'qualitative-']) {
      if (cleanId.toLowerCase().startsWith(prefix)) {
        cleanId = cleanId.substring(prefix.length);
        break;
      }
    }
    final lower = type.toLowerCase();
    final endpoint = (lower == 'pit' || id.toLowerCase().startsWith('pit-'))
        ? '/api/pit-scouting/$cleanId'
        : (lower == 'qual' || lower == 'qualitative' || id.toLowerCase().startsWith('qual-') || id.toLowerCase().startsWith('qualitative-'))
            ? '/api/qual-scouting/$cleanId'
            : '/api/scouting/$cleanId';

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    }

    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl$endpoint'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Put the saved entry into the stored list: the server's copy when it sent one, else the data just sent.
        Map<String, dynamic>? saved;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['id'] != null) saved = Map<String, dynamic>.from(decoded);
        } catch (_) {}
        await _patchCachedEntries(_entryCacheKeyFor(type, id), (list) => [
              for (final e in list)
                if (e is Map && e['id']?.toString() == cleanId)
                  saved != null ? {...e, ...saved} : {...e, 'data': data}
                else
                  e,
            ]);
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update scouting entry');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Analytics
  Future<Map<String, dynamic>?> _cachedJsonMap(String key) async {
    final raw = await _getCache(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = await _decodeCached(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _maps(Iterable<dynamic> list) =>
      list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  /// `/api/analytics` computed from stored entries and the cached match config (same math as the server).
  /// Null when there's nothing stored to compute from.
  Future<Map<String, dynamic>?> computeLocalAnalytics({bool usePrescout = false}) async {
    final config = await _cachedJsonMap("cache_config");
    final all = await getCachedScoutingEntries();
    if (config == null || all.isEmpty) return null;
    final own = _currentUser?.teamNumber;
    final regular = entry_sync.resolveEntries(all.where((e) => e is Map && e['isPrescout'] != true).toList(), 'match', own);
    final prescout = entry_sync.resolveEntries(all, 'match', own).where((e) => e['isPrescout'] == true).toList();
    final merged = local_analytics.mergePrescoutEntries(regular, prescout, _currentSettings?.eventKey ?? '', forceUsePrescout: usePrescout);
    return local_analytics.generateAnalytics(config, merged);
  }

  /// `/api/custom-analytics/dataset` computed from stored entries, configs and teams.
  Future<Map<String, dynamic>?> computeLocalDataset({String? eventKey, bool includePrescout = true}) async {
    final matchConfig = await _cachedJsonMap("cache_config");
    final all = await getCachedScoutingEntries();
    if (matchConfig == null || all.isEmpty) return null;
    final own = _currentUser?.teamNumber;
    List<Map<String, dynamic>> derive(List<dynamic> list, String kind) => entry_sync.resolveEntries(
        includePrescout ? list : list.where((e) => e is Map && e['isPrescout'] != true).toList(), kind, own);
    final teamsKey = "cache_teams_${eventKey ?? _currentSettings?.eventKey ?? ''}";
    List<dynamic> teams = const [];
    try {
      final raw = await _getCache(teamsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = await _decodeCached(raw);
        teams = decoded is List ? decoded : (decoded is Map && decoded['teams'] is List ? decoded['teams'] as List : const []);
      }
    } catch (_) {}
    return local_analytics.buildDataset(
      matchConfig: matchConfig,
      pitConfig: await _cachedJsonMap("cache_pit_config") ?? const {'fields': []},
      qualConfig: await _cachedJsonMap("cache_qual_config") ?? const {'fields': []},
      matchEntries: derive(all, 'match'),
      pitEntries: derive(await getCachedPitScoutingEntries(), 'pit'),
      qualEntries: derive(await getCachedQualScoutingEntries(), 'qual'),
      teams: _maps(teams),
      eventKeyFilter: eventKey,
      program: currentProgram,
    );
  }

  Future<List<AnalyticsWidgetModel>> fetchAnalyticsWidgets({bool usePrescout = false}) async {
    // Prescout widgets come only from the server; they don't replace the cached event copy.
    if (usePrescout) {
      final res = await requestJson('GET', '/api/analytics', query: {'usePrescout': 'true'});
      final data = res.data;
      if (res.success && data is Map && data['widgets'] is List) {
        return (data['widgets'] as List).map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>)).toList();
      }
      return [];
    }
    final cached = await _getCache("cache_analytics");
    List<AnalyticsWidgetModel> cachedWidgets = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final Map<String, dynamic> jsonMap = await _decodeCached(cached);
        if (jsonMap['widgets'] is List) {
          cachedWidgets = (jsonMap['widgets'] as List)
              .map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    if (!_isOnline || LinkQuality.instance.isLowBandwidth) {
      final local = await computeLocalAnalytics();
      if (local != null) {
        return (local['widgets'] as List).map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>)).toList();
      }
      if (!_isOnline) return cachedWidgets;
    }

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/analytics'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_analytics", response.body);
        final Map<String, dynamic> jsonMap = jsonDecode(response.body);
        if (jsonMap['widgets'] is List) {
          return (jsonMap['widgets'] as List)
              .map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    return cachedWidgets;
  }

  // Custom Analytics (BI Studio) API Methods
  Future<List<CustomAnalyticsReportRecord>> fetchCustomAnalyticsReports() async {
    final cached = await _getCache("cache_custom_analytics_reports");
    List<CustomAnalyticsReportRecord> cachedReports = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        cachedReports = list.map((e) => CustomAnalyticsReportRecord.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedReports;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/custom-analytics/reports'), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache("cache_custom_analytics_reports", response.body);
        final List list = jsonDecode(response.body);
        return list.map((e) => CustomAnalyticsReportRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return cachedReports;
  }

  Future<CustomAnalyticsReportRecord?> fetchCustomAnalyticsReport(String id) async {
    if (!_isOnline) {
      final reports = await fetchCustomAnalyticsReports();
      try {
        return reports.firstWhere((r) => r.id == id);
      } catch (_) {
        return null;
      }
    }

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/custom-analytics/reports/$id'), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return CustomAnalyticsReportRecord.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<CustomAnalyticsReportRecord?> createCustomAnalyticsReport({
    required String title,
    String category = 'General',
    String? description,
    required String configJson,
    bool isShared = false,
    bool isDefault = false,
  }) async {
    if (!_isOnline) return null;

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/custom-analytics/reports'),
        headers: _headers,
        body: jsonEncode({
          'title': title,
          'category': category,
          if (description != null) 'description': description,
          'configJson': configJson,
          'isShared': isShared,
          'isDefault': isDefault,
        }),
      );
      _checkResponse(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final created = CustomAnalyticsReportRecord.fromJson(jsonDecode(response.body));
        // Update local cache
        final reports = await fetchCustomAnalyticsReports();
        reports.insert(0, created);
        await _setCache("cache_custom_analytics_reports", jsonEncode(reports.map((r) => r.toJson()).toList()));
        return created;
      }
    } catch (_) {}
    return null;
  }

  Future<CustomAnalyticsReportRecord?> updateCustomAnalyticsReport(
    String id, {
    String? title,
    String? category,
    String? description,
    String? configJson,
    bool? isShared,
    bool? isDefault,
  }) async {
    if (!_isOnline) return null;

    try {
      final Map<String, dynamic> body = {};
      if (title != null) body['title'] = title;
      if (category != null) body['category'] = category;
      if (description != null) body['description'] = description;
      if (configJson != null) body['configJson'] = configJson;
      if (isShared != null) body['isShared'] = isShared;
      if (isDefault != null) body['isDefault'] = isDefault;

      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/custom-analytics/reports/$id'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response);
      if (response.statusCode == 200) {
        final updated = CustomAnalyticsReportRecord.fromJson(jsonDecode(response.body));
        return updated;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteCustomAnalyticsReport(String id) async {
    if (!_isOnline) return false;

    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/custom-analytics/reports/$id'),
        headers: _headers,
      );
      _checkResponse(response);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<CustomAnalyticsReportRecord?> duplicateCustomAnalyticsReport(String id) async {
    if (!_isOnline) return null;

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/custom-analytics/reports/$id/duplicate'),
        headers: _headers,
      );
      _checkResponse(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return CustomAnalyticsReportRecord.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<CustomAnalyticsDataset?> fetchCustomAnalyticsDataset({
    String? eventKey,
    bool includePrescout = true,
  }) async {
    final cacheKey = "cache_custom_analytics_dataset_${eventKey ?? 'all'}_$includePrescout";
    final cached = await _getCache(cacheKey);
    CustomAnalyticsDataset? cachedDataset;
    if (cached != null && cached.isNotEmpty) {
      try {
        cachedDataset = CustomAnalyticsDataset.fromJson(await _decodeCached(cached));
      } catch (_) {}
    }

    if (!_isOnline || LinkQuality.instance.isLowBandwidth) {
      final local = await computeLocalDataset(eventKey: eventKey, includePrescout: includePrescout);
      if (local != null) return CustomAnalyticsDataset.fromJson(local);
      if (!_isOnline) return cachedDataset;
    }

    try {
      String url = '$_currentServerUrl/api/custom-analytics/dataset?includePrescout=$includePrescout';
      if (eventKey != null && eventKey.isNotEmpty) {
        url += '&eventKey=${Uri.encodeComponent(eventKey)}';
      }

      final response = await http.get(Uri.parse(url), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        return CustomAnalyticsDataset.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}

    return cachedDataset;
  }

  // Chat API Methods
  Future<bool> fetchChatEnabled() async {
    final cached = await _getCache("cache_chat_enabled");
    if (cached != null) {
      if (cached == "false") return false;
      if (cached == "true") return true;
    }
    if (!_isOnline) return cached == "true";

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings?local=true'), headers: _headers);
      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body);
        final settings = jsonMap['settings'] ?? jsonMap;
        final enabled = settings['chatEnabled'] != false;
        await _setCache("cache_chat_enabled", enabled ? "true" : "false");
        return enabled;
      }
    } catch (_) {}
    return true;
  }

  Future<List<String>> fetchChatGroups() async {
    final cached = await _getCache("cache_chat_groups");
    List<String> cachedGroups = ["general"];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        cachedGroups = list.map((e) => e.toString()).toList();
        if (!cachedGroups.contains("general")) {
          cachedGroups.insert(0, "general");
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedGroups;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/groups'), headers: _headers);
      _checkResponseForServerError(response);
      if (response.statusCode == 200) {
        await _setCache("cache_chat_groups", response.body);
        final List list = jsonDecode(response.body);
        final set = <String>{"general", ...list.map((e) => e.toString())};
        return set.toList();
      }
    } catch (_) {}

    return cachedGroups;
  }

  Future<bool> createChatGroup(String groupName) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/chat/groups'),
        headers: _headers,
        body: jsonEncode({'groupName': groupName}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> deleteChatGroup(String groupName) async {
    if (!_isOnline) return false;
    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/chat/groups/${Uri.encodeComponent(groupName)}'),
        headers: _headers,
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> clearChatGroupMessages(String groupName) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/chat/groups/${Uri.encodeComponent(groupName)}/clear'),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<ChatGroupDetailsModel?> fetchChatGroupDetails(String groupName) async {
    if (!_isOnline) return null;
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/chat/groups/${Uri.encodeComponent(groupName)}/details'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatGroupDetailsModel.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateChatGroupPermissions(
    String groupName,
    List<String> allowedRoles,
    List<String> allowedUserIds,
  ) async {
    if (!_isOnline) return false;
    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/chat/groups/${Uri.encodeComponent(groupName)}/permissions'),
        headers: _headers,
        body: jsonEncode({
          'allowedRoles': allowedRoles,
          'allowedUserIds': allowedUserIds,
        }),
      );
      _checkResponseForServerError(response);
      return response.statusCode == 200;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<List<ChatTeamMemberModel>> fetchChatTeamMembers() async {
    if (!_isOnline) return [];
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/chat/team-members'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ChatTeamMemberModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<String?> fetchCurrentUserRole() async {
    if (_currentUser != null) return _currentUser!.role;
    final user = await fetchCurrentUser();
    return user?.role;
  }

  Future<List<ChatMessageModel>> fetchChatMessages(String groupName) async {
    final cacheKey = "cache_chat_messages_$groupName";
    final cached = await _getCache(cacheKey);
    List<ChatMessageModel> cachedList = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        cachedList = list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/messages?group=${Uri.encodeComponent(groupName)}'), headers: _headers);
      _checkResponseForServerError(response);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final List list = jsonDecode(response.body);
        return list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return cachedList;
  }

  Future<bool> sendChatMessage(String groupName, String content) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/chat/messages'),
        headers: _headers,
        body: jsonEncode({
          'groupName': groupName,
          'content': content,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> editChatMessage(String messageId, String content) async {
    if (!_isOnline) return false;
    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/chat/messages/$messageId'),
        headers: _headers,
        body: jsonEncode({
          'content': content,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> deleteChatMessage(String messageId) async {
    if (!_isOnline) return false;
    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/chat/messages/$messageId'),
        headers: _headers,
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> toggleChatReaction(String messageId, String emoji) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/chat/messages/$messageId/react'),
        headers: _headers,
        body: jsonEncode({'emoji': emoji}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  Future<bool> markChatGroupRead(String groupName) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/chat/read'),
        headers: _headers,
        body: jsonEncode({'groupName': groupName}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> fetchChatTeamUsers() async {
    final cached = await _getCache("cache_chat_team_users");
    List<String> cachedUsers = ["everyone", "channel"];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = await _decodeCached(cached);
        cachedUsers = list.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedUsers;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/team-users'), headers: _headers);
      if (response.statusCode == 200) {
        await _setCache("cache_chat_team_users", response.body);
        final List list = jsonDecode(response.body);
        final filtered = list.map((e) => e.toString()).where((u) => u.toLowerCase() != "deleted user").toList();
        final set = <String>{"everyone", "channel", ...filtered};
        return set.toList();
      }
    } catch (_) {}

    return cachedUsers;
  }

  Future<Map<String, ChatGroupUnreadModel>> fetchChatUnreadStatus() async {
    if (!_isOnline) return {};
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/unread-status'), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final Map<String, ChatGroupUnreadModel> result = {};
        if (data['groups'] is List) {
          for (final item in data['groups']) {
            final model = ChatGroupUnreadModel.fromJson(item as Map<String, dynamic>);
            result[model.groupName] = model;
          }
        }
        return result;
      }
    } catch (_) {}
    return {};
  }

  Future<void> clearAllCache() async {
    try {
      await _store.removeWithPrefix("cache_");
      _memoryCache.clear();
      _cacheTimestamps.clear();
    } catch (_) {}
  }

  // Home-screen widgets

  /// Raw JSON of the widget snapshot (see /api/widgets/snapshot), or null when offline or signed out.
  /// [placed] lists the widget kinds on the home screen so the server only pushes refreshes that matter.
  /// Also returns the response's ETag, which the native widgets reuse for their own "not modified" checks.
  Future<({String body, String? etag})?> fetchWidgetSnapshot({List<String>? placed}) async {
    if (!_isOnline || !isLoggedIn) return null;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/widgets/snapshot')
          .replace(queryParameters: placed == null ? null : {'placed': placed.join(',')});
      final response = await http.get(uri, headers: _headers);
      // Widgets refresh quietly: only a signed-out session is acted on, never a server-error banner.
      if (response.statusCode == 401) _checkResponse(response);
      if (response.statusCode == 200) return (body: response.body, etag: response.headers['etag']);
    } catch (_) {}
    return null;
  }

  /// A read-only token the phone's widgets use to fetch their snapshot while the app is closed.
  /// It is tied to this login and stops working when the user signs out or the device is revoked.
  Future<({String token, int expiresAt})?> issueWidgetToken(String platform) async {
    if (!_isOnline || !isLoggedIn) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_currentServerUrl/api/widgets/token'),
            headers: _headers,
            body: jsonEncode({'platform': platform}),
          );
      // Widgets refresh quietly: only a signed-out session is acted on, never a server-error banner.
      if (response.statusCode == 401) _checkResponse(response);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['token'] is String) {
          return (token: decoded['token'] as String, expiresAt: (decoded['expiresAt'] as num?)?.toInt() ?? 0);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchFcmPublicConfig() async {
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config/fcm-public'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> registerFcmToken(String deviceToken, String platform) async {
    if (!_isOnline) return false;
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/fcm/token'),
        headers: _headers,
        body: jsonEncode({
          'deviceToken': deviceToken,
          'platform': platform,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unregisterFcmToken(String deviceToken) async {
    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/fcm/token'),
        headers: _headers,
        body: jsonEncode({
          'deviceToken': deviceToken,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAllianceSelection(String eventKey) async {
    final cacheKey = "cache_alliance_selection_$eventKey";

    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/alliance-selection?eventKey=$eventKey'), headers: _headers);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          await _store.setString(cacheKey, response.body);
          return data;
        }
      } catch (_) {}
    }

    final cached = (await _store.getString(cacheKey));
    if (cached != null && cached.isNotEmpty) {
      try {
        return await _decodeCached(cached) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  Future<ApiResponse<void>> saveAllianceSelection(String eventKey, String selectionJson) async {
    final cacheKey = "cache_alliance_selection_$eventKey";
    await _store.setString(
      cacheKey,
      jsonEncode({
        'selectionJson': selectionJson,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/alliance-selection'),
        headers: _headers,
        body: jsonEncode({
          'eventKey': eventKey,
          'selectionJson': selectionJson,
        }),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to save alliance selection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Ranked pick list plus the Do Not Pick list shared with Alliance Selection.
  /// Falls back to the last copy fetched when offline.
  Future<PickListBoard?> getPickList(String eventKey) async {
    final cacheKey = "cache_pick_list_$eventKey";

    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/alliance-selection/picklist?eventKey=${Uri.encodeQueryComponent(eventKey)}'), headers: _headers);
        if (response.statusCode == 200) {
          await _store.setString(cacheKey, response.body);
          return PickListBoard.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        }
      } catch (_) {}
    }

    final cached = await _store.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        return PickListBoard.fromJson(await _decodeCached(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  Future<ApiResponse<PickListBoard>> savePickListRanking(String eventKey, List<int> ranking) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'You are offline. Pick list changes need a connection.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/alliance-selection/picklist'),
        headers: _headers,
        body: jsonEncode({'eventKey': eventKey, 'ranking': ranking}),
      );
      final result = ApiResponse<PickListBoard>.fromHttpResponse(
        response,
        parser: (json) => PickListBoard.fromJson(json as Map<String, dynamic>),
        defaultErrorMessage: 'Failed to save pick list',
      );
      if (result.success) await _store.setString("cache_pick_list_$eventKey", response.body);
      return result;
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Adds a team to, or removes it from, the Do Not Pick list used by Alliance Selection.
  Future<ApiResponse<PickListBoard>> setDoNotPick(String eventKey, int teamNumber, bool dnp) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'You are offline. Pick list changes need a connection.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/alliance-selection/picklist/dnp'),
        headers: _headers,
        body: jsonEncode({'eventKey': eventKey, 'teamNumber': teamNumber, 'dnp': dnp}),
      );
      final result = ApiResponse<PickListBoard>.fromHttpResponse(
        response,
        parser: (json) => PickListBoard.fromJson(json as Map<String, dynamic>),
        defaultErrorMessage: 'Failed to update Do Not Pick',
      );
      if (result.success) await _store.setString("cache_pick_list_$eventKey", response.body);
      return result;
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<Map<String, int>> getCacheSummary() async {
    final Map<String, int> summary = {};
    try {
      summary.addAll(await _store.sizesWithPrefix("cache_"));
    } catch (_) {}
    return summary;
  }

  Future<List<EventModel>> fetchEvents({int? year}) async {
    final targetYear = year ?? _currentSettings?.year ?? DateTime.now().year;
    final cacheKey = "cache_events_$targetYear";

    if (_isOnline) {
      try {
        final queryParams = <String, String>{
          if (year != null) 'year': '$year',
          'cached': '1',
        };
        final uri = Uri.parse('$_currentServerUrl/api/events').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null,
        );
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          await _store.setString(cacheKey, response.body);
          await _store.setString('cache_events_all', response.body);
          return data.map((e) => EventModel.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    final cached = (await _store.getString(cacheKey)) ?? (await _store.getString('cache_events_all'));
    if (cached != null && cached.isNotEmpty) {
      try {
        final List data = await _decodeCached(cached);
        return data.map((e) => EventModel.fromJson(e)).toList();
      } catch (_) {}
    }
    return [];
  }

  Future<ApiResponse<String>> syncEvents() async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot sync events while offline');
    }

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/integrations/sync/events'),
        headers: _headers,
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String msg = 'Events synced successfully';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['message'] != null) {
            msg = decoded['message'].toString();
          }
        } catch (_) {}
        return ApiResponse.success(msg, statusCode: response.statusCode, message: msg);
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to sync events');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<bool>> createEvent(EventModel event) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot create event while offline');
    }

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/events'),
        headers: _headers,
        body: jsonEncode(event.toJson()),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(true, statusCode: response.statusCode, message: 'Event saved successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to create event');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<bool>> updateEvent({required String oldKey, required EventModel event}) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot update event while offline');
    }

    try {
      final response = await http.put(
        Uri.parse('$_currentServerUrl/api/events'),
        headers: _headers,
        body: jsonEncode({
          'oldKey': oldKey,
          'event': event.toJson(),
        }),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(true, statusCode: response.statusCode, message: 'Event updated successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update event');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<bool>> deleteEvent(String eventKey) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Cannot delete event while offline');
    }

    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/events?eventKey=$eventKey'),
        headers: _headers,
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(true, statusCode: response.statusCode, message: 'Event deleted successfully');
      }
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to delete event');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ValidationSummaryModel?> fetchValidationData({
    String? eventKey,
    double threshold = 15.0,
    bool forcePrescout = false,
  }) async {
    final effectiveEventKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (await fetchCurrentEventKey() ?? '');
    if (effectiveEventKey.isEmpty) return null;

    final cacheKey = "cache_validation_${effectiveEventKey}_${threshold}_$forcePrescout";
    final fallbackCacheKey = "cache_validation_$effectiveEventKey";

    if (_isOnline) {
      try {
        final uri = Uri.parse(
          '$_currentServerUrl/api/validation?eventKey=${Uri.encodeComponent(effectiveEventKey)}&threshold=$threshold&forcePrescout=$forcePrescout',
        );
        final response = await http.get(uri, headers: _headers);
        _checkResponseForServerError(response);
        if (response.statusCode == 200) {
          final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
          await _store.setString(cacheKey, response.body);
          await _store.setString(fallbackCacheKey, response.body);
          return ValidationSummaryModel.fromJson(jsonMap);
        }
      } catch (_) {
        _updateOnlineState(false);
      }
    }

    final cached = (await _store.getString(cacheKey)) ?? (await _store.getString(fallbackCacheKey));
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = await _decodeCached(cached) as Map<String, dynamic>;
        return ValidationSummaryModel.fromJson(jsonMap);
      } catch (_) {}
    }
    return null;
  }

  // User Session Management
  Future<List<Map<String, dynamic>>> fetchSessions() async {
    if (!_isOnline) return [];
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/user/sessions'), headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['sessions'] is List) {
          return List<Map<String, dynamic>>.from(decoded['sessions']);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<ApiResponse<void>> revokeSession(String sessionId) async {
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/user/sessions/$sessionId'),
        headers: _headers,
      );
      _checkResponse(response);
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to revoke session');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  Future<ApiResponse<void>> revokeAllOtherSessions() async {
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    try {
      final response = await http.delete(
        Uri.parse('$_currentServerUrl/api/user/sessions?othersOnly=true'),
        headers: _headers,
      );
      _checkResponse(response);
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to revoke other sessions');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Contact Form Submission
  Future<ApiResponse<void>> sendContactMessage({
    required String type,
    required String name,
    String? replyToEmail,
    required String message,
  }) async {
    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Device is offline');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/contact'),
        headers: _headers,
        body: jsonEncode({
          'type': type,
          'name': name,
          'replyToEmail': (replyToEmail != null && replyToEmail.isNotEmpty) ? replyToEmail : null,
          'message': message,
        }),
      );
      _checkResponse(response);
      return ApiResponse.fromHttpResponse(
        response,
        defaultErrorMessage: 'Failed to send contact message',
      );
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // =========================================================================
  // Cluster Management API
  // =========================================================================

  Future<ClusterNodesResponse?> fetchClusterNodes() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/admin/cluster/nodes'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return ClusterNodesResponse.fromJson(j);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<ServerLogEntry>> fetchNodeLogs(String nodeIp,
      {int limit = 500, String? filter}) async {
    if (!_isOnline) return [];
    try {
      final queryParams = {'limit': limit.toString()};
      if (filter != null && filter.isNotEmpty) queryParams['filter'] = filter;
      final uri = Uri.parse(
              '$_currentServerUrl/api/admin/cluster/nodes/${Uri.encodeComponent(nodeIp)}/logs')
          .replace(queryParameters: queryParams);
      final response =
          await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        final logs = j['logs'] as List<dynamic>? ?? [];
        return logs
            .map((e) => ServerLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<ServerLogEntry>> fetchAllClusterLogs(
      {int limit = 500, String? filter}) async {
    if (!_isOnline) return [];
    try {
      final queryParams = {'limit': limit.toString()};
      if (filter != null && filter.isNotEmpty) queryParams['filter'] = filter;
      final uri =
          Uri.parse('$_currentServerUrl/api/admin/cluster/logs-all').replace(
        queryParameters: queryParams,
      );
      final response =
          await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        final logs = j['logs'] as List<dynamic>? ?? [];
        return logs
            .map((e) => ServerLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<AppConfigPayload?> fetchNodeAppConfig(String nodeIp) async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/nodes/${Uri.encodeComponent(nodeIp)}/app-config'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return AppConfigPayload.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> saveNodeAppConfig(
      String nodeIp, String rawJson) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/nodes/${Uri.encodeComponent(nodeIp)}/app-config'),
              headers: _headers,
              body: rawJson);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> rebootNode(String nodeIp) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final url = nodeIp == 'all'
          ? '$_currentServerUrl/api/admin/cluster/reboot-all'
          : '$_currentServerUrl/api/admin/cluster/nodes/${Uri.encodeComponent(nodeIp)}/reboot';
      final response = await http
          .post(Uri.parse(url), headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> reinstallNode(String nodeIp) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final url = nodeIp == 'all'
          ? '$_currentServerUrl/api/admin/cluster/reinstall-update-all'
          : '$_currentServerUrl/api/admin/cluster/nodes/${Uri.encodeComponent(nodeIp)}/reinstall-update';
      final response = await http
          .post(Uri.parse(url), headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> regenerateKeys() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse('$_currentServerUrl/api/admin/cluster/regenerate-keys'),
              headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // Load Balancer
  Future<LoadBalancerStatus?> fetchLoadBalancerStatus() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/load-balancer/status'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return LoadBalancerStatus.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<LoadBalancerSettings?> fetchLoadBalancerSettings() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/load-balancer/settings'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return LoadBalancerSettings.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> saveLoadBalancerSettings(
      LoadBalancerSettings settings) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/load-balancer/settings'),
              headers: _headers,
              body: jsonEncode(settings.toJson()));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // Stress Test
  Future<ActionResultResponse> startStressTest() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse('$_currentServerUrl/api/admin/cluster/stress/start'),
              headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> stopStressTest() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(Uri.parse('$_currentServerUrl/api/admin/cluster/stress/stop'),
              headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<StressTestStatus?> fetchStressTestStatus() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse('$_currentServerUrl/api/admin/cluster/stress/status'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return StressTestStatus.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Node Down Alerts
  Future<NodeAlertsEnrollment?> fetchNodeAlertsEnrollment() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/notifications/enrollment'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return NodeAlertsEnrollment.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> toggleNodeAlertsEnrollment(
      bool enrolled) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/notifications/enrollment'),
              headers: _headers,
              body: jsonEncode({'enrolled': enrolled}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> sendTestNodeAlert() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/notifications/test'),
              headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // Server Error Alerts
  Future<ServerErrorAlertsSettings?> fetchErrorAlertSettings() async {
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/error-alerts'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return ServerErrorAlertsSettings.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> saveErrorAlertSettings(
      ServerErrorAlertsSettings settings) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/error-alerts'),
              headers: _headers,
              body: jsonEncode(settings.toJson()));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> sendTestErrorAlert() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/error-alerts/test'),
              headers: _headers);
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // Quorum Fallback
  Future<List<QuorumFallbackNodeStatus>> fetchQuorumFallbackStatus() async {
    if (!_isOnline) return [];
    try {
      final response = await http
          .get(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/quorum-fallback'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final list = body is List ? body : (body['nodes'] as List? ?? []);
        return list
            .map((e) => QuorumFallbackNodeStatus.fromJson(
                e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<ActionResultResponse> toggleQuorumFallback(
      String nodeIp, bool enabled) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/quorum-fallback/toggle'),
              headers: _headers,
              body: jsonEncode({'targetIp': nodeIp, 'enabled': enabled}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> purgeQuorumFallback(String nodeIp) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/quorum-fallback/purge'),
              headers: _headers,
              body: jsonEncode({'targetIp': nodeIp}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> syncQuorumFallback(String nodeIp) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/quorum-fallback/sync'),
              headers: _headers,
              body: jsonEncode({'targetIp': nodeIp}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<QuorumFallbackInspection?> inspectQuorumFallback(String nodeIp) async {
    if (!_isOnline) return null;
    try {
      final uri = Uri.parse(
              '$_currentServerUrl/api/admin/cluster/quorum-fallback/inspect')
          .replace(queryParameters: {'targetIp': nodeIp});
      final response =
          await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return QuorumFallbackInspection.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> saveQuorumFallbackConfig(
      String targetIp, QuorumFallbackConfigDetails config) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/quorum-fallback/config'),
              headers: _headers,
              body: jsonEncode(config.toJson(targetIp: targetIp)));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // Auto Backup & Snapshots
  Future<AutoBackupCombinedStatus?> fetchAutoBackupStatus() async {
    if (!_isOnline) return null;
    try {
      // 1. Fetch local node snapshots & settings
      AutoBackupNodeStatus? localStatus;
      try {
        final localResp = await http
            .get(Uri.parse('$_currentServerUrl/api/admin/snapshots'),
                headers: _headers);
        _checkResponse(localResp);
        if (localResp.statusCode == 200) {
          localStatus = AutoBackupNodeStatus.fromJson(
              jsonDecode(localResp.body) as Map<String, dynamic>);
        }
      } catch (_) {}

      // 2. Fetch cluster-wide auto backup nodes status
      List<AutoBackupNodeStatus> clusterNodes = [];
      try {
        final clusterResp = await http
            .get(Uri.parse('$_currentServerUrl/api/admin/cluster/auto-backup'),
                headers: _headers);
        _checkResponse(clusterResp);
        if (clusterResp.statusCode == 200) {
          final decoded = jsonDecode(clusterResp.body);
          final list = decoded is List
              ? decoded
              : (decoded is Map && decoded['nodes'] is List
                  ? decoded['nodes'] as List
                  : []);
          clusterNodes = list
              .map((e) =>
                  AutoBackupNodeStatus.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}

      final fallbackLocal = localStatus ??
          const AutoBackupNodeStatus(nodeIp: 'local', isLocal: true, enabled: false);

      return AutoBackupCombinedStatus(
        localNodeStatus: fallbackLocal,
        clusterNodes: clusterNodes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ActionResultResponse> saveLocalBackupConfig(
      bool enabled, int retentionDays) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse('$_currentServerUrl/api/admin/snapshots/config'),
              headers: _headers,
              body: jsonEncode({
                'enabled': enabled,
                'retentionDays': retentionDays,
              }));
      _checkResponse(response);
      if (response.statusCode == 200) {
        return const ActionResultResponse(
            success: true, message: 'Auto-backup settings saved.');
      }
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> createLocalSnapshot() async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(Uri.parse('$_currentServerUrl/api/admin/snapshots/create'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        final fn = j['fileName']?.toString() ?? 'snapshot';
        return ActionResultResponse(
            success: true, message: 'Snapshot "$fn" created successfully.');
      }
      return const ActionResultResponse(
          success: false, message: 'Failed to create snapshot.');
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> deleteSnapshot(String fileName) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .delete(
              Uri.parse(
                  '$_currentServerUrl/api/admin/snapshots/${Uri.encodeComponent(fileName)}'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        return const ActionResultResponse(
            success: true, message: 'Snapshot deleted.');
      }
      return const ActionResultResponse(
          success: false, message: 'Failed to delete snapshot.');
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> restoreSnapshot(String fileName) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/snapshots/restore/${Uri.encodeComponent(fileName)}'),
              headers: _headers);
      _checkResponse(response);
      if (response.statusCode == 200) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        final count = j['totalRecordsRestored'] ?? 0;
        return ActionResultResponse(
            success: true,
            message: 'Database restored successfully ($count records restored).');
      }
      return const ActionResultResponse(
          success: false, message: 'Failed to restore database.');
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> toggleNodeAutoBackup(
      String nodeIp, bool enabled) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/auto-backup/toggle'),
              headers: _headers,
              body: jsonEncode({'targetIp': nodeIp, 'enabled': enabled}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> saveNodeAutoBackupConfig(
      String nodeIp, int retentionDays, {bool? enabled}) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .put(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/auto-backup/config'),
              headers: _headers,
              body: jsonEncode({
                'targetIp': nodeIp,
                'retentionDays': retentionDays,
                if (enabled != null) 'enabled': enabled,
              }));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  Future<ActionResultResponse> createNodeSnapshot(String nodeIp) async {
    if (!_isOnline) {
      return const ActionResultResponse(
          success: false, message: 'Device is offline');
    }
    try {
      final response = await http
          .post(
              Uri.parse(
                  '$_currentServerUrl/api/admin/cluster/auto-backup/create'),
              headers: _headers,
              body: jsonEncode({'targetIp': nodeIp}));
      _checkResponse(response);
      return ActionResultResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return ActionResultResponse(success: false, message: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Error Reports Management — mirrors /api/admin/errors
  // ---------------------------------------------------------------------------

  Future<ReportedErrorsListResponse?> fetchReportedErrors({
    String? type,
    String? status,
    String? search,
    int limit = 500,
    int offset = 0,
  }) async {
    if (!_isOnline) return null;
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (type != null && type.isNotEmpty && type != 'ALL') {
        queryParams['type'] = type;
      }
      if (status != null && status.isNotEmpty && status != 'ALL') {
        queryParams['status'] = status;
      }
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }

      final uri = Uri.parse('$_currentServerUrl/api/admin/errors')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return ReportedErrorsListResponse.fromJson(j);
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] fetchReportedErrors error: $e');
      return null;
    }
  }

  Future<ReportedErrorStatsResponse?> fetchReportedErrorStats() async {
    if (!_isOnline) return null;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/stats');
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return ReportedErrorStatsResponse.fromJson(j);
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] fetchReportedErrorStats error: $e');
      return null;
    }
  }

  Future<bool> updateReportedErrorStatus(String id, String newStatus) async {
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/${Uri.encodeComponent(id)}/status');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'status': newStatus}),
          );
      _checkResponse(response);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] updateReportedErrorStatus error: $e');
      return false;
    }
  }

  Future<bool> deleteReportedError(String id) async {
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/${Uri.encodeComponent(id)}');
      final response = await http.delete(uri, headers: _headers);
      _checkResponse(response);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] deleteReportedError error: $e');
      return false;
    }
  }

  Future<int> updateReportedErrorGroupStatus(List<String> errorIds, String newStatus) async {
    if (!_isOnline || errorIds.isEmpty) return 0;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/group/status');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'errorIds': errorIds, 'status': newStatus}),
          );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return (j['updatedCount'] as num?)?.toInt() ?? errorIds.length;
      }
      return 0;
    } catch (e) {
      debugPrint('[ApiService] updateReportedErrorGroupStatus error: $e');
      return 0;
    }
  }

  Future<int> deleteReportedErrorGroup(List<String> errorIds) async {
    if (!_isOnline || errorIds.isEmpty) return 0;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/group/delete');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'errorIds': errorIds}),
          );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return (j['deletedCount'] as num?)?.toInt() ?? errorIds.length;
      }
      return 0;
    } catch (e) {
      debugPrint('[ApiService] deleteReportedErrorGroup error: $e');
      return 0;
    }
  }

  Future<int?> clearReportedErrors(String? statusFilter) async {
    if (!_isOnline) return null;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/admin/errors/clear');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'statusFilter': statusFilter}),
          );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return (j['clearedCount'] as num?)?.toInt() ?? 0;
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] clearReportedErrors error: $e');
      return null;
    }
  }

  // ==========================================
  // SCOUT ASSIGNMENTS API & CACHE
  // ==========================================

  // Assignments are scoped to one event: each event has its own cache entry, nothing falls back to another
  // event's list, and any row from a different event is dropped.

  String _assignmentEventKey(String? eventKey) => ((eventKey != null && eventKey.isNotEmpty)
          ? eventKey
          : (_currentSettings?.eventKey ?? ''))
      .trim()
      .toLowerCase();

  List<ScoutingAssignment> _parseEventAssignments(dynamic decoded, String eventKey) {
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['assignments'] is List ? decoded['assignments'] as List : []);
    return list
        .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
        .where((a) => a.eventKey.trim().toLowerCase() == eventKey)
        .toList();
  }

  Future<List<ScoutingAssignment>> _getCachedEventAssignments(String cachePrefix, String eventKey) async {
    if (eventKey.isEmpty) return [];
    final cached = await _getCache('$cachePrefix$eventKey');
    if (cached == null || cached.isEmpty) return [];
    try {
      final parsed = _parseEventAssignments(await _decodeCached(cached), eventKey);
      return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: eventKey);
    } catch (_) {
      return [];
    }
  }

  Future<List<ScoutingAssignment>> _fetchEventAssignments(
      String path, String cachePrefix, String eventKey, String label) async {
    if (eventKey.isEmpty) return [];
    final cachedList = await _getCachedEventAssignments(cachePrefix, eventKey);
    if (!_isOnline) return cachedList;

    try {
      final url = '$_currentServerUrl$path?eventKey=${Uri.encodeQueryComponent(eventKey)}';
      final response = await http.get(Uri.parse(url), headers: _headers);
      _checkResponse(response);

      if (response.statusCode == 200) {
        await _setCache('$cachePrefix$eventKey', response.body);
        final parsed = _parseEventAssignments(jsonDecode(response.body), eventKey);
        return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: eventKey);
      }
    } catch (e) {
      debugPrint('[ApiService] $label error: $e');
    }
    return cachedList;
  }

  Future<List<ScoutingAssignment>> getCachedMyAssignments(String? eventKey) =>
      _getCachedEventAssignments('cache_my_assignments_', _assignmentEventKey(eventKey));

  Future<List<ScoutingAssignment>> fetchMyAssignments(String? eventKey) => _fetchEventAssignments(
      '/api/assignments/my', 'cache_my_assignments_', _assignmentEventKey(eventKey), 'fetchMyAssignments');

  Future<List<ScoutingAssignment>> getCachedAllAssignments(String? eventKey) =>
      _getCachedEventAssignments('cache_all_assignments_', _assignmentEventKey(eventKey));

  Future<List<ScoutingAssignment>> fetchAllAssignments(String? eventKey) => _fetchEventAssignments(
      '/api/assignments', 'cache_all_assignments_', _assignmentEventKey(eventKey), 'fetchAllAssignments');

  Future<List<ConflictItemDto>> fetchAssignmentConflicts(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (!_isOnline) return [];

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/assignments/conflicts?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/assignments/conflicts';
      final response = await http.get(Uri.parse(url), headers: _headers);
      _checkResponse(response);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['conflicts'] is List) {
          return (decoded['conflicts'] as List)
              .map((e) => ConflictItemDto.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (decoded is List) {
          return decoded
              .map((e) => ConflictItemDto.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] fetchAssignmentConflicts error: $e');
    }
    return [];
  }

  Future<ScoutingAssignment?> createAssignment(CreateAssignmentRequest req) async {
    if (!_isOnline) throw Exception('Cannot create assignment while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(req.toJson()),
          );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        final asgnJson = (j is Map && j['assignment'] is Map)
            ? j['assignment'] as Map<String, dynamic>
            : (j is Map ? j as Map<String, dynamic> : <String, dynamic>{});
        return ScoutingAssignment.fromJson(asgnJson);
      }
      String msg = 'Failed to create assignment (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] createAssignment error: $e');
      rethrow;
    }
  }

  Future<List<ScoutingAssignment>> bulkCreateAssignments(BulkCreateAssignmentsRequest req) async {
    if (!_isOnline) throw Exception('Cannot create assignments while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/bulk');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(req.toJson()),
          )
          .timeout(_deadline(const Duration(seconds: 45)));
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        final List list = j is List
            ? j
            : (j is Map && j['assignments'] is List
                ? j['assignments'] as List
                : []);
        return list
            .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      String msg = 'Failed to create bulk assignments (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] bulkCreateAssignments error: $e');
      rethrow;
    }
  }

  Future<AutoGenerateAssignmentsResponse> autoGenerateAssignments(AutoGenerateAssignmentsRequest req) async {
    if (!_isOnline) throw Exception('Cannot generate assignments while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/auto-generate');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(req.toJson()),
          )
          .timeout(_deadline(const Duration(seconds: 45)));
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is Map<String, dynamic>) {
          return AutoGenerateAssignmentsResponse.fromJson(j);
        }
        return AutoGenerateAssignmentsResponse(
          success: true,
          createdCount: 0,
          deletedCount: 0,
          message: 'Assignments generated successfully.',
        );
      }
      String msg = 'Failed to generate assignments (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] autoGenerateAssignments error: $e');
      rethrow;
    }
  }

  Future<List<PitScoutGroup>> fetchPitScoutGroups() async {
    if (!_isOnline) return [];
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/pit-groups');
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is List) {
          return j.map((e) => PitScoutGroup.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] fetchPitScoutGroups error: $e');
    }
    return [];
  }

  Future<List<PitScoutGroup>> savePitScoutGroups(List<PitScoutGroup> groups) async {
    if (!_isOnline) throw Exception('Cannot save pit groups while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/pit-groups');
      final response = await http
          .put(
            uri,
            headers: _headers,
            body: jsonEncode({'groups': groups.map((g) => g.toJson()).toList()}),
          );
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is List) {
          return j.map((e) => PitScoutGroup.fromJson(e as Map<String, dynamic>)).toList();
        }
        return groups;
      }
      String msg = 'Failed to save pit groups (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] savePitScoutGroups error: $e');
      rethrow;
    }
  }

  Future<AssignmentShiftsResponse> fetchAssignmentShifts(String eventKey) async {
    if (!_isOnline) return AssignmentShiftsResponse();
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/shifts')
          .replace(queryParameters: {'eventKey': eventKey});
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is Map<String, dynamic>) return AssignmentShiftsResponse.fromJson(j);
      }
    } catch (e) {
      debugPrint('[ApiService] fetchAssignmentShifts error: $e');
    }
    return AssignmentShiftsResponse();
  }

  /// Creates or updates a shift. The server applies it right away to matches already synced.
  Future<AssignmentShiftsResponse> saveAssignmentShift(AssignmentShift shift) async {
    if (!_isOnline) throw Exception('Cannot save shifts while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/shifts');
      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(shift.toSaveJson()))
          .timeout(_deadline(const Duration(seconds: 45)));
      _checkResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is Map<String, dynamic>) return AssignmentShiftsResponse.fromJson(j);
        return AssignmentShiftsResponse();
      }
      throw Exception(_shiftError(response, 'Failed to save shift'));
    } catch (e) {
      debugPrint('[ApiService] saveAssignmentShift error: $e');
      rethrow;
    }
  }

  Future<void> deleteAssignmentShift(String id) async {
    if (!_isOnline) throw Exception('Cannot delete shifts while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/shifts/${Uri.encodeComponent(id)}');
      final response = await http.delete(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_shiftError(response, 'Failed to delete shift'));
      }
    } catch (e) {
      debugPrint('[ApiService] deleteAssignmentShift error: $e');
      rethrow;
    }
  }

  String _shiftError(http.Response response, String fallback) {
    try {
      final j = jsonDecode(response.body);
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  Future<AutoResolveConflictsResponse> autoResolveConflicts(String eventKey) async {
    if (!_isOnline) throw Exception('Cannot resolve conflicts while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/auto-resolve-conflicts');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'eventKey': eventKey}),
          )
          .timeout(_deadline(const Duration(seconds: 30)));
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        if (j is Map<String, dynamic>) {
          return AutoResolveConflictsResponse.fromJson(j);
        }
        return AutoResolveConflictsResponse(
          success: true,
          resolvedCount: 0,
          message: 'Conflicts resolved successfully.',
          deletedIds: [],
        );
      }
      String msg = 'Failed to resolve conflicts (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] autoResolveConflicts error: $e');
      rethrow;
    }
  }

  Future<ScoutingAssignment?> updateAssignment(String id, UpdateAssignmentRequest req) async {
    if (!_isOnline) throw Exception('Cannot update assignment while offline.');
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/$id');
      final response = await http
          .put(
            uri,
            headers: _headers,
            body: jsonEncode(req.toJson()),
          );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final j = jsonDecode(response.body);
        final asgnJson = (j is Map && j['assignment'] is Map)
            ? j['assignment'] as Map<String, dynamic>
            : (j is Map ? j as Map<String, dynamic> : <String, dynamic>{});
        return ScoutingAssignment.fromJson(asgnJson);
      }
      String msg = 'Failed to update assignment (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] updateAssignment error: $e');
      rethrow;
    }
  }

  Future<bool> updateAssignmentStatus(String id, String status) async {
    if (!_isOnline) {
      await _enqueueOutbox('assignment_status', {'id': id, 'status': status}, null, 'Offline');
      _scheduleOutboxRetry();
      return false;
    }
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/$id/status');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'status': status}),
          );
      _checkResponse(response);
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (ok) dataSyncedNotifier.value++;
      return ok;
    } catch (e) {
      debugPrint('[ApiService] updateAssignmentStatus error: $e');
      if (e is TimeoutException || e.toString().contains('SocketException') || e.toString().contains('ClientException')) {
        await _enqueueOutbox('assignment_status', {'id': id, 'status': status}, null, e.toString());
        _scheduleOutboxRetry();
      }
      return false;
    }
  }

  Future<bool> deleteAssignment(String id) async {
    if (!_isOnline) throw Exception('Cannot delete assignment while offline.');
    try {
      final cleanId = Uri.encodeComponent(id.trim());
      final uri = Uri.parse('$_currentServerUrl/api/assignments/$cleanId');
      final headers = Map<String, String>.from(_headers);
      headers['Accept'] = 'application/json, text/plain, */*';
      final response = await http.delete(uri, headers: headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      String msg = 'Failed to delete assignment (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && (j['error'] != null || j['message'] != null)) {
          msg = (j['error'] ?? j['message']).toString();
        }
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] deleteAssignment error: $e');
      rethrow;
    }
  }

  Future<bool> deleteAllAssignments(String eventKey, {List<String>? specificIds}) async {
    if (!_isOnline) throw Exception('Cannot delete assignments while offline.');
    try {
      if (specificIds != null && specificIds.isNotEmpty) {
        final uniqueIds = specificIds.toSet().toList();
        final results = await Future.wait(uniqueIds.map((id) => deleteAssignment(id)));
        return results.any((r) => r);
      }
      final cleanKey = Uri.encodeQueryComponent(eventKey.trim());
      final uri = Uri.parse('$_currentServerUrl/api/assignments?eventKey=$cleanKey');
      final headers = Map<String, String>.from(_headers);
      headers['Accept'] = 'application/json, text/plain, */*';
      final response = await http.delete(uri, headers: headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      String msg = 'Failed to delete assignments (${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && (j['error'] != null || j['message'] != null)) {
          msg = (j['error'] ?? j['message']).toString();
        }
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      debugPrint('[ApiService] deleteAllAssignments error: $e');
      rethrow;
    }
  }

  Future<bool> sendAssignmentReminder(String id) async {
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/$id/remind');
      final response = await http.post(uri, headers: _headers);
      _checkResponse(response);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] sendAssignmentReminder error: $e');
      return false;
    }
  }

  // ==========================================
  // GAMEPAD & CONTROLLER CONFIGURATIONS
  // ==========================================

  Future<List<GamepadProfile>?> fetchGamepadProfiles({bool forceRefresh = false}) async {
    const memKey = "cache_gamepad_profiles";
    if (!forceRefresh) {
      final inMem = getFromMemoryCache<List<GamepadProfile>>(memKey);
      if (inMem != null && inMem.isNotEmpty) return inMem;
    }

    if (!_isOnline) {
      if (!forceRefresh) {
        final cached = await _getCache(memKey);
        if (cached != null && cached.isNotEmpty) {
          try {
            final List list = await _decodeCached(cached);
            final res = list.map((e) => GamepadProfile.fromJson(e as Map<String, dynamic>)).toList();
            setMemoryCache(memKey, res);
            return res;
          } catch (_) {}
        }
      }
      return null;
    }

    try {
      final uri = Uri.parse('$_currentServerUrl/api/gamepad/profiles');
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300 && response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          final rawList = (decoded is Map ? decoded['profiles'] : decoded) as List<dynamic>? ?? [];
          final profiles = rawList
              .whereType<Map<String, dynamic>>()
              .map((e) => GamepadProfile.fromJson(e))
              .toList();

          await _setCache(memKey, jsonEncode(profiles.map((p) => p.toJson()).toList()));
          setMemoryCache(memKey, profiles);
          return profiles;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ApiService] fetchGamepadProfiles error: $e');
    }

    if (!forceRefresh) {
      // Fallback to cache only on non-forced error
      final cached = await _getCache(memKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final List list = await _decodeCached(cached);
          final res = list.map((e) => GamepadProfile.fromJson(e as Map<String, dynamic>)).toList();
          setMemoryCache(memKey, res);
          return res;
        } catch (_) {}
      }
    }
    return null;
  }

  Future<GamepadProfile?> saveGamepadProfile(GamepadProfile profile) async {
    if (!_isOnline) return null;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/gamepad/profiles');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(profile.toJson()),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300 && response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          final data = decoded is Map && decoded['profile'] != null ? decoded['profile'] : decoded;
          if (data is Map<String, dynamic>) {
            final saved = GamepadProfile.fromJson(data);
            invalidateMemoryCache("cache_gamepad_profiles");
            return saved;
          }
        } catch (_) {}
        return profile;
      }
    } catch (e) {
      debugPrint('[ApiService] saveGamepadProfile error: $e');
    }
    return null;
  }

  Future<bool> deleteGamepadProfile(String profileId) async {
    if (!_isOnline) return false;
    try {
      final cleanId = Uri.encodeComponent(profileId);
      final uri = Uri.parse('$_currentServerUrl/api/gamepad/profiles/$cleanId');
      final response = await http.delete(uri, headers: _headers);
      _checkResponse(response);
      invalidateMemoryCache("cache_gamepad_profiles");
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] deleteGamepadProfile error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Share Links API
  // ─────────────────────────────────────────────────────────────────────────────

  Future<ShareLinkModel?> createSharedLink(CreateShareRequest req) async {
    if (!_isOnline) return null;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/shares');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(req.toJson()),
      );
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          invalidateMemoryCache("cache_team_shares");
          return ShareLinkModel.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[ApiService] createSharedLink error: $e');
    }
    return null;
  }

  Future<List<ShareLinkModel>> getTeamSharedLinks({String? statusFilter}) async {
    if (!_isOnline) return [];
    try {
      final query = statusFilter != null && statusFilter.isNotEmpty ? '?status=${Uri.encodeComponent(statusFilter)}' : '';
      final uri = Uri.parse('$_currentServerUrl/api/shares/team$query');
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.map((item) => ShareLinkModel.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] getTeamSharedLinks error: $e');
    }
    return [];
  }

  Future<ResolvedSharePayload?> resolveSharedLink(String token, {String? pin}) async {
    try {
      final query = pin != null && pin.isNotEmpty ? '?pin=${Uri.encodeComponent(pin)}' : '';
      final uri = Uri.parse('$_currentServerUrl/api/shares/resolve/${Uri.encodeComponent(token)}$query');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return ResolvedSharePayload.fromJson(decoded);
        }
      } else if (response.statusCode == 404) {
        return null;
      } else {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return ResolvedSharePayload.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[ApiService] resolveSharedLink error: $e');
    }
    return null;
  }

  Future<ResolvedSharePayload?> verifySharedPin(String token, String pin) async {
    try {
      final uri = Uri.parse('$_currentServerUrl/api/shares/verify-pin/${Uri.encodeComponent(token)}');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'pin': pin}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return ResolvedSharePayload.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('[ApiService] verifySharedPin error: $e');
    }
    return null;
  }

  Future<bool> revokeSharedLink(String token) async {
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/shares/${Uri.encodeComponent(token)}/revoke');
      final response = await http.post(uri, headers: _headers);
      _checkResponse(response);
      invalidateMemoryCache("cache_team_shares");
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] revokeSharedLink error: $e');
      return false;
    }
  }

  Future<bool> deleteSharedLink(String token) async {
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/shares/${Uri.encodeComponent(token)}');
      final response = await http.delete(uri, headers: _headers);
      _checkResponse(response);
      invalidateMemoryCache("cache_team_shares");
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] deleteSharedLink error: $e');
      return false;
    }
  }

  /// JSON call for the screens ported straight from website pages (analytics, alliances, storage, banners, ...).
  /// They use the same endpoints and keep the server's JSON shape, so [ApiResponse.data] is the decoded body.
  /// With [cacheKey], a GET saves the body and falls back to the saved copy when offline or on failure.
  Future<ApiResponse<dynamic>> requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? cacheKey,
  }) async {
    Future<ApiResponse<dynamic>> fromCache(ApiResponse<dynamic> fallback) async {
      if (cacheKey == null) return fallback;
      final cached = await _getCache(cacheKey);
      if (cached == null || cached.isEmpty) return fallback;
      try {
        return ApiResponse.success(await _decodeCached(cached), message: 'cached');
      } catch (_) {
        return fallback;
      }
    }

    if (!_isOnline) {
      return fromCache(const ApiResponse.error(isOffline: true, message: 'You are offline.'));
    }
    try {
      var uri = Uri.parse('$_currentServerUrl$path');
      if (query != null && query.isNotEmpty) {
        uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
      }
      final encoded = body == null ? null : jsonEncode(body);
      final http.Response response;
      switch (method.toUpperCase()) {
        case 'POST':
          response = await http.post(uri, headers: _headers, body: encoded);
          break;
        case 'PUT':
          response = await http.put(uri, headers: _headers, body: encoded);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: _headers, body: encoded);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: _headers, body: encoded);
          break;
        default:
          response = await http.get(uri, headers: _headers);
      }
      _checkResponse(response);
      final result = ApiResponse<dynamic>.fromHttpResponse(response, parser: (json) => json);
      if (result.success && cacheKey != null && response.body.isNotEmpty) {
        await _setCache(cacheKey, response.body);
      }
      if (!result.success && method.toUpperCase() == 'GET') return await fromCache(result);
      return result;
    } catch (e) {
      return fromCache(ApiResponse.error(message: e.toString()));
    }
  }

  /// Downloads a file the website links to directly (CSV reports, backups). [ApiResponse.message] holds the
  /// server's file name from Content-Disposition when it sends one.
  Future<ApiResponse<Uint8List>> requestBytes(String path, {Map<String, String>? query}) async {
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'You are offline.');
    try {
      var uri = Uri.parse('$_currentServerUrl$path');
      if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
      final response = await http.get(uri, headers: _headers);
      _checkResponse(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Download failed');
      }
      final disposition = response.headers['content-disposition'] ?? '';
      final name = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition)?.group(1);
      return ApiResponse.success(response.bodyBytes, statusCode: response.statusCode, message: name);
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Sends one file as multipart/form-data (the website's FormData uploads) and returns the decoded JSON reply.
  Future<ApiResponse<dynamic>> uploadFile(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
    Map<String, String>? query,
  }) async {
    if (!_isOnline) return const ApiResponse.error(isOffline: true, message: 'You are offline.');
    try {
      var uri = Uri.parse('$_currentServerUrl$path');
      if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
      final boundary = '----obsidianscout${DateTime.now().microsecondsSinceEpoch}';
      final safeName = filename.replaceAll('"', '');
      final body = <int>[
        ...utf8.encode('--$boundary\r\n'
            'Content-Disposition: form-data; name="$field"; filename="$safeName"\r\n'
            'Content-Type: application/octet-stream\r\n\r\n'),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      final headers = Map<String, String>.of(_headers)..['Content-Type'] = 'multipart/form-data; boundary=$boundary';
      final response = await http.post(uri, headers: headers, body: body);
      _checkResponse(response);
      return ApiResponse<dynamic>.fromHttpResponse(response, parser: (json) => json, defaultErrorMessage: 'Upload failed');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }
}

enum _OutboxOutcome { uploaded, dropped, retryLater }
