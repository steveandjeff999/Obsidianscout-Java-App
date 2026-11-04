import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/cluster_models.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/shell/shell_screen_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Load Profiler Models Serialization & Deserialization', () {
    test('LoadMinute round-trips from JSON correctly', () {
      final json = {
        'minute': 1700000000000,
        'requests': 150,
        'liveRequests': 50,
        'serverMs': 320.5,
        'liveServerMs': 90.2,
        'bytes': 102400,
        'liveBytes': 20480,
        'errors': 2,
        'invalidations': 5,
        'usersReached': 12,
      };

      final minute = LoadMinute.fromJson(json);
      expect(minute.minute, 1700000000000);
      expect(minute.requests, 150);
      expect(minute.liveRequests, 50);
      expect(minute.serverMs, 320.5);
      expect(minute.liveServerMs, 90.2);
      expect(minute.bytes, 102400);
      expect(minute.liveBytes, 20480);
      expect(minute.errors, 2);
      expect(minute.invalidations, 5);
      expect(minute.usersReached, 12);
    });

    test('LoadRoute round-trips from JSON correctly', () {
      final json = {
        'route': '/api/matches',
        'requests': 400,
        'liveRequests': 100,
        'serverMs': 1200.0,
        'maxMs': 45.2,
        'bytes': 50000,
      };

      final route = LoadRoute.fromJson(json);
      expect(route.route, '/api/matches');
      expect(route.requests, 400);
      expect(route.liveRequests, 100);
      expect(route.serverMs, 1200.0);
      expect(route.maxMs, 45.2);
      expect(route.bytes, 50000);
    });

    test('LoadTopic round-trips from JSON correctly', () {
      final json = {
        'topic': 'matches:update',
        'messages': 14,
        'usersReached': 42,
      };

      final topic = LoadTopic.fromJson(json);
      expect(topic.topic, 'matches:update');
      expect(topic.messages, 14);
      expect(topic.usersReached, 42);
    });

    test('ClusterLoadProfile parses complete cluster JSON payload', () {
      final json = {
        'windowMinutes': 15,
        'unreachableNodes': ['192.168.1.103'],
        'nodes': [
          {
            'nodeIp': '192.168.1.101',
            'trackingSinceMs': 1699990000000,
            'usersConnected': 25,
            'cpuLoad': 0.35,
            'usedHeapMb': 512,
            'maxHeapMb': 2048,
            'relayRowsWritten': 100,
            'relayRowsDelivered': 98,
            'minutes': [
              {
                'minute': 1700000000000,
                'requests': 100,
                'liveRequests': 30,
                'serverMs': 200.0,
                'liveServerMs': 60.0,
                'bytes': 50000,
                'liveBytes': 10000,
                'errors': 0,
                'invalidations': 2,
                'usersReached': 10,
              }
            ],
            'routes': [
              {
                'route': '/api/rankings',
                'requests': 80,
                'liveRequests': 20,
                'serverMs': 150.0,
                'maxMs': 12.0,
                'bytes': 40000,
              }
            ],
            'topics': [
              {
                'topic': 'rankings:live',
                'messages': 4,
                'usersReached': 20,
              }
            ]
          }
        ]
      };

      final cluster = ClusterLoadProfile.fromJson(json);
      expect(cluster.windowMinutes, 15);
      expect(cluster.unreachableNodes, ['192.168.1.103']);
      expect(cluster.nodes.length, 1);

      final node = cluster.nodes.first;
      expect(node.nodeIp, '192.168.1.101');
      expect(node.usersConnected, 25);
      expect(node.cpuLoad, 0.35);
      expect(node.usedHeapMb, 512);
      expect(node.maxHeapMb, 2048);
      expect(node.minutes.length, 1);
      expect(node.routes.length, 1);
      expect(node.topics.length, 1);
    });
  });

  group('Load Profiler Calculations & Combination Logic', () {
    test('combineProfiles aggregates multiple nodes correctly', () {
      final node1 = NodeLoadProfile(
        nodeIp: '10.0.0.1',
        trackingSinceMs: 1000,
        usersConnected: 10,
        cpuLoad: 0.20,
        usedHeapMb: 400,
        maxHeapMb: 1000,
        relayRowsWritten: 10,
        relayRowsDelivered: 10,
        minutes: const [
          LoadMinute(
            minute: 60000,
            requests: 100,
            liveRequests: 40,
            serverMs: 500.0,
            liveServerMs: 150.0,
            bytes: 10000,
            liveBytes: 4000,
            errors: 1,
            invalidations: 2,
            usersReached: 8,
          ),
        ],
        routes: const [
          LoadRoute(
            route: '/api/data',
            requests: 50,
            liveRequests: 10,
            serverMs: 250.0,
            maxMs: 30.0,
            bytes: 5000,
          ),
        ],
        topics: const [
          LoadTopic(topic: 'data:all', messages: 5, usersReached: 10),
        ],
      );

      final node2 = NodeLoadProfile(
        nodeIp: '10.0.0.2',
        trackingSinceMs: 2000,
        usersConnected: 15,
        cpuLoad: 0.45,
        usedHeapMb: 600,
        maxHeapMb: 1000,
        relayRowsWritten: 20,
        relayRowsDelivered: 20,
        minutes: const [
          LoadMinute(
            minute: 60000,
            requests: 150,
            liveRequests: 60,
            serverMs: 700.0,
            liveServerMs: 200.0,
            bytes: 15000,
            liveBytes: 6000,
            errors: 2,
            invalidations: 3,
            usersReached: 12,
          ),
          LoadMinute(
            minute: 120000,
            requests: 80,
            liveRequests: 20,
            serverMs: 300.0,
            liveServerMs: 50.0,
            bytes: 8000,
            liveBytes: 2000,
            errors: 0,
            invalidations: 1,
            usersReached: 4,
          ),
        ],
        routes: const [
          LoadRoute(
            route: '/api/data',
            requests: 70,
            liveRequests: 30,
            serverMs: 350.0,
            maxMs: 55.0,
            bytes: 7000,
          ),
        ],
        topics: const [
          LoadTopic(topic: 'data:all', messages: 10, usersReached: 15),
        ],
      );

      final combined = combineProfiles([node1, node2]);
      expect(combined.nodeCount, 2);
      expect(combined.usersConnected, 25);
      expect(combined.cpuLoad, 0.45);
      expect(combined.heapShare, 0.60);
      expect(combined.trackingSinceMs, 1000);

      // Minutes combined by timestamp
      expect(combined.minutes.length, 2);
      final min60 = combined.minutes.firstWhere((m) => m.minute == 60000);
      expect(min60.requests, 250);
      expect(min60.liveRequests, 100);
      expect(min60.serverMs, 1200.0);
      expect(min60.liveServerMs, 350.0);
      expect(min60.bytes, 25000);
      expect(min60.liveBytes, 10000);
      expect(min60.errors, 3);
      expect(min60.invalidations, 5);
      expect(min60.usersReached, 20);

      // Routes combined
      expect(combined.routes.length, 1);
      final route = combined.routes.first;
      expect(route.route, '/api/data');
      expect(route.requests, 120);
      expect(route.liveRequests, 40);
      expect(route.serverMs, 600.0);
      expect(route.maxMs, 55.0); // max of 30.0 and 55.0
      expect(route.bytes, 12000);

      // Topics combined
      expect(combined.topics.length, 1);
      final topic = combined.topics.first;
      expect(topic.topic, 'data:all');
      expect(topic.messages, 15);
      expect(topic.usersReached, 25);
    });

    test('summarizeLoadProfile works out rates and shares accurately', () {
      final combined = CombinedLoadProfile(
        nodeCount: 1,
        usersConnected: 5,
        cpuLoad: 0.15,
        heapShare: 0.30,
        trackingSinceMs: 0,
        minutes: const [
          LoadMinute(
            minute: 0,
            requests: 600,
            liveRequests: 240,
            serverMs: 6000.0,
            liveServerMs: 1500.0,
            bytes: 600000,
            liveBytes: 150000,
            errors: 2,
            invalidations: 10,
          ),
          LoadMinute(
            minute: 60000,
            requests: 1200,
            liveRequests: 360,
            serverMs: 12000.0,
            liveServerMs: 3000.0,
            bytes: 1200000,
            liveBytes: 300000,
            errors: 1,
            invalidations: 20,
          ),
        ],
        routes: const [],
        topics: const [],
      );

      // Assume now is at 120000ms (2 minutes elapsed)
      final summary = summarizeLoadProfile(combined, 120000);
      expect(summary.requests, 1800);
      expect(summary.liveRequests, 600);
      expect(summary.errors, 3);
      expect(summary.invalidations, 30);
      expect(summary.liveBytes, 450000);

      // 1800 requests over 120 seconds = 15.0 req/s
      expect(summary.requestsPerSecond, 15.0);
      // 600 liveRequests over 120 seconds = 5.0 live/s
      expect(summary.livePerSecond, 5.0);
      // Peak minute is 1200 reqs -> 1200 / 60 = 20.0 req/s
      expect(summary.peakPerSecond, 20.0);

      // Shares
      expect(summary.liveShare, closeTo(600 / 1800, 0.001)); // ~33%
      expect(summary.liveServerShare, closeTo(4500 / 18000, 0.001)); // 25%
      expect(summary.averageMs, closeTo(18000 / 1800, 0.001)); // 10.0 ms
    });
  });

  group('Load Profiler Formatting Helpers', () {
    test('formatLoadBytes formats across scale ranges', () {
      expect(formatLoadBytes(512), '512 B');
      expect(formatLoadBytes(1536), '1.5 KB');
      expect(formatLoadBytes(2 * 1024 * 1024), '2.0 MB');
      expect(formatLoadBytes(1.5 * 1024 * 1024 * 1024), '1.50 GB');
    });

    test('formatLoadMs formats appropriately', () {
      expect(formatLoadMs(4.25), '4.3 ms');
      expect(formatLoadMs(120.4), '120 ms');
      expect(formatLoadMs(12500), '12.5 s');
    });

    test('formatLoadRate formats decimals correctly', () {
      expect(formatLoadRate(4.256), '4.26');
      expect(formatLoadRate(15.678), '15.7');
    });

    test('formatLoadPercent formats as integer percentage', () {
      expect(formatLoadPercent(0.334), '33%');
      expect(formatLoadPercent(0.50), '50%');
      expect(formatLoadPercent(1.0), '100%');
    });

    test('niceMaximum finds optimal round ceiling', () {
      expect(niceMaximum(3), 4);
      expect(niceMaximum(8), 10);
      expect(niceMaximum(18), 20);
      expect(niceMaximum(35), 40);
      expect(niceMaximum(42), 50);
      expect(niceMaximum(95), 100);
      expect(niceMaximum(350), 400);
    });
  });

  group('Superadmin Permission & Shell Registration', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService();
    });

    test('superAdminOnlyPages contains load-profiler', () {
      expect(superAdminOnlyPages, contains('load-profiler'));
    });

    test('SUPERADMIN has access to load-profiler', () {
      apiService.setCachedUserForTesting(
        UserModel(
            id: '1', username: 'root', teamNumber: 1234, role: 'SUPERADMIN'),
      );
      expect(apiService.hasPageAccess('load-profiler'), isTrue);
    });

    test('ADMIN, ANALYTICS, and SCOUT are denied access to load-profiler', () {
      apiService.setCachedUserForTesting(
        UserModel(id: '2', username: 'admin', teamNumber: 1234, role: 'ADMIN'),
      );
      expect(apiService.hasPageAccess('load-profiler'), isFalse);

      apiService.setCachedUserForTesting(
        UserModel(id: '3', username: 'scout', teamNumber: 1234, role: 'SCOUT'),
      );
      expect(apiService.hasPageAccess('load-profiler'), isFalse);

      apiService.setCachedUserForTesting(
        UserModel(
            id: '4',
            username: 'analytics',
            teamNumber: 1234,
            role: 'ANALYTICS'),
      );
      expect(apiService.hasPageAccess('load-profiler'), isFalse);
    });

    test('ShellScreenRegistry registers load-profiler at index 52', () {
      expect(ShellScreenRegistry.screenCount, 55);
      expect(ShellScreenRegistry.getPageIdForIndex(52), 'load-profiler');
      expect(ShellScreenRegistry.titleKeys, contains('nav.load_profiler'));
      expect(
          ShellScreenRegistry.subtitleKeys, contains('subtitle.load_profiler'));
    });
  });
}
