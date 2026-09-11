import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_access_settings.dart';

void main() {
  setUp(() => HarnessSimulatorAccessSettings.setEnabled(false));

  test('仿真机授权默认关闭并可独立持久化', () async {
    final values = <String, String>{};
    HarnessSimulatorAccessSettings settings() => HarnessSimulatorAccessSettings(
      read: (key) async => values[key],
      write: (key, value) async => values[key] = value,
    );

    expect(await settings().loadEnabled(), isFalse);
    await settings().saveEnabled(true);
    HarnessSimulatorAccessSettings.setEnabled(false);
    expect(await settings().loadEnabled(), isTrue);
    expect(HarnessSimulatorAccessSettings.enabled, isTrue);

    await settings().saveEnabled(false);
    expect(await settings().loadEnabled(), isFalse);

    expect(await settings().loadRelayFingerprint(), isEmpty);
    await settings().saveRelayFingerprint('SHA256:ABC');
    expect(await settings().loadRelayFingerprint(), 'sha256:abc');
    expect(await settings().loadRelayExecutable(), isEmpty);
    await settings().saveRelayExecutable(' /Applications/Vibekits.app ');
    expect(
      await settings().loadRelayExecutable(),
      '/Applications/Vibekits.app',
    );
  });
}
