import 'dart:async';
import 'dart:io';

import 'harness_remote_connection.dart';
import 'harness_remote_identity.dart';
import 'harness_remote_peer_store.dart';
import 'harness_remote_tls_channel.dart';
import 'harness_remote_view_model.dart';
import 'harness_remote_workspace_client.dart';
import 'rustdesk_harness_share_service.dart';

typedef HarnessRemoteEventApplier =
    Future<void> Function(List<Map<String, dynamic>> rows);
typedef HarnessRemoteChannelConnector =
    Future<HarnessRemoteChannel> Function({
      required String host,
      required int port,
      required String trustedPeerId,
      required String trustedCertificateSha256,
      SecurityContext? clientIdentity,
    });

/// Owns the complete controller-side lifetime:
/// native direct/relay carrier -> pinned mTLS -> Harness protocol -> state UI.
///
/// It intentionally supports remembered, certificate-complete peers only.
/// First pairing is a separate explicit approval operation; a routing ID alone
/// must never silently become an authenticated remote workspace.
final class HarnessRemoteControllerSession {
  HarnessRemoteControllerSession._({
    required this.peer,
    required this.tunnel,
    required this.connection,
    required this.client,
    required this.model,
  });

  final HarnessRemotePeer peer;
  final RustDeskHarnessTunnelLease tunnel;
  final HarnessRemoteConnection connection;
  final HarnessRemoteWorkspaceClient client;
  final HarnessRemoteViewModel model;
  bool _closed = false;

  static Future<HarnessRemoteControllerSession> connect({
    required String executable,
    required HarnessRemotePeer peer,
    required HarnessRemoteIdentity identity,
    required HarnessRemoteEventApplier applyOfficialEvents,
    required HarnessRemoteEventApplier restoreOfficialSnapshot,
    bool forceRelay = false,
    Duration timeout = const Duration(seconds: 25),
    RustDeskManagedProcessLauncher? tunnelLauncher,
    HarnessRemoteChannelConnector? channelConnector,
  }) async {
    if (!peer.remembered || !peer.connectionReady) {
      throw StateError('REMOTE_PAIRING_REQUIRED');
    }
    final localPort = await RustDeskHarnessShareService.allocateTunnelPort();
    final tunnel = await RustDeskHarnessShareService.openTunnel(
      executable,
      routingId: peer.routingId,
      localPort: localPort,
      forceRelay: forceRelay,
      launcher: tunnelLauncher,
    );
    HarnessRemoteConnection? connection;
    try {
      final deadline = DateTime.now().add(timeout);
      Object? lastError;
      HarnessRemoteChannel? channel;
      while (DateTime.now().isBefore(deadline)) {
        try {
          channel = await (channelConnector ?? HarnessRemoteTlsChannel.connect)(
            host: InternetAddress.loopbackIPv4.address,
            port: localPort,
            trustedPeerId: peer.deviceId,
            trustedCertificateSha256: peer.certificateSha256,
            clientIdentity: identity.context(
              trustedCertificates: <String>[peer.certificatePem!],
            ),
          );
          break;
        } on Object catch (error) {
          lastError = error;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      if (channel == null) {
        throw TimeoutException(
          'REMOTE_TUNNEL_TLS_TIMEOUT: ${lastError ?? 'unavailable'}',
          timeout,
        );
      }
      connection = HarnessRemoteConnection(channel);
      final client = HarnessRemoteWorkspaceClient(connection);
      // Negotiate before publishing a connected model. This prevents an open
      // local port or a valid certificate from being mislabeled as usable.
      await client.negotiate();
      final model = HarnessRemoteViewModel(
        client,
        applyOfficialEvents: applyOfficialEvents,
        restoreOfficialSnapshot: restoreOfficialSnapshot,
      )..start();
      return HarnessRemoteControllerSession._(
        peer: peer,
        tunnel: tunnel,
        connection: connection,
        client: client,
        model: model,
      );
    } on Object {
      await connection?.close();
      await tunnel.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    model.dispose();
    await connection.close();
    await tunnel.close();
  }
}
