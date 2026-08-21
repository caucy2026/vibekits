import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/windows_node_verification_report.dart';

void main() {
  NodeVerificationReport report({
    String host = '192.168.3.10',
    NodeVerificationStatus status = NodeVerificationStatus.passed,
    String? failedId,
  }) {
    final DateTime started = DateTime(2026, 8, 21, 12);
    return NodeVerificationReport(
      id: 'report-1',
      sourceDeviceId: 'mac-a',
      sourceDeviceLabel: 'MacBook-A',
      sourcePlatform: 'macos',
      targetHost: host,
      hostKeyFingerprint: 'SHA256:verified-host-key',
      startedAt: started,
      completedAt: started.add(const Duration(seconds: 8)),
      status: status,
      checks: <NodeVerificationCheck>[
        for (final String id in NodeVerificationReport.requiredCheckIds)
          NodeVerificationCheck(
            id: id,
            passed: id != failedId,
            elapsedMilliseconds: 100,
            detail: '$id 已核对',
            evidenceRefs: <String>['artifact://node/mac-a/$id.json'],
          ),
      ],
    );
  }

  test('跨设备完整报告生成最多三个下一步的 WorkflowArtifact', () {
    final NodeVerificationReport valid = report();
    final WorkflowArtifact artifact = WorkflowArtifact.fromNodeVerification(
      valid,
    );
    expect(
      valid.checks,
      hasLength(NodeVerificationReport.requiredCheckIds.length),
    );
    expect(artifact.toJson()['nextSteps'], hasLength(3));
    expect(artifact.toJson().toString(), isNot(contains('password=')));
  });

  test('localhost、缺项、秘密证据和伪通过均拒绝', () {
    expect(() => report(host: 'localhost'), throwsA(isA<FormatException>()));
    expect(
      () => report(failedId: 'network_drop_retry'),
      throwsA(isA<FormatException>()),
    );
    final DateTime now = DateTime(2026, 8, 21);
    expect(
      () => NodeVerificationReport(
        id: 'bad',
        sourceDeviceId: 'mac-a',
        sourceDeviceLabel: 'Mac A',
        sourcePlatform: 'macos',
        targetHost: '192.168.3.10',
        hostKeyFingerprint: 'SHA256:key',
        startedAt: now,
        completedAt: now,
        status: NodeVerificationStatus.failed,
        checks: <NodeVerificationCheck>[
          for (final String id in NodeVerificationReport.requiredCheckIds)
            NodeVerificationCheck(
              id: id,
              passed: false,
              elapsedMilliseconds: 1,
              detail: 'blocked',
              evidenceRefs: const <String>['password=secret'],
            ),
        ],
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
