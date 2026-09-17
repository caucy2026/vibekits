import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_remote_access_settings.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_access_settings.dart';
import 'package:vibekits/features/dev_tools/domain/harness_simulator_target_runtime.dart';
import 'package:vibekits/features/dev_tools/domain/harness_system_ssh_service.dart';
import 'package:vibekits/features/dev_tools/domain/lan_mcp_tool_server.dart';
import 'package:vibekits/features/dev_tools/domain/rustdesk_harness_share_service.dart';

const _host = RustDeskHostInfo(
  executable: '/test/vibekits-harness-relay',
  id: '1554650784',
  available: true,
  callable: true,
  rendezvousOnline: true,
  registrationKeyConfirmed: true,
  state: 'registered',
  message: 'registered',
);

const _sshEnabled = HarnessSystemSshSnapshot(
  supported: true,
  enabled: true,
  endpoint: '192.168.3.10:22',
  username: 'newlink',
);

void main() {
  test('错误诊断不会在授权开关关闭时伪装成仿真已开启', () {
    HarnessSimulatorAccessSettings.setEnabled(false);
    const snapshot = HarnessSimulatorTargetSnapshot(
      phase: HarnessSimulatorTargetPhase.error,
      message: '仿真机启动失败：测试错误',
    );

    expect(snapshot.enabled, isFalse);

    HarnessSimulatorAccessSettings.setEnabled(true);
    expect(snapshot.enabled, isTrue);
  });

  setUp(() {
    HarnessRemoteAccessSettings.setEnabled(false);
    HarnessSimulatorAccessSettings.setEnabled(false);
  });

  test('启用后沿用同一 routingId 并在关闭时撤销端点', () async {
    final values = <String, String>{};
    var endpointClosed = false;
    var hostStopped = false;
    var sshEnabled = false;
    var sshKeysRevoked = false;
    final sshChanges = <bool>[];
    final nativeGateValues = <bool>[];
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      ),
      inspectHost: () async => _host,
      startHost: () async => _host,
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async => endpointClosed = true,
      ),
      stopHost: () async => hostStopped = true,
      setNativeGate: (_, enabled) async => nativeGateValues.add(enabled),
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => HarnessSystemSshSnapshot(
        supported: true,
        enabled: sshEnabled,
        endpoint: sshEnabled ? '192.168.3.10:22' : '',
        username: 'newlink',
      ),
      revokeSshKeys: () async => sshKeysRevoked = true,
      setSsh: (enabled) async {
        sshEnabled = enabled;
        sshChanges.add(enabled);
        return HarnessSystemSshSnapshot(
          supported: true,
          enabled: enabled,
          endpoint: enabled ? '192.168.3.10:22' : '',
          username: 'newlink',
          changed: true,
        );
      },
    );

    await runtime.enable();
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);
    expect(runtime.latest.routingId, _host.id);
    expect(runtime.latest.endpoint, '127.0.0.1:32148');
    expect(runtime.latest.sshEndpoint, '192.168.3.10:22');
    expect(runtime.latest.sshUsername, 'newlink');
    expect(runtime.latest.message, contains('本机 ID'));
    expect(HarnessSimulatorAccessSettings.enabled, isTrue);
    expect(nativeGateValues, <bool>[true]);

    await runtime.disable();
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.disabled);
    expect(endpointClosed, isTrue);
    expect(hostStopped, isTrue);
    expect(HarnessSimulatorAccessSettings.enabled, isFalse);
    expect(nativeGateValues, <bool>[true, false]);
    expect(sshChanges, <bool>[true, false]);
    expect(sshKeysRevoked, isTrue);
  });

  test('固定回环端点就绪后才开放原生仿真隧道', () async {
    final order = <String>[];
    var controlClosed = false;
    var mcpClosed = false;
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (_) async => null,
        write: (_, _) async {},
      ),
      inspectHost: () async => _host,
      startHost: () async => _host,
      startEndpoint: () async {
        order.add('endpoint-listening');
        return HarnessSimulatorEndpointLease(
          port: HarnessSimulatorTargetRuntime.remotePort,
          close: () async => controlClosed = true,
        );
      },
      startMcpEndpoint: () async {
        order.add('mcp-listening');
        return HarnessSimulatorEndpointLease(
          port: RustDeskHarnessShareService.simulatorRemotePort,
          close: () async => mcpClosed = true,
        );
      },
      stopHost: () async {},
      setNativeGate: (_, enabled) async {
        if (enabled) order.add('native-gate-open');
      },
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
    );

    await runtime.enable();

    expect(order, <String>[
      'endpoint-listening',
      'mcp-listening',
      'native-gate-open',
    ]);
    await runtime.disable();
    expect(controlClosed, isTrue);
    expect(mcpClosed, isTrue);
  });

  test('普通远程协助仍打开时关闭仿真机不会误停共享网络进程', () async {
    var hostStopped = false;
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (_) async => null,
        write: (_, _) async {},
      ),
      inspectHost: () async => _host,
      startHost: () async => _host,
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async {},
      ),
      stopHost: () async => hostStopped = true,
      setNativeGate: (_, _) async {},
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
    );
    HarnessRemoteAccessSettings.setEnabled(true);

    await runtime.enable();
    await runtime.disable();
    expect(hostStopped, isFalse);
  });

  test('只把固定 32148 控制端点的真实连接显示为仿真机已连接', () async {
    var connected = false;
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (_) async => null,
        write: (_, _) async {},
      ),
      inspectHost: () async => _host,
      startHost: () async => _host,
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async {},
      ),
      stopHost: () async {},
      setNativeGate: (_, _) async {},
      listConnections: (_) async => connected
          ? const <RustDeskHarnessIncomingConnection>[
              RustDeskHarnessIncomingConnection(
                connectionId: 23,
                peerId: '238638760',
                peerName: 'Windows 58',
                authorized: true,
                disconnected: false,
                portForward: '127.0.0.1:32148',
              ),
            ]
          : const <RustDeskHarnessIncomingConnection>[],
      connectionPollInterval: const Duration(milliseconds: 5),
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
    );

    await runtime.enable();
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);

    connected = true;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.connected);
    expect(runtime.latest.message, contains('238638760'));

    connected = false;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);
    await runtime.disable();
  });

  test('真实 MCP 端点固定回环监听且关闭后不可访问', () async {
    final server = await LanMcpToolServer.start(
      bindAddress: InternetAddress.loopbackIPv4,
      port: 0,
    );
    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.postUrl(server.loopbackEndpoint);
    request.write('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);

    final port = server.port;
    await server.close();
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });

  test('启动恢复同时验证固定 MCP 与系统 SSH', () async {
    final values = <String, String>{
      'harness-simulator-v1-enabled': 'true',
      'harness-simulator-v1-relay-fingerprint': 'sha256:current',
      'harness-simulator-v1-relay-executable': File(
        _host.executable,
      ).absolute.path,
    };
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      ),
      inspectHost: () async => _host,
      startHost: () async => _host,
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async {},
      ),
      stopHost: () async {},
      setNativeGate: (_, _) async {},
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
    );

    await runtime.restore();

    expect(HarnessSimulatorAccessSettings.enabled, isTrue);
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);
    expect(runtime.latest.message, contains('本机 ID'));
    await runtime.disable();
  });

  test('升级后恢复会替换仍在运行的旧中继再开放端点', () async {
    final values = <String, String>{
      'harness-simulator-v1-enabled': 'true',
      'harness-simulator-v1-relay-fingerprint': 'sha256:new-relay',
      'harness-simulator-v1-relay-executable': '/old/Vibekits.app/relay',
    };
    var oldHostRunning = true;
    var stopCount = 0;
    var startCount = 0;
    RustDeskHostInfo inspect() => RustDeskHostInfo(
      executable: _host.executable,
      id: _host.id,
      available: true,
      callable: oldHostRunning,
      rendezvousOnline: oldHostRunning,
      registrationKeyConfirmed: oldHostRunning,
      state: oldHostRunning ? 'registered' : 'offline',
      message: oldHostRunning ? 'registered' : 'offline',
    );
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      ),
      inspectHost: () async => inspect(),
      startHost: () async {
        startCount++;
        oldHostRunning = true;
        return inspect();
      },
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async {},
      ),
      stopHost: () async {
        stopCount++;
        oldHostRunning = false;
      },
      setNativeGate: (_, _) async {},
      relayFingerprint: (_) async => 'sha256:new-relay',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
      hostRestartTimeout: const Duration(milliseconds: 200),
    );

    await runtime.restore();

    expect(stopCount, 1);
    expect(startCount, 1);
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);
    expect(
      values['harness-simulator-v1-relay-fingerprint'],
      'sha256:new-relay',
    );
    expect(
      values['harness-simulator-v1-relay-executable'],
      File(_host.executable).absolute.path,
    );
    await runtime.disable();
  });

  test('升级后首次中继启动失败仍保留授权并自动重试恢复', () async {
    final values = <String, String>{
      'harness-simulator-v1-enabled': 'true',
      'harness-simulator-v1-relay-fingerprint': 'sha256:current',
      'harness-simulator-v1-relay-executable': File(_host.executable).absolute.path,
    };
    var inspections = 0;
    final nativeGateValues = <bool>[];
    final runtime = HarnessSimulatorTargetRuntime(
      settings: HarnessSimulatorAccessSettings(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      ),
      inspectHost: () async {
        inspections++;
        if (inspections == 1) throw StateError('旧中继尚未退出');
        return _host;
      },
      startHost: () async => _host,
      startEndpoint: () async => HarnessSimulatorEndpointLease(
        port: HarnessSimulatorTargetRuntime.remotePort,
        close: () async {},
      ),
      stopHost: () async {},
      setNativeGate: (_, enabled) async => nativeGateValues.add(enabled),
      relayFingerprint: (_) async => 'sha256:current',
      inspectSsh: () async => _sshEnabled,
      revokeSshKeys: () async {},
      restoreRetryDelay: const Duration(milliseconds: 5),
    );

    await runtime.restore();
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.error);
    expect(values['harness-simulator-v1-enabled'], 'true');
    expect(HarnessSimulatorAccessSettings.enabled, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(inspections, greaterThanOrEqualTo(2));
    expect(runtime.latest.phase, HarnessSimulatorTargetPhase.ready);
    expect(nativeGateValues, contains(true));
    await runtime.disable();
    expect(values['harness-simulator-v1-enabled'], 'false');
  });
}
