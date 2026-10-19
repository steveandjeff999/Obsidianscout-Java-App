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

class MatchPhasePlan {
  final List<StrokeAnnotation> annotations;
  final Map<String, TeamMarkerPosition> teamMarkerPositions;
  final Set<String> touchedMarkers;

  MatchPhasePlan({
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    Set<String>? touchedMarkers,
  })  : annotations = annotations ?? [],
        teamMarkerPositions = teamMarkerPositions ?? MatchPlanModel.defaultMarkerPositions(),
        touchedMarkers = touchedMarkers ?? <String>{};

  factory MatchPhasePlan.fromJson(
    Map<String, dynamic> json, {
    Map<String, TeamMarkerPosition>? fallbackPositions,
  }) {
    final rawAnnotations = json['annotations'] as List? ?? [];
    final annotationsList = rawAnnotations
        .whereType<Map<String, dynamic>>()
        .map((a) => StrokeAnnotation.fromJson(a))
        .toList();

    final basePositions = fallbackPositions != null
        ? Map<String, TeamMarkerPosition>.from(fallbackPositions)
        : MatchPlanModel.defaultMarkerPositions();
    final markers = Map<String, TeamMarkerPosition>.from(basePositions);

    if (json['teamMarkerPositions'] is Map<String, dynamic>) {
      final map = json['teamMarkerPositions'] as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          markers[k] = TeamMarkerPosition.fromJson(v);
        }
      });
    }

    final touched = <String>{};
    if (json['touchedMarkers'] is List) {
      for (final item in (json['touchedMarkers'] as List)) {
        if (item != null) touched.add(item.toString());
      }
    } else if (json['teamMarkerPositions'] is Map<String, dynamic>) {
      // Infer touched markers if positions differ from fallbackPositions
      for (final entry in markers.entries) {
        final basePos = basePositions[entry.key];
        if (basePos == null || basePos != entry.value) {
          touched.add(entry.key);
        }
      }
    }

    return MatchPhasePlan(
      annotations: annotationsList,
      teamMarkerPositions: markers,
      touchedMarkers: touched,
    );
  }

  Map<String, dynamic> toJson() => {
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'teamMarkerPositions': teamMarkerPositions.map((k, v) => MapEntry(k, v.toJson())),
        'touchedMarkers': touchedMarkers.toList(),
      };

  MatchPhasePlan copyWith({
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    Set<String>? touchedMarkers,
  }) {
    return MatchPhasePlan(
      annotations: annotations ?? List<StrokeAnnotation>.from(this.annotations),
      teamMarkerPositions:
          teamMarkerPositions ?? Map<String, TeamMarkerPosition>.from(this.teamMarkerPositions),
      touchedMarkers: touchedMarkers ?? Set<String>.from(this.touchedMarkers),
    );
  }
}

class MatchPlanModel {
  static const List<String> phaseOrder = ['auto', 'teleop', 'endgame'];

  final Map<String, MatchPhasePlan> phases;
  final int updatedAt;

  MatchPlanModel({
    Map<String, MatchPhasePlan>? phases,
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    this.updatedAt = 0,
  }) : phases = _initPhases(
          phases: phases,
          legacyAnnotations: annotations,
          legacyPositions: teamMarkerPositions,
        );

  static Map<String, MatchPhasePlan> _initPhases({
    Map<String, MatchPhasePlan>? phases,
    List<StrokeAnnotation>? legacyAnnotations,
    Map<String, TeamMarkerPosition>? legacyPositions,
  }) {
    if (phases != null) {
      final result = <String, MatchPhasePlan>{
        for (final p in phaseOrder)
          p: phases[p]?.copyWith() ?? MatchPhasePlan(),
      };
      _propagateUntouchedPositions(result);
      return result;
    }

    final autoPositions = legacyPositions != null
        ? Map<String, TeamMarkerPosition>.from(legacyPositions)
        : defaultMarkerPositions();
    final defaults = defaultMarkerPositions();
    final autoTouched = <String>{};
    for (final entry in autoPositions.entries) {
      if (defaults[entry.key] != entry.value) {
        autoTouched.add(entry.key);
      }
    }

    final result = <String, MatchPhasePlan>{
      'auto': MatchPhasePlan(
        annotations: legacyAnnotations != null ? List.from(legacyAnnotations) : [],
        teamMarkerPositions: autoPositions,
        touchedMarkers: autoTouched,
      ),
      'teleop': MatchPhasePlan(
        annotations: [],
        teamMarkerPositions: Map<String, TeamMarkerPosition>.from(autoPositions),
        touchedMarkers: <String>{},
      ),
      'endgame': MatchPhasePlan(
        annotations: [],
        teamMarkerPositions: Map<String, TeamMarkerPosition>.from(autoPositions),
        touchedMarkers: <String>{},
      ),
    };
    _propagateUntouchedPositions(result);
    return result;
  }

  static void _propagateUntouchedPositions(Map<String, MatchPhasePlan> phasesMap) {
    final autoPhase = phasesMap['auto'] ?? MatchPhasePlan();
    final teleopPhase = phasesMap['teleop'] ?? MatchPhasePlan();
    final endgamePhase = phasesMap['endgame'] ?? MatchPhasePlan();

    for (final stationId in defaultMarkerPositions().keys) {
      final autoPos = autoPhase.teamMarkerPositions[stationId] ??
          defaultMarkerPositions()[stationId]!;
      if (!teleopPhase.touchedMarkers.contains(stationId)) {
        teleopPhase.teamMarkerPositions[stationId] = autoPos;
      }
      final teleopPos = teleopPhase.teamMarkerPositions[stationId] ?? autoPos;
      if (!endgamePhase.touchedMarkers.contains(stationId)) {
        endgamePhase.teamMarkerPositions[stationId] = teleopPos;
      }
    }
  }

  MatchPhasePlan phasePlan(String phase) {
    return phases[phase] ?? phases['auto']!;
  }

  List<StrokeAnnotation> get annotations => phasePlan('auto').annotations;

  Map<String, TeamMarkerPosition> get teamMarkerPositions =>
      phasePlan('auto').teamMarkerPositions;

  List<StrokeAnnotation> annotationsForPhase(String phase) =>
      phasePlan(phase).annotations;

  Map<String, TeamMarkerPosition> markerPositionsForPhase(String phase) =>
      phasePlan(phase).teamMarkerPositions;

  void updateMarkerPosition(String phase, String stationId, TeamMarkerPosition pos) {
    final target = phasePlan(phase);
    target.touchedMarkers.add(stationId);
    target.teamMarkerPositions[stationId] = pos;
    _propagateUntouchedPositions(phases);
  }

  MatchPlanModel withPhaseAnnotations(String phase, List<StrokeAnnotation> newAnnotations) {
    final nextPhases = <String, MatchPhasePlan>{
      for (final entry in phases.entries)
        entry.key: entry.key == phase
            ? entry.value.copyWith(annotations: newAnnotations)
            : entry.value.copyWith(),
    };
    return MatchPlanModel(phases: nextPhases, updatedAt: updatedAt);
  }

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
    final ts = (json['updatedAt'] as num?)?.toInt() ?? updatedAt;

    if (json['phases'] is Map<String, dynamic>) {
      final rawPhases = json['phases'] as Map<String, dynamic>;
      final autoMap = rawPhases['auto'] is Map<String, dynamic>
          ? rawPhases['auto'] as Map<String, dynamic>
          : json;
      final autoPlan = MatchPhasePlan.fromJson(
        autoMap,
        fallbackPositions: defaultMarkerPositions(),
      );

      final teleopPlan = rawPhases['teleop'] is Map<String, dynamic>
          ? MatchPhasePlan.fromJson(
              rawPhases['teleop'] as Map<String, dynamic>,
              fallbackPositions: autoPlan.teamMarkerPositions,
            )
          : MatchPhasePlan(
              annotations: [],
              teamMarkerPositions: Map.from(autoPlan.teamMarkerPositions),
              touchedMarkers: <String>{},
            );

      final endgamePlan = rawPhases['endgame'] is Map<String, dynamic>
          ? MatchPhasePlan.fromJson(
              rawPhases['endgame'] as Map<String, dynamic>,
              fallbackPositions: teleopPlan.teamMarkerPositions,
            )
          : MatchPhasePlan(
              annotations: [],
              teamMarkerPositions: Map.from(teleopPlan.teamMarkerPositions),
              touchedMarkers: <String>{},
            );

      return MatchPlanModel(
        phases: {
          'auto': autoPlan,
          'teleop': teleopPlan,
          'endgame': endgamePlan,
        },
        updatedAt: ts,
      );
    }

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

    return MatchPlanModel(
      annotations: annotationsList,
      teamMarkerPositions: markers,
      updatedAt: ts,
    );
  }

  Map<String, dynamic> toJson() {
    _propagateUntouchedPositions(phases);
    final autoPlan = phasePlan('auto');
    return {
      'phases': {
        for (final p in phaseOrder) p: phasePlan(p).toJson(),
      },
      'annotations': autoPlan.annotations.map((a) => a.toJson()).toList(),
      'teamMarkerPositions':
          autoPlan.teamMarkerPositions.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  MatchPlanModel copyWith({
    Map<String, MatchPhasePlan>? phases,
    List<StrokeAnnotation>? annotations,
    Map<String, TeamMarkerPosition>? teamMarkerPositions,
    int? updatedAt,
  }) {
    if (phases != null) {
      return MatchPlanModel(
        phases: {
          for (final entry in phases.entries) entry.key: entry.value.copyWith(),
        },
        updatedAt: updatedAt ?? this.updatedAt,
      );
    }
    if (annotations != null || teamMarkerPositions != null) {
      final copiedPhases = {
        for (final entry in this.phases.entries) entry.key: entry.value.copyWith(),
      };
      final autoPlan = copiedPhases['auto']!;
      copiedPhases['auto'] = autoPlan.copyWith(
        annotations: annotations,
        teamMarkerPositions: teamMarkerPositions,
      );
      return MatchPlanModel(
        phases: copiedPhases,
        updatedAt: updatedAt ?? this.updatedAt,
      );
    }
    return MatchPlanModel(
      phases: {
        for (final entry in this.phases.entries) entry.key: entry.value.copyWith(),
      },
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
