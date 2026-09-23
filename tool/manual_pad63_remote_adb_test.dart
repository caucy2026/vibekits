import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

/// Explicit real-device test; never part of the ordinary unit-test suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test normally forces every HttpClient request to return 400.
  // Restore real networking for this explicitly invoked device test.
  HttpOverrides.global = null;

  test('PAD63 ADB works through forced HBBR relay', () async {
    const deviceId = '6795854383';
    final helperPath = Platform.environment['VIBEKITS_TEST_RELAY_HELPER'] ?? '';
    final helper = File(helperPath);
    expect(helper.existsSync(), isTrue, reason: 'Set VIBEKITS_TEST_RELAY_HELPER');
    final host = await RustDeskHarnessShareService.ensureHostAvailable(
      configuredExecutable: helper.path,
    );
    expect(host.available && host.id.isNotEmpty, isTrue, reason: host.message);
    final controller = HarnessSimulatorController(
      resolveHost: () async => RustDeskHostInfo(
        executable: helper.path,
        id: host.id,
        available: true,
        callable: true,
        message: host.message,
      ),
      enableAdbBootstrap: true,
    );
    addTearDown(controller.closeAll);

    final status = await controller.connect(
      deviceId,
      forceRelay: true,
      timeout: const Duration(seconds: 90),
    );
    expect(status['connected'], isTrue);
    expect(status['mcpReady'], isTrue);
    expect(status['adbReady'], isTrue, reason: '${status['adbError']}');
    final serial = status['adbSerial']?.toString() ?? '';
    expect(serial, startsWith('127.0.0.1:'));
    final adb = Platform.environment['VIBEKITS_TEST_ADB'] ?? 'adb';
    final result = await Process.run(adb, <String>[
      '-s', serial, 'shell', 'getprop', 'ro.product.model',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
