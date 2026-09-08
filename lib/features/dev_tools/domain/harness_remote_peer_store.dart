import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'lmcp_exposure_server.dart';
import 'platform_credential_store.dart';

class HarnessRemotePeer {
  const HarnessRemotePeer({
    required this.routingId,
    required this.deviceId,
    required this.certificateSha256,
    required this.workspaceIds,
    required this.operations,
    required this.remembered,
    required this.firstApprovedAt,
    required this.lastConnectedAt,
    required this.lastTransport,
    this.certificatePem,
  });

  final String routingId;
  final String deviceId;
  final String certificateSha256;
  final Set<String> workspaceIds;
  final Set<String> operations;
  final bool remembered;
  final DateTime firstApprovedAt;
  final DateTime lastConnectedAt;
  final String lastTransport;

  /// Public certificate captured during explicit first pairing. Legacy v1
  /// records may contain only the pin and must be paired again before use.
  final String? certificatePem;

  bool get connectionReady =>
      certificatePem != null &&
      certificatePemSha256(certificatePem!) == certificateSha256;

  HarnessRemotePeer connectedNow({required String transport, DateTime? at}) {
    if (!const {'direct', 'relay'}.contains(transport)) {
      throw ArgumentError.value(transport, 'transport');
    }
    return HarnessRemotePeer(
      routingId: routingId,
      deviceId: deviceId,
      certificateSha256: certificateSha256,
      certificatePem: certificatePem,
      workspaceIds: workspaceIds,
      operations: operations,
      remembered: remembered,
      firstApprovedAt: firstApprovedAt,
      lastConnectedAt: (at ?? DateTime.now()).toUtc(),
      lastTransport: transport,
    );
  }

  Map<String, Object?> toJson() => {
    'routingId': routingId,
    'deviceId': deviceId,
    'certificateSha256': certificateSha256,
    'workspaceIds': workspaceIds.toList()..sort(),
    'operations': operations.toList()..sort(),
    'remembered': remembered,
    'firstApprovedAt': firstApprovedAt.toUtc().toIso8601String(),
    'lastConnectedAt': lastConnectedAt.toUtc().toIso8601String(),
    'lastTransport': lastTransport,
    if (certificatePem != null) 'certificatePem': certificatePem,
  };

  static HarnessRemotePeer fromJson(Map<String, dynamic> row) {
    final workspaceIds = row['workspaceIds'];
    final operations = row['operations'];
    final first = DateTime.tryParse(row['firstApprovedAt'] as String? ?? '');
    final last = DateTime.tryParse(row['lastConnectedAt'] as String? ?? '');
    final certificatePem = row['certificatePem'];
    if (row['routingId'] is! String ||
        !RegExp(r'^[1-9][0-9]{9}$').hasMatch(row['routingId'] as String) ||
        row['deviceId'] is! String ||
        !(row['deviceId'] as String).startsWith('VH-') ||
        row['certificateSha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(row['certificateSha256'] as String) ||
        workspaceIds is! List ||
        !workspaceIds.every((value) => value is String && value.isNotEmpty) ||
        operations is! List ||
        !operations.every((value) => value is String && value.isNotEmpty) ||
        row['remembered'] is! bool ||
        first == null ||
        last == null ||
        !const {'direct', 'relay'}.contains(row['lastTransport'])) {
      throw const FormatException('Invalid Harness remote peer record');
    }
    if (certificatePem != null &&
        (certificatePem is! String ||
            certificatePemSha256(certificatePem) != row['certificateSha256'])) {
      throw const FormatException('Invalid Harness remote peer certificate');
    }
    return HarnessRemotePeer(
      routingId: row['routingId'] as String,
      deviceId: row['deviceId'] as String,
      certificateSha256: row['certificateSha256'] as String,
      workspaceIds: Set.unmodifiable(workspaceIds.cast<String>()),
      operations: Set.unmodifiable(operations.cast<String>()),
      remembered: row['remembered'] as bool,
      firstApprovedAt: first.toUtc(),
      lastConnectedAt: last.toUtc(),
      lastTransport: row['lastTransport'] as String,
      certificatePem: certificatePem as String?,
    );
  }

  static String certificatePemSha256(String pem) {
    final match = RegExp(
      r'^-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+)\s*-----END CERTIFICATE-----$',
    ).firstMatch(pem.trim());
    if (match == null) {
      throw const FormatException('Invalid Harness remote peer certificate');
    }
    try {
      final body = match.group(1)!.replaceAll(RegExp(r'\s'), '');
      return sha256.convert(base64Decode(body)).toString();
    } on FormatException {
      throw const FormatException('Invalid Harness remote peer certificate');
    }
  }
}

/// Stores remembered authorization and connection history in the platform
/// credential manager. There is deliberately no default/shared password.
class HarnessRemotePeerStore {
  HarnessRemotePeerStore({
    LmcpCredentialReader? read,
    LmcpCredentialWriter? write,
  }) : _read = read ?? PlatformCredentialStore.read,
       _write = write ?? PlatformCredentialStore.write;

  static const credentialKey = 'harness-remote-v1-peers';
  static const maxPeers = 100;
  static const maxEncodedBytes = 256 * 1024;
  final LmcpCredentialReader _read;
  final LmcpCredentialWriter _write;

  Future<List<HarnessRemotePeer>> load() async {
    final encoded = await _read(credentialKey);
    if (encoded == null || encoded.isEmpty) return const [];
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw StateError('REMOTE_PEER_STORE_TOO_LARGE');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        !const {1, 2}.contains(decoded['version']) ||
        decoded['peers'] is! List) {
      throw const FormatException('Invalid Harness remote peer store');
    }
    final peers = (decoded['peers'] as List)
        .map(
          (row) =>
              HarnessRemotePeer.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    if (peers.length > maxPeers ||
        peers.map((peer) => peer.routingId).toSet().length != peers.length) {
      throw const FormatException('Invalid Harness remote peer collection');
    }
    peers.sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
    return List.unmodifiable(peers);
  }

  Future<void> save(HarnessRemotePeer peer) async {
    final peers = (await load())
        .where((existing) => existing.routingId != peer.routingId)
        .toList();
    if (peer.remembered) peers.insert(0, peer);
    if (peers.length > maxPeers) peers.removeRange(maxPeers, peers.length);
    final encoded = jsonEncode({
      'version': 2,
      'peers': peers.map((value) => value.toJson()).toList(),
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw StateError('REMOTE_PEER_STORE_TOO_LARGE');
    }
    await _write(credentialKey, encoded);
  }

  Future<void> forget(String routingId) async {
    final peers = (await load())
        .where((peer) => peer.routingId != routingId)
        .toList();
    await _write(
      credentialKey,
      jsonEncode({
        'version': 2,
        'peers': peers.map((peer) => peer.toJson()).toList(),
      }),
    );
  }
}
