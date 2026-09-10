import 'dart:async';

enum RustDeskHarnessLinkPhase {
  disconnected,
  clientFound,
  handshaking,
  connected,
  stale,
  incompatible,
}

class RustDeskHarnessLinkSnapshot {
  const RustDeskHarnessLinkSnapshot({
    required this.phase,
    required this.message,
    required this.updatedAt,
    this.protocolVersion = 0,
    this.peerId = '',
  });

  factory RustDeskHarnessLinkSnapshot.disconnected() =>
      RustDeskHarnessLinkSnapshot(
        phase: RustDeskHarnessLinkPhase.disconnected,
        message: '未连接远程 Harness',
        updatedAt: DateTime.now(),
      );

  final RustDeskHarnessLinkPhase phase;
  final String message;
  final DateTime updatedAt;
  final int protocolVersion;
  final String peerId;

  bool get connected => phase == RustDeskHarnessLinkPhase.connected;
  bool get waiting =>
      phase == RustDeskHarnessLinkPhase.clientFound ||
      phase == RustDeskHarnessLinkPhase.handshaking;
}

/// Process-wide, non-blocking projection of the VibeKits message channel.
///
/// Finding or launching the embedded carrier never means "connected". Only a
/// validated protocol handshake followed by a fresh heartbeat may publish the
/// connected state. The source-built RustDesk carrier calls [acceptHandshake]
/// and [acceptHeartbeat]; UI code only listens to [changes]. No desktop pixels
/// or remote-control input are part of this state machine.
abstract final class RustDeskHarnessLinkStatusHub {
  static const String protocol = 'vibekits.harness.status';
  static const int supportedVersion = 1;
  static const Duration minimumHeartbeatTtl = Duration(seconds: 6);

  static final StreamController<RustDeskHarnessLinkSnapshot> _changes =
      StreamController<RustDeskHarnessLinkSnapshot>.broadcast(sync: true);
  static RustDeskHarnessLinkSnapshot _latest =
      RustDeskHarnessLinkSnapshot.disconnected();
  static Timer? _staleTimer;
  static String _activePeerId = '';
  static String _remoteDataPeerId = '';

  static RustDeskHarnessLinkSnapshot get latest => _latest;
  static Stream<RustDeskHarnessLinkSnapshot> get changes => _changes.stream;

  static void clientFound() {
    if (_remoteDataPeerId.isNotEmpty) return;
    _publish(RustDeskHarnessLinkPhase.clientFound, 'VibeKits 内置 P2P/中继引擎已就绪');
  }

  static void handshaking() =>
      _publish(RustDeskHarnessLinkPhase.handshaking, '正在校验 Harness 消息协议');

  /// The authenticated VibeKits remote-data protocol is live inside the
  /// RustDesk byte tunnel. This is distinct from remote desktop state.
  static void remoteDataConnected(String peerId) {
    _remoteDataPeerId = _bounded(peerId, 80);
    _activePeerId = _remoteDataPeerId;
    _markConnected(const Duration(seconds: 5));
  }

  static void remoteDataHeartbeat(String peerId) {
    if (_remoteDataPeerId != peerId || peerId.isEmpty) return;
    _activePeerId = peerId;
    _markConnected(const Duration(seconds: 5));
  }

  static void remoteDataDisconnected(String peerId) {
    if (_remoteDataPeerId != peerId) return;
    _remoteDataPeerId = '';
    disconnected(reason: '远程 Harness 数据通道已断开');
  }

  static bool acceptHandshake(Map<String, Object?> hello) {
    if (_remoteDataPeerId.isNotEmpty) return true;
    handshaking();
    final String peer = _bounded(hello['peerId']?.toString() ?? '', 80);
    final String remoteProtocol = hello['protocol']?.toString() ?? '';
    final Iterable<int> versions = switch (hello['versions']) {
      final List<Object?> values => values.map(
        (Object? value) => int.tryParse(value.toString()) ?? -1,
      ),
      _ => const <int>[],
    };
    if (remoteProtocol != protocol || !versions.contains(supportedVersion)) {
      _activePeerId = '';
      _publish(RustDeskHarnessLinkPhase.incompatible, 'Harness 消息协议版本不兼容');
      return false;
    }
    _activePeerId = peer;
    _publish(
      RustDeskHarnessLinkPhase.handshaking,
      '状态协议已校验，等待远端订阅',
      protocolVersion: supportedVersion,
      peerId: _activePeerId,
    );
    return true;
  }

  static bool acceptSubscription({
    required String peerId,
    required int version,
    required Duration heartbeatInterval,
  }) {
    if (!_matchesActivePeer(peerId: peerId, version: version)) return false;
    _markConnected(heartbeatInterval);
    return true;
  }

  static bool acceptHeartbeat({
    required String peerId,
    required int version,
    Duration heartbeatInterval = const Duration(seconds: 2),
  }) {
    if (!_matchesActivePeer(peerId: peerId, version: version)) return false;
    _markConnected(heartbeatInterval);
    return true;
  }

  static bool _matchesActivePeer({
    required String peerId,
    required int version,
  }) {
    if (version != supportedVersion ||
        _activePeerId.isEmpty ||
        peerId != _activePeerId) {
      return false;
    }
    return true;
  }

  static void disconnected({String reason = ''}) {
    if (_remoteDataPeerId.isNotEmpty && reason.contains('状态订阅')) return;
    _staleTimer?.cancel();
    _remoteDataPeerId = '';
    _activePeerId = '';
    _publish(
      RustDeskHarnessLinkPhase.disconnected,
      reason.trim().isEmpty ? '未连接远程 Harness' : _bounded(reason, 160),
    );
  }

  static void _markConnected(Duration heartbeatInterval) {
    _publish(
      RustDeskHarnessLinkPhase.connected,
      '远程 Harness 消息通道已连接',
      protocolVersion: supportedVersion,
      peerId: _activePeerId,
    );
    _staleTimer?.cancel();
    final Duration proposedTtl = heartbeatInterval * 3;
    final Duration ttl = proposedTtl > minimumHeartbeatTtl
        ? proposedTtl
        : minimumHeartbeatTtl;
    _staleTimer = Timer(ttl, () {
      if (_latest.phase != RustDeskHarnessLinkPhase.connected) return;
      _publish(
        RustDeskHarnessLinkPhase.stale,
        '远程 Harness 心跳已超时',
        protocolVersion: supportedVersion,
        peerId: _activePeerId,
      );
    });
  }

  static void _publish(
    RustDeskHarnessLinkPhase phase,
    String message, {
    int protocolVersion = 0,
    String peerId = '',
  }) {
    _latest = RustDeskHarnessLinkSnapshot(
      phase: phase,
      message: _bounded(message, 160),
      updatedAt: DateTime.now(),
      protocolVersion: protocolVersion,
      peerId: _bounded(peerId, 80),
    );
    _changes.add(_latest);
  }

  static String _bounded(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
