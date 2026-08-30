import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';

void main() {
  test('同机两个实例通过组播互相发现且普通 MCP 默认可调用', () async {
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
    expect(first.peers.first.toJson()['authorized'], isTrue);
    final VibekitsLanPeer futureApp = first.peers.firstWhere(
      (VibekitsLanPeer peer) => peer.instanceId == 'peer-b',
    );
    expect(futureApp.appId, 'com.example.future-app');
    expect(futureApp.appVersion, '2.3.0');
    expect(futureApp.transport, 'ssh-stdio');
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('历史 LMCP/1 JSON Schema 仍可被解析', () {
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

  test('关闭 MCP 暴露后 goodbye 让其他节点立即移除设备', () async {
    final int port = 49000 + pid % 1000;
    final LanPeerDiscoveryService observer = LanPeerDiscoveryService(
      port: port,
    );
    final LanPeerDiscoveryService provider = LanPeerDiscoveryService(
      port: port,
    );
    addTearDown(observer.stop);
    addTearDown(provider.stop);
    await observer.start(
      instanceId: 'observer',
      name: 'Observer@host-1111111111',
      capabilityDigest: 'observer',
      exposureEnabled: false,
    );
    await provider.start(
      instanceId: 'provider',
      name: 'Provider@host-2222222222',
      capabilityDigest: 'provider',
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(
      observer.peers.any(
        (VibekitsLanPeer peer) => peer.instanceId == 'provider',
      ),
      isTrue,
    );

    provider.setExposureEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      observer.peers.any(
        (VibekitsLanPeer peer) => peer.instanceId == 'provider',
      ),
      isFalse,
    );
    expect(observer.running, isTrue, reason: '关闭对外 MCP 不能关闭发现器');
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));
}
