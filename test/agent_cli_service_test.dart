import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/agent_cli_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';

void main() {
  late Directory temporaryDirectory;
  late File helper;

  setUp(() async {
    temporaryDirectory = Directory(
      '.tmp${Platform.pathSeparator}agent-cli-service-test',
    ).absolute;
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
    await temporaryDirectory.create(recursive: true);
    helper = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}helper.dart',
    );
    await helper.writeAsString(r'''
import 'dart:async';
import 'dart:io';
Future<void> main(List<String> args) async {
  stdout.write('OUT:${args.join('|')}');
  stderr.write('ERR');
  if (args.contains('wait')) await Future<void>.delayed(const Duration(seconds: 30));
  if (args.contains('fail')) exitCode = 7;
}
''');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  AgentCliService service() => AgentCliService(
    executableOverrides: <String, String>{'codex': _dartExecutableForTest()},
  );

  test(
    'catalog exposes seven stable providers and real availability',
    () async {
      final Map<String, Object?> result = await service().catalog();
      final List<Object?> providers = result['providers']! as List<Object?>;
      expect(providers, hasLength(7));
      final Map<String, Object?> codex = providers
          .cast<Map<String, Object?>>()
          .singleWhere(
            (Map<String, Object?> item) => item['providerId'] == 'codex',
          );
      expect(codex['available'], isTrue);
      expect(codex['source'], 'override');
    },
  );

  test('executes argv without shell and preserves bounded output', () async {
    final Map<String, Object?> result = await service().execute(
      'codex',
      <String>[helper.path, 'alpha beta', 'gamma'],
      workingDirectory: temporaryDirectory.path,
    );
    expect(result['state'], 'succeeded');
    expect(result['stdout'], 'OUT:alpha beta|gamma');
    expect(result['stderr'], 'ERR');
    expect(result['workingDirectory'], temporaryDirectory.path);
  });

  test('rejects secret arguments and unknown providers', () async {
    await expectLater(
      service().execute('codex', <String>[helper.path, '--api-key', 'secret']),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service().inspect('unknown'),
      throwsA(isA<FormatException>()),
    );
  });

  test('long task is pollable and reaches a truthful terminal state', () async {
    final AgentCliService instance = service();
    final Map<String, Object?> started = await instance.startTask(
      'codex',
      <String>[helper.path, 'done'],
    );
    expect(started['running'], isTrue);
    final String taskId = started['taskId']! as String;
    final Map<String, Object?> finished = await _waitForTerminal(
      instance,
      taskId,
    );
    expect(finished['state'], 'succeeded');
    expect(finished['stdout'], 'OUT:done');
  });

  test('long task can be cancelled idempotently by its task id', () async {
    final AgentCliService instance = service();
    final Map<String, Object?> started = await instance.startTask(
      'codex',
      <String>[helper.path, 'wait'],
    );
    final String taskId = started['taskId']! as String;
    final Map<String, Object?> cancelled = await instance.cancel(taskId);
    expect(cancelled['state'], 'cancelled');
    expect((await instance.cancel(taskId))['state'], 'cancelled');
    expect(
      () => instance.status('agent-cli-codex-forged'),
      throwsA(isA<FormatException>()),
    );
  });

  test('timeout produces timedOut instead of success', () async {
    final AgentCliService instance = service();
    final Map<String, Object?> started = await instance.startTask(
      'codex',
      <String>[helper.path, 'wait'],
      timeout: const Duration(milliseconds: 100),
    );
    final Map<String, Object?> finished = await _waitForTerminal(
      instance,
      started['taskId']! as String,
    );
    expect(finished['state'], 'timedOut');
  });

  test('bridge exports complete schemas and risks for all six tools', () {
    final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge();
    final Map<String, HarnessToolDefinition> catalog =
        <String, HarnessToolDefinition>{
          for (final HarnessToolDefinition tool in bridge.executableCatalog)
            tool.id: tool,
        };
    const Set<String> expected = <String>{
      VibekitsHarnessToolBridge.agentCliCatalogId,
      VibekitsHarnessToolBridge.agentCliInspectId,
      VibekitsHarnessToolBridge.agentCliExecuteId,
      VibekitsHarnessToolBridge.agentCliTaskStartId,
      VibekitsHarnessToolBridge.agentCliTaskStatusId,
      VibekitsHarnessToolBridge.agentCliTaskCancelId,
    };
    expect(catalog.keys, containsAll(expected));
    expect(
      catalog[VibekitsHarnessToolBridge.agentCliCatalogId]!.risk,
      HarnessToolRisk.readOnly,
    );
    expect(
      catalog[VibekitsHarnessToolBridge.agentCliExecuteId]!.risk,
      HarnessToolRisk.controlsDevice,
    );
    expect(
      catalog[VibekitsHarnessToolBridge.agentCliTaskStartId]!.inputSchema,
      containsPair('additionalProperties', false),
    );
  });
}

String _dartExecutableForTest() {
  Directory cursor = File(Platform.resolvedExecutable).parent;
  for (int level = 0; level < 8; level++) {
    final File candidate = File(
      '${cursor.path}${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}'
      '${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (candidate.existsSync()) return candidate.path;
    cursor = cursor.parent;
  }
  throw StateError('Unable to locate the Dart SDK executable for tests');
}

Future<Map<String, Object?>> _waitForTerminal(
  AgentCliService service,
  String taskId,
) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    final Map<String, Object?> result = service.status(taskId);
    if (result['running'] != true) return result;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('test task did not finish');
}
