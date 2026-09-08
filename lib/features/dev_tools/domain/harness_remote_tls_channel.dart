import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'harness_remote_connection.dart';

/// End-to-end carrier for either LAN or a native RustDesk byte tunnel.
/// Pinning is mandatory even if the system CA trusts the presented certificate.
/// The trusted fingerprint must come from first-pairing approval, not discovery.
class HarnessRemoteTlsChannel implements HarnessRemoteChannel {
  HarnessRemoteTlsChannel._(this._socket, this.authenticatedPeerId) {
    _subscription = _socket.listen(
      _accept,
      onError: (Object error, StackTrace stack) {
        if (!_closed) _frames.addError(error, stack);
        unawaited(close());
      },
      onDone: () {
        unawaited(close());
      },
    );
    _frames.onPause = () => _subscription.pause();
    _frames.onResume = () => _subscription.resume();
  }

  /// Only use with SecureServerSocket(requireClientCertificate: true).
  /// A signed but unapproved client certificate still has no access.
  static HarnessRemoteTlsChannel accept(
    SecureSocket socket,
    Map<String, String> approvedCertificatePeers,
  ) {
    final certificate = socket.peerCertificate;
    final fingerprint = certificate == null
        ? ''
        : sha256.convert(certificate.der).toString();
    final peerId = approvedCertificatePeers[fingerprint];
    if (peerId == null || peerId.isEmpty) {
      socket.destroy();
      throw const HandshakeException('Unapproved Harness client certificate');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    return HarnessRemoteTlsChannel._(socket, peerId);
  }

  static Future<HarnessRemoteTlsChannel> connect({
    required String host,
    required int port,
    required String trustedPeerId,
    required String trustedCertificateSha256,
    SecurityContext? clientIdentity,
  }) async {
    if (trustedPeerId.isEmpty ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(trustedCertificateSha256)) {
      throw ArgumentError(
        'Approved peer identity and certificate pin required',
      );
    }
    bool matches(X509Certificate cert) =>
        sha256.convert(cert.der).toString() ==
        trustedCertificateSha256.toLowerCase();
    final socket = await SecureSocket.connect(
      host,
      port,
      context: clientIdentity,
      timeout: const Duration(seconds: 15),
      onBadCertificate: matches,
    );
    final cert = socket.peerCertificate;
    if (cert == null || !matches(cert)) {
      socket.destroy();
      throw const HandshakeException('Harness peer certificate mismatch');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    return HarnessRemoteTlsChannel._(socket, trustedPeerId);
  }

  final SecureSocket _socket;
  @override
  final String authenticatedPeerId;
  final _frames = StreamController<String>();
  late final StreamSubscription<Uint8List> _subscription;
  final Uint8List _header = Uint8List(4);
  int _headerLength = 0;
  Uint8List? _body;
  int _bodyLength = 0;
  bool _closed = false;
  Future<void> _writes = Future<void>.value();
  int _queuedBytes = 0;
  static const maxBytes = 8 * 1024 * 1024;
  @override
  Stream<String> get frames => _frames.stream;

  void _accept(Uint8List bytes) {
    var offset = 0;
    try {
      while (!_closed && offset < bytes.length) {
        if (_body == null) {
          final count = math.min(4 - _headerLength, bytes.length - offset);
          _header.setRange(_headerLength, _headerLength + count, bytes, offset);
          _headerLength += count;
          offset += count;
          if (_headerLength != 4) continue;
          final size = ByteData.sublistView(_header).getUint32(0);
          if (size == 0 || size > maxBytes) {
            throw const FormatException('Remote frame length rejected');
          }
          _body = Uint8List(size);
          _bodyLength = 0;
        }
        final body = _body!;
        final count = math.min(
          body.length - _bodyLength,
          bytes.length - offset,
        );
        body.setRange(_bodyLength, _bodyLength + count, bytes, offset);
        _bodyLength += count;
        offset += count;
        if (_bodyLength == body.length) {
          _frames.add(utf8.decode(body));
          _body = null;
          _headerLength = 0;
        }
      }
    } catch (error, stack) {
      _frames.addError(error, stack);
      unawaited(close());
    }
  }

  @override
  Future<void> send(String frame) {
    if (_closed) return Future.error(StateError('REMOTE_CHANNEL_CLOSED'));
    final body = utf8.encode(frame);
    if (body.isEmpty ||
        body.length > maxBytes ||
        _queuedBytes + body.length > maxBytes * 2) {
      return Future.error(StateError('REMOTE_BACKPRESSURE'));
    }
    _queuedBytes += body.length;
    final result = _writes
        .then((_) async {
          if (_closed) throw StateError('REMOTE_CHANNEL_CLOSED');
          final header = ByteData(4)..setUint32(0, body.length);
          _socket.add(header.buffer.asUint8List());
          _socket.add(body);
          await _socket.flush();
        })
        .whenComplete(() {
          _queuedBytes -= body.length;
        });
    _writes = result.catchError((Object error) {
      unawaited(close());
    });
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    await _subscription.cancel();
    _body = null;
    // Do not await a paused consumer; shutdown cannot wait for UI resumption.
    unawaited(_frames.close());
  }
}
