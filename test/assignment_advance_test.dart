import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/assignment_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/models/scout_history_models.dart';
import 'package:obsidianscout_app/services/assignment_advance_service.dart';
import 'package:obsidianscout_app/services/scout_history_service.dart';

ScoutingAssignment _match(String id, int number, int team, {String status = 'PENDING', int? scheduled, String level = 'qm', int? set}) {
  final key = set != null ? '2026test_$level${set}m$number' : '2026test_$level$number';
  return ScoutingAssignment.fromJson({
    'id': id,
    'ownerTeamNumber': 1,
    'program': 'FRC',
    'eventKey': '2026test',
    'assignedUserId': 'u',
    'assignedUsername': 'scout',
    'assignmentType': 'MATCH',
    'matchKey': key,
    'matchNumber': number,
    'compLevel': level,
    'targetTeamNumber': team,
    'status': status,
    if (scheduled != null) 'scheduledTime': scheduled,
  });
}

MatchModel _m(int number) => MatchModel(matchKey: '2026test_qm$number', eventKey: '2026test', compLevel: 'qm', matchNumber: number, label: 'QM $number');

void main() {
  final matches = [for (var i = 1; i <= 30; i++) _m(i)];
  final assignments = [_match('a10', 10, 254), _match('a14', 14, 1678), _match('a20', 20, 971)];

  test('advances to the next assignment after the match just scouted', () {
    final next = AssignmentAdvanceService.next(assignments,
        type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm10', justCompletedIds: {'a10'});
    expect(next!.assignment!.id, 'a14');
  });

  test('a manual pick in between still moves forward, not back', () {
    final next = AssignmentAdvanceService.next(assignments, type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm12');
    expect(next!.assignment!.id, 'a14');
  });

  test('skips assignments whose match has already been played', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    final pastSecs = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    final list = [_match('a14', 14, 1678, scheduled: pastSecs), _match('a20', 20, 971)];
    final next = AssignmentAdvanceService.next(list, type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm10', now: now);
    expect(next!.assignment!.id, 'a20');
    expect(next.skippedPast, 1);
  });

  test('reports no more assignments once everything is done', () {
    final done = [_match('a10', 10, 254, status: 'COMPLETED')];
    final next = AssignmentAdvanceService.next(done, type: 'MATCH', matches: matches);
    expect(next, isNotNull);
    expect(next!.assignment, isNull);
  });

  test('returns null when the scout has no assignments of that type', () {
    expect(AssignmentAdvanceService.next(assignments, type: 'PIT'), isNull);
  });

  test('an event whose times are all in the past still advances instead of saying none are left', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    final past = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final list = [for (var i = 1; i <= 30; i++) _match('a$i', i, 1000 + i, scheduled: past)];
    final first = AssignmentAdvanceService.next(list, type: 'MATCH', matches: matches, now: now);
    expect(first!.assignment!.id, 'a1');
    final afterFive = AssignmentAdvanceService.next(list,
        type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm5', justCompletedIds: {'a5'}, now: now);
    expect(afterFive!.assignment!.id, 'a6');
    expect(afterFive.remaining, 29);
  });

  test('goes practice, then qualifications, then playoffs regardless of list order', () {
    final list = [
      _match('final', 1, 1, level: 'f', set: 1),
      _match('qf', 1, 2, level: 'qf', set: 2),
      _match('qm2', 2, 3),
      _match('sf', 1, 4, level: 'sf', set: 1),
      _match('pr3', 3, 5, level: 'practice'),
      _match('qm40', 40, 6),
    ];
    final order = <String>[];
    var done = <String>{};
    String? after;
    for (var i = 0; i < list.length; i++) {
      final next = AssignmentAdvanceService.next(list, type: 'MATCH', afterMatchKey: after, justCompletedIds: done)!;
      order.add(next.assignment!.id);
      done = {...done, next.assignment!.id};
      after = next.assignment!.matchKey;
    }
    expect(order, ['pr3', 'qm2', 'qm40', 'qf', 'sf', 'final']);
  });

  test('a qualification entry does not mark a practice or playoff assignment with the same number as done', () {
    final practice = _match('p5', 5, 254, level: 'practice');
    final history = ScoutHistoryEntry(
      id: 'h', type: 'match', action: 'direct_upload', timestamp: DateTime.now(), teamNumber: 254,
      eventKey: '2026test', matchKey: '2026test_qm5', matchNumber: 5, status: 'synced', payload: const {},
    );
    expect(ScoutHistoryService.isAssignmentScoutedLocally(practice, history: [history]), isFalse);
    expect(ScoutHistoryService.isAssignmentScoutedLocally(_match('q5', 5, 254), history: [history]), isTrue);
  });

  test('with noWrap, nothing comes after the last assignment even when earlier ones are open', () {
    final next = AssignmentAdvanceService.next(assignments,
        type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm20', justCompletedIds: {'a20'}, noWrap: true);
    expect(next!.assignment, isNull);
    expect(next.remaining, 2);
    // Without noWrap the advance still falls back to the earliest open one.
    final wrapped = AssignmentAdvanceService.next(assignments,
        type: 'MATCH', matches: matches, afterMatchKey: '2026test_qm20', justCompletedIds: {'a20'});
    expect(wrapped!.assignment!.id, 'a10');
  });
}
