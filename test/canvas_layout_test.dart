import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/canvas_layout.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/widgets/canvas_form_view.dart';
import 'package:obsidianscout_app/widgets/canvas_layout_editor.dart';

ScoutingFieldModel _counter(String id, {int? max}) =>
    ScoutingFieldModel(id: id, label: 'Scored', type: 'counter', phase: 'auto', min: 0, max: max, step: 1);

final _select = ScoutingFieldModel(
  id: 'climb',
  label: 'Climb',
  type: 'select',
  phase: 'endgame',
  options: [
    ScoutingOptionModel(value: 'none', label: 'None'),
    ScoutingOptionModel(value: 'deep', label: 'Deep'),
  ],
);

final _check = ScoutingFieldModel(id: 'left', label: 'Left zone', type: 'checkbox', phase: 'auto');

Map<String, dynamic> _layoutWith(List<Map<String, dynamic>> elements, {List<Map<String, dynamic>>? morePages}) => {
      'mode': 'canvas',
      'width': 1000,
      'height': 500,
      'pages': [
        {'id': 'p1', 'name': 'Auto', 'phase': 'auto', 'elements': elements},
        ...?morePages,
      ],
    };

void main() {
  group('canvas layout model', () {
    test('normalizing clamps values, fixes types and keeps unknown keys', () {
      final l = normalizeCanvasLayout({
        'mode': 'canvas',
        'width': 99999,
        'height': 'abc',
        'future': {'x': 1},
        'pages': [
          {
            'elements': [
              {'type': 'rocket', 'x': -5000, 'w': 50, 'h': 40, 'custom': true},
              'not an element',
            ]
          },
        ],
      });
      expect(l['width'], 4000);
      expect(l['height'], kCanvasDefaultHeight);
      expect(l['future'], {'x': 1});
      expect(l['showUnplaced'], isTrue);
      final page = canvasPages(l).single;
      expect(page['name'], 'Page 1');
      final el = canvasElements(page).single;
      expect(el['type'], 'shape');
      expect(el['x'], -42); // at least 8 units stay on the canvas
      expect(el['custom'], isTrue);
      expect(el['id'], isNotEmpty);
    });

    test('only a canvas-mode layout with pages is active', () {
      expect(canvasIsActive(null), isFalse);
      expect(canvasIsActive({'mode': 'classic', 'pages': []}), isFalse);
      expect(canvasIsActive({'mode': 'canvas', 'pages': []}), isFalse);
      expect(canvasIsActive(_layoutWith([])), isTrue);
    });

    test('image sources and colours are filtered', () {
      expect(canvasSafeSrc('/api/blobs/0b6b6f4e-1111-2222-3333-444455556666'), isNotEmpty);
      expect(canvasSafeSrc('data:image/png;base64,iVBORw0KGgo='), isNotEmpty);
      expect(canvasSafeSrc('https://evil.example/x.png'), isEmpty);
      expect(canvasSafeSrc('javascript:alert(1)'), isEmpty);
      expect(canvasSafeHex('#abc'), '#abc');
      expect(canvasSafeHex('red'), isNull);
      expect(canvasColor('#ff0000', Colors.black), const Color(0xFFFF0000));
    });

    test('button actions follow the field type and its bounds', () {
      final counter = _counter('scored', max: 3);
      expect(canvasApplyAction({'action': 'increment', 'amount': 2}, counter, 0)!.value, 2);
      expect(canvasApplyAction({'action': 'increment', 'amount': 2}, counter, 2)!.value, 3);
      expect(canvasApplyAction({'action': 'decrement'}, counter, 0)!.value, 0);
      expect(canvasApplyAction({'action': 'set', 'value': 1}, counter, 3)!.value, 1);
      expect(canvasApplyAction({'action': 'toggle'}, _check, false)!.value, true);
      expect(canvasApplyAction({'action': 'set', 'value': 'false'}, _check, true)!.value, false);
      expect(canvasApplyAction({'action': 'cycle'}, _select, 'deep')!.value, 'none');
      expect(canvasApplyAction({'action': 'set', 'value': 'deep'}, _select, 'none')!.value, 'deep');
      expect(canvasApplyAction({'action': 'set', 'value': 'missing'}, _select, 'none'), isNull);
      expect(canvasApplyAction({'action': 'increment'}, null, 0), isNull);
      // An action the field type doesn't support falls back to its default.
      expect(canvasApplyAction({'action': 'cycle'}, counter, 1)!.value, 2);
    });

    test('labels, displayed values and on state', () {
      final counter = _counter('scored');
      expect(canvasButtonLabel({'action': 'increment', 'amount': 1}, counter), '+1 Scored');
      expect(canvasButtonLabel({'label': ''}, counter), '');
      expect(canvasButtonLabel({'action': 'set', 'value': 'deep'}, _select), 'Deep');
      expect(canvasDisplayValue(counter, null), '0');
      expect(canvasDisplayValue(_select, 'deep'), 'Deep');
      expect(canvasDisplayValue(_check, true), 'Yes');
      expect(canvasButtonIsOn({'action': 'set', 'value': 'deep'}, _select, 'deep'), isTrue);
      expect(canvasButtonIsOn({'action': 'toggle'}, _check, false), isFalse);
    });

    test('generating from fields makes one page per phase with every field placed once', () {
      final fields = [
        _counter('auto_scored'),
        _check,
        ScoutingFieldModel(id: 'teleop_cycles', label: 'Cycles', type: 'counter'),
        _select,
        ScoutingFieldModel(id: 'sec', label: 'Section', type: 'section'),
      ];
      final l = canvasGenerateFromFields({'width': 1280, 'height': 200}, fields);
      expect(canvasPages(l).map((p) => p['phase']), ['auto', 'teleop', 'endgame']);
      expect(canvasPlacedFieldIds(l), {'auto_scored', 'left', 'teleop_cycles', 'climb'});
      expect(l['height'], greaterThanOrEqualTo(200));
      expect(canvasPageOfField(l, 'climb'), 2);
      expect(canvasPageOfField(l, 'sec'), -1);
    });
  });

  group('canvas scout form', () {
    testWidgets('a tap button changes its field and a value element shows it', (tester) async {
      final values = <String, dynamic>{'scored': 0};
      final field = _counter('scored');
      late StateSetter rebuild;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(builder: (context, setState) {
              rebuild = setState;
              return CanvasScoutForm(
                layout: _layoutWith([
                  {'id': 'b1', 'type': 'button', 'x': 10, 'y': 10, 'w': 300, 'h': 150, 'fieldId': 'scored', 'action': 'increment', 'label': 'SCORE'},
                  {'id': 'v1', 'type': 'value', 'x': 400, 'y': 10, 'w': 300, 'h': 150, 'fieldId': 'scored', 'prefix': 'Total: '},
                  {'id': 'b2', 'type': 'button', 'x': 10, 'y': 300, 'w': 200, 'h': 100, 'fieldId': 'gone'},
                  {'id': 'f1', 'type': 'field', 'x': 400, 'y': 250, 'w': 380, 'h': 120, 'fieldId': 'left'},
                  {'id': 'f2', 'type': 'field', 'x': 10, 'y': 420, 'w': 380, 'h': 70, 'fieldId': 'climb'},
                ]),
                fields: [field, _check, _select],
                values: values,
                onChanged: (id, v) => rebuild(() => values[id] = v),
              );
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Total: 0'), findsOneWidget);
      await tester.tap(find.text('SCORE'));
      await tester.pumpAndSettle();
      expect(values['scored'], 1);
      expect(find.text('Total: 1'), findsOneWidget);
      // A button for a field the form doesn't have is left out.
      expect(find.text('Button'), findsNothing);
    });

    testWidgets('pages switch, and unplaced fields are listed under the canvas', (tester) async {
      final key = GlobalKey<CanvasScoutFormState>();
      final phases = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanvasScoutForm(
              key: key,
              layout: _layoutWith([], morePages: [
                {
                  'id': 'p2',
                  'name': 'Endgame',
                  'phase': 'endgame',
                  'elements': [
                    {'id': 'e1', 'type': 'text', 'x': 10, 'y': 10, 'w': 400, 'h': 80, 'text': 'Climb now'},
                  ],
                },
              ]),
              fields: [_check],
              values: const {'left': false},
              onChanged: (_, __) {},
              onPageChanged: phases.add,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(phases, ['auto']);
      expect(find.text('MORE FIELDS'), findsOneWidget);
      expect(find.text('Climb now'), findsNothing);
      await tester.tap(find.text('Endgame'));
      await tester.pumpAndSettle();
      expect(find.text('Climb now'), findsOneWidget);
      expect(phases.last, 'endgame');
      key.currentState!.previousPage();
      await tester.pumpAndSettle();
      expect(key.currentState!.currentPhase, 'auto');
    });
  });

  group('canvas editor', () {
    testWidgets('starts a canvas from the fields and reports it', (tester) async {
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanvasLayoutEditor(
              layout: null,
              fields: [_counter('auto_scored'), _select],
              onChanged: (l) => sent = l,
              pickImage: () async => null,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start a canvas from my fields'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start a canvas from my fields'));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(sent!['mode'], 'canvas');
      expect(canvasPlacedFieldIds(sent!), {'auto_scored', 'climb'});
      expect(find.text('Arrange and set up'), findsOneWidget);
    });

    testWidgets('on a phone: add a tap button, see its settings, and drag it', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? sent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanvasLayoutEditor(
              layout: _layoutWith([]),
              fields: [_counter('scored')],
              onChanged: (l) => sent = l,
              pickImage: () async => null,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tap button'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap button'));
      await tester.pumpAndSettle();
      final button = canvasElements(canvasPages(sent!).single).single;
      expect(button['type'], 'button');
      expect(button['fieldId'], 'scored');
      expect(button['action'], 'increment');
      expect(find.text('When tapped'), findsOneWidget);

      final label = find.text('+1 Scored');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final before = button['x'] as int;
      await tester.drag(label, const Offset(60, 0));
      await tester.pumpAndSettle();
      final moved = canvasElements(canvasPages(sent!).single).single;
      expect(moved['x'], greaterThan(before));
      expect((moved['x'] as int) % 10, 0); // snapped to the grid
    });

    testWidgets('offers the season default when the team has no layout, and copying it reports a layout', (tester) async {
      Map<String, dynamic>? sent;
      final season = _layoutWith([
        {'id': 'b1', 'type': 'button', 'x': 10, 'y': 10, 'w': 200, 'h': 100, 'fieldId': 'scored'},
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanvasLayoutEditor(
              layout: null,
              fields: [_counter('scored')],
              seasonLayout: season,
              seasonYear: 2026,
              onChanged: (l) => sent = l,
              pickImage: () async => null,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026 default canvas'), findsOneWidget);
      await tester.ensureVisible(find.text('Make my own copy to change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make my own copy to change'));
      await tester.pumpAndSettle();
      expect(sent, isNotNull);
      expect(canvasElements(canvasPages(sent!).single).single['fieldId'], 'scored');
      expect(identical(sent, season), isFalse);
    });
  });
}
