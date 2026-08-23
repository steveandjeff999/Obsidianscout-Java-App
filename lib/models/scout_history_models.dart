/// Represents a single scouting record that was submitted, QR-generated,
/// or offline-cached on this device.
class ScoutHistoryEntry {
  final String id;

  /// 'match', 'pit', or 'qual'
  final String type;

  /// 'direct_upload', 'qr_generated', or 'offline_cached'
  final String action;

  final DateTime timestamp;
  final int teamNumber;
  final String eventKey;
  final String? matchKey;
  final int? matchNumber;
  final String? compLevel;

  /// 'synced', 'pending', or 'failed'
  String status;

  /// Full form data payload — same structure used for upload / QR generation
  final Map<String, dynamic> payload;

  ScoutHistoryEntry({
    required this.id,
    required this.type,
    required this.action,
    required this.timestamp,
    required this.teamNumber,
    required this.eventKey,
    this.matchKey,
    this.matchNumber,
    this.compLevel,
    required this.status,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        'teamNumber': teamNumber,
        'eventKey': eventKey,
        'matchKey': matchKey,
        'matchNumber': matchNumber,
        'compLevel': compLevel,
        'status': status,
        'payload': payload,
      };

  factory ScoutHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ScoutHistoryEntry(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'match',
      action: json['action']?.toString() ?? 'direct_upload',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      eventKey: json['eventKey']?.toString() ?? '',
      matchKey: json['matchKey']?.toString(),
      matchNumber: (json['matchNumber'] as num?)?.toInt(),
      compLevel: json['compLevel']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      payload: (json['payload'] is Map)
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : {},
    );
  }

  ScoutHistoryEntry copyWith({String? status}) {
    return ScoutHistoryEntry(
      id: id,
      type: type,
      action: action,
      timestamp: timestamp,
      teamNumber: teamNumber,
      eventKey: eventKey,
      matchKey: matchKey,
      matchNumber: matchNumber,
      compLevel: compLevel,
      status: status ?? this.status,
      payload: payload,
    );
  }

  /// Human-readable label for the team + match combination
  String get displayLabel {
    final teamStr = 'Team $teamNumber';
    if (matchKey != null && matchKey!.isNotEmpty) {
      return '$teamStr • $matchKey';
    }
    return teamStr;
  }
}
