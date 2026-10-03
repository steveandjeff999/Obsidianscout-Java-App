import 'dart:convert';

class CreateShareRequest {
  final String title;
  final String? description;
  final String resourceType; // graph, predictor, event_predictor, all_data, qual_data, pit_data, match_data, custom_analytics, match_planning
  final String? targetEventKey;
  final String shareMode; // live_query, frozen_snapshot
  final Map<String, dynamic> queryConfig;
  final Map<String, dynamic>? snapshotData;
  final String accessScope; // public, team, alliance, pin
  final String? allowedTeams;
  final String? pin;
  final bool redactPrivateNotes;
  final bool redactScoutNames;
  final DateTime? expiresAt;

  CreateShareRequest({
    required this.title,
    this.description,
    required this.resourceType,
    this.targetEventKey,
    this.shareMode = 'live_query',
    this.queryConfig = const {},
    this.snapshotData,
    this.accessScope = 'public',
    this.allowedTeams,
    this.pin,
    this.redactPrivateNotes = true,
    this.redactScoutNames = false,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'resourceType': resourceType,
    'targetEventKey': targetEventKey,
    'shareMode': shareMode,
    'queryConfigJson': jsonEncode(queryConfig),
    'snapshotDataJson': snapshotData != null ? jsonEncode(snapshotData) : null,
    'accessScope': accessScope,
    'allowedTeams': allowedTeams,
    'pin': pin,
    'redactPrivateNotes': redactPrivateNotes,
    'redactScoutNames': redactScoutNames,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };
}

class ShareLinkModel {
  final String id;
  final String token;
  final int ownerTeamNumber;
  final String program;
  final String createdByUsername;
  final String title;
  final String? description;
  final String resourceType;
  final String? targetEventKey;
  final String shareMode;
  final String queryConfigJson;
  final String accessScope;
  final String? allowedTeams;
  final bool hasPin;
  final bool redactPrivateNotes;
  final bool redactScoutNames;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isExpired;
  final bool isRevoked;
  final DateTime? revokedAt;
  final String? revokedByUsername;
  final int viewCount;
  final DateTime? lastAccessedAt;
  final String? shareUrl;

  ShareLinkModel({
    required this.id,
    required this.token,
    required this.ownerTeamNumber,
    required this.program,
    required this.createdByUsername,
    required this.title,
    this.description,
    required this.resourceType,
    this.targetEventKey,
    required this.shareMode,
    required this.queryConfigJson,
    required this.accessScope,
    this.allowedTeams,
    required this.hasPin,
    required this.redactPrivateNotes,
    required this.redactScoutNames,
    required this.createdAt,
    this.expiresAt,
    required this.isExpired,
    required this.isRevoked,
    this.revokedAt,
    this.revokedByUsername,
    required this.viewCount,
    this.lastAccessedAt,
    this.shareUrl,
  });

  factory ShareLinkModel.fromJson(Map<String, dynamic> json) {
    return ShareLinkModel(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      ownerTeamNumber: json['ownerTeamNumber'] is int ? json['ownerTeamNumber'] : int.tryParse(json['ownerTeamNumber']?.toString() ?? '0') ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      createdByUsername: json['createdByUsername']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Shared Link',
      description: json['description']?.toString(),
      resourceType: json['resourceType']?.toString() ?? 'graph',
      targetEventKey: json['targetEventKey']?.toString(),
      shareMode: json['shareMode']?.toString() ?? 'live_query',
      queryConfigJson: json['queryConfigJson']?.toString() ?? '{}',
      accessScope: json['accessScope']?.toString() ?? 'public',
      allowedTeams: json['allowedTeams']?.toString(),
      hasPin: json['hasPin'] == true,
      redactPrivateNotes: json['redactPrivateNotes'] == true,
      redactScoutNames: json['redactScoutNames'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'].toString()) : null,
      isExpired: json['isExpired'] == true,
      isRevoked: json['isRevoked'] == true,
      revokedAt: json['revokedAt'] != null ? DateTime.tryParse(json['revokedAt'].toString()) : null,
      revokedByUsername: json['revokedByUsername']?.toString(),
      viewCount: json['viewCount'] is int ? json['viewCount'] : int.tryParse(json['viewCount']?.toString() ?? '0') ?? 0,
      lastAccessedAt: json['lastAccessedAt'] != null ? DateTime.tryParse(json['lastAccessedAt'].toString()) : null,
      shareUrl: json['shareUrl']?.toString(),
    );
  }
}

class ResolvedSharePayload {
  final String token;
  final String title;
  final String? description;
  final String resourceType;
  final String? targetEventKey;
  final String shareMode;
  final String queryConfigJson;
  final String? snapshotDataJson;
  final String? liveDataJson;
  final int ownerTeamNumber;
  final String program;
  final String createdByUsername;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isExpired;
  final bool isRevoked;
  final String accessScope;
  final bool requiresPin;
  final bool pinVerified;
  final bool isAllowed;
  final String? errorMessage;

  ResolvedSharePayload({
    required this.token,
    required this.title,
    this.description,
    required this.resourceType,
    this.targetEventKey,
    required this.shareMode,
    required this.queryConfigJson,
    this.snapshotDataJson,
    this.liveDataJson,
    required this.ownerTeamNumber,
    required this.program,
    required this.createdByUsername,
    required this.createdAt,
    this.expiresAt,
    required this.isExpired,
    required this.isRevoked,
    required this.accessScope,
    required this.requiresPin,
    this.pinVerified = false,
    this.isAllowed = true,
    this.errorMessage,
  });

  factory ResolvedSharePayload.fromJson(Map<String, dynamic> json) {
    return ResolvedSharePayload(
      token: json['token']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Shared Link',
      description: json['description']?.toString(),
      resourceType: json['resourceType']?.toString() ?? 'graph',
      targetEventKey: json['targetEventKey']?.toString(),
      shareMode: json['shareMode']?.toString() ?? 'live_query',
      queryConfigJson: json['queryConfigJson']?.toString() ?? '{}',
      snapshotDataJson: json['snapshotDataJson']?.toString(),
      liveDataJson: json['liveDataJson']?.toString(),
      ownerTeamNumber: json['ownerTeamNumber'] is int ? json['ownerTeamNumber'] : int.tryParse(json['ownerTeamNumber']?.toString() ?? '0') ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      createdByUsername: json['createdByUsername']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'].toString()) : null,
      isExpired: json['isExpired'] == true,
      isRevoked: json['isRevoked'] == true,
      accessScope: json['accessScope']?.toString() ?? 'public',
      requiresPin: json['requiresPin'] == true,
      pinVerified: json['pinVerified'] == true,
      isAllowed: json['isAllowed'] != false,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
