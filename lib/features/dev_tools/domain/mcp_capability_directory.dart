import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness_tool_bridge.dart';
import 'lan_peer_discovery_service.dart';
import 'mcp_capability_models.dart';

/// Maintains the live MCP catalog shared by the Harness planner and its UI.
///
/// Other local processes publish one JSON file per provider in
/// [.runtime-cache/mcp/registrations]. Files are reread atomically; malformed
/// or stale registrations never replace the last valid snapshot.
class McpCapabilityDirectory {
  McpCapabilityDirectory({Directory? registrationDirectory})
    : registrationDirectory =
          registrationDirectory ??
          Directory(
            '${Directory.current.absolute.path}${Platform.pathSeparator}'
            '.runtime-cache${Platform.pathSeparator}mcp'
            '${Platform.pathSeparator}registrations',
          );

  static final McpCapabilityDirectory instance = McpCapabilityDirectory();

  final Directory registrationDirectory;
  final StreamController<McpCapabilitySnapshot> _changes =
      StreamController<McpCapabilitySnapshot>.broadcast();
  StreamSubscription<List<VibekitsLanPeer>>? _lanSubscription;
  Timer? _localRefreshTimer;
  List<McpDeviceCapability> _app = const <McpDeviceCapability>[];
  List<McpDeviceCapability> _local = const <McpDeviceCapability>[];
  List<McpDeviceCapability> _lan = const <McpDeviceCapability>[];
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
            ),
        ],
        lastUpdated: DateTime.now(),
      ),
    ];
    if (!_started) {
      _started = true;
      await registrationDirectory.create(recursive: true);
      _lanSubscription = LanPeerDiscoveryService.instance.changes.listen(
        _updateLan,
      );
      _localRefreshTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refreshLocal()),
      );
    }
    await refreshLocal();
    _updateLan(LanPeerDiscoveryService.instance.peers);
  }

  /// Called for every new task that needs tools. The returned immutable
  /// snapshot is always ordered APP -> local process -> LAN.
  Future<McpCapabilitySnapshot> snapshotForTask() async {
    await refreshLocal();
    return snapshot;
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
    final List<McpDeviceCapability> next = <McpDeviceCapability>[
      for (final VibekitsLanPeer peer in peers)
        McpDeviceCapability(
          id: peer.instanceId,
          name: peer.name,
          appId: peer.appId,
          appVersion: peer.appVersion,
          tier: McpCapabilityTier.lan,
          transport: peer.transport,
          endpoint: 'http://${peer.address}:${peer.port}/mcp',
          tools: peer.tools,
          lastUpdated: peer.lastSeen,
          catalogRevision: peer.capabilityDigest,
          hardwareCode: peer.hardwareCode,
        ),
    ];
    if (_signature(next) != _signature(_lan)) {
      _lan = List<McpDeviceCapability>.unmodifiable(next);
      _emit();
    }
  }

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
    _started = false;
  }
}
