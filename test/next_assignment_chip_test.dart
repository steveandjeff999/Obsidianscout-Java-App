import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/assignment_models.dart';
import 'package:obsidianscout_app/screens/config_editor_screen.dart';
import 'package:obsidianscout_app/widgets/next_assignment_chip.dart';

ScoutingAssignment _a(String id, int number, int team) => ScoutingAssignment.fromJson({
      'id': id,
      'ownerTeamNumber': 1,
      'program': 'FRC',
      'eventKey': '2026aroz',
      'assignedUserId': 'u',
      'assignedUsername': 'scout',
      'assignmentType': 'MATCH',
      'matchKey': '2026aroz_qm$number',
      'matchNumber': number,
      'compLevel': 'qm',
      'targetTeamNumber': team,
      'allianceColor': 'red',
      'status': 'PENDING',
    });

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the assignment the form is on as current, and the following one as up next', (tester) async {
    await tester.pumpWidget(_host(NextAssignmentChip(
      hasAssignments: true,
      current: _a('a2', 2, 16),
      upNext: _a('a5', 5, 254),
      autoAdvance: true,
      onToggleAutoAdvance: (_) {},
      onChange: () {},
    )));
    expect(find.textContaining('Current assignment: '), findsOneWidget);
    expect(find.textContaining('Team 16'), findsOneWidget);
    expect(find.textContaining('Up next: '), findsOneWidget);
    expect(find.textContaining('Team 254'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('says when the current assignment is the last one', (tester) async {
    await tester.pumpWidget(_host(NextAssignmentChip(
      hasAssignments: true,
      current: _a('a2', 2, 16),
      upNext: null,
      autoAdvance: true,
      onToggleAutoAdvance: (_) {},
    )));
    expect(find.textContaining('this is your last assignment'), findsOneWidget);
  });

  testWidgets('mentions earlier open assignments when nothing comes after the current one', (tester) async {
    await tester.pumpWidget(_host(NextAssignmentChip(
      hasAssignments: true,
      current: _a('a9', 9, 3937),
      upNext: null,
      earlierOpen: 2,
      autoAdvance: true,
      onToggleAutoAdvance: (_) {},
    )));
    expect(find.textContaining('You still have 2 earlier assignments open'), findsOneWidget);
  });

  testWidgets('offers Go to it when the selection is not one of the scout\'s assignments', (tester) async {
    ScoutingAssignment? went;
    await tester.pumpWidget(_host(NextAssignmentChip(
      hasAssignments: true,
      current: null,
      upNext: _a('a5', 5, 254),
      autoAdvance: true,
      onToggleAutoAdvance: (_) {},
      onGoTo: (a) => went = a,
    )));
    expect(find.textContaining('Your next assignment: '), findsOneWidget);
    await tester.tap(find.text('Go to it'));
    expect(went?.id, 'a5');
  });

  test('config editor finds dropdown options without a value', () {
    const json = '{"fields":[{"id":"climb","label":"Climb","type":"select","options":['
        '{"label":"None","value":""},{"label":"L1","value":"l1"},{"label":{"en":"L2"},"value":"  "}]},'
        '{"id":"notes","label":"Notes","type":"textarea"}]}';
    expect(blankOptionValues(json), ['Climb: None', 'Climb: L2']);
    expect(blankOptionValues('{"fields":[{"id":"c","label":"C","options":[{"label":"None","value":"n"}]}]}'), isEmpty);
  });
}
