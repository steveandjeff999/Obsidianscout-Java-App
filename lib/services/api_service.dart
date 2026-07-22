import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';

class ApiService {
  static const String keyServerUrl = "obsidianscout_server_url";
  static const String keySessionCookie = "obsidianscout_session_cookie";
  static const String keyKeepMeLoggedIn = "obsidianscout_keep_me_logged_in";
  static const String keySavedUsername = "obsidianscout_saved_username";
  static const String defaultUrl = "http://localhost:8080";

  String _currentServerUrl = defaultUrl;
  String? _sessionCookie;
  bool _keepMeLoggedIn = false;
  String _savedUsername = '';
  Timer? _syncTimer;

  bool _isOnline = true;
  Timer? _healthCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final StreamController<bool> _onlineStreamController = StreamController<bool>.broadcast();

  String get serverUrl => _currentServerUrl;
  bool get isLoggedIn => _sessionCookie != null && _sessionCookie!.isNotEmpty;
  bool get keepMeLoggedIn => _keepMeLoggedIn;
  String get savedUsername => _savedUsername;
  bool get isOnline => _isOnline;
  Stream<bool> get onOnlineStatusChanged => _onlineStreamController.stream;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentServerUrl = prefs.getString(keyServerUrl) ?? defaultUrl;
    _keepMeLoggedIn = prefs.getBool(keyKeepMeLoggedIn) ?? false;
    _savedUsername = prefs.getString(keySavedUsername) ?? '';

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
      return response.statusCode == 200;
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
        ...?_sessionCookie == null ? null : {'Cookie': _sessionCookie!},
      };

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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'teamNumber': teamNumber,
          'program': program,
          'password': password,
          'keepMeLoggedIn': keepMeLoggedIn,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        final rawCookie = response.headers['set-cookie'];
        _sessionCookie = rawCookie?.split(';').first;
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
        headers: {'Content-Type': 'application/json'},
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
        final rawCookie = response.headers['set-cookie'];
        _sessionCookie = rawCookie?.split(';').first;
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

  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs.getKeys().where((k) => k.startsWith("cache_")).toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (_) {}
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
}
