import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_capability_models.dart';

class Lmcp2Advertisement {
  const Lmcp2Advertisement({
    required this.appId,
    required this.appVersion,
    required this.displayName,
    required this.instanceId,
    required this.hardwareCode,
    required this.port,
    required this.path,
    required this.instanceKeyFingerprint,
    required this.catalogRevision,
    required this.capabilityDigest,
  });

  final String appId;
  final String appVersion;
  final String displayName;
  final String instanceId;
  final String hardwareCode;
  final int port;
  final String path;
  final String instanceKeyFingerprint;
  final String catalogRevision;
  final String capabilityDigest;

  Map<String, Object?> toAnnouncement({
    String messageType = 'announce',
    int ttlSeconds = 12,
    DateTime? sentAt,
  }) {
    final String timestamp = (sentAt ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final Map<String, Object?> goodbye = <String, Object?>{
      'protocol': LanPeerDiscoveryService.discoveryProtocol,
      'protocolVersion': '2.0',
      'messageType': messageType,
      'instanceId': instanceId,
      'sentAt': timestamp,
    };
    if (messageType == 'goodbye') return goodbye;
    final Object revision = int.tryParse(catalogRevision) ?? catalogRevision;
    final Map<String, Object?> endpoint = <String, Object?>{
      'transport': 'https-streamable-http',
      'port': port,
      'path': path,
      'instanceKeyFingerprint': instanceKeyFingerprint,
      'protocolVersions': const <String>['2025-06-18'],
      'catalogRevision': revision,
      'capabilityDigest': capabilityDigest,
    };
    String appName = displayName.split('@').first;
    String host = displayName.contains('@')
        ? displayName.substring(displayName.indexOf('@') + 1)
        : 'device-$hardwareCode';
    final String suffix = '-$hardwareCode';
    if (host.endsWith(suffix)) {
      host = host.substring(0, host.length - suffix.length);
    }
    host = host.isEmpty ? 'device' : host;
    Map<String, Object?> build() => <String, Object?>{
      ...goodbye,
      'hardwareCode': hardwareCode,
      'app': <String, Object?>{
        'id': appId,
        'name': appName,
        'displayName': '$appName@$host$suffix',
        'version': appVersion,
      },
      'catalogEndpoint': endpoint,
      'callEndpoint': <String, Object?>{
        ...endpoint,
        'serviceRole': 'tool-provider',
      },
      'mcp': <String, Object?>{
        'protocolVersions': const <String>['2025-06-18'],
        'catalogRevision': revision,
        'capabilityDigest': capabilityDigest,
        'changeNotifications': false,
      },
      'ttlSeconds': ttlSeconds,
    };

    Map<String, Object?> result = build();
    while (utf8.encode(jsonEncode(result)).length > 1200 && host.length > 1) {
      host = String.fromCharCodes(host.runes.toList()..removeLast());
      result = build();
    }
    while (utf8.encode(jsonEncode(result)).length > 1200 &&
        appName.length > 1) {
      appName = String.fromCharCodes(appName.runes.toList()..removeLast());
      result = build();
    }
    return result;
  }
}

class VibekitsLanPeer {
  const VibekitsLanPeer({
    required this.instanceId,
    required this.name,
    required this.appId,
    required this.appVersion,
    required this.address,
    required this.port,
    required this.transport,
    required this.protocolVersion,
    required this.capabilityDigest,
    required this.lastSeen,
    this.hardwareCode = '',
    this.catalogPath = '',
    this.callPath = '',
    this.instanceKeyFingerprint = '',
    this.catalogRevision = '',
    this.serviceRole = '',
    this.tools = const <McpToolInterface>[],
  });

  final String instanceId;
  final String name;
  final String appId;
  final String appVersion;
  final String address;
  final int port;
  final String transport;
  final int protocolVersion;
  final String capabilityDigest;
  final DateTime lastSeen;
  final String hardwareCode;
  final String catalogPath;
  final String callPath;
  final String instanceKeyFingerprint;
  final String catalogRevision;
  final String serviceRole;
  final List<McpToolInterface> tools;

  bool get supportsLmcp2Calls =>
      protocolVersion == 2 &&
      transport == 'https-streamable-http' &&
      catalogPath.startsWith('/') &&
      callPath.startsWith('/') &&
      RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(instanceKeyFingerprint) &&
      RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(capabilityDigest) &&
      catalogRevision.isNotEmpty &&
      (serviceRole == 'tool-provider' || serviceRole == 'harness-controller');

  Uri get catalogUri => Uri(
    scheme: transport == 'https-streamable-http' ? 'https' : 'ssh',
    host: address,
    port: port,
    path: catalogPath.isEmpty ? null : catalogPath,
  );

  Uri get callUri => Uri(
    scheme: transport == 'https-streamable-http' ? 'https' : 'ssh',
    host: address,
    port: port,
    path: callPath.isEmpty ? null : callPath,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'instanceId': instanceId,
    'name': name,
    'appId': appId,
    'appVersion': appVersion,
    'address': address,
    'port': port,
    'transport': transport,
    'protocolVersion': protocolVersion,
    'capabilityDigest': capabilityDigest,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'hardwareCode': hardwareCode,
    'catalogPath': catalogPath,
    'callPath': callPath,
    'instanceKeyFingerprint': instanceKeyFingerprint,
    'catalogRevision': catalogRevision,
    'serviceRole': serviceRole,
    'tools': <Map<String, Object?>>[
      for (final McpToolInterface tool in tools) tool.toJson(),
    ],
    'authorized': true,
    'nextAction': '普通 MCP 工具可自动读取目录并调用；远程 Harness 任务入口另行审批',
  };
}

class LanPeerDiscoveryService {
  LanPeerDiscoveryService({
    this.port = 47831,
    InternetAddress? group,
    Duration? peerTtl,
    bool? reusePort,
  }) : group = group ?? InternetAddress('239.255.42.99'),
       peerTtl = peerTtl ?? const Duration(seconds: 12),
       reusePort = reusePort ?? !Platform.isWindows;

  static final LanPeerDiscoveryService instance = LanPeerDiscoveryService();
  static const String discoveryProtocol = 'lmcp-discovery';
  static const int protocolVersion = 1;
  static const int _ipMulticastInterfaceOption = 9;

  final int port;
  final InternetAddress group;
  final Duration peerTtl;

  /// macOS/BSD require SO_REUSEPORT in addition to SO_REUSEADDR when several
  /// independent APPs listen on the shared LMCP discovery port.
  final bool reusePort;
  final Map<String, VibekitsLanPeer> _peers = <String, VibekitsLanPeer>{};
  final StreamController<List<VibekitsLanPeer>> _changes =
      StreamController<List<VibekitsLanPeer>>.broadcast();
  RawDatagramSocket? _socket;
  List<NetworkInterface> _interfaces = const <NetworkInterface>[];
  Timer? _announceTimer;
  Timer? _pruneTimer;
  String _instanceId = '';
  String _name = '';
  String _appId = '';
  String _appVersion = '';
  String _capabilityDigest = '';
  String _hardwareCode = '';
  int _sshPort = 22;
  bool _exposureEnabled = true;
  Lmcp2Advertisement? _lmcp2Advertisement;

  Stream<List<VibekitsLanPeer>> get changes => _changes.stream;
  bool get running => _socket != null;
  bool get exposureEnabled => _exposureEnabled;
  Lmcp2Advertisement? get lmcp2Advertisement => _lmcp2Advertisement;

  List<VibekitsLanPeer> get peers {
    final List<VibekitsLanPeer> result = _peers.values.toList()
      ..sort(
        (VibekitsLanPeer a, VibekitsLanPeer b) => a.name.compareTo(b.name),
      );
    return List<VibekitsLanPeer>.unmodifiable(result);
  }

  Future<void> start({
    required String instanceId,
    required String name,
    required String capabilityDigest,
    String appId = 'com.vibekits.desktop',
    String appVersion = '1.9.0',
    bool exposureEnabled = true,
    String hardwareCode = '',
    int sshPort = 22,
  }) async {
    if (_socket != null) return;
    _instanceId = _safe(instanceId, 80);
    _name = _safe(name, 80);
    _appId = _safe(appId, 120);
    _appVersion = _safe(appVersion, 40);
    _capabilityDigest = _safe(capabilityDigest, 128);
    _hardwareCode = _safe(hardwareCode, 32);
    if (sshPort < 1 || sshPort > 65535) {
      throw const FormatException('局域网节点 SSH 端口无效');
    }
    _sshPort = sshPort;
    if (_instanceId.isEmpty ||
        _name.isEmpty ||
        _appId.isEmpty ||
        _appVersion.isEmpty) {
      throw const FormatException('局域网节点发现参数无效');
    }
    _exposureEnabled = exposureEnabled;
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: reusePort,
    );
    final List<NetworkInterface> interfaces = await _privateIpv4Interfaces();
    final List<NetworkInterface> joined = <NetworkInterface>[];
    for (final NetworkInterface interface in interfaces) {
      try {
        socket.joinMulticast(group, interface);
        joined.add(interface);
      } on Object {
        // A disappearing interface must not prevent other interfaces working.
      }
    }
    if (joined.isEmpty) socket.joinMulticast(group);
    socket.multicastLoopback = true;
    socket.multicastHops = 1;
    socket.listen(_onEvent, onError: (_) => stop());
    _socket = socket;
    _interfaces = List<NetworkInterface>.unmodifiable(joined);
    if (_exposureEnabled) _announce();
    _announceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_exposureEnabled) _announce();
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 4), (_) => _prune());
  }

  Future<void> setExposureEnabled(bool enabled) async {
    if (_exposureEnabled == enabled) return;
    if (!enabled) {
      _announce(messageType: 'goodbye');
      _exposureEnabled = false;
      return;
    }
    _exposureEnabled = true;
    _announce();
  }

  void configureLmcp2Advertisement(Lmcp2Advertisement? advertisement) {
    _lmcp2Advertisement = advertisement;
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _announceTimer = null;
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _interfaces = const <NetworkInterface>[];
    _peers.clear();
    _emit();
  }

  void _announce({String messageType = 'announce'}) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;
    final Lmcp2Advertisement? lmcp2 = _lmcp2Advertisement;
    final List<int> payload = utf8.encode(
      jsonEncode(
        lmcp2?.toAnnouncement(
              messageType: messageType,
              ttlSeconds: peerTtl.inSeconds,
            ) ??
            <String, Object?>{
              'protocol': discoveryProtocol,
              'protocolVersion': '1.0',
              'messageType': messageType,
              'instanceId': _instanceId,
              'hardwareCode': _hardwareCode,
              'app': <String, Object?>{
                'id': _appId,
                'name': _name.split('@').first,
                'displayName': _name,
                'version': _appVersion,
              },
              'endpoint': <String, Object?>{
                'transport': 'ssh-stdio',
                'port': _sshPort,
              },
              'mcp': <String, Object?>{
                'protocolVersions': <String>['2025-06-18'],
                'capabilityDigest': _capabilityDigest,
              },
              'security': <String, Object?>{
                'pairingRequired': false,
                'authMethods': <String>['ssh-ed25519'],
                'controlApproval': 'remote-harness-only',
              },
              'ttlSeconds': peerTtl.inSeconds,
              'sentAt': DateTime.now().toUtc().toIso8601String(),
            },
      ),
    );
    if (payload.length > 1200) return;
    bool sent = false;
    for (final NetworkInterface interface in _interfaces) {
      final Set<String> eligible = eligiblePrivateIpv4Addresses(
        interface.addresses.map((InternetAddress address) => address.address),
      ).toSet();
      for (final InternetAddress address in interface.addresses) {
        if (!eligible.contains(address.address)) continue;
        try {
          socket.setRawOption(
            RawSocketOption(
              RawSocketOption.levelIPv4,
              _ipMulticastInterfaceOption,
              address.rawAddress,
            ),
          );
          socket.send(payload, group, port);
          sent = true;
        } on Object {
          // Continue with the remaining private interfaces.
        }
      }
    }
    if (!sent) socket.send(payload, group, port);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final Datagram packet = datagram!;
      if (!_privateIpv4(packet.address.address) || packet.data.length > 1200) {
        continue;
      }
      try {
        final Object? decoded = jsonDecode(utf8.decode(packet.data));
        if (decoded is! Map) continue;
        final String id = _safe('${decoded['instanceId'] ?? ''}', 80);
        if (decoded['messageType'] == 'goodbye') {
          if (id.isNotEmpty) {
            _peers.remove(id);
            _emit();
          }
          continue;
        }
        final VibekitsLanPeer? peer = decodePeerAnnouncement(
          decoded: decoded,
          sourceAddress: packet.address.address,
          ownInstanceId: _instanceId,
          receivedAt: DateTime.now(),
        );
        if (peer == null) continue;
        _peers[peer.instanceId] = peer;
        _emit();
      } on Object {
        // Untrusted discovery packets are ignored.
      }
    }
  }

  void _prune() {
    final DateTime cutoff = DateTime.now().subtract(peerTtl);
    _peers.removeWhere(
      (_, VibekitsLanPeer peer) => peer.lastSeen.isBefore(cutoff),
    );
    _emit();
  }

  void _emit() => _changes.add(peers);

  static String _safe(String value, int max) {
    final String clean = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    return clean.length <= max ? clean : clean.substring(0, max);
  }

  static bool _privateIpv4(String value) {
    final List<String> parts = value.split('.');
    if (parts.length != 4) return false;
    final List<int> bytes = <int>[];
    for (final String part in parts) {
      final int? parsed = int.tryParse(part);
      if (parsed == null || parsed < 0 || parsed > 255) return false;
      bytes.add(parsed);
    }
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static Future<List<NetworkInterface>> _privateIpv4Interfaces() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    return interfaces
        .where(
          (NetworkInterface interface) => eligiblePrivateIpv4Addresses(
            interface.addresses.map(
              (InternetAddress address) => address.address,
            ),
          ).isNotEmpty,
        )
        .toList(growable: false);
  }

  /// Pure selection helper used by the production multi-interface path and
  /// deterministic tests. Every returned address receives its own multicast
  /// send after the containing interface has joined the group.
  static List<String> eligiblePrivateIpv4Addresses(Iterable<String> values) =>
      values.where(_privateIpv4).toSet().toList(growable: false);

  /// Decodes both the retained LMCP/1 format and the current LMCP/2 format.
  /// The source address is supplied by UDP and is never trusted from JSON.
  static VibekitsLanPeer? decodePeerAnnouncement({
    required Map<Object?, Object?> decoded,
    required String sourceAddress,
    String ownInstanceId = '',
    DateTime? receivedAt,
  }) {
    if (!_privateIpv4(sourceAddress)) return null;
    final bool legacy = decoded['kind'] == 'vibekits.mcp.peer';
    if (!legacy &&
        (decoded['protocol'] != discoveryProtocol ||
            decoded['messageType'] != 'announce')) {
      return null;
    }
    final int major = legacy
        ? (decoded['version'] as num?)?.toInt() ?? 0
        : int.tryParse('${decoded['protocolVersion']}'.split('.').first) ?? 0;
    if (!legacy && major != 1 && major != 2) return null;
    final String id = _safe('${decoded['instanceId'] ?? ''}', 80);
    if (id.isEmpty || id == ownInstanceId) return null;

    final Map<Object?, Object?> app = decoded['app'] is Map
        ? decoded['app'] as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final Map<Object?, Object?> mcp = decoded['mcp'] is Map
        ? decoded['mcp'] as Map<Object?, Object?>
        : const <Object?, Object?>{};
    if (major == 2) {
      final String appId = _safe('${app['id'] ?? ''}', 120);
      final String hardwareCode = _safe('${decoded['hardwareCode'] ?? ''}', 32);
      final String sentAt = '${decoded['sentAt'] ?? ''}';
      final String identityPrefix = '$appId:$hardwareCode';
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,119}$').hasMatch(appId) ||
          !RegExp(r'^[A-F0-9]{10}$').hasMatch(hardwareCode) ||
          (id != identityPrefix && !id.startsWith('$identityPrefix:')) ||
          (decoded['ttlSeconds'] as num?)?.toInt() != 12 ||
          !sentAt.endsWith('Z') ||
          DateTime.tryParse(sentAt) == null ||
          mcp['changeNotifications'] is! bool) {
        return null;
      }
    }
    final Map<Object?, Object?> catalogEndpoint = major == 2
        ? (decoded['catalogEndpoint'] is Map
              ? decoded['catalogEndpoint'] as Map<Object?, Object?>
              : const <Object?, Object?>{})
        : (decoded['endpoint'] is Map
              ? decoded['endpoint'] as Map<Object?, Object?>
              : const <Object?, Object?>{});
    final Map<Object?, Object?> callEndpoint = major == 2
        ? (decoded['callEndpoint'] is Map
              ? decoded['callEndpoint'] as Map<Object?, Object?>
              : const <Object?, Object?>{})
        : catalogEndpoint;
    final String transport = _safe(
      '${legacy ? 'ssh-stdio' : catalogEndpoint['transport'] ?? ''}',
      32,
    );
    if (major == 1 && transport != 'ssh-stdio') return null;
    if (major == 2 && transport != 'https-streamable-http') return null;
    if (major == 2 && callEndpoint['transport'] != transport) return null;

    final int remotePort = legacy
        ? (catalogEndpoint['port'] as num?)?.toInt() ??
              (decoded['sshPort'] as num?)?.toInt() ??
              0
        : (catalogEndpoint['port'] as num?)?.toInt() ?? 0;
    final int callPort = major == 2
        ? (callEndpoint['port'] as num?)?.toInt() ?? 0
        : remotePort;
    if (remotePort < 1 || remotePort > 65535 || callPort != remotePort) {
      return null;
    }
    final String catalogPath = major == 2
        ? _safePath('${catalogEndpoint['path'] ?? ''}')
        : '';
    final String callPath = major == 2
        ? _safePath('${callEndpoint['path'] ?? ''}')
        : '';
    final String fingerprint = major == 2
        ? _safe(
            '${catalogEndpoint['instanceKeyFingerprint'] ?? ''}',
            80,
          ).toLowerCase()
        : '';
    final String callFingerprint = major == 2
        ? _safe(
            '${callEndpoint['instanceKeyFingerprint'] ?? ''}',
            80,
          ).toLowerCase()
        : '';
    final String serviceRole = major == 2
        ? _safe('${callEndpoint['serviceRole'] ?? ''}', 32)
        : '';
    if (major == 2 &&
        (catalogPath != '/mcp' ||
            callPath != '/mcp' ||
            !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(fingerprint) ||
            callFingerprint != fingerprint ||
            (serviceRole != 'tool-provider' &&
                serviceRole != 'harness-controller'))) {
      return null;
    }
    final String name = _safe(
      '${legacy ? decoded['name'] : app['displayName'] ?? app['name'] ?? ''}',
      80,
    );
    if (name.isEmpty) return null;
    final Object? rawTools = mcp['tools'];
    final List<McpToolInterface> tools = rawTools is List
        ? <McpToolInterface>[
            for (final Object? item in rawTools)
              if (item is Map)
                McpToolInterface.fromJson(Map<Object?, Object?>.from(item)),
          ].where((McpToolInterface tool) => tool.name.isNotEmpty).toList()
        : const <McpToolInterface>[];
    final String digest = _safe(
      '${legacy ? decoded['capabilityDigest'] : mcp['capabilityDigest'] ?? catalogEndpoint['capabilityDigest'] ?? ''}',
      128,
    );
    final String catalogRevision = major == 2
        ? _safe(
            '${mcp['catalogRevision'] ?? catalogEndpoint['catalogRevision'] ?? ''}',
            80,
          )
        : digest;
    if (major == 2) {
      final String catalogDigest = _safe(
        '${catalogEndpoint['capabilityDigest'] ?? ''}',
        128,
      ).toLowerCase();
      final String callDigest = _safe(
        '${callEndpoint['capabilityDigest'] ?? ''}',
        128,
      ).toLowerCase();
      final String catalogEndpointRevision = _safe(
        '${catalogEndpoint['catalogRevision'] ?? ''}',
        80,
      );
      final String callEndpointRevision = _safe(
        '${callEndpoint['catalogRevision'] ?? ''}',
        80,
      );
      final Set<String> mcpVersions = _stringSet(mcp['protocolVersions']);
      final Set<String> catalogVersions = _stringSet(
        catalogEndpoint['protocolVersions'],
      );
      final Set<String> callVersions = _stringSet(
        callEndpoint['protocolVersions'],
      );
      if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest.toLowerCase()) ||
          catalogDigest != digest.toLowerCase() ||
          callDigest != digest.toLowerCase() ||
          catalogPath != callPath ||
          catalogRevision.isEmpty ||
          catalogEndpointRevision != catalogRevision ||
          callEndpointRevision != catalogRevision ||
          !mcpVersions.contains('2025-06-18') ||
          mcpVersions.length != catalogVersions.length ||
          !mcpVersions.containsAll(catalogVersions) ||
          mcpVersions.length != callVersions.length ||
          !mcpVersions.containsAll(callVersions)) {
        return null;
      }
    }
    return VibekitsLanPeer(
      instanceId: id,
      name: name,
      appId: _safe('${legacy ? 'com.vibekits.desktop' : app['id'] ?? ''}', 120),
      appVersion: _safe('${legacy ? '' : app['version'] ?? ''}', 40),
      address: sourceAddress,
      port: remotePort,
      transport: transport,
      protocolVersion: major,
      capabilityDigest: digest,
      lastSeen: receivedAt ?? DateTime.now(),
      hardwareCode: _safe('${decoded['hardwareCode'] ?? ''}', 32),
      catalogPath: catalogPath,
      callPath: callPath,
      instanceKeyFingerprint: fingerprint,
      catalogRevision: catalogRevision,
      serviceRole: serviceRole,
      tools: List<McpToolInterface>.unmodifiable(tools),
    );
  }

  static String _safePath(String value) {
    final String path = _safe(value, 256);
    if (!path.startsWith('/') || path.contains('..') || path.contains('?')) {
      return '';
    }
    return path;
  }

  static Set<String> _stringSet(Object? value) =>
      value is List ? value.whereType<String>().toSet() : const <String>{};
}
