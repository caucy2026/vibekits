import 'dart:convert';
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

  test('首次公钥授权仅写入受限条目并可精确撤销', () async {
    final home = await Directory.systemTemp.createTemp('vibekits_ssh_home_');
    addTearDown(() => home.delete(recursive: true));
    final ssh = Directory('${home.path}/.ssh');
    await ssh.create();
    final authorizedKeys = File('${ssh.path}/authorized_keys');
    await authorizedKeys.writeAsString('ssh-ed25519 EXISTING user-owned\n');
    final key = base64Encode(List<int>.generate(48, (index) => index + 1));
    final publicKey = 'ssh-ed25519 $key controller';
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      if (executable.endsWith('ssh-keygen') ||
          executable.endsWith('ssh-keygen.exe')) {
        return ProcessResult(
          1,
          0,
          '256 SHA256:verifiedHost target (ED25519)',
          '',
        );
      }
      return ProcessResult(1, 0, '', '');
    }

    Future<HarnessSystemSshSnapshot> inspector() async =>
        const HarnessSystemSshSnapshot(
          supported: true,
          enabled: true,
          username: 'tester',
          endpoint: '127.0.0.1:22',
        );

    final authorized = await HarnessSystemSshService.authorizePublicKey(
      peerId: '4456560334',
      publicKey: publicKey,
      runner: runner,
      inspector: inspector,
      homeDirectory: home,
    );
    expect(authorized['authorized'], isTrue);
    expect(authorized['hostKeyFingerprint'], 'SHA256:verifiedHost');
    final text = await authorizedKeys.readAsString();
    expect(text, contains('ssh-ed25519 EXISTING user-owned'));
    expect(text, contains('from="127.0.0.1"'));
    expect(text, contains('no-port-forwarding'));
    expect(text, contains('vibekits-simulator-4456560334-'));

    final status = await HarnessSystemSshService.publicKeyStatus(
      peerId: '4456560334',
      publicKey: publicKey,
      homeDirectory: home,
    );
    expect(status['authorized'], isTrue);
    final revoked = await HarnessSystemSshService.revokePublicKeys(
      peerId: '4456560334',
      homeDirectory: home,
    );
    expect(revoked['removed'], 1);
    expect(
      await authorizedKeys.readAsString(),
      'ssh-ed25519 EXISTING user-owned\n',
    );
  });

  test('关闭远程仿真撤销全部托管密钥但保留用户密钥', () async {
    final home = await Directory.systemTemp.createTemp('vibekits_ssh_revoke_');
    addTearDown(() => home.delete(recursive: true));
    final ssh = Directory('${home.path}/.ssh');
    await ssh.create();
    final authorizedKeys = File('${ssh.path}/authorized_keys');
    await authorizedKeys.writeAsString(
      'ssh-ed25519 USERKEY owner\n'
      'ssh-ed25519 KEY1 vibekits-simulator-111111-aabb\n'
      'ssh-ed25519 KEY2 vibekits-simulator-222222-ccdd\n',
    );
    final result = await HarnessSystemSshService.revokeAllManagedPublicKeys(
      homeDirectory: home,
    );
    expect(result['removed'], 2);
    expect(await authorizedKeys.readAsString(), 'ssh-ed25519 USERKEY owner\n');
  });
}
