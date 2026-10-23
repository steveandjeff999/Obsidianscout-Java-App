import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/assignment_models.dart';

void main() {
  test('parses the shifts response the server sends', () {
    final res = AssignmentShiftsResponse.fromJson({
      'createdCount': 8,
      'shifts': [
        {
          'shift': {
            'id': 's1',
            'eventKey': '2026txhou',
            'name': 'Friday morning',
            'day': '2026-03-06',
            'startTime': '08:00',
            'endTime': '12:00',
            'stageFilter': 'qm',
            'matchScouterIds': ['', 'u1'],
            'qualMode': 'ALLIANCE',
            'qualScouterIds': ['u2', 'u3'],
            'createdByUserId': 'admin',
            'lastAppliedAt': '2026-03-05T10:00:00Z',
            'appliedCount': 8,
          },
          'matchCount': 1,
          'scouterNames': {'u1': 'alex', 'u2': 'bob', 'u3': 'cam'},
        },
      ],
    });

    expect(res.createdCount, 8);
    final view = res.shifts.single;
    expect(view.matchCount, 1);
    expect(view.scouterNames['u1'], 'alex');
    expect(view.shift.day, '2026-03-06');
    // Open seats keep their place so later seats stay on the right station
    expect(view.shift.matchScouterIds, ['', 'u1']);
    expect(view.shift.qualMode, 'ALLIANCE');
    expect(view.shift.qualScouterIds, ['u2', 'u3']);
    expect(view.shift.appliedCount, 8);
  });

  test('a new shift saves without an id so the server creates it', () {
    final body = AssignmentShift(
      eventKey: '2026txhou',
      day: '2026-03-06',
      startTime: '08:00',
      endTime: '12:00',
      matchScouterIds: const ['u1', '', 'u2'],
    ).toSaveJson();

    expect(body['id'], isNull);
    expect(body['qualMode'], 'TEAMS');
    expect(body['matchScouterIds'], ['u1', '', 'u2']);
  });
}
