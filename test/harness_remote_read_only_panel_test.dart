import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_connection.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_view_model.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_workspace_client.dart';
import 'package:vibekits/features/dev_tools/presentation/harness_remote_read_only_panel.dart';

class _Channel implements HarnessRemoteChannel {
  final incoming = StreamController<String>();
  final operations = <String>[];
  bool closed = false;
  @override
  String get authenticatedPeerId => 'VH-HOST';
  @override
  Stream<String> get frames => incoming.stream;

  @override
  Future<void> send(String frame) async {
    final request = jsonDecode(frame) as Map;
    final payload = request['payload'] as Map;
    final Map<String, Object?> response;
    if (payload['operation'] is String) {
      operations.add(payload['operation'] as String);
      response = {
        'ok': true,
        'commandId': payload['commandId'],
        'officialResponse': {
          'result': {'ok': true},
        },
      };
    } else {
      response = switch (payload['kind']) {
        'hello' => {
          'ok': true,
          'protocol': 'vibekits.harness.remote',
          'version': 1,
          'connectionId': 'c1',
          'authenticatedControllerId': 'VH-CONTROLLER',
          'capabilities': ['read-state', 'heartbeat'],
        },
        'heartbeat' => {'ok': true, 'connectionId': 'c1'},
        _ => {
          'ok': true,
          'live': true,
          'epoch': 'e1',
          'sequence': 0,
          'workspaces': [
            {
              'workspaceId': 'workspace-a',
              'title': '远端工程 A',
              'phase': 'reasoning',
              'sessionIds': ['s1', 's2'],
            },
          ],
        },
      };
    }
    incoming.add(
      jsonEncode({
        'protocol': 'vibekits.harness.remote',
        'version': 1,
        'type': 'response',
        'requestId': request['requestId'],
        'payload': response,
      }),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    unawaited(incoming.close());
  }
}

void main() {
  testWidgets(
    'renders synchronized projects and keeps stale rows on disconnect',
    (WidgetTester tester) async {
      final channel = _Channel();
      final connection = HarnessRemoteConnection(channel);
      final model = HarnessRemoteViewModel(
        HarnessRemoteWorkspaceClient(connection),
        applyOfficialEvents: (_) async {},
        restoreOfficialSnapshot: (_) async {},
      )..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HarnessRemoteReadOnlyPanel(
              peerRoutingId: '1554650784',
              model: model,
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('远程 Harness · 1554650784'), findsOneWidget);
      expect(find.text('远端工程 A'), findsOneWidget);
      expect(find.text('REASONING'), findsOneWidget);
      expect(find.text('workspace-a · 2 个会话'), findsOneWidget);

      channel.incoming.addError(StateError('REMOTE_DISCONNECTED'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('远端工程 A'), findsOneWidget);
      expect(find.textContaining('最后一次同步记录'), findsOneWidget);
      model.dispose();
      unawaited(connection.close());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('remote command UI sends explicit prompt and independent stop', (
    WidgetTester tester,
  ) async {
    final channel = _Channel();
    final connection = HarnessRemoteConnection(channel);
    final client = HarnessRemoteWorkspaceClient(connection);
    final model = HarnessRemoteViewModel(
      client,
      applyOfficialEvents: (_) async {},
      restoreOfficialSnapshot: (_) async {},
    )..start();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HarnessRemoteCommandPanel(
              model: model,
              client: client,
              allowedOperations: const {'session.prompt', 'session.cancel'},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.enterText(
      find.byKey(const Key('harness-remote-command-input')),
      '继续检查构建日志',
    );
    await tester.tap(find.byKey(const Key('harness-remote-command-send')));
    await tester.pump(const Duration(milliseconds: 30));
    expect(channel.operations, contains('session.prompt'));
    expect(find.textContaining('执行端已返回'), findsOneWidget);

    await tester.tap(find.byKey(const Key('harness-remote-command-stop')));
    await tester.pump(const Duration(milliseconds: 30));
    expect(channel.operations, contains('session.cancel'));
    expect(find.textContaining('停止请求已返回'), findsOneWidget);
    model.dispose();
    unawaited(connection.close());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remote drafts remain independent for every session', (
    WidgetTester tester,
  ) async {
    final channel = _Channel();
    final connection = HarnessRemoteConnection(channel);
    final client = HarnessRemoteWorkspaceClient(connection);
    final model = HarnessRemoteViewModel(
      client,
      applyOfficialEvents: (_) async {},
      restoreOfficialSnapshot: (_) async {},
    )..start();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HarnessRemoteCommandPanel(
            model: model,
            client: client,
            allowedOperations: const {'session.prompt'},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    final input = find.byKey(const Key('harness-remote-command-input'));
    await tester.enterText(input, '111');

    await tester.tap(find.byKey(const Key('harness-remote-session-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('远端工程 A · s2').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.enterText(input, '222');

    await tester.tap(find.byKey(const Key('harness-remote-session-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('远端工程 A · s1').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '111');

    await tester.tap(find.byKey(const Key('harness-remote-session-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('远端工程 A · s2').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '222');
    model.dispose();
    unawaited(connection.close());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
