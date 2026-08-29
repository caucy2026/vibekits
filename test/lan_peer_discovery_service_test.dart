import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';

void main() {
  test('同机两个实例通过组播互相发现且默认未授权', () async {
    final int port = 48000 + pid % 1000;
    final LanPeerDiscoveryService first = LanPeerDiscoveryService(port: port);
    final LanPeerDiscoveryService second = LanPeerDiscoveryService(port: port);
    addTearDown(first.stop);
    addTearDown(second.stop);

    await first.start(
      instanceId: 'peer-a',
      name: 'VibeKits-A',
      capabilityDigest: 'digest-a',
    );
    await second.start(
      instanceId: 'peer-b',
      name: 'VibeKits-B',
      capabilityDigest: 'digest-b',
    );
    await Future<void>.delayed(const Duration(seconds: 5));

    expect(
      first.peers.any((VibekitsLanPeer peer) => peer.instanceId == 'peer-b'),
      isTrue,
    );
    expect(
      second.peers.any((VibekitsLanPeer peer) => peer.instanceId == 'peer-a'),
      isTrue,
    );
    expect(first.peers.first.toJson()['authorized'], isFalse);
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));
}
