import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_controller_session.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_peer_store.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_REMOTE_SESSION'] == '1';
  test(
    'paired 63 session synchronizes state, performs read-only command, cancels, and closes',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final remoteRoutingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final forceRelay =
          Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] != '0';
      final host = await RustDeskHarnessShareService.ensureHostAvailable(
        configuredExecutable: executable,
      );
      expect(host.callable, isTrue);
      final peer = (await HarnessRemotePeerStore().load()).singleWhere(
        (value) => value.routingId == remoteRoutingId,
      );
      expect(peer.connectionReady, isTrue);
      final identity = await HarnessRemoteIdentityStore.instance.loadOrCreate();
      final restored = <Map<String, dynamic>>[];
      final applied = <Map<String, dynamic>>[];
      final session = await HarnessRemoteControllerSession.connect(
        executable: host.executable,
        peer: peer,
        identity: identity,
        forceRelay: forceRelay,
        timeout: const Duration(minutes: 10),
        restoreOfficialSnapshot: (rows) async {
          restored
            ..clear()
            ..addAll(rows);
        },
        applyOfficialEvents: (rows) async => applied.addAll(rows),
      );
      addTearDown(session.close);

      final stateDeadline = DateTime.now().add(const Duration(seconds: 20));
      while ((session.model.stale || restored.isEmpty) &&
          DateTime.now().isBefore(stateDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(session.model.stale, isFalse);
      expect(restored, isNotEmpty);
      final workspace = restored.firstWhere(
        (row) =>
            row['sessionIds'] is List && (row['sessionIds'] as List).isNotEmpty,
      );
      final workspaceId = workspace['workspaceId'] as String;
      final sessionId = (workspace['sessionIds'] as List).first as String;
      final historyId = session.client.newCommandId();
      final history = await session.client.call(
        commandId: historyId,
        workspaceId: workspaceId,
        sessionId: sessionId,
        method: 'session.history',
        payload: const {},
      );
      final cancelId = session.client.newCommandId();
      final cancel = await session.client.cancel(
        commandId: cancelId,
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      final roundTrip = await session.client.heartbeat();
      await session.close();

      // Printed only by the explicitly enabled manual acceptance run. Do not
      // print conversation content, certificates, credentials, or host paths.
      // ignore: avoid_print
      print(
        'HARNESS_REAL_SESSION workspace=$workspaceId session=$sessionId '
        'phase=${workspace['phase']} historyKeys=${history.keys.toList()..sort()} '
        'cancelKeys=${cancel.keys.toList()..sort()} rttMs=${roundTrip.inMilliseconds} '
        'events=${applied.length} closed=true',
      );
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_SESSION=1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
