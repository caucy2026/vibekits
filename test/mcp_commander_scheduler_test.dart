import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_commander_scheduler.dart';

void main() {
  test('指挥官保持层级并在同层优先空闲槽更多的作战单位', () {
    final DateTime now = DateTime.now();
    final List<McpDeviceCapability> devices = <McpDeviceCapability>[
      _device(
        id: 'lan-busy',
        tier: McpCapabilityTier.lan,
        capacity: 4,
        inFlight: 3,
        updatedAt: now,
      ),
      _device(
        id: 'lan-idle',
        tier: McpCapabilityTier.lan,
        capacity: 4,
        inFlight: 0,
        updatedAt: now,
      ),
      _device(
        id: 'local-one-slot',
        tier: McpCapabilityTier.local,
        capacity: 1,
        inFlight: 0,
        updatedAt: now,
      ),
    ];

    final List<McpSchedulingCandidate> ranked = McpCommanderScheduler.rank(
      devices: devices,
      toolName: 'kemi.benchmark.run',
      taskId: 'task-stable-1',
      reputations: const {},
      now: now,
    );

    expect(ranked, hasLength(1));
    expect(ranked.single.device.id, 'local-one-slot');
    expect(ranked.single.reason, contains('空闲槽=1/1'));
  });

  test('指挥官拒绝无租约工具、饱和和过期结构节点', () {
    final DateTime now = DateTime.now();
    final McpDeviceCapability complete = _device(
      id: 'complete',
      tier: McpCapabilityTier.lan,
      capacity: 2,
      inFlight: 0,
      updatedAt: now,
    );
    final McpDeviceCapability missingLeaseTools = McpDeviceCapability(
      id: 'missing',
      name: 'missing',
      appId: 'missing',
      appVersion: '1',
      tier: McpCapabilityTier.lan,
      transport: 'https-streamable-http',
      endpoint: 'https://192.168.3.10:9443/mcp',
      tools: <McpToolInterface>[_tool('kemi.benchmark.run')],
      lastUpdated: now,
      runtime: _runtime(capacity: 2, inFlight: 0),
    );
    final McpDeviceCapability saturated = _device(
      id: 'saturated',
      tier: McpCapabilityTier.lan,
      capacity: 1,
      inFlight: 1,
      updatedAt: now,
    );

    final List<McpSchedulingCandidate> ranked = McpCommanderScheduler.rank(
      devices: <McpDeviceCapability>[missingLeaseTools, saturated, complete],
      toolName: 'kemi.benchmark.run',
      taskId: 'task-stable-2',
      reputations: const {},
      now: now,
    );

    expect(
      ranked.map((McpSchedulingCandidate item) => item.device.id),
      <String>['complete'],
    );
  });
}

McpDeviceCapability _device({
  required String id,
  required McpCapabilityTier tier,
  required int capacity,
  required int inFlight,
  required DateTime updatedAt,
}) => McpDeviceCapability(
  id: id,
  name: id,
  appId: 'app.$id',
  appVersion: '1',
  tier: tier,
  transport: tier == McpCapabilityTier.local
      ? 'stdio'
      : 'https-streamable-http',
  endpoint: tier == McpCapabilityTier.local
      ? '/tmp/$id'
      : 'https://192.168.3.10:9443/mcp',
  tools: <McpToolInterface>[
    _tool('kemi.benchmark.run'),
    _tool('lmcp.node.status'),
    _tool('lmcp.capacity.reserve'),
    _tool('lmcp.capacity.renew'),
    _tool('lmcp.capacity.release'),
  ],
  lastUpdated: updatedAt,
  runtime: _runtime(capacity: capacity, inFlight: inFlight),
);

McpNodeRuntime _runtime({required int capacity, required int inFlight}) =>
    McpNodeRuntime(
      state: inFlight == 0
          ? McpNodeState.idle
          : inFlight >= capacity
          ? McpNodeState.saturated
          : McpNodeState.busy,
      capacity: capacity,
      inFlight: inFlight,
      queueDepth: 0,
      availableSlots: capacity - inFlight,
      loadRevision: 1,
      oldestTaskAgeMs: 0,
      draining: false,
      acceptingReservations: true,
    );

McpToolInterface _tool(String name) => McpToolInterface(
  name: name,
  title: name,
  description: name,
  inputSchema: const <String, Object?>{'type': 'object'},
);
