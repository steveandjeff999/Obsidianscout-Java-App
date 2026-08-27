import 'dart:math';
import 'package:flutter/material.dart';

class CustomAnalyticsReportRecord {
  final String id;
  final int ownerTeamNumber;
  final String program;
  final String userId;
  final String title;
  final String category;
  final String? description;
  final String configJson;
  final bool isShared;
  final bool isDefault;
  final String createdAt;
  final String updatedAt;
  final String authorUsername;
  final bool isOwner;

  CustomAnalyticsReportRecord({
    required this.id,
    required this.ownerTeamNumber,
    required this.program,
    required this.userId,
    required this.title,
    this.category = 'General',
    this.description,
    required this.configJson,
    this.isShared = false,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.authorUsername = 'Unknown',
    this.isOwner = false,
  });

  factory CustomAnalyticsReportRecord.fromJson(Map<String, dynamic> json) {
    return CustomAnalyticsReportRecord(
      id: json['id']?.toString() ?? '',
      ownerTeamNumber: json['ownerTeamNumber'] is num ? (json['ownerTeamNumber'] as num).toInt() : int.tryParse(json['ownerTeamNumber']?.toString() ?? '') ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      userId: json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Report',
      category: json['category']?.toString() ?? 'General',
      description: json['description']?.toString(),
      configJson: json['configJson']?.toString() ?? '{}',
      isShared: json['isShared'] == true,
      isDefault: json['isDefault'] == true,
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      authorUsername: json['authorUsername']?.toString() ?? 'Unknown',
      isOwner: json['isOwner'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerTeamNumber': ownerTeamNumber,
      'program': program,
      'userId': userId,
      'title': title,
      'category': category,
      'description': description,
      'configJson': configJson,
      'isShared': isShared,
      'isDefault': isDefault,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'authorUsername': authorUsername,
      'isOwner': isOwner,
    };
  }
}

class CustomAnalyticsSlicers {
  String eventKey;
  List<int> teamNumbers;
  bool practice;
  bool quals;
  bool playoffs;
  bool includePrescout;

  CustomAnalyticsSlicers({
    this.eventKey = '',
    List<int>? teamNumbers,
    this.practice = true,
    this.quals = true,
    this.playoffs = true,
    this.includePrescout = true,
  }) : teamNumbers = teamNumbers ?? [];

  factory CustomAnalyticsSlicers.fromJson(Map<String, dynamic> json) {
    List<int> teams = [];
    if (json['teamNumbers'] is List) {
      teams = (json['teamNumbers'] as List)
          .map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()) ?? 0)
          .where((t) => t > 0)
          .toList();
    }
    return CustomAnalyticsSlicers(
      eventKey: json['eventKey']?.toString() ?? '',
      teamNumbers: teams,
      practice: json['practice'] != false,
      quals: json['quals'] != false,
      playoffs: json['playoffs'] != false,
      includePrescout: json['includePrescout'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventKey': eventKey,
      'teamNumbers': teamNumbers,
      'practice': practice,
      'quals': quals,
      'playoffs': playoffs,
      'includePrescout': includePrescout,
    };
  }

  CustomAnalyticsSlicers clone() {
    return CustomAnalyticsSlicers(
      eventKey: eventKey,
      teamNumbers: List<int>.from(teamNumbers),
      practice: practice,
      quals: quals,
      playoffs: playoffs,
      includePrescout: includePrescout,
    );
  }
}

class CustomCalculatedMetric {
  String id;
  String name;
  String formula;

  CustomCalculatedMetric({
    required this.id,
    required this.name,
    required this.formula,
  });

  factory CustomCalculatedMetric.fromJson(Map<String, dynamic> json) {
    return CustomCalculatedMetric(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      formula: json['formula']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'formula': formula,
    };
  }

  CustomCalculatedMetric clone() {
    return CustomCalculatedMetric(id: id, name: name, formula: formula);
  }
}

class CustomAnalyticsWidget {
  String id;
  String type; // kpi, bar, stacked_bar, line, scatter, box, violin, radar, donut, matrix, heatmap, histogram
  String title;
  String subtitle;
  String width; // col-3, col-4, col-6, col-8, col-12
  String dimension; // teamNumber, matchNumber, eventKey
  String measure; // calc_total_score, calc_auto_score, etc.
  String aggregation; // avg, sum, median, max, min, count, stdev, p75
  List<String> secondaryMeasures;
  String palette; // obsidian, emerald, sunset, cyberpunk, alliance
  String sort; // val_desc, val_asc, dim_asc, dim_desc
  int topN; // 0 = all
  double? targetLine;

  CustomAnalyticsWidget({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle = '',
    this.width = 'col-6',
    this.dimension = 'teamNumber',
    this.measure = 'calc_total_score',
    this.aggregation = 'avg',
    List<String>? secondaryMeasures,
    this.palette = 'obsidian',
    this.sort = 'val_desc',
    this.topN = 0,
    this.targetLine,
  }) : secondaryMeasures = secondaryMeasures ?? [];

  factory CustomAnalyticsWidget.fromJson(Map<String, dynamic> json) {
    List<String> sec = [];
    if (json['secondaryMeasures'] is List) {
      sec = (json['secondaryMeasures'] as List).map((e) => e.toString()).toList();
    }
    return CustomAnalyticsWidget(
      id: json['id']?.toString() ?? 'w_${DateTime.now().millisecondsSinceEpoch}',
      type: json['type']?.toString() ?? 'bar',
      title: json['title']?.toString() ?? 'Visual',
      subtitle: json['subtitle']?.toString() ?? '',
      width: json['width']?.toString() ?? 'col-6',
      dimension: json['dimension']?.toString() ?? 'teamNumber',
      measure: json['measure']?.toString() ?? 'calc_total_score',
      aggregation: json['aggregation']?.toString() ?? 'avg',
      secondaryMeasures: sec,
      palette: json['palette']?.toString() ?? 'obsidian',
      sort: json['sort']?.toString() ?? 'val_desc',
      topN: json['topN'] is num ? (json['topN'] as num).toInt() : int.tryParse(json['topN']?.toString() ?? '') ?? 0,
      targetLine: json['targetLine'] is num ? (json['targetLine'] as num).toDouble() : double.tryParse(json['targetLine']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'width': width,
      'dimension': dimension,
      'measure': measure,
      'aggregation': aggregation,
      'secondaryMeasures': secondaryMeasures,
      'palette': palette,
      'sort': sort,
      'topN': topN,
      'targetLine': targetLine,
    };
  }

  CustomAnalyticsWidget clone() {
    return CustomAnalyticsWidget(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      width: width,
      dimension: dimension,
      measure: measure,
      aggregation: aggregation,
      secondaryMeasures: List<String>.from(secondaryMeasures),
      palette: palette,
      sort: sort,
      topN: topN,
      targetLine: targetLine,
    );
  }
}

class CustomAnalyticsConfig {
  String? id;
  String title;
  String category;
  String description;
  bool isShared;
  bool isDefault;
  CustomAnalyticsSlicers slicers;
  List<CustomCalculatedMetric> calculatedMetrics;
  List<CustomAnalyticsWidget> widgets;

  CustomAnalyticsConfig({
    this.id,
    this.title = 'Match Strategy & Performance',
    this.category = 'Strategy',
    this.description = 'Interactive multi-metric performance dashboard',
    this.isShared = false,
    this.isDefault = false,
    CustomAnalyticsSlicers? slicers,
    List<CustomCalculatedMetric>? calculatedMetrics,
    List<CustomAnalyticsWidget>? widgets,
  })  : slicers = slicers ?? CustomAnalyticsSlicers(),
        calculatedMetrics = calculatedMetrics ?? [],
        widgets = widgets ?? getDefaultWidgets();

  factory CustomAnalyticsConfig.fromJson(Map<String, dynamic> json) {
    List<CustomCalculatedMetric> metrics = [];
    if (json['calculatedMetrics'] is List) {
      metrics = (json['calculatedMetrics'] as List)
          .map((e) => CustomCalculatedMetric.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<CustomAnalyticsWidget> widgets = [];
    if (json['widgets'] is List) {
      widgets = (json['widgets'] as List)
          .map((e) => CustomAnalyticsWidget.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      widgets = getDefaultWidgets();
    }

    return CustomAnalyticsConfig(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? 'Match Strategy & Performance',
      category: json['category']?.toString() ?? 'Strategy',
      description: json['description']?.toString() ?? 'Interactive multi-metric performance dashboard',
      isShared: json['isShared'] == true,
      isDefault: json['isDefault'] == true,
      slicers: json['slicers'] is Map<String, dynamic>
          ? CustomAnalyticsSlicers.fromJson(json['slicers'] as Map<String, dynamic>)
          : CustomAnalyticsSlicers(),
      calculatedMetrics: metrics,
      widgets: widgets,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'category': category,
      'description': description,
      'isShared': isShared,
      'isDefault': isDefault,
      'slicers': slicers.toJson(),
      'calculatedMetrics': calculatedMetrics.map((m) => m.toJson()).toList(),
      'widgets': widgets.map((w) => w.toJson()).toList(),
    };
  }

  CustomAnalyticsConfig clone() {
    return CustomAnalyticsConfig(
      id: id,
      title: title,
      category: category,
      description: description,
      isShared: isShared,
      isDefault: isDefault,
      slicers: slicers.clone(),
      calculatedMetrics: calculatedMetrics.map((m) => m.clone()).toList(),
      widgets: widgets.map((w) => w.clone()).toList(),
    );
  }

  static List<CustomAnalyticsWidget> getDefaultWidgets() {
    return [
      CustomAnalyticsWidget(
        id: 'w_kpi_total',
        type: 'kpi',
        title: 'Event Scoring Average',
        subtitle: 'Mean Total Points per Match',
        width: 'col-3',
        dimension: 'teamNumber',
        measure: 'calc_total_score',
        aggregation: 'avg',
        palette: 'obsidian',
        sort: 'val_desc',
      ),
      CustomAnalyticsWidget(
        id: 'w_kpi_auto',
        type: 'kpi',
        title: 'Autonomous Average',
        subtitle: 'Mean Auto Score',
        width: 'col-3',
        dimension: 'teamNumber',
        measure: 'calc_auto_score',
        aggregation: 'avg',
        palette: 'emerald',
        sort: 'val_desc',
      ),
      CustomAnalyticsWidget(
        id: 'w_kpi_teleop',
        type: 'kpi',
        title: 'Teleop Average',
        subtitle: 'Mean Teleop Score',
        width: 'col-3',
        dimension: 'teamNumber',
        measure: 'calc_teleop_score',
        aggregation: 'avg',
        palette: 'sunset',
        sort: 'val_desc',
      ),
      CustomAnalyticsWidget(
        id: 'w_kpi_matches',
        type: 'kpi',
        title: 'Total Matches Scouted',
        subtitle: 'Scouting Sample Size',
        width: 'col-3',
        dimension: 'teamNumber',
        measure: 'matchNumber',
        aggregation: 'count',
        palette: 'cyberpunk',
        sort: 'val_desc',
      ),
      CustomAnalyticsWidget(
        id: 'w_stacked_scoring',
        type: 'stacked_bar',
        title: 'Points Breakdown by Game Phase',
        subtitle: 'Auto vs Teleop Points per Team',
        width: 'col-8',
        dimension: 'teamNumber',
        measure: 'calc_auto_score',
        aggregation: 'avg',
        secondaryMeasures: ['calc_teleop_score'],
        palette: 'obsidian',
        sort: 'val_desc',
        topN: 16,
      ),
      CustomAnalyticsWidget(
        id: 'w_phase_donut',
        type: 'donut',
        title: 'Overall Points Distribution',
        subtitle: 'Auto vs Teleop Proportion',
        width: 'col-4',
        dimension: 'teamNumber',
        measure: 'calc_auto_score',
        aggregation: 'sum',
        secondaryMeasures: ['calc_teleop_score'],
        palette: 'sunset',
        sort: 'val_desc',
      ),
      CustomAnalyticsWidget(
        id: 'w_scatter_auto_tele',
        type: 'scatter',
        title: 'Auto vs Teleop Correlation',
        subtitle: 'X: Auto Score, Y: Teleop Score',
        width: 'col-6',
        dimension: 'teamNumber',
        measure: 'calc_auto_score',
        secondaryMeasures: ['calc_teleop_score'],
        aggregation: 'avg',
        palette: 'emerald',
        sort: 'dim_asc',
      ),
      CustomAnalyticsWidget(
        id: 'w_box_consistency',
        type: 'box',
        title: 'Match Score Variance & Outliers',
        subtitle: 'Box & Whisker Distribution',
        width: 'col-6',
        dimension: 'teamNumber',
        measure: 'calc_total_score',
        aggregation: 'avg',
        palette: 'cyberpunk',
        sort: 'val_desc',
        topN: 12,
      ),
      CustomAnalyticsWidget(
        id: 'w_ranking_matrix',
        type: 'matrix',
        title: 'Comprehensive Team Performance Matrix',
        subtitle: 'Click rows to inspect drilldown matches',
        width: 'col-12',
        dimension: 'teamNumber',
        measure: 'calc_total_score',
        aggregation: 'avg',
        secondaryMeasures: ['calc_auto_score', 'calc_teleop_score'],
        palette: 'obsidian',
        sort: 'val_desc',
      ),
    ];
  }
}

class CustomAnalyticsField {
  final String id;
  final String label;
  final String type; // number, string, boolean
  final String source; // match, pit, qual, calculated, system
  final String section;
  final double? pointsPer;
  final List<String> options;

  CustomAnalyticsField({
    required this.id,
    required this.label,
    required this.type,
    required this.source,
    this.section = 'General',
    this.pointsPer,
    List<String>? options,
  }) : options = options ?? [];

  factory CustomAnalyticsField.fromJson(Map<String, dynamic> json) {
    List<String> opts = [];
    if (json['options'] is List) {
      opts = (json['options'] as List).map((e) => e.toString()).toList();
    }
    return CustomAnalyticsField(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? 'string',
      source: json['source']?.toString() ?? 'match',
      section: json['section']?.toString() ?? 'General',
      pointsPer: json['pointsPer'] is num ? (json['pointsPer'] as num).toDouble() : double.tryParse(json['pointsPer']?.toString() ?? ''),
      options: opts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      'source': source,
      'section': section,
      if (pointsPer != null) 'pointsPer': pointsPer,
      'options': options,
    };
  }
}

class CustomTeamAnalyticsSummary {
  final int teamNumber;
  final String? name;
  final String? nickname;
  final String? city;
  final String? state;
  final double? opr;
  final double? epa;

  CustomTeamAnalyticsSummary({
    required this.teamNumber,
    this.name,
    this.nickname,
    this.city,
    this.state,
    this.opr,
    this.epa,
  });

  factory CustomTeamAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return CustomTeamAnalyticsSummary(
      teamNumber: json['teamNumber'] is num ? (json['teamNumber'] as num).toInt() : int.tryParse(json['teamNumber']?.toString() ?? '') ?? 0,
      name: json['name']?.toString(),
      nickname: json['nickname']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      opr: json['opr'] is num ? (json['opr'] as num).toDouble() : double.tryParse(json['opr']?.toString() ?? ''),
      epa: json['epa'] is num ? (json['epa'] as num).toDouble() : double.tryParse(json['epa']?.toString() ?? ''),
    );
  }
}

class CustomAnalyticsDataset {
  final String generatedAt;
  final String? eventKey;
  final List<CustomAnalyticsField> fields;
  final List<Map<String, dynamic>> matchEntries;
  final List<Map<String, dynamic>> pitEntries;
  final List<Map<String, dynamic>> qualEntries;
  final List<CustomTeamAnalyticsSummary> teams;
  final int totalMatches;
  final int totalTeams;

  CustomAnalyticsDataset({
    required this.generatedAt,
    this.eventKey,
    required this.fields,
    required this.matchEntries,
    required this.pitEntries,
    required this.qualEntries,
    required this.teams,
    required this.totalMatches,
    required this.totalTeams,
  });

  factory CustomAnalyticsDataset.fromJson(Map<String, dynamic> json) {
    List<CustomAnalyticsField> fList = [];
    if (json['fields'] is List) {
      fList = (json['fields'] as List)
          .map((e) => CustomAnalyticsField.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<Map<String, dynamic>> matches = [];
    if (json['matchEntries'] is List) {
      matches = (json['matchEntries'] as List).cast<Map<String, dynamic>>();
    }

    List<Map<String, dynamic>> pits = [];
    if (json['pitEntries'] is List) {
      pits = (json['pitEntries'] as List).cast<Map<String, dynamic>>();
    }

    List<Map<String, dynamic>> quals = [];
    if (json['qualEntries'] is List) {
      quals = (json['qualEntries'] as List).cast<Map<String, dynamic>>();
    }

    List<CustomTeamAnalyticsSummary> tList = [];
    if (json['teams'] is List) {
      tList = (json['teams'] as List)
          .map((e) => CustomTeamAnalyticsSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return CustomAnalyticsDataset(
      generatedAt: json['generatedAt']?.toString() ?? DateTime.now().toIso8601String(),
      eventKey: json['eventKey']?.toString(),
      fields: fList,
      matchEntries: matches,
      pitEntries: pits,
      qualEntries: quals,
      teams: tList,
      totalMatches: json['totalMatches'] is num ? (json['totalMatches'] as num).toInt() : matches.length,
      totalTeams: json['totalTeams'] is num ? (json['totalTeams'] as num).toInt() : tList.length,
    );
  }
}

/// Color Palettes
class CustomAnalyticsPalettes {
  static const Map<String, List<Color>> palettes = {
    'obsidian': [
      Color(0xFF2563EB),
      Color(0xFF38BDF8),
      Color(0xFF7C3AED),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
    ],
    'emerald': [
      Color(0xFF10B981),
      Color(0xFF059669),
      Color(0xFF34D399),
      Color(0xFF065F46),
      Color(0xFF047857),
      Color(0xFF6EE7B7),
      Color(0xFF022C22),
      Color(0xFFA7F3D0),
    ],
    'sunset': [
      Color(0xFFF97316),
      Color(0xFFEF4444),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
      Color(0xFFFBBF24),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
      Color(0xFFC2410C),
    ],
    'cyberpunk': [
      Color(0xFF00F5D4),
      Color(0xFF7B2CBF),
      Color(0xFFF72585),
      Color(0xFF4CC9F0),
      Color(0xFF7209B7),
      Color(0xFF3A0CA3),
      Color(0xFF4361EE),
      Color(0xFF4895EF),
    ],
    'alliance': [
      Color(0xFF2563EB),
      Color(0xFFEF4444),
      Color(0xFF38BDF8),
      Color(0xFFF87171),
      Color(0xFF1D4ED8),
      Color(0xFFB91C1C),
    ],
  };

  static List<Color> getPalette(String? name) {
    return palettes[name?.toLowerCase()] ?? palettes['obsidian']!;
  }
}

/// Aggregations and Math Helpers
class CustomAnalyticsMath {
  static double computeAggregation(List<num> numbers, String aggType) {
    if (numbers.isEmpty) return 0.0;
    final doubles = numbers.map((n) => n.toDouble()).toList();
    switch (aggType.toLowerCase()) {
      case 'sum':
        return doubles.reduce((a, b) => a + b);
      case 'max':
        return doubles.reduce(max);
      case 'min':
        return doubles.reduce(min);
      case 'count':
        return doubles.length.toDouble();
      case 'median':
        final sorted = List<double>.from(doubles)..sort();
        final mid = sorted.length ~/ 2;
        return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
      case 'stdev':
        if (doubles.isEmpty) return 0.0;
        final avg = doubles.reduce((a, b) => a + b) / doubles.length;
        final sqDiffs = doubles.map((v) => pow(v - avg, 2).toDouble());
        return sqrt(sqDiffs.reduce((a, b) => a + b) / doubles.length);
      case 'p75':
        final sorted = List<double>.from(doubles)..sort();
        final idx = (sorted.length * 0.75).floor();
        return sorted[min(idx, sorted.length - 1)];
      case 'avg':
      default:
        return doubles.reduce((a, b) => a + b) / doubles.length;
    }
  }

  static double computeCorrelation(List<Map<String, dynamic>> entries, String fieldA, String fieldB) {
    final xs = entries.map((e) => (e[fieldA] is num ? (e[fieldA] as num).toDouble() : double.tryParse(e[fieldA]?.toString() ?? '') ?? 0.0)).toList();
    final ys = entries.map((e) => (e[fieldB] is num ? (e[fieldB] as num).toDouble() : double.tryParse(e[fieldB]?.toString() ?? '') ?? 0.0)).toList();
    if (xs.length < 2) return 1.0;

    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;

    double numVal = 0.0;
    double denX = 0.0;
    double denY = 0.0;

    for (int i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      numVal += dx * dy;
      denX += dx * dx;
      denY += dy * dy;
    }

    if (denX == 0 || denY == 0) return 0.0;
    return numVal / sqrt(denX * denY);
  }

  /// Safe mathematical expression parser for formulas like `[field1] * 2 + [field2] / 3`
  static double evaluateFormula(String formula, Map<String, dynamic> entry) {
    try {
      // 1. Replace bracketed field IDs with their numerical value
      String resolved = formula.replaceAllMapped(RegExp(r'\[([a-zA-Z0-9_]+)\]'), (match) {
        final fieldId = match.group(1)!;
        final raw = entry[fieldId];
        if (raw is num) return raw.toString();
        if (raw is String) {
          final p = double.tryParse(raw);
          if (p != null) return p.toString();
        }
        return '0.0';
      });

      // 2. Evaluate arithmetic
      return _ExpressionParser(resolved).parse();
    } catch (_) {
      return 0.0;
    }
  }
}

class _ExpressionParser {
  final List<String> _tokens;
  int _pos = 0;

  _ExpressionParser(String expr) : _tokens = _tokenize(expr.replaceAll(' ', ''));

  double parse() {
    if (_tokens.isEmpty) return 0.0;
    return _parseExpression();
  }

  double _parseExpression() {
    double left = _parseTerm();
    while (_pos < _tokens.length) {
      final op = _tokens[_pos];
      if (op == '+' || op == '-') {
        _pos++;
        double right = _parseTerm();
        if (op == '+') left += right;
        if (op == '-') left -= right;
      } else {
        break;
      }
    }
    return left;
  }

  double _parseTerm() {
    double left = _parseFactor();
    while (_pos < _tokens.length) {
      final op = _tokens[_pos];
      if (op == '*' || op == '/' || op == '%') {
        _pos++;
        double right = _parseFactor();
        if (op == '*') left *= right;
        if (op == '/') left = right != 0 ? left / right : 0.0;
        if (op == '%') left = right != 0 ? left % right : 0.0;
      } else {
        break;
      }
    }
    return left;
  }

  double _parseFactor() {
    if (_pos >= _tokens.length) return 0.0;
    final token = _tokens[_pos];
    if (token == '(') {
      _pos++; // consume '('
      final val = _parseExpression();
      if (_pos < _tokens.length && _tokens[_pos] == ')') _pos++; // consume ')'
      return val;
    } else if (token == '-') {
      _pos++;
      return -_parseFactor();
    } else if (token == '+') {
      _pos++;
      return _parseFactor();
    } else {
      _pos++;
      return double.tryParse(token) ?? 0.0;
    }
  }

  static List<String> _tokenize(String str) {
    final List<String> tokens = [];
    int i = 0;
    while (i < str.length) {
      final ch = str[i];
      if ('+-*/%()'.contains(ch)) {
        tokens.add(ch);
        i++;
      } else if (RegExp(r'[0-9.]').hasMatch(ch)) {
        int start = i;
        while (i < str.length && RegExp(r'[0-9.]').hasMatch(str[i])) {
          i++;
        }
        tokens.add(str.substring(start, i));
      } else {
        i++;
      }
    }
    return tokens;
  }
}
