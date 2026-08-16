import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';
import '../models/chat_models.dart';

class ApiService {
  static const String keyServerUrl = "obsidianscout_server_url";
  static const String keySessionCookie = "obsidianscout_session_cookie";
  static const String keyKeepMeLoggedIn = "obsidianscout_keep_me_logged_in";
  static const String keySavedUsername = "obsidianscout_saved_username";
  static const String keyThemeMode = "obsidianscout_theme_mode";
  static const String keyLocale = "obsidianscout_locale";
  static const String defaultUrl = "http://localhost:8080";

  String _currentServerUrl = defaultUrl;
  String? _sessionCookie;
  bool _keepMeLoggedIn = false;
  String _savedUsername = '';
  Timer? _syncTimer;

  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(const Locale('en'));

  bool _isOnline = true;
  Timer? _healthCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final StreamController<bool> _onlineStreamController = StreamController<bool>.broadcast();
  final StreamController<int> _serverErrorController = StreamController<int>.broadcast();

  String get serverUrl => _currentServerUrl;
  bool get isLoggedIn => _sessionCookie != null && _sessionCookie!.isNotEmpty;
  bool get keepMeLoggedIn => _keepMeLoggedIn;
  String get savedUsername => _savedUsername;
  bool get isOnline => _isOnline;
  Stream<bool> get onOnlineStatusChanged => _onlineStreamController.stream;
  Stream<int> get onServerError => _serverErrorController.stream;
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

  void _checkResponseForServerError(http.Response response) {
    if (response.statusCode >= 500) {
      _serverErrorController.add(response.statusCode);
    }
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
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    _syncTimer?.cancel();
    try {
      await http.post(
        Uri.parse('$_currentServerUrl/api/auth/logout'),
        headers: _headers,
      );
    } catch (_) {}
    _sessionCookie = null;
    _keepMeLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySessionCookie);
    await prefs.setBool(keyKeepMeLoggedIn, false);
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

  // Dropdown Data Fetching
  Future<List<TeamModel>> fetchTeams(String? eventKey) async {
    final cacheKey = "cache_teams_${eventKey ?? 'all'}";
    final cached = await _getCache(cacheKey);
    List<TeamModel> cachedList = [];
    if (cached != null && cached.isNotEmpty) {
      try {
        final List list = jsonDecode(cached);
        cachedList = list.map((item) => TeamModel.fromJson(item as Map<String, dynamic>)).toList();
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
        return list.map((item) => TeamModel.fromJson(item as Map<String, dynamic>)).toList();
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
        cachedList = list.map((item) => MatchModel.fromJson(item as Map<String, dynamic>)).toList();
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
        return list.map((item) => MatchModel.fromJson(item as Map<String, dynamic>)).toList();
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
          .get(Uri.parse('$_currentServerUrl/api/scouting?includePrescout=true'), headers: _headers)
          .timeout(const Duration(seconds: 2));
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

  // Data Submissions
  Future<bool> submitMatchScouting(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitPitScouting(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/pit-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitQualScouting(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/qual-scouting'),
        headers: _headers,
        body: jsonEncode({'data': data}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitScannedItem(String type, Map<String, dynamic> data) async {
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

    try {
      final innerData = data.containsKey('data') && data['data'] is Map<String, dynamic>
          ? data['data']
          : data;

      final response = await http.post(
        Uri.parse('$_currentServerUrl$endpoint'),
        headers: _headers,
        body: jsonEncode({'data': innerData}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
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
    if (!_isOnline) return null;
    try {
      final response = await http
          .get(Uri.parse('$_currentServerUrl/api/auth/me'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'] as Map<String, dynamic>?;
        return (user != null ? user['role'] : data['role'])?.toString().toUpperCase();
      }
    } catch (_) {}
    return null;
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

  Future<bool> saveAllianceSelection(String eventKey, String selectionJson) async {
    final cacheKey = "cache_alliance_selection_$eventKey";
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode({
        'selectionJson': selectionJson,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (!_isOnline) return true;

    try {
      final response = await http.post(
        Uri.parse('$_currentServerUrl/api/alliance-selection'),
        headers: _headers,
        body: jsonEncode({
          'eventKey': eventKey,
          'selectionJson': selectionJson,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
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
}
