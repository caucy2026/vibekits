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
        message: '未连接KEMI远程办公',
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

/// Process-wide, non-blocking projection of the local KEMI remote-office link.
///
/// Finding or launching the compatible client never means "connected". Only a
/// validated protocol handshake followed by a fresh heartbeat may publish the
/// connected state. The native RustDesk/KEMI adapter calls [acceptHandshake]
/// and [acceptHeartbeat]; UI code only listens to [changes].
abstract final class RustDeskHarnessLinkStatusHub {
  static const String protocol = 'vibekits.harness.status';
  static const int supportedVersion = 1;
  static const Duration heartbeatTtl = Duration(seconds: 6);

  static final StreamController<RustDeskHarnessLinkSnapshot> _changes =
      StreamController<RustDeskHarnessLinkSnapshot>.broadcast(sync: true);
  static RustDeskHarnessLinkSnapshot _latest =
      RustDeskHarnessLinkSnapshot.disconnected();
  static Timer? _staleTimer;
  static String _activePeerId = '';

  static RustDeskHarnessLinkSnapshot get latest => _latest;
  static Stream<RustDeskHarnessLinkSnapshot> get changes => _changes.stream;

  static void clientFound() =>
      _publish(RustDeskHarnessLinkPhase.clientFound, '已找到KEMI远程办公，等待状态协议连接');

  static void handshaking() =>
      _publish(RustDeskHarnessLinkPhase.handshaking, '正在校验KEMI远程办公状态协议');

  static bool acceptHandshake(Map<String, Object?> hello) {
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
      _publish(RustDeskHarnessLinkPhase.incompatible, 'KEMI远程办公状态协议版本不兼容');
      return false;
    }
    _activePeerId = peer;
    _markConnected();
    return true;
  }

  static bool acceptHeartbeat({required String peerId, required int version}) {
    if (version != supportedVersion ||
        _activePeerId.isEmpty ||
        peerId != _activePeerId) {
      return false;
    }
    _markConnected();
    return true;
  }

  static void disconnected({String reason = ''}) {
    _staleTimer?.cancel();
    _activePeerId = '';
    _publish(
      RustDeskHarnessLinkPhase.disconnected,
      reason.trim().isEmpty ? '未连接KEMI远程办公' : _bounded(reason, 160),
    );
  }

  static void _markConnected() {
    _publish(
      RustDeskHarnessLinkPhase.connected,
      'KEMI远程办公已连接',
      protocolVersion: supportedVersion,
      peerId: _activePeerId,
    );
    _staleTimer?.cancel();
    _staleTimer = Timer(heartbeatTtl, () {
      if (_latest.phase != RustDeskHarnessLinkPhase.connected) return;
      _publish(
        RustDeskHarnessLinkPhase.stale,
        'KEMI远程办公心跳已超时',
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
