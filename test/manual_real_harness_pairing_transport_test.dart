import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_pairing_service.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled =
      Platform.environment['VIBEKITS_REAL_PAIRING_TRANSPORT'] == '1';

  test(
    'pairing byte tunnel carries a request and response before approval',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      final localPort = await RustDeskHarnessShareService.allocateTunnelPort();
      final tunnel = await RustDeskHarnessShareService.openTunnel(
        host.executable,
        routingId: routingId,
        localPort: localPort,
        remotePort: HarnessRemotePairingHost.port,
        forceRelay: true,
      );
      addTearDown(tunnel.close);
      final socket = await Socket.connect('127.0.0.1', localPort);
      addTearDown(socket.close);
      final response = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 90));
      socket.add(utf8.encode('{"kind":"transport-probe","version":1}\n'));
      await socket.flush();
      await tunnel.waitUntilConnected(timeout: const Duration(seconds: 90));
      expect(await response, contains('PAIRING_BAD_REQUEST'));
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_PAIRING_TRANSPORT=1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
