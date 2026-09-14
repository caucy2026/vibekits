import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled =
      Platform.environment['VIBEKITS_REAL_REMOTE_SCREENSHOT'] == '1';

  test(
    'real ID simulator captures and downloads one verified frame',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      expect(File(executable).existsSync(), isTrue);
      expect(routingId, isNotEmpty);

      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      final controller = HarnessSimulatorController(
        resolveHost: () async => host,
      );
      addTearDown(controller.closeAll);

      final connected = await controller.connect(
        routingId,
        forceRelay: Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1',
      );
      expect(connected['connected'], isTrue);

      final result = await controller.captureScreenshot(routingId);
      expect(result['captured'], isTrue);
      expect(result['singleFrame'], isTrue);
      expect(result['sha256'], hasLength(64));
      expect(result['targetSha256'], result['sha256']);
      final localFile = File('${result['localPath']}');
      expect(await localFile.exists(), isTrue);
      expect(await localFile.length(), result['bytes']);
      // The downloaded image is a temporary diagnostic owned by this test.
      addTearDown(() async {
        if (await localFile.exists()) await localFile.delete();
      });

      // Do not print the screen contents or path. Integrity and dimensions are
      // sufficient acceptance evidence for the one-frame diagnostic channel.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_SCREENSHOT shaVerified=true '
        'bytes=${result['bytes']} width=${result['width']} '
        'height=${result['height']}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_SCREENSHOT=1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
