import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lan_mcp_tool_server.dart';

void main() {
  test('LAN MCP exposes standard tool catalog and executes a tool', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.programmerCalculatorId:
            (Map<String, Object?> arguments) async => <String, Object?>{
              'received': arguments['expression'],
            },
      },
    );
    final LanMcpToolServer server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);

    final Map<String, Object?> initialized = await _request(
      server.loopbackEndpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{},
      },
    );
    expect(
      (initialized['result'] as Map)['protocolVersion'],
      LanMcpToolServer.mcpProtocolVersion,
    );

    final Map<String, Object?> catalog = await _request(
      server.loopbackEndpoint,
      <String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    );
    final List<Object?> tools = ((catalog['result'] as Map)['tools'] as List)
        .cast<Object?>();
    expect(
      tools.whereType<Map>().any(
        (Map tool) =>
            tool['name'] == VibekitsHarnessToolBridge.programmerCalculatorId,
      ),
      isTrue,
    );

    final Map<String, Object?> called = await _request(
      server.loopbackEndpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.programmerCalculatorId,
          'arguments': <String, Object?>{'expression': '1+2'},
        },
      },
    );
    final Map result = called['result']! as Map;
    expect(result['isError'], isFalse);
    expect(
      ((result['structuredContent'] as Map)['data'] as Map)['received'],
      '1+2',
    );
  });

  test('仿真回环端点只为原生通道已认证的同一控制端预授权 SSH 公钥交换', () async {
    var invoked = false;
    final bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.deviceSshAuthorizeId: (arguments) async {
          invoked = true;
          return <String, Object?>{
            'authorized': true,
            'peerId': arguments['peerId'],
          };
        },
      },
    );
    final server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: (callerId) async => callerId == '8296293831',
    );
    addTearDown(server.close);

    final response = await _request(
      server.loopbackEndpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.deviceSshAuthorizeId,
          'arguments': <String, Object?>{
            'peerId': '8296293831',
            'publicKey': 'ssh-ed25519 test',
          },
        },
      },
      headers: const <String, String>{'x-vibekits-caller-id': '8296293831'},
    ).timeout(const Duration(seconds: 2));

    expect(invoked, isTrue);
    expect((response['result'] as Map)['isError'], isFalse);
  });

  test('远程仿真开关授权一次后同一控制端安装卸载不再逐次批准', () async {
    final invoked = <String>[];
    final bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.deviceAppInstallId: (arguments) async {
          invoked.add('install');
          return <String, Object?>{'installed': true};
        },
        VibekitsHarnessToolBridge.deviceAppUninstallId: (arguments) async {
          invoked.add('uninstall');
          return <String, Object?>{'uninstalled': true};
        },
      },
    );
    final server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: (callerId) async => callerId == '8296293831',
    );
    addTearDown(server.close);

    for (final toolId in <String>[
      VibekitsHarnessToolBridge.deviceAppInstallId,
      VibekitsHarnessToolBridge.deviceAppUninstallId,
    ]) {
      final response = await _request(
        server.loopbackEndpoint,
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': toolId,
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': toolId,
            'arguments': <String, Object?>{'target': 'signed-test-package'},
          },
        },
        headers: const <String, String>{'x-vibekits-caller-id': '8296293831'},
      ).timeout(const Duration(seconds: 2));
      expect((response['result'] as Map)['isError'], isFalse);
    }
    expect(invoked, <String>['install', 'uninstall']);
  });

  test('普通 LAN MCP 或缺少有效控制端 ID 仍不能继承仿真授权', () async {
    var invoked = false;
    final bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.deviceAppUninstallId: (arguments) async {
          invoked = true;
          return <String, Object?>{'uninstalled': true};
        },
      },
    );
    final server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: (_) async => true,
      sensitiveApprovalTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(server.close);

    final response = await _request(server.loopbackEndpoint, <String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': VibekitsHarnessToolBridge.deviceAppUninstallId,
        'arguments': <String, Object?>{'target': 'must-not-run'},
      },
    });
    expect((response['result'] as Map)['isError'], isTrue);
    expect(invoked, isFalse);
  });

  test('伪造有效格式的控制端 ID 不能绕过原生通道身份校验', () async {
    var invoked = false;
    final bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.deviceAppUninstallId: (arguments) async {
          invoked = true;
          return <String, Object?>{'uninstalled': true};
        },
      },
    );
    final server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: (_) async => false,
      sensitiveApprovalTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(server.close);

    final response = await _request(
      server.loopbackEndpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 8,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.deviceAppUninstallId,
          'arguments': <String, Object?>{'target': 'must-not-run'},
        },
      },
      headers: const <String, String>{'x-vibekits-caller-id': '8296293831'},
    );
    expect((response['result'] as Map)['isError'], isTrue);
    expect(invoked, isFalse);
  });

  test('只读工具绝不等待敏感授权身份查询', () async {
    var authorizationQueries = 0;
    final bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        VibekitsHarnessToolBridge.deviceProcessesId: (arguments) async =>
            <String, Object?>{'processes': <Object?>[]},
      },
    );
    final server = await LanMcpToolServer.start(
      bridge: bridge,
      bindAddress: InternetAddress.loopbackIPv4,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: (_) async {
        authorizationQueries++;
        await Completer<void>().future;
        return false;
      },
    );
    addTearDown(server.close);

    final response = await _request(
      server.loopbackEndpoint,
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 9,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': VibekitsHarnessToolBridge.deviceProcessesId,
          'arguments': const <String, Object?>{},
        },
      },
      headers: const <String, String>{'x-vibekits-caller-id': '8296293831'},
    ).timeout(const Duration(seconds: 1));
    expect((response['result'] as Map)['isError'], isFalse);
    expect(authorizationQueries, 0);
  });
}

Future<Map<String, Object?>> _request(
  Uri endpoint,
  Map<String, Object?> payload, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.write(jsonEncode(payload));
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok, reason: body);
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}
