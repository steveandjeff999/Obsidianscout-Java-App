import 'dart:convert';
import '../data/local_store.dart';
import '../models/config_models.dart';

/// Represents a preserved in-progress scouting form draft saved to local storage.
class ScoutingDraft {
  final String formType; // 'match', 'pit', etc.
  final int? teamNumber;
  final String? matchKey;
  final int? matchNumber;
  final String? eventKey;
  final Map<String, dynamic> data;
  final DateTime savedAt;

  const ScoutingDraft({
    required this.formType,
    required this.data,
    required this.savedAt,
    this.teamNumber,
    this.matchKey,
    this.matchNumber,
    this.eventKey,
  });

  Map<String, dynamic> toJson() => {
        'formType': formType,
        'teamNumber': teamNumber,
        'matchKey': matchKey,
        'matchNumber': matchNumber,
        'eventKey': eventKey,
        'data': data,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory ScoutingDraft.fromJson(Map<String, dynamic> json) => ScoutingDraft(
        formType: json['formType']?.toString() ?? 'match',
        teamNumber: json['teamNumber'] is num ? (json['teamNumber'] as num).toInt() : null,
        matchKey: json['matchKey']?.toString(),
        matchNumber: json['matchNumber'] is num ? (json['matchNumber'] as num).toInt() : null,
        eventKey: json['eventKey']?.toString(),
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : <String, dynamic>{},
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['savedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );

  String ageDescription() {
    final diff = DateTime.now().difference(savedAt);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String contextDescription() {
    final parts = <String>[];
    if (matchKey != null && matchKey!.isNotEmpty) {
      final keyShort = matchKey!.split('_').last.toUpperCase();
      parts.add(keyShort);
    } else if (matchNumber != null) {
      parts.add('Match $matchNumber');
    }
    if (teamNumber != null) {
      parts.add('Team $teamNumber');
    }
    return parts.isEmpty ? 'Untitled form' : parts.join(' · ');
  }
}

/// Service managing on-device persistence for in-progress scouting drafts.
/// Backed by Drift SQLite (via [LocalStore]) with SharedPreferences fallback.
class ScoutingDraftService {
  ScoutingDraftService._();

  static String draftKey(String formType) => 'scouting_draft_$formType';

  /// Evaluates whether the given form payload contains user modifications
  /// beyond default/blank values.
  static bool hasMeaningfulData(Map<String, dynamic> data, [ScoutingConfigModel? config]) {
    if (data.isEmpty) return false;

    // Check against config default values if available
    if (config != null && config.fields.isNotEmpty) {
      final fieldMap = {for (final f in config.fields) f.id: f};
      for (final entry in data.entries) {
        if (_isIgnoredKey(entry.key)) continue;
        final field = fieldMap[entry.key];
        final val = entry.value;

        if (field != null) {
          final t = field.type.toLowerCase();
          if (t == 'section' || t == 'header' || t == 'divider' || t == 'static_text') continue;

          final defVal = field.defaultValue;
          if (t == 'counter' || t == 'number' || t == 'stepper' || t == 'slider' || t == 'range') {
            final expected = (defVal is num ? defVal.toInt() : (field.min ?? 0));
            final actual = val is num ? val.toInt() : 0;
            if (actual != expected) return true;
          } else if (t == 'rating' || t == 'stars') {
            final expected = (defVal is num ? defVal.toInt() : (field.min ?? 1));
            final actual = val is num ? val.toInt() : 1;
            if (actual != expected) return true;
          } else if (t == 'boolean' || t == 'toggle' || t == 'checkbox') {
            final expected = defVal == true || defVal == 'true';
            final actual = val == true || val == 'true';
            if (actual != expected) return true;
          } else if (t == 'select' || t == 'dropdown' || t == 'radio' || t == 'choice') {
            final expected = defVal?.toString() ?? (field.options.isNotEmpty ? field.options.first.value : '');
            final actual = val?.toString() ?? '';
            if (actual.isNotEmpty && actual != expected) return true;
          } else if (t == 'multiselect' || t == 'multi-select') {
            final actualList = val is List ? val : const [];
            if (actualList.isNotEmpty) return true;
          } else {
            final actual = val?.toString() ?? '';
            if (actual.trim().isNotEmpty && actual != (defVal?.toString() ?? '')) return true;
          }
        } else {
          // Field not in config schema: test for generic non-empty
          if (_hasGenericValue(val)) return true;
        }
      }
      return false;
    }

    // Generic inspection when config is unavailable
    for (final entry in data.entries) {
      if (_isIgnoredKey(entry.key)) continue;
      if (_hasGenericValue(entry.value)) return true;
    }
    return false;
  }

  static bool _isIgnoredKey(String key) {
    return key.startsWith('_') ||
        key == 'eventKey' ||
        key == 'matchKey' ||
        key == 'matchNumber' ||
        key == 'targetTeamNumber' ||
        key == 'teamNumber' ||
        key == 'compLevel';
  }

  static bool _hasGenericValue(dynamic val) {
    if (val == null) return false;
    if (val is num && val != 0) return true;
    if (val is String && val.trim().isNotEmpty) return true;
    if (val is bool && val == true) return true;
    if (val is List && val.isNotEmpty) return true;
    return false;
  }

  /// Saves or removes the draft based on whether meaningful data exists.
  static Future<void> saveDraft({
    required String formType,
    required Map<String, dynamic> data,
    int? teamNumber,
    String? matchKey,
    int? matchNumber,
    String? eventKey,
    ScoutingConfigModel? config,
  }) async {
    final hasData = hasMeaningfulData(data, config);
    if (!hasData && teamNumber == null && matchKey == null) {
      await clearDraft(formType);
      return;
    }

    // Sanitize data map for JSON safety
    final sanitizedData = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.key.startsWith('_')) continue;
      sanitizedData[entry.key] = entry.value;
    }

    final draft = ScoutingDraft(
      formType: formType,
      data: sanitizedData,
      savedAt: DateTime.now(),
      teamNumber: teamNumber,
      matchKey: matchKey,
      matchNumber: matchNumber,
      eventKey: eventKey,
    );

    try {
      await LocalStore.instance.setString(draftKey(formType), jsonEncode(draft.toJson()));
    } catch (_) {}
  }

  /// Loads the active draft for [formType], or returns null if none exists.
  static Future<ScoutingDraft?> loadDraft(String formType) async {
    try {
      final raw = await LocalStore.instance.getString(draftKey(formType));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ScoutingDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Removes the stored draft for [formType].
  static Future<void> clearDraft(String formType) async {
    try {
      await LocalStore.instance.remove(draftKey(formType));
    } catch (_) {}
  }
}
