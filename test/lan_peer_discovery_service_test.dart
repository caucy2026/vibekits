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
    expect(futureApp.port, 22);
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('LMCP/2 跨实例公告通过共享端口被另一个 VibeKits 接收', () async {
    final int port = 50000 + pid % 500;
    final LanPeerDiscoveryService observer = LanPeerDiscoveryService(
      port: port,
    );
    final LanPeerDiscoveryService provider = LanPeerDiscoveryService(
      port: port,
    );
    addTearDown(observer.stop);
    addTearDown(provider.stop);
    await observer.start(
      instanceId: 'com.vibekits.desktop:1111111111',
      name: 'VibeKits@observer-1111111111',
      capabilityDigest: 'observer',
      exposureEnabled: false,
    );
    await provider.start(
      instanceId: 'com.vibekits.desktop:2222222222',
      name: 'VibeKits@provider-2222222222',
      capabilityDigest: 'provider',
      exposureEnabled: false,
    );
    final Lmcp2Advertisement advertisement = Lmcp2Advertisement(
      appId: 'com.vibekits.desktop',
      appVersion: '1.9.0-dev.137',
      displayName: 'VibeKits@provider-2222222222',
      instanceId: 'com.vibekits.desktop:2222222222',
      hardwareCode: '2222222222',
      port: 9443,
      path: '/mcp',
      instanceKeyFingerprint: 'sha256:${List<String>.filled(64, 'a').join()}',
      catalogRevision: '2137',
      capabilityDigest: 'sha256:${List<String>.filled(64, 'b').join()}',
    );
    final Map<String, Object?> encoded = advertisement.toAnnouncement();
    expect(utf8.encode(jsonEncode(encoded)).length, lessThanOrEqualTo(1200));
    expect(
      LanPeerDiscoveryService.decodePeerAnnouncement(
        decoded: encoded,
        sourceAddress: '192.168.3.65',
      ),
      isNotNull,
    );
    provider.configureLmcp2Advertisement(advertisement);
    provider.setExposureEnabled(true);

    for (int attempt = 0; attempt < 25 && observer.peers.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final VibekitsLanPeer peer = observer.peers.singleWhere(
      (VibekitsLanPeer item) =>
          item.instanceId == 'com.vibekits.desktop:2222222222',
    );
    expect(peer.supportsLmcp2Calls, isTrue);
    expect(peer.catalogUri.scheme, 'https');
    expect(peer.catalogUri.port, 9443);
    expect(peer.catalogUri.path, '/mcp');
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('多网卡筛选保留每个 RFC1918 IPv4 地址并排除公网和回环', () {
    expect(
      LanPeerDiscoveryService.eligiblePrivateIpv4Addresses(<String>[
        '192.168.3.65',
        '10.20.30.40',
        '172.31.5.9',
        '192.168.3.65',
        '172.32.0.1',
        '127.0.0.1',
        '169.254.1.1',
        '8.8.8.8',
      ]),
      <String>['192.168.3.65', '10.20.30.40', '172.31.5.9'],
    );
  });

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

  test('KEMI传书 LMCP/2 公告可解析为固定指纹 HTTPS 端点', () {
    final String digest = 'sha256:${List<String>.filled(64, '9').join()}';
    final String fingerprint = 'sha256:${List<String>.filled(64, '1').join()}';
    final VibekitsLanPeer? peer =
        LanPeerDiscoveryService.decodePeerAnnouncement(
          decoded: <Object?, Object?>{
            'protocol': 'lmcp-discovery',
            'protocolVersion': '2.0',
            'messageType': 'announce',
            'instanceId': 'org.kemi.send:E16497473C',
            'hardwareCode': 'E16497473C',
            'sentAt': '2026-08-30T12:00:00Z',
            'app': <String, Object?>{
              'id': 'org.kemi.send',
              'name': 'KEMI传书',
              'displayName': 'KEMI传书@newlinkdeMac-mini-E16497473C',
              'version': '2.0.5',
            },
            'catalogEndpoint': <String, Object?>{
              'transport': 'https-streamable-http',
              'port': 9443,
              'path': '/mcp',
              'instanceKeyFingerprint': fingerprint,
              'protocolVersions': <String>['2025-06-18'],
              'catalogRevision': '2',
              'capabilityDigest': digest,
            },
            'callEndpoint': <String, Object?>{
              'transport': 'https-streamable-http',
              'port': 9443,
              'path': '/mcp',
              'instanceKeyFingerprint': fingerprint,
              'protocolVersions': <String>['2025-06-18'],
              'catalogRevision': '2',
              'capabilityDigest': digest,
              'serviceRole': 'tool-provider',
            },
            'mcp': <String, Object?>{
              'protocolVersions': <String>['2025-06-18'],
              'catalogRevision': '2',
              'capabilityDigest': digest,
              'changeNotifications': false,
            },
            'ttlSeconds': 12,
          },
          sourceAddress: '192.168.3.65',
          ownInstanceId: 'com.vibekits.desktop:824F9994A8',
        );

    expect(peer, isNotNull);
    expect(peer!.protocolVersion, 2);
    expect(peer.transport, 'https-streamable-http');
    expect(peer.catalogUri, Uri.parse('https://192.168.3.65:9443/mcp'));
    expect(peer.callUri, Uri.parse('https://192.168.3.65:9443/mcp'));
    expect(peer.instanceKeyFingerprint, fingerprint);
    expect(peer.catalogRevision, '2');
    expect(peer.serviceRole, 'tool-provider');
    expect(peer.capabilityDigest, digest);
    expect(peer.supportsLmcp2Calls, isTrue);
  });

  test('LMCP/2 公告的证书指纹或调用端点不一致时拒绝', () {
    final String fingerprint = 'sha256:${List<String>.filled(64, 'a').join()}';
    final Map<Object?, Object?> announcement = <Object?, Object?>{
      'protocol': 'lmcp-discovery',
      'protocolVersion': '2.0',
      'messageType': 'announce',
      'instanceId': 'org.kemi.send:AAAAAAAAAA',
      'app': <String, Object?>{
        'id': 'org.kemi.send',
        'displayName': 'KEMI传书@host-AAAAAAAAAA',
        'version': '2.0.5',
      },
      'catalogEndpoint': <String, Object?>{
        'transport': 'https-streamable-http',
        'port': 9443,
        'path': '/mcp',
        'instanceKeyFingerprint': fingerprint,
        'protocolVersions': <String>['2025-06-18'],
        'catalogRevision': '2',
        'capabilityDigest': 'sha256:${List<String>.filled(64, 'c').join()}',
      },
      'callEndpoint': <String, Object?>{
        'transport': 'https-streamable-http',
        'port': 9443,
        'path': '/mcp',
        'instanceKeyFingerprint':
            'sha256:${List<String>.filled(64, 'b').join()}',
        'protocolVersions': <String>['2025-06-18'],
        'catalogRevision': '2',
        'capabilityDigest': 'sha256:${List<String>.filled(64, 'c').join()}',
        'serviceRole': 'tool-provider',
      },
      'mcp': <String, Object?>{
        'protocolVersions': <String>['2025-06-18'],
        'catalogRevision': '2',
        'capabilityDigest': 'sha256:${List<String>.filled(64, 'c').join()}',
      },
    };

    expect(
      LanPeerDiscoveryService.decodePeerAnnouncement(
        decoded: announcement,
        sourceAddress: '192.168.3.65',
      ),
      isNull,
    );
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

    await provider.setExposureEnabled(false);
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
