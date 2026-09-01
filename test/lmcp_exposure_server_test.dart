import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_caller_auth.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_exposure_server.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_inbound_call_hub.dart';
import 'package:vibekits/features/dev_tools/domain/lmcp_remote_client.dart';

void main() {
  test('远端原始目录扩展、Content-Length 和 structuredContent 身份兼容', () async {
    final Map<String, String> credentials = <String, String>{};
    final LmcpInstanceCertificate identity = await LmcpCertificateStore(
      readCredential: (String key) async => credentials[key],
      writeCredential: (String key, String value) async {
        credentials[key] = value;
      },
    ).loadOrCreate(commonName: 'KEMI-BM@test-0123456789');
    final SecurityContext context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final HttpServer server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => server.close(force: true));

    final Map<String, Object?> rawTool = <String, Object?>{
      'name': 'kemi.benchmark.device_status',
      'title': '读取基准设备状态',
      'description': '只读状态',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      'annotations': <String, Object?>{'readOnlyHint': true},
      'risk': <String, Object?>{
        'level': 'readOnly',
        'writesData': false,
        'providerExtension': 'must-remain-in-digest',
      },
    };
    final String digest =
        'sha256:${sha256.convert(utf8.encode(jsonEncode(_canonicalize(<String, Object?>{
          'tools': <Map<String, Object?>>[rawTool],
          'nextCursor': null,
        }))))}';
    final List<bool> requestUsedContentLength = <bool>[];
    final List<Map<String, String>> callerHeaders = <Map<String, String>>[];
    final List<LmcpVerifiedCaller> verifiedCallers = <LmcpVerifiedCaller>[];
    final LmcpCallerRequestVerifier callerVerifier =
        LmcpCallerRequestVerifier();
    unawaited(() async {
      await for (final HttpRequest request in server) {
        requestUsedContentLength.add(
          request.contentLength > 0 && !request.headers.chunkedTransferEncoding,
        );
        callerHeaders.add(<String, String>{
          for (final String name in <String>[
            'LMCP-Caller-Instance-Id',
            'LMCP-Caller-App-Id',
            'LMCP-Caller-Certificate',
            'LMCP-Caller-Fingerprint',
            'LMCP-Caller-Timestamp',
            'LMCP-Caller-Nonce',
            'LMCP-Caller-Signature',
          ])
            name: request.headers.value(name) ?? '',
        });
        final BytesBuilder requestBody = BytesBuilder(copy: false);
        await for (final List<int> chunk in request) {
          requestBody.add(chunk);
        }
        final List<int> requestBytes = requestBody.takeBytes();
        verifiedCallers.add(
          callerVerifier.verify(
            headers: request.headers,
            uri: request.uri,
            body: requestBytes,
          ),
        );
        final Map<String, Object?> payload = Map<String, Object?>.from(
          jsonDecode(utf8.decode(requestBytes)) as Map,
        );
        final String method = '${payload['method'] ?? ''}';
        request.response.headers.contentType = ContentType.json;
        if (!payload.containsKey('id')) {
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          continue;
        }
        final Object result = switch (method) {
          'initialize' => <String, Object?>{
            'protocolVersion': '2025-06-18',
            'capabilities': <String, Object?>{},
            'serverInfo': <String, Object?>{
              'name': 'KEMI-BM',
              'version': '2.1.4',
            },
          },
          'tools/list' => <String, Object?>{
            'tools': <Map<String, Object?>>[rawTool],
            'nextCursor': null,
          },
          'tools/call' => <String, Object?>{
            'content': <Object?>[],
            'structuredContent': <String, Object?>{
              'instanceId': 'com.newlink.kemiscrollbench:0123456789',
              'toolName': 'kemi.benchmark.device_status',
              'catalogRevision': 2,
              'ok': true,
            },
            'isError': false,
          },
          _ => <String, Object?>{},
        };
        request.response.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': result,
          }),
        );
        await request.response.close();
      }
    }());

    final VibekitsLanPeer peer = VibekitsLanPeer(
      instanceId: 'com.newlink.kemiscrollbench:0123456789',
      name: 'KEMI-BM@test-0123456789',
      appId: 'com.newlink.kemiscrollbench',
      appVersion: '2.1.4',
      address: InternetAddress.loopbackIPv4.address,
      port: server.port,
      transport: 'https-streamable-http',
      protocolVersion: 2,
      capabilityDigest: digest,
      lastSeen: DateTime.now(),
      hardwareCode: '0123456789',
      catalogPath: '/mcp',
      callPath: '/mcp',
      instanceKeyFingerprint: identity.fingerprint,
      catalogRevision: '2',
      serviceRole: 'tool-provider',
    );
    final LmcpRemoteClient client = LmcpRemoteClient();
    final tools = await client.loadTools(peer);
    expect(tools.single.risk, 'readOnly');
    final result = await client.callTool(peer: peer, name: tools.single.name);
    expect(result['isError'], isFalse);
    expect(requestUsedContentLength, everyElement(isTrue));
    expect(
      callerHeaders,
      everyElement(
        predicate<Map<String, String>>(
          (Map<String, String> headers) =>
              headers.values.every((String value) => value.isNotEmpty) &&
              headers['LMCP-Caller-Instance-Id'] ==
                  'com.vibekits.desktop:${headers['LMCP-Caller-Instance-Id']!.split(':').last}' &&
              headers['LMCP-Caller-App-Id'] == 'com.vibekits.desktop' &&
              headers['LMCP-Caller-Fingerprint'] ==
                  'sha256:${sha256.convert(base64.decode(headers['LMCP-Caller-Certificate']!))}',
        ),
      ),
    );
    expect(
      verifiedCallers.map((LmcpVerifiedCaller caller) => caller.instanceId),
      everyElement(startsWith('com.vibekits.desktop:')),
    );
  });

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

  test('协议端点完成 reserve→绑定业务调用→release 且状态不泄露 token', () async {
    int executions = 0;
    final VibekitsLmcpProtocol protocol = VibekitsLmcpProtocol(
      instanceId: 'com.vibekits.desktop:WORKER0001',
      serverVersion: '1.9.0-dev.140',
      bridge: VibekitsHarnessToolBridge(
        handlers: <String, HarnessToolHandler>{
          VibekitsHarnessToolBridge.programmerCalculatorId:
              (Map<String, Object?> arguments) async {
                executions++;
                return <String, Object?>{'value': 2};
              },
        },
      ),
    );
    const LmcpCallerIdentity caller = LmcpCallerIdentity(
      appId: 'com.vibekits.desktop',
      instanceId: 'com.vibekits.desktop:COMMANDER1',
      address: '192.168.3.65',
    );
    Future<Map<String, Object?>> call(
      int id,
      String name,
      Map<String, Object?> arguments, {
      Map<String, Object?>? scheduling,
    }) async => (await protocol.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': name,
        'arguments': arguments,
        'scheduling': ?scheduling,
      },
    }, caller: caller))!;

    final Map<String, Object?> reserved = await call(
      1,
      'lmcp.capacity.reserve',
      const <String, Object?>{
        'toolName': VibekitsHarnessToolBridge.programmerCalculatorId,
        'idempotencyKey': 'calc-001',
        'commanderId': 'com.vibekits.desktop:COMMANDER1',
        'requestedSlots': 1,
        'ttlSeconds': 45,
        'scopeDigest': 'sha256:calculator',
      },
    );
    final Map<Object?, Object?> reserveResult =
        reserved['result']! as Map<Object?, Object?>;
    final Map<Object?, Object?> lease =
        reserveResult['structuredContent']! as Map<Object?, Object?>;
    expect(lease['ok'], isTrue);

    final Map<String, Object?> executed = await call(
      2,
      VibekitsHarnessToolBridge.programmerCalculatorId,
      const <String, Object?>{'expression': '1+1'},
      scheduling: <String, Object?>{
        'leaseId': lease['leaseId'],
        'leaseToken': lease['leaseToken'],
        'idempotencyKey': 'calc-001',
      },
    );
    expect((executed['result']! as Map)['isError'], isFalse);
    expect(executions, 1);

    final Map<String, Object?> status = await call(
      3,
      'lmcp.node.status',
      const <String, Object?>{},
    );
    expect(status.toString(), isNot(contains('${lease['leaseToken']}')));
    final Map<String, Object?> released = await call(
      4,
      'lmcp.capacity.release',
      <String, Object?>{
        'leaseId': lease['leaseId'],
        'leaseToken': lease['leaseToken'],
        'reason': 'completed',
      },
    );
    expect((released['result']! as Map)['isError'], isFalse);
  });

  test('强制关闭使运行中的 tools/call 快速返回 USER_TERMINATED', () async {
    final LmcpInboundCallHub hub = LmcpInboundCallHub(
      minimumVisibleDuration: Duration.zero,
    );
    addTearDown(hub.dispose);
    final Completer<HarnessToolCallResult> blocked =
        Completer<HarnessToolCallResult>();
    bool resourceClosed = false;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.programmerCalculatorId: (
          Map<String, Object?> arguments,
        ) async => <String, Object?>{'unused': true},
      },
    );
    final VibekitsLmcpProtocol protocol = VibekitsLmcpProtocol(
      instanceId: 'com.vibekits.desktop:0123456789',
      serverVersion: '1.9.0',
      bridge: bridge,
      callHub: hub,
      invocationRunner:
          (
            HarnessToolDefinition tool,
            Map<String, Object?> arguments,
            LmcpInboundCallCancellation cancellation,
            LmcpInboundCallHandle call,
          ) {
            cancellation.addCleanupHook(() => resourceClosed = true);
            call.update(taskId: 'task-cancellable', progress: 0.2);
            return blocked.future;
          },
    );

    final Future<Map<String, Object?>?> pending = protocol.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 77,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.programmerCalculatorId,
          'arguments': <String, Object?>{'expression': '1+1'},
        },
      },
      caller: const LmcpCallerIdentity(
        appId: 'com.newlink.kemi',
        instanceId: 'com.newlink.kemi:device-d',
        address: '192.168.3.11',
      ),
    );
    expect(hub.snapshots.single.taskId, 'task-cancellable');

    final Stopwatch stopwatch = Stopwatch()..start();
    await hub.forceClose(hub.snapshots.single.traceId);
    final Map<String, Object?> response = (await pending.timeout(
      const Duration(milliseconds: 500),
    ))!;
    stopwatch.stop();
    final Map<Object?, Object?> result =
        response['result']! as Map<Object?, Object?>;
    final Map<Object?, Object?> structured =
        result['structuredContent']! as Map<Object?, Object?>;
    expect(result['isError'], isTrue);
    expect(structured['code'], LmcpUserTerminatedException.code);
    expect(structured['cancelled'], isTrue);
    expect(resourceClosed, isTrue);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
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
    expect(response.statusCode, HttpStatus.unauthorized);
    final Map<String, Object?> responseJson = Map<String, Object?>.from(
      jsonDecode(await utf8.decodeStream(response)) as Map,
    );
    final Map<Object?, Object?> error =
        responseJson['error']! as Map<Object?, Object?>;
    expect(
      (error['data']! as Map<Object?, Object?>)['code'],
      'CALLER_IDENTITY_REQUIRED',
    );

    await server.stop();
    expect(server.running, isFalse);
    expect(discovery.enabled, isFalse);
    expect(discovery.advertisement, isNull);
  });
}

Object? _canonicalize(Object? value) {
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalize(value[key]),
    };
  }
  return value;
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
