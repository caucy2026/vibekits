import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/lark_cli_service.dart';

void main() {
  late Directory temporary;
  late File executable;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('vibekits_lark_cli_');
    executable = File(
      '${temporary.path}${Platform.pathSeparator}'
      '${Platform.isWindows ? 'lark-cli.exe' : 'lark-cli'}',
    );
    await executable.writeAsBytes(const <int>[0]);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('解析官方JSON失败契约并把配置隔离到指定目录', () async {
    late Map<String, String> capturedEnvironment;
    late List<String> invoked;
    final LarkCliService service = LarkCliService(
      executable: executable.path,
      configDirectory: '${temporary.path}${Platform.pathSeparator}config',
      runner:
          (
            String path,
            List<String> arguments, {
            required Map<String, String> environment,
            required Duration timeout,
          }) async {
            invoked = arguments;
            capturedEnvironment = Map<String, String>.of(environment);
            return ProcessResult(
              1,
              1,
              '',
              '{"ok":false,"error":{"subtype":"not_configured"}}',
            );
          },
    );

    final Map<String, Object?> result = await service.authStatus();

    expect(invoked, <String>['auth', 'status']);
    expect(capturedEnvironment['LARKSUITE_CLI_CONFIG_DIR'], contains('config'));
    expect(result['ok'], isFalse);
    expect((result['envelope']! as Map<String, dynamic>)['ok'], isFalse);
  });

  test('Schema命令保持为参数数组且不经过shell', () async {
    late List<String> invoked;
    final LarkCliService service = LarkCliService(
      executable: executable.path,
      runner:
          (
            String path,
            List<String> arguments, {
            required Map<String, String> environment,
            required Duration timeout,
          }) async {
            invoked = arguments;
            return ProcessResult(1, 0, '{"ok":true}', '');
          },
    );

    await service.schema('calendar.events.get');

    expect(invoked, <String>['schema', 'calendar.events.get']);
  });

  test('拒绝通过MCP参数传入飞书秘密', () async {
    final LarkCliService service = LarkCliService(executable: executable.path);

    await expectLater(
      service.execute(const <String>['config', 'set', '--app-secret=secret']),
      throwsA(isA<FormatException>()),
    );
  });

  test('Release工具目录通过Harness桥接读取真实官方Schema', () async {
    final String toolsRoot =
        '${Directory.current.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
        '${Platform.pathSeparator}runner${Platform.pathSeparator}Release'
        '${Platform.pathSeparator}tools';
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
      runtimeToolRoot: toolsRoot,
    );
    addTearDown(bridge.dispose);
    Future<bool> approve(HarnessToolApprovalRequest _) async => true;

    final HarnessToolCallResult inspected = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.larkCliInspectId,
      arguments: const <String, Object?>{},
      approve: approve,
    );
    final HarnessToolCallResult schema = await bridge.invoke(
      toolId: VibekitsHarnessToolBridge.larkCliSchemaId,
      arguments: const <String, Object?>{'command': 'calendar.events.get'},
      approve: approve,
    );

    expect(inspected.ok, isTrue);
    expect(inspected.data.toString(), contains('v1.0.92'));
    expect(schema.ok, isTrue);
    expect(schema.data.toString(), contains('calendar_id'));
    expect(schema.data.toString(), contains('calendar:calendar:readonly'));
  }, skip: !Platform.isWindows);
}
