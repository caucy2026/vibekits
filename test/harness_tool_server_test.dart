import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_server.dart';

void main() {
  test('回环服务要求随机令牌并完成工具调用', () async {
    final HarnessToolServer server = await HarnessToolServer.start();
    addTearDown(server.close);
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));

    final HttpClientRequest denied = await client.getUrl(
      server.endpoint.replace(path: '/catalog'),
    );
    expect((await denied.close()).statusCode, HttpStatus.unauthorized);

    final HttpClientRequest catalogRequest = await client.getUrl(
      server.endpoint.replace(path: '/catalog'),
    );
    catalogRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${server.token}',
    );
    final HttpClientResponse catalogResponse = await catalogRequest.close();
    final Map<String, Object?> catalog = Map<String, Object?>.from(
      jsonDecode(await utf8.decoder.bind(catalogResponse).join()) as Map,
    );
    expect(catalog['protocol'], 'vibekits.tools.v1');

    final HttpClientRequest invoke = await client.postUrl(
      server.endpoint.replace(path: '/invoke'),
    );
    invoke.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${server.token}',
    );
    invoke.write(
      jsonEncode(<String, Object?>{
        'toolId': 'vibekits.sha256',
        'arguments': <String, Object?>{'input': 'abc'},
      }),
    );
    final Map<String, Object?> result = Map<String, Object?>.from(
      jsonDecode(await utf8.decoder.bind(await invoke.close()).join()) as Map,
    );
    expect(result['ok'], isTrue);
    expect(result.toString(), contains('ba7816bf8f01cfea'));
  });

  test('外部 Codex connection file 原子发布并在关闭时移除', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'vibekits_mcp_connection_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File connection = File(
      '${directory.path}${Platform.pathSeparator}tool-bridge.json',
    );
    final HarnessToolServer server = await HarnessToolServer.start(
      connectionFile: connection,
    );
    expect(await connection.exists(), isTrue);
    final Map<String, Object?> published = Map<String, Object?>.from(
      jsonDecode(await connection.readAsString()) as Map,
    );
    expect(published['version'], 1);
    expect(published['endpoint'], server.endpoint.toString());
    expect(published['token'], server.token);
    expect(Uri.parse('${published['endpoint']}').host, '127.0.0.1');
    await server.close();
    expect(await connection.exists(), isFalse);
  });

  test('未提供界面审批时高风险工具默认拒绝', () async {
    final HarnessToolServer server = await HarnessToolServer.start();
    addTearDown(server.close);
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));
    final HttpClientRequest invoke = await client.postUrl(
      server.endpoint.replace(path: '/invoke'),
    );
    invoke.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${server.token}',
    );
    invoke.write(
      jsonEncode(<String, Object?>{
        'toolId': 'vibekits.adb.connect',
        'arguments': <String, Object?>{'address': '192.168.3.63'},
      }),
    );
    final Map<String, Object?> result = Map<String, Object?>.from(
      jsonDecode(await utf8.decoder.bind(await invoke.close()).join()) as Map,
    );
    expect(result['cancelled'], isTrue);
  });

  test('Harness 原生工具授权请求进入统一界面审批器', () async {
    HarnessToolApprovalRequest? received;
    final HarnessToolServer server = await HarnessToolServer.start(
      approve: (HarnessToolApprovalRequest request) async {
        received = request;
        return true;
      },
    );
    addTearDown(server.close);
    final HttpClient client = HttpClient();
    addTearDown(() => client.close(force: true));

    final HttpClientRequest request = await client.postUrl(
      server.endpoint.replace(path: '/native-approval'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${server.token}',
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'toolName': 'PowerShell',
        'callId': 'call-7',
        'reason': 'git status',
        'workspace': r'D:\project',
      }),
    );
    final HttpClientResponse response = await request.close();
    final Map<String, Object?> payload = Map<String, Object?>.from(
      jsonDecode(await utf8.decoder.bind(response).join()) as Map,
    );

    expect(payload['allowed'], isTrue);
    expect(received?.tool.id, 'harness.native.powershell');
    expect(received?.arguments['callId'], 'call-7');
    expect(received?.target, r'D:\project');
  });

  test('内置 Node MCP 进程发现并调用 Vibekits 工具', () async {
    final Directory connectionDirectory = await Directory.systemTemp.createTemp(
      'vibekits_mcp_node_test',
    );
    addTearDown(() => connectionDirectory.delete(recursive: true));
    final File connectionFile = File(
      '${connectionDirectory.path}${Platform.pathSeparator}tool-bridge.json',
    );
    final HarnessToolServer bridge = await HarnessToolServer.start(
      connectionFile: connectionFile,
    );
    addTearDown(bridge.close);
    final String root = Directory.current.path;
    final String runtime =
        '$root${Platform.pathSeparator}native${Platform.pathSeparator}harness'
        '${Platform.pathSeparator}${Platform.isWindows ? 'windows' : 'macos'}'
        '${Platform.pathSeparator}runtime';
    final String externalMcp =
        '$runtime${Platform.pathSeparator}'
        'vibekits-codex-mcp.mjs';
    final String node = Platform.isWindows
        ? '$runtime${Platform.pathSeparator}node.exe'
        : '$runtime${Platform.pathSeparator}bin${Platform.pathSeparator}node';
    final Process process = await Process.start(
      node,
      <String>[externalMcp],
      environment: <String, String>{
        'VIBEKITS_TOOL_BRIDGE_FILE': connectionFile.path,
      },
      includeParentEnvironment: true,
      runInShell: false,
    );
    addTearDown(() {
      process.kill();
    });
    final Map<int, Completer<Map<String, Object?>>> pending =
        <int, Completer<Map<String, Object?>>>{};
    final StreamSubscription<String> output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          final Map<String, Object?> message = Map<String, Object?>.from(
            jsonDecode(line) as Map,
          );
          final int? id = message['id'] as int?;
          pending.remove(id)?.complete(message);
        });
    addTearDown(output.cancel);

    Future<Map<String, Object?>> rpc(int id, String method, Object params) {
      final Completer<Map<String, Object?>> completer =
          Completer<Map<String, Object?>>();
      pending[id] = completer;
      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        }),
      );
      return completer.future.timeout(const Duration(seconds: 10));
    }

    final Map<String, Object?> initialized = await rpc(
      1,
      'initialize',
      <String, Object?>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'vibekits-test',
          'version': '1',
        },
      },
    );
    expect(initialized['result'], isA<Map>());
    process.stdin.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
    );
    final Map<String, Object?> listed = await rpc(
      2,
      'tools/list',
      <String, Object?>{},
    );
    expect(listed.toString(), contains('sha256'));
    final Map<String, Object?> called = await rpc(
      3,
      'tools/call',
      <String, Object?>{
        'name': 'sha256',
        'arguments': <String, Object?>{'input': 'abc'},
      },
    );
    expect(called.toString(), contains('ba7816bf8f01cfea'));
  });
}
