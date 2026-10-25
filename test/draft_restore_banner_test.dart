import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/scouting_draft_service.dart';
import 'package:obsidianscout_app/widgets/draft_restore_banner.dart';

void main() {
  testWidgets('DraftRestoreBanner displays context, time, and triggers callbacks', (tester) async {
    bool restored = false;
    bool discarded = false;

    final draft = ScoutingDraft(
      formType: 'match',
      matchKey: '2026casf_qm12',
      teamNumber: 254,
      savedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      data: {'auto_coral': 3},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraftRestoreBanner(
            draft: draft,
            onRestore: () => restored = true,
            onDiscard: () => discarded = true,
          ),
        ),
      ),
    );

    // Verify text
    expect(find.text('Unsaved draft from 5m ago'), findsOneWidget);
    expect(find.text('QM12 · Team 254'), findsOneWidget);

    // Tap Restore
    await tester.tap(find.text('Restore'));
    await tester.pump();
    expect(restored, isTrue);

    // Tap Discard
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(discarded, isTrue);
  });
}
