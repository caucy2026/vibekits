import 'dart:convert';
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
      name: 'Future-App',
      capabilityDigest: 'digest-b',
      appId: 'com.example.future-app',
      appVersion: '2.3.0',
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
    final VibekitsLanPeer futureApp = first.peers.firstWhere(
      (VibekitsLanPeer peer) => peer.instanceId == 'peer-b',
    );
    expect(futureApp.appId, 'com.example.future-app');
    expect(futureApp.appVersion, '2.3.0');
    expect(futureApp.transport, 'ssh-stdio');
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('开放协议JSON Schema可被解析且要求配对', () {
    final File schema = File(
      '${Directory.current.path}${Platform.pathSeparator}docs'
      '${Platform.pathSeparator}schemas${Platform.pathSeparator}'
      'lmcp-discovery-1.0.schema.json',
    );
    expect(schema.existsSync(), isTrue);
    final String content = schema.readAsStringSync();
    expect(jsonDecode(content), isA<Map<String, dynamic>>());
    expect(content, contains('lmcp-discovery'));
    expect(content, contains('pairingRequired'));
    expect(content, contains('ssh-ed25519'));
  });
}
