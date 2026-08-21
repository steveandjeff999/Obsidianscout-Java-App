import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/widgets/obsidian_image_preview_card.dart';

void main() {
  // A tiny 1x1 transparent PNG data URI
  const testDataUrl = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

  group('ObsidianImagePreviewCard and ObsidianImageThumbnail Widget Tests', () {
    testWidgets('ObsidianImageThumbnail renders thumbnail and opens zoom dialog on tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ObsidianImageThumbnail(
                imageSource: testDataUrl,
                title: 'Team 2481 Robot Photo',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ObsidianImageThumbnail), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      // Tap on the thumbnail
      await tester.tap(find.byType(ObsidianImageThumbnail));
      await tester.pumpAndSettle();

      // Zoom dialog should be shown with title and InteractiveViewer
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Team 2481 Robot Photo'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Close the dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('ObsidianImagePreviewCard renders preview with label and tap to zoom', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ObsidianImagePreviewCard(
                label: 'Robot Intake Mechanism',
                imageSource: testDataUrl,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ObsidianImagePreviewCard), findsOneWidget);
      expect(find.text('Robot Intake Mechanism'), findsOneWidget);
      expect(find.text('Tap to Zoom'), findsOneWidget);

      // Tap to zoom
      await tester.tap(find.text('Tap to Zoom'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Robot Intake Mechanism'), findsNWidgets(2));
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('ObsidianImageThumbnail renders empty when image source is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ObsidianImageThumbnail(imageSource: null),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
    });
  });
}
