// ignore_for_file: non_constant_identifier_names

/// Models for Redis Cache Management & Cluster Topology.
/// Mirrors Kotlin backend models in com.obsidianscout.routes (Models.kt)
/// and RedisClusterCoordinator / ClusterManagementService.

class RedisMemoryAssessment {
  final int totalOsMb;
  final int availableOsMb;
  final int jvmMaxMb;
  final int recommendedRedisMb;
  final String evictionPolicy;

  const RedisMemoryAssessment({
    required this.totalOsMb,
    required this.availableOsMb,
    required this.jvmMaxMb,
    required this.recommendedRedisMb,
    required this.evictionPolicy,
  });

  factory RedisMemoryAssessment.fromJson(Map<String, dynamic> j) =>
      RedisMemoryAssessment(
        totalOsMb: (j['totalOsMb'] as num?)?.toInt() ?? 0,
        availableOsMb: (j['availableOsMb'] as num?)?.toInt() ?? 0,
        jvmMaxMb: (j['jvmMaxMb'] as num?)?.toInt() ?? 0,
        recommendedRedisMb: (j['recommendedRedisMb'] as num?)?.toInt() ?? 0,
        evictionPolicy: j['evictionPolicy']?.toString() ?? 'allkeys-lru',
      );

  Map<String, dynamic> toJson() => {
        'totalOsMb': totalOsMb,
        'availableOsMb': availableOsMb,
        'jvmMaxMb': jvmMaxMb,
        'recommendedRedisMb': recommendedRedisMb,
        'evictionPolicy': evictionPolicy,
      };
}

class RedisStatusResponse {
  final bool isReady;
  final bool isHost;
  final bool canHostRedis;
  final String activeEndpoint;
  final String leaseHolder;
  final int hits;
  final int misses;
  final int stampedesAvoided;
  final int evictions;
  final int redisServerHits;
  final int redisServerMisses;
  final int totalKeys;
  final int usedMemoryBytes;
  final int usedMemoryMb;
  final String usedMemoryHuman;
  final RedisMemoryAssessment memoryAssessment;

  const RedisStatusResponse({
    required this.isReady,
    required this.isHost,
    required this.canHostRedis,
    required this.activeEndpoint,
    required this.leaseHolder,
    required this.hits,
    required this.misses,
    required this.stampedesAvoided,
    required this.evictions,
    required this.redisServerHits,
    required this.redisServerMisses,
    required this.totalKeys,
    required this.usedMemoryBytes,
    required this.usedMemoryMb,
    required this.usedMemoryHuman,
    required this.memoryAssessment,
  });

  factory RedisStatusResponse.fromJson(Map<String, dynamic> j) =>
      RedisStatusResponse(
        isReady: j['is_ready'] == true,
        isHost: j['is_host'] == true,
        canHostRedis: j['can_host_redis'] == true,
        activeEndpoint: j['active_endpoint']?.toString() ?? 'None',
        leaseHolder: j['lease_holder']?.toString() ?? 'None',
        hits: (j['hits'] as num?)?.toInt() ?? 0,
        misses: (j['misses'] as num?)?.toInt() ?? 0,
        stampedesAvoided: (j['stampedes_avoided'] as num?)?.toInt() ?? 0,
        evictions: (j['evictions'] as num?)?.toInt() ?? 0,
        redisServerHits: (j['redis_server_hits'] as num?)?.toInt() ?? 0,
        redisServerMisses: (j['redis_server_misses'] as num?)?.toInt() ?? 0,
        totalKeys: (j['total_keys'] as num?)?.toInt() ?? 0,
        usedMemoryBytes: (j['used_memory_bytes'] as num?)?.toInt() ?? 0,
        usedMemoryMb: (j['used_memory_mb'] as num?)?.toInt() ?? 0,
        usedMemoryHuman: j['used_memory_human']?.toString() ?? '0 MB',
        memoryAssessment: j['memory_assessment'] is Map<String, dynamic>
            ? RedisMemoryAssessment.fromJson(
                j['memory_assessment'] as Map<String, dynamic>)
            : const RedisMemoryAssessment(
                totalOsMb: 0,
                availableOsMb: 0,
                jvmMaxMb: 0,
                recommendedRedisMb: 0,
                evictionPolicy: 'allkeys-lru',
              ),
      );

  Map<String, dynamic> toJson() => {
        'is_ready': isReady,
        'is_host': isHost,
        'can_host_redis': canHostRedis,
        'active_endpoint': activeEndpoint,
        'lease_holder': leaseHolder,
        'hits': hits,
        'misses': misses,
        'stampedes_avoided': stampedesAvoided,
        'evictions': evictions,
        'redis_server_hits': redisServerHits,
        'redis_server_misses': redisServerMisses,
        'total_keys': totalKeys,
        'used_memory_bytes': usedMemoryBytes,
        'used_memory_mb': usedMemoryMb,
        'used_memory_human': usedMemoryHuman,
        'memory_assessment': memoryAssessment.toJson(),
      };
}

class RedisNodeConfigDto {
  final String nodeIp;
  final bool isLocal;
  final bool reachable;
  final String? error;
  final bool enabled;
  final bool requirePassword;
  final String host;
  final int port;
  final bool passwordSet;
  final double maxMemoryPercent;
  final int minMemoryMb;
  final int maxMemoryMb;
  final bool isReady;
  final bool isHost;
  final bool canHostRedis;
  final String? installProgress;

  const RedisNodeConfigDto({
    required this.nodeIp,
    required this.isLocal,
    this.reachable = true,
    this.error,
    this.enabled = false,
    this.requirePassword = true,
    this.host = '',
    this.port = 6379,
    this.passwordSet = false,
    this.maxMemoryPercent = 0.40,
    this.minMemoryMb = 64,
    this.maxMemoryMb = 8192,
    this.isReady = false,
    this.isHost = false,
    this.canHostRedis = false,
    this.installProgress,
  });

  factory RedisNodeConfigDto.fromJson(Map<String, dynamic> j) =>
      RedisNodeConfigDto(
        nodeIp: j['nodeIp']?.toString() ?? '',
        isLocal: j['isLocal'] == true,
        reachable: j['reachable'] != false,
        error: j['error']?.toString(),
        enabled: j['enabled'] == true,
        requirePassword: j['requirePassword'] != false,
        host: j['host']?.toString() ?? '',
        port: (j['port'] as num?)?.toInt() ?? 6379,
        passwordSet: j['passwordSet'] == true,
        maxMemoryPercent: (j['maxMemoryPercent'] as num?)?.toDouble() ?? 0.40,
        minMemoryMb: (j['minMemoryMb'] as num?)?.toInt() ?? 64,
        maxMemoryMb: (j['maxMemoryMb'] as num?)?.toInt() ?? 8192,
        isReady: j['isReady'] == true,
        isHost: j['isHost'] == true,
        canHostRedis: j['canHostRedis'] == true,
        installProgress: j['installProgress']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'nodeIp': nodeIp,
        'isLocal': isLocal,
        'reachable': reachable,
        'error': error,
        'enabled': enabled,
        'requirePassword': requirePassword,
        'host': host,
        'port': port,
        'passwordSet': passwordSet,
        'maxMemoryPercent': maxMemoryPercent,
        'minMemoryMb': minMemoryMb,
        'maxMemoryMb': maxMemoryMb,
        'isReady': isReady,
        'isHost': isHost,
        'canHostRedis': canHostRedis,
        'installProgress': installProgress,
      };
}

class RedisConfigUpdateRequest {
  final bool? enabled;
  final bool? requirePassword;
  final String? host;
  final int? port;
  final String? password;
  final bool clearPassword;
  final double? maxMemoryPercent;
  final int? minMemoryMb;
  final int? maxMemoryMb;

  const RedisConfigUpdateRequest({
    this.enabled,
    this.requirePassword,
    this.host,
    this.port,
    this.password,
    this.clearPassword = false,
    this.maxMemoryPercent,
    this.minMemoryMb,
    this.maxMemoryMb,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'clearPassword': clearPassword,
    };
    if (enabled != null) m['enabled'] = enabled;
    if (requirePassword != null) m['requirePassword'] = requirePassword;
    if (host != null) m['host'] = host;
    if (port != null) m['port'] = port;
    if (password != null) m['password'] = password;
    if (maxMemoryPercent != null) m['maxMemoryPercent'] = maxMemoryPercent;
    if (minMemoryMb != null) m['minMemoryMb'] = minMemoryMb;
    if (maxMemoryMb != null) m['maxMemoryMb'] = maxMemoryMb;
    return m;
  }
}

class RedisClusterNodeResult {
  final String targetIp;
  final bool success;
  final String? message;

  const RedisClusterNodeResult({
    required this.targetIp,
    required this.success,
    this.message,
  });

  factory RedisClusterNodeResult.fromJson(Map<String, dynamic> j) =>
      RedisClusterNodeResult(
        targetIp: j['targetIp']?.toString() ?? '',
        success: j['success'] == true,
        message: j['message']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'targetIp': targetIp,
        'success': success,
        'message': message,
      };
}
