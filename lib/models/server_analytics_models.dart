// ============================================================================
// Server Analytics & Insights Models
// Mirrors server: com.obsidianscout.admin.ServerAnalyticsService
// ============================================================================

class DatabasePoolMetrics {
  final int activeConnections;
  final int idleConnections;
  final int threadsAwaiting;
  final int totalConnections;
  final int maxPoolSize;
  final int minIdle;
  final double saturationPercent;
  final bool isHealthy;
  final String engineType;

  const DatabasePoolMetrics({
    this.activeConnections = 0,
    this.idleConnections = 0,
    this.threadsAwaiting = 0,
    this.totalConnections = 0,
    this.maxPoolSize = 0,
    this.minIdle = 0,
    this.saturationPercent = 0.0,
    this.isHealthy = true,
    this.engineType = 'unknown',
  });

  factory DatabasePoolMetrics.fromJson(Map<String, dynamic> json) {
    return DatabasePoolMetrics(
      activeConnections: (json['activeConnections'] as num?)?.toInt() ?? 0,
      idleConnections: (json['idleConnections'] as num?)?.toInt() ?? 0,
      threadsAwaiting: (json['threadsAwaiting'] as num?)?.toInt() ?? 0,
      totalConnections: (json['totalConnections'] as num?)?.toInt() ?? 0,
      maxPoolSize: (json['maxPoolSize'] as num?)?.toInt() ?? 0,
      minIdle: (json['minIdle'] as num?)?.toInt() ?? 0,
      saturationPercent: (json['saturationPercent'] as num?)?.toDouble() ?? 0.0,
      isHealthy: json['isHealthy'] as bool? ?? true,
      engineType: json['engineType'] as String? ?? 'unknown',
    );
  }
}

class WebSocketMetrics {
  final int activeConnections;
  final int connectedUsers;
  final int connectsLastMinute;
  final int disconnectsLastMinute;
  final int churnRatePerMinute;
  final int totalTopicBroadcasts;
  final int droppedBroadcasts;

  const WebSocketMetrics({
    this.activeConnections = 0,
    this.connectedUsers = 0,
    this.connectsLastMinute = 0,
    this.disconnectsLastMinute = 0,
    this.churnRatePerMinute = 0,
    this.totalTopicBroadcasts = 0,
    this.droppedBroadcasts = 0,
  });

  factory WebSocketMetrics.fromJson(Map<String, dynamic> json) {
    return WebSocketMetrics(
      activeConnections: (json['activeConnections'] as num?)?.toInt() ?? 0,
      connectedUsers: (json['connectedUsers'] as num?)?.toInt() ?? 0,
      connectsLastMinute: (json['connectsLastMinute'] as num?)?.toInt() ?? 0,
      disconnectsLastMinute:
          (json['disconnectsLastMinute'] as num?)?.toInt() ?? 0,
      churnRatePerMinute: (json['churnRatePerMinute'] as num?)?.toInt() ?? 0,
      totalTopicBroadcasts:
          (json['totalTopicBroadcasts'] as num?)?.toInt() ?? 0,
      droppedBroadcasts: (json['droppedBroadcasts'] as num?)?.toInt() ?? 0,
    );
  }
}

class ClientFleetMetrics {
  final int totalActiveDevices;
  final Map<String, int> clientsByPlatform;
  final Map<String, int> clientsByVersion;
  final int avgIngestLagMs;
  final int maxIngestLagMs;
  final int syncSubmissionsCount;

  const ClientFleetMetrics({
    this.totalActiveDevices = 0,
    this.clientsByPlatform = const {},
    this.clientsByVersion = const {},
    this.avgIngestLagMs = 0,
    this.maxIngestLagMs = 0,
    this.syncSubmissionsCount = 0,
  });

  factory ClientFleetMetrics.fromJson(Map<String, dynamic> json) {
    final rawPlatform = json['clientsByPlatform'] as Map<String, dynamic>?;
    final platformMap = <String, int>{};
    if (rawPlatform != null) {
      rawPlatform.forEach((k, v) {
        if (v is num) platformMap[k] = v.toInt();
      });
    }

    final rawVersion = json['clientsByVersion'] as Map<String, dynamic>?;
    final versionMap = <String, int>{};
    if (rawVersion != null) {
      rawVersion.forEach((k, v) {
        if (v is num) versionMap[k] = v.toInt();
      });
    }

    return ClientFleetMetrics(
      totalActiveDevices: (json['totalActiveDevices'] as num?)?.toInt() ?? 0,
      clientsByPlatform: platformMap,
      clientsByVersion: versionMap,
      avgIngestLagMs: (json['avgIngestLagMs'] as num?)?.toInt() ?? 0,
      maxIngestLagMs: (json['maxIngestLagMs'] as num?)?.toInt() ?? 0,
      syncSubmissionsCount:
          (json['syncSubmissionsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class JvmDiagnosticsMetrics {
  final int usedHeapMb;
  final int maxHeapMb;
  final double heapUsagePercent;
  final int nonHeapUsedMb;
  final int gcCount;
  final int gcTimeMs;
  final int liveThreads;
  final int peakThreads;
  final int daemonThreads;
  final int uptimeSeconds;

  const JvmDiagnosticsMetrics({
    this.usedHeapMb = 0,
    this.maxHeapMb = 0,
    this.heapUsagePercent = 0.0,
    this.nonHeapUsedMb = 0,
    this.gcCount = 0,
    this.gcTimeMs = 0,
    this.liveThreads = 0,
    this.peakThreads = 0,
    this.daemonThreads = 0,
    this.uptimeSeconds = 0,
  });

  factory JvmDiagnosticsMetrics.fromJson(Map<String, dynamic> json) {
    return JvmDiagnosticsMetrics(
      usedHeapMb: (json['usedHeapMb'] as num?)?.toInt() ?? 0,
      maxHeapMb: (json['maxHeapMb'] as num?)?.toInt() ?? 0,
      heapUsagePercent: (json['heapUsagePercent'] as num?)?.toDouble() ?? 0.0,
      nonHeapUsedMb: (json['nonHeapUsedMb'] as num?)?.toInt() ?? 0,
      gcCount: (json['gcCount'] as num?)?.toInt() ?? 0,
      gcTimeMs: (json['gcTimeMs'] as num?)?.toInt() ?? 0,
      liveThreads: (json['liveThreads'] as num?)?.toInt() ?? 0,
      peakThreads: (json['peakThreads'] as num?)?.toInt() ?? 0,
      daemonThreads: (json['daemonThreads'] as num?)?.toInt() ?? 0,
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class LatencyMetrics {
  final double p50Ms;
  final double p90Ms;
  final double p95Ms;
  final double p99Ms;
  final double maxMs;
  final double requestsPerSecond;
  final int sampleCount;
  final int totalRequests;
  final int error4xxCount;
  final int error5xxCount;

  const LatencyMetrics({
    this.p50Ms = 0.0,
    this.p90Ms = 0.0,
    this.p95Ms = 0.0,
    this.p99Ms = 0.0,
    this.maxMs = 0.0,
    this.requestsPerSecond = 0.0,
    this.sampleCount = 0,
    this.totalRequests = 0,
    this.error4xxCount = 0,
    this.error5xxCount = 0,
  });

  factory LatencyMetrics.fromJson(Map<String, dynamic> json) {
    return LatencyMetrics(
      p50Ms: (json['p50Ms'] as num?)?.toDouble() ?? 0.0,
      p90Ms: (json['p90Ms'] as num?)?.toDouble() ?? 0.0,
      p95Ms: (json['p95Ms'] as num?)?.toDouble() ?? 0.0,
      p99Ms: (json['p99Ms'] as num?)?.toDouble() ?? 0.0,
      maxMs: (json['maxMs'] as num?)?.toDouble() ?? 0.0,
      requestsPerSecond:
          (json['requestsPerSecond'] as num?)?.toDouble() ?? 0.0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      totalRequests: (json['totalRequests'] as num?)?.toInt() ?? 0,
      error4xxCount: (json['error4xxCount'] as num?)?.toInt() ?? 0,
      error5xxCount: (json['error5xxCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SecurityAuditItem {
  final String id;
  final int timestamp;
  final String action;
  final String username;
  final String role;
  final String ipAddress;
  final String details;
  final bool success;

  const SecurityAuditItem({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.username,
    required this.role,
    required this.ipAddress,
    required this.details,
    this.success = true,
  });

  factory SecurityAuditItem.fromJson(Map<String, dynamic> json) {
    return SecurityAuditItem(
      id: json['id'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      action: json['action'] as String? ?? '',
      username: json['username'] as String? ?? 'UNKNOWN',
      role: json['role'] as String? ?? 'UNKNOWN',
      ipAddress: json['ipAddress'] as String? ?? '',
      details: json['details'] as String? ?? '',
      success: json['success'] as bool? ?? true,
    );
  }
}

class SecurityInsightsMetrics {
  final int failedLoginsLastHour;
  final int rateLimitHitsLastHour;
  final List<SecurityAuditItem> recentAuditLogs;

  const SecurityInsightsMetrics({
    this.failedLoginsLastHour = 0,
    this.rateLimitHitsLastHour = 0,
    this.recentAuditLogs = const [],
  });

  factory SecurityInsightsMetrics.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['recentAuditLogs'] as List<dynamic>?;
    final logs = <SecurityAuditItem>[];
    if (rawLogs != null) {
      for (final item in rawLogs) {
        if (item is Map<String, dynamic>) {
          logs.add(SecurityAuditItem.fromJson(item));
        }
      }
    }

    return SecurityInsightsMetrics(
      failedLoginsLastHour:
          (json['failedLoginsLastHour'] as num?)?.toInt() ?? 0,
      rateLimitHitsLastHour:
          (json['rateLimitHitsLastHour'] as num?)?.toInt() ?? 0,
      recentAuditLogs: logs,
    );
  }
}

class ServerAnalyticsOverview {
  final String nodeIp;
  final int timestamp;
  final DatabasePoolMetrics dbPool;
  final WebSocketMetrics webSockets;
  final ClientFleetMetrics clientFleet;
  final JvmDiagnosticsMetrics jvm;
  final LatencyMetrics latency;
  final SecurityInsightsMetrics security;

  const ServerAnalyticsOverview({
    required this.nodeIp,
    required this.timestamp,
    required this.dbPool,
    required this.webSockets,
    required this.clientFleet,
    required this.jvm,
    required this.latency,
    required this.security,
  });

  factory ServerAnalyticsOverview.fromJson(Map<String, dynamic> json) {
    return ServerAnalyticsOverview(
      nodeIp: json['nodeIp'] as String? ?? 'local',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      dbPool: json['dbPool'] is Map<String, dynamic>
          ? DatabasePoolMetrics.fromJson(json['dbPool'] as Map<String, dynamic>)
          : const DatabasePoolMetrics(),
      webSockets: json['webSockets'] is Map<String, dynamic>
          ? WebSocketMetrics.fromJson(
              json['webSockets'] as Map<String, dynamic>)
          : const WebSocketMetrics(),
      clientFleet: json['clientFleet'] is Map<String, dynamic>
          ? ClientFleetMetrics.fromJson(
              json['clientFleet'] as Map<String, dynamic>)
          : const ClientFleetMetrics(),
      jvm: json['jvm'] is Map<String, dynamic>
          ? JvmDiagnosticsMetrics.fromJson(json['jvm'] as Map<String, dynamic>)
          : const JvmDiagnosticsMetrics(),
      latency: json['latency'] is Map<String, dynamic>
          ? LatencyMetrics.fromJson(json['latency'] as Map<String, dynamic>)
          : const LatencyMetrics(),
      security: json['security'] is Map<String, dynamic>
          ? SecurityInsightsMetrics.fromJson(
              json['security'] as Map<String, dynamic>)
          : const SecurityInsightsMetrics(),
    );
  }
}

/// [combined] is the whole cluster, null when no node answered; [nodes] are the same figures per node.
class ClusterAnalyticsOverview {
  final ServerAnalyticsOverview? combined;
  final List<ServerAnalyticsOverview> nodes;
  final List<String> unreachableNodes;

  const ClusterAnalyticsOverview({
    this.combined,
    this.nodes = const [],
    this.unreachableNodes = const [],
  });

  factory ClusterAnalyticsOverview.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'] as List<dynamic>?;
    final rawUnreachable = json['unreachableNodes'] as List<dynamic>?;
    return ClusterAnalyticsOverview(
      combined: json['combined'] is Map<String, dynamic>
          ? ServerAnalyticsOverview.fromJson(
              json['combined'] as Map<String, dynamic>)
          : null,
      nodes: (rawNodes ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServerAnalyticsOverview.fromJson)
          .toList(),
      unreachableNodes:
          (rawUnreachable ?? const []).map((ip) => ip.toString()).toList(),
    );
  }
}
