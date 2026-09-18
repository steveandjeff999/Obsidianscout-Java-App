class MatchTeamPrediction {
  final int teamNumber;
  final String? teamKey;
  final String? nickname;
  final double? averageScoutedScore;
  final int scoutedMatchesCount;
  final double? epa;
  final double? opr;
  final bool hasDiscrepancy;

  MatchTeamPrediction({
    required this.teamNumber,
    this.teamKey,
    this.nickname,
    this.averageScoutedScore,
    this.scoutedMatchesCount = 0,
    this.epa,
    this.opr,
    this.hasDiscrepancy = false,
  });

  factory MatchTeamPrediction.fromJson(Map<String, dynamic> json) {
    return MatchTeamPrediction(
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      teamKey: json['teamKey']?.toString(),
      nickname: json['nickname']?.toString(),
      averageScoutedScore: (json['averageScoutedScore'] as num?)?.toDouble(),
      scoutedMatchesCount: (json['scoutedMatchesCount'] as num?)?.toInt() ?? 0,
      epa: (json['epa'] as num?)?.toDouble(),
      opr: (json['opr'] as num?)?.toDouble(),
      hasDiscrepancy: json['hasDiscrepancy'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teamNumber': teamNumber,
      if (teamKey != null) 'teamKey': teamKey,
      if (nickname != null) 'nickname': nickname,
      if (averageScoutedScore != null) 'averageScoutedScore': averageScoutedScore,
      'scoutedMatchesCount': scoutedMatchesCount,
      if (epa != null) 'epa': epa,
      if (opr != null) 'opr': opr,
      'hasDiscrepancy': hasDiscrepancy,
    };
  }
}

class AlliancePrediction {
  final List<MatchTeamPrediction> teams;
  final double totalScoutedScore;
  final double totalEpa;
  final double totalOpr;

  AlliancePrediction({
    this.teams = const [],
    this.totalScoutedScore = 0.0,
    this.totalEpa = 0.0,
    this.totalOpr = 0.0,
  });

  factory AlliancePrediction.fromJson(Map<String, dynamic> json) {
    final rawTeams = json['teams'] as List<dynamic>? ?? [];
    return AlliancePrediction(
      teams: rawTeams.map((t) => MatchTeamPrediction.fromJson(t as Map<String, dynamic>)).toList(),
      totalScoutedScore: (json['totalScoutedScore'] as num?)?.toDouble() ?? 0.0,
      totalEpa: (json['totalEpa'] as num?)?.toDouble() ?? 0.0,
      totalOpr: (json['totalOpr'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teams': teams.map((t) => t.toJson()).toList(),
      'totalScoutedScore': totalScoutedScore,
      'totalEpa': totalEpa,
      'totalOpr': totalOpr,
    };
  }
}

class MatchPredictionResponse {
  final String matchKey;
  final String label;
  final AlliancePrediction redAlliance;
  final AlliancePrediction blueAlliance;
  final bool useStatboticsEpa;
  final bool useTbaOpr;

  MatchPredictionResponse({
    required this.matchKey,
    required this.label,
    required this.redAlliance,
    required this.blueAlliance,
    this.useStatboticsEpa = false,
    this.useTbaOpr = false,
  });

  factory MatchPredictionResponse.fromJson(Map<String, dynamic> json) {
    return MatchPredictionResponse(
      matchKey: json['matchKey']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      redAlliance: json['redAlliance'] != null
          ? AlliancePrediction.fromJson(json['redAlliance'] as Map<String, dynamic>)
          : AlliancePrediction(),
      blueAlliance: json['blueAlliance'] != null
          ? AlliancePrediction.fromJson(json['blueAlliance'] as Map<String, dynamic>)
          : AlliancePrediction(),
      useStatboticsEpa: json['useStatboticsEpa'] == true,
      useTbaOpr: json['useTbaOpr'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'matchKey': matchKey,
      'label': label,
      'redAlliance': redAlliance.toJson(),
      'blueAlliance': blueAlliance.toJson(),
      'useStatboticsEpa': useStatboticsEpa,
      'useTbaOpr': useTbaOpr,
    };
  }
}
