import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/config_models.dart';
import '../models/team_match_models.dart';

class ApiService {
  static const String keyServerUrl = "obsidianscout_server_url";
  static const String defaultUrl = "http://localhost:8080";

  String _currentServerUrl = defaultUrl;
  String? _sessionCookie;

  String get serverUrl => _currentServerUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentServerUrl = prefs.getString(keyServerUrl) ?? defaultUrl;
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
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Settings & Event resolution
  Future<String?> fetchCurrentEventKey() async {
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/settings'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body);
        final settings = jsonMap['settings'] ?? jsonMap;
        return settings['eventKey']?.toString() ?? settings['eventCode']?.toString();
      }
    } catch (_) {}
    return null;
  }

  // Config Fetching
  Future<ScoutingConfigModel?> fetchMatchConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/config'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ScoutingConfigModel?> fetchPitConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/pit-config'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<ScoutingConfigModel?> fetchQualConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/qual-config'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return ScoutingConfigModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  // Dropdown Data Fetching
  Future<List<TeamModel>> fetchTeams(String? eventKey) async {
    try {
      final url = eventKey != null && eventKey.isNotEmpty
          ? '$_currentServerUrl/api/teams?eventKey=$eventKey'
          : '$_currentServerUrl/api/teams';
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => TeamModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<MatchModel>> fetchMatches(String? eventKey) async {
    try {
      final url = eventKey != null && eventKey.isNotEmpty
          ? '$_currentServerUrl/api/matches?eventKey=$eventKey'
          : '$_currentServerUrl/api/matches';
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => MatchModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
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

  // Analytics
  Future<List<AnalyticsWidgetModel>> fetchAnalyticsWidgets() async {
    try {
      final response = await http.get(
        Uri.parse('$_currentServerUrl/api/analytics'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = jsonDecode(response.body);
        if (jsonMap['widgets'] is List) {
          return (jsonMap['widgets'] as List)
              .map((w) => AnalyticsWidgetModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }
}
