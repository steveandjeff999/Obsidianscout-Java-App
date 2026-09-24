import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import '../theme/obsidian_ui_theme.dart';
import 'auth_storage_service.dart';
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

  UserModel? _currentUser;
  AppSettingsModel? _currentSettings;
  final ValueNotifier<int> permissionsNotifier = ValueNotifier<int>(0);

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

    _initConnectivityMonitor();

    ScoutHistoryService.currentAccountProvider = () => currentAccountUsername;
    ScoutHistoryService.currentAccountIdProvider = () => currentAccountId;
    unawaited(ScoutHistoryService.purgeExpiredEntries());

    if (_keepMeLoggedIn) {
      final savedCookie = prefs.getString(keySessionCookie);
      if (savedCookie != null && savedCookie.isNotEmpty) {
        _sessionCookie = savedCookie;
        final isValid = await _verifySession();
        if (!isValid) {
          _sessionCookie = null;
          await prefs.remove(keySessionCookie);
        }
      }
    }

    if (isLoggedIn) {
      unawaited(fetchCurrentUser());
      unawaited(fetchSettings());
    }

    _startBackgroundSync();
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
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkServerHealth();
    });
    checkServerHealth();
  }

  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/auth/status'), headers: _headers)
          .timeout(requestTimeout);
      final online = response.statusCode == 200 || response.statusCode == 401;
      _updateOnlineState(online);
      return online;
    } catch (_) {
      _updateOnlineState(false);
      return false;
    }
  }

  void _updateOnlineState(bool newState) {
    if (_isOnline != newState) {
      _isOnline = newState;
      _onlineStreamController.add(_isOnline);
      if (_isOnline) {
        syncAllServerDataInBackground();
      }
    }
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    syncAllServerDataInBackground();
    _syncTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      syncAllServerDataInBackground();
    });
  }

  Future<void> syncAllServerDataInBackground() async {
    if (!isLoggedIn || !_isOnline || _isSyncing) return;
    _isSyncing = true;
    try {
      await Future.wait([
        fetchCurrentUser(),
        fetchSettings(),
      ]);
      final eventKey = _currentSettings?.eventKey;
      await Future.wait([
        fetchMatchConfig(),
        fetchPitConfig(),
        fetchQualConfig(),
        fetchTeams(eventKey),
        fetchMatches(eventKey),
        fetchScoutingEntries(),
        fetchPrescoutScoutingEntries(),
        fetchPrescoutPitScoutingEntries(),
        fetchPrescoutQualScoutingEntries(),
        fetchAnalyticsWidgets(),
        fetchBanners(),
        fetchMyAssignments(eventKey),
        if (isAdmin) fetchAllAssignments(eventKey),
      ]);
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _setCache(String key, String rawJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, rawJson);
    } catch (_) {}
  }

  Future<String?> _getCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  // Instant Stale-While-Revalidate Synchronous & Async Cache Accessors
  Future<String?> getCachedEventKey() async {
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cached);
        final settings = jsonMap['settings'] ?? jsonMap;
        return settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
      } catch (_) {}
    }
    return _currentSettings?.eventKey;
  }

  Future<AppSettingsModel?> getCachedSettings() async {
    if (_currentSettings != null) return _currentSettings;
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cached);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        return _currentSettings;
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedMatchConfig() async {
    final cached = await _getCache("cache_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        return ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedPitConfig() async {
    final cached = await _getCache("cache_pit_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        return ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }
    return null;
  }

  Future<ScoutingConfigModel?> getCachedQualConfig() async {
    final cached = await _getCache("cache_qual_config");
    if (cached != null && cached.isNotEmpty) {
      try {
        return ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }
    return null;
  }

  Future<List<TeamModel>> getCachedTeams(String? eventKey) async {
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
          final decoded = jsonDecode(cached);
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
              return teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
            }
          }
        } catch (_) {}
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('cache_teams_')) {
          final val = prefs.getString(key);
          if (val != null && val.isNotEmpty) {
            final decoded = jsonDecode(val);
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
                return teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
              }
            }
          }
        }
      }
    } catch (_) {}

    return [];
  }

  Future<List<MatchModel>> getCachedMatches(String? eventKey) async {
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
          final decoded = jsonDecode(cached);
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
              return matchMap.values.toList();
            }
          }
        } catch (_) {}
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('cache_matches_')) {
          final val = prefs.getString(key);
          if (val != null && val.isNotEmpty) {
            final decoded = jsonDecode(val);
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
                return matchMap.values.toList();
              }
            }
          }
        }
      }
    } catch (_) {}

    return [];
  }

  Future<List<dynamic>> getCachedScoutingEntries() async {
    final cached = await _getCache("cache_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPitScoutingEntries() async {
    final cached = await _getCache("cache_pit_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedQualScoutingEntries() async {
    final cached = await _getCache("cache_qual_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutScoutingEntries() async {
    final cached = await _getCache("cache_prescout_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutPitScoutingEntries() async {
    final cached = await _getCache("cache_prescout_pit_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> getCachedPrescoutQualScoutingEntries() async {
    final cached = await _getCache("cache_prescout_qual_scouting");
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      } catch (_) {}
    }
    return [];
  }

  Future<List<EventModel>> getCachedEvents({int? year}) async {
    final targetYear = year ?? _currentSettings?.year ?? DateTime.now().year;
    final cached = await _getCache("cache_events_$targetYear");
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = jsonDecode(cached);
        return list.map((item) => EventModel.fromJson(item as Map<String, dynamic>)).toList();
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
          )
          .timeout(requestTimeout);
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
    _currentServerUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
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
      prefs.remove("cache_auth_me");
      prefs.setBool(keyKeepMeLoggedIn, false);
    });
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
          await Future.wait([fetchCurrentUser(), fetchSettings()]).timeout(const Duration(seconds: 3));
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
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
        unawaited(fetchCurrentUser());
        unawaited(fetchSettings());
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
    await prefs.remove("cache_auth_me");
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
      ).timeout(const Duration(seconds: 5));

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
          )
          .timeout(requestTimeout);

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
          )
          .timeout(requestTimeout);

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
          )
          .timeout(requestTimeout);

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

  // User Profile & Settings
  Future<UserModel?> fetchCurrentUser() async {
    final cached = await _getCache("cache_auth_me");
    if (cached != null && cached.isNotEmpty && _currentUser == null) {
      try {
        final jsonMap = jsonDecode(cached);
        final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : jsonMap;
        _currentUser = UserModel.fromJson(userObj);
      } catch (_) {}
    }

    if (!_isOnline) return _currentUser;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/auth/me'), headers: _headers)
          .timeout(requestTimeout);
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache("cache_auth_me", response.body);
        final jsonMap = jsonDecode(response.body);
        final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : jsonMap;
        _currentUser = UserModel.fromJson(userObj);
        permissionsNotifier.value++;
        return _currentUser;
      }
    } catch (_) {}
    return _currentUser;
  }

  Future<AppSettingsModel?> fetchSettings() async {
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty && _currentSettings == null) {
      try {
        final jsonMap = jsonDecode(cached);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        _syncObsidianTheme();
      } catch (_) {}
    }

    if (!_isOnline) return _currentSettings;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers)
          .timeout(requestTimeout);
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache("cache_settings", response.body);
        final jsonMap = jsonDecode(response.body);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        _syncObsidianTheme();
        permissionsNotifier.value++;
        return _currentSettings;
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
          final List decoded = jsonDecode(cached);
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
      final response = await http.get(uri, headers: _headers).timeout(requestTimeout);
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
          final List decoded = jsonDecode(cached);
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
      final response = await http.get(uri, headers: _headers).timeout(requestTimeout);
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
        final List decoded = jsonDecode(cached);
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
      ).timeout(requestTimeout);
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
      ).timeout(heavyRequestTimeout);
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
      ).timeout(requestTimeout);
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
        final jsonMap = jsonDecode(cached);
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
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers)
          .timeout(requestTimeout);
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
        final List list = jsonDecode(cached);
        cachedList = list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/banners'), headers: _headers)
          .timeout(requestTimeout);
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
        cachedModel = ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config'), headers: _headers)
          .timeout(requestTimeout);
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
        cachedModel = ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/pit-config'), headers: _headers)
          .timeout(requestTimeout);
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
        cachedModel = ScoutingConfigModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedModel;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/qual-config'), headers: _headers)
          .timeout(requestTimeout);
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
        final response = await http.get(Uri.parse('$_currentServerUrl$apiPath'), headers: _headers).timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/config/defaults?type=$typeParam'), headers: _headers)
          .timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/config-history?kind=$kindParam'), headers: _headers)
          .timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/config-history/$revisionId'), headers: _headers)
          .timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/config-migration/status?kind=$kindParam'), headers: _headers)
          .timeout(requestTimeout);
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

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/teams?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/teams';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
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
          return teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
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

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/matches?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/matches';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
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
        cachedPrediction = MatchPredictionResponse.fromJson(jsonDecode(cached));
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
      final response = await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
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
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          return MatchPredictionResponse.fromJson(decoded);
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
        final decoded = jsonDecode(cached);
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
      final response = await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
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
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          return decoded
              .map((item) => MatchPredictionResponse.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<List<dynamic>> fetchScoutingEntries() async {
    final cached = await _getCache("cache_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/scouting?includePrescout=true&all=true'), headers: _headers)
          .timeout(heavyRequestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPitScoutingEntries() async {
    final cached = await _getCache("cache_pit_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/pit-scouting?includePrescout=true&all=true'), headers: _headers)
          .timeout(heavyRequestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_pit_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchQualScoutingEntries() async {
    final cached = await _getCache("cache_qual_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/qual-scouting?includePrescout=true&all=true'), headers: _headers)
          .timeout(heavyRequestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_qual_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutScoutingEntries() async {
    final cached = await _getCache("cache_prescout_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/scouting'), headers: _headers)
          .timeout(requestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutPitScoutingEntries() async {
    final cached = await _getCache("cache_prescout_pit_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/pit-scouting'), headers: _headers)
          .timeout(requestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_pit_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  Future<List<dynamic>> fetchPrescoutQualScoutingEntries() async {
    final cached = await _getCache("cache_prescout_qual_scouting");
    List<dynamic> cachedEntries = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is List) cachedEntries = decoded;
        if (decoded is Map && decoded['entries'] is List) cachedEntries = decoded['entries'] as List;
      } catch (_) {}
    }

    if (!_isOnline) return cachedEntries;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/prescout/qual-scouting'), headers: _headers)
          .timeout(requestTimeout);
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_qual_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {}

    return cachedEntries;
  }

  // Data Submissions
  Future<ApiResponse<void>> submitMatchScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit match scouting');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitPrescoutMatchScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_prescout_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_prescout_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/prescout/scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit match prescout');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitPitScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_pit_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_pit_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/pit-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit pit scouting');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitPrescoutPitScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_prescout_pit_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_prescout_pit_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/prescout/pit-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit pit prescout');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitQualScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_qual_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_qual_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/qual-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit qualitative scouting');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitBatchQualScouting(List<Map<String, dynamic>> entries) async {
    try {
      final cached = await _getCache("cache_qual_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.addAll(entries);
      await _setCache("cache_qual_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/qual-scouting/batch'),
        headers: _headers,
        body: jsonEncode({'entries': entries}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit batch qualitative scouting');
      }
      // Fallback: submit individually
      for (final entry in entries) {
        await submitQualScouting(entry);
      }
      return const ApiResponse.success(null, statusCode: 200);
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

  Future<ApiResponse<void>> submitPrescoutQualScouting(Map<String, dynamic> data) async {
    try {
      final cached = await _getCache("cache_prescout_qual_scouting");
      List list = [];
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) list = decoded;
      }
      list.add(data);
      await _setCache("cache_prescout_qual_scouting", jsonEncode(list));
    } catch (_) {}

    if (!_isOnline) {
      return const ApiResponse.error(isOffline: true, message: 'Saved to offline cache. Will synchronize when online.');
    }
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/prescout/qual-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to submit qualitative prescout');
    } catch (e) {
      return const ApiResponse.error(isOffline: true, message: 'Connection error: saved to offline cache.');
    }
  }

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

    // Remove from local cache optimistically AND clear hasDiscrepancy on surviving entries
    try {
      final cacheKey = (lower == 'pit' || id.toLowerCase().startsWith('pit-'))
          ? "cache_pit_scouting"
          : (lower == 'qual' || lower == 'qualitative' || id.toLowerCase().startsWith('qual-') || id.toLowerCase().startsWith('qualitative-'))
              ? "cache_qual_scouting"
              : "cache_scouting";
      final cached = await _getCache(cacheKey);
      if (cached != null) {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          final filtered = decoded.where((e) => e is Map && e['id']?.toString() != cleanId).toList();
          // Clear hasDiscrepancy on all surviving entries (will be recalculated by server on next fetch)
          for (final e in filtered) {
            if (e is Map) {
              e['hasDiscrepancy'] = false;
            }
          }
          await _setCache(cacheKey, jsonEncode(filtered));
        }
      }
    } catch (_) {}

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

  /// Clears all 3 scouting caches so the next fetch goes to the network directly.
  /// Call this after resolving conflicts to ensure fresh data is loaded.
  Future<void> clearScoutingCaches() async {
    await _setCache('cache_scouting', '[]');
    await _setCache('cache_pit_scouting', '[]');
    await _setCache('cache_qual_scouting', '[]');
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
      return ApiResponse.fromHttpResponse(response, defaultErrorMessage: 'Failed to update scouting entry');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  // Analytics
  Future<List<AnalyticsWidgetModel>> fetchAnalyticsWidgets() async {
    final cached = await _getCache("cache_analytics");
    List<AnalyticsWidgetModel> cachedWidgets = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(cached);
        if (jsonMap['widgets'] is List) {
          cachedWidgets = (jsonMap['widgets'] as List)
              .map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedWidgets;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/analytics'), headers: _headers)
          .timeout(requestTimeout);
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
        final List list = jsonDecode(cached);
        cachedReports = list.map((e) => CustomAnalyticsReportRecord.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedReports;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/custom-analytics/reports'), headers: _headers)
          .timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/custom-analytics/reports/$id'), headers: _headers)
          .timeout(requestTimeout);
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
        cachedDataset = CustomAnalyticsDataset.fromJson(jsonDecode(cached));
      } catch (_) {}
    }

    if (!_isOnline) return cachedDataset;

    try {
      String url = '$_currentServerUrl/api/custom-analytics/dataset?includePrescout=$includePrescout';
      if (eventKey != null && eventKey.isNotEmpty) {
        url += '&eventKey=${Uri.encodeComponent(eventKey)}';
      }

      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/settings?local=true'), headers: _headers)
          .timeout(requestTimeout);
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
        final List list = jsonDecode(cached);
        cachedGroups = list.map((e) => e.toString()).toList();
        if (!cachedGroups.contains("general")) {
          cachedGroups.insert(0, "general");
        }
      } catch (_) {}
    }

    if (!_isOnline) return cachedGroups;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/groups'), headers: _headers)
          .timeout(requestTimeout);
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
        final List list = jsonDecode(cached);
        cachedList = list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/messages?group=${Uri.encodeComponent(groupName)}'), headers: _headers)
          .timeout(requestTimeout);
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
        final List list = jsonDecode(cached);
        cachedUsers = list.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedUsers;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/team-users'), headers: _headers)
          .timeout(requestTimeout);
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
          .get(Uri.parse('$_currentServerUrl/api/chat/unread-status'), headers: _headers)
          .timeout(requestTimeout);
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
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs.getKeys().where((k) => k.startsWith("cache_")).toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> fetchFcmPublicConfig() async {
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/config/fcm-public'))
          .timeout(requestTimeout);
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
    final prefs = await SharedPreferences.getInstance();

    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/alliance-selection?eventKey=$eventKey'), headers: _headers)
            .timeout(requestTimeout);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          await prefs.setString(cacheKey, response.body);
          return data;
        }
      } catch (_) {}
    }

    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        return jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  Future<ApiResponse<void>> saveAllianceSelection(String eventKey, String selectionJson) async {
    final cacheKey = "cache_alliance_selection_$eventKey";
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
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

  Future<Map<String, int>> getCacheSummary() async {
    final Map<String, int> summary = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith("cache_")) {
          final val = prefs.getString(key);
          summary[key] = val != null ? val.length : 0;
        }
      }
    } catch (_) {}
    return summary;
  }

  Future<List<EventModel>> fetchEvents({int? year}) async {
    final targetYear = year ?? _currentSettings?.year ?? DateTime.now().year;
    final cacheKey = "cache_events_$targetYear";
    final prefs = await SharedPreferences.getInstance();

    if (_isOnline) {
      try {
        final queryParams = <String, String>{
          if (year != null) 'year': '$year',
          'cached': '1',
        };
        final uri = Uri.parse('$_currentServerUrl/api/events').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null,
        );
        final response = await http.get(uri, headers: _headers).timeout(requestTimeout);
        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          await prefs.setString(cacheKey, response.body);
          await prefs.setString('cache_events_all', response.body);
          return data.map((e) => EventModel.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    final cached = prefs.getString(cacheKey) ?? prefs.getString('cache_events_all');
    if (cached != null && cached.isNotEmpty) {
      try {
        final List data = jsonDecode(cached);
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
      ).timeout(heavyRequestTimeout);
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
      ).timeout(requestTimeout);
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
      ).timeout(requestTimeout);
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
      ).timeout(requestTimeout);
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
    final prefs = await SharedPreferences.getInstance();

    if (_isOnline) {
      try {
        final uri = Uri.parse(
          '$_currentServerUrl/api/validation?eventKey=${Uri.encodeComponent(effectiveEventKey)}&threshold=$threshold&forcePrescout=$forcePrescout',
        );
        final response = await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
        _checkResponseForServerError(response);
        if (response.statusCode == 200) {
          final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
          await prefs.setString(cacheKey, response.body);
          await prefs.setString(fallbackCacheKey, response.body);
          return ValidationSummaryModel.fromJson(jsonMap);
        }
      } catch (_) {
        _updateOnlineState(false);
      }
    }

    final cached = prefs.getString(cacheKey) ?? prefs.getString(fallbackCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cached) as Map<String, dynamic>;
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
          .get(Uri.parse('$_currentServerUrl/api/user/sessions'), headers: _headers)
          .timeout(requestTimeout);
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
      ).timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
          await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
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
          await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              body: rawJson)
          .timeout(heavyRequestTimeout);
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
          .post(Uri.parse(url), headers: _headers)
          .timeout(heavyRequestTimeout);
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
          .post(Uri.parse(url), headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode(settings.toJson()))
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(requestTimeout);
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
              headers: _headers)
          .timeout(requestTimeout);
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
              body: jsonEncode({'enrolled': enrolled}))
          .timeout(requestTimeout);
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
              headers: _headers)
          .timeout(requestTimeout);
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
              headers: _headers)
          .timeout(requestTimeout);
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
              body: jsonEncode(settings.toJson()))
          .timeout(requestTimeout);
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
              headers: _headers)
          .timeout(requestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode({'targetIp': nodeIp, 'enabled': enabled}))
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode({'targetIp': nodeIp}))
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode({'targetIp': nodeIp}))
          .timeout(heavyRequestTimeout);
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
          await http.get(uri, headers: _headers).timeout(heavyRequestTimeout);
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
              body: jsonEncode(config.toJson(targetIp: targetIp)))
          .timeout(heavyRequestTimeout);
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
                headers: _headers)
            .timeout(heavyRequestTimeout);
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
                headers: _headers)
            .timeout(heavyRequestTimeout);
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
              }))
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              headers: _headers)
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode({'targetIp': nodeIp, 'enabled': enabled}))
          .timeout(heavyRequestTimeout);
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
              }))
          .timeout(heavyRequestTimeout);
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
              body: jsonEncode({'targetIp': nodeIp}))
          .timeout(heavyRequestTimeout);
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
      final response = await http.get(uri, headers: _headers).timeout(requestTimeout);
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
      final response = await http.get(uri, headers: _headers).timeout(requestTimeout);
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
          )
          .timeout(requestTimeout);
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
      final response = await http.delete(uri, headers: _headers).timeout(requestTimeout);
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
          )
          .timeout(heavyRequestTimeout);
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
          )
          .timeout(heavyRequestTimeout);
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
          )
          .timeout(heavyRequestTimeout);
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

  Future<List<ScoutingAssignment>> getCachedMyAssignments(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final candidateKeys = [
      if (effectiveKey.isNotEmpty) "cache_my_assignments_$effectiveKey",
      "cache_my_assignments_all",
      "cache_my_assignments_",
      "cache_my_assignments_current",
    ];

    for (final key in candidateKeys) {
      final cached = await _getCache(key);
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          final List list = decoded is List
              ? decoded
              : (decoded is Map && decoded['assignments'] is List
                  ? decoded['assignments'] as List
                  : []);
          if (list.isNotEmpty) {
            final parsed = list
                .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
                .toList();
            return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: effectiveKey);
          }
        } catch (_) {}
      }
    }
    return [];
  }

  Future<List<ScoutingAssignment>> fetchMyAssignments(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_my_assignments_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";
    final cachedList = await getCachedMyAssignments(effectiveKey);

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/assignments/my?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/assignments/my';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
      _checkResponse(response);

      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        await _setCache("cache_my_assignments_all", response.body);
        if (effectiveKey.isNotEmpty) {
          await _setCache("cache_my_assignments_$effectiveKey", response.body);
        }
        final decoded = jsonDecode(response.body);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['assignments'] is List
                ? decoded['assignments'] as List
                : []);
        final parsed = list
            .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
            .toList();
        return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: effectiveKey);
      }
    } catch (e) {
      debugPrint('[ApiService] fetchMyAssignments error: $e');
    }
    return cachedList;
  }

  Future<List<ScoutingAssignment>> getCachedAllAssignments(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final candidateKeys = [
      if (effectiveKey.isNotEmpty) "cache_all_assignments_$effectiveKey",
      "cache_all_assignments_all",
      "cache_all_assignments_",
      "cache_all_assignments_current",
    ];

    for (final key in candidateKeys) {
      final cached = await _getCache(key);
      if (cached != null && cached.isNotEmpty) {
        try {
          final decoded = jsonDecode(cached);
          final List list = decoded is List
              ? decoded
              : (decoded is Map && decoded['assignments'] is List
                  ? decoded['assignments'] as List
                  : []);
          if (list.isNotEmpty) {
            final parsed = list
                .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
                .toList();
            return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: effectiveKey);
          }
        } catch (_) {}
      }
    }
    return [];
  }

  Future<List<ScoutingAssignment>> fetchAllAssignments(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    final cacheKey = "cache_all_assignments_${effectiveKey.isNotEmpty ? effectiveKey : 'all'}";
    final cachedList = await getCachedAllAssignments(effectiveKey);

    if (!_isOnline) return cachedList;

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/assignments?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/assignments';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
      _checkResponse(response);

      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        await _setCache("cache_all_assignments_all", response.body);
        if (effectiveKey.isNotEmpty) {
          await _setCache("cache_all_assignments_$effectiveKey", response.body);
        }
        final decoded = jsonDecode(response.body);
        final List list = decoded is List
            ? decoded
            : (decoded is Map && decoded['assignments'] is List
                ? decoded['assignments'] as List
                : []);
        final parsed = list
            .map((e) => ScoutingAssignment.fromJson(e as Map<String, dynamic>))
            .toList();
        return await ScoutHistoryService.applyLocalScoutStatus(parsed, eventKey: effectiveKey);
      }
    } catch (e) {
      debugPrint('[ApiService] fetchAllAssignments error: $e');
    }
    return cachedList;
  }

  Future<List<ConflictItemDto>> fetchAssignmentConflicts(String? eventKey) async {
    final effectiveKey = (eventKey != null && eventKey.isNotEmpty)
        ? eventKey
        : (_currentSettings?.eventKey ?? '');
    if (!_isOnline) return [];

    try {
      final url = effectiveKey.isNotEmpty
          ? '$_currentServerUrl/api/assignments/conflicts?eventKey=$effectiveKey'
          : '$_currentServerUrl/api/assignments/conflicts';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(heavyRequestTimeout);
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
          )
          .timeout(heavyRequestTimeout);
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
          .timeout(const Duration(seconds: 45));
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
          .timeout(const Duration(seconds: 45));
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
          .timeout(const Duration(seconds: 30));
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
          )
          .timeout(heavyRequestTimeout);
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
    if (!_isOnline) return false;
    try {
      final uri = Uri.parse('$_currentServerUrl/api/assignments/$id/status');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(heavyRequestTimeout);
      _checkResponse(response);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] updateAssignmentStatus error: $e');
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
      final response = await http.delete(uri, headers: headers).timeout(heavyRequestTimeout);
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
      final response = await http.delete(uri, headers: headers).timeout(heavyRequestTimeout);
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
      final response = await http.post(uri, headers: _headers).timeout(heavyRequestTimeout);
      _checkResponse(response);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[ApiService] sendAssignmentReminder error: $e');
      return false;
    }
  }
}


