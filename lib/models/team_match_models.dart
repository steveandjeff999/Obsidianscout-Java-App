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
  final String? eventCode;
  final String? startDate;
  final String? endDate;
  final String? timezone;

  EventModel({
    required this.eventKey,
    required this.name,
    this.year,
    this.eventCode,
    this.startDate,
    this.endDate,
    this.timezone,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      eventKey: json['eventKey']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      year: (json['year'] as num?)?.toInt(),
      eventCode: json['eventCode']?.toString(),
      startDate: json['startDate']?.toString(),
      endDate: json['endDate']?.toString(),
      timezone: json['timezone']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventKey': eventKey,
      'name': name,
      if (year != null) 'year': year,
      if (eventCode != null) 'eventCode': eventCode,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (timezone != null) 'timezone': timezone,
    };
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

  String get shortLabel => MatchFormatUtils.formatShortMatch(
        matchKey: matchKey,
        matchNumber: matchNumber,
        compLevel: compLevel,
      );

  String get displayLabel {
    if (label.isNotEmpty) return label;
    final lvl = compLevel.toLowerCase();
    final numStr = matchNumber != null ? '$matchNumber' : '';
    if (lvl == 'practice' || lvl == 'pm') return 'Practice Match $numStr'.trim();
    if (lvl == 'qm' || lvl == 'qual') return 'Qualification Match $numStr'.trim();
    if (lvl == 'playoff') return 'Playoff Match $numStr'.trim();
    if (lvl == 'qf') return 'Quarterfinal $numStr'.trim();
    if (lvl == 'sf') return 'Semifinal $numStr'.trim();
    if (lvl == 'f') return 'Final $numStr'.trim();
    return '${compLevel.toUpperCase()} $numStr'.trim();
  }

  bool hasTeam(int teamNumber) {
    final cleanTarget = teamNumber.toString();
    bool checkList(List<String> list) {
      return list.any((key) {
        final clean = key.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
        if (clean == cleanTarget) return true;
        final parts = key.split('/');
        return parts.any((part) => part.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim() == cleanTarget);
      });
    }
    return checkList(redTeams) || checkList(blueTeams);
  }

  Set<int> getTeamNumbers() {
    final result = <int>{};
    for (final key in [...redTeams, ...blueTeams]) {
      for (final part in key.split('/')) {
        final clean = part.replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
        final num = int.tryParse(clean);
        if (num != null) {
          result.add(num);
        }
      }
    }
    return result;
  }

  static int compareMatches(MatchModel a, MatchModel b) {
    const levelOrder = {
      'practice': 0,
      'pm': 0,
      'pr': 0,
      'qm': 1,
      'qual': 1,
      'quals': 1,
      'ef': 2,
      'qf': 3,
      'sf': 4,
      'f': 5,
      'final': 5,
      'playoff': 6,
    };
    final la = levelOrder[a.compLevel.toLowerCase()] ?? 2;
    final lb = levelOrder[b.compLevel.toLowerCase()] ?? 2;
    if (la != lb) return la.compareTo(lb);

    final numA = _extractMatchSortNumbers(a);
    final numB = _extractMatchSortNumbers(b);
    if (numA.setNum != numB.setNum) return numA.setNum.compareTo(numB.setNum);
    if (numA.matchNum != numB.matchNum) return numA.matchNum.compareTo(numB.matchNum);

    return a.matchKey.compareTo(b.matchKey);
  }

  static ({int setNum, int matchNum}) _extractMatchSortNumbers(MatchModel m) {
    if (m.matchKey.contains('_')) {
      final part = m.matchKey.split('_').last.toLowerCase();
      final match = RegExp(r'^([a-z]+)(\d+)(?:m(\d+))?$').firstMatch(part);
      if (match != null) {
        if (match.group(3) != null) {
          final setNum = int.tryParse(match.group(2)!) ?? 0;
          final matchNum = int.tryParse(match.group(3)!) ?? 0;
          return (setNum: setNum, matchNum: matchNum);
        } else {
          final matchNum = int.tryParse(match.group(2)!) ?? (m.matchNumber ?? 0);
          return (setNum: 1, matchNum: matchNum);
        }
      }
    }
    return (setNum: 1, matchNum: m.matchNumber ?? 0);
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

class MatchFormatUtils {
  static String formatShortMatch({
    String? matchKey,
    int? matchNumber,
    String? compLevel,
  }) {
    if (matchKey != null && matchKey.isNotEmpty) {
      final part = matchKey.contains('_')
          ? matchKey.split('_').last.toLowerCase()
          : matchKey.toLowerCase();

      final regex = RegExp(r'^([a-z]+)(.+)$');
      final m = regex.firstMatch(part);
      if (m != null) {
        final levelStr = m.group(1)!;
        final rest = m.group(2)!;
        final abbrev = levelAbbrev(levelStr);
        if (rest.contains('m')) {
          final mIdx = rest.indexOf('m');
          final setNum = rest.substring(0, mIdx);
          final matchNum = rest.substring(mIdx + 1);
          return '$abbrev $setNum-$matchNum';
        }
        return '$abbrev $rest';
      }
    }

    final lvl = (compLevel ?? 'qm').toLowerCase();
    final abbrev = levelAbbrev(lvl);
    if (matchNumber != null) {
      return '$abbrev $matchNumber';
    }
    if (matchKey != null && matchKey.isNotEmpty) {
      return matchKey;
    }
    return abbrev;
  }

  static String levelAbbrev(String level) {
    switch (level.toLowerCase()) {
      case 'pm':
      case 'practice':
      case 'pr':
        return 'PM';
      case 'qm':
      case 'qual':
      case 'quals':
        return 'QM';
      case 'qf':
      case 'quarterfinal':
      case 'quarterfinals':
        return 'QF';
      case 'sf':
      case 'semifinal':
      case 'semifinals':
        return 'SF';
      case 'f':
      case 'final':
      case 'finals':
        return 'F';
      case 'ef':
      case 'einstein':
        return 'EF';
      case 'playoff':
        return 'PO';
      default:
        return level.toUpperCase();
    }
  }

  static String normalizeCompLevel(String? lvl) {
    if (lvl == null || lvl.trim().isEmpty) return '';
    final s = lvl.trim().toLowerCase();
    if (s == 'qm' || s == 'qual' || s == 'quals' || s == 'qualification') return 'qm';
    if (s == 'qf' || s == 'quarterfinal' || s == 'quarterfinals') return 'qf';
    if (s == 'sf' || s == 'semifinal' || s == 'semifinals') return 'sf';
    if (s == 'f' || s == 'final' || s == 'finals') return 'f';
    if (s == 'pr' || s == 'practice' || s == 'pm') return 'pr';
    return s;
  }

  static String? extractCompLevel(String? matchKey, String? compLevel) {
    final norm = normalizeCompLevel(compLevel);
    if (norm.isNotEmpty) return norm;
    if (matchKey == null || matchKey.isEmpty) return null;
    final k = matchKey.toLowerCase();
    if (k.contains('_qm') || k.startsWith('qm')) return 'qm';
    if (k.contains('_qf') || k.startsWith('qf')) return 'qf';
    if (k.contains('_sf') || k.startsWith('sf')) return 'sf';
    if (k.contains('_f') || k.startsWith('f')) return 'f';
    if (k.contains('_pr') || k.startsWith('pr') || k.contains('_pm') || k.startsWith('pm')) return 'pr';
    return null;
  }

  static int? extractMatchNumber(String? matchKey, int? matchNumber) {
    if (matchNumber != null && matchNumber > 0) return matchNumber;
    if (matchKey == null || matchKey.isEmpty) return null;
    final k = matchKey.trim().toLowerCase();
    final mPlayoff = RegExp(r'_(?:sf|qf|f)\d+m(\d+)').firstMatch(k);
    if (mPlayoff != null && mPlayoff.group(1) != null) {
      return int.tryParse(mPlayoff.group(1)!);
    }
    final m = RegExp(r'\d+$').firstMatch(k);
    if (m != null && m.group(0) != null) {
      return int.tryParse(m.group(0)!);
    }
    return null;
  }

  static int? extractSetNumber(String? matchKey) {
    if (matchKey == null || matchKey.isEmpty) return null;
    final k = matchKey.trim().toLowerCase();
    final m = RegExp(r'_(?:sf|qf|f)(\d+)m\d+').firstMatch(k);
    if (m != null && m.group(1) != null) {
      return int.tryParse(m.group(1)!);
    }
    return null;
  }

  static bool isSameMatchKeys({
    String? asgnMatchKey,
    int? asgnMatchNumber,
    String? asgnCompLevel,
    required String matchKey,
    int? matchNumber,
    String? compLevel,
  }) {
    final aKey = (asgnMatchKey ?? '').trim().toLowerCase();
    final mKey = matchKey.trim().toLowerCase();

    // 1. If both have matchKey, strict equality is required!
    if (aKey.isNotEmpty && mKey.isNotEmpty) {
      return aKey == mKey;
    }

    final aNum = extractMatchNumber(aKey, asgnMatchNumber);
    final mNum = extractMatchNumber(mKey, matchNumber);
    final aComp = extractCompLevel(aKey, asgnCompLevel);
    final mComp = extractCompLevel(mKey, compLevel);
    final aSet = extractSetNumber(aKey);
    final mSet = extractSetNumber(mKey);

    // 2. Match number must match
    if (aNum == null || mNum == null || aNum != mNum) {
      return false;
    }

    // 3. Stage / competition level must match if specified
    if (aComp != null && mComp != null && aComp != mComp) {
      return false;
    }

    // 4. Playoff set numbers (for SF/QF/Finals) must match
    final isPlayoff = aComp == 'sf' || aComp == 'qf' || aComp == 'f' ||
                      mComp == 'sf' || mComp == 'qf' || mComp == 'f';
    if (isPlayoff) {
      if (aSet != null && mSet != null && aSet != mSet) {
        return false;
      }
      if ((aSet != null && mSet == null) || (aSet == null && mSet != null)) {
        return false;
      }
    }

    // 5. If one has matchKey and the other has compLevel, verify stage prefix
    if (aKey.isNotEmpty && mKey.isEmpty) {
      if ((aKey.contains('_pr') || aKey.contains('_pm')) && mComp != null && mComp != 'pr') return false;
      if (aKey.contains('_qm') && mComp != null && mComp != 'qm') return false;
      if (aKey.contains('_sf') && mComp != null && mComp != 'sf') return false;
      if (aKey.contains('_qf') && mComp != null && mComp != 'qf') return false;
      if (aKey.contains('_f') && mComp != null && mComp != 'f') return false;
    }
    if (aKey.isEmpty && mKey.isNotEmpty) {
      if ((mKey.contains('_pr') || mKey.contains('_pm')) && aComp != null && aComp != 'pr') return false;
      if (mKey.contains('_qm') && aComp != null && aComp != 'qm') return false;
      if (mKey.contains('_sf') && aComp != null && aComp != 'sf') return false;
      if (mKey.contains('_qf') && aComp != null && aComp != 'qf') return false;
      if (mKey.contains('_f') && aComp != null && aComp != 'f') return false;
    }

    return true;
  }
}
