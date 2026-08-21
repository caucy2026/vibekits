import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_test_node_service.dart';
import 'package:vibekits/features/dev_tools/presentation/windows_test_node_workspace.dart';

void main() {
  testWidgets('Windows 节点先体检再生成可审计计划且不伪装执行', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final DateTime now = DateTime(2026, 8, 21);
    final WindowsNodeInspection inspection = WindowsNodeInspection(
      id: 'inspection-1',
      inspectedAt: now,
      rootPath: r'D:\KEMI-Test',
      raw: <String, Object?>{},
      checks: <WindowsNodeCheck>[
        WindowsNodeCheck(
          id: 'openssh',
          label: 'OpenSSH Server',
          status: WindowsNodeCheckStatus.warning,
          detail: '服务存在但尚未监听',
          requiresElevation: true,
        ),
      ],
      digest: 'inspection-digest',
      overallStatus: WindowsNodeCheckStatus.warning,
      requiresElevation: <String>['openssh'],
    );
    final WindowsNodeChangePlan plan = WindowsNodeChangePlan(
      id: 'plan-1',
      inspectionId: inspection.id,
      inspectionDigest: inspection.digest,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      actions: const <WindowsNodePlanAction>[
        WindowsNodePlanAction(
          id: 'windows.sshd.start_and_enable',
          currentValue: 'Stopped',
          targetValue: 'Running / Automatic',
          reason: '允许局域网 SSH 连接',
          risk: 'medium',
          requiresElevation: true,
          requiresNetwork: false,
          requiresRestart: false,
          estimatedSeconds: 5,
          cancelBehavior: '等待当前动作结束',
          rollback: '恢复旧服务状态',
          dependencies: <String>[],
          failureBoundary: '仅 sshd 服务',
        ),
      ],
      blockers: const <String>[],
      digest: 'plan-digest',
      rollbackId: 'rollback-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowsTestNodeWorkspace(
            inspect: () async => inspection,
            createPlan: (_) => plan,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('windows-node-inspect')));
    await tester.pumpAndSettle();
    expect(find.text('OpenSSH Server'), findsOneWidget);
    expect(find.textContaining('尚未监听'), findsOneWidget);

    await tester.tap(find.byKey(const Key('windows-node-plan')));
    await tester.pump();
    expect(find.text('windows.sshd.start_and_enable'), findsOneWidget);
    expect(find.textContaining('待签名 helper'), findsOneWidget);
  });
}
