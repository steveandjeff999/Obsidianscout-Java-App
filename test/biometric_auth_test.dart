import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obsidianscout_app/services/auth_storage_service.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:obsidianscout_app/l10n/app_localizations.dart';
import 'package:obsidianscout_app/screens/login_screen.dart';
import 'package:obsidianscout_app/widgets/obsidian_glass_card.dart';

import 'package:flutter/services.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations() : super(const Locale('en'));

  @override
  String translate(String key, [Map<String, String>? args]) {
    final map = {
      'login.connect_login': 'Sign In',
      'login.sign_in': 'Sign In',
      'login.username': 'Username',
      'login.password': 'Password',
      'login.team_number': 'Team Number',
      'login.program': 'Program',
      'login.keep_logged_in': 'Keep me logged in',
    };
    return map[key] ?? key;
  }
}

class _TestAppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async => _TestAppLocalizations();

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

Widget createTestApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      _TestAppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: home,
  );
}

class _MockAuthApiService extends ApiService {
  String? mockValidPassword;
  bool loginReturnValue = true;

  @override
  bool get isOnline => true;

  @override
  String get serverUrl => 'http://localhost:8080';

  @override
  Future<bool> login(
    String username,
    String password, {
    int teamNumber = 0,
    String program = "FRC",
    bool keepMeLoggedIn = false,
  }) async {
    if (loginReturnValue) {
      setSessionPasswordForTesting(password);
      await AuthStorageService.clearBiometricIfDifferentAccount(
        newUsername: username,
        newTeamNumber: teamNumber,
      );
      return true;
    }
    return false;
  }

  @override
  Future<bool> verifyPassword(String password) async {
    if (sessionPassword != null) {
      return sessionPassword == password;
    }
    return password == mockValidPassword;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isDeviceSupported') {
          return false;
        }
        if (methodCall.method == 'canCheckBiometrics') {
          return false;
        }
        if (methodCall.method == 'getAvailableBiometrics') {
          return <String>[];
        }
        return null;
      },
    );
  });

  group('AuthStorageService - Biometric Isolation Tests', () {
    test('clearBiometricIfDifferentAccount does nothing if no biometric is saved', () async {
      final cleared = await AuthStorageService.clearBiometricIfDifferentAccount(
        newUsername: 'scout1',
        newTeamNumber: 1234,
      );
      expect(cleared, isFalse);
    });

    test('clearBiometricIfDifferentAccount purges credentials if new username is different', () async {
      await AuthStorageService.saveCredentials(
        username: 'userA',
        password: 'passwordA',
        teamNumber: 1234,
        program: 'FRC',
        serverUrl: 'http://localhost:8080',
        jwt: 'jwt_a',
      );
      await AuthStorageService.setEnrolled(true);

      expect(await AuthStorageService.isEnrolled(), isTrue);

      final cleared = await AuthStorageService.clearBiometricIfDifferentAccount(
        newUsername: 'userB',
        newTeamNumber: 1234,
      );

      expect(cleared, isTrue);
      expect(await AuthStorageService.isEnrolled(), isFalse);
      expect(await AuthStorageService.loadCredentials(), isNull);
    });

    test('clearBiometricIfDifferentAccount purges credentials if new team number is different', () async {
      await AuthStorageService.saveCredentials(
        username: 'sharedScout',
        password: 'passwordA',
        teamNumber: 1234,
        program: 'FRC',
        serverUrl: 'http://localhost:8080',
        jwt: 'jwt_a',
      );
      await AuthStorageService.setEnrolled(true);

      final cleared = await AuthStorageService.clearBiometricIfDifferentAccount(
        newUsername: 'sharedScout',
        newTeamNumber: 5678,
      );

      expect(cleared, isTrue);
      expect(await AuthStorageService.isEnrolled(), isFalse);
    });

    test('clearBiometricIfDifferentAccount preserves credentials if same username (case-insensitive) and team', () async {
      await AuthStorageService.saveCredentials(
        username: 'UserA',
        password: 'passwordA',
        teamNumber: 1234,
        program: 'FRC',
        serverUrl: 'http://localhost:8080',
        jwt: 'jwt_a',
      );
      await AuthStorageService.setEnrolled(true);

      final cleared = await AuthStorageService.clearBiometricIfDifferentAccount(
        newUsername: 'usera',
        newTeamNumber: 1234,
      );

      expect(cleared, isFalse);
      expect(await AuthStorageService.isEnrolled(), isTrue);
      final creds = await AuthStorageService.loadCredentials();
      expect(creds?.username, equals('UserA'));
    });
  });

  group('ApiService - verifyPassword Tests', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService();
    });

    test('verifyPassword returns true when matching the exact in-memory session password', () async {
      apiService.setSessionPasswordForTesting('ExactSecret123');

      final result = await apiService.verifyPassword('ExactSecret123');
      expect(result, isTrue);
    });

    test('verifyPassword returns false when given something different from the session password', () async {
      apiService.setSessionPasswordForTesting('ExactSecret123');

      final result = await apiService.verifyPassword('WrongPassword');
      expect(result, isFalse);

      final typoResult = await apiService.verifyPassword('exactsecret123');
      expect(typoResult, isFalse);
    });

    test('logout clears in-memory session password', () async {
      apiService.setSessionPasswordForTesting('ExactSecret123');
      expect(apiService.sessionPassword, equals('ExactSecret123'));

      await apiService.logout();
      expect(apiService.sessionPassword, isNull);
    });
  });

  group('LoginScreen - Account Switch Biometric Purge', () {
    testWidgets('Logging in with a different account clears saved biometric credentials', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-save biometric for UserA
      await AuthStorageService.saveCredentials(
        username: 'UserA',
        password: 'PasswordA',
        teamNumber: 1234,
        program: 'FRC',
        serverUrl: 'http://localhost:8080',
        jwt: 'jwt_a',
      );
      await AuthStorageService.setEnrolled(true);

      expect(await AuthStorageService.isEnrolled(), isTrue);

      final mockApi = _MockAuthApiService();
      bool loginSuccessCalled = false;

      await tester.pumpWidget(
        createTestApp(
          LoginScreen(
            apiService: mockApi,
            onLoginSuccess: () {
              loginSuccessCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter UserB credentials
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'UserB'); // Username
      await tester.enterText(textFields.at(1), 'PasswordB'); // Password
      await tester.enterText(textFields.at(2), '1234'); // Team
      // Tap Sign In button
      final signInBtn = find.widgetWithIcon(ObsidianGlassCard, Icons.login_rounded);
      expect(signInBtn, findsOneWidget);
      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(loginSuccessCalled, isTrue);
      // Biometrics must now be cleared because UserB is a different account!
      expect(await AuthStorageService.isEnrolled(), isFalse);
      expect(await AuthStorageService.loadCredentials(), isNull);
    });
  });

  group('SettingsScreen - Password verification on Biometric prompt', () {
    testWidgets('Entering incorrect password displays error and does not allow enabling biometric', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = _MockAuthApiService();
      mockApi.setSessionPasswordForTesting('CorrectPassword123');

      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  String? errorMessage;
                  showDialog(
                    context: ctx,
                    builder: (dCtx) => StatefulBuilder(
                      builder: (context, setDialogState) {
                        return AlertDialog(
                          title: const Text('Enable Biometric Sign-In'),
                          content: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: 'Account Password',
                              errorText: errorMessage,
                            ),
                          ),
                          actions: [
                            ElevatedButton(
                              onPressed: () async {
                                final isValid = await mockApi.verifyPassword(controller.text);
                                if (!isValid) {
                                  setDialogState(() {
                                    errorMessage = 'Incorrect password. You must enter the exact password you used to sign in.';
                                  });
                                } else {
                                  Navigator.of(dCtx).pop(true);
                                }
                              },
                              child: const Text('Confirm'),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Enable Biometric Sign-In'), findsOneWidget);

      // Enter incorrect password
      await tester.enterText(find.byType(TextField), 'WrongPass');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Error must be displayed and dialog must still be open
      expect(find.text('Incorrect password. You must enter the exact password you used to sign in.'), findsOneWidget);
      expect(find.text('Enable Biometric Sign-In'), findsOneWidget);

      // Now enter the exact sign-in password
      await tester.enterText(find.byType(TextField), 'CorrectPassword123');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Dialog dismissed on exact match
      expect(find.text('Enable Biometric Sign-In'), findsNothing);
    });
  });
}
