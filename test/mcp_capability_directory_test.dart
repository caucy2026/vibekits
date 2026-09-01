import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/platform_storage_layout.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/dev_tools/domain/local_mcp_stdio_client.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_remote_client.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_directory.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_tool_reputation_store.dart';

void main() {
  test('默认 MCP 注册目录不依赖进程当前工作目录', () {
    final String expected =
        '${PlatformStorageLayout.current().cacheDirectory}'
        '${Platform.pathSeparator}mcp${Platform.pathSeparator}registrations';
    expect(
      McpCapabilityDirectory.defaultRegistrationDirectory().path,
      expected,
    );
    expect(
      expected,
      isNot(contains('${Directory.current.path}/.runtime-cache')),
    );
  });

  test('LMCP 目录和工具调用使用不同超时边界', () {
    final LmcpRemoteClient client = LmcpRemoteClient();
    expect(client.timeout, const Duration(seconds: 8));
    expect(client.callTimeout, const Duration(seconds: 120));
  });

  test('实时目录读取本机提供者并保持三层 Harness 查询顺序', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-directory-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
    );
    addTearDown(directory.dispose);

    await File('${root.path}${Platform.pathSeparator}vendor.json')
        .writeAsString(
          jsonEncode(<String, Object?>{
            'instanceId': 'vendor-01',
            'name': 'Vendor MCP',
            'appId': 'com.vendor.mcp',
            'appVersion': '2.1.0',
            'transport': 'stdio',
            'endpoint': r'D:\apps\vendor-mcp.exe',
            'catalogRevision': 'sha256:one',
            'tools': <Object?>[
              <String, Object?>{
                'name': 'vendor.lookup',
                'title': '查询设备',
                'description': '按设备 ID 查询实时状态。',
                'inputSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'deviceId': <String, Object?>{'type': 'string'},
                  },
                  'required': <String>['deviceId'],
                },
              },
            ],
          }),
        );

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    final McpCapabilitySnapshot snapshot = await directory.snapshotForTask();

    expect(snapshot.app, hasLength(1));
    expect(snapshot.local, hasLength(1));
    expect(snapshot.local.single.tools.single.name, 'vendor.lookup');
    expect(snapshot.local.single.tools.single.inputSchema['required'], <String>[
      'deviceId',
    ]);
    expect(snapshot.inHarnessSearchOrder.first.tier, McpCapabilityTier.app);
    expect(snapshot.inHarnessSearchOrder[1].tier, McpCapabilityTier.local);
  });

  test('非法或不完整注册文件不会进入工具目录', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-invalid-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
    );
    addTearDown(directory.dispose);
    await File('${root.path}${Platform.pathSeparator}broken.json')
        .writeAsString('{broken');
    await File('${root.path}${Platform.pathSeparator}missing-tools.json')
        .writeAsString(jsonEncode(<String, Object?>{'instanceId': 'x'}));

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    expect(directory.snapshot.local, isEmpty);
  });

  test('本地 stdio MCP 走统一路由并写入全局评分', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-local-call-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final File reputationFile = File(
      '${root.path}${Platform.pathSeparator}reputation.json',
    );
    final _FakeLocalClient localClient = _FakeLocalClient();
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
      localClient: localClient,
      reputationStore: McpToolReputationStore(file: reputationFile),
    );
    addTearDown(directory.dispose);
    await File('${root.path}${Platform.pathSeparator}local.json').writeAsString(
      jsonEncode(<String, Object?>{
        'instanceId': 'local-provider',
        'name': 'Local Provider',
        'transport': 'stdio',
        'endpoint': Platform.resolvedExecutable,
        'arguments': const <String>['--provider-mode'],
        'tools': <Object?>[
          <String, Object?>{
            'name': 'shared.lookup',
            'title': '本机查询',
            'description': '本地进程查询。',
            'inputSchema': const <String, Object?>{'type': 'object'},
          },
        ],
      }),
    );

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    final Map<String, Object?> result = await directory.invokeTool(
      instanceId: 'local-provider',
      toolName: 'shared.lookup',
      arguments: const <String, Object?>{'query': 'device'},
    );

    expect(result['ok'], isTrue, reason: '$result');
    expect(localClient.calls, 1);
    expect(localClient.executable, Platform.resolvedExecutable);
    expect(localClient.launchArguments, const <String>['--provider-mode']);
    expect(localClient.toolName, 'shared.lookup');
    final Map<String, Object?> reputations = await directory
        .exportReputations();
    final Map<String, Object?> entry =
        ((reputations['entries'] as List).single as Map)
            .cast<String, Object?>();
    expect(entry['scope'], 'global-tool-type');
    expect(entry['toolName'], 'shared.lookup');
    expect(entry['score'], 100);
  });

  test('LMCP/2 节点认证目录后才进入可调用工具路由', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-lmcp2-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final _FakeDiscoveryService discovery = _FakeDiscoveryService();
    final _FakeRemoteClient remote = _FakeRemoteClient();
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
      discoveryService: discovery,
      remoteClient: remote,
      reputationStore: McpToolReputationStore(
        file: File('${root.path}${Platform.pathSeparator}reputation.json'),
      ),
    );
    addTearDown(directory.dispose);
    addTearDown(discovery.close);
    await directory.start(appBridge: VibekitsHarnessToolBridge());

    final String digest = 'sha256:${List<String>.filled(64, '9').join()}';
    discovery.emit(<VibekitsLanPeer>[
      VibekitsLanPeer(
        instanceId: 'org.kemi.send:E16497473C',
        name: 'KEMI传书@Mac-E16497473C',
        appId: 'org.kemi.send',
        appVersion: '2.0.5',
        address: '192.168.3.65',
        port: 9443,
        transport: 'https-streamable-http',
        protocolVersion: 2,
        capabilityDigest: digest,
        lastSeen: DateTime.now(),
        catalogPath: '/mcp',
        callPath: '/mcp',
        instanceKeyFingerprint: 'sha256:${List<String>.filled(64, '1').join()}',
        catalogRevision: '2',
        serviceRole: 'tool-provider',
      ),
    ]);
    await pumpEventQueue();

    expect(directory.snapshot.lan, hasLength(1));
    expect(
      directory.snapshot.lan.single.endpoint,
      'https://192.168.3.65:9443/mcp',
    );
    expect(
      directory.snapshot.lan.single.tools.single.name,
      'kemi.device.status',
    );
    expect(remote.catalogLoads, 1);
    final Map<String, Object?> harnessCatalog = await directory
        .exportForHarness();
    final Map<String, Object?> tiers = (harnessCatalog['tiers'] as Map)
        .cast<String, Object?>();
    final List<Object?> lan = (tiers['lan'] as List).cast<Object?>();
    final Map<String, Object?> kemi = (lan.single as Map)
        .cast<String, Object?>();
    expect(kemi['callable'], isTrue);
    expect(
      (kemi['tools'] as List).single,
      containsPair('name', 'kemi.device.status'),
    );
    final Map<String, Object?> result = await directory.invokeLanTool(
      instanceId: 'org.kemi.send:E16497473C',
      toolName: 'kemi.device.status',
    );
    expect(result['instanceId'], 'org.kemi.send:E16497473C');
    expect(remote.calls, 1);
    final Map<String, Object?> scoredCatalog = await directory
        .exportForHarness();
    final Map<String, Object?> scoredTiers = (scoredCatalog['tiers'] as Map)
        .cast<String, Object?>();
    final Map<String, Object?> scoredKemi =
        ((scoredTiers['lan'] as List).single as Map).cast<String, Object?>();
    final Map<String, Object?> scoredTool =
        ((scoredKemi['tools'] as List).single as Map).cast<String, Object?>();
    final Map<String, Object?> reputation = (scoredTool['reputation'] as Map)
        .cast<String, Object?>();
    expect(reputation['score'], 100);
    expect(reputation['scope'], 'global-tool-type');

    discovery.emit(const <VibekitsLanPeer>[]);
    await pumpEventQueue();
    expect(directory.snapshot.lan, isEmpty);
    await expectLater(
      directory.invokeLanTool(
        instanceId: 'org.kemi.send:E16497473C',
        toolName: 'kemi.device.status',
      ),
      throwsA(
        isA<LmcpRemoteException>().having(
          (LmcpRemoteException error) => error.code,
          'code',
          'peer_offline',
        ),
      ),
    );
  });

  test('失败目录对重复公告退避但目录身份变化立即重验', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-lmcp2-retry-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final _FakeDiscoveryService discovery = _FakeDiscoveryService();
    final _FailingRemoteClient remote = _FailingRemoteClient();
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
      discoveryService: discovery,
      remoteClient: remote,
      reputationStore: McpToolReputationStore(
        file: File('${root.path}${Platform.pathSeparator}reputation.json'),
      ),
    );
    addTearDown(directory.dispose);
    addTearDown(discovery.close);
    await directory.start(appBridge: VibekitsHarnessToolBridge());

    VibekitsLanPeer peer(String revision) => VibekitsLanPeer(
      instanceId: 'com.vendor.device:ABCDEF0123',
      name: 'Vendor@host-ABCDEF0123',
      appId: 'com.vendor.device',
      appVersion: '1.0.0',
      address: '192.168.3.62',
      port: 9443,
      transport: 'https-streamable-http',
      protocolVersion: 2,
      capabilityDigest: 'sha256:${List<String>.filled(64, '7').join()}',
      lastSeen: DateTime.now(),
      catalogPath: '/mcp',
      callPath: '/mcp',
      instanceKeyFingerprint: 'sha256:${List<String>.filled(64, '5').join()}',
      catalogRevision: revision,
      serviceRole: 'tool-provider',
    );

    discovery.emit(<VibekitsLanPeer>[peer('3')]);
    await pumpEventQueue();
    discovery.emit(<VibekitsLanPeer>[peer('3')]);
    discovery.emit(<VibekitsLanPeer>[peer('3')]);
    await pumpEventQueue();
    expect(remote.catalogLoads, 1);

    final Map<String, Object?> failedCatalog = await directory
        .exportForHarness();
    final Map<String, Object?> failedLan =
        ((((failedCatalog['tiers'] as Map)['lan'] as List).single) as Map)
            .cast<String, Object?>();
    expect(failedLan['callable'], isFalse);
    expect(failedLan['discoveryAlive'], isTrue);
    expect(failedLan['endpointReachable'], isFalse);
    expect(failedLan['catalogState'], 'unreachable');
    expect(failedLan['catalogErrorCode'], 'connection_failed');
    expect(failedLan['catalogError'], contains('connection_failed'));

    discovery.emit(<VibekitsLanPeer>[peer('4')]);
    await pumpEventQueue();
    expect(remote.catalogLoads, 2);
  });

  test('本机注册缓存不可创建时仍订阅并显示局域网节点', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-readonly-registration-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final File blocker = File(
      '${root.path}${Platform.pathSeparator}not-a-directory',
    );
    await blocker.writeAsString('blocks child directory creation');
    final _FakeDiscoveryService discovery = _FakeDiscoveryService();
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: Directory(
        '${blocker.path}${Platform.pathSeparator}registrations',
      ),
      discoveryService: discovery,
      remoteClient: _FakeRemoteClient(),
      reputationStore: McpToolReputationStore(
        file: File('${root.path}${Platform.pathSeparator}reputation.json'),
      ),
    );
    addTearDown(directory.dispose);
    addTearDown(discovery.close);

    await directory.start(appBridge: VibekitsHarnessToolBridge());
    discovery.emit(<VibekitsLanPeer>[
      VibekitsLanPeer(
        instanceId: 'com.newlink.kemiscrollbench:41B8C7FDF4',
        name: 'KEMI-BM@hua-41B8C7FDF4',
        appId: 'com.newlink.kemiscrollbench',
        appVersion: '2.1.5',
        address: '192.168.3.62',
        port: 9443,
        transport: 'https-streamable-http',
        protocolVersion: 2,
        capabilityDigest: 'sha256:${List<String>.filled(64, '7').join()}',
        lastSeen: DateTime.now(),
        hardwareCode: '41B8C7FDF4',
        catalogPath: '/mcp',
        callPath: '/mcp',
        instanceKeyFingerprint: 'sha256:${List<String>.filled(64, '5').join()}',
        catalogRevision: '3',
        serviceRole: 'tool-provider',
      ),
    ]);
    await pumpEventQueue();

    expect(directory.snapshot.local, isEmpty);
    expect(directory.snapshot.lan, hasLength(1));
    expect(directory.snapshot.lan.single.hardwareCode, '41B8C7FDF4');
  });

  test('自动调度在预约忙时切换节点并在业务调用后释放租约', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-auto-schedule-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final _FakeDiscoveryService discovery = _FakeDiscoveryService();
    final _SchedulingRemoteClient remote = _SchedulingRemoteClient();
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
      discoveryService: discovery,
      remoteClient: remote,
      reputationStore: McpToolReputationStore(
        file: File('${root.path}${Platform.pathSeparator}reputation.json'),
      ),
    );
    addTearDown(directory.dispose);
    addTearDown(discovery.close);
    await directory.start(appBridge: VibekitsHarnessToolBridge());

    VibekitsLanPeer peer(String suffix, String address) => VibekitsLanPeer(
      instanceId: 'com.example.worker:$suffix',
      name: 'Worker@$address-$suffix',
      appId: 'com.example.worker',
      appVersion: '3.0.0',
      address: address,
      port: 9443,
      transport: 'https-streamable-http',
      protocolVersion: 2,
      capabilityDigest:
          'sha256:${List<String>.filled(64, suffix[0].toLowerCase()).join()}',
      lastSeen: DateTime.now(),
      hardwareCode: suffix,
      catalogPath: '/mcp',
      callPath: '/mcp',
      instanceKeyFingerprint:
          'sha256:${List<String>.filled(64, suffix[1].toLowerCase()).join()}',
      catalogRevision: '7',
      serviceRole: 'tool-provider',
      runtime: const McpNodeRuntime(
        state: McpNodeState.idle,
        capacity: 2,
        inFlight: 0,
        queueDepth: 0,
        availableSlots: 2,
        loadRevision: 9,
        oldestTaskAgeMs: 0,
        draining: false,
        acceptingReservations: true,
      ),
    );
    discovery.emit(<VibekitsLanPeer>[
      peer('AAAAAAAAAA', '192.168.3.61'),
      peer('BBBBBBBBBB', '192.168.3.62'),
    ]);
    await pumpEventQueue();

    final Map<String, Object?> result = await directory.scheduleAndInvoke(
      toolName: 'worker.build',
      taskId: 'build-task-001',
      idempotencyKey: 'build-task-001-attempt',
      scopeDigest: 'sha256:workspace-scope',
      arguments: const <String, Object?>{'target': 'release'},
    );

    expect(result['ok'], isTrue, reason: '$result');
    expect(remote.reserveCalls, 2);
    expect(remote.businessCalls, 1);
    expect(remote.releaseCalls, 1);
    expect(result.toString(), isNot(contains('private-lease-token')));
    final List<Object?> attempts = result['attempts']! as List<Object?>;
    expect((attempts.first! as Map)['outcome'], 'reserve-rejected');
    expect((attempts.last! as Map)['outcome'], 'completed');
  });

  test('自动调度优先使用本机 app 作战单位并释放本机槽位', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-mcp-app-schedule-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    int executions = 0;
    final McpCapabilityDirectory directory = McpCapabilityDirectory(
      registrationDirectory: root,
      reputationStore: McpToolReputationStore(
        file: File('${root.path}${Platform.pathSeparator}reputation.json'),
      ),
    );
    addTearDown(directory.dispose);
    await directory.start(
      appBridge: VibekitsHarnessToolBridge(
        handlers: <String, HarnessToolHandler>{
          VibekitsHarnessToolBridge.programmerCalculatorId:
              (Map<String, Object?> arguments) async {
                executions++;
                return <String, Object?>{'decimal': '2'};
              },
        },
      ),
    );

    final Map<String, Object?> result = await directory.scheduleAndInvoke(
      toolName: VibekitsHarnessToolBridge.programmerCalculatorId,
      taskId: 'local-calc-001',
      idempotencyKey: 'local-calc-001',
      scopeDigest: 'sha256:calculator',
      arguments: const <String, Object?>{'expression': '1+1'},
    );

    expect(result['ok'], isTrue, reason: '$result');
    expect(((result['selected'] as Map)['tier']), 'app');
    expect(executions, 1);
    expect(directory.snapshot.app.single.runtime.availableSlots, 8);
    expect(result['redactedFields'], const <String>['leaseToken']);
  });
}

class _FakeDiscoveryService extends LanPeerDiscoveryService {
  _FakeDiscoveryService() : super(port: 49999);

  final StreamController<List<VibekitsLanPeer>> _controller =
      StreamController<List<VibekitsLanPeer>>.broadcast();
  List<VibekitsLanPeer> _current = const <VibekitsLanPeer>[];

  @override
  Stream<List<VibekitsLanPeer>> get changes => _controller.stream;

  @override
  List<VibekitsLanPeer> get peers => _current;

  void emit(List<VibekitsLanPeer> peers) {
    _current = List<VibekitsLanPeer>.unmodifiable(peers);
    _controller.add(_current);
  }

  Future<void> close() => _controller.close();
}

class _FakeRemoteClient extends LmcpRemoteClient {
  int catalogLoads = 0;
  int calls = 0;

  @override
  Future<List<McpToolInterface>> loadTools(VibekitsLanPeer peer) async {
    catalogLoads++;
    return const <McpToolInterface>[
      McpToolInterface(
        name: 'kemi.device.status',
        title: '读取状态',
        description: '只读状态。',
        inputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
    ];
  }

  @override
  Future<Map<String, Object?>> callTool({
    required VibekitsLanPeer peer,
    required String name,
    Map<String, Object?> arguments = const <String, Object?>{},
    Map<String, Object?>? scheduling,
  }) async {
    calls++;
    return <String, Object?>{
      'instanceId': peer.instanceId,
      'tool': name,
      'catalogRevision': peer.catalogRevision,
      'isError': false,
    };
  }
}

class _FailingRemoteClient extends LmcpRemoteClient {
  int catalogLoads = 0;

  @override
  Future<List<McpToolInterface>> loadTools(VibekitsLanPeer peer) async {
    catalogLoads++;
    throw const LmcpRemoteException('connection_failed', '无法连接远端 MCP 端点');
  }
}

class _SchedulingRemoteClient extends LmcpRemoteClient {
  int reserveCalls = 0;
  int businessCalls = 0;
  int releaseCalls = 0;

  static const List<McpToolInterface> catalog = <McpToolInterface>[
    McpToolInterface(
      name: 'worker.build',
      title: 'build',
      description: '',
      inputSchema: <String, Object?>{'type': 'object'},
    ),
    McpToolInterface(
      name: 'lmcp.node.status',
      title: 'status',
      description: '',
      inputSchema: <String, Object?>{'type': 'object'},
    ),
    McpToolInterface(
      name: 'lmcp.capacity.reserve',
      title: 'reserve',
      description: '',
      inputSchema: <String, Object?>{'type': 'object'},
    ),
    McpToolInterface(
      name: 'lmcp.capacity.renew',
      title: 'renew',
      description: '',
      inputSchema: <String, Object?>{'type': 'object'},
    ),
    McpToolInterface(
      name: 'lmcp.capacity.release',
      title: 'release',
      description: '',
      inputSchema: <String, Object?>{'type': 'object'},
    ),
  ];

  @override
  Future<List<McpToolInterface>> loadTools(VibekitsLanPeer peer) async =>
      catalog;

  @override
  Future<Map<String, Object?>> callTool({
    required VibekitsLanPeer peer,
    required String name,
    Map<String, Object?> arguments = const <String, Object?>{},
    Map<String, Object?>? scheduling,
  }) async {
    Map<String, Object?> response(
      Map<String, Object?> structured, {
      bool isError = false,
    }) => <String, Object?>{
      'instanceId': peer.instanceId,
      'tool': name,
      'catalogRevision': peer.catalogRevision,
      'isError': isError,
      'structuredContent': structured,
    };
    if (name == 'lmcp.capacity.reserve') {
      reserveCalls++;
      if (reserveCalls == 1) {
        return response(<String, Object?>{
          'ok': false,
          'error': const <String, Object?>{'code': 'CAPACITY_BUSY'},
        }, isError: true);
      }
      return response(<String, Object?>{
        'ok': true,
        'leaseId': 'lease-visible-id',
        'leaseToken': 'private-lease-token',
      });
    }
    if (name == 'lmcp.capacity.release') {
      releaseCalls++;
      return response(const <String, Object?>{'ok': true, 'released': true});
    }
    businessCalls++;
    expect(scheduling?['leaseToken'], 'private-lease-token');
    return response(const <String, Object?>{
      'ok': true,
      'phase': 'executed',
      'artifactSha256': 'sha256:result',
    });
  }
}

class _FakeLocalClient extends LocalMcpStdioClient {
  int calls = 0;
  String executable = '';
  List<String> launchArguments = const <String>[];
  String toolName = '';

  @override
  Future<Map<String, Object?>> callTool({
    required String executable,
    List<String> launchArguments = const <String>[],
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    Map<String, Object?>? scheduling,
  }) async {
    calls++;
    this.executable = executable;
    this.launchArguments = launchArguments;
    this.toolName = toolName;
    return <String, Object?>{'ok': true, 'arguments': arguments};
  }
}
