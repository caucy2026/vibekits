import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_access_settings.dart';

void main() {
  setUp(() => HarnessRemoteAccessSettings.setEnabled(false));

  test('协同默认打开且默认密码为 12345678', () async {
    final values = <String, String>{};
    final settings = HarnessRemoteAccessSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );
    expect(await settings.loadEnabled(), isTrue);
    expect(HarnessRemoteAccessSettings.enabled, isTrue);
    expect(
      await settings.loadPassword(),
      HarnessRemoteAccessSettings.defaultPassword,
    );
  });

  test('用户明确关闭协同后重启保持关闭', () async {
    final values = <String, String>{};
    final settings = HarnessRemoteAccessSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );
    await settings.saveEnabled(false);
    HarnessRemoteAccessSettings.setEnabled(true);
    expect(await settings.loadEnabled(), isFalse);
    expect(HarnessRemoteAccessSettings.enabled, isFalse);
  });

  test('用户打开远程协助后重启仍自动恢复', () async {
    final values = <String, String>{};
    HarnessRemoteAccessSettings settings() => HarnessRemoteAccessSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );
    await settings().saveEnabled(true);
    HarnessRemoteAccessSettings.setEnabled(false);
    expect(await settings().loadEnabled(), isTrue);
    expect(HarnessRemoteAccessSettings.enabled, isTrue);
  });

  test('用户可修改密码但短密码不落盘', () async {
    final values = <String, String>{};
    final settings = HarnessRemoteAccessSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );
    await settings.savePassword('new-password-87654321');
    expect(await settings.loadPassword(), 'new-password-87654321');
    await expectLater(settings.savePassword('short'), throwsFormatException);
    expect(await settings.loadPassword(), 'new-password-87654321');
  });
}
