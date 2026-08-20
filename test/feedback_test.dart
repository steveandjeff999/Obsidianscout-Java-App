import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/widgets/obsidian_feedback.dart';

void main() {
  group('ApiResponse Model Tests', () {
    test('formats success feedback correctly with status code', () {
      const response = ApiResponse<void>.success(null, statusCode: 200, message: 'Saved successfully');
      expect(response.success, isTrue);
      expect(response.statusCode, 200);
      expect(response.formatFeedback(actionName: 'Data Save'), 'Data Save: Success (HTTP 200): Saved successfully');
    });

    test('formats HTTP error feedback correctly with status code and error message', () {
      const response = ApiResponse<void>.error(statusCode: 400, message: 'Invalid payload: matchNumber missing');
      expect(response.success, isFalse);
      expect(response.statusCode, 400);
      expect(response.formatFeedback(actionName: 'Match Scout'), 'Match Scout: Failed (HTTP 400 - Invalid payload: matchNumber missing)');
    });

    test('formats HTTP 500 server error feedback', () {
      const response = ApiResponse<void>.error(statusCode: 500, message: 'Database connection failed');
      expect(response.success, isFalse);
      expect(response.statusCode, 500);
      expect(response.formatFeedback(actionName: 'Migration'), 'Migration: Failed (HTTP 500 - Database connection failed)');
    });

    test('formats offline response feedback', () {
      const response = ApiResponse<void>.error(isOffline: true);
      expect(response.success, isFalse);
      expect(response.isOffline, isTrue);
      expect(response.formatFeedback(actionName: 'Save'), 'Save: Failed - Device is offline or server unreachable.');
    });

    test('parses HTTP response with JSON error body', () {
      final httpResponse = http.Response(
        jsonEncode({'error': 'Unauthorized admin action'}),
        403,
      );
      final apiResponse = ApiResponse.fromHttpResponse(httpResponse);
      expect(apiResponse.success, isFalse);
      expect(apiResponse.statusCode, 403);
      expect(apiResponse.message, 'Unauthorized admin action');
      expect(apiResponse.formatFeedback(), 'Failed (HTTP 403 - Unauthorized admin action)');
    });

    test('parses HTTP 201 response with JSON payload', () {
      final httpResponse = http.Response(
        jsonEncode({'migratedCount': 15, 'success': true}),
        201,
      );
      final apiResponse = ApiResponse<Map<String, dynamic>>.fromHttpResponse(
        httpResponse,
        parser: (json) => json as Map<String, dynamic>,
      );
      expect(apiResponse.success, isTrue);
      expect(apiResponse.statusCode, 201);
      expect(apiResponse.data?['migratedCount'], 15);
    });
  });

  group('ObsidianFeedback Widget Tests', () {
    tearDown(() {
      ObsidianFeedback.dismiss();
    });

    testWidgets('renders success feedback banner with HTTP status code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ObsidianFeedback.showSuccess(
                      context,
                      title: 'Config Saved',
                      message: 'Match config saved (HTTP 200)',
                      statusCode: 200,
                    );
                  },
                  child: const Text('Trigger Success'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Success'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Config Saved'), findsOneWidget);
      expect(find.text('Match config saved (HTTP 200)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      ObsidianFeedback.dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('renders server error feedback banner with HTTP 500 response code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ObsidianFeedback.showError(
                      context,
                      title: 'Migration Failed',
                      message: 'Server error occurred during column migration',
                      statusCode: 500,
                    );
                  },
                  child: const Text('Trigger Error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Migration Failed'), findsOneWidget);
      expect(find.text('Server error occurred during column migration'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      ObsidianFeedback.dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('renders offline feedback banner via showApiResponse', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ObsidianFeedback.showApiResponse(
                      context,
                      const ApiResponse<void>.error(isOffline: true),
                      actionName: 'Alliance Selection',
                    );
                  },
                  child: const Text('Trigger Offline'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Offline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Alliance Selection'), findsOneWidget);
      expect(find.text('Device is offline or server is unreachable.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      ObsidianFeedback.dismiss();
      await tester.pumpAndSettle();
    });
  });
}
