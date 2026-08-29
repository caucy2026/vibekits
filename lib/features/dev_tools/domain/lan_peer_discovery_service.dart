import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VibekitsLanPeer {
  const VibekitsLanPeer({
    required this.instanceId,
    required this.name,
    required this.address,
    required this.sshPort,
    required this.protocolVersion,
    required this.capabilityDigest,
    required this.lastSeen,
  });

  final String instanceId;
  final String name;
  final String address;
  final int sshPort;
  final int protocolVersion;
  final String capabilityDigest;
  final DateTime lastSeen;

  Map<String, Object?> toJson() => <String, Object?>{
    'instanceId': instanceId,
    'name': name,
    'address': address,
    'sshPort': sshPort,
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
    int sshPort = 22,
  }) async {
    if (_socket != null) return;
    _instanceId = _safe(instanceId, 80);
    _name = _safe(name, 80);
    _capabilityDigest = _safe(capabilityDigest, 128);
    if (_instanceId.isEmpty ||
        _name.isEmpty ||
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
        'kind': 'vibekits.mcp.peer',
        'version': protocolVersion,
        'instanceId': _instanceId,
        'name': _name,
        'sshPort': _sshPort,
        'capabilityDigest': _capabilityDigest,
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
        if (decoded is! Map || decoded['kind'] != 'vibekits.mcp.peer') continue;
        final String id = _safe('${decoded['instanceId'] ?? ''}', 80);
        final String name = _safe('${decoded['name'] ?? ''}', 80);
        final String digest = _safe(
          '${decoded['capabilityDigest'] ?? ''}',
          128,
        );
        final int remotePort = (decoded['sshPort'] as num?)?.toInt() ?? 0;
        if (id.isEmpty ||
            id == _instanceId ||
            name.isEmpty ||
            remotePort < 1 ||
            remotePort > 65535)
          continue;
        _peers[id] = VibekitsLanPeer(
          instanceId: id,
          name: name,
          address: packet.address.address,
          sshPort: remotePort,
          protocolVersion: (decoded['version'] as num?)?.toInt() ?? 0,
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
