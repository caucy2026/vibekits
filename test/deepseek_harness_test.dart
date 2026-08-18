import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/local_models/presentation/deepseek_agent_workspace.dart';

void main() {
  test('Harness 固定官方内置版本且任务参数不包含安装命令', () async {
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
      apiKey: 'test-key',
    );
    web.validate();
    agent.validate();
    expect(HarnessLaunchSpec.packageSpec, '@deepseek-ai/dsh@0.1.0-rc.7');
    expect(web.arguments, isNot(contains(HarnessLaunchSpec.packageSpec)));
    expect(agent.arguments, isNot(contains(HarnessLaunchSpec.packageSpec)));
    expect(agent.arguments, isNot(contains('--yes')));
    expect(agent.arguments, contains('headless'));
    expect(agent.arguments, isNot(contains('test-key')));
    expect(agent.baseUrl, DeepSeekHarnessService.defaultBaseUrl);
    expect(agent.model, DeepSeekHarnessService.defaultModel);
  });

  testWidgets('智能体选择工作区后在应用内流式运行任务', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_agent_ui_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final List<_FakeAgentHandle> handles = <_FakeAgentHandle>[
      _FakeAgentHandle(),
      _FakeAgentHandle(),
    ];
    addTearDown(() async {
      for (final _FakeAgentHandle handle in handles) {
        await handle.dispose();
      }
    });
    final List<HarnessAgentRequest> launched = <HarnessAgentRequest>[];
    String? savedWorkspace;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '运行环境已就绪',
            ),
            pickDirectory: () async => workspace.path,
            listModels: (_, _) async => <String>[
              'deepseek-chat',
              'deepseek-reasoner',
              'deepseek-special',
            ],
            runAgent: (HarnessAgentRequest request) async {
              launched.add(request);
              return handles[launched.length - 1];
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
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-v4-pro'), findsOneWidget);
    expect(find.text('DeepSeek 官方 V4 模型 · 验证后以 /models 返回为准'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('agent-api-key')), 'test-key');
    await tester.tap(find.byKey(const Key('agent-load-models')));
    await tester.pumpAndSettle();
    expect(find.text('来自当前 API 的 /models 实时结果'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-model-deepseek-special')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-composer')), '修复失败的测试');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('agent-send')));
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(launched.single.workspace, workspace.path);
    expect(launched.single.model, 'deepseek-special');
    expect(launched.single.prompt, '修复失败的测试');
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);
    handles.first.add('已定位并修复测试。');
    await tester.pump();
    expect(find.text('已定位并修复测试。'), findsOneWidget);
    await handles.first.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-send')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('agent-composer')), '再检查一次改动');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, hasLength(2));
    expect(launched.last.prompt, contains('修复失败的测试'));
    expect(launched.last.prompt, contains('已定位并修复测试'));
    expect(launched.last.prompt, contains('再检查一次改动'));
    handles.last.add('## 复查结果\n\n全部通过。');
    await tester.pump();
    expect(find.text('复查结果'), findsOneWidget);
    await handles.last.complete(0);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent-new-task')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新任务'));
    await tester.pumpAndSettle();
    expect(find.text('今天要开发什么？'), findsOneWidget);
    expect(find.text('已定位并修复测试。'), findsNothing);
  });

  testWidgets('智能体运行中可停止并回到可输入状态', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_agent_stop_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final _FakeAgentHandle handle = _FakeAgentHandle();
    addTearDown(handle.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            initialWorkspace: workspace.path,
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '运行环境已就绪',
            ),
            runAgent: (_) async => handle,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-api-key')), 'test-key');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-composer')), '执行长任务');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('agent-send')));
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(find.byKey(const Key('agent-progress')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-stop')));
    await tester.pumpAndSettle();
    expect(handle.running, isFalse);
    expect(find.text('任务已停止。'), findsOneWidget);
    expect(find.byKey(const Key('agent-progress')), findsNothing);
  });

  testWidgets('宽屏显示社区式项目与会话侧栏', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: null,
              npxVersion: null,
              model: DeepSeekHarnessService.defaultModel,
              message: 'DeepSeek 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-session-sidebar')), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
  });

  testWidgets('设置异步恢复后工作区和 Codex 风格输入框立即更新', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_restore_workspace_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final ValueNotifier<String> restored = ValueNotifier<String>('');
    addTearDown(restored.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: restored,
            builder: (BuildContext context, String path, Widget? child) =>
                DeepSeekAgentWorkspace(
                  initialWorkspace: path,
                  credentialReader: (_) async => null,
                  credentialWriter: (_, _) async {},
                  checkEnvironment: () async => const HarnessEnvironmentReport(
                    ready: true,
                    nodeVersion: 'v24.18.0',
                    npxVersion: '11.16.0',
                    message: '已就绪',
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择工作区'), findsOneWidget);
    restored.value = workspace.path;
    await tester.pumpAndSettle();
    expect(find.text(workspace.path), findsOneWidget);

    final TextField composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.decoration?.filled, isFalse);
    expect(composer.decoration?.fillColor, Colors.transparent);
    expect(composer.decoration?.hintText, '向 Harness 描述任务…');
    expect(composer.minLines, 1);
    expect(composer.maxLines, 7);
  });

  testWidgets('同一目标同类工具操作可授权一次并在本会话复用', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_session_approval_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final _FakeAgentHandle handle = _FakeAgentHandle();
    addTearDown(handle.dispose);
    HarnessAgentRequest? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
            runAgent: (HarnessAgentRequest request) async {
              launched = request;
              return handle;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-composer')), '检查设备');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();

    const HarnessToolDefinition tool = HarnessToolDefinition(
      id: VibekitsHarnessToolBridge.adbCommandId,
      name: '执行 ADB 命令',
      description: '执行受限 ADB 参数',
      risk: HarnessToolRisk.controlsDevice,
      inputSchema: <String, Object?>{},
      available: true,
    );
    const HarnessToolApprovalRequest getprop = HarnessToolApprovalRequest(
      tool: tool,
      target: '192.168.3.63:5555',
      arguments: <String, Object?>{
        'serial': '192.168.3.63:5555',
        'arguments': <String>['shell', 'getprop', 'ro.product.model'],
      },
    );
    final Future<bool> first = launched!.approveTool!(getprop);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('agent-approve-session')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-approve-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(await first, isTrue);

    expect(await launched!.approveTool!(getprop), isTrue);
    await tester.pump();
    expect(find.text('允许 执行 ADB 命令？'), findsNothing);

    await handle.complete(0);
    await tester.pumpAndSettle();
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
