import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness_remote_identity.dart';
import 'harness_remote_pairing.dart';
import 'harness_remote_peer_store.dart';
import 'rustdesk_harness_share_service.dart';

Future<String> _readBoundedLine(
  Socket socket, {
  int maxBytes = 256 * 1024,
  Duration timeout = const Duration(minutes: 2),
}) {
  final done = Completer<String>();
  final bytes = <int>[];
  late StreamSubscription<List<int>> subscription;
  subscription = socket.listen(
    (chunk) {
      if (done.isCompleted) return;
      final newline = chunk.indexOf(10);
      bytes.addAll(newline < 0 ? chunk : chunk.take(newline));
      if (bytes.length > maxBytes) {
        done.completeError(const FormatException('Pairing frame too large'));
        unawaited(subscription.cancel());
      } else if (newline >= 0) {
        try {
          done.complete(utf8.decode(bytes));
        } on Object catch (error, stack) {
          done.completeError(error, stack);
        }
        unawaited(subscription.cancel());
      }
    },
    onError: done.completeError,
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(StateError('PAIRING_CHANNEL_CLOSED'));
      }
    },
  );
  return done.future.timeout(
    timeout,
    onTimeout: () {
      unawaited(subscription.cancel());
      throw TimeoutException('PAIRING_APPROVAL_TIMEOUT', timeout);
    },
  );
}

final class HarnessRemotePendingPairing {
  HarnessRemotePendingPairing._(this.request, this._socket, this._timer);
  final HarnessRemotePairingRequest request;
  final Socket _socket;
  final Timer _timer;
}

/// Execution-side, loopback-only first-pair endpoint. Native RustDesk approval
/// is the outer gate; this endpoint adds explicit app approval and certificate
/// pin persistence. It never uses a product-wide or default password.
final class HarnessRemotePairingHost {
  HarnessRemotePairingHost({
    HarnessRemoteIdentityStore? identityStore,
    HarnessRemotePeerStore? peerStore,
  }) : _identityStore = identityStore ?? HarnessRemoteIdentityStore.instance,
       _peerStore = peerStore ?? HarnessRemotePeerStore();

  static final instance = HarnessRemotePairingHost();
  static const port = 32145;
  final HarnessRemoteIdentityStore _identityStore;
  final HarnessRemotePeerStore _peerStore;
  final Map<String, HarnessRemotePendingPairing> _pending = {};
  final _changes =
      StreamController<List<HarnessRemotePendingPairing>>.broadcast();
  ServerSocket? _listener;
  StreamSubscription<Socket>? _subscription;

  List<HarnessRemotePendingPairing> get pending =>
      List.unmodifiable(_pending.values);
  Stream<List<HarnessRemotePendingPairing>> get changes => _changes.stream;

  Future<void> start() async {
    if (_listener != null) return;
    final listener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _listener = listener;
    _subscription = listener.listen(_accept);
  }

  void _accept(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(() async {
      try {
        final decoded = jsonDecode(await _readBoundedLine(socket));
        if (decoded is! Map<String, dynamic> ||
            decoded['kind'] != 'pair-request' ||
            decoded['version'] != 1 ||
            _pending.length >= 8) {
          throw const FormatException('Invalid Harness pairing request');
        }
        final request = HarnessRemotePairingRequest.fromJson(decoded);
        if (decoded['certificateSha256'] != request.certificateSha256 ||
            _pending.containsKey(request.nonce)) {
          throw const FormatException('Harness pairing request was modified');
        }
        late final Timer timer;
        timer = Timer(const Duration(minutes: 2), () {
          final removed = _pending.remove(request.nonce);
          if (removed != null) {
            _reply(removed._socket, const {
              'kind': 'pair-rejected',
              'version': 1,
              'code': 'PAIRING_APPROVAL_TIMEOUT',
            });
            _publish();
          }
        });
        _pending[request.nonce] = HarnessRemotePendingPairing._(
          request,
          socket,
          timer,
        );
        _publish();
      } on Object {
        await _reply(socket, const {
          'kind': 'pair-rejected',
          'version': 1,
          'code': 'PAIRING_BAD_REQUEST',
        });
      }
    }());
  }

  Future<HarnessRemotePairingApproval> approve({
    required String nonce,
    required String hostRoutingId,
    required Set<String> grantedWorkspaceIds,
    required Set<String> grantedOperations,
    bool remember = true,
  }) async {
    final pending = _pending.remove(nonce);
    if (pending == null) throw StateError('PAIRING_REQUEST_NOT_FOUND');
    pending._timer.cancel();
    try {
      final identity = await _identityStore.loadOrCreate();
      final approval = HarnessRemotePairingApproval(
        request: pending.request,
        hostRoutingId: hostRoutingId,
        hostDeviceId: identity.deviceId,
        hostCertificatePem: identity.certificatePem,
        grantedWorkspaceIds: grantedWorkspaceIds,
        grantedOperations: grantedOperations,
        approvedAt: DateTime.now().toUtc(),
      );
      await _peerStore.save(approval.hostRecord(remembered: remember));
      await _reply(pending._socket, approval.toJson());
      return approval;
    } finally {
      _publish();
    }
  }

  Future<void> reject(String nonce) async {
    final pending = _pending.remove(nonce);
    if (pending == null) return;
    pending._timer.cancel();
    await _reply(pending._socket, const {
      'kind': 'pair-rejected',
      'version': 1,
      'code': 'PAIRING_REJECTED',
    });
    _publish();
  }

  Future<void> _reply(Socket socket, Map<String, Object?> payload) async {
    try {
      socket.add(utf8.encode('${jsonEncode(payload)}\n'));
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  void _publish() => _changes.add(pending);

  Future<void> stop() async {
    await _subscription?.cancel();
    await _listener?.close();
    _subscription = null;
    _listener = null;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final item in pending) {
      item._timer.cancel();
      await _reply(item._socket, const {
        'kind': 'pair-rejected',
        'version': 1,
        'code': 'PAIRING_HOST_STOPPED',
      });
    }
    _publish();
  }
}

final class HarnessRemotePairingClient {
  HarnessRemotePairingClient({
    HarnessRemoteIdentityStore? identityStore,
    HarnessRemotePeerStore? peerStore,
  }) : _identityStore = identityStore ?? HarnessRemoteIdentityStore.instance,
       _peerStore = peerStore ?? HarnessRemotePeerStore();

  final HarnessRemoteIdentityStore _identityStore;
  final HarnessRemotePeerStore _peerStore;

  Future<HarnessRemotePairingApproval> pair({
    required String executable,
    required String localRoutingId,
    required String remoteRoutingId,
    required Set<String> requestedWorkspaceIds,
    required Set<String> requestedOperations,
    bool forceRelay = false,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final identity = await _identityStore.loadOrCreate();
    final request = HarnessRemotePairingRequest.create(
      routingId: localRoutingId,
      deviceId: identity.deviceId,
      certificatePem: identity.certificatePem,
      requestedWorkspaceIds: requestedWorkspaceIds,
      requestedOperations: requestedOperations,
    );
    final localPort = await RustDeskHarnessShareService.allocateTunnelPort();
    final tunnel = await RustDeskHarnessShareService.openTunnel(
      executable,
      routingId: remoteRoutingId,
      localPort: localPort,
      remotePort: HarnessRemotePairingHost.port,
      forceRelay: forceRelay,
    );
    Socket? socket;
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (socket == null && DateTime.now().isBefore(deadline)) {
        try {
          socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            localPort,
            timeout: const Duration(seconds: 1),
          );
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      if (socket == null) throw StateError('PAIRING_TUNNEL_UNAVAILABLE');
      socket.add(utf8.encode('${jsonEncode(request.toJson())}\n'));
      await socket.flush();
      final decoded = jsonDecode(
        await _readBoundedLine(socket, timeout: timeout),
      );
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid Harness pairing response');
      }
      if (decoded['kind'] == 'pair-rejected') {
        throw StateError(decoded['code']?.toString() ?? 'PAIRING_REJECTED');
      }
      final approval = HarnessRemotePairingApproval.fromJson(request, decoded);
      if (approval.hostRoutingId != remoteRoutingId) {
        throw const FormatException('Harness pairing routing ID mismatch');
      }
      await _peerStore.save(approval.controllerRecord(remembered: true));
      return approval;
    } finally {
      await socket?.close();
      await tunnel.close();
    }
  }
}
