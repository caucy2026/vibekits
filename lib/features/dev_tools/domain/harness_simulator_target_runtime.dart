import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'harness_remote_access_settings.dart';
import 'harness_simulator_access_settings.dart';
import 'harness_system_ssh_service.dart';
import 'lan_mcp_tool_server.dart';
import 'simulator_control_server.dart';
import 'rustdesk_harness_share_service.dart';

enum HarnessSimulatorTargetPhase { disabled, starting, ready, connected, error }

final class HarnessSimulatorTargetSnapshot {
  const HarnessSimulatorTargetSnapshot({
    required this.phase,
    this.routingId = '',
    this.endpoint = '',
    this.message = '',
    this.sshEndpoint = '',
    this.sshUsername = '',
  });

  final HarnessSimulatorTargetPhase phase;
  final String routingId;
  final String endpoint;
  final String message;
  final String sshEndpoint;
  final String sshUsername;

  /// Whether the user has explicitly enabled simulator access.
  ///
  /// Runtime diagnostics may remain in [phase]/[message] after a failed start,
  /// but they must not make the main workspace look as if access is enabled.
  bool get enabled => HarnessSimulatorAccessSettings.enabled;
  bool get ready =>
      phase == HarnessSimulatorTargetPhase.ready ||
      phase == HarnessSimulatorTargetPhase.connected;
}

final class HarnessSimulatorEndpointLease {
  const HarnessSimulatorEndpointLease({
    required this.port,
    required this.close,
  });

  final int port;
  final Future<void> Function() close;
}

typedef HarnessSimulatorHostInspector = Future<RustDeskHostInfo> Function();
typedef HarnessSimulatorHostStarter = Future<RustDeskHostInfo> Function();
typedef HarnessSimulatorEndpointStarter =
    Future<HarnessSimulatorEndpointLease> Function();
typedef HarnessSimulatorHostStopper = Future<void> Function();
typedef HarnessSimulatorNativeGateSetter =
    Future<void> Function(String executable, bool enabled);
typedef HarnessSimulatorConnectionLister =
    Future<List<RustDeskHarnessIncomingConnection>> Function(String executable);
typedef HarnessSimulatorRelayFingerprintLoader =
    Future<String> Function(String executable);
typedef HarnessSimulatorSshInspector =
    Future<HarnessSystemSshSnapshot> Function();
typedef HarnessSimulatorSshSetter =
    Future<HarnessSystemSshSnapshot> Function(bool enabled);
typedef HarnessSimulatorSshKeyRevoker = Future<void> Function();

/// Owns the explicit "use this device as a simulator" authorization gate.
///
/// The independent simulator control endpoint is loopback-only. A caller
/// reaches it through the built-in P2P/HBBR byte-forward carrier, never by
/// opening remote-desktop UI or exposing SSH/HTTP directly to the network.
final class HarnessSimulatorTargetRuntime {
  HarnessSimulatorTargetRuntime({
    HarnessSimulatorAccessSettings? settings,
    HarnessSimulatorHostInspector? inspectHost,
    HarnessSimulatorHostStarter? startHost,
    HarnessSimulatorEndpointStarter? startEndpoint,
    HarnessSimulatorEndpointStarter? startMcpEndpoint,
    HarnessSimulatorHostStopper? stopHost,
    HarnessSimulatorNativeGateSetter? setNativeGate,
    HarnessSimulatorConnectionLister? listConnections,
    HarnessSimulatorRelayFingerprintLoader? relayFingerprint,
    HarnessSimulatorSshInspector? inspectSsh,
    HarnessSimulatorSshSetter? setSsh,
    HarnessSimulatorSshKeyRevoker? revokeSshKeys,
    Duration connectionPollInterval = const Duration(seconds: 1),
    Duration restoreRetryDelay = const Duration(seconds: 5),
  }) : _settings = settings ?? HarnessSimulatorAccessSettings(),
       _inspectHost =
           inspectHost ?? (() => RustDeskHarnessShareService.inspect()),
       _startHost =
           startHost ??
           (() => RustDeskHarnessShareService.ensureHostAvailable()),
       _startEndpoint = startEndpoint,
       _startMcpEndpoint = startMcpEndpoint,
       _stopHost = stopHost ?? RustDeskHarnessShareService.stopHost,
       _setNativeGate =
           setNativeGate ??
           ((executable, enabled) =>
               RustDeskHarnessShareService.setSimulatorAccess(
                 executable,
                 enabled: enabled,
               )),
       _listConnections =
           listConnections ??
           ((executable) =>
               RustDeskHarnessShareService.connections(executable)),
       _relayFingerprint = relayFingerprint ?? _loadRelayFingerprint,
       _inspectSsh = inspectSsh ?? HarnessSystemSshService.inspect,
       _setSsh = setSsh ?? HarnessSystemSshService.setEnabled,
       _revokeSshKeys =
           revokeSshKeys ??
           (() async {
             await HarnessSystemSshService.revokeAllManagedPublicKeys();
           }),
       _connectionPollInterval = connectionPollInterval,
       _restoreRetryDelay = restoreRetryDelay;

  static const int remotePort = SimulatorControlServer.portNumber;
  static final HarnessSimulatorTargetRuntime shared =
      HarnessSimulatorTargetRuntime();

  final HarnessSimulatorAccessSettings _settings;
  final HarnessSimulatorHostInspector _inspectHost;
  final HarnessSimulatorHostStarter _startHost;
  final HarnessSimulatorEndpointStarter? _startEndpoint;
  final HarnessSimulatorEndpointStarter? _startMcpEndpoint;
  final HarnessSimulatorHostStopper _stopHost;
  final HarnessSimulatorNativeGateSetter _setNativeGate;
  final HarnessSimulatorConnectionLister _listConnections;
  final HarnessSimulatorRelayFingerprintLoader _relayFingerprint;
  final HarnessSimulatorSshInspector _inspectSsh;
  final HarnessSimulatorSshSetter _setSsh;
  final HarnessSimulatorSshKeyRevoker _revokeSshKeys;
  final Duration _connectionPollInterval;
  final Duration _restoreRetryDelay;
  final StreamController<HarnessSimulatorTargetSnapshot> _changes =
      StreamController<HarnessSimulatorTargetSnapshot>.broadcast();

  HarnessSimulatorEndpointLease? _endpoint;
  HarnessSimulatorEndpointLease? _mcpEndpoint;
  Timer? _connectionPoller;
  Timer? _restoreRetry;
  int _restoreRetryCount = 0;
  String _hostExecutable = '';
  bool _pollingConnections = false;
  int _generation = 0;
  bool _changing = false;
  bool _sshChangedByRuntime = false;
  HarnessSimulatorTargetSnapshot _latest = const HarnessSimulatorTargetSnapshot(
    phase: HarnessSimulatorTargetPhase.disabled,
    message: '仿真机访问已关闭',
  );

  HarnessSimulatorTargetSnapshot get latest => _latest;
  Stream<HarnessSimulatorTargetSnapshot> get changes => _changes.stream;

  static Future<HarnessSimulatorEndpointLease> _startDefaultEndpoint(
    SimulatorCallerAuthorizer authorizeSimulatorCaller,
  ) async {
    final server = await SimulatorControlServer.start(
      bindAddress: InternetAddress.loopbackIPv4,
      port: remotePort,
      authorizeCaller: authorizeSimulatorCaller,
    );
    return HarnessSimulatorEndpointLease(
      port: server.port,
      close: server.close,
    );
  }

  static Future<HarnessSimulatorEndpointLease> _startDefaultMcpEndpoint(
    SimulatorCallerAuthorizer authorizeSimulatorCaller,
  ) async {
    final server = await LanMcpToolServer.start(
      bindAddress: InternetAddress.loopbackIPv4,
      port: RustDeskHarnessShareService.simulatorRemotePort,
      allowSimulatorUpdateUpload: true,
      trustSimulatorCallerAfterEnable: true,
      authorizeSimulatorCaller: authorizeSimulatorCaller,
    );
    return HarnessSimulatorEndpointLease(
      port: server.port,
      close: server.close,
    );
  }

  static Future<String> _loadRelayFingerprint(String executable) async {
    final digest = await sha256.bind(File(executable).openRead()).first;
    return 'sha256:$digest';
  }

  Future<void> restore() async {
    if (!await _settings.loadEnabled()) return;
    await _enable(persist: false);
    if (!_latest.ready && HarnessSimulatorAccessSettings.enabled) {
      _scheduleRestoreRetry();
    }
  }

  Future<void> enable({bool persist = true}) async {
    await _enable(persist: persist);
    if (!_latest.ready && HarnessSimulatorAccessSettings.enabled) {
      _scheduleRestoreRetry();
    }
  }

  void _scheduleRestoreRetry() {
    if (_restoreRetry != null) return;
    final int multiplier = 1 << _restoreRetryCount.clamp(0, 4);
    _restoreRetryCount++;
    final Duration delay = _restoreRetryDelay * multiplier;
    _restoreRetry = Timer(delay, () {
      _restoreRetry = null;
      unawaited(restore());
    });
  }

  void _clearRestoreRetry() {
    _restoreRetry?.cancel();
    _restoreRetry = null;
    _restoreRetryCount = 0;
  }

  Future<void> _enable({required bool persist}) async {
    if (_changing || _latest.ready) return;
    _changing = true;
    final generation = ++_generation;
    _publish(
      const HarnessSimulatorTargetSnapshot(
        phase: HarnessSimulatorTargetPhase.starting,
        message: '正在准备仿真机安全通道…',
      ),
    );
    RustDeskHostInfo? host;
    HarnessSystemSshSnapshot? ssh;
    try {
      if (persist) {
        await _settings.saveEnabled(true);
      } else {
        HarnessSimulatorAccessSettings.setEnabled(true);
      }
      host = await _inspectHost();
      if (!host.available) throw StateError(host.message);
      final relayExecutable = File(host.executable).absolute.path;
      final relayFingerprint = await _relayFingerprint(host.executable);
      // A stale relay can truthfully report itself callable while lacking the
      // current simulator protocol. Always pass the live process through the
      // carrier's protocol gate; it is idempotent for current relays and
      // performs a scoped takeover for old single-instance processes.
      host = await _startHost();
      if (Platform.isMacOS || Platform.isWindows) {
        ssh = await _inspectSsh();
        if (!ssh.supported) throw UnsupportedError(ssh.message);
        if (!ssh.enabled) {
          ssh = await _setSsh(true);
          _sshChangedByRuntime = ssh.changed;
        }
        if (!ssh.enabled) throw StateError('系统 SSH 端口 22 尚未就绪');
      }
      final customEndpoint = _startEndpoint;
      final endpoint = customEndpoint != null
          ? await customEndpoint()
          : await _startDefaultEndpoint(
              (callerId) =>
                  _isActiveSimulatorCaller(host!.executable, callerId),
            );
      final customMcpEndpoint = _startMcpEndpoint;
      // A custom control endpoint is treated as a complete test double unless
      // the test explicitly supplies the MCP endpoint as well. Production
      // always starts both fixed loopback endpoints before opening the gate.
      final mcpEndpoint = customMcpEndpoint != null
          ? await customMcpEndpoint()
          : customEndpoint == null
          ? await _startDefaultMcpEndpoint(
              (callerId) =>
                  _isActiveSimulatorCaller(host!.executable, callerId),
            )
          : null;
      if (generation != _generation) {
        await endpoint.close();
        await mcpEndpoint?.close();
        return;
      }
      _endpoint = endpoint;
      _mcpEndpoint = mcpEndpoint;
      // Do not advertise the native RustDesk tunnel gate until the fixed
      // loopback endpoint is actually listening. Otherwise a controller that
      // connects during startup receives an immediate connection refusal even
      // though the target UI is still preparing.
      await _setNativeGate(host.executable, true);
      await _settings.saveRelayFingerprint(relayFingerprint);
      await _settings.saveRelayExecutable(relayExecutable);
      _publish(
        HarnessSimulatorTargetSnapshot(
          phase: HarnessSimulatorTargetPhase.ready,
          routingId: host.id,
          endpoint: '127.0.0.1:${endpoint.port}',
          sshEndpoint: ssh?.endpoint ?? '',
          sshUsername: ssh?.username ?? '',
          message: '仿真机可连接 · 告知对方本机 ID 即可调试',
        ),
      );
      _clearRestoreRetry();
      _startConnectionPolling(generation, host.executable);
    } on Object catch (error) {
      _stopConnectionPolling();
      final endpoint = _endpoint;
      _endpoint = null;
      final mcpEndpoint = _mcpEndpoint;
      _mcpEndpoint = null;
      await endpoint?.close();
      await mcpEndpoint?.close();
      if (_sshChangedByRuntime) {
        try {
          await _setSsh(false);
        } on Object {
          // Preserve the startup error while reporting the failed simulator.
        }
        _sshChangedByRuntime = false;
      }
      if (host != null && host.executable.isNotEmpty) {
        try {
          await _setNativeGate(host.executable, false);
        } on Object {
          // Preserve the original startup error. The native gate is volatile
          // and resets to closed if the carrier exits.
        }
      }
      // A transient relay/SSH/startup failure must not revoke the user's
      // persistent simulator consent. Keep the native gate closed and retry.
      _publish(
        HarnessSimulatorTargetSnapshot(
          phase: HarnessSimulatorTargetPhase.error,
          message: '仿真机启动失败：$error',
        ),
      );
    } finally {
      _changing = false;
    }
  }

  Future<void> disable({bool persist = true}) async {
    if (_changing) return;
    _clearRestoreRetry();
    _changing = true;
    ++_generation;
    try {
      if (persist) {
        await _settings.saveEnabled(false);
      } else {
        HarnessSimulatorAccessSettings.setEnabled(false);
      }
      final endpoint = _endpoint;
      _endpoint = null;
      final mcpEndpoint = _mcpEndpoint;
      _mcpEndpoint = null;
      await endpoint?.close();
      await mcpEndpoint?.close();
      _stopConnectionPolling();
      await _revokeSshKeys();
      final host = await _inspectHost();
      if (host.available && host.executable.isNotEmpty) {
        await _setNativeGate(host.executable, false);
      }
      if (_sshChangedByRuntime) {
        await _setSsh(false);
        _sshChangedByRuntime = false;
      }
      if (!HarnessRemoteAccessSettings.enabled) await _stopHost();
      _publish(
        const HarnessSimulatorTargetSnapshot(
          phase: HarnessSimulatorTargetPhase.disabled,
          message: '仿真机访问已关闭',
        ),
      );
    } on Object catch (error) {
      _publish(
        HarnessSimulatorTargetSnapshot(
          phase: HarnessSimulatorTargetPhase.error,
          message: '仿真机关闭失败：$error',
        ),
      );
    } finally {
      _changing = false;
    }
  }

  void markConnected(String peerId) {
    if (!_latest.ready) return;
    final message = peerId.trim().isEmpty ? '仿真机已连接' : '仿真机已连接 · $peerId';
    if (_latest.phase == HarnessSimulatorTargetPhase.connected &&
        _latest.message == message) {
      return;
    }
    _publish(
      HarnessSimulatorTargetSnapshot(
        phase: HarnessSimulatorTargetPhase.connected,
        routingId: _latest.routingId,
        endpoint: _latest.endpoint,
        sshEndpoint: _latest.sshEndpoint,
        sshUsername: _latest.sshUsername,
        message: message,
      ),
    );
  }

  void markDisconnected() {
    if (_latest.phase != HarnessSimulatorTargetPhase.connected) return;
    _publish(
      HarnessSimulatorTargetSnapshot(
        phase: HarnessSimulatorTargetPhase.ready,
        routingId: _latest.routingId,
        endpoint: _latest.endpoint,
        sshEndpoint: _latest.sshEndpoint,
        sshUsername: _latest.sshUsername,
        message: '仿真机可连接 · 告知对方本机 ID 即可调试',
      ),
    );
  }

  void _publish(HarnessSimulatorTargetSnapshot value) {
    _latest = value;
    _changes.add(value);
  }

  void _startConnectionPolling(int generation, String executable) {
    _stopConnectionPolling();
    _hostExecutable = executable;
    unawaited(_pollConnections(generation));
    _connectionPoller = Timer.periodic(
      _connectionPollInterval,
      (_) => unawaited(_pollConnections(generation)),
    );
  }

  void _stopConnectionPolling() {
    _connectionPoller?.cancel();
    _connectionPoller = null;
    _hostExecutable = '';
  }

  Future<bool> _isActiveSimulatorCaller(
    String executable,
    String callerId,
  ) async {
    final connections = await _listConnections(executable);
    final bool active = connections.any(
      (connection) =>
          connection.peerId == callerId &&
          connection.authorized &&
          !connection.disconnected &&
          (connection.portForward == '127.0.0.1:$remotePort' ||
              connection.portForward == 'localhost:$remotePort' ||
              connection.portForward ==
                  '127.0.0.1:${RustDeskHarnessShareService.simulatorRemotePort}' ||
              connection.portForward ==
                  'localhost:${RustDeskHarnessShareService.simulatorRemotePort}'),
    );
    return active;
  }

  Future<void> _pollConnections(int generation) async {
    if (_pollingConnections ||
        generation != _generation ||
        _hostExecutable.isEmpty ||
        !_latest.ready) {
      return;
    }
    _pollingConnections = true;
    try {
      final connections = await _listConnections(_hostExecutable);
      if (generation != _generation) return;
      final target = connections.where(
        (connection) =>
            connection.authorized &&
            !connection.disconnected &&
            (connection.portForward == '127.0.0.1:$remotePort' ||
                connection.portForward == 'localhost:$remotePort' ||
                connection.portForward ==
                    '127.0.0.1:${RustDeskHarnessShareService.simulatorRemotePort}' ||
                connection.portForward ==
                    'localhost:${RustDeskHarnessShareService.simulatorRemotePort}' ||
                connection.portForward == '127.0.0.1:22' ||
                connection.portForward == 'localhost:22'),
      );
      if (target.isEmpty) {
        markDisconnected();
      } else {
        markConnected(target.first.peerId);
      }
    } on Object {
      // A transient control-query failure must not revoke a healthy endpoint.
      // The next bounded poll reconciles the real connection state.
    } finally {
      _pollingConnections = false;
    }
  }
}
