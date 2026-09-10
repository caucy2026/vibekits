import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

final class _FakeManagedProcess implements RustDeskManagedProcess {
  _FakeManagedProcess({this.readyError});
  final _exit = Completer<int>();
  final Object? readyError;
  bool terminated = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> waitUntilListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (readyError != null) throw readyError!;
  }

  @override
  bool terminate() {
    terminated = true;
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }
}

void main() {
  test('macOS only uses the VibeKits-bundled headless Harness helper', () {
    if (!Platform.isMacOS) return;
    final candidates = RustDeskHarnessShareService.candidateExecutables(
      configured: '/Applications/KEMI远程办公.app/Contents/MacOS/KEMI远程办公',
    );
    expect(candidates.first, endsWith('/vibekits-harness-relay'));
    expect(
      candidates,
      isNot(contains('/Applications/KEMI远程办公.app/Contents/MacOS/KEMI远程办公')),
    );
    expect(
      candidates,
      isNot(
        contains(
          '/Applications/KEMI远程办公.app/Contents/MacOS/'
          'vibekits-harness-relay',
        ),
      ),
    );
  });

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

  test('仅显示中继服务器确认后的独立 Harness 设备 ID', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_test_',
    );
    final File executable = File(
      '${temporary.path}${Platform.pathSeparator}'
      '${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));

    final RustDeskHostInfo info = await RustDeskHarnessShareService.inspect(
      configuredExecutable: executable.path,
      runner: (String path, List<String> arguments) async {
        expect(path, executable.path);
        expect(arguments, const <String>['--vibekits-harness-status']);
        return ProcessResult(
          1,
          0,
          '{"routingId":"1234567890","callable":true,'
              '"rendezvousOnline":true,'
              '"registrationKeyConfirmed":true,"state":"registered"}',
          '',
        );
      },
    );
    expect(info.available, isTrue);
    expect(info.id, '1234567890');
    expect(info.callable, isTrue);
    expect(info.message, contains('中继服务已确认'));
  });

  test('候选 ID 未获服务器确认时不可呼叫', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_pending_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    final RustDeskHostInfo info = await RustDeskHarnessShareService.inspect(
      configuredExecutable: executable.path,
      runner: (_, _) async => ProcessResult(
        1,
        0,
        '{"routingId":"1234567890","callable":false,'
            '"rendezvousOnline":true,'
            '"registrationKeyConfirmed":false,'
            '"state":"registration_pending"}',
        '',
      ),
    );
    expect(info.callable, isFalse);
    expect(info.message, contains('正在向中继服务器注册'));
  });

  test('远程协助关闭时仍显示持久 ID 但绝不标记为可呼叫', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_dormant_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));

    final RustDeskHostInfo info = await RustDeskHarnessShareService.inspect(
      configuredExecutable: executable.path,
      runner: (_, arguments) async => switch (arguments.single) {
        '--vibekits-harness-status' => ProcessResult(
          1,
          0,
          '{"routingId":null,"callable":false,'
              '"rendezvousOnline":false,'
              '"registrationKeyConfirmed":false,"state":"offline"}',
          '',
        ),
        '--vibekits-harness-get-id' => ProcessResult(2, 0, '1554650784\n', ''),
        _ => throw StateError('unexpected command'),
      },
    );

    expect(info.id, '1554650784');
    expect(info.callable, isFalse);
    expect(info.message, contains('远程协助未打开'));
  });

  test('启动包内传输引擎使用参数数组且不经过 shell', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_launch_',
    );
    final File executable = File(
      '${temporary.path}${Platform.pathSeparator}'
      '${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    String? launched;
    await RustDeskHarnessShareService.launchHost(
      executable.path,
      launcher: (String path, List<String> arguments) async {
        launched = path;
        expect(arguments, const <String>['--vibekits-harness-service']);
      },
    );
    expect(launched, executable.path);
  });

  test('恢复远程协助会启动中继并等待到真实可呼叫状态', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_rustdesk_resume_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    int inspections = 0;
    bool launched = false;
    final host = await RustDeskHarnessShareService.ensureHostAvailable(
      configuredExecutable: executable.path,
      timeout: const Duration(seconds: 1),
      runner: (_, arguments) async {
        if (arguments.single == '--vibekits-harness-get-id') {
          return ProcessResult(3, 0, '1554650784\n', '');
        }
        expect(arguments, const <String>['--vibekits-harness-status']);
        inspections += 1;
        return ProcessResult(
          1,
          0,
          inspections == 1
              ? '{"routingId":null,"callable":false,'
                    '"rendezvousOnline":false,'
                    '"registrationKeyConfirmed":false,"state":"offline"}'
              : '{"routingId":"1554650784","callable":true,'
                    '"rendezvousOnline":true,'
                    '"registrationKeyConfirmed":true,"state":"registered"}',
          '',
        );
      },
      launcher: (path, arguments) async {
        launched = true;
        expect(path, executable.path);
        expect(arguments, const <String>['--vibekits-harness-service']);
      },
    );
    expect(launched, isTrue);
    expect(inspections, 2);
    expect(host.callable, isTrue);
    expect(host.id, '1554650784');
  });

  test('Harness 隧道使用独立数字 ID 和固定回环目标', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_harness_tunnel_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    await RustDeskHarnessShareService.launchTunnel(
      executable.path,
      routingId: '1554650784',
      localPort: 32147,
      forceRelay: true,
      launcher: (String path, List<String> arguments) async {
        expect(path, executable.path);
        expect(arguments, const <String>[
          '--vibekits-harness-tunnel',
          '1554650784',
          '32147',
          '127.0.0.1',
          '32146',
          '--relay',
        ]);
      },
    );
  });

  test('受管 Harness 隧道可由 UI 可靠断开且幂等', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_harness_managed_tunnel_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    final process = _FakeManagedProcess();
    final lease = await RustDeskHarnessShareService.openTunnel(
      executable.path,
      routingId: '1554650784',
      localPort: 32147,
      launcher: (path, arguments) async {
        expect(path, executable.path);
        expect(arguments, const <String>[
          '--vibekits-harness-tunnel',
          '1554650784',
          '32147',
          '127.0.0.1',
          '32146',
        ]);
        return process;
      },
    );
    expect(lease.closed, isFalse);
    await lease.close();
    await lease.close();
    expect(lease.closed, isTrue);
    expect(process.terminated, isTrue);
    expect(await lease.exitCode, 0);
  });

  test('受管 Harness 隧道区分监听就绪与远端传输就绪', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_harness_failed_tunnel_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    final process = _FakeManagedProcess(
      readyError: StateError('HARNESS_TRANSPORT_transport_connect_timeout'),
    );

    final lease = await RustDeskHarnessShareService.openTunnel(
      executable.path,
      routingId: '1554650784',
      localPort: 32147,
      launcher: (_, _) async => process,
    );
    await expectLater(
      lease.waitUntilConnected(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('transport_connect_timeout'),
        ),
      ),
    );
    await lease.close();
    expect(process.terminated, isTrue);
  });

  test('Harness 隧道拒绝桌面 ID 文本和特权端口', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits_harness_tunnel_invalid_',
    );
    final File executable = File(
      '${temporary.path}/${Platform.isWindows ? 'vibekits-harness-relay.exe' : 'vibekits-harness-relay'}',
    );
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    expect(
      () => RustDeskHarnessShareService.launchTunnel(
        executable.path,
        routingId: 'VH-ABC',
        localPort: 32147,
      ),
      throwsFormatException,
    );
    expect(
      () => RustDeskHarnessShareService.launchTunnel(
        executable.path,
        routingId: '1554650784',
        localPort: 80,
      ),
      throwsFormatException,
    );
  });

  test('读取等待授权连接并按 connectionId 明确允许', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> runner(String _, List<String> arguments) async {
      calls.add(arguments);
      return ProcessResult(
        1,
        0,
        '{"ok":true,"state":"awaiting_approval","connections":['
            '{"connectionId":17,"peerId":"1554000001",'
            '"peerName":"Harness B","authorized":false,'
            '"disconnected":false}]}',
        '',
      );
    }

    final connections = await RustDeskHarnessShareService.connections(
      '/Harness',
      runner: runner,
    );
    expect(connections.single.peerName, 'Harness B');
    expect(connections.single.authorized, isFalse);
    await RustDeskHarnessShareService.decideConnection(
      '/Harness',
      connectionId: 17,
      allow: true,
      runner: runner,
    );
    expect(calls, [
      ['--vibekits-harness-connections'],
      ['--vibekits-harness-authorize', '17'],
    ]);
  });
}
