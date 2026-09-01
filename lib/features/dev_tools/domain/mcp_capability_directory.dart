import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/platform_storage_layout.dart';
import 'harness_tool_bridge.dart';
import 'lan_peer_discovery_service.dart';
import 'local_mcp_stdio_client.dart';
import 'lmcp_remote_client.dart';
import 'lmcp_capacity_manager.dart';
import 'mcp_capability_models.dart';
import 'mcp_commander_scheduler.dart';
import 'mcp_device_identity.dart';
import 'mcp_tool_reputation_store.dart';

/// Maintains the live MCP catalog shared by the Harness planner and its UI.
///
/// Other local processes publish one JSON file per provider in the stable app
/// cache MCP registration directory. Files are reread atomically; malformed or
/// stale registrations never replace the last valid snapshot.
class McpCapabilityDirectory {
  McpCapabilityDirectory({
    Directory? registrationDirectory,
    LmcpRemoteClient? remoteClient,
    LanPeerDiscoveryService? discoveryService,
    McpToolReputationStore? reputationStore,
    LocalMcpStdioClient? localClient,
  }) : registrationDirectory =
           registrationDirectory ?? defaultRegistrationDirectory(),
       _remoteClient = remoteClient ?? LmcpRemoteClient(),
       _discoveryService = discoveryService ?? LanPeerDiscoveryService.instance,
       _reputationStore = reputationStore ?? McpToolReputationStore.instance,
       _localClient = localClient ?? const LocalMcpStdioClient();

  static final McpCapabilityDirectory instance = McpCapabilityDirectory();

  static Directory defaultRegistrationDirectory() => Directory(
    '${PlatformStorageLayout.current().cacheDirectory}'
    '${Platform.pathSeparator}mcp${Platform.pathSeparator}registrations',
  );

  final Directory registrationDirectory;
  final LmcpRemoteClient _remoteClient;
  final LanPeerDiscoveryService _discoveryService;
  final McpToolReputationStore _reputationStore;
  final LocalMcpStdioClient _localClient;
  final LmcpCapacityLeaseManager _appCapacity = LmcpCapacityLeaseManager(
    capacity: 8,
  );
  VibekitsHarnessToolBridge? _appBridge;
  final StreamController<McpCapabilitySnapshot> _changes =
      StreamController<McpCapabilitySnapshot>.broadcast();
  StreamSubscription<List<VibekitsLanPeer>>? _lanSubscription;
  Timer? _localRefreshTimer;
  List<McpDeviceCapability> _app = const <McpDeviceCapability>[];
  List<McpDeviceCapability> _local = const <McpDeviceCapability>[];
  List<McpDeviceCapability> _lan = const <McpDeviceCapability>[];
  Map<String, VibekitsLanPeer> _lanPeers = <String, VibekitsLanPeer>{};
  final Map<String, List<McpToolInterface>> _remoteTools =
      <String, List<McpToolInterface>>{};
  final Map<String, String> _remoteCatalogKeys = <String, String>{};
  final Map<String, String> _loadingCatalogKeys = <String, String>{};
  final Map<String, String> _remoteCatalogErrors = <String, String>{};
  final Map<String, String> _remoteCatalogErrorCodes = <String, String>{};
  final Map<String, DateTime> _remoteRetryAfter = <String, DateTime>{};
  final Map<String, String> _remoteFailureKeys = <String, String>{};
  int _version = 0;
  bool _started = false;

  Stream<McpCapabilitySnapshot> get changes => _changes.stream;
  McpCapabilitySnapshot get snapshot => McpCapabilitySnapshot(
    version: _version,
    app: _app,
    local: _local,
    lan: _lan,
    updatedAt: DateTime.now(),
  );

  Future<void> start({required VibekitsHarnessToolBridge appBridge}) async {
    _appBridge = appBridge;
    _app = <McpDeviceCapability>[
      McpDeviceCapability(
        id: 'vibekits-app',
        name: 'VibeKits',
        appId: 'com.vibekits.desktop',
        appVersion: VibekitsHarnessToolBridge.protocolVersion,
        tier: McpCapabilityTier.app,
        transport: 'in-process',
        endpoint: 'VibekitsHarnessToolBridge',
        tools: <McpToolInterface>[
          for (final HarnessToolDefinition tool in appBridge.executableCatalog)
            McpToolInterface(
              name: tool.id,
              title: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema,
              risk: tool.risk.name,
            ),
          ..._schedulingToolInterfaces,
        ],
        lastUpdated: DateTime.now(),
        runtime: _appCapacity.runtime,
      ),
    ];
    if (!_started) {
      StreamSubscription<List<VibekitsLanPeer>>? subscription;
      Timer? refreshTimer;
      try {
        // Local stdio registrations are optional. A read-only or temporarily
        // unavailable cache must never disable independent LAN discovery.
        try {
          await registrationDirectory.create(recursive: true);
        } on Object {
          // refreshLocal treats a missing directory as an empty local tier.
        }
        subscription = _discoveryService.changes.listen(_updateLan);
        refreshTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(refreshLocal()),
        );
        _lanSubscription = subscription;
        _localRefreshTimer = refreshTimer;
        _started = true;
      } on Object {
        refreshTimer?.cancel();
        await subscription?.cancel();
        _lanSubscription = null;
        _localRefreshTimer = null;
        _started = false;
        rethrow;
      }
    }
    await refreshLocal();
    _updateLan(_discoveryService.peers);
  }

  /// Called for every new task that needs tools. The returned immutable
  /// snapshot is always ordered APP -> local process -> LAN.
  Future<McpCapabilitySnapshot> snapshotForTask() async {
    await refreshLocal();
    return snapshot;
  }

  /// Complete, model-readable catalog. Nothing is promoted to callable until
  /// an LMCP/2 catalog has passed TLS pinning and digest verification.
  Future<Map<String, Object?>> exportForHarness() async {
    final McpCapabilitySnapshot current = await snapshotForTask();
    final Map<String, McpToolReputation> reputations = await _reputationStore
        .load();
    McpToolReputation reputation(
      McpDeviceCapability device,
      McpToolInterface tool,
    ) =>
        reputations[McpToolReputationStore.key(
          device.tier,
          device.id,
          tool.name,
        )] ??
        McpToolReputation.initial(
          tier: device.tier,
          instanceId: device.id,
          toolName: tool.name,
        );
    Map<String, Object?> deviceJson(McpDeviceCapability device) {
      final String? catalogErrorCode = _remoteCatalogErrorCodes[device.id];
      final bool? endpointReachable = catalogErrorCode == null
          ? (device.callable ? true : null)
          : catalogErrorCode != 'connection_failed' &&
                catalogErrorCode != 'timeout';
      final String catalogState = device.callable
          ? 'verified'
          : catalogErrorCode == null
          ? 'verifying'
          : endpointReachable == true
          ? 'rejected'
          : 'unreachable';
      final List<McpToolInterface> tools = device.tools.toList()
        ..sort((McpToolInterface left, McpToolInterface right) {
          final int byScore = reputation(
            device,
            right,
          ).score.compareTo(reputation(device, left).score);
          return byScore != 0 ? byScore : left.name.compareTo(right.name);
        });
      return <String, Object?>{
        'instanceId': device.id,
        'name': device.name,
        'appId': device.appId,
        'appVersion': device.appVersion,
        'tier': device.tier.name,
        'online': device.online,
        'transport': device.transport,
        'endpoint': device.endpoint,
        'catalogRevision': device.catalogRevision,
        'callable': device.callable,
        'schedulable': device.schedulable,
        'runtime': device.runtime.toJson(),
        if (device.tier == McpCapabilityTier.lan) ...<String, Object?>{
          'discoveryAlive': device.online,
          'endpointReachable': endpointReachable,
          'catalogState': catalogState,
          'catalogErrorCode': ?catalogErrorCode,
        },
        if (device.tier == McpCapabilityTier.lan &&
            _remoteCatalogErrors.containsKey(device.id))
          'catalogError': _remoteCatalogErrors[device.id]!,
        'tools': <Map<String, Object?>>[
          for (final McpToolInterface tool in tools)
            <String, Object?>{
              ...tool.toJson(),
              'reputation': reputation(device, tool).toJson(),
            },
        ],
      };
    }

    return <String, Object?>{
      'version': current.version,
      'updatedAt': current.updatedAt.toUtc().toIso8601String(),
      'routingRule': '固定优先级：本机 VibeKits MCP(app) → 本地其他进程 MCP(local) → 局域网 MCP(lan)。只有同一层的同类候选工具才按 reputation.score 从高到低选择；低分/garbage 工具降权但不隐藏。仅 callable=true 的局域网实例可交给 vibekits.mcp.tool_call，评分不得绕过权限审批。',
      'rankingPolicy': <String, Object?>{
        'tierOrder': const <String>['app', 'local', 'lan'],
        'withinTier': 'reputation.score DESC, toolName ASC',
        'newToolScore': 60,
        'garbageThreshold': 30,
        'memoryScope': 'global-across-projects-sessions-restarts',
      },
      'tiers': <String, Object?>{
        'app': current.app.map(deviceJson).toList(growable: false),
        'local': current.local.map(deviceJson).toList(growable: false),
        'lan': current.lan.map(deviceJson).toList(growable: false),
      },
    };
  }

  /// Invokes a tool only after it has appeared in the authenticated LMCP/2
  /// catalog for the latest discovery revision.
  Future<Map<String, Object?>> invokeLanTool({
    required String instanceId,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final VibekitsLanPeer? peer = _lanPeers[instanceId];
    if (peer == null) {
      throw const LmcpRemoteException('peer_offline', '局域网 MCP 节点已经离线');
    }
    final List<McpToolInterface> tools = _remoteTools[instanceId] ?? peer.tools;
    if (!tools.any((McpToolInterface tool) => tool.name == toolName)) {
      throw const LmcpRemoteException('tool_not_in_catalog', '请求的工具不在当前远端目录中');
    }
    if (peer.serviceRole == 'harness-controller') {
      throw const LmcpRemoteException(
        'approval_required',
        '远程 Harness 控制必须先经过被调用端明确审批',
      );
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final Map<String, Object?> result = await _remoteClient.callTool(
        peer: peer,
        name: toolName,
        arguments: arguments,
      );
      final double quality = inferMcpCompletionQuality(result);
      await _reputationStore.record(
        tier: McpCapabilityTier.lan,
        instanceId: instanceId,
        toolName: toolName,
        succeeded: quality > 0,
        completionQuality: quality,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      return result;
    } on Object {
      await _reputationStore.record(
        tier: McpCapabilityTier.lan,
        instanceId: instanceId,
        toolName: toolName,
        succeeded: false,
        completionQuality: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> invokeTool({
    required String instanceId,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final McpDeviceCapability? local = _local
        .where((McpDeviceCapability device) => device.id == instanceId)
        .firstOrNull;
    if (local == null) {
      return invokeLanTool(
        instanceId: instanceId,
        toolName: toolName,
        arguments: arguments,
      );
    }
    if (!local.callable) {
      throw const LocalMcpException(
        'local_not_callable',
        '本地 MCP 未提供可调用的 stdio 端点',
      );
    }
    if (!local.tools.any((McpToolInterface tool) => tool.name == toolName)) {
      throw const LocalMcpException('tool_not_in_catalog', '请求工具不在本地注册目录中');
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final Map<String, Object?> result = await _localClient.callTool(
        executable: local.endpoint,
        launchArguments: local.launchArguments,
        toolName: toolName,
        arguments: arguments,
      );
      final double quality = inferMcpCompletionQuality(result);
      await _reputationStore.record(
        tier: McpCapabilityTier.local,
        instanceId: instanceId,
        toolName: toolName,
        succeeded: quality > 0,
        completionQuality: quality,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      return result;
    } on Object {
      await _reputationStore.record(
        tier: McpCapabilityTier.local,
        instanceId: instanceId,
        toolName: toolName,
        succeeded: false,
        completionQuality: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  Future<void> recordAppToolResult({
    required String toolName,
    required bool succeeded,
    required double completionQuality,
    required int latencyMs,
  }) => _reputationStore.record(
    tier: McpCapabilityTier.app,
    instanceId: 'vibekits-app',
    toolName: toolName,
    succeeded: succeeded,
    completionQuality: completionQuality,
    latencyMs: latencyMs,
  );

  Future<Map<String, Object?>> exportReputations() async {
    final List<McpToolReputation> entries =
        (await _reputationStore.load()).values.toList()
          ..sort((McpToolReputation a, McpToolReputation b) {
            final int tier = a.tier.index.compareTo(b.tier.index);
            if (tier != 0) return tier;
            final int score = b.score.compareTo(a.score);
            return score != 0 ? score : a.toolName.compareTo(b.toolName);
          });
    return <String, Object?>{
      'tierOrder': const <String>['app', 'local', 'lan'],
      'entries': entries
          .map((McpToolReputation item) => item.toJson())
          .toList(growable: false),
    };
  }

  Future<Map<String, Object?>> planScheduledTool({
    required String toolName,
    required String taskId,
  }) async {
    final String normalizedTool = toolName.trim();
    final String normalizedTask = taskId.trim();
    if (normalizedTool.isEmpty || normalizedTask.isEmpty) {
      throw const FormatException('toolName 和 taskId 均为必填项');
    }
    final McpCapabilitySnapshot current = await snapshotForTask();
    final Map<String, McpToolReputation> reputations = await _reputationStore
        .load();
    final List<McpSchedulingCandidate> ranked = McpCommanderScheduler.rank(
      devices: current.inHarnessSearchOrder,
      toolName: normalizedTool,
      taskId: normalizedTask,
      reputations: reputations,
    );
    return <String, Object?>{
      'schemaVersion': 1,
      'toolName': normalizedTool,
      'taskId': normalizedTask,
      'candidateCount': ranked.length,
      'selected': ranked.isEmpty ? null : ranked.first.toJson(),
      'candidates': ranked
          .map((McpSchedulingCandidate item) => item.toJson())
          .toList(growable: false),
      'reservationRequired': true,
      'nextAction': ranked.isEmpty
          ? '没有同时满足身份、目录、实时容量和租约工具合同的作战单位'
          : '必须先对 selected 调用 lmcp.capacity.reserve；不得凭 UDP idle 直接执行',
    };
  }

  /// Performs the commander protocol end-to-end: rank, atomically reserve,
  /// invoke with the lease binding, and always release. A busy candidate is
  /// skipped without making the business call.
  Future<Map<String, Object?>> scheduleAndInvoke({
    required String toolName,
    required String taskId,
    required String idempotencyKey,
    required String scopeDigest,
    Map<String, Object?> arguments = const <String, Object?>{},
    int requestedSlots = 1,
    int ttlSeconds = 45,
  }) async {
    final String normalizedTool = toolName.trim();
    final String normalizedTask = taskId.trim();
    final String normalizedKey = idempotencyKey.trim();
    final String normalizedScope = scopeDigest.trim();
    if (normalizedTool.isEmpty ||
        normalizedTask.isEmpty ||
        normalizedKey.isEmpty ||
        normalizedScope.isEmpty ||
        requestedSlots < 1 ||
        ttlSeconds < 10 ||
        ttlSeconds > 120) {
      throw const FormatException('自动调度参数无效');
    }
    if (normalizedTool == VibekitsHarnessToolBridge.mcpAutoCallId ||
        normalizedTool.startsWith('lmcp.capacity.') ||
        normalizedTool == 'lmcp.node.status') {
      throw const FormatException('自动调度不能递归调用调度控制工具');
    }
    final McpCapabilitySnapshot current = await snapshotForTask();
    final Map<String, McpToolReputation> reputations = await _reputationStore
        .load();
    final List<McpSchedulingCandidate> ranked = McpCommanderScheduler.rank(
      devices: current.inHarnessSearchOrder,
      toolName: normalizedTool,
      taskId: normalizedTask,
      reputations: reputations,
    );
    final String commanderId = McpDeviceIdentity.forVibekits().instanceId;
    final List<Map<String, Object?>> attempts = <Map<String, Object?>>[];
    for (final McpSchedulingCandidate candidate in ranked) {
      if (candidate.device.tier == McpCapabilityTier.app) {
        final VibekitsHarnessToolBridge? bridge = _appBridge;
        if (bridge == null) continue;
        Map<String, Object?>? lease;
        try {
          lease = _appCapacity.reserve(
            toolName: normalizedTool,
            idempotencyKey: normalizedKey,
            commanderId: commanderId,
            requestedSlots: requestedSlots,
            ttlSeconds: ttlSeconds,
            scopeDigest: normalizedScope,
            callerInstanceId: commanderId,
          );
          final Stopwatch stopwatch = Stopwatch()..start();
          final HarnessToolCallResult invoked = await bridge.invoke(
            toolId: normalizedTool,
            arguments: arguments,
            preauthorized: true,
            approve: (_) async => true,
          );
          final Map<String, Object?> business = <String, Object?>{
            'isError': !invoked.ok,
            'instanceId': 'vibekits-app',
            'tool': normalizedTool,
            'structuredContent': invoked.toJson(),
          };
          final double quality = inferMcpCompletionQuality(business);
          await _reputationStore.record(
            tier: McpCapabilityTier.app,
            instanceId: 'vibekits-app',
            toolName: normalizedTool,
            succeeded: invoked.ok,
            completionQuality: quality,
            latencyMs: stopwatch.elapsedMilliseconds,
          );
          final String leaseId = '${lease['leaseId']}';
          attempts.add(<String, Object?>{
            'instanceId': candidate.device.id,
            'outcome': invoked.ok ? 'completed' : 'tool-error',
            'leaseId': leaseId,
          });
          return <String, Object?>{
            'schemaVersion': 1,
            'ok': invoked.ok,
            'toolName': normalizedTool,
            'taskId': normalizedTask,
            'selected': candidate.toJson(),
            'leaseId': leaseId,
            'attempts': attempts,
            'result': business,
            'redactedFields': const <String>['leaseToken'],
          };
        } finally {
          if (lease != null) {
            _appCapacity.release(
              leaseId: '${lease['leaseId']}',
              leaseToken: '${lease['leaseToken']}',
              callerInstanceId: commanderId,
              reason: 'caller-finished',
            );
            _app = <McpDeviceCapability>[
              for (final McpDeviceCapability device in _app)
                McpDeviceCapability(
                  id: device.id,
                  name: device.name,
                  appId: device.appId,
                  appVersion: device.appVersion,
                  tier: device.tier,
                  transport: device.transport,
                  endpoint: device.endpoint,
                  tools: device.tools,
                  lastUpdated: DateTime.now(),
                  runtime: _appCapacity.runtime,
                ),
            ];
            _emit();
          }
        }
      }
      if (candidate.device.tier == McpCapabilityTier.local) {
        Map<String, Object?>? lease;
        try {
          final Map<String, Object?> reserve = await _localClient.callTool(
            executable: candidate.device.endpoint,
            launchArguments: candidate.device.launchArguments,
            toolName: 'lmcp.capacity.reserve',
            arguments: <String, Object?>{
              'toolName': normalizedTool,
              'idempotencyKey': normalizedKey,
              'commanderId': commanderId,
              'requestedSlots': requestedSlots,
              'ttlSeconds': ttlSeconds,
              'scopeDigest': normalizedScope,
            },
          );
          final Map<String, Object?> reserveData = _structuredContent(reserve);
          if (reserve['isError'] == true || reserveData['ok'] != true) {
            attempts.add(<String, Object?>{
              'instanceId': candidate.device.id,
              'outcome': 'reserve-rejected',
              'code': _structuredErrorCode(reserveData),
            });
            continue;
          }
          lease = reserveData;
          final String leaseId = '${lease['leaseId'] ?? ''}';
          final String leaseToken = '${lease['leaseToken'] ?? ''}';
          if (leaseId.isEmpty || leaseToken.isEmpty) continue;
          final Stopwatch stopwatch = Stopwatch()..start();
          final Map<String, Object?> result = await _localClient.callTool(
            executable: candidate.device.endpoint,
            launchArguments: candidate.device.launchArguments,
            toolName: normalizedTool,
            arguments: arguments,
            scheduling: <String, Object?>{
              'leaseId': leaseId,
              'leaseToken': leaseToken,
              'idempotencyKey': normalizedKey,
            },
          );
          final double quality = inferMcpCompletionQuality(result);
          await _reputationStore.record(
            tier: McpCapabilityTier.local,
            instanceId: candidate.device.id,
            toolName: normalizedTool,
            succeeded: quality > 0,
            completionQuality: quality,
            latencyMs: stopwatch.elapsedMilliseconds,
          );
          attempts.add(<String, Object?>{
            'instanceId': candidate.device.id,
            'outcome': result['isError'] == true ? 'tool-error' : 'completed',
            'leaseId': leaseId,
          });
          return <String, Object?>{
            'schemaVersion': 1,
            'ok': result['isError'] != true,
            'toolName': normalizedTool,
            'taskId': normalizedTask,
            'selected': candidate.toJson(),
            'leaseId': leaseId,
            'attempts': attempts,
            'result': result,
            'redactedFields': const <String>['leaseToken'],
          };
        } on Object catch (error) {
          attempts.add(<String, Object?>{
            'instanceId': candidate.device.id,
            'outcome': 'transport-error',
            'error': error.runtimeType.toString(),
          });
        } finally {
          if (lease != null) {
            try {
              await _localClient.callTool(
                executable: candidate.device.endpoint,
                launchArguments: candidate.device.launchArguments,
                toolName: 'lmcp.capacity.release',
                arguments: <String, Object?>{
                  'leaseId': lease['leaseId'],
                  'leaseToken': lease['leaseToken'],
                  'reason': 'caller-finished',
                },
              );
            } on Object {
              // TTL is the final cleanup boundary for a lost local response.
            }
          }
        }
        continue;
      }
      final VibekitsLanPeer? peer = _lanPeers[candidate.device.id];
      if (peer == null) {
        attempts.add(<String, Object?>{
          'instanceId': candidate.device.id,
          'outcome': 'offline-before-reserve',
        });
        continue;
      }
      Map<String, Object?>? lease;
      try {
        final Map<String, Object?> reserve = await _remoteClient.callTool(
          peer: peer,
          name: 'lmcp.capacity.reserve',
          arguments: <String, Object?>{
            'toolName': normalizedTool,
            'idempotencyKey': normalizedKey,
            'commanderId': commanderId,
            'requestedSlots': requestedSlots,
            'ttlSeconds': ttlSeconds,
            'scopeDigest': normalizedScope,
          },
        );
        final Map<String, Object?> reserveData = _structuredContent(reserve);
        if (reserve['isError'] == true || reserveData['ok'] != true) {
          attempts.add(<String, Object?>{
            'instanceId': candidate.device.id,
            'outcome': 'reserve-rejected',
            'code': _structuredErrorCode(reserveData),
          });
          continue;
        }
        lease = reserveData;
        final String leaseId = '${lease['leaseId'] ?? ''}';
        final String leaseToken = '${lease['leaseToken'] ?? ''}';
        if (leaseId.isEmpty || leaseToken.isEmpty) {
          attempts.add(<String, Object?>{
            'instanceId': candidate.device.id,
            'outcome': 'invalid-reserve-response',
          });
          continue;
        }
        final Stopwatch stopwatch = Stopwatch()..start();
        final Map<String, Object?> result = await _remoteClient.callTool(
          peer: peer,
          name: normalizedTool,
          arguments: arguments,
          scheduling: <String, Object?>{
            'leaseId': leaseId,
            'leaseToken': leaseToken,
            'idempotencyKey': normalizedKey,
          },
        );
        final double quality = inferMcpCompletionQuality(result);
        await _reputationStore.record(
          tier: candidate.device.tier,
          instanceId: candidate.device.id,
          toolName: normalizedTool,
          succeeded: quality > 0,
          completionQuality: quality,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
        attempts.add(<String, Object?>{
          'instanceId': candidate.device.id,
          'outcome': result['isError'] == true ? 'tool-error' : 'completed',
          'leaseId': leaseId,
        });
        return <String, Object?>{
          'schemaVersion': 1,
          'ok': result['isError'] != true,
          'toolName': normalizedTool,
          'taskId': normalizedTask,
          'selected': candidate.toJson(),
          'leaseId': leaseId,
          'attempts': attempts,
          'result': result,
          'redactedFields': const <String>['leaseToken'],
        };
      } on Object catch (error) {
        attempts.add(<String, Object?>{
          'instanceId': candidate.device.id,
          'outcome': 'transport-error',
          'error': error.runtimeType.toString(),
        });
      } finally {
        if (lease != null) {
          final String leaseId = '${lease['leaseId'] ?? ''}';
          final String leaseToken = '${lease['leaseToken'] ?? ''}';
          if (leaseId.isNotEmpty && leaseToken.isNotEmpty) {
            try {
              await _remoteClient.callTool(
                peer: peer,
                name: 'lmcp.capacity.release',
                arguments: <String, Object?>{
                  'leaseId': leaseId,
                  'leaseToken': leaseToken,
                  'reason': 'caller-finished',
                },
              );
            } on Object {
              // The short lease is the final cleanup boundary if the release
              // response is lost. Credentials are intentionally not surfaced.
            }
          }
        }
      }
    }
    return <String, Object?>{
      'schemaVersion': 1,
      'ok': false,
      'toolName': normalizedTool,
      'taskId': normalizedTask,
      'code': ranked.isEmpty ? 'NO_ELIGIBLE_NODE' : 'ALL_NODES_UNAVAILABLE',
      'attempts': attempts,
    };
  }

  static Map<String, Object?> _structuredContent(Map<String, Object?> result) =>
      result['structuredContent'] is Map
      ? Map<String, Object?>.from(result['structuredContent']! as Map)
      : <String, Object?>{};

  static String _structuredErrorCode(Map<String, Object?> structured) {
    final Object? error = structured['error'];
    return error is Map ? '${error['code'] ?? 'UNKNOWN'}' : 'UNKNOWN';
  }

  Future<Map<String, McpToolReputation>> loadReputations() =>
      _reputationStore.load();

  Future<Map<String, Object?>> rateTool({
    required String tierName,
    required String instanceId,
    required String toolName,
    required int rating,
  }) async {
    final McpCapabilityTier? tier = McpCapabilityTier.values
        .where((McpCapabilityTier item) => item.name == tierName)
        .firstOrNull;
    if (tier == null) throw const FormatException('tier 仅支持 app/local/lan');
    final McpToolReputation result = await _reputationStore.rate(
      tier: tier,
      instanceId: instanceId.trim(),
      toolName: toolName.trim(),
      rating: rating,
    );
    return result.toJson();
  }

  Future<void> refreshLocal() async {
    if (!await registrationDirectory.exists()) return;
    final List<McpDeviceCapability> next = <McpDeviceCapability>[];
    await for (final FileSystemEntity entity in registrationDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final Object? decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final McpDeviceCapability? device = _parseProvider(
          decoded,
          McpCapabilityTier.local,
        );
        if (device != null) next.add(device);
      } on Object {
        // A provider can be replacing its atomic registration file.
      }
    }
    next.sort(
      (McpDeviceCapability a, McpDeviceCapability b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (_signature(next) != _signature(_local)) {
      _local = List<McpDeviceCapability>.unmodifiable(next);
      _emit();
    }
  }

  void _updateLan(List<VibekitsLanPeer> peers) {
    _lanPeers = <String, VibekitsLanPeer>{
      for (final VibekitsLanPeer peer in peers) peer.instanceId: peer,
    };
    final Set<String> online = _lanPeers.keys.toSet();
    _remoteTools.removeWhere((String id, _) => !online.contains(id));
    _remoteCatalogKeys.removeWhere((String id, _) => !online.contains(id));
    _loadingCatalogKeys.removeWhere((String id, _) => !online.contains(id));
    _remoteCatalogErrors.removeWhere((String id, _) => !online.contains(id));
    _remoteCatalogErrorCodes.removeWhere(
      (String id, _) => !online.contains(id),
    );
    _remoteRetryAfter.removeWhere((String id, _) => !online.contains(id));
    _remoteFailureKeys.removeWhere((String id, _) => !online.contains(id));
    for (final VibekitsLanPeer peer in peers) {
      if (!peer.supportsLmcp2Calls) continue;
      final String key = _remoteCatalogKey(peer);
      final DateTime? retryAfter = _remoteRetryAfter[peer.instanceId];
      final bool sameFailedCatalog = _remoteFailureKeys[peer.instanceId] == key;
      if (_remoteCatalogKeys[peer.instanceId] == key ||
          _loadingCatalogKeys[peer.instanceId] == key ||
          (sameFailedCatalog &&
              retryAfter != null &&
              DateTime.now().isBefore(retryAfter))) {
        continue;
      }
      unawaited(_loadRemoteCatalog(peer, key));
    }
    final List<McpDeviceCapability> next = <McpDeviceCapability>[
      for (final VibekitsLanPeer peer in peers)
        McpDeviceCapability(
          id: peer.instanceId,
          name: peer.name,
          appId: peer.appId,
          appVersion: peer.appVersion,
          tier: McpCapabilityTier.lan,
          transport: peer.transport,
          endpoint: peer.supportsLmcp2Calls
              ? peer.callUri.toString()
              : '${peer.address}:${peer.port}',
          tools: _remoteTools[peer.instanceId] ?? peer.tools,
          lastUpdated: peer.lastSeen,
          catalogRevision: peer.catalogRevision.isNotEmpty
              ? peer.catalogRevision
              : peer.capabilityDigest,
          hardwareCode: peer.hardwareCode,
          runtime: peer.runtime,
        ),
    ];
    if (_signature(next) != _signature(_lan)) {
      _lan = List<McpDeviceCapability>.unmodifiable(next);
      _emit();
    }
  }

  Future<void> _loadRemoteCatalog(
    VibekitsLanPeer peer,
    String catalogKey,
  ) async {
    _loadingCatalogKeys[peer.instanceId] = catalogKey;
    try {
      final List<McpToolInterface> tools = await _remoteClient.loadTools(peer);
      final VibekitsLanPeer? current = _lanPeers[peer.instanceId];
      if (current == null || _remoteCatalogKey(current) != catalogKey) return;
      _remoteTools[peer.instanceId] = tools;
      _remoteCatalogKeys[peer.instanceId] = catalogKey;
      _remoteCatalogErrors.remove(peer.instanceId);
      _remoteCatalogErrorCodes.remove(peer.instanceId);
      _remoteRetryAfter.remove(peer.instanceId);
      _remoteFailureKeys.remove(peer.instanceId);
      _updateLan(_lanPeers.values.toList(growable: false));
    } on Object catch (error) {
      // Discovery heartbeats retry failed authenticated catalogs. A failed
      // node remains visible without tools and is never treated as callable.
      _remoteCatalogErrors[peer.instanceId] = '$error';
      _remoteCatalogErrorCodes[peer.instanceId] = error is LmcpRemoteException
          ? error.code
          : 'catalog_load_failed';
      _remoteFailureKeys[peer.instanceId] = catalogKey;
      _remoteRetryAfter[peer.instanceId] = DateTime.now().add(
        const Duration(seconds: 5),
      );
    } finally {
      if (_loadingCatalogKeys[peer.instanceId] == catalogKey) {
        _loadingCatalogKeys.remove(peer.instanceId);
      }
    }
  }

  static String _remoteCatalogKey(VibekitsLanPeer peer) => <String>[
    peer.catalogUri.toString(),
    peer.callUri.toString(),
    peer.instanceKeyFingerprint,
    peer.catalogRevision,
    peer.capabilityDigest,
  ].join('|');

  static McpDeviceCapability? _parseProvider(
    Map<Object?, Object?> json,
    McpCapabilityTier tier,
  ) {
    final String id = '${json['instanceId'] ?? json['id'] ?? ''}'.trim();
    final String name = '${json['name'] ?? ''}'.trim();
    final Object? rawTools = json['tools'];
    if (id.isEmpty || name.isEmpty || rawTools is! List) return null;
    final List<McpToolInterface> tools = <McpToolInterface>[
      for (final Object? item in rawTools)
        if (item is Map)
          McpToolInterface.fromJson(Map<Object?, Object?>.from(item)),
    ].where((McpToolInterface tool) => tool.name.isNotEmpty).toList();
    return McpDeviceCapability(
      id: id,
      name: name,
      appId: '${json['appId'] ?? ''}',
      appVersion: '${json['appVersion'] ?? ''}',
      tier: tier,
      transport: '${json['transport'] ?? 'stdio'}',
      endpoint: '${json['endpoint'] ?? ''}',
      tools: List<McpToolInterface>.unmodifiable(tools),
      lastUpdated:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      catalogRevision: '${json['catalogRevision'] ?? ''}',
      hardwareCode: '${json['hardwareCode'] ?? ''}',
      launchArguments: json['arguments'] is List
          ? (json['arguments']! as List)
                .whereType<String>()
                .take(32)
                .toList(growable: false)
          : const <String>[],
      runtime: McpNodeRuntime.fromJson(json['runtime']),
    );
  }

  void _emit() {
    _version++;
    _changes.add(snapshot);
  }

  static String _signature(List<McpDeviceCapability> devices) =>
      jsonEncode(<Object?>[
        for (final McpDeviceCapability device in devices)
          <Object?>[
            device.id,
            device.hardwareCode,
            device.catalogRevision,
            device.endpoint,
            device.runtime.toJson(),
            for (final McpToolInterface tool in device.tools) tool.toJson(),
          ],
      ]);

  Future<void> dispose() async {
    _localRefreshTimer?.cancel();
    await _lanSubscription?.cancel();
    _lanPeers = <String, VibekitsLanPeer>{};
    _remoteTools.clear();
    _remoteCatalogKeys.clear();
    _loadingCatalogKeys.clear();
    _started = false;
  }

  static const List<McpToolInterface> _schedulingToolInterfaces =
      <McpToolInterface>[
        McpToolInterface(
          name: 'lmcp.node.status',
          title: '查询作战单位实时容量',
          description: '读取本机 in-process MCP 的实时槽位。',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
        McpToolInterface(
          name: 'lmcp.capacity.reserve',
          title: '预约容量',
          description: '原子预约本机执行槽。',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
        McpToolInterface(
          name: 'lmcp.capacity.renew',
          title: '续租容量',
          description: '续租本机执行槽。',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
        McpToolInterface(
          name: 'lmcp.capacity.release',
          title: '释放容量',
          description: '幂等释放本机执行槽。',
          inputSchema: <String, Object?>{'type': 'object'},
        ),
      ];
}
