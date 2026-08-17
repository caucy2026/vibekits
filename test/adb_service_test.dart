import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';

void main() {
  test('解析官方版本和 device/unauthorized/offline 三种设备', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_adb_');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File adb = File('${sandbox.path}${Platform.pathSeparator}adb.exe')
      ..writeAsBytesSync(<int>[0]);
    Future<AdbCommandResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      if (arguments.first == 'version') {
        return const AdbCommandResult(
          exitCode: 0,
          stdout:
              'Android Debug Bridge version 1.0.41\nVersion 36.0.0-13206524',
          stderr: '',
        );
      }
      return const AdbCommandResult(
        exitCode: 0,
        stdout:
            'List of devices attached\n'
            'usb-ok device product:p model:Pixel_9 device:tokay transport_id:1\n'
            'usb-denied unauthorized transport_id:2\n'
            'usb-offline offline transport_id:3\n',
        stderr: '',
      );
    }

    final AdbInstallation installation = await AdbService.inspectExecutable(
      adb.path,
      runner: runner,
    );
    final List<AdbDevice> devices = await AdbService.listDevices(
      adb.path,
      runner: runner,
    );

    expect(installation.version, '1.0.41');
    expect(installation.executable, adb.absolute.path);
    expect(devices.map((AdbDevice item) => item.serial), <String>[
      'usb-ok',
      'usb-denied',
      'usb-offline',
    ]);
    expect(devices.map((AdbDevice item) => item.state), <AdbDeviceState>[
      AdbDeviceState.device,
      AdbDeviceState.unauthorized,
      AdbDeviceState.offline,
    ]);
    expect(devices.first.model, 'Pixel_9');
    expect(devices.where((AdbDevice item) => item.ready), hasLength(1));
  });

  test('拒绝伪装成其他名称的可执行文件和无法识别的版本', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync('vk_adb_');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File fake = File('${sandbox.path}${Platform.pathSeparator}tool.exe')
      ..writeAsBytesSync(<int>[0]);
    await expectLater(
      AdbService.inspectExecutable(fake.path),
      throwsA(isA<FormatException>()),
    );
  });
}
