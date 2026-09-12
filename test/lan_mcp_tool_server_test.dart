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

  test('仿真回环端点只为同一控制端 ID 预授权 SSH 公钥交换', () async {
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
