import 'dart:async';

enum AdbServerKind { local, rustDesk }

/// Describes the ADB server used by an adb client process.
///
/// The local endpoint preserves adb's default behaviour. A RustDesk endpoint
/// points at a loopback-only local TCP tunnel whose remote end is the selected
/// peer's ADB server.
class AdbServerEndpoint {
  const AdbServerEndpoint.local()
    : kind = AdbServerKind.local,
      host = '',
      port = 0,
      peerId = '',
      sessionId = '',
      leaseId = '';

  const AdbServerEndpoint._rustDesk({
    required this.host,
    required this.port,
    required this.peerId,
    required this.sessionId,
    required this.leaseId,
  }) : kind = AdbServerKind.rustDesk;

  factory AdbServerEndpoint.rustDesk({
    required String host,
    required int port,
    required String peerId,
    String sessionId = '',
    required String leaseId,
  }) {
    final String normalizedHost = host.trim().toLowerCase();
    if (normalizedHost != '127.0.0.1' && normalizedHost != 'localhost') {
      throw const FormatException('RustDesk ADB 隧道必须绑定本机回环地址');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('RustDesk ADB 隧道端口无效');
    }
    if (peerId.trim().isEmpty || leaseId.trim().isEmpty) {
      throw const FormatException('RustDesk ADB 隧道缺少设备或租约标识');
    }
    return AdbServerEndpoint._rustDesk(
      host: normalizedHost == 'localhost' ? '127.0.0.1' : normalizedHost,
      port: port,
      peerId: peerId.trim(),
      sessionId: sessionId.trim(),
      leaseId: leaseId.trim(),
    );
  }

  final AdbServerKind kind;
  final String host;
  final int port;
  final String peerId;
  final String sessionId;
  final String leaseId;

  bool get isRemote => kind == AdbServerKind.rustDesk;

  String get displayName => isRemote ? 'KEMI 远程办公 · $peerId' : '本机设备';

  List<String> applyTo(List<String> arguments) => isRemote
      ? <String>['-H', host, '-P', '$port', ...arguments]
      : List<String>.of(arguments);

  Map<String, Object?> toAuditFields() => <String, Object?>{
    'kind': kind.name,
    'displayName': displayName,
    if (isRemote) ...<String, Object?>{
      'host': host,
      'port': port,
      'peerId': peerId,
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
    },
  };
}

class AdbDeviceSource {
  const AdbDeviceSource({required this.endpoint});

  final AdbServerEndpoint endpoint;

  bool get remote => endpoint.isRemote;
  String get label => endpoint.displayName;
  String get peerId => endpoint.peerId;
  String get sessionId => endpoint.sessionId;
  String get leaseId => endpoint.leaseId;

  Map<String, Object?> toJson() => endpoint.toAuditFields();
}

/// Process-wide projection used by Harness tools and the interactive ADB UI.
///
/// The RustDesk lease remains owned by the ADB workspace/provider. Consumers
/// only borrow the endpoint while it is current and never close the lease.
abstract final class AdbServerEndpointHub {
  static final StreamController<AdbServerEndpoint> _changes =
      StreamController<AdbServerEndpoint>.broadcast(sync: true);
  static AdbServerEndpoint _latest = const AdbServerEndpoint.local();

  static AdbServerEndpoint get latest => _latest;
  static Stream<AdbServerEndpoint> get changes => _changes.stream;

  static void publish(AdbServerEndpoint endpoint) {
    _latest = endpoint;
    _changes.add(endpoint);
  }

  static void clearLease(String leaseId) {
    if (!_latest.isRemote || _latest.leaseId != leaseId) return;
    publish(const AdbServerEndpoint.local());
  }
}
