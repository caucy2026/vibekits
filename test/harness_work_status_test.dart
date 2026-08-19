import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_work_status.dart';

void main() {
  test('远程工作状态不暴露凭据并且限制长度', () async {
    final Future<HarnessWorkSnapshot> changed =
        HarnessWorkStatusHub.changes.first;
    HarnessWorkStatusHub.publish(
      phase: HarnessWorkPhase.runningTool,
      message: '正在执行 ADB',
      toolId: 'vibekits.adb.command',
      toolName: 'ADB 命令',
      target: '192.168.3.63 token=secret-value authorization: bearer-value',
    );
    final HarnessWorkSnapshot snapshot = await changed;
    expect(snapshot.busy, isTrue);
    expect(snapshot.target, isNot(contains('secret-value')));
    expect(snapshot.target, isNot(contains('bearer-value')));
    expect(snapshot.toJson()['toolId'], 'vibekits.adb.command');
  });
}
