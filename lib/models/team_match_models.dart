class TeamModel {
  final String eventKey;
  final String teamKey;
  final int teamNumber;
  final String? name;
  final String? nickname;
  final String? city;
  final String? state;
  final String? country;
  final double? averagePoints;
  final double? epa;
  final double? opr;

  TeamModel({
    required this.eventKey,
    required this.teamKey,
    required this.teamNumber,
    this.name,
    this.nickname,
    this.city,
    this.state,
    this.country,
    this.averagePoints,
    this.epa,
    this.opr,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) {
    return TeamModel(
      eventKey: json['eventKey']?.toString() ?? '',
      teamKey: json['teamKey']?.toString() ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString(),
      nickname: json['nickname']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      averagePoints: (json['averagePoints'] as num?)?.toDouble(),
      epa: (json['epa'] as num?)?.toDouble(),
      opr: (json['opr'] as num?)?.toDouble(),
    );
  }

  double get calculatedWeighted {
    double num = 0;
    double den = 0;
    if (averagePoints != null) {
      num += averagePoints! * 1.0;
      den += 1.0;
    }
    if (epa != null) {
      num += epa! * 0.8;
      den += 0.8;
    }
    if (opr != null) {
      num += opr! * 0.6;
      den += 0.6;
    }
    return den > 0 ? num / den : 0.0;
  }

  String get displayName {
    final title = nickname ?? name ?? '';
    return title.isNotEmpty ? '$teamNumber - $title' : '$teamNumber';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamModel &&
          runtimeType == other.runtimeType &&
          teamNumber == other.teamNumber &&
          (teamKey.isEmpty || other.teamKey.isEmpty || teamKey == other.teamKey);

  @override
  int get hashCode => teamNumber.hashCode ^ teamKey.hashCode;
}

class EventModel {
  final String eventKey;
  final String name;
  final int? year;

  EventModel({
    required this.eventKey,
    required this.name,
    this.year,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      eventKey: json['eventKey']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      year: (json['year'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventModel &&
          runtimeType == other.runtimeType &&
          eventKey == other.eventKey;

  @override
  int get hashCode => eventKey.hashCode;
}

class MatchModel {
  final String matchKey;
  final String eventKey;
  final String compLevel;
  final int? matchNumber;
  final String label;
  final List<String> redTeams;
  final List<String> blueTeams;

  MatchModel({
    required this.matchKey,
    required this.eventKey,
    required this.compLevel,
    this.matchNumber,
    required this.label,
    this.redTeams = const [],
    this.blueTeams = const [],
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    String compLevel = json['compLevel']?.toString() ??
        json['comp_level']?.toString() ??
        json['match_type']?.toString() ??
        '';
    final matchKey = json['matchKey']?.toString() ?? json['match_key']?.toString() ?? '';

    if (compLevel.isEmpty && matchKey.isNotEmpty) {
      final parts = matchKey.split('_');
      if (parts.length > 1) {
        final suffix = parts.last.toLowerCase();
        if (suffix.startsWith('practice')) {
          compLevel = 'practice';
        } else if (suffix.startsWith('qm') || suffix.startsWith('qual')) {
          compLevel = 'qm';
        } else if (suffix.startsWith('qf')) {
          compLevel = 'qf';
        } else if (suffix.startsWith('sf')) {
          compLevel = 'sf';
        } else if (suffix.startsWith('f')) {
          compLevel = 'f';
        } else if (suffix.startsWith('playoff')) {
          compLevel = 'playoff';
        }
      }
    }

    if (compLevel.isEmpty) compLevel = 'qm';

    return MatchModel(
      matchKey: matchKey,
      eventKey: json['eventKey']?.toString() ?? json['event_key']?.toString() ?? '',
      compLevel: compLevel,
      matchNumber: (json['matchNumber'] ?? json['match_number']) is num
          ? ((json['matchNumber'] ?? json['match_number']) as num).toInt()
          : int.tryParse(json['matchNumber']?.toString() ?? json['match_number']?.toString() ?? ''),
      label: json['label']?.toString() ?? '',
      redTeams: (json['redTeams'] as List?)?.map((e) => e.toString()).toList() ??
          (json['red_teams'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      blueTeams: (json['blueTeams'] as List?)?.map((e) => e.toString()).toList() ??
          (json['blue_teams'] as List?)?.map((e) => e.toString()).toList() ??
          [],
    );
  }

  String get displayLabel {
    if (label.isNotEmpty) return label;
    final lvl = compLevel.toLowerCase();
    final numStr = matchNumber != null ? '$matchNumber' : '';
    if (lvl == 'practice') return 'Practice Match $numStr'.trim();
    if (lvl == 'qm' || lvl == 'qual') return 'Qualification Match $numStr'.trim();
    if (lvl == 'playoff') return 'Playoff Match $numStr'.trim();
    if (lvl == 'qf') return 'Quarterfinal $numStr'.trim();
    if (lvl == 'sf') return 'Semifinal $numStr'.trim();
    if (lvl == 'f') return 'Final $numStr'.trim();
    return '${compLevel.toUpperCase()} $numStr'.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchModel &&
          runtimeType == other.runtimeType &&
          matchKey == other.matchKey;

  @override
  int get hashCode => matchKey.hashCode;
}
