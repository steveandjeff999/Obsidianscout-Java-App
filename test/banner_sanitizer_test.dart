import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/widgets/obsidian_banner_widget.dart';
import 'package:obsidianscout_app/widgets/sanitized_banner_text.dart';

class _MockApiService extends ApiService {
  List<Map<String, dynamic>> banners = [];
  @override
  bool get isOnline => true;
  @override
  Future<List<Map<String, dynamic>>> fetchBanners() async => banners;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SanitizedBannerText XSS and Formatting Tests', () {
    testWidgets('strips <script> tags and malicious contents entirely', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: 'Attention! <script>alert("xss")</script>Please read.',
            ),
          ),
        ),
      );

      expect(find.textContaining('Attention!'), findsOneWidget);
      expect(find.textContaining('Please read.'), findsOneWidget);
      expect(find.textContaining('alert'), findsNothing);
      expect(find.textContaining('<script>'), findsNothing);
    });

    testWidgets('strips <iframe>, <style>, and <img> tags', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: '<style>body { color: red; }</style><iframe src="evil.com"></iframe>Hello <img src="x" onerror="evil()"/>World',
            ),
          ),
        ),
      );

      expect(find.textContaining('Hello World'), findsOneWidget);
      expect(find.textContaining('iframe'), findsNothing);
      expect(find.textContaining('evil.com'), findsNothing);
      expect(find.textContaining('style'), findsNothing);
    });

    testWidgets('neutralizes javascript: URLs in hyperlinks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: '<a href="javascript:alert(1)">Click Malicious Link</a>',
            ),
          ),
        ),
      );

      // Text is rendered safely without active hyperlink
      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;

      // Ensure no TapGestureRecognizer was registered for javascript: link
      bool hasTapRecognizer = false;
      rootSpan.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) {
          hasTapRecognizer = true;
        }
        return true;
      });
      expect(hasTapRecognizer, isFalse);
    });

    testWidgets('renders safe https: hyperlinks with link recognizer and style', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: 'Check <a href="https://frc-events.firstinspires.org">Schedule</a> now',
              linkColor: Colors.amber,
            ),
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;

      bool foundLink = false;
      rootSpan.visitChildren((span) {
        if (span is TextSpan && span.text == 'Schedule') {
          if (span.recognizer != null && span.style?.color == Colors.amber) {
            foundLink = true;
          }
        }
        return true;
      });
      expect(foundLink, isTrue);
    });

    testWidgets('supports bold, italic, and decoded HTML entities', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: '<b>Important:</b> Teams &amp; robots &lt;ready&gt;',
            ),
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;

      bool foundBold = false;
      bool foundEntities = false;
      rootSpan.visitChildren((span) {
        if (span is TextSpan) {
          if (span.text == 'Important:' && span.style?.fontWeight == FontWeight.bold) {
            foundBold = true;
          }
          if (span.text != null && span.text!.contains('Teams & robots <ready>')) {
            foundEntities = true;
          }
        }
        return true;
      });

      expect(foundBold, isTrue);
      expect(foundEntities, isTrue);
    });

    testWidgets('supports markdown bold and links', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SanitizedBannerText(
              text: '**Warning:** [Docs](https://docs.obsidianscout.com)',
            ),
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(richTextFinder);
      final rootSpan = richText.text as TextSpan;

      bool foundBold = false;
      bool foundLink = false;
      rootSpan.visitChildren((span) {
        if (span is TextSpan) {
          if (span.text == 'Warning:' && span.style?.fontWeight == FontWeight.bold) {
            foundBold = true;
          }
          if (span.text == 'Docs' && span.recognizer != null) {
            foundLink = true;
          }
        }
        return true;
      });

      expect(foundBold, isTrue);
      expect(foundLink, isTrue);
    });
  });

  group('ObsidianBannerWidget with SanitizedBannerText', () {
    testWidgets('renders malicious banner safely without raw scripts or injection', (tester) async {
      final mock = _MockApiService();
      mock.banners = [
        {
          'id': 'xss-banner-1',
          'message': '<b>System:</b> <script>alert("owned")</script>Normal text',
          'bannerType': 'danger',
          'isDismissible': false,
          'isExpandable': true,
          'expandableMessage': 'Details <img src=x onerror=alert(1)>with <a href="https://example.com">link</a>',
        }
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObsidianBannerWidget(apiService: mock),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('System:'), findsOneWidget);
      expect(find.textContaining('Normal text'), findsOneWidget);
      expect(find.textContaining('alert'), findsNothing);
      expect(find.textContaining('<script>'), findsNothing);

      // Expand banner details
      await tester.tap(find.text('Read More'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Details with'), findsOneWidget);
      expect(find.textContaining('onerror'), findsNothing);
      expect(find.textContaining('link'), findsOneWidget);
    });
  });
}
