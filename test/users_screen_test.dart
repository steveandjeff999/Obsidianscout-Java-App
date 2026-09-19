import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/users_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';

class _MockAdminApiService extends ApiService {
  final UserModel caller;
  final List<UserModel> mockUsers;

  _MockAdminApiService({required this.caller, required this.mockUsers});

  @override
  bool get isOnline => true;

  @override
  UserModel? get currentUser => caller;

  @override
  String get currentUserRole => caller.role;

  @override
  bool hasPageAccess(String pageId) {
    if (pageId == 'users') {
      return caller.isAdmin;
    }
    return true;
  }

  @override
  Future<ApiResponse<List<UserModel>>> getAdminUsers({
    String? q,
    int? teamNumber,
    String? program,
    String? role,
    int limit = 50,
    int offset = 0,
    String? sortBy,
    String? sortDir,
  }) async {
    return ApiResponse.success(mockUsers);
  }
}

void main() {
  group('UserModel Permissions Tests', () {
    final superAdmin = UserModel(id: '1', username: 'superadmin', teamNumber: 254, role: 'SUPERADMIN');
    final adminTeam254 = UserModel(id: '2', username: 'admin254', teamNumber: 254, role: 'ADMIN');
    final scoutTeam254 = UserModel(id: '3', username: 'scout254', teamNumber: 254, role: 'SCOUT');
    final scoutTeam111 = UserModel(id: '4', username: 'scout111', teamNumber: 111, role: 'SCOUT');

    test('SuperAdmin can edit anyone and change usernames', () {
      expect(superAdmin.canEdit(adminTeam254), isTrue);
      expect(superAdmin.canEdit(scoutTeam111), isTrue);
      expect(superAdmin.canChangeUsername(scoutTeam254), isTrue);
      expect(superAdmin.canChangeRole(adminTeam254), isTrue);
    });

    test('Admin can only edit non-superadmin users on their team', () {
      expect(adminTeam254.canEdit(scoutTeam254), isTrue);
      expect(adminTeam254.canEdit(superAdmin), isFalse);
      expect(adminTeam254.canEdit(scoutTeam111), isFalse);
      expect(adminTeam254.canChangeUsername(scoutTeam254), isFalse);
      expect(adminTeam254.canChangeRole(scoutTeam254), isTrue);
      expect(adminTeam254.canChangeRole(superAdmin), isFalse);
    });

    test('Scout cannot edit users', () {
      expect(scoutTeam254.canEdit(scoutTeam254), isFalse);
      expect(scoutTeam254.canEdit(scoutTeam111), isFalse);
    });
  });

  group('UsersScreen Widget Tests', () {
    testWidgets('Non-admin users see Admin Locked screen', (tester) async {
      final scout = UserModel(id: '3', username: 'scout', teamNumber: 254, role: 'SCOUT');
      final mockApi = _MockAdminApiService(caller: scout, mockUsers: []);

      await tester.pumpWidget(
        MaterialApp(
          home: UsersScreen(apiService: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin only'), findsOneWidget);
      expect(find.text('You need admin access to manage users.'), findsOneWidget);
      expect(find.text('Current users'), findsNothing);
    });

    testWidgets('Admin user sees Users management screen and users table/cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final admin = UserModel(id: '2', username: 'team_admin', teamNumber: 254, role: 'ADMIN');
      final users = [
        UserModel(id: '2', username: 'team_admin', teamNumber: 254, role: 'ADMIN', email: 'admin@254.com'),
        UserModel(id: '3', username: 'lead_scout', teamNumber: 254, role: 'SCOUT', email: 'scout@254.com'),
      ];
      final mockApi = _MockAdminApiService(caller: admin, mockUsers: users);

      await tester.pumpWidget(
        MaterialApp(
          home: UsersScreen(apiService: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Create user'), findsOneWidget);
      expect(find.text('Current users'), findsOneWidget);
      expect(find.text('team_admin'), findsOneWidget);
      expect(find.text('lead_scout'), findsOneWidget);
    });
  });
}
