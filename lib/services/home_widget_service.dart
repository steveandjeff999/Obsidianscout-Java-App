import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'api_service.dart';

/// One kind of home-screen widget: its id in the server snapshot and its Android receiver.
class HomeWidgetKind {
  final String id;
  final String androidReceiver;

  /// The widget is allowed when the user can open any of these pages (same as the server's WidgetAccess).
  final List<String> pages;

  const HomeWidgetKind(this.id, this.androidReceiver, this.pages);

  String get qualifiedAndroidName => 'com.obsidianscout.obsidianscout_app.widgets.$androidReceiver';
}

/// Where a tapped widget wants the app to go.
class WidgetLaunch {
  /// `page`, `scout`, `predictor`, `checklist` or `scan`.
  final String action;
  final Map<String, String> params;

  const WidgetLaunch(this.action, this.params);

  /// Parses `obsidianscout://widget/<action>[/<page>]?...`; null for anything else.
  static WidgetLaunch? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'obsidianscout' || uri.host != 'widget') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final params = Map<String, String>.from(uri.queryParameters);
    if (segments.first == 'page' && segments.length > 1) params['page'] = segments[1];
    return WidgetLaunch(segments.first, params);
  }
}

/// Keeps the phone's home-screen widgets in step with the app.
///
/// The widgets draw one snapshot document built by the server (`/api/widgets/snapshot`): match times already
/// adjusted for the event running ahead or behind, the next match's prediction, assignments, battery, checklist,
/// rankings and chat. Each widget is only offered to users who can open its pages (role page permissions, the
/// team's chat switch, and Non-Scouting Tools for the drive-team widgets); the snapshot says which.
///
/// While the app runs this service refreshes the snapshot after every sync. For when the app is closed it hands
/// the native widget code a read-only widget token, so the widgets can fetch the snapshot themselves on a timer
/// and when the server sends a silent refresh push. Android only; a no-op elsewhere.
class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel('obsidianscout/widgets');

  static const List<HomeWidgetKind> kinds = [
    HomeWidgetKind('next_match', 'NextMatchWidgetReceiver', ['matches']),
    HomeWidgetKind('schedule', 'ScheduleWidgetReceiver', ['matches']),
    HomeWidgetKind('predictor', 'PredictorWidgetReceiver', ['predictor']),
    HomeWidgetKind('assignments', 'AssignmentsWidgetReceiver', ['my-assignments']),
    HomeWidgetKind('battery', 'BatteryWidgetReceiver', ['battery-tracker']),
    HomeWidgetKind('checklist', 'ChecklistWidgetReceiver', ['match-checklist']),
    HomeWidgetKind('rankings', 'RankingsWidgetReceiver', ['projected-rankings']),
    HomeWidgetKind('chat', 'ChatWidgetReceiver', ['chat']),
    HomeWidgetKind('quick_actions', 'QuickActionsWidgetReceiver', ['scout', 'pit-scout', 'qual-scout', 'qr-scanner']),
  ];

  // Keys shared with the native widget code (HomeWidgetPreferences).
  static const String keySnapshot = 'snapshot_v1';
  static const String keyLocal = 'local_v1';
  static const String keyToken = 'widget_token';
  static const String keyTokenExpires = 'widget_token_expires';
  static const String keyServerUrl = 'widget_server_url';
  static const String keyRefreshRequested = 'widget_refresh_requested';

  /// Get a new widget token once the current one is this close to expiring.
  static const Duration _tokenRenewBefore = Duration(days: 23);
  static const Duration _debounce = Duration(seconds: 2);

  /// While the app is open, widgets refresh this often (the widgets also poll on their own when it's closed).
  static const Duration _openAppRefresh = Duration(seconds: 30);

  static bool get supported => !kIsWeb && Platform.isAndroid;

  ApiService? _api;
  Timer? _debounceTimer;
  Timer? _openAppTimer;
  bool _refreshing = false;
  bool _wasLoggedIn = false;
  final StreamController<WidgetLaunch> _launches = StreamController<WidgetLaunch>.broadcast();
  WidgetLaunch? _initialLaunch;

  /// Widget taps while the app is running.
  Stream<WidgetLaunch> get launches => _launches.stream;

  /// The tap that started the app, handed out once.
  WidgetLaunch? takeInitialLaunch() {
    final launch = _initialLaunch;
    _initialLaunch = null;
    return launch;
  }

  Future<void> init(ApiService api) async {
    if (!supported || _api != null) return;
    _api = api;
    _initialLaunch = WidgetLaunch.fromUri(await HomeWidget.initiallyLaunchedFromHomeWidget());
    HomeWidget.widgetClicked.listen((uri) {
      final launch = WidgetLaunch.fromUri(uri);
      if (launch != null) _launches.add(launch);
    });

    _wasLoggedIn = api.isLoggedIn;
    api.permissionsNotifier.addListener(_onAccountChanged);
    api.dataSyncedNotifier.addListener(requestRefresh);
    // Queued entries uploading (or being queued) changes both the pending count and, once uploaded, assignments.
    api.outboxCount.addListener(_writeLocalStateSoon);
    api.outboxCount.addListener(requestRefresh);
    api.localeNotifier.addListener(_writeLocalStateSoon);
    api.themeNotifier.addListener(_writeLocalStateSoon);

    _openAppTimer ??= Timer.periodic(_openAppRefresh, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && api.isLoggedIn) requestRefresh();
    });

    await _writeLocalState();
    if (api.isLoggedIn) {
      await _applyLocalAccess();
      requestRefresh();
    } else {
      await _showSignedOut();
    }
  }

  void _onAccountChanged() {
    final api = _api;
    if (api == null) return;
    final loggedIn = api.isLoggedIn;
    if (loggedIn) {
      unawaited(_applyLocalAccess().then((_) => _writeLocalState()).then((_) => _redrawAll()));
      requestRefresh();
    } else if (_wasLoggedIn) {
      unawaited(_showSignedOut());
    }
    _wasLoggedIn = loggedIn;
  }

  void _writeLocalStateSoon() => unawaited(_writeLocalState().then((_) => _redrawAll()));

  /// Refresh soon (debounced); safe to call often.
  void requestRefresh() {
    if (!supported || _api == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(refreshNow()));
  }

  Future<void> refreshNow() async {
    final api = _api;
    if (api == null || _refreshing || !api.isLoggedIn) return;
    _refreshing = true;
    try {
      await _ensureToken(api);
      final placed = await placedKinds();
      final body = await api.fetchWidgetSnapshot(placed: placed);
      if (body == null) {
        // Offline: keep the last snapshot; the widgets still count down from it.
        await _redrawAll();
        return;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return;
      await HomeWidget.saveWidgetData<String>(keySnapshot, body);
      await _writeLocalState();
      await _applyAccess(decoded['widgets']);
      await _redrawAll();
    } catch (e) {
      debugPrint('[HomeWidget] refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _ensureToken(ApiService api) async {
    final token = await HomeWidget.getWidgetData<String>(keyToken);
    final expires = await HomeWidget.getWidgetData<int>(keyTokenExpires) ?? 0;
    final storedUrl = await HomeWidget.getWidgetData<String>(keyServerUrl);
    final renewAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000).subtract(_tokenRenewBefore);
    if (token != null && token.isNotEmpty && storedUrl == api.serverUrl && DateTime.now().isBefore(renewAt)) return;

    final issued = await api.issueWidgetToken('android');
    if (issued == null) return;
    await HomeWidget.saveWidgetData<String>(keyToken, issued.token);
    await HomeWidget.saveWidgetData<int>(keyTokenExpires, issued.expiresAt);
    await HomeWidget.saveWidgetData<String>(keyServerUrl, api.serverUrl);
  }

  /// Widget kinds currently on the home screen.
  Future<List<String>> placedKinds() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      final ids = <String>{};
      for (final w in installed) {
        for (final k in kinds) {
          if (w.androidClassName == k.qualifiedAndroidName || w.androidClassName?.endsWith('.${k.androidReceiver}') == true) {
            ids.add(k.id);
          }
        }
      }
      return ids.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocalState() async {
    final api = _api;
    if (api == null) return;
    final theme = switch (api.themeNotifier.value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await HomeWidget.saveWidgetData<String>(
      keyLocal,
      jsonEncode({
        'signedIn': api.isLoggedIn,
        'pendingUploads': api.outboxCount.value,
        'locale': api.localeNotifier.value.languageCode,
        'theme': theme,
        // Used by widgets that work without a server snapshot (Quick Actions).
        'widgets': localAccess(),
        'pages': {
          if (api.isLoggedIn)
            for (final page in kinds.expand((k) => k.pages).toSet()) page: api.hasPageAccess(page),
        },
        'writtenAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }),
    );
  }

  /// Widget access worked out on the device with the app's own page rules, so the widgets appear in the picker
  /// right after sign-in even before (or without) a snapshot from the server. The server's snapshot uses the
  /// same rules and replaces this once it arrives.
  Map<String, bool> localAccess() {
    final api = _api;
    if (api == null || !api.isLoggedIn) return const {};
    return {for (final k in kinds) k.id: k.pages.any(api.hasPageAccess)};
  }

  Future<void> _applyLocalAccess() => _applyAccess(localAccess());

  /// Turns widgets on or off in the system widget picker to match what the user may have.
  Future<void> _applyAccess(dynamic widgets) async {
    final allowed = <String, bool>{
      for (final k in kinds) k.id: widgets is Map && widgets[k.id] == true,
    };
    try {
      await _channel.invokeMethod('applyAccess', {'widgets': allowed});
    } catch (e) {
      debugPrint('[HomeWidget] applyAccess failed: $e');
    }
  }

  Future<void> _showSignedOut() async {
    _debounceTimer?.cancel();
    await HomeWidget.saveWidgetData<String>(keySnapshot, jsonEncode({'v': 1, 'signedOut': true}));
    await HomeWidget.saveWidgetData<String>(keyToken, null);
    await HomeWidget.saveWidgetData<int>(keyTokenExpires, null);
    await _writeLocalState();
    // Signed out: no account, so no widget is allowed.
    await _applyAccess(const <String, bool>{});
    await _redrawAll();
  }

  static Future<void> _redrawAll() async {
    for (final k in kinds) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: k.qualifiedAndroidName);
      } catch (_) {
        // The widget is turned off for this user, so there is nothing to redraw.
      }
    }
  }

  /// From a silent `widget_refresh` push while the app is in the background or closed: ask the native widget
  /// code to fetch a new snapshot. Runs in a background isolate, so it only touches home_widget storage.
  static Future<void> handleRefreshPush() async {
    if (!supported) return;
    await HomeWidget.saveWidgetData<int>(keyRefreshRequested, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await _redrawAll();
  }
}
