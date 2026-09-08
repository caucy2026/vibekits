import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/features/dev_tools/domain/harness_remote_identity.dart';
import '../lib/features/dev_tools/domain/harness_remote_ledger.dart';
import '../lib/features/dev_tools/domain/harness_remote_host.dart';
import '../lib/features/dev_tools/domain/harness_remote_execution.dart';
import '../lib/features/dev_tools/domain/harness_remote_tls_channel.dart';
import '../lib/features/dev_tools/domain/harness_remote_connection.dart';
import '../lib/features/dev_tools/domain/harness_remote_workspace_client.dart';
import '../lib/features/dev_tools/domain/harness_work_status.dart';

void main() {
  Future<HarnessRemoteIdentity> identity() => HarnessRemoteIdentityStore(
    read: (_) async => null,
    write: (_, value) async {},
  ).loadOrCreate();

  test(
    'dedicated identity persists, never silently rotates corrupt credentials',
    () async {
      final secrets = <String, String>{};
      HarnessRemoteIdentityStore store() => HarnessRemoteIdentityStore(
        read: (key) async => secrets[key],
        write: (key, value) async {
          secrets[key] = value;
        },
      );
      final first = await store().loadOrCreate();
      final second = await store().loadOrCreate();
      expect(first.deviceId, second.deviceId);
      expect(first.deviceId, startsWith('VH-'));
      expect(secrets.keys, [HarnessRemoteIdentityStore.credentialKey]);
      secrets[HarnessRemoteIdentityStore.credentialKey] = '{"broken":"value"}';
      await expectLater(store().loadOrCreate(), throwsStateError);
      expect(
        secrets[HarnessRemoteIdentityStore.credentialKey],
        '{"broken":"value"}',
      );
    },
  );

  test(
    'real mTLS transport supports scoped commands, independent cancel and revoke',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'harness-host-test-',
      );
      final hostIdentity = await identity();
      final clientIdentity = await identity();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final websockets = <WebSocket>[];
      final promptEntered = Completer<void>();
      final finishPrompt = Completer<void>();
      var promptCalls = 0;
      var cancelCalls = 0;
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          websockets.add(await WebSocketTransformer.upgrade(request));
          return;
        }
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        Map<String, Object?> result = {'ok': true, 'value': {}};
        if (body['method'] == 'workspace.list') {
          result = {
            'ok': true,
            'value': {
              'items': [
                {
                  'workspaceId': 'w',
                  'title': 'Visible',
                  'sessionIds': ['s'],
                },
                {
                  'workspaceId': 'secret',
                  'title': 'Hidden',
                  'sessionIds': ['other'],
                },
              ],
            },
          };
        } else if (body['method'] == 'session.prompt') {
          promptCalls++;
          promptEntered.complete();
          await finishPrompt.future;
        } else if (body['method'] == 'session.cancel') {
          cancelCalls++;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'type': 'server-response',
            'rpcId': body['rpcId'],
            'result': result,
          }),
        );
        await request.response.close();
      });
      final host = HarnessRemoteHost(
        officialEndpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        ledger: await HarnessRemoteLedger.open(
          File('${directory.path}/ledger'),
        ),
        workSnapshot: () {
          final now = DateTime.utc(2026, 9, 8);
          return HarnessWorkRegistrySnapshot(
            streamSequence: 7,
            generatedAt: now,
            aggregate: const HarnessWorkAggregate(
              taskCount: 1,
              busyCount: 1,
              waitingApprovalCount: 0,
              failedCount: 0,
            ),
            tasks: [
              HarnessTaskSnapshot(
                deviceRef: 'device',
                workspaceRef: 'public-workspace',
                workspaceLabel: 'Visible',
                sessionRef: 'session',
                taskId: 'task',
                streamSequence: 7,
                taskRevision: 2,
                phase: HarnessWorkPhase.reasoning,
                message: '正在继续分析',
                startedAt: now,
                updatedAt: now,
              ),
            ],
          );
        },
      );
      host.approveCertificate(
        clientIdentity.fingerprint,
        HarnessRemoteGrant(
          peerId: clientIdentity.deviceId,
          workspaceIds: {'w'},
          operations: {'session.history', 'session.prompt', 'session.cancel'},
        ),
      );
      HarnessRemoteConnection? connection;
      try {
        await host.start(
          bindAddress: InternetAddress.loopbackIPv4,
          port: 0,
          identity: hostIdentity.context(
            trustedCertificates: [clientIdentity.certificatePem],
          ),
        );
        final channel = await HarnessRemoteTlsChannel.connect(
          host: '127.0.0.1',
          port: host.port!,
          trustedPeerId: hostIdentity.deviceId,
          trustedCertificateSha256: hostIdentity.fingerprint,
          clientIdentity: clientIdentity.context(),
        );
        connection = HarnessRemoteConnection(channel);
        final client = HarnessRemoteWorkspaceClient(connection);
        await client.negotiate();
        expect(client.connectionId, isNotEmpty);
        expect(await client.heartbeat(), isA<Duration>());
        final state = await client.readState();
        expect((state['workspaces'] as List).length, 1);
        expect((state['workspaces'] as List).single['title'], 'Visible');
        expect((state['workspaces'] as List).single['phase'], 'reasoning');
        expect((state['workspaces'] as List).single['busyTaskCount'], 1);
        final readyDeadline = DateTime.now().add(const Duration(seconds: 5));
        var live = state;
        while (live['live'] != true && DateTime.now().isBefore(readyDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          live = await client.readState();
        }
        expect(live['live'], true, reason: 'Idle event stream is still live');
        final oldEpoch = live['epoch'] as String;
        await websockets.first.close();
        final reconnectDeadline = DateTime.now().add(
          const Duration(seconds: 5),
        );
        while ((live['live'] != true || live['epoch'] == oldEpoch) &&
            DateTime.now().isBefore(reconnectDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          live = await client.readState();
        }
        expect(live['live'], true);
        expect(live['epoch'], isNot(oldEpoch));
        expect(
          (await client.readState(
            epoch: oldEpoch,
            sequence: 0,
          ))['snapshotRequired'],
          true,
        );
        final prompt = client.call(
          commandId: 'prompt1',
          workspaceId: 'w',
          sessionId: 's',
          method: 'session.prompt',
          payload: {'text': 'local fixture only'},
        );
        await promptEntered.future.timeout(const Duration(seconds: 5));
        await client
            .cancel(commandId: 'cancel1', workspaceId: 'w', sessionId: 's')
            .timeout(const Duration(seconds: 5));
        expect(cancelCalls, 1);
        finishPrompt.complete();
        await prompt;
        await client.call(
          commandId: 'prompt1',
          workspaceId: 'w',
          sessionId: 's',
          method: 'session.prompt',
          payload: {'text': 'local fixture only'},
        );
        expect(promptCalls, 1);
        await expectLater(
          client.call(
            commandId: 'other',
            workspaceId: 'secret',
            sessionId: 'other',
            method: 'session.history',
            payload: {},
          ),
          throwsA(isA<HarnessRemoteActionException>()),
        );
        await host.revoke(clientIdentity.deviceId);
        await expectLater(client.readState(), throwsA(anything));
      } finally {
        if (!finishPrompt.isCompleted) finishPrompt.complete();
        await connection?.close();
        await host.close();
        for (final socket in websockets) {
          await socket.close();
        }
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
