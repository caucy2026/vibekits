import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test('RustDesk 网页端只接受无凭据 HTTP/HTTPS 地址', () {
    expect(
      RustDeskHarnessShareService.validateWebClientUrl(
        'https://remote.example.com/web',
      ).host,
      'remote.example.com',
    );
    expect(
      () => RustDeskHarnessShareService.validateWebClientUrl(
        'https://user:secret@remote.example.com/web',
      ),
      throwsFormatException,
    );
    expect(
      () => RustDeskHarnessShareService.validateWebClientUrl('file:///tmp/x'),
      throwsFormatException,
    );
  });

  test('留空时只读取 RustDesk 服务器地址并推导网页端', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_config_',
    );
    final File config = File(
      '${temporary.path}${Platform.pathSeparator}RustDesk2.toml',
    );
    await config.writeAsString(
      "rendezvous_server = 'relay.example.com:21116'\n"
      "password = 'must-not-be-read'\n",
    );
    addTearDown(() => temporary.delete(recursive: true));
    expect(
      await RustDeskHarnessShareService.discoverWebClientUrl(
        configFile: config,
      ),
      'https://relay.example.com/web',
    );
  });

  test('RustDesk 真实路径通过官方 get-id 读取设备 ID', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_test_',
    );
    final File executable = File(
      '${temporary.path}${Platform.pathSeparator}RustDesk.exe',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));

    final RustDeskHostInfo info = await RustDeskHarnessShareService.inspect(
      configuredExecutable: executable.path,
      runner: (String path, List<String> arguments) async {
        expect(path, executable.path);
        expect(arguments, const <String>['--get-id']);
        return ProcessResult(1, 0, '123456789', '');
      },
    );
    expect(info.available, isTrue);
    expect(info.id, '123456789');
    expect(info.message, '科米办公 ID：123456789');
  });

  test('启动 RustDesk 使用参数数组且不经过 shell', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_launch_',
    );
    final File executable = File(
      '${temporary.path}${Platform.pathSeparator}RustDesk.exe',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    String? launched;
    await RustDeskHarnessShareService.launchHost(
      executable.path,
      launcher: (String path, List<String> arguments) async {
        launched = path;
        expect(arguments, isEmpty);
      },
    );
    expect(launched, executable.path);
  });
}
