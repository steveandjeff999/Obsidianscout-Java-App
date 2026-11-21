import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/models/validation_models.dart';
import 'package:obsidianscout_app/shell/shell_screen_registry.dart';
import 'package:obsidianscout_app/widgets/simple_markdown.dart';
import 'package:obsidianscout_app/widgets/timer_field_widget.dart';

void main() {
  group('timer field', () {
    test('formats seconds and minutes', () {
      expect(formatTimerSeconds(0), '0.0s');
      expect(formatTimerSeconds(12.34), '12.3s');
      expect(formatTimerSeconds(65), '1:05.0');
      expect(formatTimerSeconds(null), '0.0s');
    });

    test('config keeps the timer mode through a round trip', () {
      final f = ScoutingFieldModel.fromJson({'id': 'cyc', 'label': 'Cycle', 'type': 'timer', 'mode': 'cycle'});
      expect(f.mode, 'cycle');
      expect(f.toJson()['mode'], 'cycle');
      // Mode is only written for timers.
      final counter = ScoutingFieldModel.fromJson({'id': 'c', 'label': 'C', 'type': 'counter', 'mode': 'cycle'});
      expect(counter.toJson().containsKey('mode'), isFalse);
    });

    test('config keeps the canvas layout through a round trip and edits', () {
      final layout = {
        'mode': 'canvas',
        'width': 1280,
        'pages': [
          {'id': 'p1', 'name': 'Auto', 'elements': [{'id': 'e1', 'type': 'button', 'fieldId': 'cyc'}]}
        ],
      };
      final config = ScoutingConfigModel.fromJson({'title': 'T', 'fields': const [], 'layout': layout});
      expect(config.toJson()['layout'], layout);
      // Editing fields from the app must not drop it.
      final edited = config.copyWith(fields: [ScoutingFieldModel(id: 'cyc', label: 'Cycle', type: 'timer')]);
      expect(edited.toJson()['layout'], layout);
      // No layout stays absent, so the season's default canvas still applies.
      expect(ScoutingConfigModel.fromJson({'title': 'T'}).toJson().containsKey('layout'), isFalse);
    });

    testWidgets('stopwatch records elapsed seconds and reset clears it', (tester) async {
      dynamic value;
      final field = ScoutingFieldModel(id: 'climb', label: 'Climb time', type: 'timer');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TimerFieldWidget(
              field: field,
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ));
      expect(find.text('Start'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await tester.pump();
      // The stopwatch uses the real clock, so let real time pass.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(value, isA<double>());
      expect(value as double, greaterThanOrEqualTo(0.3));
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(value, isNull);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('cycle mode shows a Lap button and loads a saved value', (tester) async {
      final field = ScoutingFieldModel(id: 'cyc', label: 'Cycle time', type: 'timer', mode: 'cycle');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TimerFieldWidget(field: field, value: 8.4, onChanged: (_) {})),
      ));
      expect(find.text('Lap'), findsOneWidget);
      expect(find.text('8.4s'), findsOneWidget);
      expect(find.text('Restored value'), findsOneWidget);
    });
  });

  group('match videos', () {
    test('keeps only plain YouTube watch links, without duplicates', () {
      final urls = parseMatchVideoUrls([
        {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=abcDEF12345'},
        {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=abcDEF12345'},
        {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=xyz789_-AB&t=90s'},
        {'type': 'youtube', 'url': 'javascript:alert(1)'},
        {'type': 'youtube', 'url': 'https://evil.example/watch?v=abcDEF12345'},
        'not a map',
      ]);
      expect(urls, [
        'https://www.youtube.com/watch?v=abcDEF12345',
        'https://www.youtube.com/watch?v=xyz789_-AB&t=90s',
      ]);
      expect(parseMatchVideoUrls(null), isEmpty);
    });

    test('match and validation models read videos', () {
      final m = MatchModel.fromJson({
        'matchKey': '2026test_qm1',
        'eventKey': '2026test',
        'videos': [
          {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=abcDEF12345'}
        ],
      });
      expect(m.videoUrls, hasLength(1));

      final v = MatchValidationModel.fromJson({
        'matchKey': '2026test_qm1',
        'videos': [
          {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=abcDEF12345'}
        ],
      });
      expect(v.videoUrls, hasLength(1));
      expect(MatchValidationModel.fromJson(v.toJson()).videoUrls, v.videoUrls);
    });
  });

  group('simple markdown', () {
    testWidgets('renders headings, lists, tables and links', (tester) async {
      String? tapped;
      const md = '# Title\n\nSome **bold** text with `code` and a [link](GETTING_STARTED.md).\n\n'
          '- one\n- two\n\n1. first\n2. second\n\n| A | B |\n|---|---|\n| x | y |\n\n'
          'Keep event_key and team_number as they are.';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SimpleMarkdown(data: md, resolveImage: (s) => s, onLink: (h) => tapped = h),
          ),
        ),
      ));
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      // Underscores inside words are not italics.
      expect(find.textContaining('event_key and team_number', findRichText: true), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring('link'));
      expect(tapped, 'GETTING_STARTED.md');
    });
  });

  group('new app pages', () {
    test('docs, tutorials, public data and assistant are registered', () {
      expect(ShellScreenRegistry.screenCount, 59);
      expect(ShellScreenRegistry.titleKeys.length, ShellScreenRegistry.screenCount);
      expect(ShellScreenRegistry.subtitleKeys.length, ShellScreenRegistry.screenCount);
      final ids = [for (var i = 0; i < ShellScreenRegistry.screenCount; i++) ShellScreenRegistry.getPageIdForIndex(i)];
      expect(ids.sublist(55), ['docs', 'tutorials', 'public-data', 'assistant']);
      expect(ids.toSet().length, ids.length, reason: 'page ids must be unique');
    });

    test('tutorials, assistant and public data need no page permission', () {
      for (final p in ['tutorials', 'assistant', 'public-data']) {
        expect(bypassPages, contains(p));
      }
      expect(bypassPages, isNot(contains('docs')));
    });
  });
}
