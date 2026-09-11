import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_system_ssh_service.dart';

void main() {
  tearDown(HarnessSystemSshService.resetForTesting);

  test('系统 SSH 开关只接受布尔状态并返回可展示端点', () async {
    final calls = <bool>[];
    HarnessSystemSshService.testSetter = (enabled) async {
      calls.add(enabled);
      return HarnessSystemSshSnapshot(
        supported: true,
        enabled: enabled,
        endpoint: enabled ? '192.168.3.10:22' : '',
        username: 'newlink',
        changed: true,
      );
    };

    final enabled = await HarnessSystemSshService.setEnabled(true);
    final disabled = await HarnessSystemSshService.setEnabled(false);

    expect(calls, <bool>[true, false]);
    expect(enabled.endpoint, '192.168.3.10:22');
    expect(enabled.username, 'newlink');
    expect(disabled.enabled, isFalse);
  });

  test('macOS 原生桥接直接管理 sshd 且不再依赖 systemsetup 假成功', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, contains('launchctl enable system/com.openssh.sshd'));
    expect(source, contains('launchctl bootstrap system'));
    expect(source, contains('launchctl disable system/com.openssh.sshd'));
    expect(source, isNot(contains('systemsetup -setremotelogin')));
  });
}
