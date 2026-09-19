import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/error_report_models.dart';
import 'package:obsidianscout_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorReport Models Serialization & Deserialization', () {
    test('ReportedErrorItem parses correctly', () {
      final json = {
        'id': 'err-123',
        'errorType': 'SERVER',
        'errorMessage': 'NullPointerException in MatchController.kt:42',
        'errorStack': 'java.lang.NullPointerException\n\tat com.obsidianscout.MatchController.save(MatchController.kt:42)',
        'requestDetails': 'POST /api/scouting/match',
        'clientIp': '192.168.1.100',
        'teamNumber': 254,
        'program': 'FRC',
        'userRole': 'ADMIN',
        'username': 'poofs_lead',
        'status': 'OPEN',
        'createdAt': '2026-09-19T14:30:00Z',
        'resolvedAt': null,
        'resolvedBy': null,
      };

      final item = ReportedErrorItem.fromJson(json);
      expect(item.id, 'err-123');
      expect(item.errorType, 'SERVER');
      expect(item.errorMessage, 'NullPointerException in MatchController.kt:42');
      expect(item.isServer, true);
      expect(item.isClient, false);
      expect(item.isOpen, true);
      expect(item.isResolved, false);
      expect(item.teamNumber, 254);
      expect(item.username, 'poofs_lead');

      final serialized = item.toJson();
      expect(serialized['id'], 'err-123');
      expect(serialized['errorType'], 'SERVER');
      expect(serialized['status'], 'OPEN');
    });

    test('ReportedErrorGroupItem parses and calculates counts correctly', () {
      final sampleJson = {
        'id': 'err-1',
        'errorType': 'CLIENT_JS',
        'errorMessage': 'Uncaught TypeError: Cannot read property of undefined',
        'errorStack': 'TypeError at app.js:120',
        'requestDetails': 'GET /dashboard',
        'clientIp': '10.0.0.5',
        'teamNumber': 1678,
        'program': 'FRC',
        'userRole': 'SCOUT',
        'username': 'citrus_scout',
        'status': 'OPEN',
        'createdAt': '2026-09-19T12:00:00Z',
      };

      final groupJson = {
        'groupKey': 'grp-abc',
        'errorType': 'CLIENT_JS',
        'errorMessage': 'Uncaught TypeError: Cannot read property of undefined',
        'location': '/dashboard',
        'count': 3,
        'openCount': 2,
        'resolvedCount': 1,
        'status': 'OPEN',
        'latestCreatedAt': '2026-09-19T14:00:00Z',
        'firstCreatedAt': '2026-09-19T10:00:00Z',
        'affectedTeams': [1678, 254],
        'affectedUsers': ['citrus_scout', 'poofs_lead'],
        'sampleError': sampleJson,
        'occurrences': [sampleJson],
      };

      final group = ReportedErrorGroupItem.fromJson(groupJson);
      expect(group.groupKey, 'grp-abc');
      expect(group.errorType, 'CLIENT_JS');
      expect(group.isServer, false);
      expect(group.count, 3);
      expect(group.openCount, 2);
      expect(group.hasOpen, true);
      expect(group.isAllResolved, false);
      expect(group.affectedTeams, [1678, 254]);
      expect(group.affectedUsers, ['citrus_scout', 'poofs_lead']);
      expect(group.sampleError.id, 'err-1');
      expect(group.occurrences.length, 1);
    });

    test('ReportedErrorsListResponse parses list response', () {
      final responseJson = {
        'success': true,
        'errors': [
          {
            'id': 'e1',
            'errorType': 'SERVER',
            'errorMessage': 'Database Timeout',
            'status': 'OPEN',
            'createdAt': '2026-09-19T10:00:00Z',
          }
        ],
        'groups': [],
        'totalCount': 10,
        'openCount': 6,
        'resolvedCount': 4,
        'serverCount': 7,
        'clientCount': 3,
      };

      final res = ReportedErrorsListResponse.fromJson(responseJson);
      expect(res.success, true);
      expect(res.errors.length, 1);
      expect(res.totalCount, 10);
      expect(res.openCount, 6);
      expect(res.resolvedCount, 4);
      expect(res.serverCount, 7);
      expect(res.clientCount, 3);
    });

    test('ReportedErrorStatsResponse parses stats response', () {
      final statsJson = {
        'success': true,
        'totalCount': 25,
        'openCount': 5,
        'resolvedCount': 20,
        'serverCount': 15,
        'clientCount': 10,
      };

      final stats = ReportedErrorStatsResponse.fromJson(statsJson);
      expect(stats.totalCount, 25);
      expect(stats.openCount, 5);
      expect(stats.resolvedCount, 20);
      expect(stats.serverCount, 15);
      expect(stats.clientCount, 10);
    });
  });

  group('Error Reports Page Access Control', () {
    test('SuperAdmin has access to error-reports', () {
      final api = ApiService();
      final superAdmin = UserModel(
        id: '1',
        username: 'sysadmin',
        teamNumber: 0,
        role: 'SUPERADMIN',
      );
      api.setCachedUserForTesting(superAdmin);

      expect(api.hasPageAccess('error-reports'), true);
      expect(superAdmin.isSuperAdmin, true);
    });

    test('Admin and Scout roles are blocked from error-reports', () {
      final api = ApiService();

      final admin = UserModel(
        id: '2',
        username: 'team_admin',
        teamNumber: 1234,
        role: 'ADMIN',
      );
      api.setCachedUserForTesting(admin);
      expect(api.hasPageAccess('error-reports'), false);

      final scout = UserModel(
        id: '3',
        username: 'scout_1',
        teamNumber: 1234,
        role: 'SCOUT',
      );
      api.setCachedUserForTesting(scout);
      expect(api.hasPageAccess('error-reports'), false);

      final analytics = UserModel(
        id: '4',
        username: 'analytics_lead',
        teamNumber: 1234,
        role: 'ANALYTICS',
      );
      api.setCachedUserForTesting(analytics);
      expect(api.hasPageAccess('error-reports'), false);
    });
  });
}
