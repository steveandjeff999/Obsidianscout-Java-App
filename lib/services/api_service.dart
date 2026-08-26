import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_response.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../models/chat_models.dart';
import '../models/validation_models.dart';

class ApiService {
  static const String keyServerUrl = "obsidianscout_server_url";
  static const String keySessionCookie = "obsidianscout_session_cookie";
  static const String keyKeepMeLoggedIn = "obsidianscout_keep_me_logged_in";
  static const String keySavedUsername = "obsidianscout_saved_username";
  static const String keyThemeMode = "obsidianscout_theme_mode";
  static const String keyLocale = "obsidianscout_locale";
  static const String defaultUrl = "https://kotlin.obsidianscout.com";

  String _currentServerUrl = defaultUrl;
  String? _sessionCookie;
  bool _keepMeLoggedIn = false;
  String _savedUsername = '';
  Timer? _syncTimer;

  UserModel? _currentUser;
  AppSettingsModel? _currentSettings;
  final ValueNotifier<int> permissionsNotifier = ValueNotifier<int>(0);

  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(const Locale('en'));

  bool _isOnline = true;
  bool _handlingRevocation = false;
  Timer? _healthCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final StreamController<bool> _onlineStreamController = StreamController<bool>.broadcast();
  final StreamController<int> _serverErrorController = StreamController<int>.broadcast();
  final StreamController<String> _sessionRevokedController = StreamController<String>.broadcast();

  String get serverUrl => _currentServerUrl;
  bool get isLoggedIn => _sessionCookie != null && _sessionCookie!.isNotEmpty;
  bool get keepMeLoggedIn => _keepMeLoggedIn;
  String get savedUsername => _savedUsername;
  UserModel? get currentUser => _currentUser;
  AppSettingsModel? get currentSettings => _currentSettings;
  String get currentUserRole => _currentUser?.role ?? 'SCOUT';
  String get currentProgram => _currentUser?.program ?? _currentSettings?.program ?? 'FRC';
  bool get isOnline => _isOnline;
  Stream<bool> get onOnlineStatusChanged => _onlineStreamController.stream;
  Stream<int> get onServerError => _serverErrorController.stream;
  Stream<String> get onSessionRevoked => _sessionRevokedController.stream;
  ThemeMode get themeMode => themeNotifier.value;
  Locale get currentLocale => localeNotifier.value;

  Future<void> setThemeMode(ThemeMode mode) async {
    themeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyThemeMode, mode.name);
  }

  Future<void> setLocale(Locale locale) async {
    localeNotifier.value = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLocale, locale.languageCode);
  }

  @visibleForTesting
  void setCachedUserForTesting(UserModel? user) {
    _currentUser = user;
    permissionsNotifier.value++;
  }

  @visibleForTesting
  void setCachedSettingsForTesting(AppSettingsModel? settings) {
    _currentSettings = settings;
    permissionsNotifier.value++;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentServerUrl = prefs.getString(keyServerUrl) ?? defaultUrl;
    _keepMeLoggedIn = prefs.getBool(keyKeepMeLoggedIn) ?? false;
    _savedUsername = prefs.getString(keySavedUsername) ?? '';

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

    _initConnectivityMonitor();

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
          .timeout(const Duration(milliseconds: 1200));
      final online = response.statusCode == 200;
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
      await fetchCurrentUser();
      await Future.delayed(const Duration(milliseconds: 100));
      await fetchSettings();
      await Future.delayed(const Duration(milliseconds: 100));
      final eventKey = await fetchCurrentEventKey();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchMatchConfig();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchPitConfig();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchQualConfig();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchTeams(eventKey);
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchMatches(eventKey);
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchScoutingEntries();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchPrescoutScoutingEntries();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchPrescoutPitScoutingEntries();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchPrescoutQualScoutingEntries();
      await Future.delayed(const Duration(milliseconds: 150));
      await fetchAnalyticsWidgets();
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

  Future<bool> _verifySession() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_currentServerUrl/api/auth/status'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _updateCookiesFromResponse(response);
        return true;
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
        ...?_sessionCookie == null ? null : {'Cookie': _sessionCookie!},
      };

  void _handleUnauthorized([String reason = 'Session has been revoked']) {
    if (_handlingRevocation || !isLoggedIn) return;
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

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      _handleUnauthorized('Session has been revoked');
    } else if (response.statusCode >= 500) {
      _serverErrorController.add(response.statusCode);
    }
  }

  void _checkResponseForServerError(http.Response response) {
    _checkResponse(response);
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
        if (value.isNotEmpty && value != 'deleted') {
          cookieMap[name] = value;
        }
      }
    }

    if (cookieMap.isNotEmpty) {
      _sessionCookie = cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
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
        _handlingRevocation = false;
        _updateCookiesFromResponse(response);
        _keepMeLoggedIn = keepMeLoggedIn;
        _savedUsername = username;

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
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> register(
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
        _handlingRevocation = false;
        _updateCookiesFromResponse(response);
        _keepMeLoggedIn = keepMeLoggedIn;
        _savedUsername = username;

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
        return true;
      }
      return false;
    } catch (e) {
      return false;
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
    _keepMeLoggedIn = false;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySessionCookie);
    await prefs.remove("cache_auth_me");
    await prefs.setBool(keyKeepMeLoggedIn, false);
    permissionsNotifier.value++;
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
          .timeout(const Duration(seconds: 4));
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache("cache_auth_me", response.body);
        final jsonMap = jsonDecode(response.body);
        final userObj = jsonMap['user'] is Map ? (jsonMap['user'] as Map<String, dynamic>) : jsonMap;
        _currentUser = UserModel.fromJson(userObj);
        permissionsNotifier.value++;
        return _currentUser;
      }
    } catch (_) {
      _updateOnlineState(false);
    }
    return _currentUser;
  }

  Future<AppSettingsModel?> fetchSettings() async {
    final cached = await _getCache("cache_settings");
    if (cached != null && cached.isNotEmpty && _currentSettings == null) {
      try {
        final jsonMap = jsonDecode(cached);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
      } catch (_) {}
    }

    if (!_isOnline) return _currentSettings;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers)
          .timeout(const Duration(seconds: 4));
      _checkResponse(response);
      if (response.statusCode == 200) {
        await _setCache("cache_settings", response.body);
        final jsonMap = jsonDecode(response.body);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        permissionsNotifier.value++;
        return _currentSettings;
      }
    } catch (_) {
      _updateOnlineState(false);
    }
    return _currentSettings;
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

    // Resolve aliases
    final candidatePages = <String>[pageId];
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

    // Dynamic role permissions from team settings
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
    final cached = await _getCache("cache_settings");
    String? cachedEventKey;
    if (cached != null && cached.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(cached);
        final settings = jsonMap['settings'] ?? jsonMap;
        cachedEventKey = settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
      } catch (_) {}
    }

    if (!_isOnline) return cachedEventKey;

    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/settings'), headers: _headers)
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_settings", response.body);
        final jsonMap = jsonDecode(response.body);
        _currentSettings = AppSettingsModel.fromJson(jsonMap);
        final settings = jsonMap['settings'] ?? jsonMap;
        return settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
      }
    } catch (_) {
      _updateOnlineState(false);
    }
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
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        await _setCache("cache_banners", response.body);
        final List list = jsonDecode(response.body);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {
      _updateOnlineState(false);
    }
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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_pit_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_qual_config", response.body);
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
        final response = await http.get(Uri.parse('$_currentServerUrl$apiPath'), headers: _headers).timeout(const Duration(seconds: 2));
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
          .timeout(const Duration(seconds: 3));
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
          .timeout(const Duration(seconds: 3));
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
          .timeout(const Duration(seconds: 3));
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
          .timeout(const Duration(seconds: 4));
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
    final cacheKey = "cache_teams_${eventKey ?? 'all'}";
    final cached = await _getCache(cacheKey);
    List<TeamModel> cachedList = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = jsonDecode(cached);
        final Map<int, TeamModel> teamMap = {};
        for (var item in list) {
          final t = TeamModel.fromJson(item as Map<String, dynamic>);
          teamMap[t.teamNumber] = t;
        }
        cachedList = teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final url = eventKey != null && eventKey.isNotEmpty
          ? '$_currentServerUrl/api/teams?eventKey=$eventKey'
          : '$_currentServerUrl/api/teams';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final List list = jsonDecode(response.body);
        final Map<int, TeamModel> teamMap = {};
        for (var item in list) {
          final t = TeamModel.fromJson(item as Map<String, dynamic>);
          teamMap[t.teamNumber] = t;
        }
        return teamMap.values.toList()..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
      }
    } catch (_) {
      _updateOnlineState(false);
    }

    return cachedList;
  }

  Future<List<MatchModel>> fetchMatches(String? eventKey) async {
    final cacheKey = "cache_matches_${eventKey ?? 'all'}";
    final cached = await _getCache(cacheKey);
    List<MatchModel> cachedList = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = jsonDecode(cached);
        final Map<String, MatchModel> matchMap = {};
        for (var item in list) {
          final m = MatchModel.fromJson(item as Map<String, dynamic>);
          if (m.matchKey.isNotEmpty) {
            matchMap[m.matchKey] = m;
          }
        }
        cachedList = matchMap.values.toList();
      } catch (_) {}
    }

    if (!_isOnline) return cachedList;

    try {
      final url = eventKey != null && eventKey.isNotEmpty
          ? '$_currentServerUrl/api/matches?eventKey=$eventKey'
          : '$_currentServerUrl/api/matches';
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final List list = jsonDecode(response.body);
        final Map<String, MatchModel> matchMap = {};
        for (var item in list) {
          final m = MatchModel.fromJson(item as Map<String, dynamic>);
          if (m.matchKey.isNotEmpty) {
            matchMap[m.matchKey] = m;
          }
        }
        return matchMap.values.toList();
      }
    } catch (_) {
      _updateOnlineState(false);
    }

    return cachedList;
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
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        await _setCache("cache_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        await _setCache("cache_pit_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        await _setCache("cache_qual_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_pit_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_prescout_qual_scouting", response.body);
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map && decoded['entries'] is List) return decoded['entries'] as List;
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_analytics", response.body);
        final Map<String, dynamic> jsonMap = jsonDecode(response.body);
        if (jsonMap['widgets'] is List) {
          return (jsonMap['widgets'] as List)
              .map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {
      _updateOnlineState(false);
    }

    return cachedWidgets;
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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body);
        final settings = jsonMap['settings'] ?? jsonMap;
        final enabled = settings['chatEnabled'] != false;
        await _setCache("cache_chat_enabled", enabled ? "true" : "false");
        return enabled;
      }
    } catch (_) {
      _updateOnlineState(false);
    }
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
          .timeout(const Duration(seconds: 2));
      _checkResponseForServerError(response);
      if (response.statusCode == 200) {
        await _setCache("cache_chat_groups", response.body);
        final List list = jsonDecode(response.body);
        final set = <String>{"general", ...list.map((e) => e.toString())};
        return set.toList();
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      _checkResponseForServerError(response);
      if (response.statusCode == 200) {
        await _setCache(cacheKey, response.body);
        final List list = jsonDecode(response.body);
        return list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      _updateOnlineState(false);
    }

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
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        await _setCache("cache_chat_team_users", response.body);
        final List list = jsonDecode(response.body);
        final filtered = list.map((e) => e.toString()).where((u) => u.toLowerCase() != "deleted user").toList();
        final set = <String>{"everyone", "channel", ...filtered};
        return set.toList();
      }
    } catch (_) {
      _updateOnlineState(false);
    }

    return cachedUsers;
  }

  Future<Map<String, ChatGroupUnreadModel>> fetchChatUnreadStatus() async {
    if (!_isOnline) return {};
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/chat/unread-status'), headers: _headers)
          .timeout(const Duration(seconds: 2));
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
          .timeout(const Duration(seconds: 3));
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
            .timeout(const Duration(seconds: 4));
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
    final targetYear = year ?? DateTime.now().year;
    final cacheKey = "cache_events_$targetYear";
    final prefs = await SharedPreferences.getInstance();

    if (_isOnline) {
      try {
        final response = await http
            .get(Uri.parse('$_currentServerUrl/api/events?year=$targetYear&cached=1'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          await prefs.setString(cacheKey, response.body);
          return data.map((e) => EventModel.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final List data = jsonDecode(cached);
        return data.map((e) => EventModel.fromJson(e)).toList();
      } catch (_) {}
    }
    return [];
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
        final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
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
          .timeout(const Duration(seconds: 4));
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
}
