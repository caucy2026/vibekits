import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VibekitsLanPeer {
  const VibekitsLanPeer({
    required this.instanceId,
    required this.name,
    required this.appId,
    required this.appVersion,
    required this.address,
    required this.sshPort,
    required this.transport,
    required this.protocolVersion,
    required this.capabilityDigest,
    required this.lastSeen,
  });

  final String instanceId;
  final String name;
  final String appId;
  final String appVersion;
  final String address;
  final int sshPort;
  final String transport;
  final int protocolVersion;
  final String capabilityDigest;
  final DateTime lastSeen;

  Map<String, Object?> toJson() => <String, Object?>{
    'instanceId': instanceId,
    'name': name,
    'appId': appId,
    'appVersion': appVersion,
    'address': address,
    'sshPort': sshPort,
    'transport': transport,
    'protocolVersion': protocolVersion,
    'capabilityDigest': capabilityDigest,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'authorized': false,
    'nextAction': '在主机端核对SSH host key并批准该设备公钥后才能调用',
  };
}

class LanPeerDiscoveryService {
  LanPeerDiscoveryService({
    this.port = 47831,
    InternetAddress? group,
    Duration? peerTtl,
  }) : group = group ?? InternetAddress('239.255.42.99'),
       peerTtl = peerTtl ?? const Duration(seconds: 12);

  static final LanPeerDiscoveryService instance = LanPeerDiscoveryService();
  static const String discoveryProtocol = 'lmcp-discovery';
  static const int protocolVersion = 1;

  final int port;
  final InternetAddress group;
  final Duration peerTtl;
  final Map<String, VibekitsLanPeer> _peers = <String, VibekitsLanPeer>{};
  final StreamController<List<VibekitsLanPeer>> _changes =
      StreamController<List<VibekitsLanPeer>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  String _instanceId = '';
  String _name = '';
  String _appId = '';
  String _appVersion = '';
  String _capabilityDigest = '';
  int _sshPort = 22;

  Stream<List<VibekitsLanPeer>> get changes => _changes.stream;
  bool get running => _socket != null;

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
    int sshPort = 22,
  }) async {
    if (_socket != null) return;
    _instanceId = _safe(instanceId, 80);
    _name = _safe(name, 80);
    _appId = _safe(appId, 120);
    _appVersion = _safe(appVersion, 40);
    _capabilityDigest = _safe(capabilityDigest, 128);
    if (_instanceId.isEmpty ||
        _name.isEmpty ||
        _appId.isEmpty ||
        _appVersion.isEmpty ||
        sshPort < 1 ||
        sshPort > 65535) {
      throw const FormatException('局域网节点发现参数无效');
    }
    _sshPort = sshPort;
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    socket.joinMulticast(group);
    socket.listen(_onEvent, onError: (_) => stop());
    _socket = socket;
    _announce();
    _announceTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _announce(),
    );
    _pruneTimer = Timer.periodic(const Duration(seconds: 4), (_) => _prune());
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _announceTimer = null;
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
    _emit();
  }

  void _announce() {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;
    final List<int> payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'protocol': discoveryProtocol,
        'protocolVersion': '1.0',
        'messageType': 'announce',
        'instanceId': _instanceId,
        'app': <String, Object?>{
          'id': _appId,
          'name': _name,
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
          'pairingRequired': true,
          'authMethods': <String>['ssh-ed25519'],
          'controlApproval': 'per-tool',
        },
        'ttlSeconds': peerTtl.inSeconds,
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (payload.length <= 1024) socket.send(payload, group, port);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final Datagram packet = datagram!;
      if (!_privateIpv4(packet.address.address) || packet.data.length > 1024)
        continue;
      try {
        final Object? decoded = jsonDecode(utf8.decode(packet.data));
        if (decoded is! Map) continue;
        final bool legacy = decoded['kind'] == 'vibekits.mcp.peer';
        if (!legacy &&
            (decoded['protocol'] != discoveryProtocol ||
                decoded['messageType'] != 'announce')) {
          continue;
        }
        final Map<Object?, Object?> app = decoded['app'] is Map
            ? decoded['app'] as Map<Object?, Object?>
            : const <Object?, Object?>{};
        final Map<Object?, Object?> endpoint = decoded['endpoint'] is Map
            ? decoded['endpoint'] as Map<Object?, Object?>
            : const <Object?, Object?>{};
        final Map<Object?, Object?> mcp = decoded['mcp'] is Map
            ? decoded['mcp'] as Map<Object?, Object?>
            : const <Object?, Object?>{};
        final String id = _safe('${decoded['instanceId'] ?? ''}', 80);
        final String name = _safe(
          '${legacy ? decoded['name'] : app['name'] ?? ''}',
          80,
        );
        final String digest = _safe(
          '${legacy ? decoded['capabilityDigest'] : mcp['capabilityDigest'] ?? ''}',
          128,
        );
        final int remotePort = legacy
            ? (decoded['sshPort'] as num?)?.toInt() ?? 0
            : (endpoint['port'] as num?)?.toInt() ?? 0;
        final String transport = _safe(
          '${legacy ? 'ssh-stdio' : endpoint['transport'] ?? ''}',
          32,
        );
        if (id.isEmpty ||
            id == _instanceId ||
            name.isEmpty ||
            transport != 'ssh-stdio' ||
            remotePort < 1 ||
            remotePort > 65535)
          continue;
        _peers[id] = VibekitsLanPeer(
          instanceId: id,
          name: name,
          appId: _safe(
            '${legacy ? 'com.vibekits.desktop' : app['id'] ?? ''}',
            120,
          ),
          appVersion: _safe('${legacy ? '' : app['version'] ?? ''}', 40),
          address: packet.address.address,
          sshPort: remotePort,
          transport: transport,
          protocolVersion: legacy
              ? (decoded['version'] as num?)?.toInt() ?? 0
              : int.tryParse(
                      '${decoded['protocolVersion']}'.split('.').first,
                    ) ??
                    0,
          capabilityDigest: digest,
          lastSeen: DateTime.now(),
        );
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
}
