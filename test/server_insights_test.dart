import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/server_analytics_models.dart';
import 'package:obsidianscout_app/screens/server_insights_screen.dart';
import 'package:obsidianscout_app/screens/settings_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/shell/shell_screen_registry.dart';

ServerAnalyticsOverview _overview(String ip, {bool healthy = true}) =>
    ServerAnalyticsOverview.fromJson({
      'nodeIp': ip,
      'timestamp': 1700000000000,
      'dbPool': {
        'isHealthy': healthy,
        'activeConnections': 64,
        'maxPoolSize': 64,
        'saturationPercent': 100.0,
        'threadsAwaiting': healthy ? 0 : 9,
        'engineType': 'cockroach/postgres',
      },
      'webSockets': {'churnRatePerMinute': healthy ? 1 : 99},
      'clientFleet': {
        'totalActiveDevices': 2,
        'avgIngestLagMs': healthy ? 10 : 90000,
        'clientsByPlatform': {'Android': 1, 'iOS': 1},
        'clientsByVersion': {'1.2.2.2': 2},
      },
      'jvm': {'usedHeapMb': 512, 'maxHeapMb': 2048},
      'latency': {'p95Ms': 19.5},
      'security': {
        'failedLoginsLastHour': 7,
        'rateLimitHitsLastHour': 1,
        'recentAuditLogs': [
          {
            'id': 'a',
            'timestamp': 1700000000000,
            'action': 'ADMIN_ACTION',
            'username': 'a_rather_long_superadmin_username',
            'role': 'SUPERADMIN',
            'ipAddress': '100.64.0.1',
            'details': 'POST /api/admin/cluster/nodes/restart',
            'success': true,
          }
        ],
      },
    });

class _FakeApi extends ApiService {
  final ClusterAnalyticsOverview? cluster;
  final String? dump;
  final List<String?> dumpNodes = [];

  _FakeApi({this.cluster, this.dump = 'THREAD-DUMP-BODY', String role = 'SUPERADMIN'}) {
    setCachedUserForTesting(
        UserModel(id: '1', username: 'root', teamNumber: 1234, role: role));
  }

  @override
  Future<ClusterAnalyticsOverview?> fetchServerAnalyticsOverview() async =>
      cluster;

  @override
  Future<String?> fetchServerThreadDump({String? nodeIp}) async {
    dumpNodes.add(nodeIp);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return dump;
  }
}

ClusterAnalyticsOverview _twoNodes({bool healthy = true}) =>
    ClusterAnalyticsOverview(
      combined: _overview('all', healthy: healthy),
      nodes: [_overview('100.64.0.5'), _overview('100.64.0.6')],
    );

Future<void> _pump(WidgetTester tester, ApiService api,
    {Size size = const Size(1400, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ServerInsightsScreen(apiService: api)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Removes the screen so its refresh timer doesn't outlive the test.
Future<void> _finish(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Server Analytics & Insights Models Test', () {
    test('ServerAnalyticsOverview reads every section from JSON', () {
      final json = {
        'nodeIp': '100.64.0.5',
        'timestamp': 1700000000000,
        'dbPool': {
          'activeConnections': 8,
          'idleConnections': 56,
          'threadsAwaiting': 0,
          'totalConnections': 64,
          'maxPoolSize': 64,
          'minIdle': 64,
          'saturationPercent': 12.5,
          'isHealthy': true,
          'engineType': 'cockroach/postgres',
        },
        'webSockets': {
          'activeConnections': 18,
          'connectedUsers': 14,
          'connectsLastMinute': 3,
          'disconnectsLastMinute': 2,
          'churnRatePerMinute': 5,
          'totalTopicBroadcasts': 1250,
          'droppedBroadcasts': 0,
        },
        'clientFleet': {
          'totalActiveDevices': 25,
          'clientsByPlatform': {
            'Android': 15,
            'iOS': 6,
            'Windows': 4,
          },
          'clientsByVersion': {
            '1.2.2.2': 20,
            '1.2.1.0': 5,
          },
          'avgIngestLagMs': 120,
          'maxIngestLagMs': 1450,
          'syncSubmissionsCount': 89,
        },
        'jvm': {
          'usedHeapMb': 512,
          'maxHeapMb': 2048,
          'heapUsagePercent': 25.0,
          'nonHeapUsedMb': 128,
          'gcCount': 42,
          'gcTimeMs': 310,
          'liveThreads': 48,
          'peakThreads': 64,
          'daemonThreads': 18,
          'uptimeSeconds': 86400,
        },
        'latency': {
          'p50Ms': 4.2,
          'p90Ms': 12.8,
          'p95Ms': 19.5,
          'p99Ms': 48.0,
          'maxMs': 115.0,
          'requestsPerSecond': 14.5,
          'sampleCount': 850,
          'totalRequests': 125000,
          'error4xxCount': 12,
          'error5xxCount': 1,
        },
        'security': {
          'failedLoginsLastHour': 2,
          'rateLimitHitsLastHour': 0,
          'recentAuditLogs': [
            {
              'id': 'audit-1',
              'timestamp': 1700000000000,
              'action': 'ADMIN_ACTION',
              'username': 'root',
              'role': 'SUPERADMIN',
              'ipAddress': '100.64.0.1',
              'details': 'POST /api/admin/storage/reclaim',
              'success': true,
            }
          ]
        }
      };

      final overview = ServerAnalyticsOverview.fromJson(json);

      expect(overview.nodeIp, '100.64.0.5');
      expect(overview.timestamp, 1700000000000);
      expect(overview.dbPool.maxPoolSize, 64);
      expect(overview.dbPool.saturationPercent, 12.5);
      expect(overview.dbPool.engineType, 'cockroach/postgres');
      expect(overview.webSockets.connectedUsers, 14);
      expect(overview.clientFleet.clientsByPlatform['Android'], 15);
      expect(overview.clientFleet.clientsByVersion['1.2.2.2'], 20);
      expect(overview.jvm.heapUsagePercent, 25.0);
      expect(overview.latency.p99Ms, 48.0);
      expect(overview.latency.totalRequests, 125000);
      expect(overview.security.recentAuditLogs.first.action, 'ADMIN_ACTION');
    });

    test('ClusterAnalyticsOverview reads the combined view and each node', () {
      final cluster = ClusterAnalyticsOverview.fromJson(jsonDecode('''{
        "combined": {"nodeIp": "all"},
        "nodes": [{"nodeIp": "100.64.0.5"}, {"nodeIp": "100.64.0.6"}],
        "unreachableNodes": ["100.64.0.7"]
      }''') as Map<String, dynamic>);

      expect(cluster.combined?.nodeIp, 'all');
      expect(cluster.nodes.map((n) => n.nodeIp), ['100.64.0.5', '100.64.0.6']);
      expect(cluster.unreachableNodes, ['100.64.0.7']);
    });

    test('a cluster with no answering node has nothing combined', () {
      final cluster = ClusterAnalyticsOverview.fromJson(
          const {'unreachableNodes': <dynamic>[]});

      expect(cluster.combined, isNull);
      expect(cluster.nodes, isEmpty);
    });
  });

  group('Server Insights access', () {
    test('it is on the superadmin-only list', () {
      expect(superAdminOnlyPages, contains('server-insights'));
    });

    test('only SUPERADMIN gets the page', () {
      final api = ApiService();
      for (final role in ['ADMIN', 'ANALYTICS', 'SCOUT', 'VIEWER', 'CUSTOM']) {
        api.setCachedUserForTesting(
            UserModel(id: '1', username: 'u', teamNumber: 1, role: role));
        expect(api.hasPageAccess('server-insights'), isFalse, reason: role);
      }
      api.setCachedUserForTesting(
          UserModel(id: '1', username: 'u', teamNumber: 1, role: 'SUPERADMIN'));
      expect(api.hasPageAccess('server-insights'), isTrue);
    });

    testWidgets('ServerInsightsScreen blocks non-superadmins gracefully',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServerInsightsScreen(
              apiService: ApiService(),
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Superadmin Access Required'), findsOneWidget);
      expect(
        find.text(
            'Server Analytics & Telemetry is strictly restricted to system superadministrators.'),
        findsOneWidget,
      );
    });

    testWidgets('an ADMIN never reaches the telemetry', (tester) async {
      final api = _FakeApi(cluster: _twoNodes(), role: 'ADMIN');

      await _pump(tester, api);

      expect(find.text('Superadmin Access Required'), findsOneWidget);
      expect(find.text('Overview'), findsNothing);
      await _finish(tester);
    });
  });

  group('Server Insights navigation', () {
    Widget screenAt(int index, void Function(int) onNavigate) =>
        ShellScreenRegistry.buildScreenByIndex(
          screenIndex: index,
          apiService: ApiService(),
          isTabActive: true,
          currentIndex: index,
          isBarsVisible: true,
          onNavigateScreen: onNavigate,
          onLogout: () async {},
          onOpenQrScanner: () {},
          onNavigateToMatchScout: (
              {matchKey, matchNumber, targetTeamNumber, sourceAssignmentId}) {},
          onNavigateToPitScout: ({targetTeamNumber, sourceAssignmentId}) {},
          onNavigateToQualScout: (
              {allianceColor,
              matchKey,
              matchNumber,
              sourceAssignmentId,
              targetTeamNumber}) {},
        );

    test('ShellScreenRegistry registers case 53 as ServerInsightsScreen', () {
      expect(ShellScreenRegistry.screenCount, 54);
      expect(ShellScreenRegistry.getPageIdForIndex(53), 'server-insights');
      expect(ShellScreenRegistry.titleKeys, contains('nav.server_insights'));
      expect(screenAt(53, (_) {}), isA<ServerInsightsScreen>());
    });

    test('the Settings card opens the screen', () {
      final opened = <int>[];

      final settings = screenAt(5, opened.add) as SettingsScreen;
      settings.onNavigateServerInsights!();

      expect(opened, [53]);
    });

    test('every language names the screen', () {
      for (final lang in ['en', 'es', 'tr', 'he']) {
        final strings = jsonDecode(
                File('assets/i18n/$lang.json').readAsStringSync())
            as Map<String, dynamic>;
        expect(strings['nav.server_insights'], isNotNull, reason: lang);
        expect(strings['subtitle.server_insights'], isNotNull, reason: lang);
      }
    });

    test('the screen uses no emoji', () {
      final source =
          File('lib/screens/server_insights_screen.dart').readAsStringSync();
      expect(source, isNot(contains('⚠')));
      expect(source, isNot(contains('✅')));
    });
  });

  group('Server Insights screen', () {
    testWidgets('the thread dump shows on first open, without a manual refresh',
        (tester) async {
      await _pump(tester, _FakeApi(cluster: _twoNodes()));
      await tester.tap(find.text('JVM & Latency'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Live Thread Dump'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('THREAD-DUMP-BODY'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _finish(tester);
    });

    testWidgets('a failed thread dump says so rather than spinning',
        (tester) async {
      await _pump(tester, _FakeApi(cluster: _twoNodes(), dump: null));
      await tester.tap(find.text('JVM & Latency'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Live Thread Dump'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No thread dump available.'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('picking a node shows its figures and asks it for the dump',
        (tester) async {
      final api = _FakeApi(cluster: _twoNodes());
      await _pump(tester, api);

      await tester.tap(find.text('All nodes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100.64.0.6').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('JVM & Latency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Live Thread Dump'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.dumpNodes, ['100.64.0.6']);
      await tester.pump(const Duration(milliseconds: 300));
      await _finish(tester);
    });

    testWidgets('a single server has no node picker', (tester) async {
      await _pump(
          tester,
          _FakeApi(
              cluster: ClusterAnalyticsOverview(
                  combined: _overview('all'),
                  nodes: [_overview('100.64.0.5')])));

      expect(find.byType(DropdownButton<String>), findsNothing);
      await _finish(tester);
    });

    testWidgets('unreachable nodes are called out', (tester) async {
      await _pump(
          tester,
          _FakeApi(
              cluster: ClusterAnalyticsOverview(
                  combined: _overview('all'),
                  nodes: [_overview('100.64.0.5')],
                  unreachableNodes: const ['100.64.0.9'])));

      expect(find.textContaining('100.64.0.9'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('no answer from the server shows the error view',
        (tester) async {
      await _pump(tester, _FakeApi());

      expect(find.text('Telemetry Unavailable'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('warnings use icons and no tab overflows at phone width',
        (tester) async {
      final problems = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError =
          (details) => problems.add(details.exceptionAsString());
      addTearDown(() => FlutterError.onError = previous);

      await _pump(tester, _FakeApi(cluster: _twoNodes(healthy: false)),
          size: const Size(320, 700));

      for (final tab in [
        'Overview',
        'Database Pool',
        'WebSockets',
        'Fleet & Sync',
        'JVM & Latency',
        'Security & Audit',
      ]) {
        await tester.ensureVisible(find.text(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      await _finish(tester);
      expect(problems, isEmpty);
    });
  });
}
