import 'dart:async';
import 'dart:io';

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
    );

    final connected = await controller.connect('9464730211');
    expect(connected['connected'], isTrue);
    expect(connected['routingId'], '9464730211');
    expect(connected['toolCount'], 2);
    expect(connected, isNot(contains('localPort')));
    expect(process.readyWaits, 1);

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
    );

    await controller.connect('4456560334');
    expect(events, containsAll(<String>['mcp:43212', 'ready']));
    await controller.closeAll();
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
  Future<List<Map<String, Object?>>> initializeAndList(int localPort) async {
    events.add('mcp:$localPort');
    return <Map<String, Object?>>[
      <String, Object?>{'name': 'vibekits.device.processes'},
    ];
  }

  @override
  Future<Map<String, Object?>> call(
    int localPort,
    String toolId,
    Map<String, Object?> arguments,
  ) async => <String, Object?>{};
}

final class _FakeMcpClient implements HarnessSimulatorMcpClient {
  int? lastPort;

  @override
  Future<List<Map<String, Object?>>> initializeAndList(int localPort) async {
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
    Map<String, Object?> arguments,
  ) async {
    lastPort = localPort;
    return <String, Object?>{'called': toolId, 'arguments': arguments};
  }
}
