import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/local_models/presentation/deepseek_agent_workspace.dart';

void main() {
  test('Harness Web 与智能体参数固定使用官方包', () async {
    final Directory workspace = await Directory.systemTemp.createTemp(
      'vibekits_harness_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final HarnessLaunchSpec web = HarnessLaunchSpec(
      workspace: workspace.path,
      port: 3080,
    );
    final HarnessAgentRequest agent = HarnessAgentRequest(
      workspace: workspace.path,
      prompt: '检查失败的测试',
    );
    web.validate();
    agent.validate();
    expect(web.arguments, <String>[
      '--yes',
      '@deepseek-ai/dsh@0.1.0-rc.5',
      'web',
      '--port',
      '3080',
    ]);
    expect(agent.arguments, <String>[
      '--yes',
      '@deepseek-ai/dsh@0.1.0-rc.5',
      '--profile',
      'headless',
      '检查失败的测试',
    ]);
  });

  testWidgets('智能体选择工作区后在应用内流式运行任务', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_agent_ui_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final _FakeAgentHandle handle = _FakeAgentHandle();
    addTearDown(handle.dispose);
    HarnessAgentRequest? launched;
    String? savedWorkspace;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '运行环境已就绪',
            ),
            pickDirectory: () async => workspace.path,
            runAgent: (HarnessAgentRequest request) async {
              launched = request;
              return handle;
            },
            onWorkspaceChanged: (String path) async {
              savedWorkspace = path;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-pick-workspace')));
    await tester.pumpAndSettle();
    expect(savedWorkspace, workspace.path);
    await tester.enterText(find.byKey(const Key('agent-composer')), '修复失败的测试');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(launched?.workspace, workspace.path);
    expect(launched?.prompt, '修复失败的测试');
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);
    handle.add('已定位并修复测试。');
    await tester.pump();
    expect(find.text('已定位并修复测试。'), findsOneWidget);
    await handle.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-send')), findsOneWidget);
  });
}

class _FakeAgentHandle implements HarnessAgentHandle {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  bool _running = true;

  void add(String value) => _output.add(value);

  Future<void> complete(int code) async {
    if (!_running) return;
    _running = false;
    _exit.complete(code);
  }

  Future<void> dispose() => _output.close();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  bool get running => _running;

  @override
  Future<void> stop() async => complete(0);
}
