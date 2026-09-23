import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  test('VibeKits launch uses its own port and preserves explicit ports', () {
    const spec = HarnessLaunchSpec(workspace: '/tmp');
    expect(spec.port, 13080);
    expect(spec.arguments, ['web', '--port', '13080', '--no-open']);
    expect(spec.url.port, 13080);
    expect(
      const HarnessLaunchSpec(workspace: '/tmp', port: 14080).url.port,
      14080,
    );
  });
  test(
    'free preferred port is selected; occupied port falls back without eviction',
    () async {
      ServerSocket? occupied;
      try {
        // A running VibeKits may already own this port. Never stop it for a test.
        occupied = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          HarnessLaunchSpec.defaultPort,
        );
        await occupied.close();
        final preferred = await DeepSeekHarnessService.findFreeLoopbackPort();
        expect(preferred, HarnessLaunchSpec.defaultPort);
        occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferred);
        addTearDown(occupied.close);
      } on SocketException {
        // Existing application exercises the same occupied-port path.
      }
      const first = HarnessLaunchSpec.defaultPort;
      final fallback = await DeepSeekHarnessService.findFreeLoopbackPort();
      expect(fallback, isNot(13080));
      expect(fallback, isNot(3080));
      final probe = await Socket.connect(InternetAddress.loopbackIPv4, first);
      probe.destroy();
      final free = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        fallback,
      );
      await free.close();
    },
  );
}
