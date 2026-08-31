import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness_tool_bridge.dart';
import 'lan_peer_discovery_service.dart';
import 'local_mcp_stdio_client.dart';
import 'lmcp_remote_client.dart';
import 'mcp_capability_models.dart';
import 'mcp_tool_reputation_store.dart';

/// Maintains the live MCP catalog shared by the Harness planner and its UI.
///
/// Other local processes publish one JSON file per provider in
/// [.runtime-cache/mcp/registrations]. Files are reread atomically; malformed
/// or stale registrations never replace the last valid snapshot.
class McpCapabilityDirectory {
  McpCapabilityDirectory({
    Directory? registrationDirectory,
    LmcpRemoteClient? remoteClient,
    LanPeerDiscoveryService? discoveryService,
    McpToolReputationStore? reputationStore,
    LocalMcpStdioClient? localClient,
  }) : registrationDirectory =
           registrationDirectory ??
           Directory(
             '${Directory.current.absolute.path}${Platform.pathSeparator}'
             '.runtime-cache${Platform.pathSeparator}mcp'
             '${Platform.pathSeparator}registrations',
           ),
       _remoteClient = remoteClient ?? LmcpRemoteClient(),
       _discoveryService = discoveryService ?? LanPeerDiscoveryService.instance,
       _reputationStore = reputationStore ?? McpToolReputationStore.instance,
       _localClient = localClient ?? const LocalMcpStdioClient();

  static final McpCapabilityDirectory instance = McpCapabilityDirectory();

  final Directory registrationDirectory;
  final LmcpRemoteClient _remoteClient;
  final LanPeerDiscoveryService _discoveryService;
  final McpToolReputationStore _reputationStore;
  final LocalMcpStdioClient _localClient;
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
        ],
        lastUpdated: DateTime.now(),
      ),
    ];
    if (!_started) {
      _started = true;
      await registrationDirectory.create(recursive: true);
      _lanSubscription = _discoveryService.changes.listen(_updateLan);
      _localRefreshTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refreshLocal()),
      );
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
    for (final VibekitsLanPeer peer in peers) {
      if (!peer.supportsLmcp2Calls) continue;
      final String key = _remoteCatalogKey(peer);
      if (_remoteCatalogKeys[peer.instanceId] == key ||
          _loadingCatalogKeys[peer.instanceId] == key) {
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
      _updateLan(_lanPeers.values.toList(growable: false));
    } on Object {
      // Discovery heartbeats retry failed authenticated catalogs. A failed
      // node remains visible without tools and is never treated as callable.
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
}
