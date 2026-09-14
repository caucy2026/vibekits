import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled =
      Platform.environment['VIBEKITS_REAL_REMOTE_APP_DEPLOY'] == '1';

  test(
    'deploys, launches, inspects, and captures an authorized remote Mac app',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final packagePath =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_PACKAGE'] ?? '';
      final expectedIdentity =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_IDENTITY'] ?? '';
      final appName =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_APP_NAME'] ?? '';
      final expectedVersion =
          Platform.environment['VIBEKITS_REAL_REMOTE_MAC_VERSION'] ?? '';
      expect(File(executable).existsSync(), isTrue);
      expect(File(packagePath).existsSync(), isTrue);
      expect(routingId, isNotEmpty);
      expect(expectedIdentity, isNotEmpty);
      expect(appName, isNotEmpty);

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

      // Replacing a running app can leave the old process image alive. A failed
      // stop is harmless when the app was not running, so inspect the result but
      // do not turn that state into a false deployment failure.
      await controller.call(
        routingId,
        'vibekits.device.app_control',
        <String, Object?>{'action': 'stop', 'target': appName},
      );
      final upload = await controller.uploadFile(routingId, packagePath);
      final remotePackage = '${upload['remotePath']}';
      addTearDown(() async {
        try {
          await controller.runSshCommand(routingId, "rm -f '$remotePackage'");
        } on Object {
          // The simulator transport owns final connection cleanup.
        }
      });

      final installed = _toolData(
        await controller
            .call(routingId, 'vibekits.device.app_install', <String, Object?>{
              'packagePath': remotePackage,
              'sha256': '${upload['sha256']}',
              'expectedIdentity': expectedIdentity,
            }),
      );
      expect(
        installed['ok'],
        isTrue,
        reason: 'remote install response: $installed',
      );
      expect(installed['identity'], expectedIdentity);
      if (expectedVersion.isNotEmpty) {
        expect(installed['version'], expectedVersion);
      }

      final launched = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.app_control',
          <String, Object?>{'action': 'launch', 'target': appName},
        ),
      );
      expect(launched['ok'], isTrue);
      await Future<void>.delayed(const Duration(seconds: 4));

      final processes = _toolData(
        await controller.call(
          routingId,
          'vibekits.device.processes',
          const <String, Object?>{'query': 'KEMI', 'limit': 20},
        ),
      );
      expect((processes['processes']! as List), isNotEmpty);

      final screenshot = await controller.captureScreenshot(routingId);
      expect(screenshot['captured'], isTrue);
      expect(screenshot['targetSha256'], screenshot['sha256']);
      final screenshotFile = File('${screenshot['localPath']}');
      expect(await screenshotFile.exists(), isTrue);

      // Keep the application installed and running for the user's hands-on
      // acceptance. The screenshot is also kept so it can be visually reviewed.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_APP_DEPLOY identity=$expectedIdentity '
        'version=${installed['version']} running=true '
        'screenshot=${screenshotFile.path} sha=${screenshot['sha256']} '
        'rollback=${installed['rollbackPath']}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_APP_DEPLOY=1',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Map<String, Object?> _toolData(Map<String, Object?> raw) {
  final structured = raw['structuredContent'];
  if (structured is! Map) return raw;
  final envelope = Map<String, Object?>.from(structured);
  final data = envelope['data'];
  return data is Map ? Map<String, Object?>.from(data) : envelope;
}
