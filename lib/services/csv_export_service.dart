import 'dart:convert';
import '../models/config_models.dart';

class CsvExportData {
  final String csvContent;
  final int rowCount;
  final int columnCount;
  final List<String> headers;
  final List<List<String>> sampleRows;
  final String suggestedFilename;

  const CsvExportData({
    required this.csvContent,
    required this.rowCount,
    required this.columnCount,
    required this.headers,
    required this.sampleRows,
    required this.suggestedFilename,
  });

  int get byteSize => utf8.encode(csvContent).length;

  String get formattedSize {
    final bytes = byteSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class CsvExportService {
  /// Format and escape a single cell value for CSV (RFC 4180 compliant)
  static String formatCell(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    if (value is num) return value.toString();
    if (value is List) {
      final joined = value.map((v) => v?.toString() ?? '').join('; ');
      return '"${joined.replaceAll('"', '""')}"';
    }
    if (value is Map) {
      final json = jsonEncode(value);
      return '"${json.replaceAll('"', '""')}"';
    }

    final str = value.toString();
    // If it contains comma, double quote, newline, or carriage return, enclose in quotes
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r') ||
        str.startsWith(' ') ||
        str.endsWith(' ')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// Extracts column field definitions ordered by config fields then any remaining dynamic keys
  static List<_CsvFieldCol> _resolveFieldColumns(
    List<Map<String, dynamic>> recordsData,
    ScoutingConfigModel? config,
  ) {
    final List<_CsvFieldCol> cols = [];
    final Set<String> seenKeys = {};

    if (config != null) {
      for (final f in config.fields) {
        if (f.type == 'section') continue;
        final phasePrefix = (f.phase != null && f.phase!.isNotEmpty)
            ? '[${f.phase![0].toUpperCase()}${f.phase!.substring(1)}] '
            : '';
        cols.add(_CsvFieldCol(
          key: f.id,
          headerName: '$phasePrefix${f.label.isNotEmpty ? f.label : f.id}',
        ));
        seenKeys.add(f.id);
      }
    }

    // Capture any extra keys from records not present in the config schema
    for (final data in recordsData) {
      for (final key in data.keys) {
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          cols.add(_CsvFieldCol(
            key: key,
            headerName: key,
          ));
        }
      }
    }

    return cols;
  }

  /// Exports match scouting records to structured CSV
  static CsvExportData exportMatchData({
    required List<dynamic> records,
    ScoutingConfigModel? config,
    String? eventKey,
  }) {
    final List<Map<String, dynamic>> allData = [];
    for (final r in records) {
      try {
        final data = r.data as Map<String, dynamic>?;
        if (data != null) allData.add(data);
      } catch (_) {}
    }

    final fieldCols = _resolveFieldColumns(allData, config);

    final List<String> headers = [
      'Record ID',
      'Team Number',
      'Event Key',
      'Match Number',
      'Scout Username',
      'Created At',
      'Has Discrepancy',
      ...fieldCols.map((c) => c.headerName),
    ];

    final StringBuffer buffer = StringBuffer();
    buffer.writeln(headers.map(formatCell).join(','));

    final List<List<String>> sampleRows = [];

    for (final r in records) {
      final id = r.id?.toString() ?? '';
      final team = r.targetTeamNumber?.toString() ?? '';
      final event = r.eventKey?.toString() ?? '';
      final match = r.matchNumber?.toString() ?? '';
      final scout = r.scoutUsername?.toString() ?? '';
      final createdAt = r.createdAt?.toString() ?? '';
      final discrepancy = r.hasDiscrepancy == true ? 'TRUE' : 'FALSE';

      final Map<String, dynamic> data = (r.data is Map<String, dynamic>)
          ? r.data as Map<String, dynamic>
          : <String, dynamic>{};

      final List<String> rowValues = [
        id,
        team,
        event,
        match,
        scout,
        createdAt,
        discrepancy,
        ...fieldCols.map((c) => data[c.key]?.toString() ?? ''),
      ];

      buffer.writeln(rowValues.map(formatCell).join(','));

      if (sampleRows.length < 5) {
        sampleRows.add(rowValues);
      }
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final eventPrefix = (eventKey != null && eventKey.isNotEmpty) ? '${eventKey}_' : '';
    final filename = 'obsidian_match_scouting_$eventPrefix$dateStr.csv';

    return CsvExportData(
      csvContent: buffer.toString(),
      rowCount: records.length,
      columnCount: headers.length,
      headers: headers,
      sampleRows: sampleRows,
      suggestedFilename: filename,
    );
  }

  /// Exports pit scouting coverage data to structured CSV
  static CsvExportData exportPitData({
    required List<dynamic> items,
    ScoutingConfigModel? config,
    String? eventKey,
  }) {
    final List<Map<String, dynamic>> allData = [];
    for (final item in items) {
      try {
        final data = item.pitData as Map<String, dynamic>?;
        if (data != null) allData.add(data);
      } catch (_) {}
    }

    final fieldCols = _resolveFieldColumns(allData, config);

    final List<String> headers = [
      'Team Number',
      'Team Nickname',
      'Pit Scouting Status',
      'Last Updated',
      'Scout Username',
      ...fieldCols.map((c) => c.headerName),
    ];

    final StringBuffer buffer = StringBuffer();
    buffer.writeln(headers.map(formatCell).join(','));

    final List<List<String>> sampleRows = [];

    for (final item in items) {
      final team = item.teamNumber?.toString() ?? '';
      final nickname = item.nickname?.toString() ?? '';
      final status = (item.hasPitData == true) ? 'Complete' : 'Missing';
      final lastUpdated = item.lastUpdated?.toString() ?? '';
      final scout = item.scoutUsername?.toString() ?? '';

      final Map<String, dynamic> data = (item.pitData is Map<String, dynamic>)
          ? item.pitData as Map<String, dynamic>
          : <String, dynamic>{};

      final List<String> rowValues = [
        team,
        nickname,
        status,
        lastUpdated,
        scout,
        ...fieldCols.map((c) => data[c.key]?.toString() ?? ''),
      ];

      buffer.writeln(rowValues.map(formatCell).join(','));

      if (sampleRows.length < 5) {
        sampleRows.add(rowValues);
      }
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final eventPrefix = (eventKey != null && eventKey.isNotEmpty) ? '${eventKey}_' : '';
    final filename = 'obsidian_pit_scouting_$eventPrefix$dateStr.csv';

    return CsvExportData(
      csvContent: buffer.toString(),
      rowCount: items.length,
      columnCount: headers.length,
      headers: headers,
      sampleRows: sampleRows,
      suggestedFilename: filename,
    );
  }

  /// Exports qualitative scouting records to structured CSV
  static CsvExportData exportQualData({
    required List<dynamic> records,
    ScoutingConfigModel? config,
    String? eventKey,
  }) {
    final List<Map<String, dynamic>> allData = [];
    for (final r in records) {
      try {
        final data = r.data as Map<String, dynamic>?;
        if (data != null) allData.add(data);
      } catch (_) {}
    }

    final fieldCols = _resolveFieldColumns(allData, config);

    final List<String> headers = [
      'Record ID',
      'Team Number',
      'Event Key',
      'Match Number',
      'Scout Username',
      'Created At',
      ...fieldCols.map((c) => c.headerName),
    ];

    final StringBuffer buffer = StringBuffer();
    buffer.writeln(headers.map(formatCell).join(','));

    final List<List<String>> sampleRows = [];

    for (final r in records) {
      final id = r.id?.toString() ?? '';
      final team = r.targetTeamNumber?.toString() ?? '';
      final event = r.eventKey?.toString() ?? '';
      final match = r.matchNumber?.toString() ?? '';
      final scout = r.scoutUsername?.toString() ?? '';
      final createdAt = r.createdAt?.toString() ?? '';

      final Map<String, dynamic> data = (r.data is Map<String, dynamic>)
          ? r.data as Map<String, dynamic>
          : <String, dynamic>{};

      final List<String> rowValues = [
        id,
        team,
        event,
        match,
        scout,
        createdAt,
        ...fieldCols.map((c) => data[c.key]?.toString() ?? ''),
      ];

      buffer.writeln(rowValues.map(formatCell).join(','));

      if (sampleRows.length < 5) {
        sampleRows.add(rowValues);
      }
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final eventPrefix = (eventKey != null && eventKey.isNotEmpty) ? '${eventKey}_' : '';
    final filename = 'obsidian_qualitative_scouting_$eventPrefix$dateStr.csv';

    return CsvExportData(
      csvContent: buffer.toString(),
      rowCount: records.length,
      columnCount: headers.length,
      headers: headers,
      sampleRows: sampleRows,
      suggestedFilename: filename,
    );
  }

  /// Exports unified scouting entries (All Data Screen) to structured CSV
  static CsvExportData exportUnifiedData({
    required List<dynamic> entries,
    ScoutingConfigModel? matchConfig,
    ScoutingConfigModel? pitConfig,
    ScoutingConfigModel? qualConfig,
    String? eventKey,
  }) {
    final List<Map<String, dynamic>> allData = [];
    for (final e in entries) {
      try {
        final data = e.data as Map<String, dynamic>?;
        if (data != null) allData.add(data);
      } catch (_) {}
    }

    // Merge configs
    final List<_CsvFieldCol> fieldCols = [];
    final Set<String> seenKeys = {};

    void colsAdd(String id, String label) {
      fieldCols.add(_CsvFieldCol(key: id, headerName: label));
    }

    void addFromConfig(ScoutingConfigModel? cfg, String prefix) {
      if (cfg == null) return;
      for (final f in cfg.fields) {
        if (f.type == 'section') continue;
        if (!seenKeys.contains(f.id)) {
          seenKeys.add(f.id);
          colsAdd(f.id, '[$prefix] ${f.label.isNotEmpty ? f.label : f.id}');
        }
      }
    }

    addFromConfig(matchConfig, 'Match');
    addFromConfig(pitConfig, 'Pit');
    addFromConfig(qualConfig, 'Qual');

    // Add extra keys
    for (final data in allData) {
      for (final key in data.keys) {
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          colsAdd(key, key);
        }
      }
    }

    final List<String> headers = [
      'Entry ID',
      'Scouting Type',
      'Team Number',
      'Event Key',
      'Match Number',
      'Scout Username',
      'Created At',
      'Has Discrepancy',
      ...fieldCols.map((c) => c.headerName),
    ];

    final StringBuffer buffer = StringBuffer();
    buffer.writeln(headers.map(formatCell).join(','));

    final List<List<String>> sampleRows = [];

    for (final e in entries) {
      final id = e.id?.toString() ?? '';
      final type = e.type?.toString() ?? '';
      final team = e.targetTeamNumber?.toString() ?? '';
      final event = e.eventKey?.toString() ?? '';
      final match = e.matchNumber?.toString() ?? '';
      final scout = e.scoutUsername?.toString() ?? '';
      final createdAt = e.createdAt?.toString() ?? '';
      final discrepancy = e.hasDiscrepancy == true ? 'TRUE' : 'FALSE';

      final Map<String, dynamic> data = (e.data is Map<String, dynamic>)
          ? e.data as Map<String, dynamic>
          : <String, dynamic>{};

      final List<String> rowValues = [
        id,
        type,
        team,
        event,
        match,
        scout,
        createdAt,
        discrepancy,
        ...fieldCols.map((c) => data[c.key]?.toString() ?? ''),
      ];

      buffer.writeln(rowValues.map(formatCell).join(','));

      if (sampleRows.length < 5) {
        sampleRows.add(rowValues);
      }
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final eventPrefix = (eventKey != null && eventKey.isNotEmpty) ? '${eventKey}_' : '';
    final filename = 'obsidian_all_scouting_$eventPrefix$dateStr.csv';

    return CsvExportData(
      csvContent: buffer.toString(),
      rowCount: entries.length,
      columnCount: headers.length,
      headers: headers,
      sampleRows: sampleRows,
      suggestedFilename: filename,
    );
  }
}

class _CsvFieldCol {
  final String key;
  final String headerName;

  _CsvFieldCol({required this.key, required this.headerName});
}
