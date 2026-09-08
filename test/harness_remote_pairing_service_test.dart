import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_pairing.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_pairing_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_peer_store.dart';

void main() {
  test('回环配对服务等待明确批准后才返回证书并持久化', () async {
    final identityValues = <String, String>{};
    final peerValues = <String, String>{};
    final identityStore = HarnessRemoteIdentityStore(
      read: (key) async => identityValues[key],
      write: (key, value) async => identityValues[key] = value,
    );
    final peerStore = HarnessRemotePeerStore(
      read: (key) async => peerValues[key],
      write: (key, value) async => peerValues[key] = value,
    );
    final host = HarnessRemotePairingHost(
      identityStore: identityStore,
      peerStore: peerStore,
    );
    await host.start();
    addTearDown(host.stop);
    final controllerValues = <String, String>{};
    final controller = await HarnessRemoteIdentityStore(
      read: (key) async => controllerValues[key],
      write: (key, value) async => controllerValues[key] = value,
    ).loadOrCreate();
    final request = HarnessRemotePairingRequest(
      routingId: '1554650784',
      deviceId: controller.deviceId,
      certificatePem: controller.certificatePem,
      nonce: List.filled(48, 'c').join(),
      requestedWorkspaceIds: const {'w1'},
      requestedOperations: const {'session.history'},
    );
    final socket = await Socket.connect('127.0.0.1', 32145);
    socket.write('${jsonEncode(request.toJson())}\n');
    await socket.flush();
    await host.changes.firstWhere((rows) => rows.isNotEmpty);
    expect(host.pending.single.request.routingId, '1554650784');
    await host.approve(
      nonce: request.nonce,
      hostRoutingId: '2602628020',
      grantedWorkspaceIds: const {'w1'},
      grantedOperations: const {'session.history'},
    );
    final responseLine = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final response = jsonDecode(responseLine) as Map<String, dynamic>;
    final approval = HarnessRemotePairingApproval.fromJson(request, response);
    expect(approval.comparisonCode, matches(RegExp(r'^\d{6}$')));
    expect((await peerStore.load()).single.connectionReady, true);
    await socket.close();
  });
}
