import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_simulation_activity.dart';
import 'package:vibekits/features/dev_tools/presentation/remote_simulation_activity_dialog.dart';

void main() {
  setUp(RemoteSimulationActivityHub.instance.clear);

  test('remote activity records direction, result and supports clear', () {
    final handle = RemoteSimulationActivityHub.instance.begin(
      direction: RemoteSimulationActivityDirection.outgoing,
      peerId: '4456560334',
      action: '查看远程应用',
      arguments: const <String, Object?>{
        'query': 'KEMI',
        'password': 'must-not-appear',
      },
    );
    handle.succeed('远端工具调用完成');

    final entry = RemoteSimulationActivityHub.instance.entries.single;
    expect(entry.peerId, '4456560334');
    expect(entry.phase, RemoteSimulationActivityPhase.succeeded);
    expect(entry.detail, contains('KEMI'));
    expect(entry.detail, contains('远端工具调用完成'));
    expect(entry.detail, isNot(contains('must-not-appear')));

    RemoteSimulationActivityHub.instance.clear();
    expect(RemoteSimulationActivityHub.instance.entries, isEmpty);
  });

  testWidgets('status chip opens rounded activity dialog and clears records', (
    WidgetTester tester,
  ) async {
    RemoteSimulationActivityHub.instance
        .begin(
          direction: RemoteSimulationActivityDirection.incoming,
          peerId: '9464730211',
          action: '读取远程应用日志',
        )
        .succeed('操作完成');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteSimulationStatusChip(
            color: Colors.green,
            label: '远程仿真中 · 9464730211',
          ),
        ),
      ),
    );

    await tester.tap(find.text('远程仿真中 · 9464730211'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('remote-simulation-activity-dialog')),
      findsOneWidget,
    );
    expect(find.text('读取远程应用日志'), findsOneWidget);
    expect(find.textContaining('远端发起 · 9464730211'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remote-simulation-clear-activity')));
    await tester.pump();
    expect(find.text('暂无远程仿真操作记录'), findsOneWidget);
  });
}
