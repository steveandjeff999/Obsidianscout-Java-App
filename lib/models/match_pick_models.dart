// Match predictions game: scouts pick red or blue to win each match and compete on an accuracy leaderboard.
// Mirrors MatchPredictionService.kt on the server. "Pick" names avoid clashing with the analytics
// MatchPredictionResponse (the Predictor screen's score forecast).

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

String? _str(dynamic v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

/// The signed-in scout's pick for one match, with the match's lock state and result.
class MatchPickStatus {
  final String matchKey;

  /// "red" or "blue", or null without a pick.
  final String? predictedWinner;

  /// "red", "blue" or "tie" once the match has a result.
  final String? result;

  /// True once the result is in; picks can't change after that.
  final bool locked;

  /// Saved on this device and waiting to upload.
  final bool pendingSync;

  const MatchPickStatus({
    required this.matchKey,
    this.predictedWinner,
    this.result,
    this.locked = false,
    this.pendingSync = false,
  });

  /// Whether the pick was right; null without a pick, before the result, or on a tie.
  bool? get correct {
    if (predictedWinner == null || result == null || result == 'tie') return null;
    return predictedWinner == result;
  }

  factory MatchPickStatus.fromJson(Map<String, dynamic> json) => MatchPickStatus(
        matchKey: json['matchKey']?.toString() ?? '',
        predictedWinner: _str(json['predictedWinner']),
        result: _str(json['result']),
        locked: json['locked'] == true,
      );

  MatchPickStatus withPick(String? winner, {bool pendingSync = false}) => MatchPickStatus(
        matchKey: matchKey,
        predictedWinner: winner == null || winner.isEmpty ? null : winner,
        result: result,
        locked: locked,
        pendingSync: pendingSync,
      );

  MatchPickStatus asLocked() => MatchPickStatus(
        matchKey: matchKey,
        predictedWinner: predictedWinner,
        result: result,
        locked: true,
      );
}

/// Outcome of saving a pick.
enum MatchPickSaveResult { saved, queued, locked, failed }

class PickLeaderboardRow {
  final int? rank;
  final String userId;
  final String username;
  final String role;
  final int predictions;
  final int scored;
  final int correct;
  final int ties;
  final int pending;
  final double? accuracyPct;
  final int currentStreak;
  final int bestStreak;
  final int events;

  const PickLeaderboardRow({
    this.rank,
    required this.userId,
    required this.username,
    this.role = '',
    this.predictions = 0,
    this.scored = 0,
    this.correct = 0,
    this.ties = 0,
    this.pending = 0,
    this.accuracyPct,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.events = 0,
  });

  factory PickLeaderboardRow.fromJson(Map<String, dynamic> json) => PickLeaderboardRow(
        rank: json['rank'] is num ? (json['rank'] as num).toInt() : null,
        userId: json['userId']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        predictions: _int(json['predictions']),
        scored: _int(json['scored']),
        correct: _int(json['correct']),
        ties: _int(json['ties']),
        pending: _int(json['pending']),
        accuracyPct: _double(json['accuracyPct']),
        currentStreak: _int(json['currentStreak']),
        bestStreak: _int(json['bestStreak']),
        events: _int(json['events']),
      );
}

class PickLeaderboard {
  /// "event" or "year".
  final String scope;
  final String? eventKey;
  final String? eventName;
  final int? year;
  final int matchesScored;
  final List<PickLeaderboardRow> rows;

  const PickLeaderboard({
    required this.scope,
    this.eventKey,
    this.eventName,
    this.year,
    this.matchesScored = 0,
    this.rows = const [],
  });

  factory PickLeaderboard.fromJson(Map<String, dynamic> json) => PickLeaderboard(
        scope: json['scope']?.toString() ?? 'event',
        eventKey: _str(json['eventKey']),
        eventName: _str(json['eventName']),
        year: json['year'] is num ? (json['year'] as num).toInt() : null,
        matchesScored: _int(json['matchesScored']),
        rows: (json['rows'] is List ? json['rows'] as List : const [])
            .whereType<Map>()
            .map((r) => PickLeaderboardRow.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

class PickLeaderboardEvent {
  final String eventKey;
  final String? name;
  final int? year;

  const PickLeaderboardEvent({required this.eventKey, this.name, this.year});

  String get label => name != null && name!.toLowerCase() != eventKey ? '$name ($eventKey)' : eventKey;
}

class PickLeaderboardOptions {
  final List<int> years;
  final List<PickLeaderboardEvent> events;

  const PickLeaderboardOptions({this.years = const [], this.events = const []});

  factory PickLeaderboardOptions.fromJson(Map<String, dynamic> json) => PickLeaderboardOptions(
        years: (json['years'] is List ? json['years'] as List : const []).map(_int).where((y) => y > 0).toList(),
        events: (json['events'] is List ? json['events'] as List : const [])
            .whereType<Map>()
            .map((e) => PickLeaderboardEvent(
                  eventKey: e['eventKey']?.toString() ?? '',
                  name: _str(e['name']),
                  year: e['year'] is num ? (e['year'] as num).toInt() : null,
                ))
            .where((e) => e.eventKey.isNotEmpty)
            .toList(),
      );
}
