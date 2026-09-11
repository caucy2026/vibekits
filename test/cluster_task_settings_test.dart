import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/cluster_task_settings.dart';

void main() {
  test('集群任务默认开启且未配置时保持安全等待', () async {
    final values = <String, String>{};
    final settings = ClusterTaskSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );

    final initial = await settings.load();
    expect(initial.enabled, isTrue);
    expect(initial.configured, isFalse);
    expect(initial.phase, 'waiting_configuration');
    final disabled = await settings.saveEnabled(false);
    expect(disabled.enabled, isFalse);
    expect(disabled.phase, 'disabled');
    final enabled = await settings.saveEnabled(true);
    expect(enabled.enabled, isTrue);
    expect(enabled.phase, 'waiting_configuration');
  });

  test('集群任务只接受 HTTPS 并保存可信域与签名公钥', () async {
    final values = <String, String>{};
    final settings = ClusterTaskSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );

    expect(
      () => settings.saveConfiguration(
        serverUrl: 'http://tasks.example.com',
        trustedHosts: const <String>['tasks.example.com'],
        signingPublicKey: 'public-key',
      ),
      throwsA(isA<FormatException>()),
    );

    final configured = await settings.saveConfiguration(
      serverUrl: 'https://tasks.example.com/api/v1/agents',
      trustedHosts: const <String>['TASKS.EXAMPLE.COM', 'content.example.com'],
      signingPublicKey: 'public-key',
    );
    expect(configured.configured, isTrue);
    expect(configured.enabled, isTrue);
    expect(configured.trustedHosts, <String>[
      'content.example.com',
      'tasks.example.com',
    ]);
    expect(configured.toSafeJson(), isNot(contains('signingPublicKey')));
    expect(configured.toSafeJson()['hasSigningPublicKey'], isTrue);
  });
}
