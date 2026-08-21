class TeamMatchEntryBreakdownModel {
  final int teamNumber;
  final String teamKey;
  final double scoutedScore;
  final String entryId;
  final String? scouterName;
  final bool hasDiscrepancy;

  TeamMatchEntryBreakdownModel({
    required this.teamNumber,
    required this.teamKey,
    required this.scoutedScore,
    required this.entryId,
    this.scouterName,
    this.hasDiscrepancy = false,
  });

  factory TeamMatchEntryBreakdownModel.fromJson(Map<String, dynamic> json) {
    return TeamMatchEntryBreakdownModel(
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      teamKey: json['teamKey']?.toString() ?? '',
      scoutedScore: (json['scoutedScore'] as num?)?.toDouble() ?? 0.0,
      entryId: json['entryId']?.toString() ?? '',
      scouterName: json['scouterName']?.toString(),
      hasDiscrepancy: json['hasDiscrepancy'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teamNumber': teamNumber,
      'teamKey': teamKey,
      'scoutedScore': scoutedScore,
      'entryId': entryId,
      'scouterName': scouterName,
      'hasDiscrepancy': hasDiscrepancy,
    };
  }
}

class AllianceValidationModel {
  final String allianceColor;
  final List<int> teams;
  final List<int> scoutedTeams;
  final List<int> missingTeams;
  final bool isFullyScouted;
  final double? actualScore;
  final double scoutedScoreSum;
  final double? scoreDiff;
  final bool isAnomaly;
  final String? warning;
  final List<TeamMatchEntryBreakdownModel> teamBreakdowns;

  AllianceValidationModel({
    required this.allianceColor,
    required this.teams,
    required this.scoutedTeams,
    required this.missingTeams,
    required this.isFullyScouted,
    this.actualScore,
    required this.scoutedScoreSum,
    this.scoreDiff,
    required this.isAnomaly,
    this.warning,
    this.teamBreakdowns = const [],
  });

  factory AllianceValidationModel.fromJson(Map<String, dynamic> json) {
    return AllianceValidationModel(
      allianceColor: json['allianceColor']?.toString() ?? 'red',
      teams: (json['teams'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
      scoutedTeams: (json['scoutedTeams'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
      missingTeams: (json['missingTeams'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [],
      isFullyScouted: json['isFullyScouted'] == true,
      actualScore: (json['actualScore'] as num?)?.toDouble(),
      scoutedScoreSum: (json['scoutedScoreSum'] as num?)?.toDouble() ?? 0.0,
      scoreDiff: (json['scoreDiff'] as num?)?.toDouble(),
      isAnomaly: json['isAnomaly'] == true,
      warning: json['warning']?.toString(),
      teamBreakdowns: (json['teamBreakdowns'] as List<dynamic>?)
              ?.map((e) => TeamMatchEntryBreakdownModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'allianceColor': allianceColor,
      'teams': teams,
      'scoutedTeams': scoutedTeams,
      'missingTeams': missingTeams,
      'isFullyScouted': isFullyScouted,
      'actualScore': actualScore,
      'scoutedScoreSum': scoutedScoreSum,
      'scoreDiff': scoreDiff,
      'isAnomaly': isAnomaly,
      'warning': warning,
      'teamBreakdowns': teamBreakdowns.map((e) => e.toJson()).toList(),
    };
  }
}

class MatchValidationModel {
  final String matchKey;
  final String eventKey;
  final String compLevel;
  final int? setNumber;
  final int? matchNumber;
  final String label;
  final int? scheduledTime;
  final int? actualTime;
  final AllianceValidationModel redAlliance;
  final AllianceValidationModel blueAlliance;
  final bool isFullyScouted;
  final bool hasAnomaly;
  final String? matchWarning;

  MatchValidationModel({
    required this.matchKey,
    required this.eventKey,
    required this.compLevel,
    this.setNumber,
    this.matchNumber,
    required this.label,
    this.scheduledTime,
    this.actualTime,
    required this.redAlliance,
    required this.blueAlliance,
    required this.isFullyScouted,
    required this.hasAnomaly,
    this.matchWarning,
  });

  factory MatchValidationModel.fromJson(Map<String, dynamic> json) {
    return MatchValidationModel(
      matchKey: json['matchKey']?.toString() ?? '',
      eventKey: json['eventKey']?.toString() ?? '',
      compLevel: json['compLevel']?.toString() ?? '',
      setNumber: (json['setNumber'] as num?)?.toInt(),
      matchNumber: (json['matchNumber'] as num?)?.toInt(),
      label: json['label']?.toString() ?? '',
      scheduledTime: (json['scheduledTime'] as num?)?.toInt(),
      actualTime: (json['actualTime'] as num?)?.toInt(),
      redAlliance: AllianceValidationModel.fromJson((json['redAlliance'] as Map<String, dynamic>?) ?? {}),
      blueAlliance: AllianceValidationModel.fromJson((json['blueAlliance'] as Map<String, dynamic>?) ?? {}),
      isFullyScouted: json['isFullyScouted'] == true,
      hasAnomaly: json['hasAnomaly'] == true,
      matchWarning: json['matchWarning']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'matchKey': matchKey,
      'eventKey': eventKey,
      'compLevel': compLevel,
      'setNumber': setNumber,
      'matchNumber': matchNumber,
      'label': label,
      'scheduledTime': scheduledTime,
      'actualTime': actualTime,
      'redAlliance': redAlliance.toJson(),
      'blueAlliance': blueAlliance.toJson(),
      'isFullyScouted': isFullyScouted,
      'hasAnomaly': hasAnomaly,
      'matchWarning': matchWarning,
    };
  }
}

class TeamValidationModel {
  final int teamNumber;
  final String teamKey;
  final String nickname;
  final int scoutedMatchCount;
  final double? averageScoutedScore;
  final double? epa;
  final double? opr;
  final double? epaDiff;
  final double? oprDiff;
  final bool isAnomaly;
  final String? anomalyReason;
  final bool hasDiscrepancy;

  TeamValidationModel({
    required this.teamNumber,
    required this.teamKey,
    required this.nickname,
    required this.scoutedMatchCount,
    this.averageScoutedScore,
    this.epa,
    this.opr,
    this.epaDiff,
    this.oprDiff,
    required this.isAnomaly,
    this.anomalyReason,
    this.hasDiscrepancy = false,
  });

  factory TeamValidationModel.fromJson(Map<String, dynamic> json) {
    return TeamValidationModel(
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      teamKey: json['teamKey']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? 'Team ${json['teamNumber']}',
      scoutedMatchCount: (json['scoutedMatchCount'] as num?)?.toInt() ?? 0,
      averageScoutedScore: (json['averageScoutedScore'] as num?)?.toDouble(),
      epa: (json['epa'] as num?)?.toDouble(),
      opr: (json['opr'] as num?)?.toDouble(),
      epaDiff: (json['epaDiff'] as num?)?.toDouble(),
      oprDiff: (json['oprDiff'] as num?)?.toDouble(),
      isAnomaly: json['isAnomaly'] == true,
      anomalyReason: json['anomalyReason']?.toString(),
      hasDiscrepancy: json['hasDiscrepancy'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teamNumber': teamNumber,
      'teamKey': teamKey,
      'nickname': nickname,
      'scoutedMatchCount': scoutedMatchCount,
      'averageScoutedScore': averageScoutedScore,
      'epa': epa,
      'opr': opr,
      'epaDiff': epaDiff,
      'oprDiff': oprDiff,
      'isAnomaly': isAnomaly,
      'anomalyReason': anomalyReason,
      'hasDiscrepancy': hasDiscrepancy,
    };
  }
}

class ValidationSummaryModel {
  final String eventKey;
  final int totalMatches;
  final int fullyScoutedMatches;
  final int incompleteMatches;
  final int unscoutedMatches;
  final int matchesWithAnomalies;
  final int teamsAnalyzed;
  final int teamsWithAnomalies;
  final bool useStatboticsEpa;
  final bool useTbaOpr;
  final double threshold;
  final List<MatchValidationModel> matches;
  final List<TeamValidationModel> teams;

  ValidationSummaryModel({
    required this.eventKey,
    required this.totalMatches,
    required this.fullyScoutedMatches,
    required this.incompleteMatches,
    required this.unscoutedMatches,
    required this.matchesWithAnomalies,
    required this.teamsAnalyzed,
    required this.teamsWithAnomalies,
    required this.useStatboticsEpa,
    required this.useTbaOpr,
    required this.threshold,
    required this.matches,
    required this.teams,
  });

  factory ValidationSummaryModel.fromJson(Map<String, dynamic> json) {
    return ValidationSummaryModel(
      eventKey: json['eventKey']?.toString() ?? '',
      totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
      fullyScoutedMatches: (json['fullyScoutedMatches'] as num?)?.toInt() ?? 0,
      incompleteMatches: (json['incompleteMatches'] as num?)?.toInt() ?? 0,
      unscoutedMatches: (json['unscoutedMatches'] as num?)?.toInt() ?? 0,
      matchesWithAnomalies: (json['matchesWithAnomalies'] as num?)?.toInt() ?? 0,
      teamsAnalyzed: (json['teamsAnalyzed'] as num?)?.toInt() ?? 0,
      teamsWithAnomalies: (json['teamsWithAnomalies'] as num?)?.toInt() ?? 0,
      useStatboticsEpa: json['useStatboticsEpa'] == true,
      useTbaOpr: json['useTbaOpr'] == true,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 15.0,
      matches: (json['matches'] as List<dynamic>?)
              ?.map((e) => MatchValidationModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      teams: (json['teams'] as List<dynamic>?)
              ?.map((e) => TeamValidationModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventKey': eventKey,
      'totalMatches': totalMatches,
      'fullyScoutedMatches': fullyScoutedMatches,
      'incompleteMatches': incompleteMatches,
      'unscoutedMatches': unscoutedMatches,
      'matchesWithAnomalies': matchesWithAnomalies,
      'teamsAnalyzed': teamsAnalyzed,
      'teamsWithAnomalies': teamsWithAnomalies,
      'useStatboticsEpa': useStatboticsEpa,
      'useTbaOpr': useTbaOpr,
      'threshold': threshold,
      'matches': matches.map((e) => e.toJson()).toList(),
      'teams': teams.map((e) => e.toJson()).toList(),
    };
  }
}
