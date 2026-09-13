import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_controller.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

void main() {
  test('只凭 ID 建立连接、读取目录、调用工具并可靠断开', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'vibekits_simulator_controller_',
    );
    final executable = File('${temporary.path}/relay');
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));

    final process = _FakeManagedProcess();
    final mcp = _FakeMcpClient();
    final controller = HarnessSimulatorController(
      resolveHost: () async => RustDeskHostInfo(
        executable: executable.path,
        id: '1554650784',
        available: true,
        callable: true,
        message: 'ready',
      ),
      allocatePort: () async => 43210,
      openTunnel: (path, routingId, localPort, forceRelay) =>
          RustDeskHarnessShareService.openSimulatorTunnel(
            path,
            routingId: routingId,
            localPort: localPort,
            forceRelay: forceRelay,
            launcher: (actualPath, arguments) async {
              expect(actualPath, executable.path);
              expect(arguments, <String>[
                '--vibekits-harness-tunnel',
                '9464730211',
                '43210',
                '127.0.0.1',
                '32147',
              ]);
              return process;
            },
          ),
      mcpClient: mcp,
      enableSshBootstrap: false,
    );
    final statusChanges = <Map<String, Object?>>[];
    final statusSubscription = controller.changes.listen(statusChanges.add);
    addTearDown(statusSubscription.cancel);

    final connected = await controller.connect('9464730211');
    expect(connected['connected'], isTrue);
    expect(connected['routingId'], '9464730211');
    expect(connected['toolCount'], 2);
    expect(connected, isNot(contains('localPort')));
    expect(process.readyWaits, 1);
    expect(statusChanges.last['connected'], isTrue);

    final catalog = controller.catalog('9464730211');
    expect(
      catalog.map((tool) => tool['name']),
      contains('vibekits.system.resources'),
    );
    final result = await controller.call(
      '9464730211',
      'vibekits.system.resources',
      const <String, Object?>{'samples': 3},
    );
    expect(result['called'], 'vibekits.system.resources');
    expect(mcp.lastPort, 43210);

    final disconnected = await controller.disconnect('9464730211');
    expect(disconnected['connected'], isFalse);
    expect(process.terminated, isTrue);
    expect(controller.status('9464730211')['connected'], isFalse);
    expect(statusChanges.last['connected'], isFalse);
  });

  test('强制中继只改变内部传输且不要求用户提供端口或凭据', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'vibekits_simulator_relay_',
    );
    final executable = File('${temporary.path}/relay');
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    final process = _FakeManagedProcess();
    final controller = HarnessSimulatorController(
      resolveHost: () async => RustDeskHostInfo(
        executable: executable.path,
        id: '1554650784',
        available: true,
        callable: true,
        message: 'ready',
      ),
      allocatePort: () async => 43211,
      openTunnel: (path, routingId, localPort, forceRelay) =>
          RustDeskHarnessShareService.openSimulatorTunnel(
            path,
            routingId: routingId,
            localPort: localPort,
            forceRelay: forceRelay,
            launcher: (_, arguments) async {
              expect(arguments.last, '--relay');
              return process;
            },
          ),
      mcpClient: _FakeMcpClient(),
      enableSshBootstrap: false,
    );

    final result = await controller.connect('9464730211', forceRelay: true);
    expect(result['transport'], 'relay');
    expect(
      result.keys,
      isNot(containsAll(<String>['host', 'port', 'username'])),
    );
    await controller.closeAll();
    expect(process.terminated, isTrue);
  });

  test('拒绝无效 ID、未连接调用和远端未公开工具', () async {
    final controller = HarnessSimulatorController(
      resolveHost: () async => const RustDeskHostInfo(
        executable: '',
        id: '',
        available: false,
        message: 'unused',
      ),
    );
    expect(
      () => controller.status('192.168.3.75'),
      throwsA(
        isA<HarnessSimulatorControllerException>().having(
          (error) => error.code,
          'code',
          'invalid_id',
        ),
      ),
    );
    expect(
      () => controller.catalog('9464730211'),
      throwsA(
        isA<HarnessSimulatorControllerException>().having(
          (error) => error.code,
          'code',
          'not_connected',
        ),
      ),
    );
  });

  test('首个真实 MCP 请求直接激活需求驱动的 RustDesk 转发', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'vibekits_simulator_activation_',
    );
    final executable = File('${temporary.path}/relay');
    await executable.writeAsBytes(const <int>[0]);
    addTearDown(() => temporary.delete(recursive: true));
    final events = <String>[];
    final process = _FakeManagedProcess(onReady: () => events.add('ready'));
    final controller = HarnessSimulatorController(
      resolveHost: () async => RustDeskHostInfo(
        executable: executable.path,
        id: '1554650784',
        available: true,
        callable: true,
        message: 'ready',
      ),
      allocatePort: () async => 43212,
      openTunnel: (_, _, _, _) async => RustDeskHarnessShareService.openTunnel(
        executable.path,
        routingId: '4456560334',
        localPort: 43212,
        remotePort: RustDeskHarnessShareService.simulatorRemotePort,
        launcher: (_, _) async => process,
      ),
      mcpClient: _OrderedMcpClient(events),
      enableSshBootstrap: false,
    );

    await controller.connect('4456560334');
    expect(events, containsAll(<String>['mcp:43212', 'ready']));
    await controller.closeAll();
  });

  test('仅凭 ID 完成首次公钥授权、主机指纹校验、命令和文件上传', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'vibekits_simulator_ssh_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/relay');
    await executable.writeAsBytes(const <int>[0]);
    final upload = File('${temporary.path}/Demo.zip');
    await upload.writeAsString('signed-test-candidate');
    final expectedSha = (await sha256.bind(upload.openRead()).first).toString();
    final mcpTunnelProcess = _FakeManagedProcess();
    final sshTunnelProcess = _FakeManagedProcess();
    final mcp = _SshBootstrapMcpClient();
    final ports = <int>[43213, 43214];
    final executed = <String>[];
    Future<ProcessResult> processRunner(
      String executablePath,
      List<String> arguments,
    ) async {
      executed.add('$executablePath ${arguments.join(' ')}');
      if ((executablePath.endsWith('ssh-keygen') ||
              executablePath.endsWith('ssh-keygen.exe')) &&
          arguments.contains('-f')) {
        final keyPath = arguments[arguments.indexOf('-f') + 1];
        await File(keyPath).writeAsString('private-key');
        final key = base64Encode(List<int>.generate(48, (index) => index + 1));
        await File('$keyPath.pub').writeAsString('ssh-ed25519 $key controller');
        return ProcessResult(1, 0, '', '');
      }
      if ((executablePath.endsWith('/ssh') ||
              executablePath.endsWith('ssh.exe')) &&
          arguments.contains('StrictHostKeyChecking=accept-new')) {
        final knownHostsOption = arguments.firstWhere(
          (argument) => argument.startsWith('UserKnownHostsFile='),
        );
        final rawKnownHostsPath = knownHostsOption.substring(
          'UserKnownHostsFile='.length,
        );
        final knownHostsPath =
            rawKnownHostsPath.startsWith('"') && rawKnownHostsPath.endsWith('"')
            ? rawKnownHostsPath.substring(1, rawKnownHostsPath.length - 1)
            : rawKnownHostsPath;
        await File(
          knownHostsPath,
        ).writeAsString('[127.0.0.1]:43214 ssh-ed25519 AAAATESTHOSTKEY\n');
        return ProcessResult(
          1,
          255,
          '',
          'authentication intentionally skipped',
        );
      }
      if ((executablePath.endsWith('ssh-keygen') ||
              executablePath.endsWith('ssh-keygen.exe')) &&
          arguments.contains('-lf')) {
        return ProcessResult(
          1,
          0,
          '256 SHA256:verifiedHost target (ED25519)',
          '',
        );
      }
      if (executablePath.endsWith('scp') ||
          executablePath.endsWith('scp.exe')) {
        return ProcessResult(1, 0, '', '');
      }
      final command = arguments.isEmpty ? '' : arguments.last;
      if (command == 'hostname') {
        return ProcessResult(1, 0, 'target-mac\n', '');
      }
      if (command.startsWith('shasum -a 256')) {
        return ProcessResult(1, 0, '$expectedSha  Demo.zip\n', '');
      }
      if (command == 'uname -a') {
        return ProcessResult(1, 0, 'Darwin target-mac arm64\n', '');
      }
      return ProcessResult(1, 0, '', '');
    }

    final controller = HarnessSimulatorController(
      resolveHost: () async => RustDeskHostInfo(
        executable: executable.path,
        id: '1554650784',
        available: true,
        callable: true,
        message: 'ready',
      ),
      allocatePort: () async => ports.removeAt(0),
      openTunnel: (_, _, _, _) async => RustDeskHarnessShareService.openTunnel(
        executable.path,
        routingId: '4456560334',
        localPort: 43213,
        remotePort: RustDeskHarnessShareService.simulatorRemotePort,
        launcher: (_, _) async => mcpTunnelProcess,
      ),
      openSshTunnel: (_, _, localPort, _) async {
        expect(localPort, 43214);
        return RustDeskHarnessShareService.openTunnel(
          executable.path,
          routingId: '4456560334',
          localPort: localPort,
          remotePort: 22,
          launcher: (_, arguments) async {
            expect(arguments, contains('22'));
            return sshTunnelProcess;
          },
        );
      },
      mcpClient: mcp,
      processRunner: processRunner,
      sshKeyRoot: Directory('${temporary.path}/keys with space'),
    );

    final connected = await controller.connect('4456560334');
    expect(connected['sshReady'], isTrue);
    expect(connected['sshUsername'], 'remote-user');
    expect(connected['sshHostKeyFingerprint'], 'SHA256:verifiedHost');
    expect(connected['hostname'], 'target-mac');
    expect(mcp.authorizedPeerId, '1554650784');
    expect(mcp.authorizedPublicKey, startsWith('ssh-ed25519 '));
    expect(mcp.callerIds, isNotEmpty);
    expect(mcp.callerIds, everyElement('1554650784'));
    expect(
      executed.any(
        (line) =>
            line.contains('StrictHostKeyChecking=accept-new') &&
            line.contains('UserKnownHostsFile="') &&
            line.contains('KexAlgorithms=curve25519-sha256') &&
            line.contains('HostKeyAlgorithms=ssh-ed25519'),
      ),
      isTrue,
    );

    final command = await controller.runSshCommand('4456560334', 'uname -a');
    expect(command['ok'], isTrue);
    expect(command['stdout'], contains('target-mac arm64'));
    final uploaded = await controller.uploadFile('4456560334', upload.path);
    expect(uploaded['uploaded'], isTrue);
    expect(uploaded['sha256'], expectedSha);
    expect(
      executed.any(
        (line) =>
            line.contains('StrictHostKeyChecking=yes') &&
            line.contains('UserKnownHostsFile='),
      ),
      isTrue,
    );
    await controller.disconnect('4456560334');
    expect(mcpTunnelProcess.terminated, isTrue);
    expect(sshTunnelProcess.terminated, isTrue);
  });
}

final class _FakeManagedProcess implements RustDeskManagedProcess {
  _FakeManagedProcess({this.onReady});

  final void Function()? onReady;
  final Completer<int> _exit = Completer<int>();
  int readyWaits = 0;
  bool terminated = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool terminate() {
    terminated = true;
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  @override
  Future<void> waitUntilListening({Duration? timeout}) async {}

  @override
  Future<void> waitUntilReady({Duration? timeout}) async {
    readyWaits++;
    onReady?.call();
  }
}

final class _OrderedMcpClient implements HarnessSimulatorMcpClient {
  _OrderedMcpClient(this.events);

  final List<String> events;

  @override
  Future<List<Map<String, Object?>>> initializeAndList(
    int localPort, {
    String callerId = '',
  }) async {
    events.add('mcp:$localPort');
    return <Map<String, Object?>>[
      <String, Object?>{'name': 'vibekits.device.processes'},
    ];
  }

  @override
  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments, {
    String callerId = '',
  }) async => <String, Object?>{};
}

final class _FakeMcpClient implements HarnessSimulatorMcpClient {
  int? lastPort;

  @override
  Future<List<Map<String, Object?>>> initializeAndList(
    int localPort, {
    String callerId = '',
  }) async {
    lastPort = localPort;
    return <Map<String, Object?>>[
      <String, Object?>{'name': 'vibekits.system.resources'},
      <String, Object?>{'name': 'vibekits.adb.logcat'},
    ];
  }

  @override
  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments, {
    String callerId = '',
  }) async {
    lastPort = localPort;
    return <String, Object?>{'called': toolId, 'arguments': arguments};
  }
}

final class _SshBootstrapMcpClient implements HarnessSimulatorMcpClient {
  String? authorizedPeerId;
  String? authorizedPublicKey;
  final List<String> callerIds = <String>[];

  @override
  Future<List<Map<String, Object?>>> initializeAndList(
    int localPort, {
    String callerId = '',
  }) async {
    callerIds.add(callerId);
    return <Map<String, Object?>>[
      <String, Object?>{'name': 'vibekits.device.ssh_identity'},
      <String, Object?>{'name': 'vibekits.device.ssh_key_status'},
      <String, Object?>{'name': 'vibekits.device.ssh_authorize'},
      <String, Object?>{'name': 'vibekits.device.processes'},
    ];
  }

  @override
  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments, {
    String callerId = '',
  }) async {
    callerIds.add(callerId);
    final data = switch (toolId) {
      'vibekits.device.ssh_identity' => <String, Object?>{
        'username': 'remote-user',
        'hostKeyFingerprint': 'SHA256:verifiedHost',
        'remotePort': 22,
      },
      'vibekits.device.ssh_key_status' => <String, Object?>{
        'authorized': false,
      },
      'vibekits.device.ssh_authorize' => <String, Object?>{'authorized': true},
      _ => <String, Object?>{},
    };
    if (toolId == 'vibekits.device.ssh_authorize') {
      authorizedPeerId = '${arguments['peerId'] ?? ''}';
      authorizedPublicKey = '${arguments['publicKey'] ?? ''}';
    }
    return <String, Object?>{
      'structuredContent': <String, Object?>{'ok': true, 'data': data},
    };
  }
}
