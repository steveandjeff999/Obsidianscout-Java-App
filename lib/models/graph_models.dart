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
