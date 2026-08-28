import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';
import 'package:obsidianscout_app/widgets/reset_password_modal.dart';

class _MockAuthApiService extends ApiService {
  String? lastForgotEmail;
  String? lastForgotUsername;
  int? lastForgotTeamNumber;
  bool? lastForgotIsApp;

  String? lastVerifyToken;
  String? lastResetToken;
  String? lastResetUserId;
  String? lastResetNewUsername;
  String? lastResetNewPassword;

  bool shouldForgotSucceed = true;
  bool shouldVerifySucceed = true;
  bool shouldResetSucceed = true;

  List<Map<String, dynamic>> mockAccounts = [
    {'userId': 'user-uuid-1', 'username': 'scout1', 'teamNumber': 1234},
    {'userId': 'user-uuid-2', 'username': 'scout2', 'teamNumber': 5678},
  ];

  @override
  bool get isOnline => true;

  @override
  Future<ApiResponse<Map<String, dynamic>>> forgotPassword({
    String? email,
    String? username,
    int? teamNumber,
    bool isApp = true,
  }) async {
    lastForgotEmail = email;
    lastForgotUsername = username;
    lastForgotTeamNumber = teamNumber;
    lastForgotIsApp = isApp;

    if (shouldForgotSucceed) {
      return const ApiResponse.success(
        {'message': 'Password reset token sent to registered email.'},
        message: 'Password reset token sent to registered email.',
      );
    } else {
      return const ApiResponse.error(
        statusCode: 404,
        message: 'No accounts found with that email address.',
      );
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> verifyResetToken(String token) async {
    lastVerifyToken = token;
    if (shouldVerifySucceed && token == 'valid-token') {
      return ApiResponse.success({
        'valid': true,
        'accounts': mockAccounts,
      });
    } else {
      return const ApiResponse.success({
        'valid': false,
        'accounts': [],
      });
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> resetPassword({
    required String token,
    String? userId,
    String? newUsername,
    required String newPassword,
  }) async {
    lastResetToken = token;
    lastResetUserId = userId;
    lastResetNewUsername = newUsername;
    lastResetNewPassword = newPassword;

    if (shouldResetSucceed) {
      return const ApiResponse.success(
        {'message': 'Credentials have been reset successfully.'},
        message: 'Credentials have been reset successfully.',
      );
    } else {
      return const ApiResponse.error(
        statusCode: 400,
        message: 'Invalid or expired reset token.',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('Forgot Password & Reset Credentials Tests', () {
    testWidgets('LoginScreen toggles to Forgot Password mode and back', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockAuthApiService();

      await tester.pumpWidget(
        buildTestableWidget(
          LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "Forgot username/password?" link is present
      final forgotLinkFinder = find.text('Forgot username/password?');
      expect(forgotLinkFinder, findsOneWidget);

      // Tap forgot password link
      await tester.tap(forgotLinkFinder);
      await tester.pumpAndSettle();

      // Verify Recover Password view is displayed
      expect(find.text('Recover Password'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Username & Team'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);

      // Toggle to "Username & Team" tab
      await tester.tap(find.text('Username & Team'));
      await tester.pumpAndSettle();

      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Team Number'), findsOneWidget);

      // Tap "Back to sign in"
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();

      // Verify back on Sign In tab
      expect(find.text('Forgot username/password?'), findsOneWidget);
    });

    testWidgets('Submitting Email recovery invokes ApiService.forgotPassword with isApp: true', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockAuthApiService();

      await tester.pumpWidget(
        buildTestableWidget(
          LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to forgot password
      await tester.tap(find.text('Forgot username/password?'));
      await tester.pumpAndSettle();

      // Enter email
      final emailField = find.widgetWithText(TextFormField, 'Email Address');
      expect(emailField, findsOneWidget);
      await tester.enterText(emailField, 'scout@example.com');
      await tester.pumpAndSettle();

      // Tap "Send reset link"
      final sendBtn = find.text('Send reset link');
      await tester.ensureVisible(sendBtn);
      await tester.pumpAndSettle();
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mockApi.lastForgotEmail, 'scout@example.com');
      expect(mockApi.lastForgotIsApp, true);
      expect(find.byType(ResetPasswordModal), findsOneWidget);
    });

    testWidgets('Submitting Username & Team recovery invokes ApiService.forgotPassword with isApp: true', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockAuthApiService();

      await tester.pumpWidget(
        buildTestableWidget(
          LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to forgot password
      await tester.tap(find.text('Forgot username/password?'));
      await tester.pumpAndSettle();

      // Switch to Username & Team tab
      await tester.tap(find.text('Username & Team'));
      await tester.pumpAndSettle();

      // Enter username & team number
      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final teamField = find.widgetWithText(TextFormField, 'Team Number');

      await tester.enterText(usernameField, 'lead_scout');
      await tester.enterText(teamField, '1234');
      await tester.pumpAndSettle();

      // Tap "Send reset link"
      final sendBtn = find.text('Send reset link');
      await tester.ensureVisible(sendBtn);
      await tester.pumpAndSettle();
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mockApi.lastForgotUsername, 'lead_scout');
      expect(mockApi.lastForgotTeamNumber, 1234);
      expect(mockApi.lastForgotIsApp, true);
      expect(find.byType(ResetPasswordModal), findsOneWidget);
    });

    testWidgets('ResetPasswordModal verifies token, shows multi-account dropdown, and resets credentials', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockAuthApiService();
      String? updatedUsername;

      await tester.pumpWidget(
        buildTestableWidget(
          ResetPasswordModal(
            apiService: mockApi,
            initialToken: 'valid-token',
            onResetSuccess: (name) => updatedUsername = name,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Token auto-verifies
      expect(mockApi.lastVerifyToken, 'valid-token');
      expect(find.text('Select Account to Reset'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Enter new password and confirmation
      final newPasswordField = find.widgetWithText(TextFormField, 'New Password');
      final confirmPasswordField = find.widgetWithText(TextFormField, 'Confirm Password');

      await tester.enterText(newPasswordField, 'newsecurepassword');
      await tester.enterText(confirmPasswordField, 'newsecurepassword');
      await tester.pumpAndSettle();

      // Tap Reset Credentials button
      await tester.tap(find.text('Reset credentials'));
      await tester.pumpAndSettle();

      expect(mockApi.lastResetToken, 'valid-token');
      expect(mockApi.lastResetUserId, 'user-uuid-1');
      expect(mockApi.lastResetNewPassword, 'newsecurepassword');
      expect(updatedUsername, 'scout1');
    });

    testWidgets('ResetPasswordModal handles invalid/expired token error state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockAuthApiService();

      await tester.pumpWidget(
        buildTestableWidget(
          ResetPasswordModal(
            apiService: mockApi,
            initialToken: 'invalid-token',
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mockApi.lastVerifyToken, 'invalid-token');
      expect(find.textContaining('invalid or has expired'), findsOneWidget);
      expect(find.text('Select Account to Reset'), findsNothing);
    });
  });
}
