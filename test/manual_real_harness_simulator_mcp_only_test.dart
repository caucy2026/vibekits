import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final bool enabled =
      Platform.environment['VIBEKITS_REAL_REMOTE_SIMULATOR'] == '1';

  test(
    'real ID simulator keeps MCP responsive without the SSH carrier',
    () async {
      final String executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final String routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final bool forceRelay =
          Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1';
      expect(File(executable).existsSync(), isTrue);

      final RustDeskHostInfo host =
          await RustDeskHarnessShareService.ensureHostAvailable(
            configuredExecutable: executable,
          );
      final HarnessSimulatorController controller = HarnessSimulatorController(
        resolveHost: () async => host,
        enableSshBootstrap: false,
      );
      addTearDown(controller.closeAll);

      final Map<String, Object?> connected = await controller.connect(
        routingId,
        forceRelay: forceRelay,
      );
      expect(connected['connected'], isTrue);
      expect(controller.catalog(routingId).length, greaterThan(100));
      final Map<String, Object?> status = await controller.call(
        routingId,
        'vibekits.remote_assistance.status',
        const <String, Object?>{},
      );
      expect(status, isNotEmpty);
      final Map<String, Object?> processes = await controller.call(
        routingId,
        'vibekits.device.processes',
        const <String, Object?>{'query': 'Vibekits'},
      );
      expect(processes, isNotEmpty);
      // ignore: avoid_print
      print(
        'HARNESS_REAL_MCP_ONLY tools=${controller.catalog(routingId).length} '
        'forceRelay=$forceRelay statusKeys=${status.length} '
        'processKeys=${processes.length}',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_SIMULATOR=1',
  );
}
