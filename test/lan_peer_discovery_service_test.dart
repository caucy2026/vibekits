import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/lan_peer_discovery_service.dart';
import 'package:vibekits/features/dev_tools/domain/mcp_capability_models.dart';

void main() {
  test('同一实例并发 start 只绑定一个 UDP socket', () async {
    int bindCount = 0;
    final LanPeerDiscoveryService service = LanPeerDiscoveryService(
      socketFactory: () async {
        bindCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      },
    );
    addTearDown(service.stop);

    await Future.wait(<Future<void>>[
      service.start(
        instanceId: 'com.vibekits.desktop:1111111111',
        name: 'VibeKits@single-flight-1111111111',
        capabilityDigest: 'first',
        exposureEnabled: false,
      ),
      service.start(
        instanceId: 'com.vibekits.desktop:1111111111',
        name: 'VibeKits@single-flight-1111111111',
        capabilityDigest: 'second',
        exposureEnabled: false,
      ),
    ]);

    expect(bindCount, 1);
    expect(service.running, isTrue);
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('未配置 LMCP/2 HTTPS 端点时不再回退发送 LMCP/1', () async {
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

    expect(first.peers, isEmpty);
    expect(second.peers, isEmpty);
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
      runtimeProvider: () => const McpNodeRuntime(
        state: McpNodeState.idle,
        capacity: 4,
        inFlight: 0,
        queueDepth: 0,
        availableSlots: 4,
        loadRevision: 7,
        oldestTaskAgeMs: 0,
        draining: false,
        acceptingReservations: true,
      ).toJson(),
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
    expect(peer.runtime.state, McpNodeState.idle);
    expect(peer.runtime.availableSlots, 4);
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  test('提供方先运行后启动的观察者仍会收到周期公告', () async {
    final int port = 50500 + pid % 400;
    final LanPeerDiscoveryService provider = LanPeerDiscoveryService(
      port: port,
    );
    final LanPeerDiscoveryService lateObserver = LanPeerDiscoveryService(
      port: port,
    );
    addTearDown(provider.stop);
    addTearDown(lateObserver.stop);
    await provider.start(
      instanceId: 'com.example.provider:3333333333',
      name: 'Provider@early-3333333333',
      capabilityDigest: 'provider',
      exposureEnabled: false,
    );
    provider.configureLmcp2Advertisement(
      Lmcp2Advertisement(
        appId: 'com.example.provider',
        appVersion: '1.0.0',
        displayName: 'Provider@early-3333333333',
        instanceId: 'com.example.provider:3333333333',
        hardwareCode: '3333333333',
        port: 9443,
        path: '/mcp',
        instanceKeyFingerprint: 'sha256:${List<String>.filled(64, 'c').join()}',
        catalogRevision: '1',
        capabilityDigest: 'sha256:${List<String>.filled(64, 'd').join()}',
      ),
    );
    provider.setExposureEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 4200));

    await lateObserver.start(
      instanceId: 'com.vibekits.desktop:4444444444',
      name: 'VibeKits@late-4444444444',
      capabilityDigest: 'observer',
      exposureEnabled: false,
    );
    for (
      int attempt = 0;
      attempt < 25 && lateObserver.peers.isEmpty;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(
      lateObserver.peers.map((VibekitsLanPeer peer) => peer.instanceId),
      contains('com.example.provider:3333333333'),
    );
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

  test('历史 LMCP/1 公告只发现且明确不可调用', () {
    final VibekitsLanPeer? peer =
        LanPeerDiscoveryService.decodePeerAnnouncement(
          decoded: <Object?, Object?>{
            'protocol': 'lmcp-discovery',
            'protocolVersion': '1.0',
            'messageType': 'announce',
            'instanceId': 'legacy-vibekits',
            'app': <String, Object?>{
              'id': 'com.vibekits.desktop',
              'displayName': 'Legacy VibeKits',
              'version': '1.9.0-dev.137',
            },
            'endpoint': <String, Object?>{'transport': 'ssh-stdio', 'port': 22},
            'mcp': <String, Object?>{'capabilityDigest': 'legacy'},
          },
          sourceAddress: '192.168.3.58',
        );

    expect(peer, isNotNull);
    expect(peer!.supportsLmcp2Calls, isFalse);
    expect(peer.toJson()['authorized'], isFalse);
    expect(peer.toJson()['nextAction'], contains('仅发现、不可调用'));
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
      instanceId: 'com.example.provider:2222222222',
      name: 'Provider@host-2222222222',
      capabilityDigest: 'provider',
      exposureEnabled: false,
    );
    provider.configureLmcp2Advertisement(
      Lmcp2Advertisement(
        appId: 'com.example.provider',
        appVersion: '1.0.0',
        displayName: 'Provider@host-2222222222',
        instanceId: 'com.example.provider:2222222222',
        hardwareCode: '2222222222',
        port: 9443,
        path: '/mcp',
        instanceKeyFingerprint: 'sha256:${List<String>.filled(64, 'a').join()}',
        catalogRevision: '1',
        capabilityDigest: 'sha256:${List<String>.filled(64, 'b').join()}',
      ),
    );
    await provider.setExposureEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(
      observer.peers.any(
        (VibekitsLanPeer peer) =>
            peer.instanceId == 'com.example.provider:2222222222',
      ),
      isTrue,
    );

    await provider.setExposureEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      observer.peers.any(
        (VibekitsLanPeer peer) =>
            peer.instanceId == 'com.example.provider:2222222222',
      ),
      isFalse,
    );
    expect(observer.running, isTrue, reason: '关闭对外 MCP 不能关闭发现器');
  }, skip: !(Platform.isWindows || Platform.isMacOS || Platform.isLinux));
}
