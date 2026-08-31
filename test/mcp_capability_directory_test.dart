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

    expect(result['ok'], isTrue);
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
  }) async {
    calls++;
    this.executable = executable;
    this.launchArguments = launchArguments;
    this.toolName = toolName;
    return <String, Object?>{'ok': true, 'arguments': arguments};
  }
}
