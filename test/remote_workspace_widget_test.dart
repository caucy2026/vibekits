import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';
import 'package:vibekits/features/dev_tools/presentation/dev_tools_tab.dart';

void main() {
  testWidgets('SSH 工作区用一个主操作连接并发送输入', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeRemoteSession fake = _FakeRemoteSession();
    RemoteLaunchRequest? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            remoteStartSession: (RemoteLaunchRequest request) async {
              captured = request;
              fake.addOutput('welcome from server');
              return fake;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('remote-host')),
      'server.example.com',
    );
    await tester.enterText(find.byKey(const Key('remote-user')), 'developer');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();

    expect(captured?.mode, RemoteSessionMode.ssh);
    expect(captured?.profile.host, 'server.example.com');
    expect(find.textContaining('welcome from server'), findsOneWidget);
    expect(find.text('断开'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('remote-command')), 'uname -a');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(fake.sentLines, <String>['uname -a']);

    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();
    expect(fake.running, isFalse);
  });

  testWidgets('非法主机在启动进程前给出明确错误', (WidgetTester tester) async {
    bool started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsTab(
            remoteStartSession: (RemoteLaunchRequest request) async {
              started = true;
              return _FakeRemoteSession();
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('SSH / SFTP'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('remote-host')), '-oBad');
    await tester.enterText(find.byKey(const Key('remote-user')), 'dev');
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(started, isFalse);
    expect(find.byKey(const Key('remote-error')), findsOneWidget);
  });
}

class _FakeRemoteSession implements RemoteSessionHandle {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  final List<String> sentLines = <String>[];

  @override
  bool running = true;

  void addOutput(String value) => _output.add(value);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  void sendLine(String line) => sentLines.add(line);

  @override
  Future<void> stop() async {
    if (!running) return;
    running = false;
    if (!_exit.isCompleted) _exit.complete(0);
    await _output.close();
  }
}
