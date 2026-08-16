import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  test('Harness 启动参数固定使用官方包和本机端口', () async {
    final Directory workspace = await Directory.systemTemp.createTemp(
      'vibekits_harness_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final HarnessLaunchSpec spec = HarnessLaunchSpec(
      workspace: workspace.path,
      port: 3080,
    );

    spec.validate();

    expect(spec.arguments, <String>[
      '--yes',
      '@deepseek-ai/dsh@0.1.0-rc.5',
      'web',
      '--port',
      '3080',
    ]);
    expect(spec.url, Uri.parse('http://127.0.0.1:3080'));
  });

  testWidgets('选择工作区后一键启动并在就绪时打开控制台', (WidgetTester tester) async {
    final Directory workspace = Directory.systemTemp.createTempSync(
      'vibekits_harness_ui_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final _FakeHarnessSession session = _FakeHarnessSession();
    HarnessLaunchSpec? launched;
    Uri? opened;
    String? savedWorkspace;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            harnessCheckEnvironment: () async => const HarnessEnvironmentReport(
              ready: true,
              nodeVersion: 'v24.18.0',
              npxVersion: '11.16.0',
              message: '运行环境已就绪',
            ),
            harnessPickDirectory: () async => workspace.path,
            harnessStartSession: (HarnessLaunchSpec spec) async {
              launched = spec;
              return session;
            },
            harnessOpenBrowser: (Uri url) async => opened = url,
            onHarnessWorkspaceChanged: (String path) async {
              savedWorkspace = path;
            },
          ),
        ),
      ),
    );
    final Finder search = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == '搜索工具',
    );
    await tester.enterText(search, 'DeepSeek');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'DeepSeek Harness'));
    await tester.pumpAndSettle();

    expect(find.text('开发者预览 · MIT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('harness-pick-workspace')));
    await tester.pumpAndSettle();
    expect(savedWorkspace, workspace.path);

    await tester.tap(find.byKey(const Key('harness-primary-action')));
    await tester.pump();
    expect(launched?.workspace, workspace.path);
    session.add('Web UI: http://127.0.0.1:3080\n');
    await tester.pump();
    expect(opened, Uri.parse('http://127.0.0.1:3080'));
    expect(find.text('控制台已就绪'), findsOneWidget);

    await tester.tap(find.byKey(const Key('harness-stop')));
    await tester.pumpAndSettle();
    expect(session.running, isFalse);
  });
}

class _FakeHarnessSession implements HarnessSessionHandle {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  bool _running = true;

  void add(String value) => _output.add(value);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  bool get running => _running;

  @override
  Uri get url => Uri.parse('http://127.0.0.1:3080');

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    if (!_exit.isCompleted) _exit.complete(0);
    await _output.close();
  }
}
