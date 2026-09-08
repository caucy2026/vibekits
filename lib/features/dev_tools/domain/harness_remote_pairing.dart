import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'harness_remote_peer_store.dart';

/// Certificate exchange carried only inside an explicitly authorized RustDesk
/// byte tunnel. The six-digit comparison code binds both routing identities,
/// both certificates and a fresh nonce so a substituted endpoint is visible.
final class HarnessRemotePairingRequest {
  HarnessRemotePairingRequest({
    required this.routingId,
    required this.deviceId,
    required this.certificatePem,
    required this.nonce,
    required Set<String> requestedWorkspaceIds,
    required Set<String> requestedOperations,
  }) : certificateSha256 = HarnessRemotePeer.certificatePemSha256(
         certificatePem,
       ),
       requestedWorkspaceIds = Set.unmodifiable(requestedWorkspaceIds),
       requestedOperations = Set.unmodifiable(requestedOperations) {
    _validate();
  }

  factory HarnessRemotePairingRequest.create({
    required String routingId,
    required String deviceId,
    required String certificatePem,
    required Set<String> requestedWorkspaceIds,
    required Set<String> requestedOperations,
    Random? random,
  }) {
    final secure = random ?? Random.secure();
    final nonce = List.generate(
      24,
      (_) => secure.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return HarnessRemotePairingRequest(
      routingId: routingId,
      deviceId: deviceId,
      certificatePem: certificatePem,
      nonce: nonce,
      requestedWorkspaceIds: requestedWorkspaceIds,
      requestedOperations: requestedOperations,
    );
  }

  factory HarnessRemotePairingRequest.fromJson(Map<String, dynamic> row) {
    final workspaces = row['requestedWorkspaceIds'];
    final operations = row['requestedOperations'];
    if (workspaces is! List || operations is! List) {
      throw const FormatException('Invalid Harness pairing request');
    }
    return HarnessRemotePairingRequest(
      routingId: row['routingId']?.toString() ?? '',
      deviceId: row['deviceId']?.toString() ?? '',
      certificatePem: row['certificatePem']?.toString() ?? '',
      nonce: row['nonce']?.toString() ?? '',
      requestedWorkspaceIds: workspaces.cast<String>().toSet(),
      requestedOperations: operations.cast<String>().toSet(),
    );
  }

  final String routingId;
  final String deviceId;
  final String certificatePem;
  final String certificateSha256;
  final String nonce;
  final Set<String> requestedWorkspaceIds;
  final Set<String> requestedOperations;

  void _validate() {
    final expectedDeviceId =
        'VH-${certificateSha256.substring(0, 32).toUpperCase()}';
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(routingId) ||
        !RegExp(r'^VH-[A-F0-9]{16,64}$').hasMatch(deviceId) ||
        deviceId != expectedDeviceId ||
        !RegExp(r'^[a-f0-9]{48}$').hasMatch(nonce) ||
        requestedWorkspaceIds.isEmpty ||
        requestedWorkspaceIds.length > 100 ||
        requestedOperations.isEmpty ||
        requestedOperations.length > 32 ||
        requestedWorkspaceIds.any(
          (value) => value.isEmpty || value.length > 512,
        ) ||
        requestedOperations.any(
          (value) => value.isEmpty || value.length > 80,
        )) {
      throw const FormatException('Invalid Harness pairing request');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'pair-request',
    'version': 1,
    'routingId': routingId,
    'deviceId': deviceId,
    'certificatePem': certificatePem,
    'certificateSha256': certificateSha256,
    'nonce': nonce,
    'requestedWorkspaceIds': requestedWorkspaceIds.toList()..sort(),
    'requestedOperations': requestedOperations.toList()..sort(),
  };
}

final class HarnessRemotePairingApproval {
  HarnessRemotePairingApproval({
    required this.request,
    required this.hostRoutingId,
    required this.hostDeviceId,
    required this.hostCertificatePem,
    required Set<String> grantedWorkspaceIds,
    required Set<String> grantedOperations,
    required this.approvedAt,
  }) : hostCertificateSha256 = HarnessRemotePeer.certificatePemSha256(
         hostCertificatePem,
       ),
       grantedWorkspaceIds = Set.unmodifiable(grantedWorkspaceIds),
       grantedOperations = Set.unmodifiable(grantedOperations) {
    final expectedHostDeviceId =
        'VH-${hostCertificateSha256.substring(0, 32).toUpperCase()}';
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(hostRoutingId) ||
        !RegExp(r'^VH-[A-F0-9]{16,64}$').hasMatch(hostDeviceId) ||
        hostDeviceId != expectedHostDeviceId ||
        !request.requestedWorkspaceIds.containsAll(grantedWorkspaceIds) ||
        !request.requestedOperations.containsAll(grantedOperations) ||
        grantedWorkspaceIds.isEmpty ||
        grantedOperations.isEmpty) {
      throw const FormatException('Invalid Harness pairing approval');
    }
  }

  final HarnessRemotePairingRequest request;
  final String hostRoutingId;
  final String hostDeviceId;
  final String hostCertificatePem;
  final String hostCertificateSha256;
  final Set<String> grantedWorkspaceIds;
  final Set<String> grantedOperations;
  final DateTime approvedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'pair-approved',
    'version': 1,
    'hostRoutingId': hostRoutingId,
    'hostDeviceId': hostDeviceId,
    'hostCertificatePem': hostCertificatePem,
    'hostCertificateSha256': hostCertificateSha256,
    'grantedWorkspaceIds': grantedWorkspaceIds.toList()..sort(),
    'grantedOperations': grantedOperations.toList()..sort(),
    'approvedAt': approvedAt.toUtc().toIso8601String(),
    'comparisonCode': comparisonCode,
  };

  factory HarnessRemotePairingApproval.fromJson(
    HarnessRemotePairingRequest request,
    Map<String, dynamic> row,
  ) {
    final workspaces = row['grantedWorkspaceIds'];
    final operations = row['grantedOperations'];
    final approvedAt = DateTime.tryParse(row['approvedAt']?.toString() ?? '');
    if (row['kind'] != 'pair-approved' ||
        row['version'] != 1 ||
        workspaces is! List ||
        operations is! List ||
        approvedAt == null) {
      throw const FormatException('Invalid Harness pairing response');
    }
    final approval = HarnessRemotePairingApproval(
      request: request,
      hostRoutingId: row['hostRoutingId']?.toString() ?? '',
      hostDeviceId: row['hostDeviceId']?.toString() ?? '',
      hostCertificatePem: row['hostCertificatePem']?.toString() ?? '',
      grantedWorkspaceIds: workspaces.cast<String>().toSet(),
      grantedOperations: operations.cast<String>().toSet(),
      approvedAt: approvedAt.toUtc(),
    );
    if (row['hostCertificateSha256'] != approval.hostCertificateSha256 ||
        row['comparisonCode'] != approval.comparisonCode) {
      throw const FormatException('Harness pairing response was modified');
    }
    return approval;
  }

  String get comparisonCode {
    final digest = sha256.convert(
      utf8.encode(
        [
          'vibekits-harness-pair-v1',
          request.routingId,
          hostRoutingId,
          request.deviceId,
          hostDeviceId,
          request.certificateSha256,
          hostCertificateSha256,
          request.nonce,
        ].join('\n'),
      ),
    );
    final value = digest.bytes.take(4).fold<int>(0, (a, b) => (a << 8) | b);
    return (value % 1000000).toString().padLeft(6, '0');
  }

  HarnessRemotePeer controllerRecord({required bool remembered}) =>
      HarnessRemotePeer(
        routingId: hostRoutingId,
        deviceId: hostDeviceId,
        certificateSha256: hostCertificateSha256,
        certificatePem: hostCertificatePem,
        workspaceIds: grantedWorkspaceIds,
        operations: grantedOperations,
        remembered: remembered,
        firstApprovedAt: approvedAt.toUtc(),
        lastConnectedAt: approvedAt.toUtc(),
        lastTransport: 'relay',
      );

  HarnessRemotePeer hostRecord({required bool remembered}) => HarnessRemotePeer(
    routingId: request.routingId,
    deviceId: request.deviceId,
    certificateSha256: request.certificateSha256,
    certificatePem: request.certificatePem,
    workspaceIds: grantedWorkspaceIds,
    operations: grantedOperations,
    remembered: remembered,
    firstApprovedAt: approvedAt.toUtc(),
    lastConnectedAt: approvedAt.toUtc(),
    lastTransport: 'relay',
  );
}
