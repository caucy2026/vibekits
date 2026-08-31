import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_exposure_server.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_remote_client.dart';

void main() {
  test('持久 EC 证书重载后保持同一 SHA-256 实例指纹', () async {
    final Map<String, String> credentials = <String, String>{};
    final LmcpCertificateStore store = LmcpCertificateStore(
      readCredential: (String key) async => credentials[key],
      writeCredential: (String key, String value) async {
        if (value.isEmpty) {
          credentials.remove(key);
        } else {
          credentials[key] = value;
        }
      },
    );

    final LmcpInstanceCertificate first = await store.loadOrCreate(
      commonName: 'VibeKits@test-0123456789',
    );
    final LmcpInstanceCertificate second = await store.loadOrCreate(
      commonName: 'VibeKits@test-0123456789',
    );

    expect(first.fingerprint, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    expect(second.fingerprint, first.fingerprint);
    expect(second.certificatePem, first.certificatePem);
    expect(second.privateKeyPem, first.privateKeyPem);
    expect(first.privateKeyPem, contains('BEGIN EC PRIVATE KEY'));
    expect(first.privateKeyPem, isNot(contains('BEGIN RSA PRIVATE KEY')));
    expect(
      credentials.values.join('\n'),
      isNot(contains('PRIVATE KEY-----\n\n')),
    );
  });

  test('半写入或损坏的实例凭据会安全重建完整证书对', () async {
    final Map<String, String> credentials = <String, String>{
      'lmcp-v2-instance-certificate': 'not-a-certificate',
      'lmcp-v2-instance-private-key': '',
    };
    final LmcpCertificateStore store = LmcpCertificateStore(
      readCredential: (String key) async => credentials[key],
      writeCredential: (String key, String value) async {
        credentials[key] = value;
      },
    );

    final LmcpInstanceCertificate rebuilt = await store.loadOrCreate(
      commonName: 'VibeKits@recovery-0123456789',
    );
    final LmcpInstanceCertificate reloaded = await store.loadOrCreate(
      commonName: 'VibeKits@recovery-0123456789',
    );

    expect(rebuilt.fingerprint, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    expect(reloaded.fingerprint, rebuilt.fingerprint);
    expect(credentials.values, everyElement(isNotEmpty));
  });

  test('MCP 2025-06-18 支持分页目录、参数验证和统一审批审计桥', () async {
    int approvals = 0;
    int executions = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.programmerCalculatorId:
            (Map<String, Object?> arguments) async {
              executions++;
              return <String, Object?>{'expression': arguments['expression']};
            },
        VibekitsHarnessToolBridge.networkDownloadId:
            (Map<String, Object?> arguments) async {
              executions++;
              return <String, Object?>{'url': arguments['url']};
            },
      },
    );
    final VibekitsLmcpProtocol protocol = VibekitsLmcpProtocol(
      instanceId: 'com.vibekits.desktop:0123456789',
      serverVersion: '1.9.0',
      bridge: bridge,
      pageSize: 2,
      approve: (HarnessToolApprovalRequest request) async {
        approvals++;
        return true;
      },
    );

    final Map<String, Object?> initialize = (await protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{'name': 'KEMI', 'version': '2.0.5'},
        },
      },
    ))!;
    expect(
      (initialize['result']! as Map<Object?, Object?>)['protocolVersion'],
      '2025-06-18',
    );

    final Map<String, Object?> firstPage = (await protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': <String, Object?>{},
      },
    ))!;
    final Map<Object?, Object?> firstResult =
        firstPage['result']! as Map<Object?, Object?>;
    expect(firstResult['tools'], hasLength(2));
    final Map<Object?, Object?> firstTool =
        (firstResult['tools']! as List<Object?>).first!
            as Map<Object?, Object?>;
    expect(firstTool['annotations'], isA<Map<Object?, Object?>>());
    expect(firstResult['nextCursor'], isA<String>());
    final Map<String, Object?> secondPage = (await protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/list',
        'params': <String, Object?>{'cursor': firstResult['nextCursor']},
      },
    ))!;
    expect(
      (secondPage['result']! as Map<Object?, Object?>)['tools'],
      hasLength(2),
    );

    final Map<String, Object?> invalid = (await protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.programmerCalculatorId,
          'arguments': <String, Object?>{},
        },
      },
    ))!;
    expect((invalid['error']! as Map<Object?, Object?>)['code'], -32602);
    expect(executions, 0);

    final Map<String, Object?> readOnly = (await protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.programmerCalculatorId,
          'arguments': <String, Object?>{'expression': '1+1'},
        },
      },
    ))!;
    final Map<Object?, Object?> readOnlyResult =
        readOnly['result']! as Map<Object?, Object?>;
    expect(readOnlyResult['isError'], isFalse);
    expect(readOnlyResult['instanceId'], 'com.vibekits.desktop:0123456789');
    expect(approvals, 0, reason: '只读工具沿用 Harness 的免审批风险规则');

    final Map<String, Object?> write = (await protocol.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 6,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': VibekitsHarnessToolBridge.networkDownloadId,
        'arguments': <String, Object?>{'url': 'https://example.test/file'},
      },
    }))!;
    expect((write['result']! as Map<Object?, Object?>)['isError'], isFalse);
    expect(approvals, 1, reason: '写入工具必须进入现有 Harness 审批回调');
    expect(executions, 2);
  });

  test('工具参数递归验证数组、嵌套对象、范围和未知字段', () {
    final Map<String, Object?> schema = <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['items'],
      'properties': <String, Object?>{
        'items': <String, Object?>{
          'type': 'array',
          'minItems': 1,
          'maxItems': 2,
          'items': <String, Object?>{
            'type': 'object',
            'additionalProperties': false,
            'required': <String>['size'],
            'properties': <String, Object?>{
              'size': <String, Object?>{
                'type': 'integer',
                'minimum': 1,
                'maximum': 10,
              },
            },
          },
        },
      },
    };
    validateToolArguments(<String, Object?>{
      'items': <Object?>[
        <String, Object?>{'size': 5},
      ],
    }, schema);
    expect(
      () => validateToolArguments(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'size': 11, 'extra': true},
        ],
      }, schema),
      throwsA(isA<LmcpProtocolException>()),
    );
  });

  test('真实 HTTPS 服务广播严格 LMCP/2 并在关闭时撤销端点', () async {
    final Map<String, String> credentials = <String, String>{};
    final _FakeDiscovery discovery = _FakeDiscovery();
    final ServerSocket occupied = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    addTearDown(occupied.close);
    final VibekitsLmcpExposureServer server = VibekitsLmcpExposureServer(
      discovery: discovery,
      preferredPort: occupied.port,
      certificateStore: LmcpCertificateStore(
        readCredential: (String key) async => credentials[key],
        writeCredential: (String key, String value) async {
          if (value.isEmpty) {
            credentials.remove(key);
          } else {
            credentials[key] = value;
          }
        },
      ),
    );
    addTearDown(() => server.stop(force: true));
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.programmerCalculatorId: (
          Map<String, Object?> arguments,
        ) async => <String, Object?>{'value': 2},
      },
    );

    await server.start(
      instanceId: 'com.vibekits.desktop:0123456789',
      displayName: 'VibeKits@test-0123456789',
      appId: 'com.vibekits.desktop',
      appVersion: '1.9.0',
      hardwareCode: '0123456789',
      bridge: bridge,
      approve: (HarnessToolApprovalRequest request) async => false,
    );

    expect(server.running, isTrue);
    expect(server.port, isNot(occupied.port));
    expect(discovery.enabled, isTrue);
    final Lmcp2Advertisement announcement = discovery.advertisement!;
    final Map<String, Object?> packet = announcement.toAnnouncement(
      sentAt: DateTime.utc(2026, 8, 30, 12),
    );
    expect(utf8.encode(jsonEncode(packet)).length, lessThanOrEqualTo(1200));
    expect(packet['protocolVersion'], '2.0');
    expect(packet['endpoint'], isNull);
    final Map<Object?, Object?> catalog =
        packet['catalogEndpoint']! as Map<Object?, Object?>;
    final Map<Object?, Object?> call =
        packet['callEndpoint']! as Map<Object?, Object?>;
    for (final String key in <String>[
      'transport',
      'port',
      'path',
      'instanceKeyFingerprint',
      'protocolVersions',
      'catalogRevision',
      'capabilityDigest',
    ]) {
      expect(call[key], catalog[key], reason: '端点字段必须一致：$key');
    }
    expect(call['serviceRole'], 'tool-provider');
    expect(
      LanPeerDiscoveryService.decodePeerAnnouncement(
        decoded: packet,
        sourceAddress: '192.168.3.65',
      )?.supportsLmcp2Calls,
      isTrue,
    );

    final VibekitsLanPeer loopbackPeer = VibekitsLanPeer(
      instanceId: 'com.vibekits.desktop:0123456789',
      name: 'VibeKits@test-0123456789',
      appId: 'com.vibekits.desktop',
      appVersion: '1.9.0',
      address: '127.0.0.1',
      port: server.port!,
      transport: 'https-streamable-http',
      protocolVersion: 2,
      capabilityDigest: '${catalog['capabilityDigest']}',
      lastSeen: DateTime.now(),
      hardwareCode: '0123456789',
      catalogPath: '/mcp',
      callPath: '/mcp',
      instanceKeyFingerprint: '${catalog['instanceKeyFingerprint']}',
      catalogRevision: '${catalog['catalogRevision']}',
      serviceRole: 'tool-provider',
    );
    final LmcpRemoteClient remote = LmcpRemoteClient();
    final remoteTools = await remote.loadTools(loopbackPeer);
    expect(
      remoteTools.where(
        (tool) => tool.name == VibekitsHarnessToolBridge.programmerCalculatorId,
      ),
      isNotEmpty,
    );
    final Map<String, Object?> remoteResult = await remote.callTool(
      peer: loopbackPeer,
      name: VibekitsHarnessToolBridge.programmerCalculatorId,
      arguments: <String, Object?>{'expression': '1+1'},
    );
    expect(remoteResult['isError'], isFalse);

    final HttpClient client = HttpClient()
      ..badCertificateCallback = (_, _, _) => true;
    addTearDown(() => client.close(force: true));
    final HttpClientRequest request = await client.postUrl(
      Uri(scheme: 'https', host: '127.0.0.1', port: server.port, path: '/mcp'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{'name': 'KEMI', 'version': '2.0.5'},
        },
      }),
    );
    final HttpClientResponse response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final Map<String, Object?> responseJson = Map<String, Object?>.from(
      jsonDecode(await utf8.decodeStream(response)) as Map,
    );
    expect(
      (responseJson['result']! as Map<Object?, Object?>)['protocolVersion'],
      '2025-06-18',
    );

    await server.stop();
    expect(server.running, isFalse);
    expect(discovery.enabled, isFalse);
    expect(discovery.advertisement, isNull);
  });
}

class _FakeDiscovery extends LanPeerDiscoveryService {
  bool enabled = false;
  Lmcp2Advertisement? advertisement;

  @override
  bool get running => true;

  @override
  void configureLmcp2Advertisement(Lmcp2Advertisement? advertisement) {
    this.advertisement = advertisement;
  }

  @override
  Future<void> setExposureEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}
