import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_execution.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_pairing_service.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_REMOTE_PAIRING'] == '1';
  test(
    'real RustDesk/HBBS pairing persists the explicitly approved peer',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final remoteRoutingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final workspaceId =
          Platform.environment['VIBEKITS_REMOTE_WORKSPACE_ID'] ?? '';
      final forceRelay =
          Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] != '0';
      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      expect(host.callable, isTrue);
      expect(host.id, isNotEmpty);
      final approval = await HarnessRemotePairingClient().pair(
        executable: host.executable,
        localRoutingId: host.id,
        remoteRoutingId: remoteRoutingId,
        requestedWorkspaceIds: <String>{workspaceId},
        requestedOperations: HarnessRemoteExecution.sessionOperations,
        forceRelay: forceRelay,
        // Native RustDesk authorization precedes the app-level certificate
        // prompt. Keep the manual gate long enough for a real dual-screen
        // operator; the pairing host still expires an exposed certificate
        // request after its own two-minute approval window.
        timeout: const Duration(minutes: 10),
      );
      expect(approval.hostRoutingId, remoteRoutingId);
      expect(approval.grantedWorkspaceIds, contains(workspaceId));
      expect(approval.controllerRecord(remembered: true).connectionReady, true);
      // Printed only in the explicitly enabled manual acceptance run so both
      // screens can compare the same short code before accepting persistence.
      // ignore: avoid_print
      print('HARNESS_REAL_PAIRING_CODE=${approval.comparisonCode}');
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_PAIRING=1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
