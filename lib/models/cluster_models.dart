// ignore_for_file: non_constant_identifier_names

// ---------------------------------------------------------------------------
// Cluster Models — mirrors ClusterManagementService.kt & PeerLoadRouter.kt & SnapshotService.kt
// ---------------------------------------------------------------------------

/// A single cluster node as returned by GET /api/admin/cluster/nodes
class ClusterNodeInfo {
  final String nodeId;
  final String ip;
  final int dbPort;
  final int appPort;
  final bool isLocal;
  final String status;
  final String role;
  final String? cockroachVersion;
  final bool isDbActive;
  final String? serverVersion;
  final String? executionMode;

  const ClusterNodeInfo({
    required this.nodeId,
    required this.ip,
    required this.dbPort,
    required this.appPort,
    required this.isLocal,
    required this.status,
    required this.role,
    this.cockroachVersion,
    required this.isDbActive,
    this.serverVersion,
    this.executionMode,
  });

  factory ClusterNodeInfo.fromJson(Map<String, dynamic> j) => ClusterNodeInfo(
        nodeId: j['nodeId']?.toString() ?? '',
        ip: j['ip']?.toString() ?? '',
        dbPort: (j['dbPort'] as num?)?.toInt() ?? 26257,
        appPort: (j['appPort'] as num?)?.toInt() ?? 8080,
        isLocal: j['isLocal'] == true,
        status: j['status']?.toString() ?? 'unknown',
        role: j['role']?.toString() ?? 'UNKNOWN',
        cockroachVersion: j['cockroachVersion']?.toString(),
        isDbActive: j['isDbActive'] == true,
        serverVersion: j['serverVersion']?.toString(),
        executionMode: j['executionMode']?.toString(),
      );
}

/// Top-level response for GET /api/admin/cluster/nodes
class ClusterNodesResponse {
  final String localNodeIp;
  final int totalNodes;
  final List<ClusterNodeInfo> nodes;

  const ClusterNodesResponse({
    required this.localNodeIp,
    required this.totalNodes,
    required this.nodes,
  });

  factory ClusterNodesResponse.fromJson(Map<String, dynamic> j) =>
      ClusterNodesResponse(
        localNodeIp: j['localNodeIp']?.toString() ?? '',
        totalNodes: (j['totalNodes'] as num?)?.toInt() ?? 0,
        nodes: (j['nodes'] as List<dynamic>? ?? [])
            .map((e) => ClusterNodeInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A single log entry returned in the logs arrays
class ServerLogEntry {
  final String timestamp;
  final String level;
  final String message;
  final String? logger;
  final String? nodeIp;

  const ServerLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.logger,
    this.nodeIp,
  });

  factory ServerLogEntry.fromJson(Map<String, dynamic> j) => ServerLogEntry(
        timestamp: j['timestamp']?.toString() ?? '',
        level: j['level']?.toString() ?? 'INFO',
        message: j['message']?.toString() ?? '',
        logger: j['logger']?.toString(),
        nodeIp: j['nodeIp']?.toString(),
      );
}

/// Generic action result (reboot, reinstall, key regen, etc.)
class ActionResultResponse {
  final bool success;
  final String message;
  final String? targetIp;

  const ActionResultResponse({
    required this.success,
    required this.message,
    this.targetIp,
  });

  factory ActionResultResponse.fromJson(Map<String, dynamic> j) =>
      ActionResultResponse(
        success: j['success'] == true,
        message: j['message']?.toString() ?? '',
        targetIp: j['targetIp']?.toString(),
      );
}

/// Response for GET /api/admin/cluster/nodes/{ip}/app-config
class AppConfigPayload {
  final String nodeIp;
  final bool isLocal;
  final String rawJson;
  final Map<String, dynamic>? config;

  const AppConfigPayload({
    required this.nodeIp,
    required this.isLocal,
    required this.rawJson,
    this.config,
  });

  factory AppConfigPayload.fromJson(Map<String, dynamic> j) => AppConfigPayload(
        nodeIp: j['nodeIp']?.toString() ?? '',
        isLocal: j['isLocal'] == true,
        rawJson: j['rawJson']?.toString() ?? '',
        config: j['config'] as Map<String, dynamic>?,
      );
}

// ---------------------------------------------------------------------------
// Load Balancer Models (mirrors PeerLoadRouter.kt & SettingsService.kt)
// ---------------------------------------------------------------------------

class NodeLoad {
  final String ip;
  final int appPort;
  final int availableHeapMb;
  final int maxHeapMb;
  final int usedHeapMb;
  final double cpuLoad; // 0.0 - 1.0
  final int activeThreads;
  final int latencyMs;
  final double score; // 0.0 - 1.0

  const NodeLoad({
    required this.ip,
    this.appPort = 8080,
    this.availableHeapMb = 0,
    this.maxHeapMb = 0,
    this.usedHeapMb = 0,
    this.cpuLoad = 0.0,
    this.activeThreads = 0,
    this.latencyMs = 0,
    this.score = 0.0,
  });

  factory NodeLoad.fromJson(Map<String, dynamic> j) => NodeLoad(
        ip: j['ip']?.toString() ?? '',
        appPort: (j['appPort'] as num?)?.toInt() ?? 8080,
        availableHeapMb: (j['availableHeapMb'] as num?)?.toInt() ?? 0,
        maxHeapMb: (j['maxHeapMb'] as num?)?.toInt() ?? 0,
        usedHeapMb: (j['usedHeapMb'] as num?)?.toInt() ?? 0,
        cpuLoad: (j['cpuLoad'] as num?)?.toDouble() ?? 0.0,
        activeThreads: (j['activeThreads'] as num?)?.toInt() ?? 0,
        latencyMs: (j['latencyMs'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toDouble() ?? 0.0,
      );
}

class LoadBalancingActivityEntry {
  final int timestampEpochMs;
  final String localIp;
  final String targetIp;
  final bool isForwarded;
  final double localScore;
  final double targetScore;
  final int localHeapFreeMb;
  final int localCpuPercent;
  final int requestsForwarded;
  final int requestsServedLocally;
  final String note;

  const LoadBalancingActivityEntry({
    required this.timestampEpochMs,
    this.localIp = '',
    this.targetIp = '',
    this.isForwarded = false,
    this.localScore = 0.0,
    this.targetScore = 0.0,
    this.localHeapFreeMb = 0,
    this.localCpuPercent = 0,
    this.requestsForwarded = 0,
    this.requestsServedLocally = 0,
    this.note = '',
  });

  factory LoadBalancingActivityEntry.fromJson(Map<String, dynamic> j) =>
      LoadBalancingActivityEntry(
        timestampEpochMs: (j['timestampEpochMs'] as num?)?.toInt() ?? 0,
        localIp: j['localIp']?.toString() ?? '',
        targetIp: j['targetIp']?.toString() ?? '',
        isForwarded: j['isForwarded'] == true,
        localScore: (j['localScore'] as num?)?.toDouble() ?? 0.0,
        targetScore: (j['targetScore'] as num?)?.toDouble() ?? 0.0,
        localHeapFreeMb: (j['localHeapFreeMb'] as num?)?.toInt() ?? 0,
        localCpuPercent: (j['localCpuPercent'] as num?)?.toInt() ?? 0,
        requestsForwarded: (j['requestsForwarded'] as num?)?.toInt() ?? 0,
        requestsServedLocally:
            (j['requestsServedLocally'] as num?)?.toInt() ?? 0,
        note: j['note']?.toString() ?? '',
      );
}

class LoadBalancingRecentStats {
  final int totalForwarded30m;
  final int totalLocalServed30m;
  final double forwardedRatio30m;
  final Map<String, int> targetDistribution;

  const LoadBalancingRecentStats({
    this.totalForwarded30m = 0,
    this.totalLocalServed30m = 0,
    this.forwardedRatio30m = 0.0,
    this.targetDistribution = const {},
  });

  factory LoadBalancingRecentStats.fromJson(Map<String, dynamic> j) =>
      LoadBalancingRecentStats(
        totalForwarded30m: (j['totalForwarded30m'] as num?)?.toInt() ?? 0,
        totalLocalServed30m: (j['totalLocalServed30m'] as num?)?.toInt() ?? 0,
        forwardedRatio30m:
            (j['forwardedRatio30m'] as num?)?.toDouble() ?? 0.0,
        targetDistribution: (j['targetDistribution'] as Map<String, dynamic>? ??
                {})
            .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      );
}

class LoadBalancerStatus {
  final bool enabled;
  final NodeLoad? localNode;
  final List<NodeLoad> peerNodes;
  final String bestNodeIp;
  final bool isForwardingActive;
  final int forwardedCount;
  final int localServedCount;
  final double localPreferenceMargin;
  final double maxExpectedLatencyMs;
  final int probeIntervalSeconds;
  final LoadBalancingRecentStats recentStats;
  final List<LoadBalancingActivityEntry> activityHistory;

  const LoadBalancerStatus({
    required this.enabled,
    this.localNode,
    this.peerNodes = const [],
    this.bestNodeIp = '',
    this.isForwardingActive = false,
    this.forwardedCount = 0,
    this.localServedCount = 0,
    this.localPreferenceMargin = 0.10,
    this.maxExpectedLatencyMs = 150.0,
    this.probeIntervalSeconds = 15,
    this.recentStats = const LoadBalancingRecentStats(),
    this.activityHistory = const [],
  });

  factory LoadBalancerStatus.fromJson(Map<String, dynamic> j) =>
      LoadBalancerStatus(
        enabled: j['enabled'] == true,
        localNode: j['localNode'] != null
            ? NodeLoad.fromJson(j['localNode'] as Map<String, dynamic>)
            : null,
        peerNodes: (j['peerNodes'] as List<dynamic>? ?? [])
            .map((e) => NodeLoad.fromJson(e as Map<String, dynamic>))
            .toList(),
        bestNodeIp: j['bestNodeIp']?.toString() ?? '',
        isForwardingActive: j['isForwardingActive'] == true,
        forwardedCount: (j['forwardedCount'] as num?)?.toInt() ?? 0,
        localServedCount: (j['localServedCount'] as num?)?.toInt() ?? 0,
        localPreferenceMargin:
            (j['localPreferenceMargin'] as num?)?.toDouble() ?? 0.10,
        maxExpectedLatencyMs:
            (j['maxExpectedLatencyMs'] as num?)?.toDouble() ?? 150.0,
        probeIntervalSeconds:
            (j['probeIntervalSeconds'] as num?)?.toInt() ?? 15,
        recentStats: j['recentStats'] != null
            ? LoadBalancingRecentStats.fromJson(
                j['recentStats'] as Map<String, dynamic>)
            : const LoadBalancingRecentStats(),
        activityHistory: (j['activityHistory'] as List<dynamic>? ?? [])
            .map((e) => LoadBalancingActivityEntry.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      );
}

class LoadBalancerSettings {
  final bool enabled;
  final int probeIntervalSeconds;
  final int forwardTimeoutSeconds;
  final double localPreferenceMargin;
  final double maxExpectedLatencyMs;
  final List<String> excludedPathPrefixes;

  const LoadBalancerSettings({
    this.enabled = false,
    this.probeIntervalSeconds = 15,
    this.forwardTimeoutSeconds = 30,
    this.localPreferenceMargin = 0.10,
    this.maxExpectedLatencyMs = 150.0,
    this.excludedPathPrefixes = const [
      "/api/admin",
      "/api/auth",
      "/api/session",
      "/api/cluster",
      "/api/health",
      "/health",
      "/api/version",
      "/version",
      "/cluster-management"
    ],
  });

  factory LoadBalancerSettings.fromJson(Map<String, dynamic> j) =>
      LoadBalancerSettings(
        enabled: j['enabled'] == true,
        probeIntervalSeconds:
            (j['probeIntervalSeconds'] as num?)?.toInt() ?? 15,
        forwardTimeoutSeconds:
            (j['forwardTimeoutSeconds'] as num?)?.toInt() ?? 30,
        localPreferenceMargin:
            (j['localPreferenceMargin'] as num?)?.toDouble() ?? 0.10,
        maxExpectedLatencyMs:
            (j['maxExpectedLatencyMs'] as num?)?.toDouble() ?? 150.0,
        excludedPathPrefixes: (j['excludedPathPrefixes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'probeIntervalSeconds': probeIntervalSeconds,
        'forwardTimeoutSeconds': forwardTimeoutSeconds,
        'localPreferenceMargin': localPreferenceMargin,
        'maxExpectedLatencyMs': maxExpectedLatencyMs,
        'excludedPathPrefixes': excludedPathPrefixes,
      };
}

// ---------------------------------------------------------------------------
// Stress Test
// ---------------------------------------------------------------------------

class StressTestStatus {
  final bool isRunning;
  final int remainingSeconds;
  final String? startedAt;

  const StressTestStatus({
    required this.isRunning,
    this.remainingSeconds = 0,
    this.startedAt,
  });

  factory StressTestStatus.fromJson(Map<String, dynamic> j) => StressTestStatus(
        isRunning: j['isRunning'] == true,
        remainingSeconds: (j['remainingSeconds'] as num?)?.toInt() ??
            (j['secondsRemaining'] as num?)?.toInt() ??
            0,
        startedAt: j['startedAt']?.toString(),
      );
}

// ---------------------------------------------------------------------------
// Node Down Alerts & Server Error Alerts
// ---------------------------------------------------------------------------

class NodeAlertsEnrollment {
  final bool enrolled;
  final String? email;
  final String? userId;

  const NodeAlertsEnrollment({
    required this.enrolled,
    this.email,
    this.userId,
  });

  factory NodeAlertsEnrollment.fromJson(Map<String, dynamic> j) =>
      NodeAlertsEnrollment(
        enrolled: j['enrolled'] == true,
        email: j['email']?.toString(),
        userId: j['userId']?.toString(),
      );
}

class ServerErrorAlertsSettings {
  final bool enabled;
  final List<String> additionalEmails;
  final List<String> enrolledSuperadmins;

  const ServerErrorAlertsSettings({
    required this.enabled,
    this.additionalEmails = const [],
    this.enrolledSuperadmins = const [],
  });

  factory ServerErrorAlertsSettings.fromJson(Map<String, dynamic> j) =>
      ServerErrorAlertsSettings(
        enabled: j['enabled'] == true || j['emailServerErrors'] == true,
        additionalEmails: (j['additionalEmails'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        enrolledSuperadmins: (j['enrolledSuperadmins'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'emailServerErrors': enabled,
        'additionalEmails': additionalEmails,
      };
}

// ---------------------------------------------------------------------------
// Quorum Fallback Models
// ---------------------------------------------------------------------------

class QuorumFallbackConfigDetails {
  final bool mirrorAllData;
  final bool mirrorUsers;
  final bool mirrorScouting;
  final bool mirrorApiData;
  final bool mirrorCustomAnalytics;
  final bool mirrorConfigs;
  final bool mirrorAlliances;
  final bool mirrorChat;
  final bool mirrorNotificationsSecrets;
  final int scoutingRetentionDays;
  final int syncIntervalSeconds;
  final String sqliteFile;

  const QuorumFallbackConfigDetails({
    this.mirrorAllData = false,
    this.mirrorUsers = true,
    this.mirrorScouting = true,
    this.mirrorApiData = true,
    this.mirrorCustomAnalytics = true,
    this.mirrorConfigs = true,
    this.mirrorAlliances = true,
    this.mirrorChat = true,
    this.mirrorNotificationsSecrets = true,
    this.scoutingRetentionDays = 7,
    this.syncIntervalSeconds = 30,
    this.sqliteFile = "data/quorum_fallback.db",
  });

  factory QuorumFallbackConfigDetails.fromJson(Map<String, dynamic> j) =>
      QuorumFallbackConfigDetails(
        mirrorAllData: j['mirror_all_data'] == true || j['mirrorAllData'] == true,
        mirrorUsers: j['mirror_users'] != false && j['mirrorUsers'] != false,
        mirrorScouting: j['mirror_scouting'] != false && j['mirrorScouting'] != false,
        mirrorApiData: j['mirror_api_data'] != false && j['mirrorApiData'] != false,
        mirrorCustomAnalytics: j['mirror_custom_analytics'] != false && j['mirrorCustomAnalytics'] != false,
        mirrorConfigs: true,
        mirrorAlliances: j['mirror_alliances'] != false && j['mirrorAlliances'] != false,
        mirrorChat: j['mirror_chat'] != false && j['mirrorChat'] != false,
        mirrorNotificationsSecrets: j['mirror_notifications_secrets'] != false && j['mirrorNotificationsSecrets'] != false,
        scoutingRetentionDays: (j['scouting_retention_days'] as num?)?.toInt() ?? (j['scoutingRetentionDays'] as num?)?.toInt() ?? 7,
        syncIntervalSeconds: (j['sync_interval_seconds'] as num?)?.toInt() ?? (j['syncIntervalSeconds'] as num?)?.toInt() ?? 30,
        sqliteFile: j['sqlite_file']?.toString() ?? j['sqliteFile']?.toString() ?? "data/quorum_fallback.db",
      );

  Map<String, dynamic> toJson({String? targetIp}) => {
        if (targetIp != null) 'targetIp': targetIp,
        'mirrorAllData': mirrorAllData,
        'mirrorUsers': mirrorUsers,
        'mirrorScouting': mirrorScouting,
        'mirrorApiData': mirrorApiData,
        'mirrorCustomAnalytics': mirrorCustomAnalytics,
        'mirrorConfigs': mirrorConfigs,
        'mirrorAlliances': mirrorAlliances,
        'mirrorChat': mirrorChat,
        'mirrorNotificationsSecrets': mirrorNotificationsSecrets,
        'scoutingRetentionDays': scoutingRetentionDays,
        'syncIntervalSeconds': syncIntervalSeconds,
        'sqliteFile': sqliteFile,
      };
}

class QuorumFallbackNodeStatus {
  final String nodeIp;
  final bool isLocal;
  final bool enabled;
  final bool isAvailable;
  final bool isActiveServingReads;
  final String status;
  final int databaseSizeBytes;
  final int freeDiskSpaceBytes;
  final int totalDiskSpaceBytes;
  final String? lastSyncTimestamp;
  final QuorumFallbackConfigDetails? config;

  const QuorumFallbackNodeStatus({
    required this.nodeIp,
    required this.isLocal,
    required this.enabled,
    required this.isAvailable,
    required this.isActiveServingReads,
    required this.status,
    required this.databaseSizeBytes,
    required this.freeDiskSpaceBytes,
    required this.totalDiskSpaceBytes,
    this.lastSyncTimestamp,
    this.config,
  });

  factory QuorumFallbackNodeStatus.fromJson(Map<String, dynamic> j) =>
      QuorumFallbackNodeStatus(
        nodeIp: j['nodeIp']?.toString() ?? '',
        isLocal: j['isLocal'] == true,
        enabled: j['enabled'] == true,
        isAvailable: j['isAvailable'] == true,
        isActiveServingReads: j['isActiveServingReads'] == true,
        status: j['status']?.toString() ?? 'unknown',
        databaseSizeBytes: (j['databaseSizeBytes'] as num?)?.toInt() ?? 0,
        freeDiskSpaceBytes: (j['freeDiskSpaceBytes'] as num?)?.toInt() ?? 0,
        totalDiskSpaceBytes: (j['totalDiskSpaceBytes'] as num?)?.toInt() ?? 0,
        lastSyncTimestamp: j['lastSyncTimestamp']?.toString(),
        config: j['config'] != null
            ? QuorumFallbackConfigDetails.fromJson(
                j['config'] as Map<String, dynamic>)
            : null,
      );
}

class QuorumFallbackInspectEvent {
  final String eventKey;
  final String name;
  final String? startDate;
  final String? endDate;
  final int matchCount;
  final int teamCount;
  final int matchScoutingCount;
  final int pitScoutingCount;
  final int qualScoutingCount;

  const QuorumFallbackInspectEvent({
    required this.eventKey,
    required this.name,
    this.startDate,
    this.endDate,
    this.matchCount = 0,
    this.teamCount = 0,
    this.matchScoutingCount = 0,
    this.pitScoutingCount = 0,
    this.qualScoutingCount = 0,
  });

  factory QuorumFallbackInspectEvent.fromJson(Map<String, dynamic> j) =>
      QuorumFallbackInspectEvent(
        eventKey: j['eventKey']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        startDate: j['startDate']?.toString(),
        endDate: j['endDate']?.toString(),
        matchCount: (j['matchCount'] as num?)?.toInt() ?? 0,
        teamCount: (j['teamCount'] as num?)?.toInt() ?? 0,
        matchScoutingCount: (j['matchScoutingCount'] as num?)?.toInt() ?? 0,
        pitScoutingCount: (j['pitScoutingCount'] as num?)?.toInt() ?? 0,
        qualScoutingCount: (j['qualScoutingCount'] as num?)?.toInt() ?? 0,
      );
}

class QuorumFallbackInspection {
  final String nodeIp;
  final String status;
  final int databaseSizeBytes;
  final int freeDiskSpaceBytes;
  final int totalDiskSpaceBytes;
  final String? lastSyncTimestamp;
  final Map<String, int> tableCounts;
  final List<QuorumFallbackInspectEvent> activeEvents;

  const QuorumFallbackInspection({
    required this.nodeIp,
    required this.status,
    this.databaseSizeBytes = 0,
    this.freeDiskSpaceBytes = 0,
    this.totalDiskSpaceBytes = 0,
    this.lastSyncTimestamp,
    this.tableCounts = const {},
    this.activeEvents = const [],
  });

  factory QuorumFallbackInspection.fromJson(Map<String, dynamic> j) =>
      QuorumFallbackInspection(
        nodeIp: j['nodeIp']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        databaseSizeBytes: (j['databaseSizeBytes'] as num?)?.toInt() ?? 0,
        freeDiskSpaceBytes: (j['freeDiskSpaceBytes'] as num?)?.toInt() ?? 0,
        totalDiskSpaceBytes: (j['totalDiskSpaceBytes'] as num?)?.toInt() ?? 0,
        lastSyncTimestamp: j['lastSyncTimestamp']?.toString(),
        tableCounts: (j['tableCounts'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
        activeEvents: (j['activeEvents'] as List<dynamic>? ?? [])
            .map((e) => QuorumFallbackInspectEvent.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Auto-Backup & Database Snapshots (mirrors SnapshotService.kt & Routes.kt)
// ---------------------------------------------------------------------------

class SnapshotInfoDto {
  final String fileName;
  final int sizeBytes;
  final int createdAtEpochMs;
  final bool isAutoBackup;
  final String createdAtUtc;

  const SnapshotInfoDto({
    required this.fileName,
    required this.sizeBytes,
    required this.createdAtEpochMs,
    this.isAutoBackup = false,
    this.createdAtUtc = '',
  });

  factory SnapshotInfoDto.fromJson(Map<String, dynamic> j) => SnapshotInfoDto(
        fileName: j['fileName']?.toString() ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        createdAtEpochMs: (j['createdAtEpochMs'] as num?)?.toInt() ?? 0,
        isAutoBackup: j['isAutoBackup'] == true,
        createdAtUtc: j['createdAtUtc']?.toString() ?? '',
      );
}

class AutoBackupNodeStatus {
  final String nodeIp;
  final bool isLocal;
  final bool enabled;
  final bool isAvailable;
  final String targetTimeUtc;
  final int retentionDays;
  final String storageDirectory;
  final String? lastBackupTimestamp;
  final String? lastBackupTimeUtc;
  final String lastBackupStatus;
  final String? nextScheduledRunUtc;
  final int snapshotCount;
  final int totalStorageBytes;
  final List<SnapshotInfoDto> snapshots;

  const AutoBackupNodeStatus({
    required this.nodeIp,
    required this.isLocal,
    required this.enabled,
    this.isAvailable = true,
    this.targetTimeUtc = '02:54',
    this.retentionDays = 30,
    this.storageDirectory = 'data/snapshots',
    this.lastBackupTimestamp,
    this.lastBackupTimeUtc,
    this.lastBackupStatus = 'None',
    this.nextScheduledRunUtc,
    this.snapshotCount = 0,
    this.totalStorageBytes = 0,
    this.snapshots = const [],
  });

  factory AutoBackupNodeStatus.fromJson(Map<String, dynamic> j) {
    final snapshotsList = (j['snapshots'] as List<dynamic>? ?? [])
        .map((e) => SnapshotInfoDto.fromJson(e as Map<String, dynamic>))
        .toList();
    final count = (j['snapshotCount'] as num?)?.toInt() ??
        (j['snapshotsCount'] as num?)?.toInt() ??
        snapshotsList.length;
    final totalBytes = (j['totalStorageBytes'] as num?)?.toInt() ??
        (j['totalSnapshotsSizeBytes'] as num?)?.toInt() ??
        0;

    return AutoBackupNodeStatus(
      nodeIp: j['nodeIp']?.toString() ?? '',
      isLocal: j['isLocal'] == true,
      enabled: j['enabled'] == true,
      isAvailable: j['isAvailable'] != false,
      targetTimeUtc: j['targetTimeUtc']?.toString() ?? '02:54',
      retentionDays: (j['retentionDays'] as num?)?.toInt() ?? 30,
      storageDirectory: j['storageDirectory']?.toString() ?? 'data/snapshots',
      lastBackupTimestamp: j['lastBackupTimestamp']?.toString(),
      lastBackupTimeUtc: j['lastBackupTimeUtc']?.toString(),
      lastBackupStatus: j['lastBackupStatus']?.toString() ?? 'None',
      nextScheduledRunUtc: j['nextScheduledRunUtc']?.toString(),
      snapshotCount: count,
      totalStorageBytes: totalBytes,
      snapshots: snapshotsList,
    );
  }
}

class AutoBackupCombinedStatus {
  final AutoBackupNodeStatus localNodeStatus;
  final List<AutoBackupNodeStatus> clusterNodes;

  const AutoBackupCombinedStatus({
    required this.localNodeStatus,
    required this.clusterNodes,
  });
}
