import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/match_pick_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/widgets/match_prediction_card.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

final _match = MatchModel(
  matchKey: '2026test_qm1',
  eventKey: '2026test',
  compLevel: 'qm',
  matchNumber: 1,
  label: 'QM 1',
  redTeams: const ['frc254', 'frc1678', 'frc118'],
  blueTeams: const ['frc971', 'frc973', 'frc604'],
);

void main() {
  group('MatchPickStatus', () {
    test('parses the server response and scores the pick', () {
      final right = MatchPickStatus.fromJson({'matchKey': 'k1', 'predictedWinner': 'red', 'result': 'red', 'locked': true});
      final wrong = MatchPickStatus.fromJson({'matchKey': 'k2', 'predictedWinner': 'red', 'result': 'blue', 'locked': true});
      final tie = MatchPickStatus.fromJson({'matchKey': 'k3', 'predictedWinner': 'blue', 'result': 'tie', 'locked': true});
      final open = MatchPickStatus.fromJson({'matchKey': 'k4', 'predictedWinner': null, 'result': null, 'locked': false});
      expect(right.correct, isTrue);
      expect(wrong.correct, isFalse);
      expect(tie.correct, isNull);
      expect(open.correct, isNull);
      expect(open.locked, isFalse);
    });

    test('a blank pick clears it and keeps the result', () {
      const status = MatchPickStatus(matchKey: 'k', predictedWinner: 'red');
      expect(status.withPick('').predictedWinner, isNull);
      expect(status.withPick('blue', pendingSync: true).pendingSync, isTrue);
      expect(status.asLocked().locked, isTrue);
      expect(status.asLocked().predictedWinner, 'red');
    });
  });

  test('leaderboard parses ranked and unranked rows', () {
    final board = PickLeaderboard.fromJson({
      'scope': 'event',
      'eventKey': '2026abc',
      'matchesScored': 3,
      'rows': [
        {'rank': 1, 'userId': 'a', 'username': 'alice', 'predictions': 4, 'scored': 3, 'correct': 3, 'accuracyPct': 100.0, 'currentStreak': 3, 'bestStreak': 3, 'events': 1},
        {'rank': null, 'userId': 'b', 'username': 'bob', 'predictions': 1, 'scored': 0, 'pending': 1},
      ],
    });
    expect(board.rows.length, 2);
    expect(board.rows.first.rank, 1);
    expect(board.rows.first.accuracyPct, 100.0);
    expect(board.rows.last.rank, isNull);
    expect(board.rows.last.accuracyPct, isNull);
    expect(board.rows.last.pending, 1);
  });

  test('options list events with readable labels', () {
    final options = PickLeaderboardOptions.fromJson({
      'years': [2026, 2025],
      'events': [
        {'eventKey': '2026abc', 'name': 'ABC Regional', 'year': 2026},
        {'eventKey': '2026xyz', 'name': '2026xyz', 'year': 2026},
      ],
    });
    expect(options.years, [2026, 2025]);
    expect(options.events.first.label, 'ABC Regional (2026abc)');
    expect(options.events.last.label, '2026xyz');
  });

  test('settings keep matchPredictionsEnabled off unless the server reports it', () {
    expect(AppSettingsModel.fromJson({'settings': <String, dynamic>{}}).matchPredictionsEnabled, isNull);
    final on = AppSettingsModel.fromJson({'settings': <String, dynamic>{'matchPredictionsEnabled': true}});
    expect(on.matchPredictionsEnabled, isTrue);
    expect(on.toJson()['matchPredictionsEnabled'], isTrue);
    expect(AppSettingsModel().toJson().containsKey('matchPredictionsEnabled'), isFalse);
    final stringOn = AppSettingsModel.fromJson({'settings': <String, dynamic>{'matchPredictionsEnabled': 'true'}});
    expect(stringOn.matchPredictionsEnabled, isTrue);
    final rootOn = AppSettingsModel.fromJson({'matchPredictionsEnabled': true});
    expect(rootOn.matchPredictionsEnabled, isTrue);
  });

  testWidgets('pick buttons show the teams, pick, clear, and lock', (tester) async {
    final picks = <String>[];
    await tester.pumpWidget(_host(MatchPickButtons(
      match: _match,
      status: const MatchPickStatus(matchKey: '2026test_qm1'),
      onPick: picks.add,
    )));
    expect(find.text('254 · 1678 · 118'), findsOneWidget);
    expect(find.text('971 · 973 · 604'), findsOneWidget);
    await tester.tap(find.text('Red'));
    expect(picks, ['red']);

    // Tapping the current pick clears it.
    await tester.pumpWidget(_host(MatchPickButtons(
      match: _match,
      status: const MatchPickStatus(matchKey: '2026test_qm1', predictedWinner: 'red'),
      onPick: picks.add,
    )));
    await tester.tap(find.text('Red'));
    expect(picks, ['red', '']);

    // Locked once the result is in: taps do nothing and the status line reports the outcome.
    const done = MatchPickStatus(matchKey: '2026test_qm1', predictedWinner: 'blue', result: 'blue', locked: true);
    await tester.pumpWidget(_host(Column(children: [
      MatchPickButtons(match: _match, status: done, onPick: picks.add),
      const MatchPickStatusLine(status: done),
    ])));
    await tester.tap(find.text('Red'));
    expect(picks, ['red', '']);
    expect(find.text('Blue won - you called it'), findsOneWidget);
  });
}
