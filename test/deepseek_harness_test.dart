import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_agent_preferences.dart';
import 'package:vibekits/features/dev_tools/domain/harness_conversation_store.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/harness_work_status.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/local_models/presentation/deepseek_agent_workspace.dart';

void main() {
  tearDown(() async {
    // The production discovery singleton intentionally lives for the whole
    // application. Widget tests must release its socket and periodic timers
    // explicitly because destroying one workspace does not end the app.
    await LanPeerDiscoveryService.instance.stop();
  });

  test('macOS Harness runtime 从主程序或 App.framework 都能定位 App bundle', () {
    const String bundle = '/Applications/Vibekits.app';
    expect(
      macOsAppBundleForExecutable('$bundle/Contents/MacOS/Vibekits')?.path,
      bundle,
    );
    expect(
      macOsAppBundleForExecutable(
        '$bundle/Contents/Frameworks/App.framework/Versions/A/App',
      )?.path,
      bundle,
    );
    expect(macOsAppBundleForExecutable('/usr/bin/dart'), isNull);
  });

  test('Harness 调试目录创建 logs screenshots temp 三个子目录', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vibekits_harness_debug_',
    );
    await root.delete(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final HarnessDebugPaths paths =
        await DeepSeekHarnessService.prepareDebugDirectory(root.path);
    expect(paths.root.path, root.path);
    expect(await paths.logs.exists(), isTrue);
    expect(await paths.screenshots.exists(), isTrue);
    expect(await paths.temp.exists(), isTrue);
  });

  test('Harness 调试日志输出会移除 API Key', () {
    const String key = 'sk-vibekits-canary-secret';
    final String safe = DeepSeekHarnessService.redactSensitiveOutput(
      'request failed: Authorization Bearer $key',
      const <String>[key],
    );
    expect(safe, isNot(contains(key)));
    expect(safe, contains('[REDACTED]'));
  });

  test('旧 Key 一次迁移到官方可写凭据文件且不覆盖新 Key', () async {
    final Directory home = await Directory.systemTemp.createTemp(
      'vibekits_harness_credentials_',
    );
    addTearDown(() => home.delete(recursive: true));

    expect(
      await DeepSeekHarnessService.migrateLegacyCredentialToOfficialStore(
        'sk-legacy',
        harnessHome: home,
      ),
      HarnessCredentialMigration.migrated,
    );
    final File credentials = File(
      '${home.path}${Platform.pathSeparator}.credentials.yaml',
    );
    expect(await credentials.readAsString(), contains('"sk-legacy"'));

    expect(
      await DeepSeekHarnessService.migrateLegacyCredentialToOfficialStore(
        'sk-must-not-overwrite',
        harnessHome: home,
      ),
      HarnessCredentialMigration.alreadyConfigured,
    );
    final String persisted = await credentials.readAsString();
    expect(persisted, contains('"sk-legacy"'));
    expect(persisted, isNot(contains('sk-must-not-overwrite')));
  });

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
    final HarnessWebRequest officialWeb = HarnessWebRequest(
      workspace: workspace.path,
      apiKey: '',
      port: 31888,
    );
    web.validate();
    agent.validate();
    officialWeb.validate();
    expect(HarnessLaunchSpec.packageSpec, '@deepseek-ai/dsh@0.1.1-rc.2');
    expect(web.arguments, isNot(contains(HarnessLaunchSpec.packageSpec)));
    expect(agent.arguments, isNot(contains(HarnessLaunchSpec.packageSpec)));
    expect(agent.arguments, isNot(contains('--yes')));
    expect(agent.arguments, contains('headless'));
    expect(agent.arguments, isNot(contains('test-key')));
    expect(agent.baseUrl, DeepSeekHarnessService.defaultBaseUrl);
    expect(agent.model, DeepSeekHarnessService.defaultModel);
    expect(agent.nativeSandboxMode, 'workspace-write');
    expect(officialWeb.arguments, <String>[
      'web',
      '--port',
      '31888',
      '--no-open',
    ]);
    expect(officialWeb.url, Uri.parse('http://127.0.0.1:31888'));
    expect(
      HarnessAgentRequest(
        workspace: workspace.path,
        prompt: 'test',
        apiKey: 'test-key',
        permissionMode: HarnessAgentPermissionMode.fullAccess,
      ).nativeSandboxMode,
      'danger-full-access',
    );
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
    HarnessConversationProject? savedConversation;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => 'test-key',
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
            loadConversation: (_) async => savedConversation,
            saveConversation: (HarnessConversationProject project) async {
              savedConversation = project;
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('agent-pick-workspace')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(savedWorkspace, workspace.path);
    await tester.ensureVisible(find.byKey(const Key('agent-settings')));
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Harness 模型设置'), findsOneWidget);
    expect(find.text(DeepSeekHarnessService.defaultModel), findsWidgets);
    expect(find.byKey(const Key('agent-load-models')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('agent-api-key')), 'test-key');
    await tester.tap(find.byKey(const Key('agent-load-models')));
    await tester.pumpAndSettle();
    expect(find.text('来自当前 API 的 /models 实时结果'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('agent-model-deepseek-special')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('agent-model-deepseek-special')));
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
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
    expect(
      find.byKey(const Key('agent-persisted-execution-trace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-persisted-trace-details')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('agent-persisted-trace-toggle')));
    await tester.pump();
    expect(
      find.byKey(const Key('agent-persisted-trace-details')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('agent-persisted-step-0')), findsOneWidget);
    expect(find.byKey(const Key('agent-persisted-step-1')), findsOneWidget);
    expect(find.text('理解任务'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-persisted-trace-toggle')));
    await tester.pump();
    expect(
      find.byKey(const Key('agent-persisted-trace-details')),
      findsNothing,
    );

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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天要开发什么？'), findsOneWidget);
    expect(find.text('已定位并修复测试。'), findsNothing);
    expect(savedConversation?.sessions, hasLength(2));
    expect(
      savedConversation?.sessions
          .expand((HarnessConversationSession session) => session.messages)
          .any(
            (HarnessConversationMessage message) =>
                !message.user && message.executionTrace.contains('执行时间线'),
          ),
      isTrue,
    );
    expect(
      savedConversation?.sessions.any(
        (HarnessConversationSession session) => session.title == '修复失败的测试',
      ),
      isTrue,
    );
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
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            initialWorkspace: workspace.path,
            saveConversation: (_) async {},
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
    await tester.enterText(find.byKey(const Key('agent-composer')), '执行长任务');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('agent-send')));
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(find.byKey(const Key('agent-progress')), findsOneWidget);
    expect(find.byKey(const Key('agent-reasoning-progress')), findsOneWidget);
    expect(find.byKey(const Key('agent-progress-details')), findsNothing);
    expect(find.text('规划操作'), findsWidgets);
    await tester.tap(find.byKey(const Key('agent-progress-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('agent-progress-details')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-stop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(handle.running, isFalse);
    expect(find.text('任务已停止。'), findsOneWidget);
    expect(find.byKey(const Key('agent-progress')), findsNothing);
  });

  testWidgets('历史 48 步时间线逐项显示且不铺开超长 JSON', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.reset);
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_timeline_48_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final DateTime now = DateTime.now();
    final String longValue = List<String>.filled(420, 'x').join();
    final String trace = <String>[
      '### 执行时间线',
      for (int index = 0; index < 48; index++)
        '✓ **调用工具 $index** — 目标：测试设备 '
            '参数：{"payload":"$longValue"} '
            '结果：{"ok":true,"raw":"$longValue"} '
            '状态：执行成功 耗时：${index + 1} ms',
    ].join('\n');
    final HarnessConversationProject project = HarnessConversationProject(
      workspace: workspace.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'timeline-48',
          title: '历史时间线',
          messages: <HarnessConversationMessage>[
            const HarnessConversationMessage(text: '执行测试', user: true),
            HarnessConversationMessage(
              text: '任务已完成。',
              user: false,
              executionTrace: trace,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeSessionId: 'timeline-48',
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            loadWorkspaceCatalog: () async => <String>[workspace.path],
            loadConversation: (_) async => project,
            saveConversation: (_) async {},
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v22.19.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('执行时间线 · 48 步'), findsOneWidget);
    expect(
      find.byKey(const Key('agent-persisted-trace-details')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('agent-persisted-trace-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('agent-persisted-step-0')), findsOneWidget);
    expect(find.byKey(const Key('agent-persisted-step-47')), findsOneWidget);
    expect(find.text('调用工具 0'), findsOneWidget);
    expect(find.text('调用工具 47'), findsOneWidget);
    expect(find.textContaining(longValue), findsNothing);
    expect(find.textContaining('结果：已保存完整输出，点击这一步查看'), findsNWidgets(48));
  });

  testWidgets('Harness 调试目录可选择保存并创建真实分类目录', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vibekits_debug_setting_',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final Directory selected = Directory(
      '${sandbox.path}${Platform.pathSeparator}selected-debug',
    );
    String? savedDirectory;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            debugDirectoryPicker: () async => selected.path,
            onDebugDirectoryChanged: (String path) async {
              savedDirectory = path;
            },
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('agent-settings')));
    await tester.tap(find.byKey(const Key('agent-settings')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-pick-debug-directory')));
    await tester.pump();
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('agent-debug-directory')),
    );
    expect(field.controller?.text, selected.path);

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
        .onPressed!();
    await tester.pumpAndSettle();
    for (int attempt = 0; attempt < 20 && savedDirectory == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(savedDirectory, selected.path);
    expect(
      Directory('${selected.path}${Platform.pathSeparator}logs').existsSync(),
      isTrue,
    );
    expect(
      Directory(
        '${selected.path}${Platform.pathSeparator}screenshots',
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory('${selected.path}${Platform.pathSeparator}temp').existsSync(),
      isTrue,
    );
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
    expect(find.text('工作区'), findsOneWidget);
    expect(find.byKey(const Key('agent-add-workspace')), findsOneWidget);
    expect(find.byKey(const Key('agent-manage-workspaces')), findsOneWidget);
    expect(find.byKey(const Key('agent-sidebar-settings')), findsOneWidget);
    expect(find.text('Harness 设置'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('agent-composer-shell'))).width,
      greaterThan(820),
    );
  });

  testWidgets('标准 Mac 窗口可打开和收起会话侧边栏', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agent-session-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('agent-new-session-sidebar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-close-session-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-session-sidebar')), findsNothing);
    expect(find.byKey(const Key('agent-open-session-sidebar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-open-session-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-session-sidebar')), findsOneWidget);
  });

  testWidgets('点击当前项目可折叠并重新展开对应会话', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(tester.view.reset);
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_workspace_collapse_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final DateTime now = DateTime.now();
    final HarnessConversationProject project = HarnessConversationProject(
      workspace: workspace.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'collapse-one',
          title: '第一条会话',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
        HarnessConversationSession(
          id: 'collapse-two',
          title: '第二条会话',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeSessionId: 'collapse-one',
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            loadWorkspaceCatalog: () async => <String>[workspace.path],
            loadConversation: (_) async => project,
            saveConversation: (_) async {},
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder header = find.byKey(
      ValueKey<String>('agent-workspace-header-${workspace.path}'),
    );
    expect(header, findsOneWidget);
    expect(find.byKey(const Key('agent-session-collapse-one')), findsOneWidget);
    expect(find.byKey(const Key('agent-session-collapse-two')), findsOneWidget);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-session-collapse-one')), findsNothing);
    expect(find.byKey(const Key('agent-session-collapse-two')), findsNothing);
    expect(find.byTooltip('展开项目会话'), findsOneWidget);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-session-collapse-one')), findsOneWidget);
    expect(find.byKey(const Key('agent-session-collapse-two')), findsOneWidget);
    expect(find.byTooltip('折叠项目会话'), findsOneWidget);
  });

  testWidgets('项目菜单支持改名且移除取消不丢项目，会话仅选中项显示操作', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(tester.view.reset);
    final Directory root = Directory.systemTemp.createTempSync(
      'vibekits_workspace_menu_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory source = Directory('${root.path}/source')..createSync();
    final Directory target = Directory('${root.path}/target')..createSync();
    final DateTime now = DateTime.now();
    final HarnessConversationProject sourceProject = HarnessConversationProject(
      workspace: source.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'selected-session',
          title: '已选会话',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
        HarnessConversationSession(
          id: 'other-session',
          title: '未选会话',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeSessionId: 'selected-session',
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: source.path,
            loadWorkspaceCatalog: () async => <String>[
              source.path,
              target.path,
            ],
            loadConversation: (String workspace) async =>
                workspace == source.path ? sourceProject : null,
            saveConversation: (_) async {},
            saveWorkspaceCatalog: (_) async {},
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('agent-session-menu-selected-session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-session-menu-other-session')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(ValueKey<String>('agent-workspace-menu-${source.path}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑名称'), findsOneWidget);
    expect(find.text('在此新建会话'), findsOneWidget);
    expect(find.text('移除项目'), findsOneWidget);

    await tester.tap(find.text('编辑名称'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agent-workspace-name-field')),
      '重新命名项目',
    );
    await tester.tap(find.byKey(const Key('agent-save-workspace-name')));
    await tester.pumpAndSettle();
    expect(find.text('重新命名项目'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('agent-workspace-menu-${source.path}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除项目'));
    await tester.pumpAndSettle();
    expect(find.text('移除项目？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('agent-workspace-${source.path}')),
      findsOneWidget,
    );
    expect(find.text('重新命名项目'), findsOneWidget);
  });

  testWidgets('Harness 运行时可切换项目且后台结果回到原会话', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.reset);
    final Directory root = Directory.systemTemp.createTempSync(
      'vibekits_background_project_switch_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory source = Directory('${root.path}/source')..createSync();
    final Directory target = Directory('${root.path}/target')..createSync();
    final DateTime now = DateTime.now();
    final Map<String, HarnessConversationProject> projects =
        <String, HarnessConversationProject>{
          source.path: HarnessConversationProject(
            workspace: source.path,
            sessions: <HarnessConversationSession>[
              HarnessConversationSession(
                id: 'source-session',
                title: '后台任务',
                messages: const <HarnessConversationMessage>[],
                createdAt: now,
                updatedAt: now,
              ),
            ],
            activeSessionId: 'source-session',
            updatedAt: now,
          ),
          target.path: HarnessConversationProject(
            workspace: target.path,
            sessions: <HarnessConversationSession>[
              HarnessConversationSession(
                id: 'target-session',
                title: '目标会话',
                messages: const <HarnessConversationMessage>[
                  HarnessConversationMessage(text: '目标项目内容', user: true),
                ],
                createdAt: now,
                updatedAt: now,
              ),
            ],
            activeSessionId: 'target-session',
            updatedAt: now,
          ),
        };
    final List<_FakeAgentHandle> handles = <_FakeAgentHandle>[
      _FakeAgentHandle(),
      _FakeAgentHandle(),
    ];
    addTearDown(() async {
      for (final _FakeAgentHandle handle in handles) {
        await handle.dispose();
      }
    });
    int launchedCount = 0;
    final List<String> workspaceChanges = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: source.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            loadWorkspaceCatalog: () async => <String>[
              source.path,
              target.path,
            ],
            loadConversation: (String workspace) async => projects[workspace],
            saveConversation: (HarnessConversationProject project) async {
              projects[project.workspace] = project;
            },
            onWorkspaceChanged: (String workspace) async {
              workspaceChanges.add(workspace);
            },
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
            runAgent: (_) async => handles[launchedCount++],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('agent-workspace-menu-${source.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('agent-workspace-menu-${target.path}')),
      findsNothing,
    );

    await tester.enterText(find.byKey(const Key('agent-composer')), '后台运行');
    await tester.ensureVisible(find.byKey(const Key('agent-send')));
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(HarnessWorkStatusHub.latest.phase, HarnessWorkPhase.reasoning);
    expect(
      find.byKey(const Key('agent-session-menu-source-session')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey<String>('agent-workspace-header-${target.path}')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(workspaceChanges.last, target.path);
    expect(find.text('目标项目内容'), findsOneWidget);
    expect(find.byKey(const Key('agent-stop')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('agent-composer'))).enabled,
      isNot(false),
    );
    expect(HarnessWorkStatusHub.latest.phase, HarnessWorkPhase.reasoning);
    expect(
      find.byKey(
        ValueKey<String>('agent-session-running-${source.path}-source-session'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('agent-workspace-running-${source.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('agent-workspace-menu-${source.path}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('agent-workspace-menu-${target.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('agent-session-menu-${source.path}-source-session'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('agent-session-menu-target-session')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('agent-composer')), '第二会话并行任务');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(launchedCount, 2);
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);
    handles[1].add('第二会话已完成');
    await tester.pump();
    expect(find.text('第二会话已完成'), findsOneWidget);
    await handles[1].complete(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('agent-stop')), findsNothing);

    handles[0].add('后台任务已完成');
    await tester.pump();
    expect(find.text('后台任务已完成'), findsNothing);
    await handles[0].complete(0);
    await tester.pumpAndSettle();
    expect(HarnessWorkStatusHub.latest.phase, HarnessWorkPhase.ready);
    expect(
      find.byKey(
        ValueKey<String>('agent-session-running-${source.path}-source-session'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(ValueKey<String>('agent-workspace-header-${source.path}')),
    );
    await tester.pumpAndSettle();
    expect(workspaceChanges.last, source.path);
    expect(find.text('后台任务已完成'), findsOneWidget);
  });

  testWidgets('可添加工作区并拖动会话后确认权限根目录重绑定', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(tester.view.reset);
    final Directory root = Directory.systemTemp.createTempSync(
      'vibekits_workspace_move_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory source = Directory('${root.path}/source')..createSync();
    final Directory target = Directory('${root.path}/target')..createSync();
    final DateTime now = DateTime.now();
    final HarnessConversationSession movable = HarnessConversationSession(
      id: 'move-me',
      title: '移动到目标项目',
      messages: const <HarnessConversationMessage>[
        HarnessConversationMessage(text: '继续实现功能', user: true),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final Map<String, HarnessConversationProject> projects =
        <String, HarnessConversationProject>{
          source.path: HarnessConversationProject(
            workspace: source.path,
            sessions: <HarnessConversationSession>[movable],
            activeSessionId: movable.id,
            updatedAt: now,
          ),
        };
    List<String> savedCatalog = <String>[];
    String activeWorkspace = source.path;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: source.path,
            onWorkspaceChanged: (String value) async {
              activeWorkspace = value;
            },
            pickDirectory: () async => target.path,
            loadWorkspaceCatalog: () async => <String>[source.path],
            saveWorkspaceCatalog: (List<String> value) async {
              savedCatalog = List<String>.of(value);
            },
            loadConversation: (String workspace) async => projects[workspace],
            saveConversation: (HarnessConversationProject project) async {
              projects[project.workspace] = project;
            },
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent-add-workspace')));
    await tester.pumpAndSettle();
    expect(savedCatalog, containsAll(<String>[source.path, target.path]));
    expect(activeWorkspace, target.path);
    expect(find.text('source'), findsWidgets);
    expect(find.text('target'), findsWidgets);

    await tester.tap(
      find.byKey(ValueKey<String>('agent-workspace-menu-${target.path}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑名称'), findsOneWidget);
    expect(
      find.text('在 Finder 中显示'),
      Platform.isMacOS ? findsOneWidget : findsNothing,
    );
    expect(find.text('在此新建会话'), findsOneWidget);
    expect(find.text('移除项目'), findsOneWidget);
    await tester.tap(find.text('编辑名称'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agent-workspace-name-field')),
      '目标项目别名',
    );
    await tester.tap(find.byKey(const Key('agent-save-workspace-name')));
    await tester.pumpAndSettle();
    expect(find.text('目标项目别名'), findsWidgets);

    final Finder targetWorkspace = find.byKey(
      ValueKey<String>('agent-workspace-${target.path}'),
    );
    final TestGesture secondaryMouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    final Offset targetCenter = tester.getCenter(targetWorkspace);
    await secondaryMouse.addPointer(location: targetCenter);
    await secondaryMouse.down(targetCenter);
    await secondaryMouse.up();
    await secondaryMouse.removePointer();
    await tester.pumpAndSettle();
    expect(find.text('编辑名称'), findsOneWidget);
    expect(find.text('移除项目'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    Finder session = find.byKey(
      ValueKey<String>('agent-session-${source.path}-move-me'),
    );
    expect(session, findsOneWidget);
    expect(targetWorkspace, findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('agent-session-menu-${source.path}-move-me')),
      findsNothing,
    );

    await tester.tap(session);
    await tester.pumpAndSettle();
    expect(activeWorkspace, source.path);
    session = find.byKey(const Key('agent-session-move-me'));
    expect(session, findsOneWidget);

    final Finder sessionMenu = find.byKey(
      const Key('agent-session-menu-move-me'),
    );
    await tester.tap(sessionMenu);
    await tester.pumpAndSettle();
    expect(find.text('移动到项目'), findsOneWidget);
    expect(find.text('移动到…'), findsNothing);
    expect(
      find.byKey(const Key('agent-session-source-workspace-path')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-session-source-workspace-path')),
      findsOneWidget,
    );
    expect(find.text(target.path), findsAtLeast(1));
    expect(
      find.byKey(ValueKey<String>('agent-session-move-target-${target.path}')),
      findsOneWidget,
    );
    await tester.tap(sessionMenu);
    await tester.pumpAndSettle();

    final Offset start = tester.getCenter(session);
    final Offset end = tester.getCenter(targetWorkspace);
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: start);
    await mouse.down(start);
    await mouse.moveTo(end);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('移动会话并重新绑定工作区权限？'), findsOneWidget);
    expect(find.textContaining('workspace-write'), findsOneWidget);
    expect(find.textContaining(source.path), findsWidgets);
    expect(find.textContaining(target.path), findsWidgets);
    await tester.tap(find.byKey(const Key('agent-confirm-move-session')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(
      projects[source.path]!.sessions.any(
        (HarnessConversationSession item) => item.id == movable.id,
      ),
      isFalse,
    );
    expect(
      projects[target.path]!.sessions.any(
        (HarnessConversationSession item) => item.id == movable.id,
      ),
      isTrue,
    );
    expect(activeWorkspace, target.path);
  });

  testWidgets('会话菜单永久删除聊天推理时间线和未发送草稿', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_delete_session_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final DateTime now = DateTime.now();
    final HarnessConversationSession doomed = HarnessConversationSession(
      id: 'delete-me',
      title: '需要永久删除的会话',
      messages: <HarnessConversationMessage>[
        const HarnessConversationMessage(text: '秘密聊天内容', user: true),
        const HarnessConversationMessage(
          text: 'Harness 回复',
          user: false,
          executionTrace: '理解任务\n规划操作\n调用只读工具\n继续分析',
        ),
      ],
      createdAt: now.subtract(const Duration(minutes: 2)),
      updatedAt: now,
    );
    final HarnessConversationSession kept = HarnessConversationSession(
      id: 'keep-me',
      title: '保留的会话',
      messages: const <HarnessConversationMessage>[
        HarnessConversationMessage(text: '保留内容', user: true),
      ],
      createdAt: now.subtract(const Duration(minutes: 4)),
      updatedAt: now.subtract(const Duration(minutes: 1)),
    );
    HarnessConversationProject project = HarnessConversationProject(
      workspace: workspace.path,
      sessions: <HarnessConversationSession>[doomed, kept],
      activeSessionId: doomed.id,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            loadWorkspaceCatalog: () async => <String>[workspace.path],
            loadConversation: (_) async => project,
            saveConversation: (HarnessConversationProject value) async {
              project = value;
            },
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v22.19.0',
              npxVersion: '@deepseek-ai/dsh@0.1.1-rc.2',
              message: 'Harness 已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('秘密聊天内容'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('agent-composer')),
      '也必须删除的未发送草稿',
    );
    await tester.tap(find.byKey(const Key('agent-session-menu-delete-me')));
    await tester.pumpAndSettle();
    expect(find.text('删除会话'), findsOneWidget);
    expect(find.text('永久删除全部聊天与推理记录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-session-delete-delete-me')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除会话？'), findsOneWidget);
    expect(find.textContaining('全部聊天消息、推理过程'), findsOneWidget);
    expect(find.textContaining('此操作不可恢复'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-confirm-delete-session')));
    await tester.pumpAndSettle();

    expect(project.sessions.map((item) => item.id), <String>['keep-me']);
    expect(project.activeSessionId, 'keep-me');
    expect(find.text('需要永久删除的会话'), findsNothing);
    expect(find.text('秘密聊天内容'), findsNothing);
    expect(find.text('保留内容'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('agent-composer')))
          .controller
          ?.text,
      isEmpty,
    );
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

  testWidgets('帮我批准默认自动执行且三档权限可持久选择', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.reset);
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_session_approval_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final _FakeAgentHandle handle = _FakeAgentHandle();
    addTearDown(handle.dispose);
    HarnessAgentRequest? launched;
    HarnessAgentPermissionMode? savedMode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            loadPermissionMode: () async => HarnessAgentPermissionMode.assisted,
            savePermissionMode: (HarnessAgentPermissionMode mode) async {
              savedMode = mode;
            },
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
    expect(await launched!.approveTool!(getprop), isTrue);
    await tester.pump();
    expect(find.text('允许 执行 ADB 命令？'), findsNothing);
    expect(find.text('帮我批准'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-permission-menu')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请求批准'), findsOneWidget);
    expect(find.text('完全访问权限'), findsOneWidget);
    await tester.ensureVisible(find.text('请求批准'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('请求批准'));
    await tester.pump();
    expect(savedMode, HarnessAgentPermissionMode.requestApproval);

    final Future<bool> requested = launched!.approveTool!(getprop);
    await tester.pump();
    expect(find.text('允许 执行 ADB 命令？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-approve-once')));
    await tester.pump();
    expect(await requested, isTrue);

    await handle.complete(0);
    await tester.pumpAndSettle();
  });

  testWidgets('完全访问权限重建后仍生效且不再弹出批准菜单', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.reset);
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_full_access_restart_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    HarnessAgentPermissionMode savedMode = HarnessAgentPermissionMode.assisted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            loadPermissionMode: () async => savedMode,
            savePermissionMode: (HarnessAgentPermissionMode mode) async {
              savedMode = mode;
            },
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-permission-menu')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('完全访问权限'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('完全访问权限'));
    await tester.pumpAndSettle();
    expect(savedMode, HarnessAgentPermissionMode.fullAccess);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final _FakeAgentHandle restartedHandle = _FakeAgentHandle();
    addTearDown(restartedHandle.dispose);
    HarnessAgentRequest? restartedRequest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            loadPermissionMode: () async => savedMode,
            savePermissionMode: (HarnessAgentPermissionMode mode) async {
              savedMode = mode;
            },
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
            runAgent: (HarnessAgentRequest request) async {
              restartedRequest = request;
              return restartedHandle;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('完全访问权限'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('agent-composer')), '执行工具');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();

    const HarnessToolDefinition destructiveTool = HarnessToolDefinition(
      id: 'test.destructive',
      name: '测试高风险工具',
      description: '验证完全访问权限',
      risk: HarnessToolRisk.destructive,
      inputSchema: <String, Object?>{},
      available: true,
    );
    const HarnessToolApprovalRequest destructiveRequest =
        HarnessToolApprovalRequest(
          tool: destructiveTool,
          target: 'test-target',
          arguments: <String, Object?>{},
        );
    expect(await restartedRequest!.approveTool!(destructiveRequest), isTrue);
    await tester.pump();
    expect(find.text('允许 测试高风险工具？'), findsNothing);
    await restartedHandle.complete(0);
    await tester.pumpAndSettle();
  });

  testWidgets('项目保存多个会话并在重建后恢复活动会话', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    const String workspace = r'D:\projects\alpha';
    final DateTime now = DateTime(2026, 8, 18, 12);
    HarnessConversationProject savedProject = HarnessConversationProject(
      workspace: workspace,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'session-one',
          title: '检查 ADB 设备',
          messages: const <HarnessConversationMessage>[
            HarnessConversationMessage(text: '检查 ADB 设备', user: true),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        HarnessConversationSession(
          id: 'session-two',
          title: '分析项目代码',
          messages: const <HarnessConversationMessage>[
            HarnessConversationMessage(text: '分析项目代码', user: true),
          ],
          createdAt: now,
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      activeSessionId: 'session-one',
      updatedAt: now,
    );

    DeepSeekAgentWorkspace workspaceWidget() => DeepSeekAgentWorkspace(
      initialWorkspace: workspace,
      credentialReader: (_) async => null,
      credentialWriter: (_, _) async {},
      loadConversation: (_) async => savedProject,
      saveConversation: (HarnessConversationProject project) async {
        savedProject = project;
      },
      checkEnvironment: () async => const HarnessEnvironmentReport(
        ready: true,
        nodeVersion: 'v24.18.0',
        npxVersion: '11.16.0',
        message: '已就绪',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: workspaceWidget())),
    );
    await tester.pumpAndSettle();
    expect(find.text('检查 ADB 设备'), findsWidgets);
    expect(find.text('分析项目代码'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-session-session-two')));
    await tester.pumpAndSettle();
    expect(find.text('分析项目代码'), findsWidgets);
    expect(savedProject.activeSessionId, 'session-two');

    await tester.tap(find.byKey(const Key('agent-new-session-sidebar')));
    await tester.pumpAndSettle();
    expect(savedProject.sessions, hasLength(3));
    expect(find.text('检查 ADB 设备'), findsOneWidget);
    expect(find.text('分析项目代码'), findsOneWidget);
    expect(find.text('新会话'), findsOneWidget);

    final String? activeAfterNew = savedProject.activeSessionId;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: workspaceWidget())),
    );
    await tester.pumpAndSettle();
    expect(savedProject.activeSessionId, activeAfterNew);
    expect(find.text('检查 ADB 设备'), findsOneWidget);
    expect(find.text('分析项目代码'), findsOneWidget);
    expect(find.text('新会话'), findsOneWidget);
  });

  testWidgets('外部工具结果可切入智能体输入框继续分析', (WidgetTester tester) async {
    Widget workspace(String prompt, int serial) => MaterialApp(
      home: Scaffold(
        body: DeepSeekAgentWorkspace(
          key: const ValueKey<String>('external-prompt-workspace'),
          externalPrompt: prompt,
          externalPromptSerial: serial,
          credentialReader: (_) async => null,
          credentialWriter: (_, _) async {},
          loadConversation: (_) async => null,
          saveConversation: (_) async {},
          checkEnvironment: () async => const HarnessEnvironmentReport(
            ready: true,
            nodeVersion: 'v24.18.0',
            npxVersion: '11.16.0',
            message: '已就绪',
          ),
        ),
      ),
    );

    await tester.pumpWidget(workspace('分析 C 盘占用', 1));
    await tester.pumpAndSettle();
    TextField composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.controller?.text, '分析 C 盘占用');

    await tester.pumpWidget(workspace('解释 ESTLOG 是否合理', 2));
    await tester.pumpAndSettle();
    composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.controller?.text, '解释 ESTLOG 是否合理');
  });

  testWidgets('每个 Harness 会话保留自己的未发送输入草稿', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_session_draft_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final DateTime now = DateTime.now();
    final HarnessConversationProject project = HarnessConversationProject(
      workspace: workspace.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'draft-one',
          title: '会话一',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
        HarnessConversationSession(
          id: 'draft-two',
          title: '会话二',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      activeSessionId: 'draft-one',
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            loadConversation: (_) async => project,
            saveConversation: (_) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('agent-composer')), '111');
    await tester.tap(find.byKey(const Key('agent-session-draft-two')));
    await tester.pumpAndSettle();
    TextField composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.controller?.text, isEmpty);

    await tester.enterText(find.byKey(const Key('agent-composer')), '222');
    await tester.tap(find.byKey(const Key('agent-session-draft-one')));
    await tester.pumpAndSettle();
    composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.controller?.text, '111');

    await tester.tap(find.byKey(const Key('agent-session-draft-two')));
    await tester.pumpAndSettle();
    composer = tester.widget<TextField>(
      find.byKey(const Key('agent-composer')),
    );
    expect(composer.controller?.text, '222');
  });

  testWidgets('同一项目的两个 Harness 会话可独立并行运行', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_session_parallel_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final DateTime now = DateTime.now();
    final HarnessConversationProject project = HarnessConversationProject(
      workspace: workspace.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'parallel-one',
          title: '任务一',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now,
        ),
        HarnessConversationSession(
          id: 'parallel-two',
          title: '任务二',
          messages: const <HarnessConversationMessage>[],
          createdAt: now,
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      activeSessionId: 'parallel-one',
      updatedAt: now,
    );
    final List<_FakeAgentHandle> handles = <_FakeAgentHandle>[
      _FakeAgentHandle(),
      _FakeAgentHandle(),
    ];
    addTearDown(() async {
      for (final _FakeAgentHandle handle in handles) {
        await handle.dispose();
      }
    });
    final List<String> prompts = <String>[];
    final List<bool> runningChanges = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: workspace.path,
            credentialReader: (_) async => 'test-key',
            credentialWriter: (_, _) async {},
            loadConversation: (_) async => project,
            saveConversation: (_) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '已就绪',
            ),
            runAgent: (HarnessAgentRequest request) async {
              prompts.add(request.prompt);
              return handles[prompts.length - 1];
            },
            onRunningChanged: runningChanges.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('agent-composer')), '111');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(prompts, <String>['111']);
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-session-parallel-two')));
    await tester.pump();
    expect(find.byKey(const Key('agent-stop')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('agent-composer'))).enabled,
      isNot(false),
    );
    await tester.enterText(find.byKey(const Key('agent-composer')), '222');
    await tester.tap(find.byKey(const Key('agent-send')));
    await tester.pump();
    expect(prompts, <String>['111', '222']);
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);

    handles[1].add('任务二结果');
    await tester.pump();
    await handles[1].complete(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('任务二结果'), findsOneWidget);
    expect(find.byKey(const Key('agent-stop')), findsNothing);
    expect(runningChanges, <bool>[true]);

    await tester.tap(find.byKey(const Key('agent-session-parallel-one')));
    await tester.pump();
    expect(find.byKey(const Key('agent-stop')), findsOneWidget);
    handles[0].add('任务一结果');
    await tester.pump();
    expect(find.text('任务一结果'), findsOneWidget);
    await handles[0].complete(0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('agent-stop')), findsNothing);
    expect(runningChanges, <bool>[true, false]);
  });

  testWidgets('向上滚动显示圆形向下箭头并可回到最新消息', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final DateTime now = DateTime.now();
    final List<HarnessConversationMessage> messages = List.generate(
      30,
      (int index) => HarnessConversationMessage(
        text: '第 $index 条历史消息，用于验证离开底部后出现回到最新消息按钮。' * 3,
        user: index.isEven,
      ),
    );
    final HarnessConversationProject project = HarnessConversationProject(
      workspace: Directory.systemTemp.path,
      sessions: <HarnessConversationSession>[
        HarnessConversationSession(
          id: 'scroll-session',
          title: '滚动验收',
          messages: messages,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeSessionId: 'scroll-session',
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepSeekAgentWorkspace(
            initialWorkspace: Directory.systemTemp.path,
            credentialReader: (_) async => null,
            credentialWriter: (_, _) async {},
            loadConversation: (_) async => project,
            saveConversation: (_) async {},
            checkEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.20.0',
              npxVersion: '11.6.0',
              message: '已就绪',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder button = find.byKey(const Key('agent-scroll-to-latest'));
    AnimatedOpacity opacity() => tester.widget<AnimatedOpacity>(
      find.ancestor(of: button, matching: find.byType(AnimatedOpacity)).first,
    );
    expect(button, findsOneWidget);
    expect(opacity().opacity, 0);

    await tester.drag(
      find.byKey(const Key('agent-conversation')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();
    expect(opacity().opacity, 1);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opacity().opacity, 0);
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
