import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('桌面仿真机恢复属于 App 生命周期而不依赖 Harness 页面', () {
    final String app = File('lib/app/app.dart').readAsStringSync();
    final String harness = File(
      'lib/features/local_models/presentation/official_harness_workspace.dart',
    ).readAsStringSync();

    expect(
      app,
      contains('HarnessSimulatorTargetRuntime.shared.restore()'),
    );
    expect(
      app,
      contains('!Platform.isAndroid && !Platform.isIOS'),
    );
    expect(
      harness,
      isNot(contains('HarnessSimulatorTargetRuntime.shared.restore()')),
    );
  });
}
