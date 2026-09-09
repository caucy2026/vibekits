import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/domain/harness_remote_connection.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_controller_session.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_peer_store.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

final class _Process implements RustDeskManagedProcess {
  final exit = Completer<int>();
  @override
  Future<int> get exitCode => exit.future;
  @override
  Future<void> waitUntilListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {}
  @override
  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {}
  @override
  bool terminate() {
    if (!exit.isCompleted) exit.complete(0);
    return true;
  }
}

final class _Channel implements HarnessRemoteChannel {
  _Channel(this.authenticatedPeerId);
  @override
  final String authenticatedPeerId;
  final controller = StreamController<String>();
  bool closed = false;
  @override
  Stream<String> get frames => controller.stream;

  @override
  Future<void> send(String frame) async {
    final request = jsonDecode(frame) as Map<String, dynamic>;
    final payload = request['payload'] as Map<String, dynamic>;
    final response = switch (payload['kind']) {
      'hello' => <String, Object?>{
        'ok': true,
        'protocol': 'vibekits.harness.remote',
        'version': 1,
        'connectionId': 'connection-1',
        'authenticatedControllerId': 'VH-CONTROLLER',
        'capabilities': const ['read-state', 'heartbeat'],
      },
      'heartbeat' => <String, Object?>{
        'ok': true,
        'connectionId': payload['connectionId'],
      },
      'read-state' => <String, Object?>{
        'ok': true,
        'live': true,
        'epoch': 'epoch-1',
        'sequence': 0,
        'workspaces': const [
          {
            'workspaceId': 'w1',
            'title': '远端项目',
            'sessionIds': ['s1'],
            'phase': 'ready',
          },
        ],
      },
      _ => <String, Object?>{'ok': false},
    };
    scheduleMicrotask(
      () => controller.add(
        jsonEncode({
          'protocol': 'vibekits.harness.remote',
          'version': 1,
          'type': 'response',
          'requestId': request['requestId'],
          'payload': response,
        }),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controller.close();
  }
}

void main() {
  test('已配对设备完成隧道、证书、hello、状态同步并统一关闭', () async {
    final credentials = <String, String>{};
    final identity = await HarnessRemoteIdentityStore(
      read: (key) async => credentials[key],
      write: (key, value) async => credentials[key] = value,
    ).loadOrCreate();
    final peer = HarnessRemotePeer(
      routingId: '1554650784',
      deviceId: identity.deviceId,
      certificateSha256: identity.fingerprint,
      certificatePem: identity.certificatePem,
      workspaceIds: const {'w1'},
      operations: const {'session.history'},
      remembered: true,
      firstApprovedAt: DateTime.utc(2026, 9, 8),
      lastConnectedAt: DateTime.utc(2026, 9, 8),
      lastTransport: 'relay',
    );
    final process = _Process();
    final channel = _Channel(peer.deviceId);
    List<Map<String, dynamic>> restored = const [];
    final session = await HarnessRemoteControllerSession.connect(
      executable: Platform.resolvedExecutable,
      peer: peer,
      identity: identity,
      forceRelay: true,
      tunnelLauncher: (_, arguments) async {
        expect(arguments.last, '--relay');
        return process;
      },
      channelConnector:
          ({
            required host,
            required port,
            required trustedPeerId,
            required trustedCertificateSha256,
            clientIdentity,
          }) async {
            expect(trustedPeerId, peer.deviceId);
            expect(trustedCertificateSha256, peer.certificateSha256);
            expect(clientIdentity, isNotNull);
            return channel;
          },
      applyOfficialEvents: (_) async {},
      restoreOfficialSnapshot: (rows) async => restored = rows,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(restored.single['title'], '远端项目');
    expect(session.model.stale, isFalse);
    await session.close();
    await session.close();
    expect(channel.closed, isTrue);
    expect(await process.exitCode, 0);
  });

  test('只有 routingId 和指纹的旧记录必须重新配对', () async {
    final credentials = <String, String>{};
    final identity = await HarnessRemoteIdentityStore(
      read: (key) async => credentials[key],
      write: (key, value) async => credentials[key] = value,
    ).loadOrCreate();
    final peer = HarnessRemotePeer(
      routingId: '1554650784',
      deviceId: 'VH-LEGACY',
      certificateSha256: List.filled(64, 'a').join(),
      workspaceIds: const {'w1'},
      operations: const {'session.history'},
      remembered: true,
      firstApprovedAt: DateTime.utc(2026, 9, 8),
      lastConnectedAt: DateTime.utc(2026, 9, 8),
      lastTransport: 'relay',
    );
    await expectLater(
      HarnessRemoteControllerSession.connect(
        executable: Platform.resolvedExecutable,
        peer: peer,
        identity: identity,
        applyOfficialEvents: (_) async {},
        restoreOfficialSnapshot: (_) async {},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'REMOTE_PAIRING_REQUIRED',
        ),
      ),
    );
  });
}
