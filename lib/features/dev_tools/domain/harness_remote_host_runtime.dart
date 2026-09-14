import 'dart:io';

import '../../../app/platform_storage_layout.dart';
import 'harness_remote_execution.dart';
import 'harness_remote_host.dart';
import 'harness_remote_identity.dart';
import 'harness_remote_ledger.dart';
import 'harness_remote_peer_store.dart';
import 'harness_official_remote_adapter.dart';
import 'harness_runtime_log_store.dart';

/// Production owner for the execution-side loopback service.
///
/// The native RustDesk identity can reach only this loopback port. The service
/// starts only when at least one remembered peer has a complete approved public
/// certificate; legacy fingerprint-only records remain fail-closed.
final class HarnessRemoteHostRuntime {
  HarnessRemoteHostRuntime({
    HarnessRemoteIdentityStore? identityStore,
    HarnessRemotePeerStore? peerStore,
  }) : _identityStore = identityStore ?? HarnessRemoteIdentityStore.instance,
       _peerStore = peerStore ?? HarnessRemotePeerStore();

  /// App-wide owner for the single loopback execution endpoint. Workspace
  /// widgets may be rebuilt without ending an authorized remote session.
  static final HarnessRemoteHostRuntime shared = HarnessRemoteHostRuntime();

  static const port = 32146;
  final HarnessRemoteIdentityStore _identityStore;
  final HarnessRemotePeerStore _peerStore;
  HarnessRemoteHost? _host;
  bool get running => _host?.port != null;

  Future<bool> start(Uri officialEndpoint) async {
    return _start(HarnessOfficialRemoteAdapter(officialEndpoint));
  }

  Future<bool> startWithAdapter(HarnessRemoteApiAdapter adapter) =>
      _start(adapter);

  Future<bool> _start(HarnessRemoteApiAdapter adapter) async {
    if (_host != null) {
      await adapter.close();
      return true;
    }
    final peers = (await _peerStore.load())
        .where((peer) => peer.remembered && peer.connectionReady)
        .toList(growable: false);
    if (peers.isEmpty) {
      await adapter.close();
      return false;
    }
    final identity = await _identityStore.loadOrCreate();
    final directory = Directory(
      '${PlatformStorageLayout.current().settingsDirectory}'
      '${Platform.pathSeparator}harness-remote',
    );
    await directory.create(recursive: true);
    final ledger = await HarnessRemoteLedger.open(
      File('${directory.path}${Platform.pathSeparator}commands.jsonl'),
    );
    final host = HarnessRemoteHost(adapter: adapter, ledger: ledger);
    try {
      final HarnessRemoteWorkspaceProvisioner? workspaceProvisioner =
          adapter is HarnessRemoteWorkspaceProvisioner
          ? adapter as HarnessRemoteWorkspaceProvisioner
          : null;
      if (workspaceProvisioner != null) {
        final approvedPaths = <String>{
          for (final peer in peers)
            for (final scope in peer.workspaceIds)
              if (Directory(scope).isAbsolute) scope,
        };
        for (final path in approvedPaths) {
          await workspaceProvisioner.ensureWorkspacePath(path);
        }
      }
      var approvedPeerCount = 0;
      for (final peer in peers) {
        final workspaceIds = await host.inventory.resolveWorkspaceScopes(
          peer.workspaceIds,
        );
        if (workspaceIds.isEmpty) continue;
        host.approveCertificate(
          peer.certificateSha256,
          HarnessRemoteGrant(
            peerId: peer.deviceId,
            workspaceIds: workspaceIds,
            operations: peer.operations,
          ),
        );
        approvedPeerCount++;
      }
      await HarnessRuntimeLogStore.appendWorkEvent(<String, Object?>{
        'kind': 'harness-remote-host-grants-loaded',
        'rememberedPeerCount': peers.length,
        'approvedPeerCount': approvedPeerCount,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      if (approvedPeerCount == 0) {
        throw StateError('REMOTE_PAIRING_SCOPE_NOT_RESOLVED');
      }
      await host.start(
        bindAddress: InternetAddress.loopbackIPv4,
        port: port,
        identity: identity.context(
          trustedCertificates: peers.map((peer) => peer.certificatePem!),
        ),
      );
      _host = host;
      return true;
    } on Object {
      await host.close();
      rethrow;
    }
  }

  Future<void> stop() async {
    final host = _host;
    _host = null;
    await host?.close();
  }
}
