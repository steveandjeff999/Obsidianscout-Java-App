import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/redis_models.dart';
import 'package:obsidianscout_app/screens/cluster_management_screen.dart';
import 'package:obsidianscout_app/screens/redis_status_screen.dart';
import 'package:obsidianscout_app/screens/settings_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/shell/shell_screen_registry.dart';

class _FakeRedisApi extends ApiService {
  final UserModel _user;
  final RedisStatusResponse? fakeStatus;
  final List<RedisNodeConfigDto> fakeConfig;

  _FakeRedisApi({
    required String role,
    this.fakeStatus,
    this.fakeConfig = const [],
  }) : _user = UserModel(id: '1', username: 'test', teamNumber: 1, role: role);

  @override
  UserModel? get currentUser => _user;

  @override
  bool hasPageAccess(String pageId) {
    if (superAdminOnlyPages.contains(pageId)) {
      return _user.role.toUpperCase() == 'SUPERADMIN';
    }
    return true;
  }

  @override
  Future<RedisStatusResponse?> fetchRedisStatus() async => fakeStatus;

  @override
  Future<List<RedisNodeConfigDto>> fetchRedisConfig() async => fakeConfig;
}

void main() {
  group('Redis Models Serialization & Deserialization', () {
    test('RedisMemoryAssessment round-trips from JSON correctly', () {
      final json = {
        'totalOsMb': 16384,
        'availableOsMb': 8192,
        'jvmMaxMb': 2048,
        'recommendedRedisMb': 1024,
        'evictionPolicy': 'allkeys-lru',
      };
      final obj = RedisMemoryAssessment.fromJson(json);
      expect(obj.totalOsMb, 16384);
      expect(obj.availableOsMb, 8192);
      expect(obj.jvmMaxMb, 2048);
      expect(obj.recommendedRedisMb, 1024);
      expect(obj.evictionPolicy, 'allkeys-lru');

      final exported = obj.toJson();
      expect(exported['totalOsMb'], 16384);
      expect(exported['recommendedRedisMb'], 1024);
    });

    test('RedisStatusResponse parses full JSON payload', () {
      final json = {
        'is_ready': true,
        'is_host': true,
        'can_host_redis': true,
        'active_endpoint': '10.0.0.1:6379',
        'lease_holder': '10.0.0.1',
        'hits': 1500,
        'misses': 25,
        'stampedes_avoided': 8,
        'evictions': 0,
        'redis_server_hits': 4000,
        'redis_server_misses': 100,
        'total_keys': 150,
        'used_memory_bytes': 2097152,
        'used_memory_mb': 2,
        'used_memory_human': '2.0 MB',
        'memory_assessment': {
          'totalOsMb': 16384,
          'availableOsMb': 8192,
          'jvmMaxMb': 2048,
          'recommendedRedisMb': 1024,
          'evictionPolicy': 'allkeys-lru',
        },
      };

      final status = RedisStatusResponse.fromJson(json);
      expect(status.isReady, isTrue);
      expect(status.isHost, isTrue);
      expect(status.canHostRedis, isTrue);
      expect(status.activeEndpoint, '10.0.0.1:6379');
      expect(status.hits, 1500);
      expect(status.misses, 25);
      expect(status.stampedesAvoided, 8);
      expect(status.usedMemoryHuman, '2.0 MB');
      expect(status.memoryAssessment.recommendedRedisMb, 1024);
    });

    test('RedisNodeConfigDto parses node data correctly', () {
      final json = {
        'nodeIp': '10.0.0.1',
        'isLocal': true,
        'reachable': true,
        'error': null,
        'enabled': true,
        'requirePassword': true,
        'host': '',
        'port': 6379,
        'passwordSet': false,
        'maxMemoryPercent': 0.40,
        'minMemoryMb': 64,
        'maxMemoryMb': 8192,
        'isReady': true,
        'isHost': true,
        'canHostRedis': true,
        'installProgress': null,
      };

      final node = RedisNodeConfigDto.fromJson(json);
      expect(node.nodeIp, '10.0.0.1');
      expect(node.isLocal, isTrue);
      expect(node.reachable, isTrue);
      expect(node.enabled, isTrue);
      expect(node.port, 6379);
      expect(node.isReady, isTrue);
    });

    test('RedisConfigUpdateRequest serializes only non-null updates', () {
      final req = RedisConfigUpdateRequest(
        enabled: true,
        requirePassword: true,
        port: 6380,
        clearPassword: true,
      );
      final j = req.toJson();
      expect(j['enabled'], isTrue);
      expect(j['requirePassword'], isTrue);
      expect(j['port'], 6380);
      expect(j['clearPassword'], isTrue);
      expect(j.containsKey('host'), isFalse);
    });

    test('RedisClusterNodeResult parses result from node', () {
      final json = {
        'targetIp': '10.0.0.2',
        'success': true,
        'message': 'Saved and restarted',
      };
      final res = RedisClusterNodeResult.fromJson(json);
      expect(res.targetIp, '10.0.0.2');
      expect(res.success, isTrue);
      expect(res.message, 'Saved and restarted');
    });
  });

  group('Superadmin Permissions & Registration', () {
    test('superAdminOnlyPages contains redis-status', () {
      expect(superAdminOnlyPages, contains('redis-status'));
    });

    test('SUPERADMIN role has page access to redis-status', () {
      final api = _FakeRedisApi(role: 'SUPERADMIN');
      expect(api.hasPageAccess('redis-status'), isTrue);
    });

    test('ADMIN, ANALYTICS, and SCOUT are denied access to redis-status', () {
      expect(_FakeRedisApi(role: 'ADMIN').hasPageAccess('redis-status'), isFalse);
      expect(_FakeRedisApi(role: 'ANALYTICS').hasPageAccess('redis-status'), isFalse);
      expect(_FakeRedisApi(role: 'SCOUT').hasPageAccess('redis-status'), isFalse);
    });

    test('ShellScreenRegistry registers case 54 as RedisStatusScreen', () {
      expect(ShellScreenRegistry.screenCount, 55);
      expect(ShellScreenRegistry.getPageIdForIndex(54), 'redis-status');
      expect(ShellScreenRegistry.titleKeys, contains('nav.redis_status'));
      expect(ShellScreenRegistry.subtitleKeys, contains('subtitle.redis_status'));

      final screen = ShellScreenRegistry.buildScreenByIndex(
        screenIndex: 54,
        apiService: ApiService(),
        isTabActive: true,
        currentIndex: 54,
        isBarsVisible: true,
        onNavigateScreen: (_) {},
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
      expect(screen, isA<RedisStatusScreen>());
    });

    test('the Settings card navigates to Redis Status (index 54)', () {
      final opened = <int>[];
      final settings = ShellScreenRegistry.buildScreenByIndex(
        screenIndex: 5,
        apiService: ApiService(),
        isTabActive: true,
        currentIndex: 5,
        isBarsVisible: true,
        onNavigateScreen: opened.add,
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
      ) as SettingsScreen;

      expect(settings.onNavigateRedisStatus, isNotNull);
      settings.onNavigateRedisStatus!();
      expect(opened, [54]);
    });

    test('ClusterManagementScreen has button to navigate to Redis Status', () {
      final opened = <int>[];
      final cluster = ShellScreenRegistry.buildScreenByIndex(
        screenIndex: 23,
        apiService: ApiService(),
        isTabActive: true,
        currentIndex: 23,
        isBarsVisible: true,
        onNavigateScreen: opened.add,
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
      ) as ClusterManagementScreen;

      expect(cluster.onNavigateRedisStatus, isNotNull);
      cluster.onNavigateRedisStatus!();
      expect(opened, [54]);
    });
  });

  group('Internationalization & Strings Verification', () {
    test('every language defines nav.redis_status and subtitle.redis_status', () {
      for (final lang in ['en', 'es', 'tr', 'he']) {
        final strings = jsonDecode(
          File('assets/i18n/$lang.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(strings['nav.redis_status'], isNotNull, reason: lang);
        expect(strings['subtitle.redis_status'], isNotNull, reason: lang);
        expect(strings['redis.title'], isNotNull, reason: lang);
      }
    });

    test('RedisStatusScreen source code contains no raw emojis', () {
      final source =
          File('lib/screens/redis_status_screen.dart').readAsStringSync();
      expect(source, isNot(contains('⚠')));
      expect(source, isNot(contains('❌')));
      expect(source, isNot(contains('✅')));
    });
  });

  group('Sidebar & Drawer Alphabetical Sorting', () {
    test('desktop sidebar orders load-profiler, migration, redis-status, and server-insights correctly', () {
      final content =
          File('lib/widgets/obsidian_desktop_sidebar.dart').readAsStringSync();

      final idxFcm = content.indexOf("'pageId': 'fcm-settings'");
      final idxLoad = content.indexOf("'pageId': 'load-profiler'");
      final idxMig = content.indexOf("'pageId': 'migration'");
      final idxRedis = content.indexOf("'pageId': 'redis-status'");
      final idxScout = content.indexOf("'pageId': 'scout-assignments'");
      final idxScouter = content.indexOf("'pageId': 'scouter-report'");
      final idxInsights = content.indexOf("'pageId': 'server-insights'");
      final idxCluster = content.indexOf("'pageId': 'cluster-management'");
      final idxSettings = content.indexOf("'pageId': 'settings'");

      expect(idxFcm, isNonNegative);
      expect(idxLoad, isNonNegative);
      expect(idxMig, isNonNegative);
      expect(idxRedis, isNonNegative);
      expect(idxScout, isNonNegative);
      expect(idxScouter, isNonNegative);
      expect(idxInsights, isNonNegative);
      expect(idxCluster, isNonNegative);
      expect(idxSettings, isNonNegative);

      expect(idxFcm < idxLoad, isTrue, reason: 'fcm-settings must precede load-profiler');
      expect(idxLoad < idxMig, isTrue, reason: 'load-profiler must precede migration');
      expect(idxMig < idxRedis, isTrue, reason: 'migration must precede redis-status');
      expect(idxRedis < idxScout, isTrue, reason: 'redis-status must precede scout-assignments');
      expect(idxScout < idxScouter, isTrue, reason: 'scout-assignments must precede scouter-report');
      expect(idxScouter < idxInsights, isTrue, reason: 'scouter-report must precede server-insights');
      expect(idxInsights < idxCluster, isTrue, reason: 'server-insights must precede cluster-management');
      expect(idxCluster < idxSettings, isTrue, reason: 'cluster-management must precede settings');
    });

    test('drawer orders load-profiler, migration, redis-status, and server-insights correctly', () {
      final content =
          File('lib/widgets/obsidian_drawer.dart').readAsStringSync();

      final idxFcm = content.indexOf("'pageId': 'fcm-settings'");
      final idxLoad = content.indexOf("'pageId': 'load-profiler'");
      final idxMig = content.indexOf("'pageId': 'migration'");
      final idxRedis = content.indexOf("'pageId': 'redis-status'");
      final idxScout = content.indexOf("'pageId': 'scout-assignments'");
      final idxScouter = content.indexOf("'pageId': 'scouter-report'");
      final idxInsights = content.indexOf("'pageId': 'server-insights'");
      final idxCluster = content.indexOf("'pageId': 'cluster-management'");
      final idxSettings = content.indexOf("'pageId': 'settings'");

      expect(idxFcm, isNonNegative);
      expect(idxLoad, isNonNegative);
      expect(idxMig, isNonNegative);
      expect(idxRedis, isNonNegative);
      expect(idxScout, isNonNegative);
      expect(idxScouter, isNonNegative);
      expect(idxInsights, isNonNegative);
      expect(idxCluster, isNonNegative);
      expect(idxSettings, isNonNegative);

      expect(idxFcm < idxLoad, isTrue);
      expect(idxLoad < idxMig, isTrue);
      expect(idxMig < idxRedis, isTrue);
      expect(idxRedis < idxScout, isTrue);
      expect(idxScouter < idxInsights, isTrue);
      expect(idxInsights < idxCluster, isTrue);
      expect(idxCluster < idxSettings, isTrue);
    });
  });

  group('RedisStatusScreen Widget Tests', () {
    testWidgets('RedisStatusScreen blocks non-superadmins gracefully', (tester) async {
      final api = _FakeRedisApi(role: 'SCOUT');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RedisStatusScreen(
              apiService: api,
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('SuperAdmin Access Required'), findsOneWidget);
      expect(
        find.text('You need superadministrator privileges to access Redis cache & cluster management.'),
        findsOneWidget,
      );
    });

    testWidgets('RedisStatusScreen renders metrics and data for SUPERADMIN', (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final status = RedisStatusResponse(
        isReady: true,
        isHost: true,
        canHostRedis: true,
        activeEndpoint: '192.168.1.100:6379',
        leaseHolder: '192.168.1.100',
        hits: 1200,
        misses: 40,
        stampedesAvoided: 15,
        evictions: 0,
        redisServerHits: 3000,
        redisServerMisses: 200,
        totalKeys: 88,
        usedMemoryBytes: 1572864,
        usedMemoryMb: 2,
        usedMemoryHuman: '1.5 MB',
        memoryAssessment: const RedisMemoryAssessment(
          totalOsMb: 16384,
          availableOsMb: 8192,
          jvmMaxMb: 2048,
          recommendedRedisMb: 1024,
          evictionPolicy: 'allkeys-lru',
        ),
      );

      final nodes = [
        const RedisNodeConfigDto(
          nodeIp: '192.168.1.100',
          isLocal: true,
          reachable: true,
          enabled: true,
          isReady: true,
          isHost: true,
          canHostRedis: true,
          host: '',
          port: 6379,
        ),
      ];

      final api = _FakeRedisApi(
        role: 'SUPERADMIN',
        fakeStatus: status,
        fakeConfig: nodes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RedisStatusScreen(
              apiService: api,
              isVisible: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Redis Cache & Topology'), findsOneWidget);
      expect(find.text('ACTIVE (Cached)'), findsOneWidget);
      expect(find.text('96.8 %'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('MASTER (Host)'), findsOneWidget);
      expect(find.text('192.168.1.100'), findsWidgets);
      expect(find.text('Install & Deploy Redis on Nodes'), findsOneWidget);
      expect(find.text('Purge Entire Cluster Cache'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
