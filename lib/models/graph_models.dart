import 'config_models.dart';

/// Models for scouting entries returned by /api/scouting
class ScoutingEntryModel {
  final String? matchKey;
  final String? eventKey;
  final int? matchNumber;
  final int? targetTeamNumber;
  final bool isPrescout;
  final bool hasDiscrepancy;
  final int? matchPlayedTime;
  final Map<String, dynamic> data;

  ScoutingEntryModel({
    this.matchKey,
    this.eventKey,
    this.matchNumber,
    this.targetTeamNumber,
    this.isPrescout = false,
    this.hasDiscrepancy = false,
    this.matchPlayedTime,
    this.data = const {},
  });

  factory ScoutingEntryModel.fromJson(Map<String, dynamic> json) {
    // Server returns entries with a nested `data` field
    final rawData = json['data'];
    Map<String, dynamic> parsedData = {};
    if (rawData is Map<String, dynamic>) {
      parsedData = rawData;
    } else if (rawData == null) {
      // The entry itself is the data (flat format)
      parsedData = json;
    }

    final playedTime = (json['matchPlayedTime'] as num?)?.toInt() ??
        (parsedData['matchPlayedTime'] as num?)?.toInt() ??
        (json['match_played_time'] as num?)?.toInt();

    return ScoutingEntryModel(
      matchKey: parsedData['matchKey']?.toString() ?? json['matchKey']?.toString(),
      eventKey: parsedData['eventKey']?.toString() ?? json['eventKey']?.toString(),
      matchNumber: (parsedData['matchNumber'] as num?)?.toInt() ?? (json['matchNumber'] as num?)?.toInt(),
      targetTeamNumber: (parsedData['targetTeamNumber'] as num?)?.toInt() ?? (json['targetTeamNumber'] as num?)?.toInt(),
      isPrescout: json['isPrescout'] == true || parsedData['isPrescout'] == true,
      hasDiscrepancy: json['hasDiscrepancy'] == true || parsedData['hasDiscrepancy'] == true,
      matchPlayedTime: playedTime,
      data: parsedData,
    );
  }
}

/// A selectable metric for graphing
class GraphMetric {
  final String id;
  final String label;
  final String kind; // "count", "numeric", "score", "category"
  final String? scope; // "total", "auto", "teleop", "endgame"
  final String? fieldId;
  final ScoutingFieldModel? field;

  const GraphMetric({
    required this.id,
    required this.label,
    required this.kind,
    this.scope,
    this.fieldId,
    this.field,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphMetric &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A single data point [label, value] for bar/line charts
class GraphPoint {
  final String label;
  final double value;

  const GraphPoint(this.label, this.value);
}

/// A series of points (for multi-line / grouped-bar)
class GraphSeries {
  final String name;
  final List<String> x;
  final List<double> y;

  const GraphSeries({required this.name, required this.x, required this.y});
}

/// Statistical summary for Box Plot / Violin distributions
class DistributionStats {
  final String name;
  final double min;
  final double q1;
  final double median;
  final double q3;
  final double max;
  final double mean;
  final int count;
  final List<double> rawValues;
  final List<double> outliers;

  DistributionStats({
    required this.name,
    required this.min,
    required this.q1,
    required this.median,
    required this.q3,
    required this.max,
    required this.mean,
    required this.count,
    required this.rawValues,
    this.outliers = const [],
  });

  factory DistributionStats.fromValues(String name, List<double> values) {
    if (values.isEmpty) {
      return DistributionStats(
        name: name,
        min: 0,
        q1: 0,
        median: 0,
        q3: 0,
        max: 0,
        mean: 0,
        count: 0,
        rawValues: [],
        outliers: [],
      );
    }

    final sorted = List<double>.from(values)..sort();
    final n = sorted.length;
    final min = sorted.first;
    final max = sorted.last;
    final mean = sorted.reduce((a, b) => a + b) / n;

    double quantile(double q) {
      if (n == 1) return sorted.first;
      final pos = q * (n - 1);
      final low = pos.floor();
      final high = pos.ceil();
      final weight = pos - low;
      return sorted[low] * (1.0 - weight) + sorted[high] * weight;
    }

    final q1 = quantile(0.25);
    final median = quantile(0.50);
    final q3 = quantile(0.75);
    final iqr = q3 - q1;
    final lowerFence = q1 - 1.5 * iqr;
    final upperFence = q3 + 1.5 * iqr;

    final outliers = sorted.where((v) => v < lowerFence || v > upperFence).toList();

    return DistributionStats(
      name: name,
      min: min,
      q1: q1,
      median: median,
      q3: q3,
      max: max,
      mean: mean,
      count: n,
      rawValues: sorted,
      outliers: outliers,
    );
  }
}

/// Histogram bin frequency data
class HistogramBin {
  final String rangeLabel;
  final double start;
  final double end;
  final int count;

  HistogramBin({
    required this.rangeLabel,
    required this.start,
    required this.end,
    required this.count,
  });
}

/// Statistics history cache returned by /api/stats/history
class StatsHistoryModel {
  final Map<String, double> oprs;
  final List<dynamic> epaHistory;
  final List<dynamic> match13History;

  StatsHistoryModel({
    this.oprs = const {},
    this.epaHistory = const [],
    this.match13History = const [],
  });

  factory StatsHistoryModel.fromJson(Map<String, dynamic> json) {
    final rawOprs = json['oprs'];
    final Map<String, double> parsedOprs = {};
    if (rawOprs is Map) {
      rawOprs.forEach((k, v) {
        if (v is num) parsedOprs[k.toString()] = v.toDouble();
      });
    }

    final rawEpa = json['epaHistory'] as List<dynamic>? ?? [];
    final rawMatch13 = json['match13History'] as List<dynamic>? ?? [];

    return StatsHistoryModel(
      oprs: parsedOprs,
      epaHistory: rawEpa,
      match13History: rawMatch13,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'oprs': oprs,
      'epaHistory': epaHistory,
      'match13History': match13History,
    };
  }
}

/// Helper to extract Match 13 EXP team object from a Match 13 match object
dynamic extractTeamExpData(dynamic matchObj, int teamNumber) {
  if (matchObj is! Map) return null;
  final teams = matchObj['teams'];
  if (teams == null) return null;

  if (teams is List) {
    for (final t in teams) {
      if (t is Map) {
        final rawNum = t['teamNumber'] ?? t['team_number'] ?? t['team'];
        int? parsedNum;
        if (rawNum is num) {
          parsedNum = rawNum.toInt();
        } else if (rawNum != null) {
          parsedNum = int.tryParse(rawNum.toString().replaceAll(RegExp(r'[^0-9]'), ''));
        } else if (t['teamKey'] != null) {
          parsedNum = int.tryParse(t['teamKey'].toString().replaceAll(RegExp(r'[^0-9]'), ''));
        }
        if (parsedNum == teamNumber) return t;
      }
    }
    return null;
  }

  if (teams is Map) {
    return teams[teamNumber] ??
        teams['$teamNumber'] ??
        teams['frc$teamNumber'] ??
        teams['ftc$teamNumber'] ??
        teams['frc_$teamNumber'];
  }

  return null;
}

/// Helper to extract numeric value from Match 13 team data given a metric ID
double getTeamExpMetricValue(dynamic teamExpData, String metricId) {
  if (teamExpData is! Map) return 0.0;

  double numVal(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  if (metricId == 'score_auto') {
    final v = teamExpData['xAutoPost'] ??
        teamExpData['xAuto'] ??
        teamExpData['xAutoPre'] ??
        teamExpData['auto'] ??
        teamExpData['auto_exp'] ??
        teamExpData['autoExp'];
    return numVal(v);
  }

  if (metricId == 'score_teleop') {
    final v = teamExpData['xTelePost'] ??
        teamExpData['xTele'] ??
        teamExpData['xTelePre'] ??
        teamExpData['teleop'] ??
        teamExpData['teleop_exp'] ??
        teamExpData['teleopExp'];
    return numVal(v);
  }

  if (metricId == 'score_endgame') {
    final v = teamExpData['xEndPost'] ??
        teamExpData['xEnd'] ??
        teamExpData['xEndPre'] ??
        teamExpData['endgame'] ??
        teamExpData['endgame_exp'] ??
        teamExpData['endgameExp'];
    return numVal(v);
  }

  final v = teamExpData['xpPost'] ??
      teamExpData['xp'] ??
      teamExpData['xpPre'] ??
      teamExpData['exp'] ??
      teamExpData['total'] ??
      teamExpData['total_points'];
  return numVal(v);
}

/// Helper to convert a matchKey to user-friendly label (QM 1, SF 1-1, Final 1)
String formatMatchKeyToLabel(String? matchKey) {
  if (matchKey == null || matchKey.isEmpty) return 'Match';
  final str = matchKey.trim();
  final parts = str.split('_');
  final compPart = parts.length > 1 ? parts[1].toLowerCase() : str.toLowerCase();

  if (compPart.startsWith('qm')) {
    return 'QM ${compPart.replaceFirst('qm', '')}';
  }
  if (compPart.startsWith('qf')) {
    final match = RegExp(r'qf(\d+)m(\d+)').firstMatch(compPart);
    return match != null ? 'QF ${match.group(1)}-${match.group(2)}' : compPart.toUpperCase();
  }
  if (compPart.startsWith('sf')) {
    final match = RegExp(r'sf(\d+)m(\d+)').firstMatch(compPart);
    return match != null ? 'SF ${match.group(1)}-${match.group(2)}' : compPart.toUpperCase();
  }
  if (compPart.startsWith('f')) {
    final match = RegExp(r'f(\d+)m(\d+)').firstMatch(compPart);
    return match != null ? 'Final ${match.group(2)}' : compPart.toUpperCase();
  }
  return compPart.toUpperCase();
}

/// Helper to compute integer sort order from match label
int getMatchSortWeightFromLabel(String label) {
  if (label.isEmpty) return 0;
  final str = label.trim().toLowerCase();

  if (str.contains('prescout')) {
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
  }
  if (str.startsWith('practice') || str.startsWith('pm')) {
    final match = RegExp(r'\d+').firstMatch(str);
    final num = match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
    return 100000 + (num * 100);
  }
  if (str.startsWith('qm') || str.startsWith('q ') || str.startsWith('qual') || str.startsWith('match')) {
    final match = RegExp(r'\d+').firstMatch(str);
    final num = match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
    return 200000 + (num * 100);
  }
  if (str.startsWith('ef')) {
    final matches = RegExp(r'\d+').allMatches(str).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    final setNum = matches.isNotEmpty ? matches[0] : 0;
    final matchNum = matches.length > 1 ? matches[1] : 0;
    return 300000 + (setNum * 1000) + matchNum;
  }
  if (str.startsWith('qf')) {
    final matches = RegExp(r'\d+').allMatches(str).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    final setNum = matches.isNotEmpty ? matches[0] : 0;
    final matchNum = matches.length > 1 ? matches[1] : 0;
    return 400000 + (setNum * 1000) + matchNum;
  }
  if (str.startsWith('sf') || str.startsWith('semi')) {
    final matches = RegExp(r'\d+').allMatches(str).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    final setNum = matches.isNotEmpty ? matches[0] : 0;
    final matchNum = matches.length > 1 ? matches[1] : 0;
    return 500000 + (setNum * 1000) + matchNum;
  }
  if (str.startsWith('f ') || str.startsWith('final') || RegExp(r'^f\d').hasMatch(str)) {
    final matches = RegExp(r'\d+').allMatches(str).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
    final setNum = matches.isNotEmpty ? matches[0] : 0;
    final matchNum = matches.length > 1 ? matches[1] : 0;
    return 600000 + (setNum * 1000) + matchNum;
  }
  final match = RegExp(r'\d+').firstMatch(str);
  final anyNum = match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
  return 200000 + (anyNum * 100);
}
