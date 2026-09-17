import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'harness_remote_identity.dart';
import 'harness_remote_access_settings.dart';
import 'harness_remote_pairing.dart';
import 'harness_remote_peer_store.dart';
import 'rustdesk_harness_share_service.dart';

Future<String> _readBoundedLine(
  Socket socket, {
  int maxBytes = 256 * 1024,
  Duration timeout = const Duration(minutes: 2),
  bool keepListeningAfterLine = false,
  void Function()? onPeerClosed,
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
        if (!keepListeningAfterLine) unawaited(subscription.cancel());
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!done.isCompleted) done.completeError(error, stackTrace);
      onPeerClosed?.call();
    },
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(StateError('PAIRING_CHANNEL_CLOSED'));
      }
      onPeerClosed?.call();
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
/// pin persistence. A nonce-bound password proof rejects unauthorized pairing
/// before anything is shown to the operator; the password itself is never sent.
final class HarnessRemotePairingHost {
  HarnessRemotePairingHost({
    HarnessRemoteIdentityStore? identityStore,
    HarnessRemotePeerStore? peerStore,
    Future<String> Function()? passwordReader,
    int listenPort = port,
  }) : _identityStore = identityStore ?? HarnessRemoteIdentityStore.instance,
       _peerStore = peerStore ?? HarnessRemotePeerStore(),
       _passwordReader =
           passwordReader ?? HarnessRemoteAccessSettings().loadPassword,
       _listenPort = listenPort;

  static final instance = HarnessRemotePairingHost();
  static const port = 32145;
  final HarnessRemoteIdentityStore _identityStore;
  final HarnessRemotePeerStore _peerStore;
  final Future<String> Function() _passwordReader;
  final int _listenPort;
  final Map<String, HarnessRemotePendingPairing> _pending = {};
  final _changes =
      StreamController<List<HarnessRemotePendingPairing>>.broadcast();
  ServerSocket? _listener;
  StreamSubscription<Socket>? _subscription;
  int? get boundPort => _listener?.port;

  List<HarnessRemotePendingPairing> get pending =>
      List.unmodifiable(_pending.values);
  Stream<List<HarnessRemotePendingPairing>> get changes => _changes.stream;

  Future<void> start() async {
    if (_listener != null) return;
    final listener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      _listenPort,
      shared: false,
    );
    _listener = listener;
    _subscription = listener.listen(_accept);
  }

  /// Restores the execution-side carrier without depending on Harness model
  /// startup. This keeps first pairing available while the local workspace is
  /// still loading or has failed, and gives official/fallback UI one shared
  /// lifecycle implementation.
  Future<RustDeskHostInfo> ensureCarrierAvailable({
    String configuredExecutable = '',
  }) async {
    final RustDeskHostInfo ready =
        await RustDeskHarnessShareService.ensureHostAvailable(
          configuredExecutable: configuredExecutable,
        );
    if (!ready.callable || ready.executable.isEmpty) {
      throw StateError('REMOTE_CARRIER_NOT_REGISTERED');
    }
    await RustDeskHarnessShareService.setRemoteAssistanceAccess(
      ready.executable,
      enabled: true,
    );
    await start();
    return ready;
  }

  void _accept(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(() async {
      var peerClosed = false;
      var failureStage = 'FRAME';
      void withdrawClosedSocket() {
        peerClosed = true;
        String? nonce;
        HarnessRemotePendingPairing? removed;
        for (final entry in _pending.entries) {
          if (identical(entry.value._socket, socket)) {
            nonce = entry.key;
            removed = entry.value;
            break;
          }
        }
        if (nonce != null && removed != null) {
          _pending.remove(nonce);
          removed._timer.cancel();
          _publish();
        }
      }

      try {
        final decoded = jsonDecode(
          await _readBoundedLine(
            socket,
            keepListeningAfterLine: true,
            onPeerClosed: withdrawClosedSocket,
          ),
        );
        failureStage = 'ENVELOPE';
        if (decoded is! Map<String, dynamic> ||
            decoded['kind'] != 'pair-request' ||
            decoded['version'] != 1 ||
            _pending.length >= 8) {
          throw const FormatException('Invalid Harness pairing request');
        }
        failureStage = 'REQUEST';
        final request = HarnessRemotePairingRequest.fromJson(decoded);
        failureStage = 'PASSWORD';
        final password = await _passwordReader();
        if (!request.verifiesPassword(password)) {
          await _reply(socket, const {
            'kind': 'pair-rejected',
            'version': 1,
            'code': 'PAIRING_BAD_PASSWORD',
          });
          return;
        }
        failureStage = 'INTEGRITY';
        if (decoded['certificateSha256'] != request.certificateSha256 ||
            _pending.containsKey(request.nonce)) {
          throw const FormatException('Harness pairing request was modified');
        }
        failureStage = 'PENDING';
        if (peerClosed) throw StateError('PAIRING_CHANNEL_CLOSED');
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
      } on Object catch (error, stackTrace) {
        developer.log(
          'Rejected Harness pairing request: ${error.runtimeType}: $error',
          name: 'vibekits.harness.pairing',
          error: error,
          stackTrace: stackTrace,
        );
        await _reply(socket, {
          'kind': 'pair-rejected',
          'version': 1,
          'code': 'PAIRING_BAD_REQUEST_$failureStage',
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
    Future<void> Function()? beforeReply,
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
      // The controller opens the mTLS session as soon as it receives this
      // approval. Make the execution endpoint reload the newly pinned client
      // certificate before replying, otherwise the first real session races
      // the old listener and is disconnected during its restart.
      await beforeReply?.call();
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
    String password = HarnessRemoteAccessSettings.defaultPassword,
    Duration timeout = const Duration(minutes: 2),
    Future<void>? cancellation,
  }) async {
    final identity = await _identityStore.loadOrCreate();
    final request = HarnessRemotePairingRequest.create(
      routingId: localRoutingId,
      deviceId: identity.deviceId,
      certificatePem: identity.certificatePem,
      requestedWorkspaceIds: requestedWorkspaceIds,
      requestedOperations: requestedOperations,
      password: password,
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
      // The real request must be the demand connection that drives the
      // RustDesk port-forward login. Waiting for `transport_connected` before
      // writing leaves an empty TCP stream in the native login phase; some
      // relay paths close that stream as soon as they switch to raw forwarding,
      // so the pairing host only observes EOF (PAIRING_CHANNEL_CLOSED).
      final responseFuture = cancellation == null
          ? _readBoundedLine(socket, timeout: timeout)
          : Future.any<String>(<Future<String>>[
              _readBoundedLine(socket, timeout: timeout),
              cancellation.then<String>(
                (_) => throw StateError('PAIRING_CANCELLED'),
              ),
            ]);
      // Observe early remote failures while the native carrier is still
      // producing the more useful connection error below.
      unawaited(
        responseFuture.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
      socket.add(utf8.encode('${jsonEncode(request.toJson())}\n'));
      await socket.flush();
      await tunnel.waitUntilConnected(timeout: timeout);
      final responseLine = await responseFuture;
      final decoded = jsonDecode(responseLine);
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
