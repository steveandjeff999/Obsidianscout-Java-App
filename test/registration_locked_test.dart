import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';
import 'package:obsidianscout_app/widgets/obsidian_glass_card.dart';

class _MockRegisterApiService extends ApiService {
  bool isRegistrationLocked = false;
  String? genericError;

  @override
  bool get isOnline => true;

  @override
  Future<ApiResponse<void>> register(
    String username,
    String password, {
    required int teamNumber,
    String program = "FRC",
    String? email,
    String role = "SCOUT",
    bool keepMeLoggedIn = false,
  }) async {
    if (isRegistrationLocked) {
      return const ApiResponse.error(
        statusCode: 403,
        errorCode: 'REGISTRATION_LOCKED',
        message: 'Registration is locked for this team. Please contact a team administrator to create an account.',
      );
    }
    if (genericError != null) {
      return ApiResponse.error(
        statusCode: 400,
        message: genericError,
      );
    }
    return const ApiResponse.success(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Shows "Registration is locked for that team" when server rejects with locked registration',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockApi = _MockRegisterApiService()..isRegistrationLocked = true;
    bool loggedIn = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () => loggedIn = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Create Account tab
    final createAccountTab = find.text('Create Account');
    expect(createAccountTab, findsOneWidget);
    await tester.tap(createAccountTab);
    await tester.pumpAndSettle();

    // Fill in registration form (there are 5 TextFormFields in register form: username, email, team, password, confirm)
    final textFields = find.byType(TextFormField);
    expect(textFields, findsWidgets);

    // Enter username (index 0), team (index 2), password (index 3), confirm (index 4)
    await tester.enterText(textFields.at(0), 'newscout');
    await tester.enterText(textFields.at(2), '9999');
    await tester.enterText(textFields.at(3), 'secret123');
    await tester.enterText(textFields.at(4), 'secret123');
    await tester.pumpAndSettle();

    // Tap register submit button
    final registerBtn = find.widgetWithIcon(ObsidianGlassCard, Icons.person_add_rounded);
    expect(registerBtn, findsOneWidget);
    await tester.ensureVisible(registerBtn);
    await tester.tap(registerBtn);
    await tester.pumpAndSettle();

    expect(loggedIn, isFalse);
    expect(find.text('Registration is locked for that team'), findsOneWidget);
    expect(find.text('Registration failed. Please check your information and try again.'), findsNothing);
  });

  testWidgets('Shows fallback error message when server rejects with non-locked error',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockApi = _MockRegisterApiService()..genericError = 'Registration failed. Please check your information and try again.';
    bool loggedIn = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () => loggedIn = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Create Account tab
    final createAccountTab = find.text('Create Account');
    await tester.tap(createAccountTab);
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'newscout');
    await tester.enterText(textFields.at(2), '9999');
    await tester.enterText(textFields.at(3), 'secret123');
    await tester.enterText(textFields.at(4), 'secret123');
    await tester.pumpAndSettle();

    final registerBtn = find.widgetWithIcon(ObsidianGlassCard, Icons.person_add_rounded);
    await tester.ensureVisible(registerBtn);
    await tester.tap(registerBtn);
    await tester.pumpAndSettle();

    expect(loggedIn, isFalse);
    expect(find.text('Registration is locked for that team'), findsNothing);
    expect(find.text('Registration failed. Please check your information and try again.'), findsOneWidget);
  });
}
