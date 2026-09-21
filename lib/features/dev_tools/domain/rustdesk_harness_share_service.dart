import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'harness_simulator_access_settings.dart';

class RustDeskHostInfo {
  const RustDeskHostInfo({
    required this.executable,
    required this.id,
    required this.available,
    required this.message,
    this.callable = false,
    this.rendezvousOnline = false,
    this.registrationKeyConfirmed = false,
    this.state = 'unavailable',
  });

  final String executable;
  final String id;
  final bool available;
  final String message;
  final bool callable;
  final bool rendezvousOnline;
  final bool registrationKeyConfirmed;
  final String state;
}

class RustDeskHarnessIncomingConnection {
  const RustDeskHarnessIncomingConnection({
    required this.connectionId,
    required this.peerId,
    required this.peerName,
    required this.authorized,
    required this.disconnected,
    this.portForward = '',
  });
  final int connectionId;
  final String peerId;
  final String peerName;
  final bool authorized;
  final bool disconnected;
  final String portForward;
}

typedef RustDeskProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef RustDeskProcessLauncher =
    Future<void> Function(String executable, List<String> arguments);
typedef RustDeskStaleRelayTerminator = Future<void> Function(String executable);
typedef RustDeskManagedProcessLauncher =
    Future<RustDeskManagedProcess> Function(
      String executable,
      List<String> arguments,
    );

abstract interface class RustDeskManagedProcess {
  Future<int> get exitCode;
  Future<void> waitUntilListening({Duration timeout});
  Future<void> waitUntilReady({Duration timeout});
  bool terminate();
  bool forceTerminate();
}

final class _IoRustDeskManagedProcess implements RustDeskManagedProcess {
  _IoRustDeskManagedProcess(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleOutput, onDone: _handleOutputDone);
    process.stderr.transform(utf8.decoder).listen((String chunk) {
      if (_stderr.length < 4096) {
        final int remaining = 4096 - _stderr.length;
        _stderr += chunk.length <= remaining
            ? chunk
            : chunk.substring(0, remaining);
      }
    });
    unawaited(
      process.exitCode.then((int code) {
        final StateError error = StateError(
          'HARNESS_TRANSPORT_EXITED: exit=$code'
          '${_stderr.trim().isEmpty ? '' : ', ${_stderr.trim()}'}',
        );
        if (!_listening.isCompleted) _listening.completeError(error);
        if (!_ready.isCompleted) _ready.completeError(error);
      }),
    );
  }
  final Process process;
  final Completer<void> _listening = Completer<void>();
  final Completer<void> _ready = Completer<void>();
  String _stderr = '';

  void _handleOutput(String line) {
    if (_ready.isCompleted || line.trim().isEmpty) return;
    try {
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map || decoded['ok'] is! bool) return;
      if (decoded['ok'] == true && decoded['state'] == 'listener_ready') {
        if (!_listening.isCompleted) _listening.complete();
        return;
      }
      if (decoded['ok'] == true && decoded['state'] == 'transport_connected') {
        if (!_listening.isCompleted) _listening.complete();
        _ready.complete();
        return;
      }
      final String code = decoded['code']?.toString() ?? 'invalid_state';
      final String message = decoded['message']?.toString() ?? line;
      final StateError error = StateError('HARNESS_TRANSPORT_$code: $message');
      if (!_listening.isCompleted) _listening.completeError(error);
      if (!_ready.isCompleted) _ready.completeError(error);
    } on FormatException {
      // Native logging may share stdout in older builds. Ignore non-JSON lines
      // but never promote them to a connected state.
    }
  }

  void _handleOutputDone() {
    final StateError error = StateError(
      'HARNESS_TRANSPORT_OUTPUT_CLOSED'
      '${_stderr.trim().isEmpty ? '' : ': ${_stderr.trim()}'}',
    );
    if (!_listening.isCompleted) _listening.completeError(error);
    if (!_ready.isCompleted) _ready.completeError(error);
  }

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  Future<void> waitUntilListening({
    Duration timeout = const Duration(seconds: 5),
  }) => _listening.future.timeout(timeout);

  @override
  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
  }) => _ready.future.timeout(timeout);

  @override
  bool terminate() => process.kill(ProcessSignal.sigterm);

  @override
  bool forceTerminate() => process.kill(ProcessSignal.sigkill);
}

/// Owns exactly one native carrier port-forward process.
///
/// Closing this lease is the authoritative disconnect operation. Merely
/// hiding the remote workspace must never leave a relay running in the
/// background.
final class RustDeskHarnessTunnelLease {
  RustDeskHarnessTunnelLease._({
    required this.routingId,
    required this.localPort,
    required this.remotePort,
    required this.forceRelay,
    RustDeskManagedProcess? process,
    Future<void> Function()? nativeClose,
  }) : _process = process,
       _nativeClose = nativeClose;

  final String routingId;
  final int localPort;
  final int remotePort;
  final bool forceRelay;
  final RustDeskManagedProcess? _process;
  final Future<void> Function()? _nativeClose;
  bool _closed = false;

  bool get closed => _closed;
  Future<int> get exitCode => _process?.exitCode ?? Future<int>.value(0);

  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final process = _process;
    if (process != null) await process.waitUntilReady(timeout: timeout);
  }

  Future<void> close({Duration timeout = const Duration(seconds: 3)}) async {
    if (_closed) return;
    _closed = true;
    if (_nativeClose != null) {
      await _nativeClose();
      return;
    }
    final process = _process;
    if (process == null) return;
    process.terminate();
    try {
      await process.exitCode.timeout(timeout);
    } on TimeoutException {
      // A stale tunnel is still a live remote connection. Never report the
      // lease closed while leaving that process behind: escalate from the
      // cooperative signal to an unconditional process termination.
      process.forceTerminate();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        throw StateError('HARNESS_TUNNEL_PROCESS_DID_NOT_EXIT');
      }
    }
  }
}

/// Controls VibeKits' source-built RustDesk carrier without desktop sharing.
///
/// The embedded helper reuses only rendezvous, hole-punching and hbbr byte
/// transport. VibeKits' own authenticated protocol defines every payload; no
/// separately installed RustDesk/KEMI app or plugin is a runtime dependency.
abstract final class RustDeskHarnessShareService {
  static const int simulatorRemotePort = 32147;
  static const int simulatorControlRemotePort = 32148;
  static const int simulatorSshRemotePort = 22;
  static const String _currentProtocolCommand = '--vibekits-harness-protocol';
  static const String _currentProtocolCode = 'protocol_v2';
  static const MethodChannel _androidRelay = MethodChannel(
    'vibekits/harness-relay',
  );

  static Future<String> discoverWebClientUrl({File? configFile}) async {
    final List<File> candidates = configFile != null
        ? <File>[configFile]
        : <File>[
            if (Platform.isWindows)
              File(
                '${Platform.environment['APPDATA'] ?? ''}'
                '${Platform.pathSeparator}RustDesk${Platform.pathSeparator}config'
                '${Platform.pathSeparator}RustDesk2.toml',
              ),
            if (Platform.isMacOS)
              File(
                '${Platform.environment['HOME'] ?? ''}'
                '${Platform.pathSeparator}Library${Platform.pathSeparator}Preferences'
                '${Platform.pathSeparator}com.carriez.RustDesk${Platform.pathSeparator}RustDesk2.toml',
              ),
          ];
    for (final File file in candidates) {
      if (!await file.exists() || await file.length() > 1024 * 1024) continue;
      final List<String> lines = await file.readAsLines();
      for (final String key in <String>[
        'custom-rendezvous-server',
        'rendezvous_server',
      ]) {
        final RegExp expression = RegExp(
          '^${RegExp.escape(key)}\\s*=\\s*[\\x27\\x22]'
          '([^\\x27\\x22]+)[\\x27\\x22]\\s*\$',
        );
        for (final String line in lines) {
          final String? raw = expression.firstMatch(line.trim())?.group(1);
          if (raw == null) continue;
          final String host = raw.trim().replaceFirst(RegExp(r':\d+$'), '');
          if (RegExp(r'^[A-Za-z0-9.-]{1,253}$').hasMatch(host)) {
            return 'https://$host/web';
          }
        }
      }
    }
    return '';
  }

  static List<String> candidateExecutables({String configured = ''}) {
    final String siblingName = Platform.isWindows
        ? 'vibekits-harness-relay.exe'
        : 'vibekits-harness-relay';
    final List<String> candidates = <String>[
      if (Platform.isMacOS)
        '${File(Platform.resolvedExecutable).parent.parent.path}'
            '/Helpers/VibeKitsHarnessRelay.app/Contents/MacOS/$siblingName',
      '${File(Platform.resolvedExecutable).parent.path}'
          '${Platform.pathSeparator}$siblingName',
    ];
    final String configuredPath = configured.trim();
    if (configuredPath.isNotEmpty) {
      final String basename = File(configuredPath).uri.pathSegments.last;
      if (basename == siblingName) {
        candidates.add(configuredPath);
      }
    }
    return candidates.toSet().toList(growable: false);
  }

  static Future<RustDeskHostInfo> inspect({
    String configuredExecutable = '',
    RustDeskProcessRunner? runner,
  }) async {
    if (Platform.isAndroid) {
      try {
        final payload = await _androidJson('inspect');
        final id = payload['routingId']?.toString() ?? '';
        final state = payload['state']?.toString() ?? 'invalid_response';
        return RustDeskHostInfo(
          executable: 'android://vibekits-harness-relay',
          id: id,
          available: true,
          callable: payload['callable'] == true,
          rendezvousOnline: payload['rendezvousOnline'] == true,
          registrationKeyConfirmed: payload['registrationKeyConfirmed'] == true,
          state: state,
          message: state == 'registered'
              ? 'Harness 本机 ID：$id（中继服务已确认，可连接）'
              : 'Harness 中继状态：$state',
        );
      } on Object catch (error) {
        return RustDeskHostInfo(
          executable: '',
          id: '',
          available: false,
          message: 'VibeKits 内置 Harness 传输引擎不可用：$error',
        );
      }
    }
    final String executable =
        candidateExecutables(
          configured: configuredExecutable,
        ).where((String path) => File(path).existsSync()).firstOrNull ??
        '';
    if (executable.isEmpty) {
      return const RustDeskHostInfo(
        executable: '',
        id: '',
        available: false,
        message: '未找到 VibeKits 包内 Harness 传输引擎，请重新安装完整应用',
      );
    }
    try {
      final ProcessResult result = await _runControlCommand(
        executable,
        const <String>['--vibekits-harness-status'],
        timeout: const Duration(seconds: 8),
        runner: runner,
      );
      final Map<String, Object?> payload = _decodeStatus(result);
      String id = payload['routingId']?.toString() ?? '';
      if (id.isEmpty) {
        // The assistance service is deliberately off by default, but users
        // must still be able to read and share this installation's stable ID.
        // Reading the persisted ID does not start a listener or make the host
        // callable; those gates remain controlled by [launchHost].
        try {
          final ProcessResult idResult = await _runControlCommand(
            executable,
            const <String>['--vibekits-harness-get-id'],
            timeout: const Duration(seconds: 5),
            runner: runner,
          );
          final String candidate = idResult.stdout.toString().trim();
          if (idResult.exitCode == 0 &&
              RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(candidate)) {
            id = candidate;
          }
        } on Object {
          // Status remains authoritative. Failure to read a dormant identity
          // must not turn an offline host into a callable one.
        }
      }
      final bool online = payload['rendezvousOnline'] == true;
      final bool confirmed = payload['registrationKeyConfirmed'] == true;
      final bool callable = payload['callable'] == true;
      final String state = payload['state']?.toString() ?? 'invalid_response';
      return RustDeskHostInfo(
        executable: executable,
        id: id,
        available: true,
        callable: callable,
        rendezvousOnline: online,
        registrationKeyConfirmed: confirmed,
        state: state,
        message: switch (state) {
          'registered' => 'Harness 本机 ID：$id（中继服务已确认，可连接）',
          'registration_pending' => 'Harness ID 正在向中继服务器注册',
          'offline' =>
            id.isEmpty
                ? 'Harness 中继服务离线；暂未读到本机 ID'
                : 'Harness 本机 ID：$id（远程协助未打开）',
          'invalid_routing_id' => '中继服务器返回的 Harness ID 无效',
          _ => 'Harness 中继状态不可用：$state',
        },
      );
    } on Object catch (error) {
      return RustDeskHostInfo(
        executable: executable,
        id: '',
        available: true,
        message: '包内 Harness 传输引擎响应不兼容，请重新安装当前版本：$error',
      );
    }
  }

  static Map<String, Object?> _decodeStatus(ProcessResult result) {
    if (result.exitCode != 0) {
      throw StateError('状态命令退出码 ${result.exitCode}');
    }
    final String output = result.stdout.toString().trim();
    final Object? decoded = jsonDecode(output);
    if (decoded is! Map<String, Object?> || decoded['state'] is! String) {
      throw const FormatException('Harness 中继状态响应格式不兼容');
    }
    return decoded;
  }

  static Future<void> launchHost(
    String executable, {
    RustDeskProcessLauncher? launcher,
  }) async {
    if (Platform.isAndroid) {
      await _androidJson('inspect');
      return;
    }
    _validateRelayExecutable(executable);
    await (launcher ?? _launchDetached)(executable, const <String>[
      '--vibekits-harness-service',
    ]);
  }

  /// Makes the native carrier genuinely callable, rather than treating an
  /// installed executable or an allocated routing ID as a live endpoint.
  static Future<RustDeskHostInfo> ensureHostAvailable({
    String configuredExecutable = '',
    RustDeskProcessRunner? runner,
    RustDeskProcessLauncher? launcher,
    RustDeskStaleRelayTerminator? staleRelayTerminator,
    Duration timeout = const Duration(seconds: 8),
    bool? enforceCurrentProtocol,
  }) async {
    final bool shouldEnforceCurrentProtocol =
        enforceCurrentProtocol ?? Platform.isWindows;
    Future<bool> usable(RustDeskHostInfo candidate) async {
      if (!candidate.callable) return false;
      if (!shouldEnforceCurrentProtocol) return true;
      return _supportsCurrentProtocol(candidate.executable, runner: runner);
    }

    RustDeskHostInfo host = await inspect(
      configuredExecutable: configuredExecutable,
      runner: runner,
    );
    if (await usable(host)) return host;
    if (!host.available || host.executable.isEmpty) {
      throw StateError(host.message);
    }
    final bool staleCallable = host.callable;
    if (!staleCallable) {
      await launchHost(host.executable, launcher: launcher);
      final deadline = DateTime.now().add(timeout);
      do {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        host = await inspect(
          configuredExecutable: configuredExecutable,
          runner: runner,
        );
        if (await usable(host)) return host;
      } while (DateTime.now().isBefore(deadline));
    }

    // A detached service from an older App can still own the isolated IPC
    // namespace while reporting offline. Launching another single-instance
    // helper then has no effect. Stop only that VibeKits-owned service through
    // its scoped control command and relaunch the current package's helper.
    Object? gracefulStopError;
    try {
      final stopped = await _runControlCommand(
        host.executable,
        const <String>['--vibekits-harness-stop'],
        timeout: const Duration(seconds: 5),
        runner: runner,
      );
      final stopPayload = _decodeControl(stopped);
      if (stopPayload['ok'] != true) {
        throw StateError(stopPayload['code']?.toString() ?? 'failed');
      }
    } on Object catch (error) {
      gracefulStopError = error;
      final terminate =
          staleRelayTerminator ??
          (Platform.isWindows ? _terminateStaleWindowsRelay : null);
      if (terminate == null) {
        throw TimeoutException(
          'HARNESS_RELAY_NOT_CALLABLE: ${host.state}; takeover=$error',
          timeout,
        );
      }
      await terminate(host.executable);
    }
    await launchHost(host.executable, launcher: launcher);
    final takeoverDeadline = DateTime.now().add(timeout);
    do {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      host = await inspect(
        configuredExecutable: configuredExecutable,
        runner: runner,
      );
      if (await usable(host)) return host;
    } while (DateTime.now().isBefore(takeoverDeadline));
    throw TimeoutException(
      'HARNESS_RELAY_NOT_CALLABLE_AFTER_TAKEOVER: ${host.state}; '
      'gracefulStop=${gracefulStopError ?? 'ok'}',
      timeout,
    );
  }

  static Future<bool> _supportsCurrentProtocol(
    String executable, {
    RustDeskProcessRunner? runner,
  }) async {
    try {
      final ProcessResult result = await _runControlCommand(
        executable,
        const <String>[_currentProtocolCommand],
        timeout: const Duration(seconds: 5),
        runner: runner,
      );
      final Map<String, Object?> payload = _decodeControl(result);
      return payload['ok'] == true &&
          payload['code']?.toString() == _currentProtocolCode;
    } on Object {
      return false;
    }
  }

  static Future<void> _terminateStaleWindowsRelay(String executable) async {
    _validateRelayExecutable(executable);
    final result = await Process.run('taskkill.exe', const <String>[
      '/F',
      '/IM',
      'vibekits-harness-relay.exe',
    ], runInShell: false).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) {
      final output = '${result.stdout}\n${result.stderr}'.trim();
      throw StateError(
        'HARNESS_STALE_RELAY_TERMINATION_FAILED: '
        '${output.isEmpty ? result.exitCode : output}',
      );
    }
    // Give Windows enough time to release the relay's single-instance IPC
    // namespace before launching the current package's executable.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  /// Stops the Android-only independent Harness relay process. Desktop hosts
  /// are process-owned by the signed native client and are not killed through
  /// an unscoped compatibility command.
  static Future<void> stopHost({String configuredExecutable = ''}) async {
    if (Platform.isAndroid) {
      final response = await _androidJson('stop');
      if (response['ok'] != true) throw StateError('Harness 中继停止失败');
      return;
    }
    final host = await inspect(configuredExecutable: configuredExecutable);
    if (!host.available || host.executable.isEmpty) return;
    final result = await _runControlCommand(host.executable, const <String>[
      '--vibekits-harness-stop',
    ], timeout: const Duration(seconds: 5));
    final payload = _decodeControl(result);
    if (payload['ok'] != true) {
      throw StateError(payload['code']?.toString() ?? 'Harness 中继停止失败');
    }
  }

  /// Starts an independent Harness byte tunnel through the configured
  /// RustDesk HBBS/HBBR network. The native client first attempts a direct
  /// connection and falls back to hbbr; the Harness protocol and mTLS run
  /// inside this loopback-only carrier.
  static Future<void> launchTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    int remotePort = 32146,
    bool forceRelay = false,
    RustDeskProcessLauncher? launcher,
  }) async {
    _validateTunnel(
      executable,
      routingId: routingId,
      localPort: localPort,
      remotePort: remotePort,
    );
    if (Platform.isAndroid) {
      final response = await _androidJson('openTunnel', <String, Object?>{
        'routingId': routingId,
        'localPort': localPort,
        'remotePort': remotePort,
        'forceRelay': forceRelay,
      });
      if (response['ok'] != true) {
        throw StateError(response['code']?.toString() ?? 'Harness 隧道启动失败');
      }
      return;
    }
    await (launcher ?? _launchDetached)(executable, <String>[
      '--vibekits-harness-tunnel',
      routingId,
      '$localPort',
      '127.0.0.1',
      '$remotePort',
      if (forceRelay) '--relay',
    ]);
  }

  /// Starts a tunnel whose lifetime is explicitly owned by the caller.
  /// This is used by the interactive remote workspace; [launchTunnel] is
  /// retained for compatibility with legacy fire-and-forget callers.
  static Future<RustDeskHarnessTunnelLease> openTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    int remotePort = 32146,
    bool forceRelay = false,
    RustDeskManagedProcessLauncher? launcher,
  }) async {
    _validateTunnel(
      executable,
      routingId: routingId,
      localPort: localPort,
      remotePort: remotePort,
    );
    if (Platform.isAndroid) {
      final response = await _androidJson('openTunnel', <String, Object?>{
        'routingId': routingId,
        'localPort': localPort,
        'remotePort': remotePort,
        'forceRelay': forceRelay,
      });
      if (response['ok'] != true) {
        throw StateError(response['code']?.toString() ?? 'Harness 隧道启动失败');
      }
      return RustDeskHarnessTunnelLease._(
        routingId: routingId,
        localPort: localPort,
        remotePort: remotePort,
        forceRelay: forceRelay,
        nativeClose: () async {
          final result = await _androidRelay.invokeMapMethod<String, Object?>(
            'closeTunnel',
            <String, Object?>{'localPort': localPort},
          );
          if (result?['ok'] != true) {
            throw StateError('Harness 隧道关闭失败');
          }
        },
      );
    }
    final arguments = <String>[
      '--vibekits-harness-tunnel',
      routingId,
      '$localPort',
      '127.0.0.1',
      '$remotePort',
      if (forceRelay) '--relay',
    ];
    final process = await (launcher ?? _launchManaged)(executable, arguments);
    try {
      await process.waitUntilListening();
    } on Object {
      process.terminate();
      rethrow;
    }
    return RustDeskHarnessTunnelLease._(
      routingId: routingId,
      localPort: localPort,
      remotePort: remotePort,
      forceRelay: forceRelay,
      process: process,
    );
  }

  static void _validateTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    required int remotePort,
  }) {
    if (!Platform.isAndroid) _validateRelayExecutable(executable);
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(routingId)) {
      throw const FormatException('Harness 远端 ID 必须是 6～16 位数字');
    }
    if (localPort < 1024 || localPort > 65535) {
      throw const FormatException('Harness 本地转发端口无效');
    }
    if ((remotePort < 1024 && remotePort != simulatorSshRemotePort) ||
        remotePort > 65535) {
      throw const FormatException('Harness 远端服务端口无效');
    }
  }

  /// Refuse a desktop RustDesk/KEMI executable even if a stale preference or
  /// caller passes one explicitly. Harness transport is a dedicated headless
  /// companion binary; accepting a general desktop client here can open a
  /// remote-desktop window when an argument is missing or unsupported.
  static void _validateRelayExecutable(String executable) {
    final File file = File(executable.trim());
    final String expectedName = Platform.isWindows
        ? 'vibekits-harness-relay.exe'
        : 'vibekits-harness-relay';
    final String actualName = file.uri.pathSegments.isEmpty
        ? ''
        : file.uri.pathSegments.last;
    if (!file.existsSync() || actualName != expectedName) {
      throw StateError(
        'HARNESS_HEADLESS_RELAY_REQUIRED: only $expectedName is allowed',
      );
    }
  }

  static Future<int> allocateTunnelPort() async {
    final ServerSocket reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final int port = reservation.port;
    await reservation.close();
    return port;
  }

  static Future<List<RustDeskHarnessIncomingConnection>> connections(
    String executable, {
    RustDeskProcessRunner? runner,
  }) async {
    if (Platform.isAndroid) {
      final response = await _androidRelay.invokeMapMethod<String, Object?>(
        'connections',
      );
      final raw = response?['json'];
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! List) {
        throw const FormatException('Harness 授权列表格式不兼容');
      }
      return _decodeConnections(decoded);
    }
    final ProcessResult result = await _runControlCommand(
      executable,
      const <String>['--vibekits-harness-connections'],
      timeout: const Duration(seconds: 5),
      runner: runner,
    );
    final Map<String, Object?> payload = _decodeControl(result);
    final Object? rows = payload['connections'];
    if (rows is! List) {
      throw const FormatException('Harness 授权列表格式不兼容');
    }
    return _decodeConnections(rows);
  }

  static List<RustDeskHarnessIncomingConnection> _decodeConnections(
    List<dynamic> rows,
  ) => List<RustDeskHarnessIncomingConnection>.unmodifiable(
    rows.map((Object? value) {
      if (value is! Map<String, dynamic> ||
          value['connectionId'] is! int ||
          value['peerId'] is! String ||
          value['peerName'] is! String ||
          value['authorized'] is! bool ||
          value['disconnected'] is! bool) {
        throw const FormatException('Harness 授权记录格式不兼容');
      }
      return RustDeskHarnessIncomingConnection(
        connectionId: value['connectionId'] as int,
        peerId: value['peerId'] as String,
        peerName: value['peerName'] as String,
        authorized: value['authorized'] as bool,
        disconnected: value['disconnected'] as bool,
        portForward: value['portForward']?.toString() ?? '',
      );
    }),
  );

  static Future<void> decideConnection(
    String executable, {
    required int connectionId,
    required bool allow,
    RustDeskProcessRunner? runner,
  }) async {
    if (Platform.isAndroid) {
      final response = await _androidRelay.invokeMapMethod<String, Object?>(
        allow ? 'authorize' : 'reject',
        <String, Object?>{'connectionId': connectionId},
      );
      if (response?['ok'] != true) throw StateError('Harness 授权操作失败');
      return;
    }
    final ProcessResult result = await _runControlCommand(
      executable,
      <String>[
        allow ? '--vibekits-harness-authorize' : '--vibekits-harness-reject',
        '$connectionId',
      ],
      timeout: const Duration(seconds: 5),
      runner: runner,
    );
    final Map<String, Object?> payload = _decodeControl(result);
    if (payload['ok'] != true) {
      throw StateError(payload['code']?.toString() ?? 'Harness 授权操作失败');
    }
  }

  /// Enables or revokes the native gate for the one fixed simulator MCP
  /// endpoint. This never changes desktop, terminal, file-transfer or generic
  /// tunnel permissions.
  static Future<void> setSimulatorAccess(
    String executable, {
    required bool enabled,
    RustDeskProcessRunner? runner,
  }) async {
    if (Platform.isAndroid) {
      throw UnsupportedError('PAD 只作为协助端，不开放本机仿真机访问');
    }
    final ProcessResult result = await _runControlCommand(
      executable,
      <String>['--vibekits-harness-simulator-access', enabled ? '1' : '0'],
      timeout: const Duration(seconds: 5),
      runner: runner,
    );
    final Map<String, Object?> payload = _decodeControl(result);
    if (payload['ok'] != true) {
      throw StateError(payload['code']?.toString() ?? '仿真机权限更新失败');
    }
  }

  /// Enables or revokes the native byte-tunnel gate for the fixed pairing
  /// and authenticated Harness session endpoints. This is deliberately
  /// independent from simulator access and never enables arbitrary tunnels.
  static Future<void> setRemoteAssistanceAccess(
    String executable, {
    required bool enabled,
    RustDeskProcessRunner? runner,
    RustDeskProcessLauncher? launcher,
  }) async {
    if (Platform.isAndroid) {
      throw UnsupportedError('PAD 只作为协助端，不开放本机被协助服务');
    }
    Future<Map<String, Object?>> updateGate() async {
      final ProcessResult result = await _runControlCommand(
        executable,
        <String>[
          '--vibekits-harness-remote-assistance-access',
          enabled ? '1' : '0',
        ],
        timeout: const Duration(seconds: 5),
        runner: runner,
      );
      if (result.exitCode != 0) {
        final String output = '${result.stdout}\n${result.stderr}'.trim();
        if (output.contains('unsupported VibeKits Harness relay command')) {
          return const <String, Object?>{
            'ok': false,
            'state': 'legacy',
            'code': 'control_response_invalid',
          };
        }
      }
      return _decodeControl(result);
    }

    Map<String, Object?> payload = await updateGate();
    if (payload['ok'] == true) return;
    final String code = payload['code']?.toString() ?? '';
    const staleServiceCodes = <String>{
      'control_response_invalid',
      'control_send_failed',
    };
    if (!staleServiceCodes.contains(code)) {
      throw StateError(code.isEmpty ? '远程协助权限更新失败' : code);
    }

    // An App update does not replace an already-running detached relay. Old
    // services do not understand the new remote-assistance gate and would
    // otherwise keep every pairing attempt behind the generic tunnel policy.
    // Disabling is already fail-closed on those versions, so avoid restarting
    // a relay that may still serve an explicitly enabled simulator endpoint.
    if (!enabled) return;

    final bool restoreSimulator = HarnessSimulatorAccessSettings.enabled;
    final ProcessResult stopped = await _runControlCommand(
      executable,
      const <String>['--vibekits-harness-stop'],
      timeout: const Duration(seconds: 5),
      runner: runner,
    );
    final Map<String, Object?> stopPayload = _decodeControl(stopped);
    if (stopPayload['ok'] != true) {
      throw StateError(stopPayload['code']?.toString() ?? '旧版 Harness 中继停止失败');
    }
    await launchHost(executable, launcher: launcher);

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    Object? lastError;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        payload = await updateGate();
        if (payload['ok'] == true) {
          if (restoreSimulator) {
            await setSimulatorAccess(executable, enabled: true, runner: runner);
          }
          return;
        }
        lastError = payload['code'];
      } on Object catch (error) {
        lastError = error;
      }
    } while (DateTime.now().isBefore(deadline));
    throw TimeoutException(
      'HARNESS_RELAY_UPGRADE_TIMEOUT: ${lastError ?? code}',
      const Duration(seconds: 10),
    );
  }

  static Future<RustDeskHarnessTunnelLease> openSimulatorTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    bool forceRelay = false,
    RustDeskManagedProcessLauncher? launcher,
  }) => openTunnel(
    executable,
    routingId: routingId,
    localPort: localPort,
    remotePort: simulatorRemotePort,
    forceRelay: forceRelay,
    launcher: launcher,
  );

  static Future<RustDeskHarnessTunnelLease> openSimulatorControlTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    bool forceRelay = false,
    RustDeskManagedProcessLauncher? launcher,
  }) => openTunnel(
    executable,
    routingId: routingId,
    localPort: localPort,
    remotePort: simulatorControlRemotePort,
    forceRelay: forceRelay,
    launcher: launcher,
  );

  static Future<RustDeskHarnessTunnelLease> openSimulatorSshTunnel(
    String executable, {
    required String routingId,
    required int localPort,
    bool forceRelay = false,
    RustDeskManagedProcessLauncher? launcher,
  }) => openTunnel(
    executable,
    routingId: routingId,
    localPort: localPort,
    remotePort: simulatorSshRemotePort,
    forceRelay: forceRelay,
    launcher: launcher,
  );

  static Map<String, Object?> _decodeControl(ProcessResult result) {
    if (result.exitCode != 0) {
      throw StateError('Harness 授权命令退出码 ${result.exitCode}');
    }
    final Object? decoded = jsonDecode(result.stdout.toString().trim());
    if (decoded is! Map<String, Object?> ||
        decoded['ok'] is! bool ||
        decoded['state'] is! String) {
      throw const FormatException('Harness 授权响应格式不兼容');
    }
    return decoded;
  }

  static Future<Map<String, Object?>> _androidJson(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final response = await _androidRelay.invokeMapMethod<String, Object?>(
      method,
      arguments,
    );
    final raw = response?['json'];
    final decoded = raw is String ? jsonDecode(raw) : null;
    if (decoded is! Map) {
      throw const FormatException('Harness Android 中继响应格式不兼容');
    }
    return decoded.cast<String, Object?>();
  }

  /// Runs a short-lived native control command and owns its complete lifetime.
  ///
  /// `Future.timeout` on `Process.run` only stops waiting; it does not terminate
  /// the child process. An incompatible desktop client could therefore leave a
  /// new GUI/control process behind on every two-second status refresh. The
  /// production path starts the child explicitly and terminates it on timeout.
  static Future<ProcessResult> _runControlCommand(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    RustDeskProcessRunner? runner,
  }) async {
    if (runner != null) {
      return runner(executable, arguments).timeout(timeout);
    }
    final Process process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final Future<String> stdout = process.stdout.transform(utf8.decoder).join();
    final Future<String> stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final int exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      throw TimeoutException(
        'Harness native control command timed out',
        timeout,
      );
    }
  }

  static Uri validateWebClientUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('KEMI远程办公网页端地址必须是不含账号信息的 HTTP/HTTPS URL');
    }
    return uri;
  }

  static Future<void> openWebClient(
    String value, {
    RustDeskProcessLauncher? launcher,
  }) async {
    final Uri uri = validateWebClientUrl(value);
    if (Platform.isWindows) {
      await (launcher ?? _launchDetached)('explorer.exe', <String>[
        uri.toString(),
      ]);
    } else if (Platform.isMacOS) {
      await (launcher ?? _launchDetached)('/usr/bin/open', <String>[
        uri.toString(),
      ]);
    } else {
      await (launcher ?? _launchDetached)('xdg-open', <String>[uri.toString()]);
    }
  }

  static Future<void> _launchDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }

  static Future<RustDeskManagedProcess> _launchManaged(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    return _IoRustDeskManagedProcess(process);
  }
}
