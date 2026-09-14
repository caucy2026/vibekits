import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled =
      Platform.environment['VIBEKITS_REAL_REMOTE_APP_CENTER'] == '1';

  test(
    'opens the remote Mac App Center through accessibility and captures it',
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
      await controller.connect(
        routingId,
        forceRelay: Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1',
      );

      final activated = await controller.runSshCommand(
        routingId,
        "/usr/bin/open -a 'KEMI远程办公'",
      );
      expect(activated['ok'], isTrue, reason: '$activated');
      await Future<void>.delayed(const Duration(seconds: 2));

      final clicked = await controller.runSshCommand(
        routingId,
        "/usr/bin/osascript -e 'tell application \"System Events\" to tell process \"KEMI远程办公\" to click first UI element of front window whose description is \"应用\"'",
      );
      if (clicked['ok'] != true) {
        final fallback = await controller.runSshCommand(
          routingId,
          "/usr/bin/osascript -e 'tell application \"System Events\" to tell process \"KEMI远程办公\" to click first UI element of front window whose name is \"应用\"'",
        );
        expect(
          fallback['ok'],
          isTrue,
          reason: 'primary=$clicked fallback=$fallback',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 5));

      final screenshot = await controller.captureScreenshot(routingId);
      final file = File('${screenshot['localPath']}');
      expect(await file.exists(), isTrue);
      // Keep the frame for visual confirmation that the destination rendered.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_APP_CENTER clicked=true screenshot=${file.path} '
        'sha=${screenshot['sha256']}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_APP_CENTER=1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
