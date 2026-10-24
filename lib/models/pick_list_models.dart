/// A team's ranked pick list for one event, as returned by `/api/alliance-selection/picklist`.
///
/// [dnp] is the Do Not Pick list shared with Alliance Selection; the server never
/// includes those teams in [ranking].
class PickListBoard {
  final List<int> ranking;
  final List<int> dnp;
  final Map<String, String> notes;
  final int updatedAt;

  const PickListBoard({
    this.ranking = const [],
    this.dnp = const [],
    this.notes = const {},
    this.updatedAt = 0,
  });

  static List<int> _teamList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => (e as num?)?.toInt() ?? 0).where((n) => n > 0).toList();
  }

  factory PickListBoard.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'];
    return PickListBoard(
      ranking: _teamList(json['ranking']),
      dnp: _teamList(json['dnp']),
      notes: rawNotes is Map ? rawNotes.map((k, v) => MapEntry(k.toString(), v.toString())) : const {},
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'ranking': ranking,
        'dnp': dnp,
        'notes': notes,
        'updatedAt': updatedAt,
      };
}
