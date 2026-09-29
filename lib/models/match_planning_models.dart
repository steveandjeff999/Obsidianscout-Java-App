import 'dart:convert';

class TeamMarkerPosition {
  final double xRatio;
  final double yRatio;

  const TeamMarkerPosition({
    required this.xRatio,
    required this.yRatio,
  });

  factory TeamMarkerPosition.fromJson(Map<String, dynamic> json) {
    final x = (json['xRatio'] ?? json['x']) as num? ?? 0.5;
    final y = (json['yRatio'] ?? json['y']) as num? ?? 0.5;
    return TeamMarkerPosition(
      xRatio: x.toDouble().clamp(0.0, 1.0),
      yRatio: y.toDouble().clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'xRatio': xRatio,
        'yRatio': yRatio,
      };

  TeamMarkerPosition copyWith({double? xRatio, double? yRatio}) {
    return TeamMarkerPosition(
      xRatio: xRatio ?? this.xRatio,
      yRatio: yRatio ?? this.yRatio,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamMarkerPosition &&
          runtimeType == other.runtimeType &&
          (xRatio - other.xRatio).abs() < 0.0001 &&
          (yRatio - other.yRatio).abs() < 0.0001;

  @override
  int get hashCode => Object.hash(xRatio, yRatio);
}

class StrokePoint {
  final double xRatio;
  final double yRatio;

  const StrokePoint(this.xRatio, this.yRatio);

  factory StrokePoint.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      num nx = (json['xRatio'] ?? json['x']) as num? ?? 0.0;
      num ny = (json['yRatio'] ?? json['y']) as num? ?? 0.0;
      // If legacy absolute coords were saved (e.g. > 1), normalize based on standard 1000x500 box
      if (nx > 1.0) nx = nx / 1000.0;
      if (ny > 1.0) ny = ny / 500.0;
      return StrokePoint(nx.toDouble().clamp(0.0, 1.0), ny.toDouble().clamp(0.0, 1.0));
    }
    return const StrokePoint(0.0, 0.0);
  }

  Map<String, dynamic> toJson() => {
        'x': xRatio,
        'y': yRatio,
        'xRatio': xRatio,
        'yRatio': yRatio,
      };
}

class StrokeAnnotation {
  final String tool; // 'pen' | 'eraser'
  final String color;
  final double widthRatio;
  final List<StrokePoint> points;

  StrokeAnnotation({
    this.tool = 'pen',
    this.color = '#ffffff',
    this.widthRatio = 0.006,
    List<StrokePoint>? points,
  }) : points = points ?? [];

  factory StrokeAnnotation.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List? ?? [];
    final pointsList = rawPoints.map((p) => StrokePoint.fromJson(p)).toList();
    final rawWidthRatio = (json['widthRatio'] as num?)?.toDouble() ??
        ((json['width'] as num?)?.toDouble() != null
            ? (json['width'] as num).toDouble() / 1000.0
            : 0.006);

    return StrokeAnnotation(
      tool: json['tool']?.toString() ?? 'pen',
      color: json['color']?.toString() ?? '#ffffff',
      widthRatio: rawWidthRatio.clamp(0.001, 0.1),
      points: pointsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'color': color,
        'widthRatio': widthRatio,
        'points': points.map((p) => p.toJson()).toList(),
      };

  StrokeAnnotation copyWith({
    String? tool,
    String? color,
    double? widthRatio,
    List<StrokePoint>? points,
  }) {
    return StrokeAnnotation(
      tool: tool ?? this.tool,
      color: color ?? this.color,
      widthRatio: widthRatio ?? this.widthRatio,
      points: points ?? List.from(this.points),
    );
  }
}

class MatchPlanModel {
  final List<StrokeAnnotation> annotations;
  final Map<String, TeamMarkerPosition> teamMarkerPositions;
  final int updatedAt;

  MatchPlanModel({
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    this.updatedAt = 0,
  })  : annotations = annotations ?? [],
        teamMarkerPositions = teamMarkerPositions ?? defaultMarkerPositions();

  static Map<String, TeamMarkerPosition> defaultMarkerPositions() {
    return {
      'b1': const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.20),
      'b2': const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.50),
      'b3': const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.80),
      'r1': const TeamMarkerPosition(xRatio: 0.88, yRatio: 0.20),
      'r2': const TeamMarkerPosition(xRatio: 0.88, yRatio: 0.50),
      'r3': const TeamMarkerPosition(xRatio: 0.88, yRatio: 0.80),
    };
  }

  factory MatchPlanModel.fromJsonString(String rawJson, {int updatedAt = 0}) {
    if (rawJson.trim().isEmpty || rawJson.trim() == '{}') {
      return MatchPlanModel(updatedAt: updatedAt);
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return MatchPlanModel.fromJson(decoded, updatedAt: updatedAt);
      }
    } catch (_) {}
    return MatchPlanModel(updatedAt: updatedAt);
  }

  factory MatchPlanModel.fromJson(Map<String, dynamic> json, {int updatedAt = 0}) {
    final rawAnnotations = json['annotations'] as List? ?? [];
    final annotationsList = rawAnnotations
        .whereType<Map<String, dynamic>>()
        .map((a) => StrokeAnnotation.fromJson(a))
        .toList();

    final markers = defaultMarkerPositions();
    if (json['teamMarkerPositions'] is Map<String, dynamic>) {
      final map = json['teamMarkerPositions'] as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          markers[k] = TeamMarkerPosition.fromJson(v);
        }
      });
    }

    final ts = (json['updatedAt'] as num?)?.toInt() ?? updatedAt;

    return MatchPlanModel(
      annotations: annotationsList,
      teamMarkerPositions: markers,
      updatedAt: ts,
    );
  }

  Map<String, dynamic> toJson() => {
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'teamMarkerPositions': teamMarkerPositions.map((k, v) => MapEntry(k, v.toJson())),
      };

  String toJsonString() => jsonEncode(toJson());

  MatchPlanModel copyWith({
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    int? updatedAt,
  }) {
    return MatchPlanModel(
      annotations: annotations ?? List.from(this.annotations),
      teamMarkerPositions: teamMarkerPositions ?? Map.from(this.teamMarkerPositions),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class FieldImageInfoModel {
  final String imagePath;
  final String? filename;
  final int? year;

  const FieldImageInfoModel({
    required this.imagePath,
    this.filename,
    this.year,
  });

  factory FieldImageInfoModel.fromJson(Map<String, dynamic> json) {
    return FieldImageInfoModel(
      imagePath: json['imagePath']?.toString() ?? '',
      filename: json['filename']?.toString(),
      year: (json['year'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        if (filename != null) 'filename': filename,
        if (year != null) 'year': year,
      };
}
