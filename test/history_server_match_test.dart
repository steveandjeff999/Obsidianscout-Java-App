import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/scout_history_models.dart';
import 'package:obsidianscout_app/services/history_server_match.dart';

ScoutHistoryEntry _local({
  String type = 'match',
  int team = 254,
  String event = '2026mitry',
  String? matchKey = 'qm5',
  int? matchNumber,
  Map<String, dynamic> payload = const {},
}) {
  return ScoutHistoryEntry(
    id: 'x',
    type: type,
    action: 'offline_cached',
    timestamp: DateTime(2026),
    teamNumber: team,
    eventKey: event,
    matchKey: matchKey,
    matchNumber: matchNumber,
    status: 'pending',
    payload: payload,
  );
}

Map<String, dynamic> _server(Map<String, dynamic> fields) => {'isPrescout': false, 'data': <String, dynamic>{}, ...fields};

void main() {
  group('isHistoryEntryOnServer', () {
    test('matches a match key with the event prefix', () {
      expect(isHistoryEntryOnServer(_local(), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026MITRY', 'matchKey': '2026mitry_qm5'})
      ]), isTrue);
    });

    test('matches by match number when the server has no key', () {
      expect(isHistoryEntryOnServer(_local(), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026mitry', 'matchNumber': 5})
      ]), isTrue);
    });

    test('reads fields from the nested data map', () {
      expect(isHistoryEntryOnServer(_local(), [
        {'data': {'targetTeamNumber': 254, 'eventKey': '2026mitry', 'matchKey': 'qm5'}}
      ]), isTrue);
    });

    test('does not match another match, team or the prescout copy', () {
      expect(isHistoryEntryOnServer(_local(), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026mitry', 'matchKey': 'qm6'}),
        _server({'targetTeamNumber': 1678, 'eventKey': '2026mitry', 'matchKey': 'qm5'}),
        _server({'isPrescout': true, 'targetTeamNumber': 254, 'eventKey': '2026mitry', 'matchKey': 'qm5'}),
      ]), isFalse);
    });

    test('a server record without match info does not count for a match record', () {
      expect(isHistoryEntryOnServer(_local(), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026mitry'})
      ]), isFalse);
    });

    test('pit records match on team and event', () {
      expect(isHistoryEntryOnServer(_local(type: 'pit', matchKey: null), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026mitry'})
      ]), isTrue);
    });

    test('falls back to the payload team when the record has none', () {
      expect(isHistoryEntryOnServer(_local(team: 0, payload: {'teamNumber': '254'}), [
        _server({'targetTeamNumber': 254, 'eventKey': '2026mitry', 'matchKey': 'qm5'})
      ]), isTrue);
    });
  });
}
