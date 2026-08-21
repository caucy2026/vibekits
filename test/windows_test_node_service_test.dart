import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_test_node_service.dart';

void main() {
  Map<String, Object?> healthyFacts() => <String, Object?>{
    'osEdition': 'Windows 11 Pro',
    'osBuild': 26100,
    'cpu': 'Test CPU',
    'ramBytes': 32 * 1024 * 1024 * 1024,
    'gpu': 'Test GPU',
    'display': '1920x1080 @ 150%',
    'dExists': true,
    'dTotalBytes': 100 * 1024 * 1024 * 1024,
    'dFreeBytes': 50 * 1024 * 1024 * 1024,
    'ipv4': '192.168.3.10',
    'candidateCidr': '192.168.3.0/24',
    'networkCategory': 'Private',
    'opensshCapability': 'Installed',
    'sshdBinary': true,
    'sshdServiceExists': true,
    'sshdVersion': '9.5',
    'sshdConfigValid': true,
    'sshdRunningAndListening': true,
    'firewallValid': true,
    'powershell7': true,
    'webview2': true,
    'vcredist': true,
    'acPowerSafe': true,
    'testRootValid': true,
    'testUserValid': true,
    'authorizedKeysValid': true,
  };

  test('D 盘不足 30 GiB 阻断且不生成可执行计划', () async {
    final Map<String, Object?> facts = healthyFacts()
      ..['dFreeBytes'] = 20 * 1024 * 1024 * 1024;
    final WindowsTestNodeService service = WindowsTestNodeService(
      probe: () async => facts,
      clock: () => DateTime(2026, 8, 21),
      random: Random(1),
    );
    final WindowsNodeInspection inspection = await service.inspect();
    expect(inspection.overallStatus, WindowsNodeCheckStatus.blocked);
    final WindowsNodeChangePlan plan = service.plan(inspection.id);
    expect(plan.blockers.join(), contains('D 盘'));
    expect(
      () => service.requireExecutablePlan(planId: plan.id, digest: plan.digest),
      throwsA(isA<FormatException>()),
    );
  });

  test('矛盾 OpenSSH 状态生成稳定动作且摘要篡改被拒绝', () async {
    final Map<String, Object?> facts = healthyFacts()
      ..['opensshCapability'] = 'NotPresent'
      ..['sshdBinary'] = true
      ..['sshdServiceExists'] = true
      ..['sshdRunningAndListening'] = false
      ..['firewallValid'] = false
      ..['networkCategory'] = 'Public';
    final WindowsTestNodeService service = WindowsTestNodeService(
      probe: () async => facts,
      clock: () => DateTime(2026, 8, 21),
      random: Random(2),
    );
    final WindowsNodeInspection inspection = await service.inspect();
    expect(
      inspection.checks
          .firstWhere((WindowsNodeCheck item) => item.id == 'openssh')
          .status,
      WindowsNodeCheckStatus.pass,
      reason: 'capability 元数据不能覆盖真实二进制与服务证据',
    );
    final WindowsNodeChangePlan first = service.plan(inspection.id);
    final WindowsNodeChangePlan second = service.plan(inspection.id);
    expect(
      first.actions.map((WindowsNodePlanAction item) => item.id),
      second.actions.map((WindowsNodePlanAction item) => item.id),
    );
    expect(
      first.actions.map((WindowsNodePlanAction item) => item.id),
      containsAll(<String>[
        'windows.sshd.start_and_enable',
        'windows.network.mark_private',
        'windows.firewall.apply_lan_rule',
      ]),
    );
    expect(
      () => service.requireExecutablePlan(
        planId: first.id,
        digest: '${first.digest}tampered',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('根目录越过 D KEMI-Test 门禁时直接拒绝', () async {
    final WindowsTestNodeService service = WindowsTestNodeService(
      probe: () async => healthyFacts(),
    );
    await expectLater(
      service.inspect(rootPath: r'C:\Temp'),
      throwsA(isA<FormatException>()),
    );
  });
}
