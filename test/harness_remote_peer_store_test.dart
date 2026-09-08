import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_peer_store.dart';

void main() {
  HarnessRemotePeer peer({
    String routingId = '1234567890',
    bool remembered = true,
    String transport = 'relay',
  }) => HarnessRemotePeer(
    routingId: routingId,
    deviceId: 'VH-ABC',
    certificateSha256: List.filled(64, 'a').join(),
    workspaceIds: {'workspace'},
    operations: {'session.history'},
    remembered: remembered,
    firstApprovedAt: DateTime.utc(2026, 9, 8, 1),
    lastConnectedAt: DateTime.utc(2026, 9, 8, 2),
    lastTransport: transport,
  );

  test(
    'remembered peer persists complete identity and scope without password',
    () async {
      final values = <String, String>{};
      final store = HarnessRemotePeerStore(
        read: (key) async => values[key],
        write: (key, value) async {
          values[key] = value;
        },
      );
      await store.save(peer());
      final restored = (await store.load()).single;
      expect(restored.routingId, '1234567890');
      expect(restored.certificateSha256, List.filled(64, 'a').join());
      expect(restored.workspaceIds, {'workspace'});
      expect(values.values.single, isNot(contains('password')));
    },
  );

  test('allow-once peer is never written to remembered history', () async {
    final values = <String, String>{};
    final store = HarnessRemotePeerStore(
      read: (key) async => values[key],
      write: (key, value) async {
        values[key] = value;
      },
    );
    await store.save(peer(remembered: false));
    expect(await store.load(), isEmpty);
  });

  test(
    'successful reconnect updates transport and time without changing scope',
    () {
      final original = peer();
      final when = DateTime.utc(2026, 9, 8, 9);
      final updated = original.connectedNow(transport: 'direct', at: when);
      expect(updated.routingId, original.routingId);
      expect(updated.workspaceIds, original.workspaceIds);
      expect(updated.operations, original.operations);
      expect(updated.lastTransport, 'direct');
      expect(updated.lastConnectedAt, when);
    },
  );

  test('forget removes only exact routing identity', () async {
    final values = <String, String>{};
    final store = HarnessRemotePeerStore(
      read: (key) async => values[key],
      write: (key, value) async {
        values[key] = value;
      },
    );
    await store.save(peer(routingId: '1234567890'));
    await store.save(peer(routingId: '1234567891'));
    await store.forget('1234567890');
    expect((await store.load()).single.routingId, '1234567891');
  });

  test('corrupt or duplicate history fails closed', () async {
    final duplicate = jsonEncode({
      'version': 1,
      'peers': [peer().toJson(), peer().toJson()],
    });
    final store = HarnessRemotePeerStore(
      read: (_) async => duplicate,
      write: (_, __) async {},
    );
    await expectLater(store.load(), throwsFormatException);
  });

  test(
    'v2 stores the approved public certificate and rejects pin mismatch',
    () async {
      final credentials = <String, String>{};
      final identity = await HarnessRemoteIdentityStore(
        read: (key) async => credentials[key],
        write: (key, value) async => credentials[key] = value,
      ).loadOrCreate();
      final values = <String, String>{};
      final store = HarnessRemotePeerStore(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      );
      final approved = HarnessRemotePeer(
        routingId: '1234567890',
        deviceId: identity.deviceId,
        certificateSha256: identity.fingerprint,
        certificatePem: identity.certificatePem,
        workspaceIds: const {'workspace'},
        operations: const {'session.history'},
        remembered: true,
        firstApprovedAt: DateTime.utc(2026, 9, 8, 1),
        lastConnectedAt: DateTime.utc(2026, 9, 8, 2),
        lastTransport: 'direct',
      );
      await store.save(approved);
      expect((await store.load()).single.connectionReady, isTrue);
      expect(jsonDecode(values.values.single)['version'], 2);

      expect(
        () => HarnessRemotePeer.fromJson({
          ...approved.toJson(),
          'certificateSha256': List.filled(64, '0').join(),
        }),
        throwsFormatException,
      );
    },
  );
}
