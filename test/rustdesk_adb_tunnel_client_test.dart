import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_server_endpoint.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_adb_tunnel_client.dart';

void main() {
  test(
    'CLI adapter parses open response and closes the returned lease',
    () async {
      final List<List<String>> calls = <List<String>>[];
      final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
        processRunner: (String executable, List<String> arguments) async {
          calls.add(arguments);
          if (arguments.first == RustDeskCliAdbTunnelClient.openCommand) {
            return ProcessResult(
              1,
              0,
              '{"schemaVersion":1,"ok":true,"operation":"open",'
                  '"state":"ready","host":"127.0.0.1","port":15037,'
                  '"leaseId":"lease-1","peerId":"peer-1",'
                  '"sessionId":"123e4567-e89b-42d3-a456-426614174000"}',
              '',
            );
          }
          if (arguments.first == RustDeskCliAdbTunnelClient.statusCommand) {
            return ProcessResult(
              2,
              0,
              '{"schemaVersion":1,"ok":true,"operation":"status",'
                  '"state":"ready","host":"127.0.0.1",'
                  '"port":15037,"leaseId":"lease-1","peerId":"peer-1"}',
              '',
            );
          }
          if (arguments.first == RustDeskCliAdbTunnelClient.heartbeatCommand) {
            return ProcessResult(
              3,
              0,
              '{"schemaVersion":1,"ok":true,"operation":"heartbeat",'
                  '"state":"ready","host":"127.0.0.1",'
                  '"port":15037,"leaseId":"lease-1","peerId":"peer-1"}',
              '',
            );
          }
          return ProcessResult(
            2,
            0,
            '{"schemaVersion":1,"ok":true,"operation":"close"}',
            '',
          );
        },
      );

      final AdbServerEndpoint endpoint = await client.open(
        rustDeskExecutable: '/Applications/RustDesk',
        peerId: 'peer-1',
        sessionId: '123e4567-e89b-42d3-a456-426614174000',
      );
      await client.close(
        rustDeskExecutable: '/Applications/RustDesk',
        leaseId: endpoint.leaseId,
      );

      expect(endpoint.host, '127.0.0.1');
      expect(endpoint.port, 15037);
      expect(endpoint.peerId, 'peer-1');
      final RustDeskAdbTunnelStatus status = await client.status(
        rustDeskExecutable: '/Applications/RustDesk',
        leaseId: endpoint.leaseId,
      );
      expect(status.state, RustDeskAdbTunnelState.ready);
      final RustDeskAdbTunnelStatus heartbeat = await client.heartbeat(
        rustDeskExecutable: '/Applications/RustDesk',
        leaseId: endpoint.leaseId,
      );
      expect(heartbeat.state, RustDeskAdbTunnelState.ready);
      expect(calls, <List<String>>[
        <String>[
          '--vibekits-adb-tunnel-open',
          '--peer-id',
          'peer-1',
          '--session-id',
          '123e4567-e89b-42d3-a456-426614174000',
        ],
        <String>['--vibekits-adb-tunnel-close', '--lease-id', 'lease-1'],
        <String>['--vibekits-adb-tunnel-status', '--lease-id', 'lease-1'],
        <String>['--vibekits-adb-tunnel-heartbeat', '--lease-id', 'lease-1'],
      ]);
    },
  );

  test('provider closes an existing lease before replacing it', () async {
    final _FakeTunnelClient client = _FakeTunnelClient();
    final RustDeskAdbTunnelProvider provider = RustDeskAdbTunnelProvider(
      rustDeskExecutable: '/Applications/RustDesk',
      client: client,
    );

    await provider.open(peerId: 'peer-1');
    await provider.open(peerId: 'peer-2');
    await provider.dispose();

    expect(client.openedPeers, <String>['peer-1', 'peer-2']);
    expect(client.closedLeases, <String>['lease-peer-1', 'lease-peer-2']);
    expect(provider.endpoint, isNull);
  });

  test('adapter rejects non-loopback endpoints returned by RustDesk', () async {
    final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
      processRunner: (String executable, List<String> arguments) async =>
          ProcessResult(
            1,
            0,
            '{"schemaVersion":1,"ok":true,"operation":"open",'
                '"state":"ready","host":"10.0.0.2","port":5037,'
                '"leaseId":"lease-1","peerId":"peer-1"}',
            '',
          ),
    );

    await expectLater(
      client.open(rustDeskExecutable: '/RustDesk', peerId: 'peer-1'),
      throwsFormatException,
    );
  });

  test('adapter preserves structured error code on non-zero exit', () async {
    final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
      processRunner: (String executable, List<String> arguments) async =>
          ProcessResult(
            1,
            7,
            '{"schemaVersion":1,"ok":false,"operation":"open",'
                '"code":"peer_not_connected",'
                '"message":"No active authenticated session for peer"}',
            'diagnostic',
          ),
    );

    Object? error;
    try {
      await client.open(rustDeskExecutable: '/RustDesk', peerId: 'peer-1');
    } on Object catch (caught) {
      error = caught;
    }
    expect(error, isA<RustDeskAdbTunnelException>());
    final RustDeskAdbTunnelException tunnelError =
        error! as RustDeskAdbTunnelException;
    expect(tunnelError.code, 'peer_not_connected');
    expect(tunnelError.exitCode, 7);
  });

  test('adapter rejects incompatible error envelopes', () async {
    final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
      processRunner: (String executable, List<String> arguments) async =>
          ProcessResult(
            1,
            3,
            '{"schemaVersion":2,"ok":false,"operation":"status",'
                '"code":"peer_not_connected","message":"stale contract"}',
            '',
          ),
    );

    await expectLater(
      client.open(rustDeskExecutable: '/RustDesk', peerId: 'peer-1'),
      throwsA(
        isA<RustDeskAdbTunnelException>().having(
          (RustDeskAdbTunnelException error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('adapter rejects a non-UUID explicit RustDesk sessionId', () async {
    final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
      processRunner: (String executable, List<String> arguments) async =>
          throw StateError('must not start a process'),
    );

    await expectLater(
      client.open(
        rustDeskExecutable: '/RustDesk',
        peerId: 'peer-1',
        sessionId: 'session-1',
      ),
      throwsFormatException,
    );
  });

  test('adapter rejects incompatible success envelopes', () async {
    final RustDeskCliAdbTunnelClient client = RustDeskCliAdbTunnelClient(
      processRunner: (String executable, List<String> arguments) async =>
          ProcessResult(
            1,
            0,
            '{"schemaVersion":2,"ok":true,"operation":"open",'
                '"host":"127.0.0.1","port":15037,'
                '"leaseId":"lease-1","peerId":"peer-1"}',
            '',
          ),
    );

    await expectLater(
      client.open(rustDeskExecutable: '/RustDesk', peerId: 'peer-1'),
      throwsA(
        isA<RustDeskAdbTunnelException>().having(
          (RustDeskAdbTunnelException error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('provider keeps lease when close fails so caller can retry', () async {
    final _FakeTunnelClient client = _FakeTunnelClient()..failNextClose = true;
    final RustDeskAdbTunnelProvider provider = RustDeskAdbTunnelProvider(
      rustDeskExecutable: '/Applications/RustDesk',
      client: client,
    );
    await provider.open(peerId: 'peer-retry');

    await expectLater(provider.close(), throwsStateError);
    expect(provider.endpoint?.leaseId, 'lease-peer-retry');
    await provider.close();
    expect(provider.endpoint, isNull);
  });
}

class _FakeTunnelClient implements RustDeskAdbTunnelClient {
  final List<String> openedPeers = <String>[];
  final List<String> closedLeases = <String>[];
  bool failNextClose = false;

  @override
  Future<AdbServerEndpoint> open({
    required String rustDeskExecutable,
    required String peerId,
    String sessionId = '',
  }) async {
    openedPeers.add(peerId);
    return AdbServerEndpoint.rustDesk(
      host: '127.0.0.1',
      port: 15037,
      peerId: peerId,
      sessionId: sessionId,
      leaseId: 'lease-$peerId',
    );
  }

  @override
  Future<void> close({
    required String rustDeskExecutable,
    required String leaseId,
  }) async {
    if (failNextClose) {
      failNextClose = false;
      throw StateError('close failed');
    }
    closedLeases.add(leaseId);
  }

  @override
  Future<RustDeskAdbTunnelStatus> status({
    required String rustDeskExecutable,
    required String leaseId,
  }) async => RustDeskAdbTunnelStatus(
    state: RustDeskAdbTunnelState.ready,
    leaseId: leaseId,
    peerId: leaseId.replaceFirst('lease-', ''),
    host: '127.0.0.1',
    port: 15037,
  );

  @override
  Future<RustDeskAdbTunnelStatus> heartbeat({
    required String rustDeskExecutable,
    required String leaseId,
  }) => status(rustDeskExecutable: rustDeskExecutable, leaseId: leaseId);
}
