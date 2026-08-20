/// Models for scouting entries returned by /api/scouting
class ScoutingEntryModel {
  final String? matchKey;
  final String? eventKey;
  final int? matchNumber;
  final int? targetTeamNumber;
  final bool isPrescout;
  final Map<String, dynamic> data;

  ScoutingEntryModel({
    this.matchKey,
    this.eventKey,
    this.matchNumber,
    this.targetTeamNumber,
    this.isPrescout = false,
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

    return ScoutingEntryModel(
      matchKey: parsedData['matchKey']?.toString() ?? json['matchKey']?.toString(),
      eventKey: parsedData['eventKey']?.toString() ?? json['eventKey']?.toString(),
      matchNumber: (parsedData['matchNumber'] as num?)?.toInt() ?? (json['matchNumber'] as num?)?.toInt(),
      targetTeamNumber: (parsedData['targetTeamNumber'] as num?)?.toInt() ?? (json['targetTeamNumber'] as num?)?.toInt(),
      isPrescout: json['isPrescout'] == true,
      data: parsedData,
    );
  }
}

/// A selectable metric for graphing
class GraphMetric {
  final String id;
  final String label;
  final String kind; // "count", "numeric", "score"
  final String? fieldId;

  const GraphMetric({
    required this.id,
    required this.label,
    required this.kind,
    this.fieldId,
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
