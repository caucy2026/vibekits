import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_controller_session.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_peer_store.dart';

void main() {
  final enabled = Platform.environment['VIBEKITS_REAL_REMOTE_SESSION'] == '1';

  test(
    'real paired peer synchronizes projects, sessions, feedback and stop',
    () async {
      final executable =
          Platform.environment['VIBEKITS_HARNESS_RELAY_EXECUTABLE'] ?? '';
      final routingId =
          Platform.environment['VIBEKITS_REMOTE_ROUTING_ID'] ?? '';
      final mutate =
          Platform.environment['VIBEKITS_REAL_REMOTE_MUTATION'] == '1';
      final forceRelay =
          Platform.environment['VIBEKITS_REMOTE_FORCE_RELAY'] == '1';
      expect(File(executable).existsSync(), isTrue);

      final peers = await HarnessRemotePeerStore().load();
      final peer = peers.singleWhere((item) => item.routingId == routingId);
      expect(peer.connectionReady, isTrue);
      final identity = await HarnessRemoteIdentityStore.instance.loadOrCreate();
      final snapshots = <List<Map<String, dynamic>>>[];
      final events = <Map<String, dynamic>>[];
      final session = await HarnessRemoteControllerSession.connect(
        executable: executable,
        peer: peer,
        identity: identity,
        forceRelay: forceRelay,
        timeout: const Duration(seconds: 40),
        restoreOfficialSnapshot: (rows) async => snapshots.add(rows),
        applyOfficialEvents: (rows) async => events.addAll(rows),
      );
      try {
        await _waitUntil(
          () => session.model.workspaces.isNotEmpty,
          timeout: const Duration(seconds: 30),
          failure: () =>
              'REMOTE_PROJECT_SYNC_TIMEOUT: ${session.model.error ?? 'unknown'}',
        );
        final workspaces = session.model.workspaces;
        final workspace = workspaces.firstWhere(
          (row) =>
              row['sessionIds'] is List &&
              (row['sessionIds'] as List).isNotEmpty,
          orElse: () => throw StateError('REMOTE_SESSION_LIST_EMPTY'),
        );
        final workspaceId = workspace['workspaceId'] as String;
        final sessionId = (workspace['sessionIds'] as List).first as String;
        final history = await session.client.call(
          commandId: session.client.newCommandId(),
          workspaceId: workspaceId,
          sessionId: sessionId,
          method: 'session.history',
          payload: const <String, Object?>{},
        );
        expect(history['type'], 'server-response');

        // Keep the regular manual smoke read-only. Mutation is a second,
        // explicit acceptance gate because it invokes the remote model.
        if (mutate) {
          final prompt = await session.client.call(
            commandId: session.client.newCommandId(),
            workspaceId: workspaceId,
            sessionId: sessionId,
            method: 'session.prompt',
            payload: const <String, Object?>{
              'text': '远程闭环验收：只回复 REMOTE_ACCEPTANCE_READY，不调用工具。',
              'mode': 'queue',
            },
          );
          expect(prompt['type'], 'server-response');
          final cancel = await session.client.cancel(
            commandId: session.client.newCommandId(),
            workspaceId: workspaceId,
            sessionId: sessionId,
          );
          expect(cancel['type'], 'server-response');
          await _waitUntil(
            () => events.isNotEmpty || snapshots.length >= 2,
            timeout: const Duration(seconds: 20),
            failure: () => 'REMOTE_FEEDBACK_TIMEOUT',
          );
        }

        // Print only counts and transport-neutral state; never conversation
        // content, paths, credentials, certificates, or provider metadata.
        // ignore: avoid_print
        print(
          'HARNESS_REMOTE_ACCEPTANCE '
          'workspaces=${workspaces.length} '
          'sessions=${workspaces.fold<int>(0, (sum, row) => sum + ((row['sessionIds'] as List?)?.length ?? 0))} '
          'events=${events.length} mutate=$mutate',
        );
      } finally {
        await session.close();
      }
    },
    skip: enabled ? false : 'set VIBEKITS_REAL_REMOTE_SESSION=1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  required Duration timeout,
  required String Function() failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (!predicate()) throw TimeoutException(failure(), timeout);
}
