import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_device_service.dart';

void main() {
  String publicKey(int seed) {
    final List<int> algorithm = utf8.encode('ssh-ed25519');
    final List<int> key = List<int>.generate(32, (int index) => seed + index);
    final BytesBuilder blob = BytesBuilder();
    for (final List<int> field in <List<int>>[algorithm, key]) {
      blob.add(<int>[
        (field.length >> 24) & 0xff,
        (field.length >> 16) & 0xff,
        (field.length >> 8) & 0xff,
        field.length & 0xff,
      ]);
      blob.add(field);
    }
    return 'ssh-ed25519 ${base64.encode(blob.takeBytes())} ignored-comment';
  }

  test('独立 Ed25519 设备登记、禁用、撤销和原子 authorized_keys', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vk_node_devices_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    DateTime now = DateTime(2026, 8, 21, 10);
    final WindowsNodeDeviceService service = WindowsNodeDeviceService(
      directory: directory,
      clock: () => now,
      random: Random(1),
    );

    final WindowsNodeDevice macA = await service.enroll(
      label: 'MacBook-A',
      publicKey: publicKey(1),
    );
    final WindowsNodeDevice macB = await service.enroll(
      label: 'MacBook-B',
      publicKey: publicKey(40),
    );
    expect(macA.fingerprint, startsWith('SHA256:'));
    expect(macB.fingerprint, isNot(macA.fingerprint));
    expect(await service.authorizedKeysContents(), contains(macA.publicKey));
    expect(await service.authorizedKeysContents(), contains(macB.publicKey));

    await expectLater(
      service.enroll(label: '复制私钥', publicKey: publicKey(1)),
      throwsA(isA<FormatException>()),
    );
    await service.setEnabled(macA.id, enabled: false);
    expect(
      await service.authorizedKeysContents(),
      isNot(contains(macA.publicKey)),
    );
    expect(await service.authorizedKeysContents(), contains(macB.publicKey));
    await service.setEnabled(macA.id, enabled: true);
    now = now.add(const Duration(hours: 1));
    await service.recordConnection(macA.fingerprint);
    expect(
      (await service.list())
          .firstWhere((item) => item.id == macA.id)
          .lastConnectedAt,
      now,
    );

    await service.revoke(macA.id);
    final String authorized = await service.authorizedKeysContents();
    expect(authorized, isNot(contains(macA.publicKey)));
    expect(authorized, contains(macB.publicKey), reason: '撤销一台设备不能影响其他设备');
    expect(File('${service.registryFile.path}.tmp').existsSync(), isFalse);
  });

  test('拒绝私钥、RSA、损坏公钥和宽于 /24 的网络范围', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vk_node_devices_invalid_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final WindowsNodeDeviceService service = WindowsNodeDeviceService(
      directory: directory,
    );
    for (final String value in <String>[
      '-----BEGIN OPENSSH PRIVATE KEY-----',
      'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ==',
      'ssh-ed25519 broken',
    ]) {
      await expectLater(
        service.enroll(label: 'invalid', publicKey: value),
        throwsA(isA<FormatException>()),
      );
    }
    expect(
      () => service.onboarding(
        host: '192.168.3.10',
        port: 22,
        hostKeyFingerprint: 'SHA256:host-key',
        allowedCidr: '192.168.0.0/16',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('onboarding 只含连接事实和固定 host key 不含秘密', () {
    final WindowsNodeOnboarding onboarding = WindowsNodeDeviceService()
        .onboarding(
          host: '192.168.3.10',
          port: 22,
          hostKeyFingerprint: 'SHA256:host-key',
          allowedCidr: '192.168.3.0/24',
        );
    final String encoded = jsonEncode(onboarding.toJson());
    expect(encoded, contains('StrictHostKeyChecking yes'));
    expect(encoded, contains('SHA256:host-key'));
    expect(encoded.toLowerCase(), isNot(contains('privatekey')));
    expect(encoded.toLowerCase(), isNot(contains('password')));
  });
}
