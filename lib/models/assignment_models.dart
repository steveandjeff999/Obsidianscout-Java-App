import 'team_match_models.dart';

class ScoutingAssignment {
  final String id;
  final int ownerTeamNumber;
  final String program;
  final String eventKey;
  final String assignedUserId;
  final String assignedUsername;
  final String? assignedUserDisplayName;
  final String assignmentType; // MATCH | PIT | QUALITATIVE
  final String? matchKey;
  final int? matchNumber;
  final String? compLevel;
  final int? targetTeamNumber;
  final String? targetTeamName;
  final String? allianceColor;
  final String? targetAlliance;
  final String status; // PENDING | IN_PROGRESS | COMPLETED | SKIPPED | MISSED
  final String? notes;
  final String? createdByUserId;
  final String? createdByUsername;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;
  final int? scheduledTime;
  final int? predictedTime;
  final int? scheduleOffsetSeconds;
  final int? reminderMinutesBefore;

  int? get effectiveScheduledTime => predictedTime ?? scheduledTime;

  String get formattedMatchName => MatchFormatUtils.formatShortMatch(
        matchKey: matchKey,
        matchNumber: matchNumber,
        compLevel: compLevel,
      );

  bool isMatchFor(MatchModel match) {
    return MatchFormatUtils.isSameMatchKeys(
      asgnMatchKey: matchKey,
      asgnMatchNumber: matchNumber,
      asgnCompLevel: compLevel,
      matchKey: match.matchKey,
      matchNumber: match.matchNumber,
      compLevel: match.compLevel,
    );
  }

  bool isForSlot(MatchModel match, int? teamNum) {
    if (!isMatchFor(match)) return false;
    if (teamNum == null) return true;
    return targetTeamNumber == teamNum;
  }

  bool isForQualAlliance(MatchModel match, String alliance) {
    if (!isMatchFor(match)) return false;
    final aAlliance = (allianceColor ?? targetAlliance ?? '').trim().toUpperCase();
    final target = alliance.trim().toUpperCase();
    if (target.isEmpty) return targetTeamNumber == null;
    return aAlliance == target && targetTeamNumber == null;
  }

  static const Map<String, int> _compLevelRank = {
    'practice': 0,
    'prac': 0,
    'pr': 0,
    'prc': 0,
    'pm': 0,
    'p': 0,
    'qm': 1,
    'q': 1,
    'qual': 1,
    'quals': 1,
    'qualification': 1,
    'qf': 2,
    'quarterfinal': 2,
    'quarterfinals': 2,
    'sf': 3,
    'semifinal': 3,
    'semifinals': 3,
    'f': 4,
    'final': 4,
    'finals': 4,
    'ef': 5,
    'einstein': 5,
    'playoff': 6,
    'playoffs': 6,
  };

  static final RegExp _legacyKeyRegex =
      RegExp(r'^.+_([a-z]+)_s(\d+)_m(\d+)$', caseSensitive: false);
  static final RegExp _tbaSuffixRegex =
      RegExp(r'^([a-z]+?)(\d+)(?:m(\d+))?$', caseSensitive: false);

  static ({int stageRank, int setNum, int matchNum}) matchOrderTuple(
    ScoutingAssignment a, {
    Map<String, MatchModel>? matchesByKey,
  }) {
    if (a.assignmentType.toUpperCase() == 'PIT') {
      return (stageRank: 10, setNum: 0, matchNum: a.targetTeamNumber ?? 999999);
    }

    final matched = (a.matchKey != null && matchesByKey != null)
        ? matchesByKey[a.matchKey!.trim().toLowerCase()]
        : null;
    final rawKey = (a.matchKey != null && a.matchKey!.trim().isNotEmpty)
        ? a.matchKey!.trim().toLowerCase()
        : (matched?.matchKey.trim().toLowerCase() ?? '');

    String? keyLevel;
    int? keySet;
    int? keyMatch;

    if (rawKey.isNotEmpty) {
      final legacy = _legacyKeyRegex.firstMatch(rawKey);
      if (legacy != null) {
        keyLevel = legacy.group(1)?.toLowerCase();
        keySet = int.tryParse(legacy.group(2) ?? '');
        keyMatch = int.tryParse(legacy.group(3) ?? '');
      } else {
        final suffix = rawKey.contains('_') ? rawKey.split('_').last : rawKey;
        final tba = _tbaSuffixRegex.firstMatch(suffix);
        if (tba != null) {
          keyLevel = tba.group(1)?.toLowerCase();
          if (tba.group(3) != null) {
            keySet = int.tryParse(tba.group(2) ?? '');
            keyMatch = int.tryParse(tba.group(3) ?? '');
          } else {
            keySet = 1;
            keyMatch = int.tryParse(tba.group(2) ?? '');
          }
        }
      }
    }

    String normLevel(String? raw) {
      if (raw == null) return '';
      final s = raw.trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '');
      if (s.isEmpty) return '';
      if (_compLevelRank.containsKey(s)) {
        final r = _compLevelRank[s]!;
        if (r == 0) return 'pr';
        if (r == 1) return 'qm';
        if (r == 2) return 'qf';
        if (r == 3) return 'sf';
        if (r == 4) return 'f';
        if (r == 5) return 'ef';
        if (r == 6) return 'playoff';
      }
      return s;
    }

    final explicitRaw = (a.compLevel != null && a.compLevel!.trim().isNotEmpty)
        ? a.compLevel
        : matched?.compLevel;
    var resolvedLevel = normLevel(explicitRaw);
    final parsedKeyLevel = (keyLevel != null && keyLevel != 'm') ? normLevel(keyLevel) : '';

    if (parsedKeyLevel.isNotEmpty &&
        (resolvedLevel.isEmpty ||
            ((resolvedLevel == 'qm' || resolvedLevel == 'playoff') &&
                parsedKeyLevel != 'qm'))) {
      resolvedLevel = parsedKeyLevel;
    }

    final setNum = keySet ?? 1;
    if (resolvedLevel == 'playoff') {
      if (setNum == 1) {
        resolvedLevel = 'qf';
      } else if (setNum == 2) {
        resolvedLevel = 'sf';
      } else if (setNum == 3) {
        resolvedLevel = 'f';
      }
    }

    final stageRank =
        _compLevelRank[resolvedLevel.isEmpty ? 'qm' : resolvedLevel] ?? 7;
    final matchNum = (a.matchNumber != null && a.matchNumber! > 0)
        ? a.matchNumber!
        : (keyMatch ?? matched?.matchNumber ?? 0);

    return (stageRank: stageRank, setNum: setNum, matchNum: matchNum);
  }

  /// Compares two assignments following Practice > Qualification > Playoff (QF > SF > F) order,
  /// with Pit assignments ordered after match assignments by team number.
  static int compareMatchOrder(
    ScoutingAssignment a,
    ScoutingAssignment b, {
    Map<String, MatchModel>? matchesByKey,
  }) {
    final ka = matchOrderTuple(a, matchesByKey: matchesByKey);
    final kb = matchOrderTuple(b, matchesByKey: matchesByKey);

    if (ka.stageRank != kb.stageRank) {
      return ka.stageRank.compareTo(kb.stageRank);
    }
    if (ka.setNum != kb.setNum) {
      return ka.setNum.compareTo(kb.setNum);
    }
    if (ka.matchNum != kb.matchNum) {
      return ka.matchNum.compareTo(kb.matchNum);
    }

    final typeCmp = a.assignmentType.compareTo(b.assignmentType);
    if (typeCmp != 0) return typeCmp;

    final teamA = a.targetTeamNumber ?? 999999;
    final teamB = b.targetTeamNumber ?? 999999;
    if (teamA != teamB) return teamA.compareTo(teamB);

    final allianceA = (a.allianceColor ?? a.targetAlliance ?? '').toUpperCase();
    final allianceB = (b.allianceColor ?? b.targetAlliance ?? '').toUpperCase();
    if (allianceA != allianceB) return allianceA.compareTo(allianceB);

    return a.id.compareTo(b.id);
  }

  ScoutingAssignment({
    required this.id,
    this.ownerTeamNumber = 0,
    this.program = 'FRC',
    required this.eventKey,
    required this.assignedUserId,
    required this.assignedUsername,
    this.assignedUserDisplayName,
    required this.assignmentType,
    this.matchKey,
    this.matchNumber,
    this.compLevel,
    this.targetTeamNumber,
    this.targetTeamName,
    this.allianceColor,
    this.targetAlliance,
    this.status = 'PENDING',
    this.notes,
    this.createdByUserId,
    this.createdByUsername,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.scheduledTime,
    this.predictedTime,
    this.scheduleOffsetSeconds,
    this.reminderMinutesBefore,
  });

  factory ScoutingAssignment.fromJson(Map<String, dynamic> json) {
    int? parsedScheduledTime;
    if (json['scheduledTime'] != null) {
      if (json['scheduledTime'] is num) {
        parsedScheduledTime = (json['scheduledTime'] as num).toInt();
      } else if (json['scheduledTime'] is String) {
        parsedScheduledTime = int.tryParse(json['scheduledTime']);
      }
      if (parsedScheduledTime != null && parsedScheduledTime > 0 && parsedScheduledTime < 10000000000) {
        parsedScheduledTime = parsedScheduledTime * 1000;
      }
    }

    int? parsedPredictedTime;
    if (json['predictedTime'] != null) {
      if (json['predictedTime'] is num) {
        parsedPredictedTime = (json['predictedTime'] as num).toInt();
      } else if (json['predictedTime'] is String) {
        parsedPredictedTime = int.tryParse(json['predictedTime']);
      }
      if (parsedPredictedTime != null && parsedPredictedTime > 0 && parsedPredictedTime < 10000000000) {
        parsedPredictedTime = parsedPredictedTime * 1000;
      }
    }

    int? parsedOffset;
    if (json['scheduleOffsetSeconds'] != null) {
      if (json['scheduleOffsetSeconds'] is num) {
        parsedOffset = (json['scheduleOffsetSeconds'] as num).toInt();
      } else if (json['scheduleOffsetSeconds'] is String) {
        parsedOffset = int.tryParse(json['scheduleOffsetSeconds']);
      }
    }

    return ScoutingAssignment(
      id: json['id']?.toString() ?? '',
      ownerTeamNumber: (json['ownerTeamNumber'] as num?)?.toInt() ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      eventKey: json['eventKey']?.toString() ?? '',
      assignedUserId: json['assignedUserId']?.toString() ?? '',
      assignedUsername: json['assignedUsername']?.toString() ??
          json['assignedUserName']?.toString() ??
          '',
      assignedUserDisplayName: json['assignedUserDisplayName']?.toString() ??
          json['assignedUsername']?.toString() ??
          json['assignedUserName']?.toString(),
      assignmentType: (json['assignmentType']?.toString() ?? 'MATCH').toUpperCase(),
      matchKey: json['matchKey']?.toString(),
      matchNumber: (json['matchNumber'] as num?)?.toInt(),
      compLevel: json['compLevel']?.toString(),
      targetTeamNumber: (json['targetTeamNumber'] as num?)?.toInt(),
      targetTeamName: json['targetTeamName']?.toString(),
      allianceColor: json['allianceColor']?.toString(),
      targetAlliance: json['targetAlliance']?.toString() ?? json['allianceColor']?.toString(),
      status: (json['status']?.toString() ?? 'PENDING').toUpperCase(),
      notes: json['notes']?.toString(),
      createdByUserId: json['createdByUserId']?.toString(),
      createdByUsername: json['createdByUsername']?.toString(),
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      completedAt: json['completedAt']?.toString(),
      scheduledTime: parsedScheduledTime,
      predictedTime: parsedPredictedTime,
      scheduleOffsetSeconds: parsedOffset,
      reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerTeamNumber': ownerTeamNumber,
      'program': program,
      'eventKey': eventKey,
      'assignedUserId': assignedUserId,
      'assignedUsername': assignedUsername,
      'assignedUserDisplayName': assignedUserDisplayName,
      'assignmentType': assignmentType,
      'matchKey': matchKey,
      'matchNumber': matchNumber,
      'compLevel': compLevel,
      'targetTeamNumber': targetTeamNumber,
      'targetTeamName': targetTeamName,
      'allianceColor': allianceColor,
      'targetAlliance': targetAlliance,
      'status': status,
      'notes': notes,
      'createdByUserId': createdByUserId,
      'createdByUsername': createdByUsername,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completedAt': completedAt,
      'scheduledTime': scheduledTime,
      'predictedTime': predictedTime,
      'scheduleOffsetSeconds': scheduleOffsetSeconds,
      'reminderMinutesBefore': reminderMinutesBefore,
    };
  }

  ScoutingAssignment copyWith({
    String? id,
    int? ownerTeamNumber,
    String? program,
    String? eventKey,
    String? assignedUserId,
    String? assignedUsername,
    String? assignedUserDisplayName,
    String? assignmentType,
    String? matchKey,
    int? matchNumber,
    String? compLevel,
    int? targetTeamNumber,
    String? targetTeamName,
    String? allianceColor,
    String? targetAlliance,
    String? status,
    String? notes,
    String? createdByUserId,
    String? createdByUsername,
    String? createdAt,
    String? updatedAt,
    String? completedAt,
    int? scheduledTime,
    int? predictedTime,
    int? scheduleOffsetSeconds,
    int? reminderMinutesBefore,
  }) {
    return ScoutingAssignment(
      id: id ?? this.id,
      ownerTeamNumber: ownerTeamNumber ?? this.ownerTeamNumber,
      program: program ?? this.program,
      eventKey: eventKey ?? this.eventKey,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      assignedUsername: assignedUsername ?? this.assignedUsername,
      assignedUserDisplayName: assignedUserDisplayName ?? this.assignedUserDisplayName,
      assignmentType: assignmentType ?? this.assignmentType,
      matchKey: matchKey ?? this.matchKey,
      matchNumber: matchNumber ?? this.matchNumber,
      compLevel: compLevel ?? this.compLevel,
      targetTeamNumber: targetTeamNumber ?? this.targetTeamNumber,
      targetTeamName: targetTeamName ?? this.targetTeamName,
      allianceColor: allianceColor ?? this.allianceColor,
      targetAlliance: targetAlliance ?? this.targetAlliance,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUsername: createdByUsername ?? this.createdByUsername,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      predictedTime: predictedTime ?? this.predictedTime,
      scheduleOffsetSeconds: scheduleOffsetSeconds ?? this.scheduleOffsetSeconds,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
    );
  }
}

class CreateAssignmentRequest {
  final String assignedUserId;
  final String assignmentType;
  final String eventKey;
  final String? matchKey;
  final int? matchNumber;
  final String? compLevel;
  final int? targetTeamNumber;
  final String? allianceColor;
  final String? notes;
  final int? scheduledTime;
  final int? reminderMinutesBefore;

  CreateAssignmentRequest({
    required this.assignedUserId,
    required this.assignmentType,
    required this.eventKey,
    this.matchKey,
    this.matchNumber,
    this.compLevel,
    this.targetTeamNumber,
    this.allianceColor,
    this.notes,
    this.scheduledTime,
    this.reminderMinutesBefore,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'assignedUserId': assignedUserId,
      'assignmentType': assignmentType,
      'eventKey': eventKey,
    };
    if (matchKey != null && matchKey!.isNotEmpty) map['matchKey'] = matchKey;
    if (matchNumber != null) map['matchNumber'] = matchNumber;
    if (compLevel != null && compLevel!.isNotEmpty) map['compLevel'] = compLevel;
    if (targetTeamNumber != null) map['targetTeamNumber'] = targetTeamNumber;
    if (allianceColor != null && allianceColor!.isNotEmpty) map['allianceColor'] = allianceColor;
    if (notes != null && notes!.isNotEmpty) map['notes'] = notes;
    if (scheduledTime != null) map['scheduledTime'] = scheduledTime;
    if (reminderMinutesBefore != null) map['reminderMinutesBefore'] = reminderMinutesBefore;
    return map;
  }
}

class BulkAssignmentItem {
  final String assignedUserId;
  final String assignmentType;
  final String? matchKey;
  final int? matchNumber;
  final String? compLevel;
  final int? targetTeamNumber;
  final String? allianceColor;
  final String? targetAlliance;
  final String? notes;
  final int? scheduledTime;

  BulkAssignmentItem({
    required this.assignedUserId,
    required this.assignmentType,
    this.matchKey,
    this.matchNumber,
    this.compLevel,
    this.targetTeamNumber,
    this.allianceColor,
    this.targetAlliance,
    this.notes,
    this.scheduledTime,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'assignedUserId': assignedUserId,
      'assignmentType': assignmentType,
    };
    if (matchKey != null && matchKey!.isNotEmpty) map['matchKey'] = matchKey;
    if (matchNumber != null) map['matchNumber'] = matchNumber;
    if (compLevel != null && compLevel!.isNotEmpty) map['compLevel'] = compLevel;
    if (targetTeamNumber != null) map['targetTeamNumber'] = targetTeamNumber;
    if (allianceColor != null && allianceColor!.isNotEmpty) map['allianceColor'] = allianceColor;
    if (targetAlliance != null && targetAlliance!.isNotEmpty) map['targetAlliance'] = targetAlliance;
    if (notes != null && notes!.isNotEmpty) map['notes'] = notes;
    if (scheduledTime != null) map['scheduledTime'] = scheduledTime;
    return map;
  }
}

class BulkCreateAssignmentsRequest {
  final String eventKey;
  final List<BulkAssignmentItem> assignments;
  final int? reminderMinutesBefore;

  BulkCreateAssignmentsRequest({
    required this.eventKey,
    required this.assignments,
    this.reminderMinutesBefore,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'eventKey': eventKey,
      'assignments': assignments.map((a) => a.toJson()).toList(),
    };
    if (reminderMinutesBefore != null) map['reminderMinutesBefore'] = reminderMinutesBefore;
    return map;
  }
}

class UpdateAssignmentRequest {
  final String? assignedUserId;
  final int? targetTeamNumber;
  final String? allianceColor;
  final String? notes;
  final String? status;
  final int? reminderMinutesBefore;

  UpdateAssignmentRequest({
    this.assignedUserId,
    this.targetTeamNumber,
    this.allianceColor,
    this.notes,
    this.status,
    this.reminderMinutesBefore,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (assignedUserId != null) map['assignedUserId'] = assignedUserId;
    if (targetTeamNumber != null) map['targetTeamNumber'] = targetTeamNumber;
    if (allianceColor != null) map['allianceColor'] = allianceColor;
    if (notes != null) map['notes'] = notes;
    if (status != null) map['status'] = status;
    if (reminderMinutesBefore != null) map['reminderMinutesBefore'] = reminderMinutesBefore;
    return map;
  }
}

class ConflictScouterDto {
  final String assignmentId;
  final String userId;
  final String username;
  final String assignmentType;
  final String status;

  ConflictScouterDto({
    required this.assignmentId,
    required this.userId,
    required this.username,
    required this.assignmentType,
    required this.status,
  });

  factory ConflictScouterDto.fromJson(Map<String, dynamic> json) {
    return ConflictScouterDto(
      assignmentId: json['assignmentId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      assignmentType: json['assignmentType']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

class ConflictItemDto {
  final String assignmentType;
  final String? matchKey;
  final int? matchNumber;
  final int? targetTeamNumber;
  final String? allianceColor;
  final String description;
  final List<String> assignmentIds;
  final List<ConflictScouterDto> scouters;

  ConflictItemDto({
    required this.assignmentType,
    this.matchKey,
    this.matchNumber,
    this.targetTeamNumber,
    this.allianceColor,
    required this.description,
    required this.assignmentIds,
    required this.scouters,
  });

  factory ConflictItemDto.fromJson(Map<String, dynamic> json) {
    return ConflictItemDto(
      assignmentType: json['assignmentType']?.toString() ?? '',
      matchKey: json['matchKey']?.toString(),
      matchNumber: (json['matchNumber'] as num?)?.toInt(),
      targetTeamNumber: (json['targetTeamNumber'] as num?)?.toInt(),
      allianceColor: json['allianceColor']?.toString(),
      description: json['description']?.toString() ?? '',
      assignmentIds: (json['assignmentIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      scouters: (json['scouters'] as List<dynamic>?)
              ?.map((e) => ConflictScouterDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AssignmentConflictDto {
  final bool hasConflict;
  final List<ConflictScouterDto> existingScouters;
  final List<ConflictItemDto> conflicts;

  AssignmentConflictDto({
    required this.hasConflict,
    required this.existingScouters,
    required this.conflicts,
  });

  factory AssignmentConflictDto.fromJson(Map<String, dynamic> json) {
    return AssignmentConflictDto(
      hasConflict: json['hasConflict'] == true,
      existingScouters: (json['existingScouters'] as List<dynamic>?)
              ?.map((e) => ConflictScouterDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      conflicts: (json['conflicts'] as List<dynamic>?)
              ?.map((e) => ConflictItemDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AutoGenerateAssignmentsRequest {
  final String eventKey;
  final String assignmentType;
  final List<String> scouterUserIds;
  final String stageFilter;
  final String? startMatchKey;
  final String? endMatchKey;
  final int consecutiveMatches;
  final bool overwrite;
  final String pitScope;
  final int? reminderMinutesBefore;

  AutoGenerateAssignmentsRequest({
    required this.eventKey,
    required this.assignmentType,
    required this.scouterUserIds,
    this.stageFilter = 'all',
    this.startMatchKey,
    this.endMatchKey,
    this.consecutiveMatches = 5,
    this.overwrite = false,
    this.pitScope = 'unassigned',
    this.reminderMinutesBefore,
  });

  Map<String, dynamic> toJson() {
    return {
      'eventKey': eventKey,
      'assignmentType': assignmentType,
      'scouterUserIds': scouterUserIds,
      'stageFilter': stageFilter,
      if (startMatchKey != null) 'startMatchKey': startMatchKey,
      if (endMatchKey != null) 'endMatchKey': endMatchKey,
      'consecutiveMatches': consecutiveMatches,
      'overwrite': overwrite,
      'pitScope': pitScope,
      if (reminderMinutesBefore != null) 'reminderMinutesBefore': reminderMinutesBefore,
    };
  }
}

class AutoGenerateAssignmentsResponse {
  final bool success;
  final int createdCount;
  final int deletedCount;
  final String message;

  AutoGenerateAssignmentsResponse({
    required this.success,
    required this.createdCount,
    required this.deletedCount,
    required this.message,
  });

  factory AutoGenerateAssignmentsResponse.fromJson(Map<String, dynamic> json) {
    return AutoGenerateAssignmentsResponse(
      success: json['success'] == true,
      createdCount: (json['createdCount'] as num?)?.toInt() ?? 0,
      deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
    );
  }
}

class AutoResolveConflictsResponse {
  final bool success;
  final int resolvedCount;
  final String message;
  final List<String> deletedIds;

  AutoResolveConflictsResponse({
    required this.success,
    required this.resolvedCount,
    required this.message,
    required this.deletedIds,
  });

  factory AutoResolveConflictsResponse.fromJson(Map<String, dynamic> json) {
    return AutoResolveConflictsResponse(
      success: json['success'] == true,
      resolvedCount: (json['resolvedCount'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      deletedIds: (json['deletedIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

