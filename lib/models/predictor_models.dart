class Match13TeamExpDetail {
  final double? xpPost;
  final double? xpPre;
  final double? xAutoPost;
  final double? xAutoPre;
  final double? xTelePost;
  final double? xTelePre;
  final double? xEndPost;
  final double? xEndPre;

  Match13TeamExpDetail({
    this.xpPost,
    this.xpPre,
    this.xAutoPost,
    this.xAutoPre,
    this.xTelePost,
    this.xTelePre,
    this.xEndPost,
    this.xEndPre,
  });

  factory Match13TeamExpDetail.fromJson(Map<String, dynamic> json) {
    return Match13TeamExpDetail(
      xpPost: (json['xpPost'] as num?)?.toDouble() ?? (json['xp'] as num?)?.toDouble(),
      xpPre: (json['xpPre'] as num?)?.toDouble(),
      xAutoPost: (json['xAutoPost'] as num?)?.toDouble() ?? (json['xAuto'] as num?)?.toDouble(),
      xAutoPre: (json['xAutoPre'] as num?)?.toDouble(),
      xTelePost: (json['xTelePost'] as num?)?.toDouble() ?? (json['xTele'] as num?)?.toDouble(),
      xTelePre: (json['xTelePre'] as num?)?.toDouble(),
      xEndPost: (json['xEndPost'] as num?)?.toDouble() ?? (json['xEnd'] as num?)?.toDouble(),
      xEndPre: (json['xEndPre'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (xpPost != null) 'xpPost': xpPost,
      if (xpPre != null) 'xpPre': xpPre,
      if (xAutoPost != null) 'xAutoPost': xAutoPost,
      if (xAutoPre != null) 'xAutoPre': xAutoPre,
      if (xTelePost != null) 'xTelePost': xTelePost,
      if (xTelePre != null) 'xTelePre': xTelePre,
      if (xEndPost != null) 'xEndPost': xEndPost,
      if (xEndPre != null) 'xEndPre': xEndPre,
    };
  }
}

class Match13PredictionDetail {
  final double? redScore;
  final double? blueScore;
  final double? winProb;
  final double? redRp1;
  final double? redRp2;
  final double? redRp3;
  final double? blueRp1;
  final double? blueRp2;
  final double? blueRp3;
  final double? redVar;
  final double? blueVar;

  Match13PredictionDetail({
    this.redScore,
    this.blueScore,
    this.winProb,
    this.redRp1,
    this.redRp2,
    this.redRp3,
    this.blueRp1,
    this.blueRp2,
    this.blueRp3,
    this.redVar,
    this.blueVar,
  });

  double? get redWinProb => winProb;
  double? get blueWinProb => winProb != null ? (1.0 - winProb!) : null;

  factory Match13PredictionDetail.fromJson(Map<String, dynamic> json) {
    return Match13PredictionDetail(
      redScore: (json['redScore'] as num?)?.toDouble() ?? (json['red_score'] as num?)?.toDouble(),
      blueScore: (json['blueScore'] as num?)?.toDouble() ?? (json['blue_score'] as num?)?.toDouble(),
      winProb: (json['winProb'] as num?)?.toDouble() ??
          (json['win_prob'] as num?)?.toDouble() ??
          (json['redWinProb'] as num?)?.toDouble() ??
          (json['red_win_prob'] as num?)?.toDouble(),
      redRp1: (json['redRp1'] as num?)?.toDouble() ?? (json['red_rp_1'] as num?)?.toDouble(),
      redRp2: (json['redRp2'] as num?)?.toDouble() ?? (json['red_rp_2'] as num?)?.toDouble(),
      redRp3: (json['redRp3'] as num?)?.toDouble() ?? (json['red_rp_3'] as num?)?.toDouble(),
      blueRp1: (json['blueRp1'] as num?)?.toDouble() ?? (json['blue_rp_1'] as num?)?.toDouble(),
      blueRp2: (json['blueRp2'] as num?)?.toDouble() ?? (json['blue_rp_2'] as num?)?.toDouble(),
      blueRp3: (json['blueRp3'] as num?)?.toDouble() ?? (json['blue_rp_3'] as num?)?.toDouble(),
      redVar: (json['redVar'] as num?)?.toDouble() ?? (json['red_var'] as num?)?.toDouble(),
      blueVar: (json['blueVar'] as num?)?.toDouble() ?? (json['blue_var'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (redScore != null) 'redScore': redScore,
      if (blueScore != null) 'blueScore': blueScore,
      if (winProb != null) 'winProb': winProb,
      if (redRp1 != null) 'redRp1': redRp1,
      if (redRp2 != null) 'redRp2': redRp2,
      if (redRp3 != null) 'redRp3': redRp3,
      if (blueRp1 != null) 'blueRp1': blueRp1,
      if (blueRp2 != null) 'blueRp2': blueRp2,
      if (blueRp3 != null) 'blueRp3': blueRp3,
      if (redVar != null) 'redVar': redVar,
      if (blueVar != null) 'blueVar': blueVar,
    };
  }
}

class MatchTeamPrediction {
  final int teamNumber;
  final String? teamKey;
  final String? nickname;
  final double? averageScoutedScore;
  final int scoutedMatchesCount;
  final double? epa;
  final double? opr;
  final double? exp;
  final Match13TeamExpDetail? match13TeamExp;
  final bool hasDiscrepancy;

  MatchTeamPrediction({
    required this.teamNumber,
    this.teamKey,
    this.nickname,
    this.averageScoutedScore,
    this.scoutedMatchesCount = 0,
    this.epa,
    this.opr,
    this.exp,
    this.match13TeamExp,
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
      exp: (json['exp'] as num?)?.toDouble() ?? (json['match13Exp'] as num?)?.toDouble() ?? (json['match13_exp'] as num?)?.toDouble(),
      match13TeamExp: json['match13TeamExp'] is Map<String, dynamic>
          ? Match13TeamExpDetail.fromJson(json['match13TeamExp'] as Map<String, dynamic>)
          : null,
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
      if (exp != null) 'exp': exp,
      if (match13TeamExp != null) 'match13TeamExp': match13TeamExp!.toJson(),
      'hasDiscrepancy': hasDiscrepancy,
    };
  }
}

class AlliancePrediction {
  final List<MatchTeamPrediction> teams;
  final double totalScoutedScore;
  final double totalEpa;
  final double totalOpr;
  final double totalExp;

  AlliancePrediction({
    this.teams = const [],
    this.totalScoutedScore = 0.0,
    this.totalEpa = 0.0,
    this.totalOpr = 0.0,
    this.totalExp = 0.0,
  });

  factory AlliancePrediction.fromJson(Map<String, dynamic> json) {
    final rawTeams = json['teams'] as List<dynamic>? ?? [];
    return AlliancePrediction(
      teams: rawTeams.map((t) => MatchTeamPrediction.fromJson(t as Map<String, dynamic>)).toList(),
      totalScoutedScore: (json['totalScoutedScore'] as num?)?.toDouble() ?? 0.0,
      totalEpa: (json['totalEpa'] as num?)?.toDouble() ?? 0.0,
      totalOpr: (json['totalOpr'] as num?)?.toDouble() ?? 0.0,
      totalExp: (json['totalExp'] as num?)?.toDouble() ?? (json['total_exp'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teams': teams.map((t) => t.toJson()).toList(),
      'totalScoutedScore': totalScoutedScore,
      'totalEpa': totalEpa,
      'totalOpr': totalOpr,
      'totalExp': totalExp,
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
  final bool useMatch13Exp;
  final Match13PredictionDetail? match13Pred;

  MatchPredictionResponse({
    required this.matchKey,
    required this.label,
    required this.redAlliance,
    required this.blueAlliance,
    this.useStatboticsEpa = false,
    this.useTbaOpr = false,
    this.useMatch13Exp = false,
    this.match13Pred,
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
      useMatch13Exp: json['useMatch13Exp'] == true,
      match13Pred: json['match13Pred'] is Map<String, dynamic>
          ? Match13PredictionDetail.fromJson(json['match13Pred'] as Map<String, dynamic>)
          : null,
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
      'useMatch13Exp': useMatch13Exp,
      if (match13Pred != null) 'match13Pred': match13Pred!.toJson(),
    };
  }
}
