import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:vibekits/features/dev_tools/domain/harness_remote_identity.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_pairing.dart';

void main() {
  test('首次配对验证码绑定双端 ID、证书、nonce 和最小授权范围', () async {
    Future<HarnessRemoteIdentity> identity(String prefix) {
      final credentials = <String, String>{};
      return HarnessRemoteIdentityStore(
        read: (key) async => credentials['$prefix:$key'],
        write: (key, value) async => credentials['$prefix:$key'] = value,
      ).loadOrCreate();
    }

    final controller = await identity('controller');
    final host = await identity('host');
    final request = HarnessRemotePairingRequest(
      routingId: '1554650784',
      deviceId: controller.deviceId,
      certificatePem: controller.certificatePem,
      nonce: List.filled(48, 'a').join(),
      passwordProof: HarnessRemotePairingRequest.computePasswordProof(
        password: '12345678',
        routingId: '1554650784',
        deviceId: controller.deviceId,
        certificateSha256: controller.fingerprint,
        nonce: List.filled(48, 'a').join(),
        requestedWorkspaceIds: const {'workspace-1'},
        requestedOperations: const {'session.history', 'session.prompt'},
      ),
      requestedWorkspaceIds: const {'workspace-1'},
      requestedOperations: const {'session.history', 'session.prompt'},
    );
    final approval = HarnessRemotePairingApproval(
      request: request,
      hostRoutingId: '2602628020',
      hostDeviceId: host.deviceId,
      hostCertificatePem: host.certificatePem,
      grantedWorkspaceIds: const {'workspace-1'},
      grantedOperations: const {'session.history'},
      approvedAt: DateTime.utc(2026, 9, 8, 8),
    );
    expect(approval.comparisonCode, matches(RegExp(r'^\d{6}$')));
    expect(approval.controllerRecord(remembered: true).connectionReady, true);
    expect(approval.hostRecord(remembered: true).connectionReady, true);
    expect(
      HarnessRemotePairingRequest.fromJson(request.toJson()).certificateSha256,
      controller.fingerprint,
    );
  });

  test('配对不得扩大请求范围或接受篡改证书', () async {
    final credentials = <String, String>{};
    final identity = await HarnessRemoteIdentityStore(
      read: (key) async => credentials[key],
      write: (key, value) async => credentials[key] = value,
    ).loadOrCreate();
    final request = HarnessRemotePairingRequest(
      routingId: '1554650784',
      deviceId: identity.deviceId,
      certificatePem: identity.certificatePem,
      nonce: List.filled(48, 'b').join(),
      passwordProof: HarnessRemotePairingRequest.computePasswordProof(
        password: '12345678',
        routingId: '1554650784',
        deviceId: identity.deviceId,
        certificateSha256: identity.fingerprint,
        nonce: List.filled(48, 'b').join(),
        requestedWorkspaceIds: const {'workspace-1'},
        requestedOperations: const {'session.history'},
      ),
      requestedWorkspaceIds: const {'workspace-1'},
      requestedOperations: const {'session.history'},
    );
    expect(
      () => HarnessRemotePairingApproval(
        request: request,
        hostRoutingId: '2602628020',
        hostDeviceId: identity.deviceId,
        hostCertificatePem: identity.certificatePem,
        grantedWorkspaceIds: const {'workspace-2'},
        grantedOperations: const {'session.history'},
        approvedAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    expect(
      () => HarnessRemotePairingRequest.fromJson({
        ...request.toJson(),
        'certificatePem': '${identity.certificatePem}x',
      }),
      throwsFormatException,
    );
  });

  test('控制端只输入设备 ID 时由执行端解析当前项目范围', () async {
    Future<HarnessRemoteIdentity> identity(String prefix) {
      final credentials = <String, String>{};
      return HarnessRemoteIdentityStore(
        read: (key) async => credentials['$prefix:$key'],
        write: (key, value) async => credentials['$prefix:$key'] = value,
      ).loadOrCreate();
    }

    final controller = await identity('controller-catalog');
    final host = await identity('host-catalog');
    final request = HarnessRemotePairingRequest.create(
      routingId: '9464730211',
      deviceId: controller.deviceId,
      certificatePem: controller.certificatePem,
      requestedWorkspaceIds: const {
        HarnessRemotePairingRequest.currentWorkspaceCatalogScope,
      },
      requestedOperations: const {'session.history', 'session.prompt'},
      password: '12345678',
      random: Random(7),
    );
    final approval = HarnessRemotePairingApproval(
      request: request,
      hostRoutingId: '1554650784',
      hostDeviceId: host.deviceId,
      hostCertificatePem: host.certificatePem,
      grantedWorkspaceIds: const {'/Volumes/ORICO/newlink-new/vibekits'},
      grantedOperations: const {'session.history', 'session.prompt'},
      approvedAt: DateTime.utc(2026, 9, 10, 3),
    );

    expect(approval.hostRecord(remembered: true).workspaceIds, const {
      '/Volumes/ORICO/newlink-new/vibekits',
    });
    expect(approval.controllerRecord(remembered: true).workspaceIds, const {
      '/Volumes/ORICO/newlink-new/vibekits',
    });
  });
}
