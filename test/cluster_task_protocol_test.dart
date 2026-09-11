import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/cluster_task_protocol.dart';
import 'package:vibekits/features/dev_tools/domain/cluster_task_settings.dart';

void main() {
  const configuration = ClusterTaskConfiguration(
    serverUrl: 'https://tasks.example.com/api/v1/agents',
    trustedHosts: <String>['content.example.com'],
    signingPublicKey: 'test-public-key',
  );
  final now = DateTime.utc(2026, 9, 11, 10);

  ClusterTaskEnvelope envelope({
    String url = 'https://content.example.com/tasks/42',
    DateTime? issuedAt,
    DateTime? expiresAt,
  }) => ClusterTaskEnvelope(
    taskId: 'task-42',
    version: '3',
    descriptionUrl: Uri.parse(url),
    issuedAt: issuedAt ?? now.subtract(const Duration(minutes: 1)),
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    signature: 'signed-envelope',
  );

  test('签名任务网址通过可信域校验后才交给 Harness', () async {
    final validator = ClusterTaskEnvelopeValidator(
      verifySignature: (task, key) async =>
          task.signature == 'signed-envelope' && key == 'test-public-key',
    );
    final accepted = await validator.validate(
      envelope: envelope(),
      configuration: configuration,
      now: now,
    );
    expect(accepted.deduplicationKey, 'task-42@3');
  });

  test('非可信域、过期任务和坏签名全部拒绝', () async {
    final validSignature = ClusterTaskEnvelopeValidator(
      verifySignature: (_, _) async => true,
    );
    expect(
      () => validSignature.validate(
        envelope: envelope(url: 'https://evil.example/tasks/42'),
        configuration: configuration,
        now: now,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => validSignature.validate(
        envelope: envelope(expiresAt: now.subtract(const Duration(seconds: 1))),
        configuration: configuration,
        now: now,
      ),
      throwsA(isA<StateError>()),
    );
    final badSignature = ClusterTaskEnvelopeValidator(
      verifySignature: (_, _) async => false,
    );
    expect(
      () => badSignature.validate(
        envelope: envelope(),
        configuration: configuration,
        now: now,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
