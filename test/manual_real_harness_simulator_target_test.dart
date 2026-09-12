import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_target_runtime.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final bool enabled =
      Platform.environment['VIBEKITS_REAL_SIMULATOR_TARGET'] == '1';

  test(
    'real simulator target exposes MCP and SSH through its routing ID',
    () async {
      final String executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final String stopFile =
          Platform.environment['VIBEKITS_REAL_TARGET_STOP_FILE'] ?? '';
      expect(File(executable).existsSync(), isTrue);
      expect(stopFile, isNotEmpty);
      await File(stopFile).delete().catchError((_) => File(stopFile));

      final HarnessSimulatorTargetRuntime runtime =
          HarnessSimulatorTargetRuntime(
            inspectHost: () => RustDeskHarnessShareService.inspect(
              configuredExecutable: executable,
            ),
            startHost: () => RustDeskHarnessShareService.ensureHostAvailable(
              configuredExecutable: executable,
            ),
            stopHost: () => RustDeskHarnessShareService.stopHost(
              configuredExecutable: executable,
            ),
          );
      try {
        await RustDeskHarnessShareService.stopHost(
          configuredExecutable: executable,
        );
        await runtime.enable(persist: false);
        expect(runtime.latest.ready, isTrue, reason: runtime.latest.message);
        expect(runtime.latest.routingId, isNotEmpty);
        expect(runtime.latest.sshEndpoint, isNotEmpty);
        // ignore: avoid_print
        print(
          'HARNESS_REAL_TARGET_READY id=${runtime.latest.routingId} '
          'mcp=${runtime.latest.endpoint} ssh=${runtime.latest.sshEndpoint}',
        );
        final DateTime deadline = DateTime.now().add(
          const Duration(minutes: 10),
        );
        while (!File(stopFile).existsSync() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(File(stopFile).existsSync(), isTrue);
        expect(await File(stopFile).readAsString(), contains('PASS'));
      } finally {
        await runtime.disable(persist: false);
        await File(stopFile).delete().catchError((_) => File(stopFile));
      }
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_SIMULATOR_TARGET=1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
