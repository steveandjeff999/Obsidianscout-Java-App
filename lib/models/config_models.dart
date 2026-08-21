class ScoutingFieldModel {
  final String id;
  final String label;
  final String? description;
  final String type; // e.g. "counter", "number", "slider", "range", "toggle", "boolean", "select", "radio", "multiselect", "rating", "text", "textarea", "section", "checkbox"
  final bool required;
  final String? phase; // e.g. "auto", "teleop", "endgame"
  final String? placeholder;
  final dynamic defaultValue;
  final List<ScoutingOptionModel> options;
  final int? min;
  final int? max;
  final int? step;
  final int? doubleStep;
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
    this.doubleStep,
    this.pointsPer,
  });

  ScoutingFieldModel copyWith({
    String? id,
    String? label,
    String? description,
    String? type,
    bool? required,
    String? phase,
    String? placeholder,
    dynamic defaultValue,
    List<ScoutingOptionModel>? options,
    int? min,
    int? max,
    int? step,
    int? doubleStep,
    double? pointsPer,
    bool clearMin = false,
    bool clearMax = false,
    bool clearStep = false,
    bool clearDoubleStep = false,
    bool clearPointsPer = false,
    bool clearPhase = false,
  }) {
    return ScoutingFieldModel(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      type: type ?? this.type,
      required: required ?? this.required,
      phase: clearPhase ? null : (phase ?? this.phase),
      placeholder: placeholder ?? this.placeholder,
      defaultValue: defaultValue ?? this.defaultValue,
      options: options ?? this.options,
      min: clearMin ? null : (min ?? this.min),
      max: clearMax ? null : (max ?? this.max),
      step: clearStep ? null : (step ?? this.step),
      doubleStep: clearDoubleStep ? null : (doubleStep ?? this.doubleStep),
      pointsPer: clearPointsPer ? null : (pointsPer ?? this.pointsPer),
    );
  }

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

    final parsedType = json['type']?.toString() ?? json['fieldType']?.toString() ?? 'text';
    return ScoutingFieldModel(
      id: json['id']?.toString() ?? json['key']?.toString() ?? '',
      label: parsedLabel,
      description: parsedDesc,
      type: parsedType,
      required: parsedType == 'text' ? false : (json['required'] == true),
      phase: json['phase']?.toString(),
      placeholder: json['placeholder']?.toString() ?? json['hint']?.toString(),
      defaultValue: json['defaultValue'] ?? json['default'],
      options: parsedOptions,
      min: (json['min'] as num?)?.toInt(),
      max: (json['max'] as num?)?.toInt(),
      step: (json['step'] as num?)?.toInt(),
      doubleStep: (json['doubleStep'] as num?)?.toInt() ?? (json['double_step'] as num?)?.toInt(),
      pointsPer: (json['pointsPer'] as num?)?.toDouble() ?? (json['points_per'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'label': label,
      'type': type,
    };

    if (type != 'section') {
      if (description != null && description!.isNotEmpty) {
        data['description'] = description;
      }
      if (type != 'text' && required) {
        data['required'] = true;
      }
      if (phase != null && phase!.isNotEmpty) {
        data['phase'] = phase;
      }
      if (placeholder != null && placeholder!.isNotEmpty) {
        data['placeholder'] = placeholder;
      }
      if (defaultValue != null) {
        data['defaultValue'] = defaultValue;
      }

      if (type == 'select' || type == 'radio' || type == 'multiselect') {
        data['options'] = options.map((o) => o.toJson()).toList();
      }

      if (min != null) data['min'] = min;
      if (max != null) data['max'] = max;
      if (step != null) data['step'] = step;
      if (type == 'counter' && doubleStep != null) {
        data['doubleStep'] = doubleStep;
      }
      if (pointsPer != null) {
        data['pointsPer'] = pointsPer;
      }
    }

    return data;
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

  ScoutingOptionModel copyWith({
    String? label,
    String? value,
    double? points,
  }) {
    return ScoutingOptionModel(
      label: label ?? this.label,
      value: value ?? this.value,
      points: points ?? this.points,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
      'points': points,
    };
  }
}

class ScoutingConfigModel {
  final int version;
  final String title;
  final List<ScoutingFieldModel> fields;
  final List<AnalyticsWidgetModel> analytics;
  final bool enableRobotRoleCollection;
  final String? tbaKey;
  final String? firstUsername;
  final String? firstKey;
  final String? eventCode;

  ScoutingConfigModel({
    this.version = 1,
    this.title = 'ObsidianScout',
    this.fields = const [],
    this.analytics = const [],
    this.enableRobotRoleCollection = false,
    this.tbaKey,
    this.firstUsername,
    this.firstKey,
    this.eventCode,
  });

  ScoutingConfigModel copyWith({
    int? version,
    String? title,
    List<ScoutingFieldModel>? fields,
    List<AnalyticsWidgetModel>? analytics,
    bool? enableRobotRoleCollection,
    String? tbaKey,
    String? firstUsername,
    String? firstKey,
    String? eventCode,
  }) {
    return ScoutingConfigModel(
      version: version ?? this.version,
      title: title ?? this.title,
      fields: fields ?? this.fields,
      analytics: analytics ?? this.analytics,
      enableRobotRoleCollection: enableRobotRoleCollection ?? this.enableRobotRoleCollection,
      tbaKey: tbaKey ?? this.tbaKey,
      firstUsername: firstUsername ?? this.firstUsername,
      firstKey: firstKey ?? this.firstKey,
      eventCode: eventCode ?? this.eventCode,
    );
  }

  factory ScoutingConfigModel.fromJson(Map<String, dynamic> json) {
    List<ScoutingFieldModel> parsedFields = [];
    if (json['fields'] is List) {
      parsedFields = (json['fields'] as List)
          .map((f) => ScoutingFieldModel.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    List<AnalyticsWidgetModel> parsedAnalytics = [];
    if (json['analytics'] is List) {
      parsedAnalytics = (json['analytics'] as List)
          .map((a) => AnalyticsWidgetModel.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    return ScoutingConfigModel(
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? 'ObsidianScout',
      fields: parsedFields,
      analytics: parsedAnalytics,
      enableRobotRoleCollection: json['enable_robot_role_collection'] == true || json['enableRobotRoleCollection'] == true,
      tbaKey: json['tba_key']?.toString(),
      firstUsername: json['first_username']?.toString(),
      firstKey: json['first_key']?.toString(),
      eventCode: json['event_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'version': version,
      'title': title,
      'fields': fields.map((f) => f.toJson()).toList(),
    };

    if (analytics.isNotEmpty) {
      data['analytics'] = analytics.map((a) => {
        'id': a.id,
        'title': a.title,
        'type': a.type,
      }).toList();
    }

    if (enableRobotRoleCollection) {
      data['enable_robot_role_collection'] = true;
    }

    if (tbaKey != null) data['tba_key'] = tbaKey;
    if (firstUsername != null) data['first_username'] = firstUsername;
    if (firstKey != null) data['first_key'] = firstKey;
    if (eventCode != null) data['event_code'] = eventCode;

    return data;
  }
}

class DefaultConfigPresetModel {
  final String? id;
  final String name;
  final String program;
  final String configType;
  final String configJson;
  final bool isDefault;
  final String? updatedAt;

  DefaultConfigPresetModel({
    this.id,
    required this.name,
    required this.program,
    required this.configType,
    required this.configJson,
    this.isDefault = false,
    this.updatedAt,
  });

  factory DefaultConfigPresetModel.fromJson(Map<String, dynamic> json) {
    return DefaultConfigPresetModel(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      program: json['program']?.toString() ?? 'FRC',
      configType: json['configType']?.toString() ?? json['config_type']?.toString() ?? 'match',
      configJson: json['configJson']?.toString() ?? json['config_json']?.toString() ?? '{}',
      isDefault: json['isDefault'] == true || json['is_default'] == true,
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'program': program,
      'configType': configType,
      'configJson': configJson,
      'isDefault': isDefault,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
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

const List<String> defaultScoutPages = [
  'dashboard', 'chat', 'scout', 'pit-scout', 'qual-scout', 'qr-scanner', 'contact',
];

const List<String> defaultAnalyticsPages = [
  'dashboard', 'events', 'scout', 'pit-scout', 'qual-scout', 'qr-scanner',
  'all-data', 'match-data', 'qual-data', 'pit-data', 'analytics', 'graphs',
  'teams', 'rankings', 'qual-rankings', 'matches', 'predictor',
  'event-predictor', 'alliances', 'alliance-selection', 'chat', 'backup', 'docs', 'contact',
];

const List<String> defaultAdminPages = [
  'dashboard', 'admin-settings', 'default-configs', 'config-editor', 'users', 'banners', 'scout', 'pit-scout', 'qual-scout', 'qr-scanner',
  'all-data', 'match-data', 'qual-data', 'pit-data', 'analytics', 'graphs',
  'events', 'teams', 'rankings', 'qual-rankings', 'matches', 'predictor',
  'event-predictor', 'alliances', 'alliance-selection', 'chat', 'backup', 'docs', 'contact',
];

const List<String> superAdminOnlyPages = [
  'cluster-management', 'fcm-settings', 'migration', 'backup', 'logs',
];

const List<String> adminOnlyBasePages = [
  'users', 'banners', 'admin-settings', 'default-configs', 'events', 'config-editor',
];

const List<String> bypassPages = [
  'settings', 'login', 'index', 'dashboard', 'theme-editor', 'team',
  'cache-manager', 'prescout', 'prescout-scout', 'prescout-pit',
  'prescout-qual', 'reset-password', 'docs', 'contact', 'config-migration', 'schema-history',
];

class UserModel {
  final String id;
  final String username;
  final int teamNumber;
  final String program;
  final String role; // "SUPERADMIN", "ADMIN", "ANALYTICS", "SCOUT"
  final String? email;
  final String? profilePicture;
  final String? notificationPreference;

  UserModel({
    required this.id,
    required this.username,
    required this.teamNumber,
    this.program = 'FRC',
    this.role = 'SCOUT',
    this.email,
    this.profilePicture,
    this.notificationPreference,
  });

  bool get isSuperAdmin => role.toUpperCase() == 'SUPERADMIN';
  bool get isAdmin => isSuperAdmin || role.toUpperCase() == 'ADMIN';
  bool get canAccessAnalytics => isAdmin || role.toUpperCase() == 'ANALYTICS';

  String get roleDisplayLabel {
    final r = role.toUpperCase();
    if (r == 'SUPERADMIN') return 'Site Admin';
    if (r.isEmpty) return 'Scout';
    return r[0] + r.substring(1).toLowerCase();
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      role: json['role']?.toString().toUpperCase() ?? 'SCOUT',
      email: json['email']?.toString(),
      profilePicture: json['profilePicture']?.toString(),
      notificationPreference: json['notificationPreference']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'teamNumber': teamNumber,
      'program': program,
      'role': role,
      'email': email,
      'profilePicture': profilePicture,
      'notificationPreference': notificationPreference,
    };
  }
}

class AppSettingsModel {
  final int year;
  final String eventCode;
  final String eventKey;
  final String timezone;
  final String preferredSource;
  final bool chatEnabled;
  final List<String> scoutPages;
  final List<String> analyticsPages;
  final List<String> adminPages;
  final String program;
  final String serverVersion;

  AppSettingsModel({
    this.year = 2026,
    this.eventCode = '',
    this.eventKey = '',
    this.timezone = 'America/New_York',
    this.preferredSource = 'tba',
    this.chatEnabled = true,
    this.scoutPages = defaultScoutPages,
    this.analyticsPages = defaultAnalyticsPages,
    this.adminPages = defaultAdminPages,
    this.program = 'FRC',
    this.serverVersion = '',
  });

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    final settingsMap = json['settings'] is Map ? (json['settings'] as Map<String, dynamic>) : json;

    List<String> parseList(dynamic raw, List<String> fallback) {
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return fallback;
    }

    return AppSettingsModel(
      year: (settingsMap['year'] as num?)?.toInt() ?? DateTime.now().year,
      eventCode: settingsMap['eventCode']?.toString() ?? '',
      eventKey: settingsMap['eventKey']?.toString() ?? '',
      timezone: settingsMap['timezone']?.toString() ?? 'America/New_York',
      preferredSource: settingsMap['preferredSource']?.toString() ?? 'tba',
      chatEnabled: settingsMap['chatEnabled'] != false,
      scoutPages: parseList(settingsMap['scoutPages'], defaultScoutPages),
      analyticsPages: parseList(settingsMap['analyticsPages'], defaultAnalyticsPages),
      adminPages: parseList(settingsMap['adminPages'], defaultAdminPages),
      program: settingsMap['program']?.toString() ?? json['program']?.toString() ?? 'FRC',
      serverVersion: json['version']?.toString() ?? json['serverVersion']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'eventCode': eventCode,
      'eventKey': eventKey,
      'timezone': timezone,
      'preferredSource': preferredSource,
      'chatEnabled': chatEnabled,
      'scoutPages': scoutPages,
      'analyticsPages': analyticsPages,
      'adminPages': adminPages,
      'program': program,
      'serverVersion': serverVersion,
    };
  }
}

class ConfigRevisionModel {
  final String id;
  final int teamNumber;
  final String program;
  final String configKind;
  final int version;
  final String title;
  final String? configJson;
  final String? changeSummary;
  final String? savedByUsername;
  final int fieldCount;
  final String? createdAt;

  ConfigRevisionModel({
    required this.id,
    required this.teamNumber,
    required this.program,
    required this.configKind,
    required this.version,
    required this.title,
    this.configJson,
    this.changeSummary,
    this.savedByUsername,
    required this.fieldCount,
    this.createdAt,
  });

  factory ConfigRevisionModel.fromJson(Map<String, dynamic> json) {
    return ConfigRevisionModel(
      id: json['id']?.toString() ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      configKind: json['configKind']?.toString() ?? 'game',
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? 'Scouting Form',
      configJson: json['configJson']?.toString(),
      changeSummary: json['changeSummary']?.toString(),
      savedByUsername: json['savedByUsername']?.toString(),
      fieldCount: (json['fieldCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'teamNumber': teamNumber,
      'program': program,
      'configKind': configKind,
      'version': version,
      'title': title,
      if (configJson != null) 'configJson': configJson,
      if (changeSummary != null) 'changeSummary': changeSummary,
      if (savedByUsername != null) 'savedByUsername': savedByUsername,
      'fieldCount': fieldCount,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}

class ConfigSchemaStatusModel {
  final String configKind;
  final int entryCount;
  final int configVersion;
  final List<ScoutingFieldModel> configFields;
  final List<String> dataKeys;
  final List<String> unmatchedDataKeys;
  final List<String> newConfigKeys;

  ConfigSchemaStatusModel({
    required this.configKind,
    required this.entryCount,
    required this.configVersion,
    required this.configFields,
    required this.dataKeys,
    required this.unmatchedDataKeys,
    required this.newConfigKeys,
  });

  factory ConfigSchemaStatusModel.fromJson(Map<String, dynamic> json) {
    List<ScoutingFieldModel> fields = [];
    if (json['configFields'] is List) {
      fields = (json['configFields'] as List)
          .map((f) => ScoutingFieldModel.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    List<String> parseStrList(dynamic val) {
      if (val is List) return val.map((e) => e.toString()).toList();
      return [];
    }

    return ConfigSchemaStatusModel(
      configKind: json['configKind']?.toString() ?? 'game',
      entryCount: (json['entryCount'] as num?)?.toInt() ?? 0,
      configVersion: (json['configVersion'] as num?)?.toInt() ?? 1,
      configFields: fields,
      dataKeys: parseStrList(json['dataKeys']),
      unmatchedDataKeys: parseStrList(json['unmatchedDataKeys']),
      newConfigKeys: parseStrList(json['newConfigKeys']),
    );
  }
}

class ConfigMigrationMappingModel {
  final String oldKey;
  final String? newKey;
  final String action; // "map", "keep", "delete"

  ConfigMigrationMappingModel({
    required this.oldKey,
    this.newKey,
    this.action = 'map',
  });

  Map<String, dynamic> toJson() {
    return {
      'oldKey': oldKey,
      'newKey': newKey,
      'action': action,
    };
  }
}

class ConfigMigrationSampleModel {
  final String id;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;

  ConfigMigrationSampleModel({
    required this.id,
    required this.before,
    required this.after,
  });

  factory ConfigMigrationSampleModel.fromJson(Map<String, dynamic> json) {
    return ConfigMigrationSampleModel(
      id: json['id']?.toString() ?? '',
      before: json['before'] is Map ? Map<String, dynamic>.from(json['before'] as Map) : {},
      after: json['after'] is Map ? Map<String, dynamic>.from(json['after'] as Map) : {},
    );
  }
}

class ConfigMigrationPreviewModel {
  final String configKind;
  final int totalEntries;
  final List<ConfigMigrationSampleModel> samples;

  ConfigMigrationPreviewModel({
    required this.configKind,
    required this.totalEntries,
    required this.samples,
  });

  factory ConfigMigrationPreviewModel.fromJson(Map<String, dynamic> json) {
    List<ConfigMigrationSampleModel> sampleList = [];
    if (json['samples'] is List) {
      sampleList = (json['samples'] as List)
          .map((s) => ConfigMigrationSampleModel.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return ConfigMigrationPreviewModel(
      configKind: json['configKind']?.toString() ?? 'game',
      totalEntries: (json['totalEntries'] as num?)?.toInt() ?? 0,
      samples: sampleList,
    );
  }
}

class ConfigMigrationResultModel {
  final bool success;
  final String configKind;
  final int migratedCount;
  final List<String> updatedKeys;
  final List<String> deletedKeys;
  final List<String> backfilledKeys;

  ConfigMigrationResultModel({
    required this.success,
    required this.configKind,
    required this.migratedCount,
    this.updatedKeys = const [],
    this.deletedKeys = const [],
    this.backfilledKeys = const [],
  });

  factory ConfigMigrationResultModel.fromJson(Map<String, dynamic> json) {
    List<String> parseStrList(dynamic val) {
      if (val is List) return val.map((e) => e.toString()).toList();
      return [];
    }

    return ConfigMigrationResultModel(
      success: json['success'] == true,
      configKind: json['configKind']?.toString() ?? 'game',
      migratedCount: (json['migratedCount'] as num?)?.toInt() ?? 0,
      updatedKeys: parseStrList(json['updatedKeys']),
      deletedKeys: parseStrList(json['deletedKeys']),
      backfilledKeys: parseStrList(json['backfilledKeys']),
    );
  }
}

