import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/adb_server_endpoint.dart';
import 'package:vibekits/features/dev_tools/domain/adb_service.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';

void main() {
  test('局域网主机别名自动解析为 192.168.3.x:5555', () {
    expect(AdbService.normalizeWirelessAddress('53'), '192.168.3.53:5555');
  });

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

  test('ADB 实际进程完成后由执行层写入原始命令证据', () async {
    if (!Platform.isWindows) return;
    final String adb = File(
      '${Directory.current.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}android-platform-tools'
      '${Platform.pathSeparator}windows${Platform.pathSeparator}adb.exe',
    ).absolute.path;
    Map<String, Object?>? capturedArguments;
    Object? capturedResult;
    HarnessToolActivityStatus? capturedStatus;

    final AdbCommandResult result = await AdbService.runCommand(
      adb,
      const <String>['devices', '-l'],
      audit: AdbCommandAudit(
        toolId: 'vibekits.adb.list_devices',
        toolName: '列出 ADB 设备',
        target: '',
        recorder:
            ({
              required String toolId,
              required String toolName,
              required String target,
              required Map<String, Object?> arguments,
              required Object? result,
              required HarnessToolActivityStatus status,
              required DateTime startedAt,
            }) async {
              capturedArguments = arguments;
              capturedResult = result;
              capturedStatus = status;
            },
      ),
    );

    expect(result.exitCode, 0);
    expect(capturedArguments?['executable'], adb);
    expect(capturedArguments?['arguments'], <String>['devices', '-l']);
    expect(capturedStatus, HarnessToolActivityStatus.succeeded);
    expect(capturedResult.toString(), contains('evidenceSource: adb-process'));
  });

  test('用户命令支持引号、自动 Shell 且不能覆盖选中设备', () {
    expect(AdbService.parseUserCommand('getprop ro.product.model'), <String>[
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    expect(
      AdbService.parseUserCommand('shell input text "hello world"'),
      <String>['shell', 'input', 'text', 'hello world'],
    );
    expect(
      AdbService.parseUserCommand(r'install "C:\build output\app.apk"'),
      <String>['install', r'C:\build output\app.apk'],
    );
    expect(
      () => AdbService.parseUserCommand('-s other-device shell id'),
      throwsFormatException,
    );
    expect(
      () => AdbService.parseUserCommand('kill-server'),
      throwsFormatException,
    );
  });

  test('远端 ADB server 参数始终位于实际命令最前并标记设备来源', () async {
    final AdbServerEndpoint endpoint = AdbServerEndpoint.rustDesk(
      host: 'localhost',
      port: 15037,
      peerId: 'peer-123',
      sessionId: 'session-7',
      leaseId: 'lease-9',
    );
    final List<List<String>> calls = <List<String>>[];
    Future<AdbCommandResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      calls.add(arguments);
      if (arguments.contains('connect')) {
        return const AdbCommandResult(
          exitCode: 0,
          stdout: 'connected to 192.168.3.53:5555',
          stderr: '',
        );
      }
      return const AdbCommandResult(
        exitCode: 0,
        stdout: 'List of devices attached\nremote-usb device model:Pixel_9\n',
        stderr: '',
      );
    }

    final List<AdbDevice> devices = await AdbService.listDevices(
      '/unused/adb',
      runner: runner,
      endpoint: endpoint,
    );
    await AdbService.connect(
      '/unused/adb',
      '192.168.3.53',
      runner: runner,
      endpoint: endpoint,
    );

    expect(calls, <List<String>>[
      <String>['-H', '127.0.0.1', '-P', '15037', 'devices', '-l'],
      <String>[
        '-H',
        '127.0.0.1',
        '-P',
        '15037',
        'connect',
        '192.168.3.53:5555',
      ],
    ]);
    expect(devices.single.source.remote, isTrue);
    expect(devices.single.source.peerId, 'peer-123');
    expect(devices.single.source.label, 'KEMI 远程办公 · peer-123');
  });

  test('本机 endpoint 保持现有 adb 参数不变', () {
    const AdbServerEndpoint endpoint = AdbServerEndpoint.local();
    expect(endpoint.applyTo(<String>['devices', '-l']), <String>[
      'devices',
      '-l',
    ]);
    final AdbDevice device = AdbService.parseDevices(
      'List of devices attached\nusb device\n',
    ).single;
    expect(device.source.remote, isFalse);
    expect(device.source.label, '本机设备');
  });

  test('ADB 审计证据包含远端 server、peer 与 session 但不含 lease', () async {
    if (Platform.isWindows) return;
    final AdbServerEndpoint endpoint = AdbServerEndpoint.rustDesk(
      host: '127.0.0.1',
      port: 15037,
      peerId: 'peer-audit',
      sessionId: 'session-audit',
      leaseId: 'lease-audit',
    );
    Map<String, Object?>? captured;
    await AdbService.runCommand(
      '/usr/bin/true',
      const <String>['devices', '-l'],
      endpoint: endpoint,
      audit: AdbCommandAudit(
        toolId: 'vibekits.adb.list_devices',
        toolName: '列出 ADB 设备',
        target: '',
        recorder:
            ({
              required String toolId,
              required String toolName,
              required String target,
              required Map<String, Object?> arguments,
              required Object? result,
              required HarnessToolActivityStatus status,
              required DateTime startedAt,
            }) async {
              captured = arguments;
            },
      ),
    );

    expect(captured?['arguments'], <String>[
      '-H',
      '127.0.0.1',
      '-P',
      '15037',
      'devices',
      '-l',
    ]);
    expect(captured?['adbServer'], <String, Object?>{
      'kind': 'rustDesk',
      'displayName': 'KEMI 远程办公 · peer-audit',
      'host': '127.0.0.1',
      'port': 15037,
      'peerId': 'peer-audit',
      'sessionId': 'session-audit',
    });
  });
}
