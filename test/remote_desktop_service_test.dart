import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/remote_desktop_service.dart';

void main() {
  test('Windows 使用 mstsc 参数数组且不携带密码', () {
    const String canary = 'VK_RDP_SECRET_7f3a';
    final RemoteDesktopLaunchRequest request =
        RemoteDesktopService.buildRequest(
          const RemoteDesktopTarget(host: 'rdp.test', port: 3390),
          platform: RemoteDesktopPlatform.windows,
        );

    expect(request.executable, 'mstsc.exe');
    expect(request.arguments, <String>['/v:rdp.test:3390']);
    expect(request.arguments.join(' '), isNot(contains(canary)));
  });

  test('macOS 使用系统 open 打开 VNC URL 并正确包裹 IPv6', () {
    final RemoteDesktopLaunchRequest request =
        RemoteDesktopService.buildRequest(
          const RemoteDesktopTarget(host: '2001:db8::8', port: 5901),
          platform: RemoteDesktopPlatform.macos,
        );

    expect(request.executable, '/usr/bin/open');
    expect(request.arguments, <String>['vnc://[2001:db8::8]:5901']);
  });

  test('系统客户端缺失时分别给出 Windows 和 macOS 可行动错误', () async {
    Future<void> missing(String executable, List<String> arguments) =>
        Future<void>.error(ProcessException(executable, arguments));

    await expectLater(
      RemoteDesktopService.launch(
        const RemoteDesktopTarget(host: 'rdp.test', port: 3389),
        platform: RemoteDesktopPlatform.windows,
        launcher: missing,
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('Windows 系统可选功能'),
        ),
      ),
    );
    await expectLater(
      RemoteDesktopService.launch(
        const RemoteDesktopTarget(host: 'screen.test', port: 5900),
        platform: RemoteDesktopPlatform.macos,
        launcher: missing,
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('macOS 系统屏幕共享客户端不可用'),
        ),
      ),
    );
  });

  test('拒绝选项注入和非法端口', () {
    expect(
      () => const RemoteDesktopTarget(host: '-oBad', port: 3389).validate(),
      throwsFormatException,
    );
    expect(
      () => const RemoteDesktopTarget(host: 'rdp.test', port: 0).validate(),
      throwsFormatException,
    );
  });
}
