// Intrusion detection: what the server's /api/security and /api/admin/security endpoints return.

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _str(dynamic v) => v?.toString() ?? '';
String? _strOrNull(dynamic v) => v?.toString();
List<String> _strList(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];

/// Why the server refused a request from this network (HTTP 403, code "ip_blocked").
class IpBlockInfo {
  final String message;
  final String? blockId;
  final int? expiresAt;
  final int? retryAfterSeconds;
  final bool unblockRequestsEnabled;

  const IpBlockInfo({
    required this.message,
    this.blockId,
    this.expiresAt,
    this.retryAfterSeconds,
    this.unblockRequestsEnabled = true,
  });

  factory IpBlockInfo.fromJson(Map<String, dynamic> j) => IpBlockInfo(
        message: _str(j['error']),
        blockId: _strOrNull(j['blockId']),
        expiresAt: _intOrNull(j['expiresAt']),
        retryAfterSeconds: _intOrNull(j['retryAfterSeconds']),
        unblockRequestsEnabled: j['unblockRequestsEnabled'] != false,
      );

  /// Reads a refusal body; null when it isn't an IP block.
  static IpBlockInfo? tryParse(dynamic body) {
    if (body is Map && body['code'] == 'ip_blocked') {
      return IpBlockInfo.fromJson(Map<String, dynamic>.from(body));
    }
    return null;
  }
}

class PowChallenge {
  final String token;
  final String nonce;
  final int difficulty;
  final int expiresAt;

  const PowChallenge({required this.token, required this.nonce, required this.difficulty, required this.expiresAt});

  factory PowChallenge.fromJson(Map<String, dynamic> j) => PowChallenge(
        token: _str(j['token']),
        nonce: _str(j['nonce']),
        difficulty: _int(j['difficulty']),
        expiresAt: _int(j['expiresAt']),
      );
}

class BlockStatus {
  final bool blocked;
  final String ip;
  final String? blockId;
  final int? expiresAt;
  final bool unblockRequestsEnabled;
  final String? pendingRequestId;
  final String? pendingRequestStatus;

  const BlockStatus({
    required this.blocked,
    required this.ip,
    this.blockId,
    this.expiresAt,
    this.unblockRequestsEnabled = true,
    this.pendingRequestId,
    this.pendingRequestStatus,
  });

  factory BlockStatus.fromJson(Map<String, dynamic> j) => BlockStatus(
        blocked: j['blocked'] == true,
        ip: _str(j['ip']),
        blockId: _strOrNull(j['blockId']),
        expiresAt: _intOrNull(j['expiresAt']),
        unblockRequestsEnabled: j['unblockRequestsEnabled'] != false,
        pendingRequestId: _strOrNull(j['pendingRequestId']),
        pendingRequestStatus: _strOrNull(j['pendingRequestStatus']),
      );
}

class UnblockRequestStatus {
  final String id;
  final String status;
  final String? reviewNote;

  const UnblockRequestStatus({required this.id, required this.status, this.reviewNote});

  factory UnblockRequestStatus.fromJson(Map<String, dynamic> j) => UnblockRequestStatus(
        id: _str(j['id']),
        status: _str(j['status']),
        reviewNote: _strOrNull(j['reviewNote']),
      );
}

class SecurityTimelineBucket {
  final int hourStart;
  final int low;
  final int medium;
  final int high;
  final int info;

  const SecurityTimelineBucket({required this.hourStart, this.low = 0, this.medium = 0, this.high = 0, this.info = 0});

  int get total => low + medium + high + info;

  factory SecurityTimelineBucket.fromJson(Map<String, dynamic> j) => SecurityTimelineBucket(
        hourStart: _int(j['hourStart']),
        low: _int(j['low']),
        medium: _int(j['medium']),
        high: _int(j['high']),
        info: _int(j['info']),
      );
}

class ThreatOffender {
  final String ip;
  final double score;
  final String level;
  final int lastEventAt;
  final String lastEventType;

  const ThreatOffender({required this.ip, required this.score, required this.level, required this.lastEventAt, required this.lastEventType});

  factory ThreatOffender.fromJson(Map<String, dynamic> j) => ThreatOffender(
        ip: _str(j['ip']),
        score: _double(j['score']),
        level: _str(j['level']),
        lastEventAt: _int(j['lastEventAt']),
        lastEventType: _str(j['lastEventType']),
      );
}

class SecuritySummary {
  final bool enabled;
  final String mode;
  final bool autoRevokeSessions;
  final int maxBlockMinutes;
  final int activeBlocks;
  final int pendingUnblockRequests;
  final int protectedAccounts;
  final bool credentialStuffingActive;
  final Map<String, int> eventsLast24h;
  final List<SecurityTimelineBucket> timeline;
  final List<ThreatOffender> topOffenders;
  final int droppedEvents;

  const SecuritySummary({
    required this.enabled,
    required this.mode,
    required this.autoRevokeSessions,
    required this.maxBlockMinutes,
    required this.activeBlocks,
    required this.pendingUnblockRequests,
    required this.protectedAccounts,
    required this.credentialStuffingActive,
    required this.eventsLast24h,
    required this.timeline,
    required this.topOffenders,
    required this.droppedEvents,
  });

  bool get enforcing => mode == 'enforce';

  factory SecuritySummary.fromJson(Map<String, dynamic> j) => SecuritySummary(
        enabled: j['enabled'] != false,
        mode: _str(j['mode']).isEmpty ? 'observe' : _str(j['mode']),
        autoRevokeSessions: j['autoRevokeSessions'] == true,
        maxBlockMinutes: _int(j['maxBlockMinutes']),
        activeBlocks: _int(j['activeBlocks']),
        pendingUnblockRequests: _int(j['pendingUnblockRequests']),
        protectedAccounts: _int(j['protectedAccounts']),
        credentialStuffingActive: j['credentialStuffingActive'] == true,
        eventsLast24h: (j['eventsLast24h'] is Map)
            ? (j['eventsLast24h'] as Map).map((k, v) => MapEntry(k.toString(), _int(v)))
            : const {},
        timeline: (j['timeline'] as List? ?? const [])
            .map((e) => SecurityTimelineBucket.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        topOffenders: (j['topOffenders'] as List? ?? const [])
            .map((e) => ThreatOffender.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        droppedEvents: _int(j['droppedEvents']),
      );
}

class IpBlock {
  final String id;
  final String ipOrCidr;
  final String reason;
  final List<String> triggeringEventTypes;
  final int createdAt;
  final int expiresAt;
  final String createdBy;
  final int strike;
  final int hits;
  final bool active;
  final String? pendingRequestId;
  final int recentDistinctUsers;

  const IpBlock({
    required this.id,
    required this.ipOrCidr,
    required this.reason,
    required this.triggeringEventTypes,
    required this.createdAt,
    required this.expiresAt,
    required this.createdBy,
    required this.strike,
    required this.hits,
    required this.active,
    this.pendingRequestId,
    this.recentDistinctUsers = 0,
  });

  factory IpBlock.fromJson(Map<String, dynamic> j) => IpBlock(
        id: _str(j['id']),
        ipOrCidr: _str(j['ipOrCidr']),
        reason: _str(j['reason']),
        triggeringEventTypes: _strList(j['triggeringEventTypes']),
        createdAt: _int(j['createdAt']),
        expiresAt: _int(j['expiresAt']),
        createdBy: _str(j['createdBy']),
        strike: _int(j['strike']),
        hits: _int(j['hits']),
        active: j['active'] == true,
        pendingRequestId: _strOrNull(j['pendingRequestId']),
        recentDistinctUsers: _int(j['recentDistinctUsers']),
      );
}

class UnblockRequest {
  final String id;
  final String blockId;
  final String ip;
  final String name;
  final int? teamNumber;
  final String? email;
  final String message;
  final String status;
  final bool highRisk;
  final int createdAt;
  final String? blockReason;
  final int? blockExpiresAt;
  final int recentDistinctUsers;

  const UnblockRequest({
    required this.id,
    required this.blockId,
    required this.ip,
    required this.name,
    this.teamNumber,
    this.email,
    required this.message,
    required this.status,
    required this.highRisk,
    required this.createdAt,
    this.blockReason,
    this.blockExpiresAt,
    this.recentDistinctUsers = 0,
  });

  factory UnblockRequest.fromJson(Map<String, dynamic> j) => UnblockRequest(
        id: _str(j['id']),
        blockId: _str(j['blockId']),
        ip: _str(j['ip']),
        name: _str(j['name']),
        teamNumber: _intOrNull(j['teamNumber']),
        email: _strOrNull(j['email']),
        message: _str(j['message']),
        status: _str(j['status']),
        highRisk: j['highRisk'] == true,
        createdAt: _int(j['createdAt']),
        blockReason: _strOrNull(j['blockReason']),
        blockExpiresAt: _intOrNull(j['blockExpiresAt']),
        recentDistinctUsers: _int(j['recentDistinctUsers']),
      );
}

class AllowlistEntry {
  final String id;
  final String ipOrCidr;
  final String note;
  final int createdAt;
  final String createdBy;
  final int? expiresAt;
  final bool fromConfig;

  const AllowlistEntry({
    required this.id,
    required this.ipOrCidr,
    required this.note,
    required this.createdAt,
    required this.createdBy,
    this.expiresAt,
    this.fromConfig = false,
  });

  factory AllowlistEntry.fromJson(Map<String, dynamic> j) => AllowlistEntry(
        id: _str(j['id']),
        ipOrCidr: _str(j['ipOrCidr']),
        note: _str(j['note']),
        createdAt: _int(j['createdAt']),
        createdBy: _str(j['createdBy']),
        expiresAt: _intOrNull(j['expiresAt']),
        fromConfig: j['fromConfig'] == true,
      );
}

class ProtectedAccount {
  /// The server's account key (username, team and program); sent back to clear protection.
  final String account;
  final String username;
  final int? teamNumber;
  final String? program;
  final int protectedUntil;

  const ProtectedAccount({
    required this.account,
    required this.username,
    this.teamNumber,
    this.program,
    required this.protectedUntil,
  });

  /// "admin (team 254 FRC)", or just the username when the team is unknown.
  String get label => teamNumber == null ? username : '$username (team $teamNumber${program != null ? ' $program' : ''})';

  factory ProtectedAccount.fromJson(Map<String, dynamic> j) => ProtectedAccount(
        account: _str(j['account']).isEmpty ? _str(j['username']) : _str(j['account']),
        username: _str(j['username']),
        teamNumber: _intOrNull(j['teamNumber']),
        program: _strOrNull(j['program']),
        protectedUntil: _int(j['protectedUntil']),
      );
}

class SecurityEventEntry {
  final String id;
  final int at;
  final String type;
  final String severity;
  final String ip;
  final String? username;
  final int? teamNumber;
  final String method;
  final String path;
  final String details;
  final String node;

  const SecurityEventEntry({
    required this.id,
    required this.at,
    required this.type,
    required this.severity,
    required this.ip,
    this.username,
    this.teamNumber,
    this.method = '',
    this.path = '',
    this.details = '',
    this.node = '',
  });

  factory SecurityEventEntry.fromJson(Map<String, dynamic> j) => SecurityEventEntry(
        id: _str(j['id']),
        at: _int(j['at']),
        type: _str(j['type']),
        severity: _str(j['severity']),
        ip: _str(j['ip']),
        username: _strOrNull(j['username']),
        teamNumber: _intOrNull(j['teamNumber']),
        method: _str(j['method']),
        path: _str(j['path']),
        details: _str(j['details']),
        node: _str(j['node']),
      );
}

class SecurityEventPage {
  final List<SecurityEventEntry> events;
  final int total;
  final int offset;
  final int limit;

  const SecurityEventPage({required this.events, required this.total, required this.offset, required this.limit});

  factory SecurityEventPage.fromJson(Map<String, dynamic> j) => SecurityEventPage(
        events: (j['events'] as List? ?? const [])
            .map((e) => SecurityEventEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total: _int(j['total']),
        offset: _int(j['offset']),
        limit: _int(j['limit']),
      );
}

/// Result of an admin action: success, or the server's message.
class SecurityActionResult {
  final bool ok;
  final String? error;
  final int? count;

  const SecurityActionResult({required this.ok, this.error, this.count});
}
