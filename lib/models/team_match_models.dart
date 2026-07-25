class TeamModel {
  final String eventKey;
  final String teamKey;
  final int teamNumber;
  final String? name;
  final String? nickname;
  final double? averagePoints;
  final double? epa;
  final double? opr;

  TeamModel({
    required this.eventKey,
    required this.teamKey,
    required this.teamNumber,
    this.name,
    this.nickname,
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
    return MatchModel(
      matchKey: json['matchKey']?.toString() ?? '',
      eventKey: json['eventKey']?.toString() ?? '',
      compLevel: json['compLevel']?.toString() ?? 'qm',
      matchNumber: (json['matchNumber'] as num?)?.toInt(),
      label: json['label']?.toString() ?? '',
      redTeams: (json['redTeams'] as List?)?.map((e) => e.toString()).toList() ?? [],
      blueTeams: (json['blueTeams'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  String get displayLabel {
    if (label.isNotEmpty) return label;
    return '${compLevel.toUpperCase()} ${matchNumber ?? ""}';
  }
}
