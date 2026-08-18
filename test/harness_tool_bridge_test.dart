import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  test('导出版本化可执行工具目录且不暴露未接工具', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Map<String, Object?> catalog = bridge.exportCatalog();
    expect(catalog['protocol'], VibekitsHarnessToolBridge.protocolVersion);
    final List<dynamic> tools = catalog['tools']! as List<dynamic>;
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.sha256'),
      isTrue,
    );
    expect(
      tools.any((dynamic tool) => tool['id'] == 'vibekits.database_manager'),
      isFalse,
    );
    expect(
      tools.any(
        (dynamic tool) =>
            tool['id'] == VibekitsHarnessToolBridge.adbListDevicesId,
      ),
      isTrue,
    );
    for (final String id in <String>[
      VibekitsHarnessToolBridge.adbCommandId,
      VibekitsHarnessToolBridge.serialListPortsId,
      VibekitsHarnessToolBridge.serialTransactId,
      VibekitsHarnessToolBridge.sqliteInspectId,
      VibekitsHarnessToolBridge.sqliteQueryId,
      VibekitsHarnessToolBridge.gitInspectId,
      VibekitsHarnessToolBridge.fileSearchId,
      VibekitsHarnessToolBridge.apiRequestId,
      VibekitsHarnessToolBridge.githubDiagnosticsId,
      VibekitsHarnessToolBridge.programmerCalculatorId,
    ]) {
      expect(tools.any((dynamic tool) => tool['id'] == id), isTrue, reason: id);
    }
  });

  test('只读文本工具无需审批并返回结构化结果', () async {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    int approvals = 0;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.sha256',
      arguments: <String, Object?>{'input': 'abc'},
      approve: (_) async {
        approvals++;
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(approvals, 0);
    expect(
      result.data?['output'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('ADB 连接先展示规范化目标并取得一次性批准', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: 'C:\\tools\\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'connected to 192.168.3.63:5555',
          stderr: '',
        );
      },
    );
    HarnessToolApprovalRequest? approval;
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbConnectId,
      arguments: <String, Object?>{'address': '192.168.3.63'},
      approve: (HarnessToolApprovalRequest request) async {
        approval = request;
        return true;
      },
    );
    expect(approval?.tool.risk, HarnessToolRisk.controlsDevice);
    expect(approval?.target, '192.168.3.63:5555');
    expect(calls.single, <String>['connect', '192.168.3.63:5555']);
    expect(result.ok, isTrue);
  });

  test('拒绝高风险工具后不执行处理器', () async {
    int calls = 0;
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      handlers: <String, HarnessToolHandler>{
        'vibekits.batch_rename': (_) async {
          calls++;
          return <String, Object?>{};
        },
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: 'vibekits.batch_rename',
      arguments: <String, Object?>{'input': 'D:\\project'},
      approve: (_) async => false,
    );
    expect(result.cancelled, isTrue);
    expect(calls, 0);
  });

  test('ADB 命令经过设备审批并使用固定可执行文件', () async {
    final List<List<String>> calls = <List<String>>[];
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      adbExecutable: r'C:\tools\adb.exe',
      adbRunner: (String executable, List<String> arguments) async {
        calls.add(arguments);
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'Pixel_8',
          stderr: '',
        );
      },
    );
    final HarnessToolCallResult result = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.adbCommandId,
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
      approve: (HarnessToolApprovalRequest request) async {
        expect(request.target, '192.168.3.63:5555');
        return true;
      },
    );
    expect(result.ok, isTrue);
    expect(calls.single, <String>[
      '-s',
      '192.168.3.63:5555',
      'shell',
      'getprop',
      'ro.product.model',
    ]);
  });

  test('SQLite 检查和查询通过桥接完成闭环', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_sqlite_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final String path = '${sandbox.path}${Platform.pathSeparator}sample.db';
    final Database database = sqlite3.open(path);
    database.execute('CREATE TABLE users(id INTEGER, name TEXT)');
    database.execute("INSERT INTO users VALUES (1, 'Ada')");
    database.close();
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();

    final HarnessToolCallResult inspect = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteInspectId,
      arguments: <String, Object?>{'path': path},
      approve: (_) async => true,
    );
    final HarnessToolCallResult query = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.sqliteQueryId,
      arguments: <String, Object?>{
        'path': path,
        'sql': 'SELECT name FROM users',
      },
      approve: (_) async => true,
    );

    expect(inspect.ok, isTrue);
    expect(inspect.data?['objects'].toString(), contains('users'));
    expect(query.ok, isTrue);
    expect(query.data?['rows'], <List<String>>[
      <String>['Ada'],
    ]);
  });

  test('文件搜索通过桥接返回结构化匹配', () async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'vibekits_harness_search_',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    await File('${sandbox.path}${Platform.pathSeparator}hello.dart')
        .writeAsString('void main() {}');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.fileSearchId,
          arguments: <String, Object?>{'root': sandbox.path, 'query': 'hello'},
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['matches'].toString(), contains('hello.dart'));
  });

  test('HTTP 工具经审批访问本地服务并回传响应', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"bridge":"ok"}');
      await request.response.close();
    });
    final Uri target = Uri.parse('http://127.0.0.1:${server.port}/health');
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.apiRequestId,
          arguments: <String, Object?>{
            'method': 'GET',
            'url': target.toString(),
          },
          approve: (HarnessToolApprovalRequest request) async {
            expect(request.target, target.toString());
            return true;
          },
        );
    expect(result.ok, isTrue);
    expect(result.data?['statusCode'], 200);
    expect(result.data?['body'], '{"bridge":"ok"}');
  });

  test('程序员计算器通过桥接返回多进制结果', () async {
    final HarnessToolCallResult result = await VibekitsHarnessToolBridge()
        .invoke(
          toolId: VibekitsHarnessToolBridge.programmerCalculatorId,
          arguments: <String, Object?>{
            'expression': '(0xFF << 2) | 3',
            'width': 16,
          },
          approve: (_) async => true,
        );
    expect(result.ok, isTrue);
    expect(result.data?['hexadecimal'], '0x03FF');
    expect(result.data?['decimal'], '1023');
  });
}
