import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserModel and AppSettingsModel Serialization', () {
    test('UserModel serializes and deserializes correctly', () {
      final user = UserModel(
        id: '42',
        username: 'lead_scout',
        teamNumber: 1234,
        program: 'FRC',
        role: 'ANALYTICS',
        email: 'lead@scout.org',
        profilePicture: 'https://example.com/avatar.png',
      );

      final json = user.toJson();
      expect(json['id'], '42');
      expect(json['username'], 'lead_scout');
      expect(json['teamNumber'], 1234);
      expect(json['program'], 'FRC');
      expect(json['role'], 'ANALYTICS');
      expect(json['profilePicture'], 'https://example.com/avatar.png');

      final deserialized = UserModel.fromJson(json);
      expect(deserialized.id, '42');
      expect(deserialized.username, 'lead_scout');
      expect(deserialized.teamNumber, 1234);
      expect(deserialized.program, 'FRC');
      expect(deserialized.role, 'ANALYTICS');
      expect(deserialized.roleDisplayLabel, 'Analytics');
      expect(deserialized.isSuperAdmin, false);
      expect(deserialized.isAdmin, false);
    });

    test('AppSettingsModel parses custom permissions', () {
      final json = {
        'year': 2026,
        'eventCode': 'mndu',
        'eventKey': '2026mndu',
        'timezone': 'America/Chicago',
        'preferredSource': 'tba',
        'chatEnabled': false,
        'scoutPages': ['scout', 'qr-scanner'],
        'analyticsPages': ['graphs', 'teams'],
        'adminPages': ['admin-settings'],
        'program': 'FRC',
        'serverVersion': '1.5.0',
      };

      final settings = AppSettingsModel.fromJson(json);
      expect(settings.year, 2026);
      expect(settings.eventCode, 'mndu');
      expect(settings.chatEnabled, false);
      expect(settings.scoutPages, ['scout', 'qr-scanner']);
      expect(settings.analyticsPages, ['graphs', 'teams']);
      expect(settings.adminPages, ['admin-settings']);
      expect(settings.program, 'FRC');
    });
  });

  group('ApiService Page Access Permissions Logic', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService();
    });

    test('Bypass pages are accessible to any user', () {
      apiService.setCachedUserForTesting(UserModel(id: '1', username: 'test_scout', teamNumber: 1234, role: 'SCOUT'));
      
      expect(apiService.hasPageAccess('dashboard'), isTrue);
      expect(apiService.hasPageAccess('settings'), isTrue);
      expect(apiService.hasPageAccess('docs'), isTrue);
      expect(apiService.hasPageAccess('contact'), isTrue);
    });

    test('SUPERADMIN has access to all pages unconditionally', () {
      apiService.setCachedUserForTesting(UserModel(id: '1', username: 'root', teamNumber: 1234, role: 'SUPERADMIN'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(
        chatEnabled: false,
        scoutPages: [],
        analyticsPages: [],
        adminPages: [],
      ));

      expect(apiService.hasPageAccess('dashboard'), isTrue);
      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('pit-scout'), isTrue);
      expect(apiService.hasPageAccess('graphs'), isTrue);
      expect(apiService.hasPageAccess('alliance-selection'), isTrue);
      expect(apiService.hasPageAccess('chat'), isTrue);
      expect(apiService.hasPageAccess('admin-settings'), isTrue);
      expect(apiService.hasPageAccess('config-editor'), isTrue);
      expect(apiService.hasPageAccess('backup'), isTrue);
      expect(apiService.hasPageAccess('logs'), isTrue);
      expect(apiService.hasPageAccess('users'), isTrue);
    });

    test('ADMIN has access to admin, analytics, scout, but not superadmin-only pages', () {
      apiService.setCachedUserForTesting(UserModel(id: '2', username: 'team_admin', teamNumber: 1234, role: 'ADMIN'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(chatEnabled: true));

      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('graphs'), isTrue);
      expect(apiService.hasPageAccess('teams'), isTrue);
      expect(apiService.hasPageAccess('chat'), isTrue);
      expect(apiService.hasPageAccess('admin-settings'), isTrue);
      expect(apiService.hasPageAccess('config-editor'), isTrue);
      expect(apiService.hasPageAccess('users'), isTrue);
      expect(apiService.hasPageAccess('default-configs'), isTrue);
      expect(apiService.hasPageAccess('banners'), isTrue);

      // SuperAdmin only pages are denied
      expect(apiService.hasPageAccess('backup'), isFalse);
      expect(apiService.hasPageAccess('logs'), isFalse);
      expect(apiService.hasPageAccess('cluster-management'), isFalse);
      expect(apiService.hasPageAccess('fcm-settings'), isFalse);
    });

    test('ANALYTICS has access to analytics and scouting pages, but not admin pages', () {
      apiService.setCachedUserForTesting(UserModel(id: '3', username: 'data_analyst', teamNumber: 1234, role: 'ANALYTICS'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(chatEnabled: true));

      expect(apiService.hasPageAccess('dashboard'), isTrue);
      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('pit-scout'), isTrue);
      expect(apiService.hasPageAccess('graphs'), isTrue);
      expect(apiService.hasPageAccess('teams'), isTrue);
      expect(apiService.hasPageAccess('matches'), isTrue);
      expect(apiService.hasPageAccess('alliance-selection'), isTrue);
      expect(apiService.hasPageAccess('chat'), isTrue);

      // Admin pages are denied
      expect(apiService.hasPageAccess('admin-settings'), isFalse);
      expect(apiService.hasPageAccess('config-editor'), isFalse);
      expect(apiService.hasPageAccess('users'), isFalse);
      expect(apiService.hasPageAccess('backup'), isFalse);
    });

    test('SCOUT default pages allow scouting but deny analytics and admin pages', () {
      apiService.setCachedUserForTesting(UserModel(id: '4', username: 'scout_member', teamNumber: 1234, role: 'SCOUT'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(chatEnabled: true));

      expect(apiService.hasPageAccess('dashboard'), isTrue);
      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('pit-scout'), isTrue);
      expect(apiService.hasPageAccess('qual-scout'), isTrue);
      expect(apiService.hasPageAccess('qr-scanner'), isTrue);
      expect(apiService.hasPageAccess('chat'), isTrue);

      // Denied analytics and admin pages
      expect(apiService.hasPageAccess('graphs'), isFalse);
      expect(apiService.hasPageAccess('teams'), isFalse);
      expect(apiService.hasPageAccess('matches'), isFalse);
      expect(apiService.hasPageAccess('alliance-selection'), isFalse);
      expect(apiService.hasPageAccess('admin-settings'), isFalse);
      expect(apiService.hasPageAccess('config-editor'), isFalse);
    });

    test('Custom team settings restrict SCOUT role to specific scoutPages', () {
      apiService.setCachedUserForTesting(UserModel(id: '5', username: 'restricted_scout', teamNumber: 1234, role: 'SCOUT'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(
        chatEnabled: false,
        scoutPages: ['scout', 'qr-scanner'], // pit-scout and qual-scout disabled
      ));

      expect(apiService.hasPageAccess('dashboard'), isTrue);
      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('qr-scanner'), isTrue);

      // Excluded from custom scoutPages
      expect(apiService.hasPageAccess('pit-scout'), isFalse);
      expect(apiService.hasPageAccess('qual-scout'), isFalse);

      // Chat disabled for team
      expect(apiService.hasPageAccess('chat'), isFalse);
    });

    test('Disabling chat in team settings disables chat for SCOUT and ANALYTICS', () {
      apiService.setCachedSettingsForTesting(AppSettingsModel(chatEnabled: false));

      apiService.setCachedUserForTesting(UserModel(id: '6', username: 'scout_1', teamNumber: 1234, role: 'SCOUT'));
      expect(apiService.hasPageAccess('chat'), isFalse);

      apiService.setCachedUserForTesting(UserModel(id: '7', username: 'analyst_1', teamNumber: 1234, role: 'ANALYTICS'));
      expect(apiService.hasPageAccess('chat'), isFalse);

      apiService.setCachedUserForTesting(UserModel(id: '8', username: 'admin_1', teamNumber: 1234, role: 'ADMIN'));
      expect(apiService.hasPageAccess('chat'), isFalse);

      // SuperAdmin still gets chat
      apiService.setCachedUserForTesting(UserModel(id: '9', username: 'super_1', teamNumber: 1234, role: 'SUPERADMIN'));
      expect(apiService.hasPageAccess('chat'), isTrue);
    });

    test('Disabling qr-scanner in team scoutPages removes access for SCOUT role', () {
      apiService.setCachedUserForTesting(UserModel(id: '10', username: 'no_qr_scout', teamNumber: 1234, role: 'SCOUT'));
      apiService.setCachedSettingsForTesting(AppSettingsModel(
        scoutPages: ['scout', 'pit-scout'], // qr-scanner excluded
      ));

      expect(apiService.hasPageAccess('qr-scanner'), isFalse);
      expect(apiService.hasPageAccess('scout'), isTrue);
      expect(apiService.hasPageAccess('pit-scout'), isTrue);
    });
  });
}
