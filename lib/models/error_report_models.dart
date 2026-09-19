// ignore_for_file: non_constant_identifier_names

// ---------------------------------------------------------------------------
// Error Report Models — mirrors ServerErrorAlertService.kt & Models.kt
// ---------------------------------------------------------------------------

class ReportedErrorItem {
  final String id;
  final String errorType; // "SERVER" | "CLIENT_JS"
  final String errorMessage;
  final String? errorStack;
  final String? requestDetails;
  final String? clientIp;
  final int? teamNumber;
  final String? program;
  final String? userRole;
  final String? username;
  final String status; // "OPEN" | "RESOLVED"
  final String createdAt;
  final String? resolvedAt;
  final String? resolvedBy;

  const ReportedErrorItem({
    required this.id,
    required this.errorType,
    required this.errorMessage,
    this.errorStack,
    this.requestDetails,
    this.clientIp,
    this.teamNumber,
    this.program,
    this.userRole,
    this.username,
    this.status = 'OPEN',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  bool get isOpen => status.toUpperCase() == 'OPEN';
  bool get isResolved => status.toUpperCase() == 'RESOLVED';
  bool get isServer => errorType.toUpperCase() == 'SERVER';
  bool get isClient => errorType.toUpperCase() == 'CLIENT_JS';

  factory ReportedErrorItem.fromJson(Map<String, dynamic> j) {
    return ReportedErrorItem(
      id: j['id']?.toString() ?? '',
      errorType: j['errorType']?.toString() ?? 'SERVER',
      errorMessage: j['errorMessage']?.toString() ?? '',
      errorStack: j['errorStack']?.toString(),
      requestDetails: j['requestDetails']?.toString(),
      clientIp: j['clientIp']?.toString(),
      teamNumber: (j['teamNumber'] as num?)?.toInt(),
      program: j['program']?.toString(),
      userRole: j['userRole']?.toString(),
      username: j['username']?.toString(),
      status: j['status']?.toString() ?? 'OPEN',
      createdAt: j['createdAt']?.toString() ?? '',
      resolvedAt: j['resolvedAt']?.toString(),
      resolvedBy: j['resolvedBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'errorType': errorType,
        'errorMessage': errorMessage,
        'errorStack': errorStack,
        'requestDetails': requestDetails,
        'clientIp': clientIp,
        'teamNumber': teamNumber,
        'program': program,
        'userRole': userRole,
        'username': username,
        'status': status,
        'createdAt': createdAt,
        'resolvedAt': resolvedAt,
        'resolvedBy': resolvedBy,
      };

  ReportedErrorItem copyWith({
    String? id,
    String? errorType,
    String? errorMessage,
    String? errorStack,
    String? requestDetails,
    String? clientIp,
    int? teamNumber,
    String? program,
    String? userRole,
    String? username,
    String? status,
    String? createdAt,
    String? resolvedAt,
    String? resolvedBy,
  }) {
    return ReportedErrorItem(
      id: id ?? this.id,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      errorStack: errorStack ?? this.errorStack,
      requestDetails: requestDetails ?? this.requestDetails,
      clientIp: clientIp ?? this.clientIp,
      teamNumber: teamNumber ?? this.teamNumber,
      program: program ?? this.program,
      userRole: userRole ?? this.userRole,
      username: username ?? this.username,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
    );
  }
}

class ReportedErrorGroupItem {
  final String groupKey;
  final String errorType;
  final String errorMessage;
  final String location;
  final int count;
  final int openCount;
  final int resolvedCount;
  final String status;
  final String latestCreatedAt;
  final String firstCreatedAt;
  final List<int> affectedTeams;
  final List<String> affectedUsers;
  final ReportedErrorItem sampleError;
  final List<ReportedErrorItem> occurrences;

  const ReportedErrorGroupItem({
    required this.groupKey,
    required this.errorType,
    required this.errorMessage,
    required this.location,
    required this.count,
    required this.openCount,
    required this.resolvedCount,
    required this.status,
    required this.latestCreatedAt,
    required this.firstCreatedAt,
    this.affectedTeams = const [],
    this.affectedUsers = const [],
    required this.sampleError,
    this.occurrences = const [],
  });

  bool get isServer => errorType.toUpperCase() == 'SERVER';
  bool get hasOpen => openCount > 0;
  bool get isAllResolved => openCount == 0 && resolvedCount > 0;

  factory ReportedErrorGroupItem.fromJson(Map<String, dynamic> j) {
    final sampleMap = j['sampleError'] is Map<String, dynamic>
        ? j['sampleError'] as Map<String, dynamic>
        : <String, dynamic>{};

    final occList = (j['occurrences'] as List<dynamic>? ?? [])
        .map((e) => ReportedErrorItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return ReportedErrorGroupItem(
      groupKey: j['groupKey']?.toString() ?? '',
      errorType: j['errorType']?.toString() ?? 'SERVER',
      errorMessage: j['errorMessage']?.toString() ?? '',
      location: j['location']?.toString() ?? '',
      count: (j['count'] as num?)?.toInt() ?? 0,
      openCount: (j['openCount'] as num?)?.toInt() ?? 0,
      resolvedCount: (j['resolvedCount'] as num?)?.toInt() ?? 0,
      status: j['status']?.toString() ?? 'OPEN',
      latestCreatedAt: j['latestCreatedAt']?.toString() ?? '',
      firstCreatedAt: j['firstCreatedAt']?.toString() ?? '',
      affectedTeams: (j['affectedTeams'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      affectedUsers: (j['affectedUsers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      sampleError: ReportedErrorItem.fromJson(sampleMap),
      occurrences: occList,
    );
  }
}

class ReportedErrorsListResponse {
  final bool success;
  final List<ReportedErrorItem> errors;
  final List<ReportedErrorGroupItem> groups;
  final int totalCount;
  final int openCount;
  final int resolvedCount;
  final int serverCount;
  final int clientCount;

  const ReportedErrorsListResponse({
    this.success = true,
    required this.errors,
    this.groups = const [],
    required this.totalCount,
    required this.openCount,
    required this.resolvedCount,
    required this.serverCount,
    required this.clientCount,
  });

  factory ReportedErrorsListResponse.fromJson(Map<String, dynamic> j) {
    final rawErrors = (j['errors'] as List<dynamic>? ?? [])
        .map((e) => ReportedErrorItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawGroups = (j['groups'] as List<dynamic>? ?? [])
        .map((e) => ReportedErrorGroupItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return ReportedErrorsListResponse(
      success: j['success'] == true,
      errors: rawErrors,
      groups: rawGroups,
      totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
      openCount: (j['openCount'] as num?)?.toInt() ?? 0,
      resolvedCount: (j['resolvedCount'] as num?)?.toInt() ?? 0,
      serverCount: (j['serverCount'] as num?)?.toInt() ?? 0,
      clientCount: (j['clientCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReportedErrorStatsResponse {
  final bool success;
  final int totalCount;
  final int openCount;
  final int resolvedCount;
  final int serverCount;
  final int clientCount;

  const ReportedErrorStatsResponse({
    this.success = true,
    required this.totalCount,
    required this.openCount,
    required this.resolvedCount,
    required this.serverCount,
    required this.clientCount,
  });

  factory ReportedErrorStatsResponse.fromJson(Map<String, dynamic> j) {
    return ReportedErrorStatsResponse(
      success: j['success'] == true,
      totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
      openCount: (j['openCount'] as num?)?.toInt() ?? 0,
      resolvedCount: (j['resolvedCount'] as num?)?.toInt() ?? 0,
      serverCount: (j['serverCount'] as num?)?.toInt() ?? 0,
      clientCount: (j['clientCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ClearReportedErrorsResponse {
  final bool success;
  final int clearedCount;

  const ClearReportedErrorsResponse({
    this.success = true,
    required this.clearedCount,
  });

  factory ClearReportedErrorsResponse.fromJson(Map<String, dynamic> j) {
    return ClearReportedErrorsResponse(
      success: j['success'] == true,
      clearedCount: (j['clearedCount'] as num?)?.toInt() ?? 0,
    );
  }
}
