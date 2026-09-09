import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_startup_recovery.dart';

void main() {
  test('Harness 异常退出采用有限指数退避且稳定后重置', () {
    final HarnessStartupRecovery recovery = HarnessStartupRecovery();

    expect(recovery.nextDelay(), const Duration(milliseconds: 800));
    expect(recovery.nextDelay(), const Duration(milliseconds: 1600));
    expect(recovery.nextDelay(), const Duration(milliseconds: 3200));
    expect(recovery.nextDelay(), isNull);

    recovery.markStable();
    expect(recovery.attempts, 0);
    expect(recovery.nextDelay(), const Duration(milliseconds: 800));
  });

  test('Harness 恢复次数可按部署策略限制', () {
    final HarnessStartupRecovery recovery = HarnessStartupRecovery(
      maxAttempts: 1,
      baseDelay: const Duration(milliseconds: 25),
    );

    expect(recovery.nextDelay(), const Duration(milliseconds: 25));
    expect(recovery.nextDelay(), isNull);
  });
}
