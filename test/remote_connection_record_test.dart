import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_connection_record.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';

void main() {
  test('远程会话记录往返不包含密码或口令', () {
    const RemoteConnectionRecord record = RemoteConnectionRecord(
      id: 'remote_test_1',
      name: '生产跳板机',
      mode: RemoteSessionMode.ssh,
      host: 'server.example.com',
      user: 'developer',
      port: 2222,
      identityFile: r'D:\Keys\id_ed25519',
      favorite: true,
      lastUsedEpochMs: 123456,
      hostKeyType: 'ssh-ed25519',
      hostKeyFingerprint: 'SHA256:AbCdEf0123456789xyzXYZ+/test',
    );
    final String encoded = record.encode();
    final RemoteConnectionRecord restored = RemoteConnectionRecord.decode(
      encoded,
    )!;

    expect(restored.id, record.id);
    expect(restored.mode, RemoteSessionMode.ssh);
    expect(restored.host, record.host);
    expect(restored.favorite, isTrue);
    expect(restored.hostKeyFingerprint, record.hostKeyFingerprint);
    expect(encoded.toLowerCase(), isNot(contains('password')));
    expect(encoded.toLowerCase(), isNot(contains('secret')));
    expect(encoded.toLowerCase(), isNot(contains('passphrase')));
  });

  test('主机指纹必须类型与 SHA256 值成对保存', () {
    const String partial =
        '{"id":"bad_host_key","name":"坏指纹","mode":"ssh",'
        '"host":"host.example.com","user":"dev","port":22,'
        '"hostKeyType":"ssh-ed25519"}';
    expect(RemoteConnectionRecord.decode(partial), isNull);
  });

  test('损坏记录被忽略且收藏和最近时间决定顺序', () {
    const RemoteConnectionRecord oldFavorite = RemoteConnectionRecord(
      id: 'favorite',
      name: '收藏',
      mode: RemoteSessionMode.sftp,
      host: 'sftp.example.com',
      user: 'dev',
      port: 22,
      favorite: true,
      lastUsedEpochMs: 1,
    );
    const RemoteConnectionRecord recent = RemoteConnectionRecord(
      id: 'recent',
      name: '最近',
      mode: RemoteSessionMode.ssh,
      host: 'ssh.example.com',
      user: 'dev',
      port: 22,
      lastUsedEpochMs: 999,
    );

    final List<RemoteConnectionRecord> records =
        RemoteConnectionRecord.decodeMany(<String>[
          recent.encode(),
          '{bad json',
          oldFavorite.encode(),
          recent.encode(),
        ]);

    expect(records.map((RemoteConnectionRecord value) => value.id), <String>[
      'favorite',
      'recent',
    ]);
  });

  test('即使旧数据含敏感字段也不会写回', () {
    final String source = jsonEncode(<String, Object?>{
      'id': 'legacy',
      'name': '旧记录',
      'mode': 'ssh',
      'host': 'legacy.example.com',
      'user': 'dev',
      'port': 22,
      'password': 'VK_SECRET_20260817_7f3a',
    });
    final RemoteConnectionRecord record = RemoteConnectionRecord.decode(
      source,
    )!;
    expect(record.encode(), isNot(contains('VK_SECRET_20260817_7f3a')));
  });

  test('远程桌面记录允许空用户名并可跨重启恢复', () {
    const RemoteConnectionRecord desktop = RemoteConnectionRecord(
      id: 'desktop_test',
      name: '测试桌面',
      mode: RemoteSessionMode.remoteDesktop,
      host: 'rdp.test',
      user: '',
      port: 3390,
    );

    final RemoteConnectionRecord restored = RemoteConnectionRecord.decode(
      desktop.encode(),
    )!;
    expect(restored.mode, RemoteSessionMode.remoteDesktop);
    expect(restored.user, isEmpty);
    expect(restored.port, 3390);
  });
}
