class ScoutingFieldModel {
  final String id;
  final String label;
  final String? description;
  final String type; // e.g. "counter", "number", "slider", "range", "toggle", "boolean", "select", "radio", "multiselect", "rating", "text", "textarea", "section"
  final bool required;
  final String? phase; // e.g. "auto", "teleop", "endgame"
  final String? placeholder;
  final dynamic defaultValue;
  final List<ScoutingOptionModel> options;
  final int? min;
  final int? max;
  final int? step;
  final double? pointsPer;

  ScoutingFieldModel({
    required this.id,
    required this.label,
    this.description,
    required this.type,
    this.required = false,
    this.phase,
    this.placeholder,
    this.defaultValue,
    this.options = const [],
    this.min,
    this.max,
    this.step,
    this.pointsPer,
  });

  factory ScoutingFieldModel.fromJson(Map<String, dynamic> json) {
    // Parse label which may be a raw String or localized JsonObject e.g. {"en": "Label"}
    String parsedLabel = "";
    if (json['label'] is Map) {
      parsedLabel = (json['label'] as Map)['en']?.toString() ?? json['id'] ?? '';
    } else {
      parsedLabel = json['label']?.toString() ?? json['name']?.toString() ?? json['title']?.toString() ?? json['id'] ?? '';
    }

    String? parsedDesc;
    if (json['description'] is Map) {
      parsedDesc = (json['description'] as Map)['en']?.toString();
    } else {
      parsedDesc = json['description']?.toString() ?? json['helpText']?.toString() ?? json['subtitle']?.toString();
    }

    List<ScoutingOptionModel> parsedOptions = [];
    if (json['options'] is List) {
      parsedOptions = (json['options'] as List).map((opt) {
        if (opt is Map<String, dynamic>) {
          return ScoutingOptionModel.fromJson(opt);
        } else if (opt is Map) {
          return ScoutingOptionModel.fromJson(Map<String, dynamic>.from(opt));
        } else {
          return ScoutingOptionModel(label: opt.toString(), value: opt.toString());
        }
      }).toList();
    }

    return ScoutingFieldModel(
      id: json['id']?.toString() ?? json['key']?.toString() ?? '',
      label: parsedLabel,
      description: parsedDesc,
      type: json['type']?.toString() ?? json['fieldType']?.toString() ?? 'text',
      required: json['required'] == true,
      phase: json['phase']?.toString(),
      placeholder: json['placeholder']?.toString() ?? json['hint']?.toString(),
      defaultValue: json['defaultValue'] ?? json['default'],
      options: parsedOptions,
      min: (json['min'] as num?)?.toInt(),
      max: (json['max'] as num?)?.toInt(),
      step: (json['step'] as num?)?.toInt(),
      pointsPer: (json['pointsPer'] as num?)?.toDouble(),
    );
  }
}

class ScoutingOptionModel {
  final String label;
  final String value;
  final double points;

  ScoutingOptionModel({
    required this.label,
    required this.value,
    this.points = 0.0,
  });

  factory ScoutingOptionModel.fromJson(Map<String, dynamic> json) {
    String parsedLabel = "";
    if (json['label'] is Map) {
      parsedLabel = (json['label'] as Map)['en']?.toString() ?? json['value']?.toString() ?? '';
    } else {
      parsedLabel = json['label']?.toString() ?? json['value']?.toString() ?? '';
    }

    return ScoutingOptionModel(
      label: parsedLabel,
      value: json['value']?.toString() ?? '',
      points: (json['points'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ScoutingConfigModel {
  final int version;
  final String title;
  final List<ScoutingFieldModel> fields;

  ScoutingConfigModel({
    this.version = 1,
    this.title = 'ObsidianScout',
    this.fields = const [],
  });

  factory ScoutingConfigModel.fromJson(Map<String, dynamic> json) {
    List<ScoutingFieldModel> parsedFields = [];
    if (json['fields'] is List) {
      parsedFields = (json['fields'] as List)
          .map((f) => ScoutingFieldModel.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    return ScoutingConfigModel(
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? 'ObsidianScout',
      fields: parsedFields,
    );
  }
}

class AnalyticsWidgetModel {
  final String id;
  final String title;
  final String type; // "count", "avg", "sum", "bar", "score_total", "score_avg"
  final double? value;
  final List<AnalyticsSeriesPointModel> series;

  AnalyticsWidgetModel({
    required this.id,
    required this.title,
    required this.type,
    this.value,
    this.series = const [],
  });

  factory AnalyticsWidgetModel.fromJson(Map<String, dynamic> json) {
    List<AnalyticsSeriesPointModel> parsedSeries = [];
    if (json['series'] is List) {
      parsedSeries = (json['series'] as List)
          .map((s) => AnalyticsSeriesPointModel.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return AnalyticsWidgetModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? 'metric',
      value: (json['value'] as num?)?.toDouble(),
      series: parsedSeries,
    );
  }
}

class AnalyticsSeriesPointModel {
  final String label;
  final double value;

  AnalyticsSeriesPointModel({
    required this.label,
    required this.value,
  });

  factory AnalyticsSeriesPointModel.fromJson(Map<String, dynamic> json) {
    return AnalyticsSeriesPointModel(
      label: json['label']?.toString() ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
