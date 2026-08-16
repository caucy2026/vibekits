import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';

void main() {
  test('SSH 参数逐项传递并保留主机密钥验证', () {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_ssh_');
    final File key = File(
      '${sandbox.path}${Platform.pathSeparator}key with space',
    )..writeAsStringSync('test key');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final RemoteLaunchRequest request = RemoteLaunchRequest(
      mode: RemoteSessionMode.ssh,
      profile: RemoteConnectionProfile(
        host: 'server.example.com',
        user: 'developer',
        port: 2222,
        identityFile: key.path,
      ),
    );

    final List<String> args = request.buildArguments();
    expect(request.executable, 'ssh');
    expect(args, containsAllInOrder(<String>['-p', '2222', '-l', 'developer']));
    expect(args, contains('StrictHostKeyChecking=ask'));
    expect(args, contains('BatchMode=yes'));
    expect(args, containsAllInOrder(<String>['-i', key.path]));
    expect(args.last, 'server.example.com');
    expect(args, isNot(contains('StrictHostKeyChecking=no')));
  });

  test('SFTP 使用正确端口参数且不经过 shell 字符串', () {
    final RemoteLaunchRequest request = RemoteLaunchRequest(
      mode: RemoteSessionMode.sftp,
      profile: const RemoteConnectionProfile(
        host: '10.0.0.8',
        user: r'domain\developer',
        port: 2200,
      ),
    );
    expect(request.executable, 'sftp');
    expect(
      request.buildArguments(),
      containsAllInOrder(<String>['-P', '2200']),
    );
  });

  test('本地转发只监听回环并要求建立失败时退出', () {
    final RemoteLaunchRequest request = RemoteLaunchRequest(
      mode: RemoteSessionMode.localForward,
      profile: const RemoteConnectionProfile(
        host: 'jump.example.com',
        user: 'dev',
      ),
      localPort: 5433,
      targetHost: 'db.internal',
      targetPort: 5432,
    );
    final List<String> args = request.buildArguments();
    expect(
      args,
      containsAllInOrder(<String>[
        '-N',
        '-L',
        '127.0.0.1:5433:db.internal:5432',
      ]),
    );
    expect(args, contains('ExitOnForwardFailure=yes'));
  });

  test('拒绝选项注入、非法端口和不存在私钥', () {
    expect(
      () => const RemoteLaunchRequest(
        mode: RemoteSessionMode.ssh,
        profile: RemoteConnectionProfile(host: '-oProxyCommand=bad', user: 'x'),
      ).buildArguments(),
      throwsFormatException,
    );
    expect(
      () => const RemoteLaunchRequest(
        mode: RemoteSessionMode.ssh,
        profile: RemoteConnectionProfile(host: 'host;bad', user: 'x'),
      ).buildArguments(),
      throwsFormatException,
    );
    expect(
      () => const RemoteLaunchRequest(
        mode: RemoteSessionMode.ssh,
        profile: RemoteConnectionProfile(host: 'host', user: 'x', port: 0),
      ).buildArguments(),
      throwsFormatException,
    );
    expect(
      () => const RemoteLaunchRequest(
        mode: RemoteSessionMode.ssh,
        profile: RemoteConnectionProfile(
          host: 'host',
          user: 'x',
          identityFile: r'Z:\missing\key',
        ),
      ).buildArguments(),
      throwsFormatException,
    );
  });
}
