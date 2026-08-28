import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/contact_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';

class _MockContactApiService extends ApiService {
  String? lastType;
  String? lastName;
  String? lastReplyToEmail;
  String? lastMessage;
  ApiResponse<void> responseToReturn = const ApiResponse.success(null);

  @override
  bool get isOnline => true;

  @override
  Future<ApiResponse<void>> sendContactMessage({
    required String type,
    required String name,
    String? replyToEmail,
    required String message,
  }) async {
    lastType = type;
    lastName = name;
    lastReplyToEmail = replyToEmail;
    lastMessage = message;
    return responseToReturn;
  }
}

void main() {
  testWidgets('ContactScreen renders prefilled fields and sends message successfully', (WidgetTester tester) async {
    final mockApi = _MockContactApiService();
    mockApi.setCachedUserForTesting(
      UserModel(
        id: '123',
        username: 'ScoutLeader',
        teamNumber: 2054,
        email: 'scout@team2054.org',
        role: 'SCOUT',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ObsidianUITheme.darkTheme,
        home: Scaffold(
          body: ContactScreen(apiService: mockApi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header and fields
    expect(find.text('Contact Us'), findsOneWidget);
    expect(find.text('ScoutLeader'), findsOneWidget);
    expect(find.text('scout@team2054.org'), findsOneWidget);
    expect(find.text('2054'), findsOneWidget);

    // Enter message
    final messageField = find.byType(TextFormField).last;
    await tester.ensureVisible(messageField);
    await tester.enterText(messageField, 'We found a bug in the match scoring counter!');
    await tester.pumpAndSettle();

    // Tap submit
    final submitBtn = find.widgetWithText(ElevatedButton, 'Send Message');
    expect(submitBtn, findsOneWidget);
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // Verify API called with correct payload
    expect(mockApi.lastType, 'BUG_REPORT');
    expect(mockApi.lastName, 'ScoutLeader');
    expect(mockApi.lastReplyToEmail, 'scout@team2054.org');
    expect(mockApi.lastMessage, 'We found a bug in the match scoring counter!');

    // Verify success snackbar shown and message field cleared
    expect(find.text('Your message has been sent successfully to obsidianscoutfrc@gmail.com!'), findsOneWidget);
  });

  testWidgets('ContactScreen shows validation error on empty message', (WidgetTester tester) async {
    final mockApi = _MockContactApiService();
    mockApi.setCachedUserForTesting(
      UserModel(
        id: '123',
        username: 'ScoutLeader',
        teamNumber: 2054,
        email: 'scout@team2054.org',
        role: 'SCOUT',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ObsidianUITheme.darkTheme,
        home: Scaffold(
          body: ContactScreen(apiService: mockApi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap submit without message
    final submitBtn = find.widgetWithText(ElevatedButton, 'Send Message');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a message'), findsOneWidget);
    expect(mockApi.lastMessage, isNull);
  });

  testWidgets('ContactScreen handles SMTP 503 error gracefully', (WidgetTester tester) async {
    final mockApi = _MockContactApiService();
    mockApi.responseToReturn = const ApiResponse.error(
      statusCode: 503,
      message: 'SMTP email settings are not configured',
    );
    mockApi.setCachedUserForTesting(
      UserModel(
        id: '123',
        username: 'ScoutLeader',
        teamNumber: 2054,
        email: 'scout@team2054.org',
        role: 'SCOUT',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ObsidianUITheme.darkTheme,
        home: Scaffold(
          body: ContactScreen(apiService: mockApi),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final messageField = find.byType(TextFormField).last;
    await tester.ensureVisible(messageField);
    await tester.enterText(messageField, 'Feedback message');
    await tester.pumpAndSettle();

    final submitBtn = find.widgetWithText(ElevatedButton, 'Send Message');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(find.text('SMTP email configuration is missing or incorrect. Please contact your team admin.'), findsOneWidget);
  });
}
