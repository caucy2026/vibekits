import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/deepseek_harness_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled Windows Harness opens its loopback web port',
    () async {
      final String runtime =
          Platform.environment['VIBEKITS_HARNESS_RUNTIME_ROOT'] ?? '';
      if (!Platform.isWindows || runtime.isEmpty) return;

      final Directory scratch = await Directory.systemTemp.createTemp(
        'vibekits-windows-harness-smoke-',
      );
      final int port = await DeepSeekHarnessService.findFreeLoopbackPort();
      HarnessSessionHandle? session;
      try {
        session = await DeepSeekHarnessService.startWebAgent(
          HarnessWebRequest(
            workspace: scratch.path,
            apiKey: '',
            port: port,
            debugDirectory: scratch.path,
          ),
        );
        final Stopwatch watch = Stopwatch()..start();
        bool ready = false;
        while (watch.elapsed < const Duration(seconds: 90)) {
          expect(
            session.running,
            isTrue,
            reason: 'Harness exited before ready',
          );
          if ((session.url.queryParameters['token'] ?? '').isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            continue;
          }
          try {
            final Socket socket = await Socket.connect(
              InternetAddress.loopbackIPv4,
              port,
              timeout: const Duration(milliseconds: 500),
            );
            socket.destroy();
            ready = true;
            break;
          } on SocketException {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        expect(
          ready,
          isTrue,
          reason: 'Harness did not announce its web token and bind loopback',
        );
      } finally {
        await session?.stop();
        await scratch.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
