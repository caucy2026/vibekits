import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/port_forward_service.dart';
import 'package:vibekits/features/dev_tools/domain/remote_session.dart';

void main() {
  test('本地、远程和 SOCKS5 转发生成明确描述', () {
    const PortForwardSpec local = PortForwardSpec(
      kind: PortForwardKind.local,
      listenPort: 18080,
      targetHost: 'service.internal',
      targetPort: 8080,
    );
    const PortForwardSpec remote = PortForwardSpec(
      kind: PortForwardKind.remote,
      listenPort: 18081,
      targetHost: '127.0.0.1',
      targetPort: 3000,
    );
    const PortForwardSpec dynamic = PortForwardSpec(
      kind: PortForwardKind.dynamic,
      listenPort: 1080,
    );

    local.validate();
    remote.validate();
    dynamic.validate();
    expect(local.description, '127.0.0.1:18080 → service.internal:8080');
    expect(remote.description, '远端 localhost:18081 → 127.0.0.1:3000');
    expect(dynamic.description, 'SOCKS5 127.0.0.1:1080');
  });

  test('端口和目标主机逐项校验且 SOCKS5 不要求目标', () {
    expect(
      () => const PortForwardSpec(
        kind: PortForwardKind.local,
        listenPort: 0,
        targetHost: 'db.internal',
        targetPort: 5432,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const PortForwardSpec(
        kind: PortForwardKind.remote,
        listenPort: 8080,
        targetHost: '-oBad',
        targetPort: 80,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const PortForwardSpec(
        kind: PortForwardKind.dynamic,
        listenPort: 1080,
      ).validate(),
      returnsNormally,
    );
  });

  test('后台 Isolate 连接失败会返回错误且不挂住调用线程', () async {
    final ServerSocket reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int closedPort = reservation.port;
    await reservation.close();

    await expectLater(
      PortForwardService.connect(
        RemoteConnectionProfile(
          host: '127.0.0.1',
          user: 'dev',
          port: closedPort,
        ),
        verifyHostKey: (_, _) async => false,
      ).timeout(const Duration(seconds: 5)),
      throwsA(anything),
    );
  });
}
