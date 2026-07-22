class TeamModel {
  final String eventKey;
  final String teamKey;
  final int teamNumber;
  final String? name;
  final String? nickname;

  TeamModel({
    required this.eventKey,
    required this.teamKey,
    required this.teamNumber,
    this.name,
    this.nickname,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) {
    return TeamModel(
      eventKey: json['eventKey']?.toString() ?? '',
      teamKey: json['teamKey']?.toString() ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString(),
      nickname: json['nickname']?.toString(),
    );
  }

  String get displayName {
    final title = nickname ?? name ?? '';
    return title.isNotEmpty ? '$teamNumber - $title' : '$teamNumber';
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
