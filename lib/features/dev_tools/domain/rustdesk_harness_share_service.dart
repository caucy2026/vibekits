import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  });
  final int connectionId;
  final String peerId;
  final String peerName;
  final bool authorized;
  final bool disconnected;
}

typedef RustDeskProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef RustDeskProcessLauncher =
    Future<void> Function(String executable, List<String> arguments);
typedef RustDeskManagedProcessLauncher =
    Future<RustDeskManagedProcess> Function(
      String executable,
      List<String> arguments,
    );

abstract interface class RustDeskManagedProcess {
  Future<int> get exitCode;
  bool terminate();
}

final class _IoRustDeskManagedProcess implements RustDeskManagedProcess {
  const _IoRustDeskManagedProcess(this.process);
  final Process process;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  bool terminate() => process.kill(ProcessSignal.sigterm);
}

/// Owns exactly one native RustDesk port-forward process.
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
    required RustDeskManagedProcess process,
  }) : _process = process;

  final String routingId;
  final int localPort;
  final int remotePort;
  final bool forceRelay;
  final RustDeskManagedProcess _process;
  bool _closed = false;

  bool get closed => _closed;
  Future<int> get exitCode => _process.exitCode;

  Future<void> close({Duration timeout = const Duration(seconds: 3)}) async {
    if (_closed) return;
    _closed = true;
    _process.terminate();
    try {
      await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      // The native process owns no user data. If SIGTERM is delayed, report
      // the lease closed and let the OS reap it; callers must not reuse it.
    }
  }
}

/// Integrates with the official RustDesk client without handling passwords.
///
/// `hbbr` is not a generic application-data relay. The official RustDesk host
/// streams the Vibekits desktop through hbbs/hbbr and the official web client
/// provides remote interaction. This adapter only discovers/starts that host.
abstract final class RustDeskHarnessShareService {
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
    final List<String> candidates = <String>[];
    if (configured.trim().isNotEmpty) candidates.add(configured.trim());
    if (Platform.isWindows) {
      for (final String? root in <String?>[
        Platform.environment['ProgramFiles'],
        Platform.environment['ProgramFiles(x86)'],
        Platform.environment['LOCALAPPDATA'],
      ]) {
        if (root == null || root.trim().isEmpty) continue;
        candidates.add(
          '$root${Platform.pathSeparator}RustDesk${Platform.pathSeparator}RustDesk.exe',
        );
      }
    } else if (Platform.isMacOS) {
      candidates.add('/Applications/KEMI远程办公.app/Contents/MacOS/KEMI远程办公');
      candidates.add('/Applications/RustDesk.app/Contents/MacOS/RustDesk');
    }
    return candidates.toSet().toList(growable: false);
  }

  static Future<RustDeskHostInfo> inspect({
    String configuredExecutable = '',
    RustDeskProcessRunner? runner,
  }) async {
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
        message: '未找到兼容的 Harness 中继引擎，请在设置中指定路径',
      );
    }
    try {
      final ProcessResult result = await (runner ?? Process.run)(
        executable,
        const <String>['--vibekits-harness-status'],
      ).timeout(const Duration(seconds: 8));
      final Map<String, Object?> payload = _decodeStatus(result);
      final String id = payload['routingId']?.toString() ?? '';
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
          'offline' => 'Harness 中继服务离线',
          'invalid_routing_id' => '中继服务器返回的 Harness ID 无效',
          _ => 'Harness 中继状态不可用：$state',
        },
      );
    } on Object catch (error) {
      return RustDeskHostInfo(
        executable: executable,
        id: '',
        available: true,
        message: '客户端不支持独立 Harness 中继状态，需更新配套网络引擎：$error',
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
    if (executable.trim().isEmpty || !File(executable).existsSync()) {
      throw StateError('KEMI远程办公客户端不存在');
    }
    await (launcher ?? _launchDetached)(executable, const <String>[
      '--vibekits-harness-service',
    ]);
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
    final arguments = <String>[
      '--vibekits-harness-tunnel',
      routingId,
      '$localPort',
      '127.0.0.1',
      '$remotePort',
      if (forceRelay) '--relay',
    ];
    final process = await (launcher ?? _launchManaged)(executable, arguments);
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
    if (executable.trim().isEmpty || !File(executable).existsSync()) {
      throw StateError('Harness 中继引擎不存在');
    }
    if (!RegExp(r'^[1-9][0-9]{5,15}$').hasMatch(routingId)) {
      throw const FormatException('Harness 远端 ID 必须是 6～16 位数字');
    }
    if (localPort < 1024 || localPort > 65535) {
      throw const FormatException('Harness 本地转发端口无效');
    }
    if (remotePort < 1024 || remotePort > 65535) {
      throw const FormatException('Harness 远端服务端口无效');
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
    final ProcessResult result = await (runner ?? Process.run)(
      executable,
      const <String>['--vibekits-harness-connections'],
    ).timeout(const Duration(seconds: 5));
    final Map<String, Object?> payload = _decodeControl(result);
    final Object? rows = payload['connections'];
    if (rows is! List) {
      throw const FormatException('Harness 授权列表格式不兼容');
    }
    return List<RustDeskHarnessIncomingConnection>.unmodifiable(
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
        );
      }),
    );
  }

  static Future<void> decideConnection(
    String executable, {
    required int connectionId,
    required bool allow,
    RustDeskProcessRunner? runner,
  }) async {
    final ProcessResult result =
        await (runner ?? Process.run)(executable, <String>[
          allow ? '--vibekits-harness-authorize' : '--vibekits-harness-reject',
          '$connectionId',
        ]).timeout(const Duration(seconds: 5));
    final Map<String, Object?> payload = _decodeControl(result);
    if (payload['ok'] != true) {
      throw StateError(payload['code']?.toString() ?? 'Harness 授权操作失败');
    }
  }

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
    // The native carrier may emit diagnostics, but the product UI consumes
    // structured link state. Drain both streams so a full pipe cannot stall it.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return _IoRustDeskManagedProcess(process);
  }
}
